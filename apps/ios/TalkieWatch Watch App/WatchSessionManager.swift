//
//  WatchSessionManager.swift
//  TalkieWatch
//
//  Handles WatchConnectivity communication with iPhone
//

import Foundation
import AVFoundation
import WatchConnectivity
import WatchKit

// MARK: - Watch Memo Model

struct WatchMemo: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    var status: MemoStatus
    var transcriptionPreview: String?
    var presetId: String?
    var presetName: String?

    enum MemoStatus: String, Codable {
        case sending
        case sent
        case received      // iPhone received it
        case thinking      // iPhone is transcribing or answering
        case transcribed   // Transcription complete
        case answered      // AI answer is ready
        case failed
    }

    init(duration: TimeInterval) {
        self.id = UUID()
        self.timestamp = Date()
        self.duration = duration
        self.status = .sending
        self.transcriptionPreview = nil
        self.presetId = nil
        self.presetName = nil
    }
}

private struct PendingAudioTransfer: Codable, Identifiable {
    let id: UUID
    let memoID: UUID
    let audioFilename: String
    let metadataData: Data
    let createdAt: Date
    var transferCompletedAt: Date?
}

// MARK: - Watch Session Manager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    @Published var lastSentStatus: SendStatus = .idle
    @Published var recentMemos: [WatchMemo] = []
    @Published private(set) var codexSnapshot: CodexWatchSnapshot?
    @Published private(set) var selectedCodexTaskID: String?
    @Published private(set) var codexDispatchReceipt: CodexWatchDispatchReceipt? {
        didSet { saveCodexDispatchReceipt() }
    }

    private let maxRecentMemos = 10
    private let selectedCodexTaskKey = "watch.codex.selected-task.v1"

    enum SendStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    private var session: WCSession?
    private var pendingAudioTransfers: [PendingAudioTransfer] = []
    private var aiAudioPlayer: AVAudioPlayer?

    var codexChannels: [CodexWatchChannel] {
        codexSnapshot?.channels ?? []
    }

    var selectedCodexChannel: CodexWatchChannel? {
        guard let selectedCodexTaskID else { return nil }
        return codexChannels.first { $0.taskID == selectedCodexTaskID }
    }

    private override init() {
        super.init()
        loadRecentMemos()
        selectedCodexTaskID = UserDefaults.standard.string(forKey: selectedCodexTaskKey)
        loadCodexDispatchReceipt()
        loadPendingAudioTransfers()
        reconcilePendingCodexAudioWithReceipt()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Persistence

    private var memosFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recent_memos.json")
    }

    private func loadRecentMemos() {
        guard let data = try? Data(contentsOf: memosFileURL),
              let memos = try? JSONDecoder().decode([WatchMemo].self, from: data) else {
            return
        }
        recentMemos = memos
    }

    private func saveRecentMemos() {
        guard let data = try? JSONEncoder().encode(recentMemos) else { return }
        try? data.write(to: memosFileURL)
    }

    private var codexReceiptFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codex_dispatch_receipt.json")
    }

    private func loadCodexDispatchReceipt() {
        guard let data = try? Data(contentsOf: codexReceiptFileURL),
              let receipt = try? JSONDecoder().decode(CodexWatchDispatchReceipt.self, from: data) else {
            return
        }
        codexDispatchReceipt = receipt
    }

    private func saveCodexDispatchReceipt() {
        guard let codexDispatchReceipt,
              let data = try? JSONEncoder().encode(codexDispatchReceipt) else {
            try? FileManager.default.removeItem(at: codexReceiptFileURL)
            return
        }
        try? data.write(to: codexReceiptFileURL, options: .atomic)
    }

    private var pendingAudioDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "PendingAudio", directoryHint: .isDirectory)
    }

    private var pendingAudioTransfersFileURL: URL {
        pendingAudioDirectoryURL.appending(path: "transfers.json")
    }

    private func loadPendingAudioTransfers() {
        guard let data = try? Data(contentsOf: pendingAudioTransfersFileURL),
              let transfers = try? JSONDecoder().decode([PendingAudioTransfer].self, from: data) else {
            return
        }
        pendingAudioTransfers = transfers
        WatchConsole.info("⌚️ [Watch] Restored \(transfers.count) pending audio transfer(s)")
    }

    private func savePendingAudioTransfers() throws {
        try FileManager.default.createDirectory(
            at: pendingAudioDirectoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(pendingAudioTransfers)
        try data.write(to: pendingAudioTransfersFileURL, options: .atomic)
    }

    private func persistPendingAudioTransfer(
        fileURL: URL,
        memoID: UUID,
        metadata: [String: Any]
    ) throws -> PendingAudioTransfer {
        let queueID = UUID()
        let extensionName = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
        let audioFilename = queueID.uuidString + "." + extensionName
        let durableAudioURL = pendingAudioDirectoryURL.appending(path: audioFilename)

        try FileManager.default.createDirectory(
            at: pendingAudioDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fileURL, to: durableAudioURL)

        var durableMetadata = metadata
        durableMetadata["queueID"] = queueID.uuidString
        let metadataData = try PropertyListSerialization.data(
            fromPropertyList: durableMetadata,
            format: .binary,
            options: 0
        )
        let transfer = PendingAudioTransfer(
            id: queueID,
            memoID: memoID,
            audioFilename: audioFilename,
            metadataData: metadataData,
            createdAt: Date(),
            transferCompletedAt: nil
        )

        pendingAudioTransfers.append(transfer)
        do {
            try savePendingAudioTransfers()
        } catch {
            pendingAudioTransfers.removeAll { $0.id == queueID }
            try? FileManager.default.removeItem(at: durableAudioURL)
            throw error
        }
        return transfer
    }

    private func metadata(for transfer: PendingAudioTransfer) -> [String: Any]? {
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: transfer.metadataData,
            options: [],
            format: nil
        ) else {
            return nil
        }
        return propertyList as? [String: Any]
    }

    private func flushPendingAudioTransfers() {
        guard let session, session.activationState == .activated else {
            WatchConsole.info("⌚️ [Watch] Audio queue waiting for session activation")
            return
        }

        let outstandingQueueIDs = Set(session.outstandingFileTransfers.compactMap { transfer in
            transfer.file.metadata?["queueID"] as? String
        })

        for transfer in pendingAudioTransfers where !outstandingQueueIDs.contains(transfer.id.uuidString) {
            let audioURL = pendingAudioDirectoryURL.appending(path: transfer.audioFilename)
            guard FileManager.default.fileExists(atPath: audioURL.path),
                  var metadata = metadata(for: transfer) else {
                WatchConsole.info("⌚️ [Watch] ❌ Pending audio is missing or unreadable: \(transfer.id)")
                continue
            }

            // Codex recordings remain durable until the phone sends its own
            // application-level `received` receipt. Suppress rapid duplicate
            // transfers while still retrying if that receipt never arrives.
            if metadata["intent"] as? String == "codex",
               let completedAt = transfer.transferCompletedAt,
               Date().timeIntervalSince(completedAt) < 300 {
                continue
            }

            metadata["background"] = !session.isReachable
            session.transferFile(audioURL, metadata: metadata)
            WatchConsole.info(
                "⌚️ [Watch] Enqueued durable audio \(transfer.id) (reachable: \(session.isReachable))"
            )
        }
    }

    private func completePendingAudioTransfer(queueID: UUID) {
        guard let transfer = pendingAudioTransfers.first(where: { $0.id == queueID }) else {
            return
        }

        pendingAudioTransfers.removeAll { $0.id == queueID }
        do {
            try savePendingAudioTransfers()
            let audioURL = pendingAudioDirectoryURL.appending(path: transfer.audioFilename)
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            pendingAudioTransfers.append(transfer)
            WatchConsole.info("⌚️ [Watch] ❌ Could not commit audio queue completion: \(error.localizedDescription)")
        }
    }

    private func markTransferCompleted(queueID: UUID, at date: Date?) {
        guard let index = pendingAudioTransfers.firstIndex(where: { $0.id == queueID }) else {
            return
        }
        let previous = pendingAudioTransfers[index].transferCompletedAt
        pendingAudioTransfers[index].transferCompletedAt = date
        do {
            try savePendingAudioTransfers()
        } catch {
            pendingAudioTransfers[index].transferCompletedAt = previous
            WatchConsole.info(
                "⌚️ [Watch] ❌ Could not save transfer receipt wait: \(error.localizedDescription)"
            )
        }
    }

    /// A phone receipt is the durable application-level acknowledgement. It
    /// closes the Watch queue even when WatchConnectivity never delivers the
    /// lower-level file-transfer callback before the Watch app is suspended.
    private func acknowledgePendingCodexAudio(with receipt: CodexWatchDispatchReceipt) {
        guard receipt.state.progressRank >= CodexWatchDispatchReceipt.State.received.progressRank else {
            return
        }

        let queueIDs = pendingAudioTransfers.compactMap { transfer -> UUID? in
            guard let metadata = metadata(for: transfer),
                  metadata["intent"] as? String == "codex",
                  metadata["requestID"] as? String == receipt.requestID.uuidString,
                  metadata["hostID"] as? String == receipt.hostID,
                  metadata["taskID"] as? String == receipt.taskID else {
                return nil
            }
            return transfer.id
        }

        for queueID in queueIDs {
            completePendingAudioTransfer(queueID: queueID)
            WatchConsole.info("⌚️ [Watch] Retired acknowledged Codex audio \(queueID)")
        }
    }

    private func reconcilePendingCodexAudioWithReceipt() {
        guard let codexDispatchReceipt else { return }
        acknowledgePendingCodexAudio(with: codexDispatchReceipt)
    }

    /// Send audio file to iPhone for transcription.
    ///
    /// `autoRoute` flags that the phone should classify intent from the
    /// transcript and choose memo vs Ask AI on its own. When `preset`
    /// is provided (e.g. the "ASK AI" pill), the explicit `intent` in
    /// metadata wins and the phone skips classification.
    func sendAudio(
        fileURL: URL,
        duration: TimeInterval = 0,
        preset: WatchPreset? = nil,
        autoRoute: Bool = false
    ) {
        WatchConsole.info("⌚️ [Watch] sendAudio called with: \(fileURL.lastPathComponent), preset: \(preset?.name ?? "none"), autoRoute: \(autoRoute)")
        WatchConsole.info("⌚️ [Watch] File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")

        var routingMetadata: [String: Any] = [:]
        if let preset = preset {
            if let workflowId = preset.workflowId {
                routingMetadata["workflowId"] = workflowId
            }
            if let intent = preset.intent {
                routingMetadata["intent"] = intent
            }
        }

        // Flag for the phone-side intent classifier. Phone reads
        // transcript and picks memo vs Ask AI when this is true and no
        // explicit `intent` was sent.
        if autoRoute {
            routingMetadata["autoRoute"] = true
        }

        enqueueAudio(
            fileURL: fileURL,
            duration: duration,
            presetID: preset?.id,
            presetName: preset?.name,
            routingMetadata: routingMetadata
        )
    }

    /// Transfers a recording to either the selected conversation or an
    /// explicitly requested fresh task in the same project.
    func sendCodexAudio(
        fileURL: URL,
        duration: TimeInterval,
        requestID: UUID,
        hostID: String,
        taskID: String,
        taskTitle: String,
        workingDirectory: String,
        action: CodexWatchDispatchAction
    ) {
        let routingMetadata: [String: Any] = [
            "intent": "codex",
            "requestID": requestID.uuidString,
            "hostID": hostID,
            "taskID": taskID,
            "taskTitle": taskTitle,
            "cwd": workingDirectory,
            "codexAction": action.rawValue
        ]
        WatchConsole.info(
            "⌚️ [Watch] Codex dispatch action=\(action.rawValue) task=\(taskID)"
        )

        enqueueAudio(
            fileURL: fileURL,
            duration: duration,
            presetID: nil,
            presetName: "Codex · \(taskTitle)",
            routingMetadata: routingMetadata,
            codexRequestID: requestID,
            codexHostID: hostID,
            codexTaskID: taskID
        )
    }

    private func enqueueAudio(
        fileURL: URL,
        duration: TimeInterval,
        presetID: String?,
        presetName: String?,
        routingMetadata: [String: Any],
        codexRequestID: UUID? = nil,
        codexHostID: String? = nil,
        codexTaskID: String? = nil
    ) {
        var memo = WatchMemo(duration: duration)
        memo.presetId = presetID
        memo.presetName = presetName
        recentMemos.insert(memo, at: 0)

        if recentMemos.count > maxRecentMemos {
            recentMemos = Array(recentMemos.prefix(maxRecentMemos))
        }
        saveRecentMemos()

        var metadata: [String: Any] = [
            "type": "audio",
            "timestamp": memo.timestamp.timeIntervalSince1970,
            "memoId": memo.id.uuidString,
            "duration": duration
        ]
        if let presetID { metadata["presetId"] = presetID }
        if let presetName { metadata["presetName"] = presetName }
        routingMetadata.forEach { metadata[$0.key] = $0.value }

        do {
            let transfer = try persistPendingAudioTransfer(
                fileURL: fileURL,
                memoID: memo.id,
                metadata: metadata
            )
            WatchConsole.info("⌚️ [Watch] Persisted audio before delivery: \(transfer.id)")
        } catch {
            WatchConsole.info("⌚️ [Watch] ❌ Could not persist audio: \(error.localizedDescription)")
            lastSentStatus = .failed("Could not save recording")
            updateMemoStatus(memo.id, status: .failed)
            if let codexRequestID, let codexHostID, let codexTaskID {
                codexDispatchReceipt = CodexWatchDispatchReceipt(
                    requestID: codexRequestID,
                    hostID: codexHostID,
                    taskID: codexTaskID,
                    state: .failed,
                    detail: "Could not save recording on Watch"
                )
            }
            return
        }

        let isActivated = session?.activationState == .activated
        let isReachable = isActivated && session?.isReachable == true

        if let codexRequestID, let codexHostID, let codexTaskID {
            codexDispatchReceipt = CodexWatchDispatchReceipt(
                requestID: codexRequestID,
                hostID: codexHostID,
                taskID: codexTaskID,
                state: isReachable ? .sending : .queued,
                detail: isReachable ? nil : "Waiting for iPhone delivery"
            )
        }

        lastSentStatus = .sending
        guard isActivated else {
            WatchConsole.info("⌚️ [Watch] Session not activated; durable audio remains queued")
            return
        }

        flushPendingAudioTransfers()
    }

    // MARK: - Memo Updates

    private func updateMemoStatus(_ memoId: UUID, status: WatchMemo.MemoStatus, preview: String? = nil) {
        if let index = recentMemos.firstIndex(where: { $0.id == memoId }) {
            recentMemos[index].status = status
            if let preview = preview {
                recentMemos[index].transcriptionPreview = preview
            }
            saveRecentMemos()
        }
    }

    func handleMemoUpdate(memoId: String, status: String, preview: String?) {
        guard let uuid = UUID(uuidString: memoId),
              let memoStatus = WatchMemo.MemoStatus(rawValue: status) else { return }
        updateMemoStatus(uuid, status: memoStatus, preview: preview)
    }

    // MARK: - Codex State

    func selectCodexChannel(taskID: String) {
        guard taskID != selectedCodexTaskID,
              let snapshot = codexSnapshot,
              snapshot.channels.contains(where: { $0.taskID == taskID }) else {
            return
        }

        selectedCodexTaskID = taskID
        UserDefaults.standard.set(taskID, forKey: selectedCodexTaskKey)
        WatchConsole.info(
            "⌚️ [Watch] Local Codex selection changed task=\(taskID); iPhone UI unchanged"
        )
    }

    private func handleCodexSnapshot(_ propertyList: [String: Any]) {
        guard let snapshot = CodexWatchSnapshot(propertyList: propertyList) else {
            WatchConsole.info("⌚️ [Watch] ❌ Ignored malformed Codex snapshot")
            return
        }

        if let current = codexSnapshot,
           current.hostID == snapshot.hostID,
           snapshot.revision < current.revision {
            WatchConsole.info("⌚️ [Watch] Ignored stale Codex snapshot revision \(snapshot.revision)")
            return
        }

        let previousSelection = selectedCodexTaskID
        codexSnapshot = snapshot

        if let previousSelection,
           snapshot.channels.contains(where: { $0.taskID == previousSelection }) {
            selectedCodexTaskID = previousSelection
        } else {
            selectedCodexTaskID = snapshot.selectedTaskID ?? snapshot.channels.first?.taskID
        }
        if let selectedCodexTaskID {
            UserDefaults.standard.set(selectedCodexTaskID, forKey: selectedCodexTaskKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedCodexTaskKey)
        }

        WatchConsole.info(
            "⌚️ [Watch] Codex snapshot revision \(snapshot.revision), channels: \(snapshot.channels.count)"
        )
    }

    private func handleCodexDispatchUpdate(_ propertyList: [String: Any]) {
        guard let update = CodexWatchDispatchReceipt(propertyList: propertyList) else {
            WatchConsole.info("⌚️ [Watch] ❌ Ignored malformed Codex dispatch update")
            return
        }

        // Retire the durable transfer before the display-state monotonicity
        // guard. A repeated or older `received` update is still a valid
        // acknowledgement for the exact request/host/task tuple.
        acknowledgePendingCodexAudio(with: update)

        guard let current = codexDispatchReceipt,
              current.requestID == update.requestID,
              current.hostID == update.hostID,
              current.taskID == update.taskID,
              !current.state.isTerminal,
              update.state.progressRank >= current.state.progressRank,
              update.updatedAt >= current.updatedAt else {
            WatchConsole.info("⌚️ [Watch] Ignored stale or mismatched Codex dispatch update")
            return
        }

        codexDispatchReceipt = update
    }

    private func handleAIAudio(fileURL: URL, metadata: [String: Any]) {
        do {
            let audioURL = FileManager.default.temporaryDirectory
                .appending(path: "talkie-ai-answer-\(UUID().uuidString)")
                .appendingPathExtension("mp3")
            try? FileManager.default.removeItem(at: audioURL)
            try FileManager.default.moveItem(at: fileURL, to: audioURL)

            if let memoId = metadata["memoId"] as? String {
                handleMemoUpdate(
                    memoId: memoId,
                    status: "answered",
                    preview: metadata["preview"] as? String
                )
            }

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            aiAudioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            aiAudioPlayer?.prepareToPlay()
            aiAudioPlayer?.play()
            WatchConsole.info("⌚️ [Watch] 🔊 Playing AI answer on Watch")
        } catch {
            WatchConsole.info("⌚️ [Watch] ❌ AI audio playback failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                WatchConsole.info("⌚️ [Watch] Session activation failed: \(error.localizedDescription)")
            } else {
                let stateStr = switch activationState {
                    case .notActivated: "notActivated"
                    case .inactive: "inactive"
                    case .activated: "activated"
                    @unknown default: "unknown"
                }
                let device = WKInterfaceDevice.current()
                let watchBundleID = Bundle.main.bundleIdentifier ?? "unknown"
                let expectedCompanionID = watchBundleID.replacingOccurrences(of: ".watchkitapp", with: "")

                WatchConsole.info("⌚️ [Watch] ========== SESSION INFO ==========")
                WatchConsole.info("⌚️ [Watch] Watch Name: \(device.name)")
                WatchConsole.info("⌚️ [Watch] Watch Model: \(device.model)")
                WatchConsole.info("⌚️ [Watch] Watch OS: \(device.systemVersion)")
                WatchConsole.info("⌚️ [Watch] Watch Bundle ID: \(watchBundleID)")
                WatchConsole.info("⌚️ [Watch] Expected iOS Bundle: \(expectedCompanionID)")
                WatchConsole.info("⌚️ [Watch] State: \(stateStr)")
                WatchConsole.info("⌚️ [Watch] Reachable: \(session.isReachable)")
                WatchConsole.info("⌚️ [Watch] Companion installed: \(session.isCompanionAppInstalled)")
                WatchConsole.info("⌚️ [Watch] Outstanding transfers: \(session.outstandingFileTransfers.count)")
                WatchConsole.info("⌚️ [Watch] =====================================")
                self.isReachable = session.isReachable
                if activationState == .activated {
                    self.flushPendingAudioTransfers()
                }
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.flushPendingAudioTransfers()
            let device = WKInterfaceDevice.current()
            WatchConsole.info("⌚️ [Watch] Reachability → \(session.isReachable) | Companion: \(session.isCompanionAppInstalled) | Watch: \(device.name)")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            let metadata = fileTransfer.file.metadata ?? [:]
            let memoIdString = metadata["memoId"] as? String
            let queueID = (metadata["queueID"] as? String).flatMap(UUID.init(uuidString:))
            let isCodexDispatch = metadata["intent"] as? String == "codex"
            let codexRequestID = (metadata["requestID"] as? String).flatMap(UUID.init(uuidString:))

            if let error = error {
                WatchConsole.info("⌚️ [Watch] ❌ File transfer FAILED: \(error.localizedDescription)")
                self.lastSentStatus = .sending
                if let queueID {
                    self.markTransferCompleted(queueID: queueID, at: nil)
                }

                if isCodexDispatch,
                   let codexRequestID,
                   let receipt = self.codexDispatchReceipt,
                   receipt.requestID == codexRequestID,
                   receipt.state.progressRank <= CodexWatchDispatchReceipt.State.queued.progressRank {
                    self.codexDispatchReceipt = CodexWatchDispatchReceipt(
                        requestID: receipt.requestID,
                        hostID: receipt.hostID,
                        taskID: receipt.taskID,
                        state: .queued,
                        detail: "Delivery interrupted; will retry"
                    )
                }
            } else {
                let file = fileTransfer.file
                WatchConsole.info("⌚️ [Watch] ✅ File transfer complete!")
                WatchConsole.info("⌚️ [Watch]    File: \(file.fileURL.lastPathComponent)")
                WatchConsole.info("⌚️ [Watch]    Metadata: \(metadata)")
                if let queueID, isCodexDispatch {
                    self.markTransferCompleted(queueID: queueID, at: .now)
                } else if let queueID {
                    self.completePendingAudioTransfer(queueID: queueID)
                }
                self.lastSentStatus = .sent

                // Update memo status to sent
                if let memoIdString, let memoId = UUID(uuidString: memoIdString) {
                    self.updateMemoStatus(memoId, status: .sent)
                }
                if isCodexDispatch,
                   let codexRequestID,
                   let receipt = self.codexDispatchReceipt,
                   receipt.requestID == codexRequestID,
                   receipt.state.progressRank < CodexWatchDispatchReceipt.State.received.progressRank {
                    self.codexDispatchReceipt = CodexWatchDispatchReceipt(
                        requestID: receipt.requestID,
                        hostID: receipt.hostID,
                        taskID: receipt.taskID,
                        state: .transferred,
                        detail: "Audio transferred; awaiting durable phone receipt"
                    )
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))
                if self.lastSentStatus == .sent {
                    self.lastSentStatus = .idle
                }
            }
        }
    }

    // Handle messages from iPhone (memo status updates)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            WatchConsole.info("⌚️ [Watch] 📩 Received message: \(message)")

            switch message["type"] as? String {
            case "memoUpdate":
                if let memoId = message["memoId"] as? String,
                   let status = message["status"] as? String {
                    let preview = message["preview"] as? String
                    self.handleMemoUpdate(memoId: memoId, status: status, preview: preview)
                }
            case "codexSnapshot":
                self.handleCodexSnapshot(message)
            case "codexDispatchUpdate":
                self.handleCodexDispatchUpdate(message)
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard metadata["type"] as? String == "aiAudio" else {
            return
        }

        Task { @MainActor in
            self.handleAIAudio(fileURL: file.fileURL, metadata: metadata)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            WatchConsole.info("⌚️ [Watch] 📩 Received application context: \(applicationContext)")

            // Handle bulk memo updates from iPhone
            if let updates = applicationContext["memoUpdates"] as? [[String: Any]] {
                for update in updates {
                    if let memoId = update["memoId"] as? String,
                       let status = update["status"] as? String {
                        let preview = update["preview"] as? String
                        self.handleMemoUpdate(memoId: memoId, status: status, preview: preview)
                    }
                }
            }

            if let snapshot = applicationContext["codexSnapshot"] as? [String: Any] {
                self.handleCodexSnapshot(snapshot)
            } else if applicationContext["type"] as? String == "codexSnapshot" {
                self.handleCodexSnapshot(applicationContext)
            }

            if let update = applicationContext["codexDispatchUpdate"] as? [String: Any] {
                self.handleCodexDispatchUpdate(update)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            switch userInfo["type"] as? String {
            case "codexDispatchUpdate":
                self.handleCodexDispatchUpdate(userInfo)
            case "memoUpdate":
                if let memoID = userInfo["memoId"] as? String,
                   let status = userInfo["status"] as? String {
                    self.handleMemoUpdate(
                        memoId: memoID,
                        status: status,
                        preview: userInfo["preview"] as? String
                    )
                }
            default:
                break
            }
        }
    }
}
