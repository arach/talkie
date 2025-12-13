//
//  WatchSessionManager.swift
//  TalkieWatch
//
//  Handles WatchConnectivity communication with iPhone
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    @Published var lastSentStatus: SendStatus = .idle

    enum SendStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    private var session: WCSession?

    private override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Send audio file to iPhone for transcription
    func sendAudio(fileURL: URL) {
        guard let session = session, session.activationState == .activated else {
            lastSentStatus = .failed("Watch not connected")
            return
        }

        guard session.isReachable else {
            // iPhone not reachable - queue for background transfer
            transferInBackground(fileURL: fileURL)
            return
        }

        lastSentStatus = .sending

        // Send immediately if reachable
        session.transferFile(fileURL, metadata: [
            "type": "audio",
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    private func transferInBackground(fileURL: URL) {
        guard let session = session else { return }

        lastSentStatus = .sending

        session.transferFile(fileURL, metadata: [
            "type": "audio",
            "timestamp": Date().timeIntervalSince1970,
            "background": true
        ])
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[Watch] Session activation failed: \(error.localizedDescription)")
            } else {
                print("[Watch] Session activated: \(activationState.rawValue)")
                self.isReachable = session.isReachable
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            print("[Watch] Reachability changed: \(session.isReachable)")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[Watch] File transfer failed: \(error.localizedDescription)")
                self.lastSentStatus = .failed(error.localizedDescription)
            } else {
                print("[Watch] File transfer complete")
                self.lastSentStatus = .sent

                // Reset status after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.lastSentStatus == .sent {
                    self.lastSentStatus = .idle
                }
            }
        }
    }
}
