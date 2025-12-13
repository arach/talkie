//
//  WatchSessionManager.swift
//  Talkie iOS
//
//  Receives audio from Apple Watch and queues for transcription
//

import Foundation
import WatchConnectivity
import UIKit

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isWatchReachable = false
    @Published var pendingTransfers = 0

    private var session: WCSession?

    private override init() {
        super.init()

        print("📱 [iOS] WatchSessionManager init...")
        print("📱 [iOS] WCSession.isSupported: \(WCSession.isSupported())")

        if WCSession.isSupported() {
            session = WCSession.default
            print("📱 [iOS] Setting delegate to self: \(self)")
            session?.delegate = self
            print("📱 [iOS] Delegate set: \(String(describing: session?.delegate))")
            print("📱 [iOS] Activating WCSession...")
            session?.activate()

            // Log status after a delay to see initial state
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.logSessionStatus()
            }
        } else {
            print("📱 [iOS] ⚠️ WCSession NOT supported on this device")
        }
    }

    func logSessionStatus() {
        guard let session = session else {
            print("📱 [iOS] Session is nil!")
            return
        }
        let myBundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let expectedWatchID = "\(myBundleID).watchkitapp"
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let deviceName = UIDevice.current.name

        print("📱 [iOS] ===== SESSION STATUS CHECK =====")
        print("📱 [iOS] Device: \(deviceName)")
        print("📱 [iOS] Device ID: \(deviceID)")
        print("📱 [iOS] iOS Bundle ID: \(myBundleID)")
        print("📱 [iOS] Expected Watch ID: \(expectedWatchID)")
        print("📱 [iOS] activationState: \(session.activationState.rawValue)")
        print("📱 [iOS] isPaired: \(session.isPaired)")
        print("📱 [iOS] isWatchAppInstalled: \(session.isWatchAppInstalled)")
        print("📱 [iOS] isReachable: \(session.isReachable)")
        if let watchDir = session.watchDirectoryURL {
            print("📱 [iOS] watchDirectoryURL: \(watchDir.path)")
        }
        print("📱 [iOS] ==================================")
    }

    /// Called when audio is received from Watch
    var onAudioReceived: ((URL, [String: Any]) -> Void)?
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("📱 [iOS] Watch session activation FAILED: \(error.localizedDescription)")
            } else {
                print("📱 [iOS] ========== SESSION INFO ==========")
                print("📱 [iOS] State: \(activationState.rawValue)")
                print("📱 [iOS] Reachable: \(session.isReachable)")
                print("📱 [iOS] Watch app installed: \(session.isWatchAppInstalled)")
                print("📱 [iOS] Paired: \(session.isPaired)")
                print("📱 [iOS] =====================================")
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
            print("📱 [iOS] Watch reachability → \(session.isReachable) | Watch installed: \(session.isWatchAppInstalled)")
        }
    }

    // MARK: - File Transfer

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // First log - before ANY other code
        NSLog("🔵🔵🔵 [iOS] didReceive FILE DELEGATE CALLED 🔵🔵🔵")

        let metadata = file.metadata ?? [:]
        let sourceURL = file.fileURL

        print("🔵 [iOS] ========== WATCH FILE RECEIVED ==========")
        print("🔵 [iOS] File: \(sourceURL.lastPathComponent)")
        print("🔵 [iOS] Path: \(sourceURL.path)")
        print("🔵 [iOS] Exists: \(FileManager.default.fileExists(atPath: sourceURL.path))")
        print("🔵 [iOS] Metadata: \(metadata)")

        // Move to permanent location
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchAudioDir = documentsDir.appendingPathComponent("WatchAudio", isDirectory: true)

        do {
            try fileManager.createDirectory(at: watchAudioDir, withIntermediateDirectories: true)

            let filename = "watch_\(Int(Date().timeIntervalSince1970))_\(sourceURL.lastPathComponent)"
            let destURL = watchAudioDir.appendingPathComponent(filename)

            try fileManager.moveItem(at: sourceURL, to: destURL)

            print("🔵 [iOS] Saved Watch audio to: \(destURL.lastPathComponent)")

            // Notify handler on main thread
            Task { @MainActor in
                print("🔵 [iOS] Callback set: \(self.onAudioReceived != nil)")
                self.onAudioReceived?(destURL, metadata)
            }
        } catch {
            print("🔵 [iOS] ❌ Failed to save Watch audio: \(error)")
        }
    }
}
