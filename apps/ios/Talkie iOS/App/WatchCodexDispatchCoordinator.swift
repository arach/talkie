//
//  WatchCodexDispatchCoordinator.swift
//  Talkie iOS
//
//  Durable phone-side inbox for Watch-originated Codex recordings. A received
//  recording is persisted before asynchronous work begins, so iOS suspension
//  can delay delivery without losing it.
//

import BackgroundTasks
import Foundation
import UIKit

enum WatchCodexDispatchAction: String, Codable, Equatable {
    case continueTask = "continue"
    case newTask = "new-task"

    init(metadataValue: Any?) {
        self = (metadataValue as? String).flatMap(Self.init(rawValue:)) ?? .continueTask
    }
}

struct WatchCodexPendingDispatch: Codable, Identifiable, Equatable {
    enum Stage: String, Codable {
        case received
        case transcribed
        case submitted
    }

    let id: UUID
    let hostID: String
    let anchorTaskID: String
    let projectDirectory: String?
    let taskTitle: String?
    let action: WatchCodexDispatchAction?
    var audioFilename: String
    let createdAt: Date
    var updatedAt: Date
    var stage: Stage
    var transcript: String?
    var jobID: String?
    var createdTaskID: String?
    var attemptCount: Int
    var lastError: String?
}

/// Synchronous handoff written from the WCSession file callback before it
/// returns. iOS may suspend the app immediately after that callback, so the
/// main-actor dispatch queue cannot be the first durable record of the work.
struct WatchCodexIncomingDispatch: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: String?
    let anchorTaskID: String?
    let projectDirectory: String?
    let taskTitle: String?
    let action: WatchCodexDispatchAction?
    let audioFilename: String
    let createdAt: Date

    var metadata: [String: Any] {
        var values: [String: Any] = ["requestID": id.uuidString]
        if let hostID { values["hostID"] = hostID }
        if let anchorTaskID { values["taskID"] = anchorTaskID }
        if let projectDirectory { values["cwd"] = projectDirectory }
        if let taskTitle { values["taskTitle"] = taskTitle }
        if let action { values["codexAction"] = action.rawValue }
        return values
    }
}

struct WatchCodexIncomingDispatchStore {
    let directoryURL: URL
    let audioDirectoryURL: URL

    init(
        directoryURL: URL,
        audioDirectoryURL: URL = URL.documentsDirectory
            .appending(path: "WatchAudio", directoryHint: .isDirectory)
    ) {
        self.directoryURL = directoryURL
        self.audioDirectoryURL = audioDirectoryURL
    }

