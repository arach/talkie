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

    private let log = Log(.system)

    @Published var isWatchReachable = false
    @Published var isWatchAppInstalled = false
    @Published var pendingTransfers = 0
    @Published private(set) var isActivated = false

    private var session: WCSession?

    private override init() {
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
}
