//
//  WatchSessionManager.swift
//  TalkieWatch
//
//  Handles WatchConnectivity communication with iPhone
//

import Foundation
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
        case transcribed   // Transcription complete
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

    /// Send audio file to iPhone for transcription
    func sendAudio(fileURL: URL, duration: TimeInterval = 0, preset: WatchPreset? = nil) {
        print("⌚️ [Watch] sendAudio called with: \(fileURL.lastPathComponent), preset: \(preset?.name ?? "none")")
        print("⌚️ [Watch] File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")

        guard let session = session, session.activationState == .activated else {
            print("⌚️ [Watch] ❌ Session not activated")
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

        print("⌚️ [Watch] Session state: \(session.activationState.rawValue), reachable: \(session.isReachable)")

        // Build metadata
        var metadata: [String: Any] = [
            "type": "audio",
            "timestamp": Date().timeIntervalSince1970,
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
        }

        guard session.isReachable else {
            // iPhone not reachable - queue for background transfer
            print("⌚️ [Watch] iPhone not reachable, using background transfer")
            transferInBackground(fileURL: fileURL, memoId: memo.id, metadata: metadata)
            return
        }

        lastSentStatus = .sending
        print("⌚️ [Watch] 📤 Sending file to iPhone...")

        // Send immediately if reachable
        session.transferFile(fileURL, metadata: metadata)
        print("⌚️ [Watch] transferFile() called")

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
                    print("⌚️ [Watch] ⏰ Timeout - assuming transfer queued")
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
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("⌚️ [Watch] Session activation failed: \(error.localizedDescription)")
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

                print("⌚️ [Watch] ========== SESSION INFO ==========")
                print("⌚️ [Watch] Watch Name: \(device.name)")
                print("⌚️ [Watch] Watch Model: \(device.model)")
                print("⌚️ [Watch] Watch OS: \(device.systemVersion)")
                print("⌚️ [Watch] Watch Bundle ID: \(watchBundleID)")
                print("⌚️ [Watch] Expected iOS Bundle: \(expectedCompanionID)")
                print("⌚️ [Watch] State: \(stateStr)")
                print("⌚️ [Watch] Reachable: \(session.isReachable)")
                print("⌚️ [Watch] Companion installed: \(session.isCompanionAppInstalled)")
                print("⌚️ [Watch] Outstanding transfers: \(session.outstandingFileTransfers.count)")
                print("⌚️ [Watch] =====================================")
                self.isReachable = session.isReachable
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            let device = WKInterfaceDevice.current()
            print("⌚️ [Watch] Reachability → \(session.isReachable) | Companion: \(session.isCompanionAppInstalled) | Watch: \(device.name)")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            // Cancel timeout - delegate fired
            self.cancelSendingTimeout()

            let metadata = fileTransfer.file.metadata ?? [:]
            let memoIdString = metadata["memoId"] as? String

            if let error = error {
                print("⌚️ [Watch] ❌ File transfer FAILED: \(error.localizedDescription)")
                self.lastSentStatus = .failed(error.localizedDescription)

                // Update memo status
                if let memoIdString, let memoId = UUID(uuidString: memoIdString) {
                    self.updateMemoStatus(memoId, status: .failed)
                }
            } else {
                let file = fileTransfer.file
                print("⌚️ [Watch] ✅ File transfer complete!")
                print("⌚️ [Watch]    File: \(file.fileURL.lastPathComponent)")
                print("⌚️ [Watch]    Metadata: \(metadata)")
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
            print("⌚️ [Watch] 📩 Received message: \(message)")

            if let type = message["type"] as? String, type == "memoUpdate",
               let memoId = message["memoId"] as? String,
               let status = message["status"] as? String {
                let preview = message["preview"] as? String
                self.handleMemoUpdate(memoId: memoId, status: status, preview: preview)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            print("⌚️ [Watch] 📩 Received application context: \(applicationContext)")

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
