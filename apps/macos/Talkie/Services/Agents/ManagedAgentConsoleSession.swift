//
//  ManagedAgentConsoleSession.swift
//  Talkie
//
//  Live managed console session backed by a native PTY process.
//

import AppKit
import Foundation
import Observation
import TalkieKit

private let sessionLog = Log(.ui)

@MainActor
@Observable
final class ManagedAgentConsoleSession: Identifiable {
    private enum TranscriptBuffer {
        static let maxLength = 600_000
        static let trimTargetLength = 450_000
    }

    enum Status: Equatable {
        case launching
        case running
        case exited(Int32)
        case failed(String)
    }

    protocol Listener: AnyObject {
        func consoleSession(_ session: ManagedAgentConsoleSession, didResetTranscript transcript: Data)
        func consoleSession(_ session: ManagedAgentConsoleSession, didReceiveOutput chunk: Data)
    }

    let id = UUID()
    let profile: ManagedAgentConsoleProfile
    let workspace: ManagedAgentWorkspace
    let prompt: String
    let notes: String
    let createdAt: Date
    let prefersConsoleTmux: Bool

    var status: Status = .launching
    var transcriptData: Data = .init()

    @ObservationIgnored private let process = ManagedAgentPTYProcess()
    @ObservationIgnored private weak var listener: (any Listener)?
    @ObservationIgnored private var initialPromptTask: Task<Void, Never>?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var didSendInitialPrompt = false
    @ObservationIgnored private var launchMode: AgentHarnessProfile.LaunchSpec.SessionMode = .ephemeral
    @ObservationIgnored private var shouldSendInitialPrompt = false
    @ObservationIgnored private var latestTerminalSize: ManagedAgentPTYProcess.Size = .default

    init(
        profile: ManagedAgentConsoleProfile,
        workspace: ManagedAgentWorkspace,
        prompt: String,
        notes: String,
        prefersConsoleTmux: Bool = false,
        createdAt: Date = Date()
    ) {
        self.profile = profile
        self.workspace = workspace
        self.prompt = prompt
        self.notes = notes
        self.prefersConsoleTmux = prefersConsoleTmux
        self.createdAt = createdAt
        ManagedAgentConsoleSessionRegistry.shared.register(self)
    }

    deinit {
        initialPromptTask?.cancel()
        launchTask?.cancel()
        ManagedAgentConsoleSessionRegistry.shared.unregister(self)
    }

    var title: String {
        "\(profile.title) \(createdAt.formatted(date: .omitted, time: .shortened))"
    }

    var statusLabel: String {
        switch status {
        case .launching:
            "Launching"
        case .running:
            "Running"
        case .exited(let code):
            code == 0 ? "Exited" : "Exited \(code)"
        case .failed:
            "Failed"
        }
    }

    var detailLine: String {
        switch status {
        case .launching:
            "Preparing agent console in \(workspace.rootURL.lastPathComponent)"
        case .running:
            workspace.rootURL.path
        case .exited(let code):
            "Session exited with status \(code)"
        case .failed(let message):
            message
        }
    }

    var isRunning: Bool {
        if case .running = status {
            true
        } else {
            false
        }
    }

    var keepsSessionAliveOnDetach: Bool {
        launchMode.keepsSessionAliveOnDetach
    }

    func start() {
        status = .launching
        initialPromptTask?.cancel()
        launchTask?.cancel()
        didSendInitialPrompt = false

        let sessionID = id
        let profileID = profile.id
        let requestedHarness = profile.harness
        let workspaceURL = workspace.rootURL
        let preferredModel = profile.preferredModel
        let preferTmux = prefersConsoleTmux

        launchTask = Task.detached(priority: .userInitiated) {
            do {
                let resolution = try AgentConsoleCompanion.resolveConsoleLaunch(
                    profileID: profileID,
                    requestedHarness: requestedHarness,
                    workspaceURL: workspaceURL,
                    preferredModel: preferredModel,
                    preferTmux: preferTmux
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let session = ManagedAgentConsoleSessionRegistry.shared.session(for: sessionID) else { return }
                    session.startResolvedLaunch(resolution)
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let session = ManagedAgentConsoleSessionRegistry.shared.session(for: sessionID) else { return }
                    session.handleLaunchFailure(error)
                }
            }
        }
    }

