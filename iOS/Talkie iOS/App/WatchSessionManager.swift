//
//  WatchSessionManager.swift
//  Talkie iOS
//
//  Receives audio from Apple Watch and queues for transcription
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isWatchReachable = false
    @Published var pendingTransfers = 0

    private var session: WCSession?

    private override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Called when audio is received from Watch
    var onAudioReceived: ((URL, [String: Any]) -> Void)?
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[iOS] Watch session activation failed: \(error.localizedDescription)")
            } else {
                print("[iOS] Watch session activated: \(activationState.rawValue)")
                self.isWatchReachable = session.isReachable
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[iOS] Watch session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[iOS] Watch session deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            print("[iOS] Watch reachability changed: \(session.isReachable)")
        }
    }

    // MARK: - File Transfer

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let sourceURL = file.fileURL

        print("[iOS] Received file from Watch: \(sourceURL.lastPathComponent)")
        print("[iOS] Metadata: \(metadata)")

        // Move to permanent location
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchAudioDir = documentsDir.appendingPathComponent("WatchAudio", isDirectory: true)

        do {
            try fileManager.createDirectory(at: watchAudioDir, withIntermediateDirectories: true)

            let filename = "watch_\(Int(Date().timeIntervalSince1970))_\(sourceURL.lastPathComponent)"
            let destURL = watchAudioDir.appendingPathComponent(filename)

            try fileManager.moveItem(at: sourceURL, to: destURL)

            print("[iOS] Saved Watch audio to: \(destURL.lastPathComponent)")

            // Notify handler on main thread
            Task { @MainActor in
                self.onAudioReceived?(destURL, metadata)
            }
        } catch {
            print("[iOS] Failed to save Watch audio: \(error)")
        }
    }
}