    func stage(audioURL: URL, metadata: [String: Any]) throws -> WatchCodexIncomingDispatch {
        guard let requestIDValue = nonemptyString(metadata["requestID"])
                ?? nonemptyString(metadata["memoId"]),
              let requestID = UUID(uuidString: requestIDValue) else {
            throw StageError.missingRequestID
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifestURL = url(for: requestID)
        if let existing = try? JSONDecoder().decode(
            WatchCodexIncomingDispatch.self,
            from: Data(contentsOf: manifestURL)
        ), FileManager.default.fileExists(atPath: self.audioURL(for: existing).path) {
            if existing.audioFilename != audioURL.lastPathComponent {
                try? FileManager.default.removeItem(at: audioURL)
            }
            return existing
        }

        let incoming = WatchCodexIncomingDispatch(
            id: requestID,
            hostID: nonemptyString(metadata["hostID"]),
            anchorTaskID: nonemptyString(metadata["taskID"]),
            projectDirectory: nonemptyString(metadata["cwd"]),
            taskTitle: nonemptyString(metadata["taskTitle"]),
            action: WatchCodexDispatchAction(metadataValue: metadata["codexAction"]),
            audioFilename: audioURL.lastPathComponent,
            createdAt: .now
        )
        try JSONEncoder().encode(incoming).write(
            to: manifestURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return incoming
    }

    func load() throws -> [WatchCodexIncomingDispatch] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            do {
                return try JSONDecoder().decode(
                    WatchCodexIncomingDispatch.self,
                    from: Data(contentsOf: url)
                )
            } catch {
                AppLogger.ai.warning(
                    "Watch Codex incoming manifest is unreadable: \(url.lastPathComponent)"
                )
                return nil
            }
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(_ incoming: WatchCodexIncomingDispatch) throws {
        let manifestURL = url(for: incoming.id)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        try FileManager.default.removeItem(at: manifestURL)
    }

    func audioURL(for incoming: WatchCodexIncomingDispatch) -> URL {
        audioDirectoryURL.appending(path: incoming.audioFilename)
    }

    private func url(for requestID: UUID) -> URL {
        directoryURL.appending(path: requestID.uuidString).appendingPathExtension("json")
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    enum StageError: LocalizedError {
        case missingRequestID

        var errorDescription: String? {
            "The Watch request is missing its durable identifier."
        }
    }
}

struct WatchCodexPendingDispatchStore {
    let url: URL

    func load() throws -> [WatchCodexPendingDispatch] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode(
            [WatchCodexPendingDispatch].self,
            from: Data(contentsOf: url)
        )
    }

    func save(_ pending: [WatchCodexPendingDispatch]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(pending).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

@MainActor
final class WatchCodexDispatchCoordinator {
    static let shared = WatchCodexDispatchCoordinator()

    private let bridge: BridgeManager
    private let watchSession: WatchSessionManager
    private let store: WatchCodexPendingDispatchStore
    private let incomingStore: WatchCodexIncomingDispatchStore
    private var pending: [WatchCodexPendingDispatch]
    private var resumeTask: Task<Void, Never>?

    private init() {
        bridge = .shared
        watchSession = .shared
        store = WatchCodexPendingDispatchStore(url: Self.storeURL)
        incomingStore = WatchCodexIncomingDispatchStore(directoryURL: Self.incomingStoreURL)
        do {
            pending = try store.load()
        } catch {
            pending = []
            AppLogger.ai.warning("Watch Codex inbox is unreadable: \(error.localizedDescription)")
        }
    }

    /// Persists the Watch recording before beginning transcription or network
    /// work. Repeated WatchConnectivity delivery with the same request ID is
    /// idempotent and resumes the existing record.
    func enqueue(audioURL: URL, metadata: [String: Any]) async {
        do {
            _ = try incomingStore.stage(audioURL: audioURL, metadata: metadata)
        } catch {
            AppLogger.ai.warning("Watch Codex dispatch rejected incomplete routing metadata")
            sendFailureIfAddressable(metadata, detail: error.localizedDescription)
            try? FileManager.default.removeItem(at: audioURL)
            return
        }
        await resumePendingDispatches()
    }

    /// Older Watch installs can outlive a phone update and send the Codex
    /// intent before they receive the richer project snapshot. Upgrade that
    /// request from the phone's current project anchor instead of discarding a
    /// recording the user already made. The Watch memo UUID remains the durable
    /// idempotency key until the updated Watch app begins supplying requestID.
    private func resolvedRouting(
        from metadata: [String: Any]
    ) -> (
        requestID: UUID,
        hostID: String,
        taskID: String,
        taskTitle: String,
        projectDirectory: String,
        action: WatchCodexDispatchAction
    )? {
        let requestIDValue = nonemptyString(metadata["requestID"])
            ?? nonemptyString(metadata["memoId"])
        guard let requestIDValue,
              let requestID = UUID(uuidString: requestIDValue) else {
            return nil
        }

        let store = CodexLaneStore.shared
        let suppliedTaskID = nonemptyString(metadata["taskID"])
        let anchor = suppliedTaskID.flatMap { taskID in
            store.catalog.first(where: { $0.id == taskID })
                ?? store.sortedLanes.first(where: { $0.task.id == taskID })?.task
        } ?? store.selectedTask ?? store.catalog.first ?? store.sortedLanes.first?.task

        guard let hostID = nonemptyString(metadata["hostID"]) ?? bridge.activePairedMacID,
              let taskID = suppliedTaskID ?? anchor?.id,
              let projectDirectory = nonemptyString(metadata["cwd"])
                ?? anchor?.canonicalWorkingDirectory else {
            return nil
        }
        let taskTitle = nonemptyString(metadata["taskTitle"]) ?? anchor?.title ?? "Codex task"
        let action = WatchCodexDispatchAction(metadataValue: metadata["codexAction"])

        if nonemptyString(metadata["requestID"]) == nil
            || nonemptyString(metadata["hostID"]) == nil
            || nonemptyString(metadata["taskID"]) == nil
            || nonemptyString(metadata["cwd"]) == nil {
            AppLogger.ai.info(
                "Upgraded legacy Watch Codex routing request=\(requestID) project=\(projectDirectory)"
            )
        }

        return (requestID, hostID, taskID, taskTitle, projectDirectory, action)
    }

    /// Resumes every durable dispatch. Safe to call at launch, foregrounding,
    /// Watch file delivery, and BGAppRefresh entry.
    func resumePendingDispatches() async {
        if let resumeTask {
            await resumeTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.importIncomingDispatches()
            await self.processPendingDispatches()
        }
        resumeTask = task
        await task.value
        resumeTask = nil
    }

    /// Atomically promotes every synchronous WCSession handoff into the durable
    /// state-machine inbox. The manifest is removed only after the inbox save,
    /// making a crash on either side of the transition safe and idempotent.
    private func importIncomingDispatches() {
        let incoming: [WatchCodexIncomingDispatch]
        do {
            incoming = try incomingStore.load()
        } catch {
            AppLogger.ai.warning("Watch Codex incoming queue is unreadable: \(error.localizedDescription)")
            return
        }

        for item in incoming {
            let audioURL = incomingStore.audioURL(for: item)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                AppLogger.ai.warning(
                    "Watch Codex incoming audio is missing: \(item.audioFilename)"
                )
                try? incomingStore.remove(item)
                continue
            }
            guard let routing = resolvedRouting(from: item.metadata) else {
                sendFailureIfAddressable(
                    item.metadata,
                    detail: "The Watch request was missing its Codex destination."
                )
                try? FileManager.default.removeItem(at: audioURL)
                try? incomingStore.remove(item)
                continue
            }

            if let index = pending.firstIndex(where: { $0.id == routing.requestID }) {
                let existingAudioURL = self.audioURL(for: pending[index])
                if FileManager.default.fileExists(atPath: existingAudioURL.path) {
                    if existingAudioURL != audioURL {
                        try? FileManager.default.removeItem(at: audioURL)
                    }
                } else {
                    pending[index].audioFilename = item.audioFilename
                    pending[index].updatedAt = .now
                }
            } else {
                pending.append(WatchCodexPendingDispatch(
                    id: routing.requestID,
                    hostID: routing.hostID,
                    anchorTaskID: routing.taskID,
                    projectDirectory: routing.projectDirectory,
                    taskTitle: routing.taskTitle,
                    action: routing.action,
                    audioFilename: item.audioFilename,
                    createdAt: item.createdAt,
                    updatedAt: .now,
                    stage: .received,
                    transcript: nil,
                    jobID: nil,
                    createdTaskID: nil,
                    attemptCount: 0,
                    lastError: nil
                ))
            }

            do {
                try store.save(pending)
                try incomingStore.remove(item)
                sendUpdate(
                    requestID: routing.requestID.uuidString,
                    hostID: routing.hostID,
                    taskID: routing.taskID,
                    status: "received",
                    detail: "Phone received and saved the recording."
                )
                AppLogger.ai.info(
                    "Watch Codex dispatch persisted request=\(routing.requestID) "
                        + "action=\(routing.action.rawValue) task=\(routing.taskID)"
                )
            } catch {
                AppLogger.ai.error(
                    "Watch Codex incoming handoff could not be committed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func processPendingDispatches() async {
        guard !pending.isEmpty else { return }

        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "Watch Codex dispatch"
        ) { [weak self] in
            Task { @MainActor in
                self?.resumeTask?.cancel()
            }
        }
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }

        let requestIDs = pending.map(\.id)
        for requestID in requestIDs where !Task.isCancelled {
            await process(requestID: requestID)
        }

        if !pending.isEmpty {
            scheduleBackgroundResume()
        }
    }

    private func process(requestID: UUID) async {
        guard var record = record(id: requestID) else { return }

        do {
            guard let activeHostID = bridge.activePairedMacID else {
                throw DispatchError.hostUnavailable
            }
            guard activeHostID == record.hostID else {
                throw DispatchError.hostMismatch
            }

            if record.stage == .received {
                sendUpdate(for: record, status: "running", detail: "Transcribing…")
                let transcript = try await transcribe(audioURL(for: record))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { throw DispatchError.emptyTranscript }
                record.transcript = transcript
                record.stage = .transcribed
                record.updatedAt = .now
                record.lastError = nil
                replace(record)
            }

            if record.stage == .transcribed {
                guard let transcript = record.transcript else {
                    throw DispatchError.emptyTranscript
                }
                let action = record.action ?? .continueTask
                sendUpdate(
                    for: record,
                    status: "running",
                    detail: action == .newTask
                        ? "Creating a fresh Codex task…"
                        : "Continuing \(record.taskTitle ?? "the selected task")…"
                )
                let receipt: CodexTurnJob
                switch action {
                case .continueTask:
                    receipt = try await CodexLaneStore.shared.dispatchFromWatchToTask(
                        instruction: transcript,
                        taskID: record.anchorTaskID,
                        taskTitle: record.taskTitle,
                        projectDirectory: record.projectDirectory,
                        expectedHostID: record.hostID,
                        submissionID: record.id
                    )
                case .newTask:
                    receipt = try await CodexLaneStore.shared.dispatchFromWatch(
                        instruction: transcript,
                        taskID: record.anchorTaskID,
                        projectDirectory: record.projectDirectory,
                        expectedHostID: record.hostID,
                        submissionID: record.id
                    )
                }
                record.jobID = receipt.id
                record.createdTaskID = receipt.taskId
                record.stage = .submitted
                record.updatedAt = .now
                record.lastError = nil
                replace(record)
                sendUpdate(
                    for: record,
                    status: receipt.status == "queued" ? "queued" : "running",
                    detail: receipt.status == "queued"
                        ? (action == .newTask
                            ? "New task queued on the Mac."
                            : "Message queued in the selected task.")
                        : (action == .newTask
                            ? "New task is running."
                            : "Selected task is running.")
                )
                if await handleTerminal(receipt, record: record) {
                    return
                }
                try await pollForTerminalReceipt(record: record)
                return
            }

            guard let jobID = record.jobID else { throw DispatchError.missingReceipt }
            let job = try await bridge.codexTurnStatus(jobId: jobID)
            if await handleTerminal(job, record: record) {
                return
            }
            try await pollForTerminalReceipt(record: record)
        } catch {
            guard var latest = self.record(id: requestID) else { return }
            latest.attemptCount += 1
            latest.updatedAt = .now
            latest.lastError = error.localizedDescription

            if Self.isRetryable(error) {
                replace(latest)
                sendUpdate(
                    for: latest,
                    status: "queued",
                    detail: "Saved on iPhone. Waiting to reconnect to the Mac."
                )
                AppLogger.ai.info(
                    "Watch Codex dispatch deferred request=\(requestID) attempt=\(latest.attemptCount): "
                        + error.localizedDescription
                )
            } else {
                AppLogger.ai.warning(
                    "Watch Codex dispatch failed request=\(requestID): \(error.localizedDescription)"
                )
                sendUpdate(for: latest, status: "failed", detail: error.localizedDescription)
                remove(latest)
            }
        }
    }

    /// Keeps the phone alive just long enough to relay the usual short Codex
    /// response back to Watch. Longer turns remain in the durable inbox and
    /// resume through the existing foreground/BGAppRefresh paths.
    private func pollForTerminalReceipt(record: WatchCodexPendingDispatch) async throws {
        for _ in 0..<20 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))

            guard UIApplication.shared.applicationState == .active
                    || UIApplication.shared.backgroundTimeRemaining > 3,
                  let latest = self.record(id: record.id),
                  latest.stage == .submitted,
                  let jobID = latest.jobID else {
                return
            }

            let job = try await bridge.codexTurnStatus(jobId: jobID)
            if await handleTerminal(job, record: latest) {
                return
            }
        }
    }

    @discardableResult
    private func handleTerminal(
        _ job: CodexTurnJob,
        record: WatchCodexPendingDispatch
    ) async -> Bool {
        switch job.status {
        case "completed":
            sendUpdate(
                for: record,
                status: "completed",
                detail: job.response ?? "Instruction delivered."
            )
            AppLogger.ai.info(
                "Watch Codex dispatch completed action="
                    + "\((record.action ?? .continueTask).rawValue) anchor=\(record.anchorTaskID) "
                    + "targetTask=\(job.taskId)"
            )
            remove(record)
            return true
        case "failed" where job.retryable == true:
            guard var latest = self.record(id: record.id) else { return true }
            latest.attemptCount += 1
            latest.updatedAt = .now
            latest.lastError = job.error ?? job.hint
            // Re-submit the same durable submission ID on the next resume.
            // The Mac retains the created task/accepted-turn boundary and
            // restarts only retryable work, so this cannot create a duplicate.
            latest.stage = .transcribed
            latest.jobID = nil
            replace(latest)
            sendUpdate(
                for: latest,
                status: "queued",
                detail: "Saved on iPhone. Waiting for the Mac to become available."
            )
            AppLogger.ai.info(
                "Watch Codex dispatch retained retryable receipt request=\(record.id) "
                    + "job=\(job.id) attempt=\(latest.attemptCount)"
            )
            return true
        case "failed", "blocked", "unknown":
            sendUpdate(
                for: record,
                status: "failed",
                detail: job.error ?? job.hint ?? "Codex could not complete the instruction."
            )
            remove(record)
            return true
        default:
            // Completion is owned by the durable Mac receipt. The phone will
            // poll it again on the next foreground/background opportunity.
            return false
        }
    }

    private func audioURL(for record: WatchCodexPendingDispatch) -> URL {
        URL.documentsDirectory
            .appending(path: "WatchAudio", directoryHint: .isDirectory)
            .appending(path: record.audioFilename)
    }

    private func transcribe(_ audioURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DispatchError.audioMissing
        }
        let byteCount = try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        AppLogger.ai.info(
            "Watch Codex transcription opening \(audioURL.lastPathComponent) (\(byteCount) bytes)"
        )
        return try await withCheckedThrowingContinuation { continuation in
            TranscriptionService.shared.transcribe(audioURL: audioURL, useCase: .memo) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func record(id: UUID) -> WatchCodexPendingDispatch? {
        pending.first { $0.id == id }
    }

    private func replace(_ record: WatchCodexPendingDispatch) {
        guard let index = pending.firstIndex(where: { $0.id == record.id }) else { return }
        pending[index] = record
        persist()
    }

    private func remove(_ record: WatchCodexPendingDispatch) {
        pending.removeAll { $0.id == record.id }
        persist()
        try? FileManager.default.removeItem(at: audioURL(for: record))
    }

    private static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "WatchCodex", directoryHint: .isDirectory)
            .appending(path: "pending-dispatches.json")
    }

