//
//  SSHTerminalSession.swift
//  Talkie iOS
//
//  Main-actor session model for an interactive SSH shell.
//

import Foundation
import Observation
import TalkieMobileKit
import NIOCore
@preconcurrency import NIOSSH
import NIOTransportServices

@MainActor
@Observable
final class SSHTerminalSession {
    struct DiagnosticEvent: Identifiable, Equatable {
        enum Level: String, Equatable {
            case info
            case warning
            case error
        }

        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    protocol Listener: AnyObject {
        func sshTerminalSession(_ session: SSHTerminalSession, didResetTranscript transcript: Data)
        func sshTerminalSession(_ session: SSHTerminalSession, didReceiveOutput chunk: Data)
    }

    var status: Status = .disconnected
    var transcriptData: Data = .init()
    var outputChunkRecords: [SSHTerminalOutputChunkRecord] = []
    var endpointLabel: String = ""
    var hostFingerprint: String?
    var hostTrustMessage: String?
    var launchModeLabel: String?
    var launchCommandSummary: String?
    var recentDiagnostics: [DiagnosticEvent] = []

    @ObservationIgnored private weak var listener: (any Listener)?
    @ObservationIgnored private var eventLoopGroup: NIOTSEventLoopGroup?
    @ObservationIgnored private var connectionChannel: Channel?
    @ObservationIgnored private var shellChannel: Channel?
    @ObservationIgnored private var connectBeganAt: Date?
    @ObservationIgnored private var readyAt: Date?
    @ObservationIgnored private var terminalColumns = 120
    @ObservationIgnored private var terminalRows = 34
    @ObservationIgnored private var terminalPixelWidth = 0
    @ObservationIgnored private var terminalPixelHeight = 0
    @ObservationIgnored private let log = Log(.ui)
    @ObservationIgnored private var nextOutputChunkSequence = 0
    @ObservationIgnored private var isTearingDown = false
    @ObservationIgnored private var didObserveRemoteExit = false

    func attach(
        listener: (any Listener)?,
        replayTranscript: Bool = true
    ) {
        self.listener = listener
        guard replayTranscript else { return }
        listener?.sshTerminalSession(self, didResetTranscript: transcriptData)
    }

