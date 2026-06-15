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

extension Notification.Name {
    static let watchTransferAssumedSuccess = Notification.Name("watchTransferAssumedSuccess")
}

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

// MARK: - Watch Session Manager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    @Published var lastSentStatus: SendStatus = .idle
    @Published var recentMemos: [WatchMemo] = []

    private let maxRecentMemos = 10

    enum SendStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    private var session: WCSession?
    private var currentMemoId: UUID?
    private var sendingTimeoutTask: Task<Void, Never>?
    private var aiAudioPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        loadRecentMemos()

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

        guard let session = session, session.activationState == .activated else {
            WatchConsole.info("⌚️ [Watch] ❌ Session not activated")
            lastSentStatus = .failed("Watch not connected")
            return
        }

        // Create memo entry
        var memo = WatchMemo(duration: duration)
        memo.presetId = preset?.id
        memo.presetName = preset?.name
        currentMemoId = memo.id
        recentMemos.insert(memo, at: 0)

        // Trim to max count
        if recentMemos.count > maxRecentMemos {
            recentMemos = Array(recentMemos.prefix(maxRecentMemos))
        }
        saveRecentMemos()

        WatchConsole.info("⌚️ [Watch] Session state: \(session.activationState.rawValue), reachable: \(session.isReachable)")

        // Build metadata
        var metadata: [String: Any] = [
            "type": "audio",
            "timestamp": memo.timestamp.timeIntervalSince1970,
            "memoId": memo.id.uuidString,
            "duration": duration
        ]

        // Add preset info if present
        if let preset = preset {
            metadata["presetId"] = preset.id
            metadata["presetName"] = preset.name
            if let workflowId = preset.workflowId {
                metadata["workflowId"] = workflowId
            }
            if let intent = preset.intent {
                metadata["intent"] = intent
            }
        }

        // Flag for the phone-side intent classifier. Phone reads
        // transcript and picks memo vs Ask AI when this is true and no
        // explicit `intent` was sent.
        if autoRoute {
            metadata["autoRoute"] = true
        }

        guard session.isReachable else {
            // iPhone not reachable - queue for background transfer
            WatchConsole.info("⌚️ [Watch] iPhone not reachable, using background transfer")
            transferInBackground(fileURL: fileURL, memoId: memo.id, metadata: metadata)
            return
        }

        lastSentStatus = .sending
        WatchConsole.info("⌚️ [Watch] 📤 Sending file to iPhone...")

        // Send immediately if reachable
        session.transferFile(fileURL, metadata: metadata)
        WatchConsole.info("⌚️ [Watch] transferFile() called")

        // Start timeout in case delegate doesn't fire
        startSendingTimeout(memoId: memo.id)
    }

    private func transferInBackground(fileURL: URL, memoId: UUID, metadata: [String: Any]) {
        guard let session = session else { return }

        lastSentStatus = .sending

        // Add background flag to metadata
        var bgMetadata = metadata
        bgMetadata["background"] = true

        session.transferFile(fileURL, metadata: bgMetadata)

        // Start timeout in case delegate doesn't fire
        startSendingTimeout(memoId: memoId)
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

    /// Start a timeout that assumes success if we don't hear back
    private func startSendingTimeout(memoId: UUID) {
        sendingTimeoutTask?.cancel()
        sendingTimeoutTask = Task { @MainActor in
            do {
                // Wait 5 seconds for callback
                try await Task.sleep(nanoseconds: 5_000_000_000)

                // If still sending, assume it went through (queued by system)
                if lastSentStatus == .sending {
                    WatchConsole.info("⌚️ [Watch] ⏰ Timeout - assuming transfer queued")
                    lastSentStatus = .sent
                    updateMemoStatus(memoId, status: .sent)

                    // Trigger success animation
                    NotificationCenter.default.post(name: .watchTransferAssumedSuccess, object: nil)

                    // Reset after delay
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if lastSentStatus == .sent {
                        lastSentStatus = .idle
                    }
                }
            } catch {
                // Task cancelled - callback arrived, ignore
            }
        }
    }

    private func cancelSendingTimeout() {
        sendingTimeoutTask?.cancel()
        sendingTimeoutTask = nil
    }

    func handleMemoUpdate(memoId: String, status: String, preview: String?) {
        guard let uuid = UUID(uuidString: memoId),
              let memoStatus = WatchMemo.MemoStatus(rawValue: status) else { return }
        updateMemoStatus(uuid, status: memoStatus, preview: preview)
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
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            let device = WKInterfaceDevice.current()
            WatchConsole.info("⌚️ [Watch] Reachability → \(session.isReachable) | Companion: \(session.isCompanionAppInstalled) | Watch: \(device.name)")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            // Cancel timeout - delegate fired
            self.cancelSendingTimeout()

            let metadata = fileTransfer.file.metadata ?? [:]
            let memoIdString = metadata["memoId"] as? String

            if let error = error {
                WatchConsole.info("⌚️ [Watch] ❌ File transfer FAILED: \(error.localizedDescription)")
                self.lastSentStatus = .failed(error.localizedDescription)

                // Update memo status
                if let memoIdString, let memoId = UUID(uuidString: memoIdString) {
                    self.updateMemoStatus(memoId, status: .failed)
                }
            } else {
                let file = fileTransfer.file
                WatchConsole.info("⌚️ [Watch] ✅ File transfer complete!")
                WatchConsole.info("⌚️ [Watch]    File: \(file.fileURL.lastPathComponent)")
                WatchConsole.info("⌚️ [Watch]    Metadata: \(metadata)")
                self.lastSentStatus = .sent

                // Update memo status to sent
                if let memoIdString, let memoId = UUID(uuidString: memoIdString) {
                    self.updateMemoStatus(memoId, status: .sent)
                }

                // Reset status after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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

            if let type = message["type"] as? String, type == "memoUpdate",
               let memoId = message["memoId"] as? String,
               let status = message["status"] as? String {
                let preview = message["preview"] as? String
                self.handleMemoUpdate(memoId: memoId, status: status, preview: preview)
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
        }
    }
}