    nonisolated static var incomingStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "WatchCodex", directoryHint: .isDirectory)
            .appending(path: "Incoming", directoryHint: .isDirectory)
    }

    private func persist() {
        do {
            try store.save(pending)
        } catch {
            AppLogger.ai.error("Watch Codex inbox could not be saved: \(error.localizedDescription)")
        }
    }

    private func scheduleBackgroundResume() {
        let request = BGAppRefreshTaskRequest(identifier: talkieApp.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.ai.debug("Watch Codex background resume was not scheduled: \(error.localizedDescription)")
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        // Background-task expiration cancels the active resume task. That is a
        // scheduling interruption, not a terminal delivery failure: keep the
        // persisted inbox entry so the next WatchConnectivity, foreground, or
        // BGAppRefresh window can continue from its last durable stage.
        if error is CancellationError { return true }
        if error is URLError { return true }
        if let dispatchError = error as? DispatchError {
            return dispatchError == .hostUnavailable
        }
        if let dispatchError = error as? CodexDispatchError {
            switch dispatchError {
            case .noActiveHost, .unavailableTask:
                return true
            case .emptyInstruction, .hostMismatch, .invalidProject, .projectMismatch:
                return false
            }
        }
        guard let bridgeError = error as? BridgeError else { return false }
        switch bridgeError {
        case .notConfigured, .connectionFailed:
            return true
        case .httpError(let status, _):
            return status == 408 || status == 425 || status == 429 || (500..<600).contains(status)
        default:
            return false
        }
    }

    private func sendUpdate(
        for record: WatchCodexPendingDispatch,
        status: String,
        detail: String
    ) {
        sendUpdate(
            requestID: record.id.uuidString,
            hostID: record.hostID,
            taskID: record.anchorTaskID,
            status: status,
            detail: detail
        )
    }

    private func sendUpdate(
        requestID: String,
        hostID: String,
        taskID: String,
        status: String,
        detail: String
    ) {
        watchSession.sendCodexDispatchUpdate(
            requestID: requestID,
            hostID: hostID,
            taskID: taskID,
            status: status,
            detail: detail
        )
    }

    private func sendFailureIfAddressable(_ metadata: [String: Any], detail: String) {
        guard let requestID = nonemptyString(metadata["requestID"]),
              let hostID = nonemptyString(metadata["hostID"]),
              let taskID = nonemptyString(metadata["taskID"]) else { return }
        sendUpdate(
            requestID: requestID,
            hostID: hostID,
            taskID: taskID,
            status: "failed",
            detail: detail
        )
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum DispatchError: LocalizedError, Equatable {
        case audioMissing
        case emptyTranscript
        case hostUnavailable
        case hostMismatch
        case missingReceipt

        var errorDescription: String? {
            switch self {
            case .audioMissing:
                return "The saved Watch recording is missing."
            case .emptyTranscript:
                return "Talkie could not hear an instruction."
            case .hostUnavailable:
                return "The selected Mac is not connected yet."
            case .hostMismatch:
                return "The selected Mac changed. Pick the channel again."
            case .missingReceipt:
                return "The Mac did not return a durable Codex receipt."
            }
        }
    }
}