    func startWithLaunchSpec(_ launchSpec: AgentHarnessProfile.LaunchSpec, reason: String = "Tab session") {
        status = .launching
        initialPromptTask?.cancel()
        launchTask?.cancel()
        didSendInitialPrompt = false

        do {
            launchMode = launchSpec.sessionMode
            shouldSendInitialPrompt = launchSpec.shouldSendInitialPrompt && profile.autoSendPrompt
            didSendInitialPrompt = false

            process.onOutput = { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.append(data)
                    self.scheduleInitialPromptIfNeeded()
                }
            }

            process.onExit = { [weak self] exitCode in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.initialPromptTask?.cancel()
                    self.status = .exited(exitCode)
                    self.append(Data("\r\n[Talkie] Session exited with status \(exitCode)\r\n".utf8))
                    sessionLog.info("Tab console session exited", detail: "\(self.profile.id) status=\(exitCode)")
                }
            }

            try process.start(spec: launchSpec, initialSize: latestTerminalSize)
            status = .running
            append(Data("[Talkie] \(reason)\r\n".utf8))
            pulseInitialResize()
            sessionLog.info("Tab console session started", detail: "\(profile.id)")
        } catch {
            handleLaunchFailure(error)
        }
    }

    func stop() {
        guard canControlProcess else { return }
        initialPromptTask?.cancel()
        launchTask?.cancel()
        append(Data("\r\n[Talkie] Stopping session...\r\n".utf8))

        if case .tmux(let sessionName, let executableURL) = launchMode {
            destroyTmuxSession(
                named: sessionName,
                executableURL: executableURL
            )
        }

        process.terminate()
    }

    func handleConsoleClosed() {
        guard canControlProcess else { return }
        initialPromptTask?.cancel()
        launchTask?.cancel()
        process.terminate()
    }

    nonisolated static func handleApplicationWillTerminate() {
        ManagedAgentConsoleSessionRegistry.shared.handleApplicationWillTerminate()
    }

    func send(_ text: String) {
        send(Data(text.utf8))
    }

    func send(_ data: Data) {
        process.send(data)
    }

    func sendPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(trimmed + "\r")
    }

    func resize(columns: Int, rows: Int) {
        let size = ManagedAgentPTYProcess.Size(columns: columns, rows: rows)
        latestTerminalSize = size
        process.resize(to: size)
    }

    func revealWorkspace() {
        NSWorkspace.shared.activateFileViewerSelecting([workspace.rootURL])
    }

    var clipboardTranscriptText: String {
        TerminalTranscriptFormatter.plainText(from: transcriptData)
    }

    @discardableResult
    func copyTranscriptToClipboard() -> Bool {
        let text = clipboardTranscriptText
        guard !text.isEmpty else { return false }

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    func attach(
        listener: (any Listener)?,
        replayTranscript: Bool = true
    ) {
        self.listener = listener
        guard replayTranscript else { return }
        listener?.consoleSession(self, didResetTranscript: transcriptData)
    }

    func detach(listener: any Listener) {
        guard self.listener === listener else { return }
        self.listener = nil
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        transcriptData.append(chunk)

        if trimTranscriptIfNeeded() {
            if keepsSessionAliveOnDetach {
                listener?.consoleSession(self, didReceiveOutput: chunk)
            } else {
                listener?.consoleSession(self, didResetTranscript: transcriptData)
            }
            return
        }

        listener?.consoleSession(self, didReceiveOutput: chunk)
    }

    /// Trim with hysteresis so long-running consoles don't replay ~600 KB of
    /// transcript on every chunk once they cross the buffer cap.
    private func trimTranscriptIfNeeded() -> Bool {
        guard transcriptData.count > TranscriptBuffer.maxLength else { return false }
        transcriptData = Data(transcriptData.suffix(TranscriptBuffer.trimTargetLength))
        return true
    }

    private func scheduleInitialPromptIfNeeded() {
        guard profile.harness == .openCode else { return }
        guard shouldSendInitialPrompt else { return }
        guard !didSendInitialPrompt else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        didSendInitialPrompt = true
        initialPromptTask?.cancel()
        initialPromptTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            guard self.isRunning else { return }
            self.send(trimmedPrompt + "\r")
        }
    }

    private func startResolvedLaunch(_ resolution: AgentConsoleCompanion.Resolution) {
        do {
            let launchSpec = try resolution.makeLaunchSpec()
            launchMode = launchSpec.sessionMode
            shouldSendInitialPrompt = launchSpec.shouldSendInitialPrompt && profile.autoSendPrompt
            didSendInitialPrompt = false

            process.onOutput = { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.append(data)
                    self.scheduleInitialPromptIfNeeded()
                }
            }

            process.onExit = { [weak self] exitCode in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.initialPromptTask?.cancel()
                    self.status = .exited(exitCode)
                    self.append(Data("\r\n[Talkie] Session exited with status \(exitCode)\r\n".utf8))
                    sessionLog.info("Managed agent console exited", detail: "\(self.profile.id) status=\(exitCode)")
                }
            }

            try process.start(spec: launchSpec, initialSize: latestTerminalSize)
            status = .running
            append(Data("[Talkie] \(resolution.reason)\r\n".utf8))
            pulseInitialResize()
            sessionLog.info(
                "Managed agent console started",
                detail: "\(profile.id) target=\(resolution.resolvedTarget)"
            )
        } catch {
            handleLaunchFailure(error)
        }
    }

    private func handleLaunchFailure(_ error: Error) {
        launchMode = .ephemeral
        shouldSendInitialPrompt = false
        status = .failed(error.localizedDescription)
        append(Data("[Talkie] Launch failed: \(error.localizedDescription)\r\n".utf8))
        sessionLog.error("Managed agent console failed", error: error)
    }

    private var canControlProcess: Bool {
        switch status {
        case .launching, .running:
            true
        case .exited, .failed:
            false
        }
    }

    private func pulseInitialResize() {
        let size = latestTerminalSize
        process.resize(to: size)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, self.isRunning else { return }
            self.process.resize(to: self.latestTerminalSize)
        }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, self.isRunning else { return }
            self.process.resize(to: self.latestTerminalSize)
        }
    }

    private func destroyTmuxSession(named sessionName: String, executableURL: URL) {
        let task = Process()
        task.executableURL = executableURL
        task.arguments = ["kill-session", "-t", sessionName]
        task.currentDirectoryURL = workspace.rootURL

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus != 0 else { return }
            sessionLog.warning("Failed to kill tmux session", detail: "\(sessionName) status=\(task.terminationStatus)")
        } catch {
            sessionLog.warning("Failed to launch tmux kill-session", detail: "\(sessionName): \(error.localizedDescription)")
        }
    }

}