    func connect(configuration: SSHTerminalConfiguration) async {
        await disconnect()
        isTearingDown = false
        didObserveRemoteExit = false
        connectBeganAt = .now
        readyAt = nil

        let host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = configuration.password.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateKeyPEM = configuration.privateKeyPEM?.trimmingCharacters(in: .whitespacesAndNewlines)
        let startupCommand = configuration.startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty, !username.isEmpty else {
            status = .failed("Enter a host and username.")
            return
        }

        guard !password.isEmpty || !(privateKeyPEM ?? "").isEmpty else {
            status = .failed(SSHClientError.authenticationRequired.localizedDescription)
            return
        }

        let parsedPrivateKey: NIOSSHPrivateKey?
        do {
            if let privateKeyPEM, !privateKeyPEM.isEmpty {
                parsedPrivateKey = try SSHPrivateKeyParser.parse(privateKeyPEM)
            } else {
                parsedPrivateKey = nil
            }
        } catch {
            status = .failed(SSHErrorFormatter.message(for: error))
            return
        }

        endpointLabel = "\(username)@\(host):\(configuration.port)"
        hostFingerprint = nil
        hostTrustMessage = nil
        launchModeLabel = configuration.startupProfile.title
        launchCommandSummary = startupCommandSummary(
            for: configuration.startupProfile,
            command: startupCommand
        )
        status = .connecting
        resetTranscript()
        recentDiagnostics = []
        appendDiagnostic(.info, "Connecting to \(endpointLabel)")
        appendDiagnostic(.info, "Launch mode: \(configuration.startupProfile.title)")
        appendDiagnostic(.info, "Startup: \(launchCommandSummary ?? "login shell")")

        let group = NIOTSEventLoopGroup()
        eventLoopGroup = group

        let authDelegate = SSHClientAuthenticationDelegate(
            username: username,
            password: password.isEmpty ? nil : password,
            privateKey: parsedPrivateKey
        )
        let hostKeyValidator = SSHHostKeyValidator(host: host, port: configuration.port) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.applyHostValidation(result)
            }
        }
        let readyCallback: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.readyAt = .now
                self.status = .connected
            }
        }
        let outputCallback: @Sendable (Data) -> Void = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.append(data)
            }
        }
        let exitCallback: @Sendable (Int?) -> Void = { [weak self] code in
            Task { @MainActor [weak self] in
                self?.handleRemoteExit(code)
            }
        }
        let errorCallback: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.handleConnectionError(error)
            }
        }

        let initialColumns = terminalColumns
        let initialRows = terminalRows
        let initialPixelWidth = terminalPixelWidth
        let initialPixelHeight = terminalPixelHeight

        do {
            let bootstrap = NIOTSConnectionBootstrap(group: group)
                .channelInitializer { channel in
                    do {
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSHHandler(
                                role: .client(
                                    .init(
                                        userAuthDelegate: authDelegate,
                                        serverAuthDelegate: hostKeyValidator
                                    )
                                ),
                                allocator: channel.allocator,
                                inboundChildChannelInitializer: nil
                            )
                        )
                        try channel.pipeline.syncOperations.addHandler(
                            SSHConnectionErrorHandler(onError: errorCallback)
                        )
                        return channel.eventLoop.makeSucceededFuture(())
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }

            let connectionChannel = try await bootstrap.connect(host: host, port: configuration.port).get()
            self.connectionChannel = connectionChannel

            let shellChannel = try await connectionChannel.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
                let promise = connectionChannel.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(promise) { childChannel, channelType in
                    guard channelType == .session else {
                        return connectionChannel.eventLoop.makeFailedFuture(SSHClientError.invalidChannelType)
                    }

                    return childChannel.pipeline.addHandler(
                        SSHTerminalChannelHandler(
                            term: configuration.term,
                            startupCommand: startupCommand,
                            initialColumns: initialColumns,
                            initialRows: initialRows,
                            initialPixelWidth: initialPixelWidth,
                            initialPixelHeight: initialPixelHeight,
                            onReady: readyCallback,
                            onOutput: outputCallback,
                            onExit: exitCallback,
                            onError: errorCallback
                        )
                    )
                }

                return promise.futureResult
            }.get()

            self.shellChannel = shellChannel
        } catch {
            await handleConnectionError(error)
        }
    }

    func disconnect() async {
        isTearingDown = true
        let shellChannel = self.shellChannel
        let connectionChannel = self.connectionChannel
        let eventLoopGroup = self.eventLoopGroup

        self.shellChannel = nil
        self.connectionChannel = nil
        self.eventLoopGroup = nil
        self.connectBeganAt = nil
        self.readyAt = nil

        if let shellChannel {
            try? await shellChannel.close().get()
        }

        if let connectionChannel {
            try? await connectionChannel.close().get()
        }

        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }

        if case .failed = status {
            return
        }

        status = .disconnected
    }

    func send(_ text: String) {
        send(Data(text.utf8))
    }

    func send(_ data: Data) {
        guard let shellChannel else { return }
        guard !data.isEmpty else { return }
        var buffer = shellChannel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        shellChannel.writeAndFlush(buffer, promise: nil)
    }

    func sendInterrupt() {
        send("\u{03}")
    }

    func resize(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        terminalColumns = max(columns, 2)
        terminalRows = max(rows, 1)
        terminalPixelWidth = max(pixelWidth, 0)
        terminalPixelHeight = max(pixelHeight, 0)

        guard let shellChannel else { return }

        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: terminalColumns,
            terminalRowHeight: terminalRows,
            terminalPixelWidth: terminalPixelWidth,
            terminalPixelHeight: terminalPixelHeight
        )
        shellChannel.triggerUserOutboundEvent(request, promise: nil)
    }

    private func applyHostValidation(_ result: SSHKnownHostStore.ValidationResult) {
        switch result {
        case .trusted(let fingerprint):
            hostFingerprint = fingerprint
            hostTrustMessage = "Known host"
            appendDiagnostic(.info, "Host key trusted")
        case .trustedOnFirstUse(let fingerprint):
            hostFingerprint = fingerprint
            hostTrustMessage = "Trusted on first use"
            appendStatusLine("[Talkie] Trusted host key on first connection")
            appendDiagnostic(.warning, "Trusted host key on first use")
        case .mismatch(let expected, let actual):
            hostFingerprint = actual
            hostTrustMessage = "Host key mismatch"
            appendStatusLine("[Talkie] Host key mismatch. Expected \(expected), got \(actual)")
            appendDiagnostic(.error, "Host key mismatch")
        }
    }

    private func handleRemoteExit(_ code: Int?) {
        didObserveRemoteExit = true
        let exitedDuringStartup = didExitDuringStartup
        if let code {
            appendStatusLine("[Talkie] Remote shell exited with status \(code)")
            appendDiagnostic(code == 0 ? .info : .warning, "Remote shell exited with status \(code)")
            if exitedDuringStartup, code != 0 {
                let mode = launchModeLabel ?? "This launch mode"
                status = .failed("\(mode) exited during startup. Open Troubleshooting for the helper step and retry options.")
                return
            }
        } else {
            appendStatusLine("[Talkie] Remote shell closed")
            appendDiagnostic(.warning, "Remote shell closed")
            if exitedDuringStartup, let launchModeLabel, launchModeLabel != SSHTerminalStartupProfile.standardShell.title {
                status = .failed("\(launchModeLabel) closed during startup. Open Troubleshooting for the helper step and retry options.")
                return
            }
        }
        status = .disconnected
    }

    private func handleConnectionError(_ error: Error) async {
        if shouldSuppressConnectionError(error) {
            log.info(
                "Suppressing expected SSH teardown error",
                detail: "status=\(status) error=\(error.localizedDescription)"
            )
            if case .failed = status {
                return
            }
            status = .disconnected
            return
        }

        let message = contextualMessage(for: error)
        appendDiagnostic(.error, "Failure: \(message)")
        appendDiagnostic(.error, "Raw error: \(technicalErrorDescription(for: error))")
        appendStatusLine("[Talkie] SSH error: \(message)")
        status = .failed(message)
        log.error("SSH terminal connection failed", error: error)
        await disconnect()
        status = .failed(message)
    }

    private func shouldSuppressConnectionError(_ error: Error) -> Bool {
        if isTearingDown || didObserveRemoteExit || status == .disconnected {
            if isExpectedTeardownError(error) {
                return true
            }
        }

        return false
    }

    private func isExpectedTeardownError(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            switch channelError {
            case .ioOnClosedChannel, .alreadyClosed, .outputClosed, .inputClosed, .eof:
                return true
            default:
                break
            }
        }

        if let ioError = error as? IOError {
            switch ioError.errnoCode {
            case ECONNABORTED, ECONNRESET, ENOTCONN, EPIPE:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ECONNABORTED, ECONNRESET, ENOTCONN, EPIPE:
                return true
            default:
                break
            }
        }

        return false
    }

    private func resetTranscript(with message: String = "") {
        transcriptData = Data(message.utf8)
        outputChunkRecords = []
        nextOutputChunkSequence = 0
        listener?.sshTerminalSession(self, didResetTranscript: transcriptData)
    }

    private func appendStatusLine(_ line: String) {
        append(Data("\(line)\r\n".utf8))
    }

    private func appendDiagnostic(_ level: DiagnosticEvent.Level, _ message: String) {
        recentDiagnostics.append(
            DiagnosticEvent(
                timestamp: .now,
                level: level,
                message: message
            )
        )
        if recentDiagnostics.count > 12 {
            recentDiagnostics.removeFirst(recentDiagnostics.count - 12)
        }
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        transcriptData.append(chunk)
        outputChunkRecords.append(
            SSHTerminalOutputChunkRecord(
                sequence: nextOutputChunkSequence,
                data: chunk
            )
        )
        nextOutputChunkSequence += 1

        let maxLength = 600_000
        if transcriptData.count > maxLength {
            transcriptData.removeFirst(transcriptData.count - maxLength)
            trimOutputChunkRecords(maxLength: maxLength)
            listener?.sshTerminalSession(self, didResetTranscript: transcriptData)
        } else {
            listener?.sshTerminalSession(self, didReceiveOutput: chunk)
        }
    }

    private func trimOutputChunkRecords(maxLength: Int) {
        var totalLength = outputChunkRecords.reduce(into: 0) { partialResult, record in
            partialResult += record.byteCount
        }

        while totalLength > maxLength, !outputChunkRecords.isEmpty {
            totalLength -= outputChunkRecords.removeFirst().byteCount
        }
    }

    private func contextualMessage(for error: Error) -> String {
        let baseMessage = SSHErrorFormatter.message(for: error)

        guard case .connecting = status else {
            return baseMessage
        }

        if let launchModeLabel,
           launchModeLabel != SSHTerminalStartupProfile.standardShell.title {
            switch baseMessage {
            case "The SSH connection closed unexpectedly.",
                 "The SSH session is disconnected.",
                 "The server reset the SSH connection.":
                return "\(launchModeLabel) closed during startup. Check the connection log below for the helper/runtime step that failed."
            default:
                break
            }
        }

        switch baseMessage {
        case "The SSH connection closed unexpectedly.",
             "The SSH session is disconnected.",
             "The server reset the SSH connection.":
            return "The server closed the SSH connection before login. Check that SSH is enabled on the host and that your user is allowed to sign in."
        default:
            return baseMessage
        }
    }

    private func startupCommandSummary(
        for profile: SSHTerminalStartupProfile,
        command: String?
    ) -> String? {
        let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCommand.isEmpty else {
            return "login shell"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-shell") {
            return "talkie-shell helper"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-session") {
            return "talkie-session helper"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-enter") {
            return "talkie-enter helper"
        }

        switch profile {
        case .standardShell:
            return "login shell"
        case .talkieShell, .talkieSession:
            let prefix = trimmedCommand.prefix(96)
            return prefix.count == trimmedCommand.count ? String(prefix) : "\(prefix)…"
        }
    }

    private func technicalErrorDescription(for error: Error) -> String {
        if let channelError = error as? ChannelError {
            return "ChannelError.\(String(describing: channelError))"
        }

        if let ioError = error as? IOError {
            return "IOError(errno=\(ioError.errnoCode)): \(ioError.localizedDescription)"
        }

        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }

    private var didExitDuringStartup: Bool {
        if let readyAt {
            return Date.now.timeIntervalSince(readyAt) < 4
        }

        if connectBeganAt != nil {
            return true
        }

        return false
    }
}
