//
//  TalkieLiveClient.swift
//  Talkie
//
//  Simple client for communicating with TalkieLive via URL scheme.
//  No persistent XPC connections - just process detection and fire-and-forget URL commands.
//

import Foundation
import AppKit
import TalkieKit
import Observation

@MainActor
@Observable
final class TalkieLiveClient {
    static let shared = TalkieLiveClient()

    // MARK: - Observable State

    /// Is TalkieLive process running?
    private(set) var isRunning: Bool = false

    /// TalkieLive process ID (if running)
    private(set) var processId: Int32? = nil

    // MARK: - Private

    private var workspaceObservers: [NSObjectProtocol] = []
    private let liveBundleId: String
    private let liveURLScheme: String

    private init() {
        liveBundleId = TalkieEnvironment.current.liveBundleId
        liveURLScheme = TalkieEnvironment.current.liveURLScheme

        // Check initial state
        refreshProcessState()

        // Watch for app launch/quit
        setupWorkspaceObservers()

        // Listen for new dictations from TalkieLive (cross-process)
        setupDictationObserver()

        NSLog("[TalkieLiveClient] Initialized - scheme: %@, isRunning: %@", liveURLScheme, isRunning ? "true" : "false")
    }

    private func setupDictationObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: .liveDictationWasAdded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[TalkieLiveClient] 📥 Received liveDictationWasAdded notification")
            self?.logEvent(.record, "← TalkieLive", detail: "New dictation saved")

            // Refresh the dictation store
            DictationStore.shared.refresh()
        }
    }

    // MARK: - Process Detection

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // Instant detection when TalkieLive launches
        let launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.liveBundleId else { return }

            self.processId = app.processIdentifier
            self.isRunning = true
            NSLog("[TalkieLiveClient] TalkieLive launched (PID: %d)", app.processIdentifier)
        }
        workspaceObservers.append(launchObserver)

        // Instant detection when TalkieLive quits
        let terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.liveBundleId else { return }

            self.processId = nil
            self.isRunning = false
            NSLog("[TalkieLiveClient] TalkieLive terminated")
        }
        workspaceObservers.append(terminateObserver)
    }

    /// Refresh process state by checking running applications
    func refreshProcessState() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: liveBundleId)
        if let app = apps.first {
            processId = app.processIdentifier
            isRunning = true
        } else {
            processId = nil
            isRunning = false
        }
    }

    // MARK: - URL Commands

    /// Start recording in TalkieLive (only if idle)
    /// Returns true if URL was sent successfully
    @discardableResult
    func startRecording() -> Bool {
        sendCommand("start")
    }

    /// Stop recording in TalkieLive (only if recording)
    /// Returns true if URL was sent successfully
    @discardableResult
    func stopRecording() -> Bool {
        sendCommand("stop")
    }

    private func sendCommand(_ command: String) -> Bool {
        let urlString = "\(liveURLScheme)://\(command)"

        guard let url = URL(string: urlString) else {
            logEvent(.error, "Failed to create URL", detail: urlString)
            return false
        }

        // Log outgoing request (access log style)
        NSLog("[TalkieLiveClient] 📤 URL sending: %@ (isRunning: %@)", urlString, isRunning ? "true" : "false")
        logEvent(.system, "→ TalkieLive", detail: "\(command) (\(liveURLScheme))")

        guard isRunning else {
            NSLog("[TalkieLiveClient] ⚠️ TalkieLive not running, URL may fail")
            logEvent(.warning, "TalkieLive not running", detail: "Command may not be received")
        }

        NSWorkspace.shared.open(url)

        NSLog("[TalkieLiveClient] ✓ URL opened: %@", urlString)
        return true
    }

    // MARK: - Logging

    private func logEvent(_ type: SystemEventType, _ message: String, detail: String? = nil) {
        // Log to SystemEventManager (visible in Talkie's system logs viewer)
        SystemEventManager.shared.logSync(type, message, detail: detail)
    }

    // MARK: - Launch TalkieLive

    /// Launch TalkieLive if not running
    func launchTalkieLive() {
        if isRunning {
            NSLog("[TalkieLiveClient] Already running")
            return
        }

        logEvent(.system, "Launching TalkieLive")
        _ = AppEnvironment.shared.launch(.talkieLive)
    }
}