private enum TerminalTranscriptFormatter {
    static func plainText(from data: Data) -> String {
        plainText(from: String(decoding: data, as: UTF8.self))
    }

    private static func plainText(from rawText: String) -> String {
        var text = rawText
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")

        text = remove(pattern: "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)", from: text)
        text = remove(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]", from: text)
        text = remove(pattern: "\u{001B}[@-Z\\\\-_]", from: text)

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(trimTrailingWhitespace)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remove(pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func trimTrailingWhitespace(_ line: Substring) -> String {
        var text = String(line)
        while let last = text.last, last.isWhitespace {
            text.removeLast()
        }
        return text
    }
}

private enum AgentConsoleCompanion {
    struct Resolution: Decodable {
        let requestedTarget: String
        let resolvedTarget: String
        let resolvedHarness: String
        let reason: String
        let launchSpec: LaunchSpecPayload

        func makeLaunchSpec() throws -> AgentHarnessProfile.LaunchSpec {
            try launchSpec.makeLaunchSpec()
        }
    }

    struct LaunchSpecPayload: Decodable {
        let executablePath: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String
        let sessionMode: SessionModePayload
        let shouldSendInitialPrompt: Bool

        func makeLaunchSpec() throws -> AgentHarnessProfile.LaunchSpec {
            guard !executablePath.isEmpty else {
                throw CompanionError.invalidResponse("The companion returned an empty executable path.")
            }

            return AgentHarnessProfile.LaunchSpec(
                executableURL: URL(fileURLWithPath: executablePath),
                arguments: arguments,
                environment: environment,
                workingDirectoryURL: URL(fileURLWithPath: workingDirectory),
                sessionMode: try sessionMode.makeSessionMode(),
                shouldSendInitialPrompt: shouldSendInitialPrompt
            )
        }
    }

    struct SessionModePayload: Decodable {
        let kind: String
        let sessionName: String?
        let executablePath: String?

        func makeSessionMode() throws -> AgentHarnessProfile.LaunchSpec.SessionMode {
            switch kind {
            case "ephemeral":
                return .ephemeral
            case "tmux":
                guard let sessionName,
                      let executablePath,
                      !sessionName.isEmpty,
                      !executablePath.isEmpty else {
                    throw CompanionError.invalidResponse("The companion returned an incomplete tmux launch spec.")
                }
                return .tmux(
                    sessionName: sessionName,
                    executableURL: URL(fileURLWithPath: executablePath)
                )
            default:
                throw CompanionError.invalidResponse("The companion returned an unknown session mode: \(kind).")
            }
        }
    }

    struct ProcessResult {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    enum CompanionError: LocalizedError {
        case bunMissing
        case npmMissing
        case companionMissing
        case installFailed(String)
        case executionFailed(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .bunMissing:
                "Bun is required to resolve Talkie agent harnesses on this Mac."
            case .npmMissing:
                "npm is required to install the Talkie companion runtime for the agent console."
            case .companionMissing:
                "Talkie could not find a local companion runtime for the agent console."
            case .installFailed(let message):
                "Talkie could not install the local agent companion: \(message)"
            case .executionFailed(let message):
                "Talkie could not resolve the local agent harness: \(message)"
            case .invalidResponse(let message):
                "Talkie received an invalid agent launch response: \(message)"
            }
        }
    }

    static func resolveConsoleLaunch(
        profileID: String,
        requestedHarness: AgentHarnessProfile,
        workspaceURL: URL,
        preferredModel: String?,
        preferTmux: Bool
    ) throws -> Resolution {
        try ensureCompanionInstalledIfNeeded()

        guard let bunPath = resolvedCommandPath(
            named: "bun",
            candidates: [
                "\(NSHomeDirectory())/.bun/bin/bun",
                "/opt/homebrew/bin/bun",
                "/usr/local/bin/bun",
            ]
        ) else {
            throw CompanionError.bunMissing
        }

        let entrypointURL = try companionEntrypointURL()
        let arguments = companionArguments(
            entrypointURL: entrypointURL,
            profileID: profileID,
            requestedHarness: requestedHarness,
            workspaceURL: workspaceURL,
            preferredModel: preferredModel,
            preferTmux: preferTmux
        )

        let result = try runProcess(
            executablePath: bunPath,
            arguments: arguments,
            currentDirectoryURL: workspaceURL
        )

        guard result.status == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let message = [stderr, stdout]
                .first(where: { !$0.isEmpty }) ?? "exit status \(result.status)"
            throw CompanionError.executionFailed(message)
        }

        do {
            return try JSONDecoder().decode(Resolution.self, from: result.stdout)
        } catch {
            let payload = String(decoding: result.stdout, as: UTF8.self)
            throw CompanionError.invalidResponse(payload.isEmpty ? error.localizedDescription : payload)
        }
    }

    private static func companionArguments(
        entrypointURL: URL,
        profileID: String,
        requestedHarness: AgentHarnessProfile,
        workspaceURL: URL,
        preferredModel: String?,
        preferTmux: Bool
    ) -> [String] {
        var arguments = [
            entrypointURL.path,
            "--json",
            "agent",
            "resolve",
            "--profile", profileID,
            "--requested-target", requestedTargetName(for: requestedHarness),
            "--workspace", workspaceURL.path,
        ]

        if let preferredModel, !preferredModel.isEmpty {
            arguments.append(contentsOf: ["--preferred-model", preferredModel])
        }

        if preferTmux {
            arguments.append("--tmux")
        }

        return arguments
    }

    private static func requestedTargetName(for harness: AgentHarnessProfile) -> String {
        switch harness {
        case .openCode:
            "opencode"
        case .claude:
            "claude"
        case .helloWorld:
            "shell"
        }
    }

    private static func ensureCompanionInstalledIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: companionPackageManifestURL.path),
              FileManager.default.fileExists(atPath: companionSourceEntrypointURL.path) else {
            return
        }

