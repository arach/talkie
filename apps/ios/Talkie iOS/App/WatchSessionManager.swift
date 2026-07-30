//
//  WatchSessionManager.swift
//  Talkie iOS
//
//  Receives audio from Apple Watch and queues for transcription.
//  Uses lazy activation - only activates WCSession when explicitly requested,
//  avoiding framework noise when no watch app is installed.
//

import Foundation
import WatchConnectivity
import UIKit
import TalkieMobileKit

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private enum Keys {
        static let codexSnapshotRevision = "watch.codex.snapshot.revision.v1"
        static let codexSnapshotSignature = "watch.codex.snapshot.signature.v1"
    }

    private let log = Log(.system)

    @Published var isWatchReachable = false
    @Published var isWatchAppInstalled = false
    @Published var pendingTransfers = 0
    @Published private(set) var isActivated = false

    private var session: WCSession?
    private var codexSnapshotRevision: Int
    private var codexSnapshotSignature: String?

    private override init() {
        codexSnapshotRevision = UserDefaults.standard.integer(forKey: Keys.codexSnapshotRevision)
        codexSnapshotSignature = UserDefaults.standard.string(forKey: Keys.codexSnapshotSignature)
        super.init()
        // Don't activate immediately - wait for explicit activation request
        // This avoids WCSession framework noise when watch app isn't installed
    }

    /// Activate the watch session. Call this when watch connectivity is needed.
    /// Safe to call multiple times - only activates once.
    func activateIfNeeded() {
        guard !isActivated else { return }
        guard WCSession.isSupported() else {
            log.debug("WCSession not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
        isActivated = true
    }

    /// Called when audio is received from Watch
    var onAudioReceived: ((URL, [String: Any]) -> Void)?

    func sendMemoUpdate(memoId: String, status: String, preview: String? = nil) {
        activateIfNeeded()

        guard let session, session.activationState == .activated else {
            log.debug("Watch memo update skipped; session is not activated")
            return
        }

        var update: [String: Any] = [
            "type": "memoUpdate",
            "memoId": memoId,
            "status": status
        ]

        if let preview {
            update["preview"] = String(preview.prefix(240))
        }

        if session.isReachable {
            session.sendMessage(update, replyHandler: nil) { [log] error in
                log.debug("Watch memo update send failed: \(error.localizedDescription)")
            }
        }

        do {
            var context = session.applicationContext
            context["memoUpdates"] = [update]
            try session.updateApplicationContext(context)
        } catch {
            log.debug("Watch memo update context failed: \(error.localizedDescription)")
        }
    }

    /// Publishes the bounded Codex channel snapshot used by the Watch picker.
    /// Application context is the durable last-known value; the immediate
    /// message keeps an open Watch view responsive.
    func publishCodexSnapshot(_ snapshot: [String: Any]) {
        activateIfNeeded()

        guard let session, session.activationState == .activated else {
            log.debug("Watch Codex snapshot skipped; session is not activated")
            return
        }

        var message = snapshot
        message["type"] = "codexSnapshot"

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [log] error in
                log.debug("Watch Codex snapshot send failed: \(error.localizedDescription)")
            }
        }

        do {
            var context = session.applicationContext
            context["codexSnapshot"] = snapshot
            try session.updateApplicationContext(context)
        } catch {
            log.debug("Watch Codex snapshot context failed: \(error.localizedDescription)")
        }
    }

    /// Rebuilds the bounded Watch conversation catalogue from the phone's
    /// authoritative task state. Watch keeps its own selection; the phone's
    /// selection is only the initial default when Watch has none.
    func publishCurrentCodexSnapshot() {
        let bridge = BridgeManager.shared
        let store = CodexLaneStore.shared
        let hostID = bridge.activePairedMacID ?? ""

        var seenTaskIDs = Set<String>()
        var tasks: [CodexTaskSummary] = []
        if let selected = store.selectedTask,
           seenTaskIDs.insert(selected.id).inserted {
            tasks.append(selected)
        }
        for lane in store.sortedLanes
        where seenTaskIDs.insert(lane.task.id).inserted {
            tasks.append(lane.task)
        }
        for task in store.catalog
        where seenTaskIDs.insert(task.id).inserted {
            tasks.append(task)
        }

        let channels: [[String: Any]] = tasks.prefix(20).map { task in
            let lane = store.sortedLanes.first(where: { $0.task.id == task.id })
            let status: String
            if let lane, store.isTurnInFlight(on: lane.number) {
                status = "running"
            } else if let lane, store.queuedMessageCount(for: lane.number) > 0 {
                status = "queued"
            } else if store.selectedTask?.id == task.id && store.selectedDestinationIsInFlight {
                status = "running"
            } else {
                status = "ready"
            }
            return [
                "taskID": task.id,
                "title": task.title,
                "project": task.projectName,
                "cwd": task.canonicalWorkingDirectory,
                "status": status,
                "updatedAt": task.updatedAt,
            ]
        }

        let selectedTaskID = store.selectedTask?.id
        let signature = ([hostID, selectedTaskID ?? ""] + channels.flatMap { channel in
            [
                channel["taskID"] as? String ?? "",
                channel["title"] as? String ?? "",
                channel["status"] as? String ?? "",
                channel["cwd"] as? String ?? "",
            ]
        }).joined(separator: "\u{1F}")
        if signature != codexSnapshotSignature {
            codexSnapshotRevision += 1
            codexSnapshotSignature = signature
            UserDefaults.standard.set(codexSnapshotRevision, forKey: Keys.codexSnapshotRevision)
            UserDefaults.standard.set(signature, forKey: Keys.codexSnapshotSignature)
        }
        var snapshot: [String: Any] = [
            "revision": codexSnapshotRevision,
            "hostID": hostID,
            "channels": channels,
        ]
        if let selectedTaskID {
            snapshot["selectedTaskID"] = selectedTaskID
        }
        publishCodexSnapshot(snapshot)
    }

    /// Refreshes projects without depending on the iPhone mapper being on
    /// screen. WCSession can wake the phone in the background, so the Watch
    /// should be able to obtain a current project snapshot from that wake alone.
    private func refreshCurrentCodexSnapshot() async {
        let store = CodexLaneStore.shared
        if !store.isLoadingCatalog {
            await store.refreshCatalog()
        }
        // `refreshCatalog()` publishes on success. Publish again here so an
        // offline refresh still sends the durable last-known project list.
        publishCurrentCodexSnapshot()
    }

    /// Sends one state transition for a Watch-originated fresh-task dispatch.
    func sendCodexDispatchUpdate(
        requestID: String,
        hostID: String,
        taskID: String,
        status: String,
        detail: String? = nil
    ) {
        activateIfNeeded()

        guard let session, session.activationState == .activated else {
            log.debug("Watch Codex update skipped; session is not activated")
            return
        }

        var update: [String: Any] = [
            "type": "codexDispatchUpdate",
            "requestID": requestID,
            "hostID": hostID,
            "taskID": taskID,
            "status": status,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let detail, !detail.isEmpty {
            update["detail"] = String(detail.prefix(240))
        }

        do {
            var context = session.applicationContext
            context["codexDispatchUpdate"] = update
            try session.updateApplicationContext(context)
        } catch {
            log.debug("Watch Codex update context failed: \(error.localizedDescription)")
        }

        // `sendMessage` is only an immediate optimization. User-info transfer
        // is the durable path and can reach the Watch after either app suspends.
        for transfer in session.outstandingUserInfoTransfers
        where transfer.userInfo["type"] as? String == "codexDispatchUpdate"
            && transfer.userInfo["requestID"] as? String == requestID {
            transfer.cancel()
        }
        session.transferUserInfo(update)

        guard session.isReachable else {
            log.debug("Watch Codex update deferred; Watch is not reachable")
            return
        }
        session.sendMessage(update, replyHandler: nil) { [log] error in
            log.debug("Watch Codex update send failed: \(error.localizedDescription)")
        }
    }

    func sendAIAudio(memoId: String, audioData: Data, preview: String? = nil) -> Bool {
        activateIfNeeded()

        guard let session, session.activationState == .activated else {
            log.debug("Watch AI audio skipped; session is not activated")
            return false
        }

        guard session.isWatchAppInstalled else {
            log.debug("Watch AI audio skipped; Watch app is not installed")
            return false
        }

        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appending(path: "talkie-watch-ai-\(UUID().uuidString)")
                .appendingPathExtension("mp3")
            try audioData.write(to: fileURL, options: .atomic)

            var metadata: [String: Any] = [
                "type": "aiAudio",
                "memoId": memoId
            ]
            if let preview {
                metadata["preview"] = String(preview.prefix(240))
            }

            session.transferFile(fileURL, metadata: metadata)
            log.info("Queued AI audio for Watch")
            return true
        } catch {
            log.warning("Watch AI audio file failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                log.error("Watch session activation failed: \(error.localizedDescription)")
                return
            }

            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled

            // Only log if watch app is actually installed
            if session.isWatchAppInstalled {
                log.info("⌚ Watch app connected (reachable: \(session.isReachable))")
                await self.refreshCurrentCodexSnapshot()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // Called when switching watches - no action needed
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasReachable = self.isWatchReachable
            self.isWatchReachable = session.isReachable

            // Only log changes when watch app is installed
            if session.isWatchAppInstalled && wasReachable != session.isReachable {
                log.info("⌚ Watch reachability: \(session.isReachable)")
            }
            if session.isReachable {
                await self.refreshCurrentCodexSnapshot()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }
            switch type {
            case "codexSelectChannel":
                self.log.info(
                    "Ignored legacy Watch Codex selection; Watch navigation is local-only"
                )
            case "codexSnapshotRequest":
                await self.refreshCurrentCodexSnapshot()
            default:
                break
            }
        }
    }

    // MARK: - File Transfer

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let sourceURL = file.fileURL

        // Move to permanent location
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchAudioDir = documentsDir.appendingPathComponent("WatchAudio", isDirectory: true)

        do {
            try fileManager.createDirectory(at: watchAudioDir, withIntermediateDirectories: true)

            let filename = "watch_\(Int(Date().timeIntervalSince1970))_\(sourceURL.lastPathComponent)"
            let destURL = watchAudioDir.appendingPathComponent(filename)

            try fileManager.moveItem(at: sourceURL, to: destURL)

            // WCSession may return the app to suspension as soon as this
            // delegate callback exits. Persist Codex routing synchronously so
            // the recording can be promoted into the main inbox on any later
            // launch/background window, even if the MainActor task below never
            // gets CPU time during this delivery.
            if metadata["intent"] as? String == "codex" {
                let incomingStore = WatchCodexIncomingDispatchStore(
                    directoryURL: WatchCodexDispatchCoordinator.incomingStoreURL
                )
                _ = try incomingStore.stage(audioURL: destURL, metadata: metadata)
            }

            Task { @MainActor in
                self.log.info("⌚ Received audio from Watch: \(destURL.lastPathComponent)")
                self.onAudioReceived?(destURL, metadata)
            }
        } catch {
            Task { @MainActor in
                self.log.error("Failed to save Watch audio: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata ?? [:]
        guard metadata["type"] as? String == "aiAudio" else { return }

        let fileURL = fileTransfer.file.fileURL
        try? FileManager.default.removeItem(at: fileURL)

        Task { @MainActor in
            if let error {
                self.log.warning("Watch AI audio transfer failed: \(error.localizedDescription)")
            } else {
                self.log.info("Watch AI audio transfer completed")
            }
        }
    }
}
