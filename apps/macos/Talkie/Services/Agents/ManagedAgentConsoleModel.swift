//
//  ManagedAgentConsoleModel.swift
//  Talkie
//
//  State and process management for the starter in-app agent lab.
//

import AppKit
import Foundation
import Observation
import TalkieKit

private let log = Log(.ui)

@MainActor
@Observable
final class ManagedAgentConsoleModel {
    enum Status: Equatable {
        case idle
        case preparing
        case running
        case finished(Int32)
        case failed(String)
    }

    var selectedProfile: AgentHarnessProfile
    var prompt: String
    var notes: String
    var output: String = ""
    var status: Status = .idle
    var workspace: ManagedAgentWorkspace?
    var lastStartedAt: Date?
    var lastFinishedAt: Date?

    @ObservationIgnored private let workspaceStore: ManagedAgentWorkspaceStore
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var standardOutputPipe: Pipe?
    @ObservationIgnored private var standardErrorPipe: Pipe?

    init(
        workspaceStore: ManagedAgentWorkspaceStore = .init()
    ) {
        self.workspaceStore = workspaceStore
        self.selectedProfile = .defaultProfile
        self.prompt = "Say hello from Talkie. Briefly summarize the rule, config, memo, and workflow surfaces in this workspace, then suggest one concrete next step."
        self.notes = """
        This is the starter Talkie agent workspace.
        Use the guides and tools in the workspace before widening scope.
        Keep your advice concrete and minimal.
        """
    }

    var canRun: Bool {
        !isRunning && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isRunning: Bool {
        if case .running = status {
            true
        } else {
            false
        }
    }

    var statusLabel: String {
        switch status {
        case .idle:
            "Idle"
        case .preparing:
            "Preparing workspace"
        case .running:
            "Running"
        case .finished(let code):
            code == 0 ? "Finished" : "Exited \(code)"
        case .failed:
            "Failed"
        }
    }

    var statusDetail: String {
        switch status {
        case .idle:
            "Boot a managed harness with a prepared Talkie workspace."
        case .preparing:
            "Writing guides, mounting live config, and preparing memo inspection tools."
        case .running:
            "Streaming output from the current harness run."
        case .finished(let code):
            code == 0 ? "The harness exited cleanly." : "The harness exited with a non-zero status."
        case .failed(let message):
            message
        }
    }

    func run() {
        guard canRun else { return }

        stopIfNeeded()
        output = ""
        status = .preparing
        lastStartedAt = Date()
        lastFinishedAt = nil

        do {
            let workspace = try workspaceStore.prepareWorkspace(
                profile: selectedProfile,
                prompt: prompt,
                notes: notes
            )
            self.workspace = workspace

            let spec = try selectedProfile.makeLaunchSpec(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                workspaceURL: workspace.rootURL
            )

            appendOutput("""
            > Harness: \(selectedProfile.displayName)
            > Workspace: \(workspace.rootURL.path())
            > Prompt saved at: \(workspace.rootURL.appending(path: "PROMPT.md").path())

            """)

            let process = Process()
            process.executableURL = spec.executableURL
            process.arguments = spec.arguments
            process.currentDirectoryURL = spec.workingDirectoryURL
            process.environment = mergedEnvironment(extra: spec.environment)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.appendOutput(Self.sanitize(String(decoding: data, as: UTF8.self)))
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.appendOutput(Self.sanitize(String(decoding: data, as: UTF8.self)))
                }
            }

            process.terminationHandler = { [weak self] process in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastFinishedAt = Date()
                    self.status = .finished(process.terminationStatus)
                    self.appendOutput("\n> Process exited with status \(process.terminationStatus)\n")
                    self.cleanupProcess()
                }
            }

            self.process = process
            self.standardOutputPipe = stdoutPipe
            self.standardErrorPipe = stderrPipe
            status = .running

            try process.run()
            log.info("Managed agent harness started", detail: "\(selectedProfile.rawValue)")
        } catch {
            status = .failed(error.localizedDescription)
            appendOutput("\n> Launch failed: \(error.localizedDescription)\n")
            cleanupProcess()
            log.error("Managed agent harness failed", error: error)
        }
    }

    func stop() {
        guard let process else { return }
        appendOutput("\n> Stopping harness...\n")
        process.terminate()
    }

    func revealWorkspace() {
        guard let workspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([workspace.rootURL])
    }

    private func stopIfNeeded() {
        if process?.isRunning == true {
            process?.terminate()
        }
        cleanupProcess()
    }

    private func cleanupProcess() {
        standardOutputPipe?.fileHandleForReading.readabilityHandler = nil
        standardErrorPipe?.fileHandleForReading.readabilityHandler = nil
        standardOutputPipe = nil
        standardErrorPipe = nil
        process = nil
    }

    private func appendOutput(_ string: String) {
        guard !string.isEmpty else { return }
        output.append(string)

        let maxLength = 200_000
        if output.count > maxLength {
            output.removeFirst(output.count - maxLength)
        }
    }

    private func mergedEnvironment(extra: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let pathAdditions = [
            "\(NSHomeDirectory())/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        environment["PATH"] = pathAdditions.joined(separator: ":")

        for (key, value) in extra {
            environment[key] = value
        }

        return environment
    }

    private static func sanitize(_ string: String) -> String {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return normalized
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        return expression.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
    }
}