        if !companionInstallNeedsRefresh() {
            return
        }

        guard let npmPath = resolvedCommandPath(
            named: "npm",
            candidates: [
                "\(NSHomeDirectory())/.local/state/fnm/current/bin/npm",
                "/opt/homebrew/bin/npm",
                "/usr/local/bin/npm",
            ]
        ) else {
            throw CompanionError.npmMissing
        }

        try FileManager.default.createDirectory(
            at: companionRuntimeDirectoryURL,
            withIntermediateDirectories: true
        )

        let installResult = try runProcess(
            executablePath: npmPath,
            arguments: [
                "install",
                "--foreground-scripts",
                "--no-audit",
                "--no-fund",
                "--force",
                "--global",
                "--prefix", companionRuntimeDirectoryURL.path,
                companionPackageURL.path,
            ],
            currentDirectoryURL: companionPackageURL,
            environment: installEnvironment(npmPath: npmPath)
        )

        guard installResult.status == 0 else {
            let stderr = String(decoding: installResult.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(decoding: installResult.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let message = [stderr, stdout]
                .first(where: { !$0.isEmpty }) ?? "exit status \(installResult.status)"
            throw CompanionError.installFailed(message)
        }
    }

    private static func companionEntrypointURL() throws -> URL {
        if FileManager.default.fileExists(atPath: installedCompanionEntrypointURL.path) {
            return installedCompanionEntrypointURL
        }

        if FileManager.default.fileExists(atPath: companionSourceEntrypointURL.path) {
            return companionSourceEntrypointURL
        }

        throw CompanionError.companionMissing
    }

    private static func companionInstallNeedsRefresh() -> Bool {
        guard FileManager.default.fileExists(atPath: installedCompanionEntrypointURL.path) else {
            return true
        }

        let installedDate = modificationDate(for: installedCompanionEntrypointURL) ?? .distantPast
        let packageDate = latestModificationDate(in: companionPackageURL) ?? .distantPast
        return installedDate < packageDate
    }

    private static func installEnvironment(npmPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let npmDirectory = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path
        let bunDirectory = resolvedCommandPath(
            named: "bun",
            candidates: [
                "\(NSHomeDirectory())/.bun/bin/bun",
                "/opt/homebrew/bin/bun",
                "/usr/local/bin/bun",
            ]
        )
        let nodeDirectory = resolvedCommandPath(
            named: "node",
            candidates: [
                "\(NSHomeDirectory())/.local/state/fnm/current/bin/node",
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
            ]
        )
        .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = [
            bunDirectory.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path },
            nodeDirectory,
            npmDirectory,
            ProcessInfo.processInfo.environment["PATH"],
        ]
        .compactMap { $0 }
        .joined(separator: ":")

        return environment
    }

