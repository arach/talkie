//
//  WatchSessionManager.swift
//  TalkieWatch
//
//  Handles WatchConnectivity communication with iPhone
//

import Foundation
import WatchConnectivity
import WatchKit

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
        print("⌚️ [Watch] sendAudio called with: \(fileURL.lastPathComponent)")
        print("⌚️ [Watch] File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")

        guard let session = session, session.activationState == .activated else {
            print("⌚️ [Watch] ❌ Session not activated")
            lastSentStatus = .failed("Watch not connected")
            return
        }

        print("⌚️ [Watch] Session state: \(session.activationState.rawValue), reachable: \(session.isReachable)")

        guard session.isReachable else {
            // iPhone not reachable - queue for background transfer
            print("⌚️ [Watch] iPhone not reachable, using background transfer")
            transferInBackground(fileURL: fileURL)
            return
        }

        lastSentStatus = .sending
        print("⌚️ [Watch] 📤 Sending file to iPhone...")

        // Send immediately if reachable
        session.transferFile(fileURL, metadata: [
            "type": "audio",
            "timestamp": Date().timeIntervalSince1970
        ])
        print("⌚️ [Watch] transferFile() called")
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
            if let error = error {
                print("⌚️ [Watch] ❌ File transfer FAILED: \(error.localizedDescription)")
                self.lastSentStatus = .failed(error.localizedDescription)
            } else {
                let file = fileTransfer.file
                print("⌚️ [Watch] ✅ File transfer complete!")
                print("⌚️ [Watch]    File: \(file.fileURL.lastPathComponent)")
                print("⌚️ [Watch]    Metadata: \(file.metadata ?? [:])")
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