    private static func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private static func latestModificationDate(in directoryURL: URL) -> Date? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return modificationDate(for: directoryURL)
        }

        var latestDate = modificationDate(for: directoryURL)

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate else {
                continue
            }

            if latestDate == nil || modifiedAt > latestDate! {
                latestDate = modifiedAt
            }
        }

        return latestDate
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func resolvedCommandPath(named name: String, candidates: [String] = []) -> String? {
        ExecutableResolver.resolve(name, extraCandidates: candidates)?.path
    }

    private static var talkieShellHomeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".talkie-shell", directoryHint: .isDirectory)
    }

    private static var companionRuntimeDirectoryURL: URL {
        talkieShellHomeURL.appending(path: "runtime", directoryHint: .isDirectory)
    }

    private static var installedCompanionEntrypointURL: URL {
        companionRuntimeDirectoryURL
            .appending(path: "lib", directoryHint: .isDirectory)
            .appending(path: "node_modules", directoryHint: .isDirectory)
            .appending(path: "@talkie", directoryHint: .isDirectory)
            .appending(path: "companion", directoryHint: .isDirectory)
            .appending(path: "src", directoryHint: .isDirectory)
            .appending(path: "index.js")
    }

    private static var companionPackageURL: URL {
        if let repoRoot = LocalCheckoutLocator.talkieRepositoryRootURL(compileTimeFilePath: #filePath) {
            return repoRoot.appending(path: "companion", directoryHint: .isDirectory)
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        return sourceFileURL
            .deletingLastPathComponent() // Agents
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Talkie
            .deletingLastPathComponent() // macOS
            .deletingLastPathComponent() // repo root
            .appending(path: "companion", directoryHint: .isDirectory)
    }

    private static var companionPackageManifestURL: URL {
        companionPackageURL.appending(path: "package.json")
    }

    private static var companionSourceEntrypointURL: URL {
        companionPackageURL
            .appending(path: "src", directoryHint: .isDirectory)
            .appending(path: "index.js")
    }
}

private final class ManagedAgentConsoleSessionRegistry {
    static let shared = ManagedAgentConsoleSessionRegistry()

    private let lock = NSLock()
    private var sessions: [UUID: WeakManagedAgentConsoleSession] = [:]

    func register(_ session: ManagedAgentConsoleSession) {
        lock.lock()
        sessions[session.id] = WeakManagedAgentConsoleSession(session)
        cleanupReleasedSessionsLocked()
        lock.unlock()
    }

    func unregister(_ session: ManagedAgentConsoleSession) {
        lock.lock()
        sessions.removeValue(forKey: session.id)
        cleanupReleasedSessionsLocked()
        lock.unlock()
    }

    func session(for id: UUID) -> ManagedAgentConsoleSession? {
        lock.lock()
        let session = sessions[id]?.session
        cleanupReleasedSessionsLocked()
        lock.unlock()
        return session
    }

    func handleApplicationWillTerminate() {
        lock.lock()
        let activeSessions = sessions.values.compactMap(\.session)
        cleanupReleasedSessionsLocked()
        lock.unlock()

        for session in activeSessions {
            MainActor.assumeIsolated {
                session.handleConsoleClosed()
            }
        }
    }

    private func cleanupReleasedSessionsLocked() {
        sessions = sessions.filter { $0.value.session != nil }
    }
}

private final class WeakManagedAgentConsoleSession {
    weak var session: ManagedAgentConsoleSession?

    init(_ session: ManagedAgentConsoleSession) {
        self.session = session
    }
}
