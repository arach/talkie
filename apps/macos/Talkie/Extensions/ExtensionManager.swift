//
//  ExtensionManager.swift
//  Talkie
//
//  Manages Talkie extensions - loading, unloading, and routing events.
//  Conforms to TalkieExtensionHost to provide app state and UI injection.
//

import SwiftUI
import Observation
import TalkieKit

private let log = Log(.system)

// MARK: - Extension Manager

@MainActor
@Observable
final class ExtensionManager: TalkieExtensionHost {
    // MARK: - Singleton

    static let shared = ExtensionManager()

    // MARK: - State

    /// Registered extensions
    private(set) var extensions: [TalkieExtension] = []

    /// Event delegates (weak references)
    private var delegates = NSHashTable<AnyObject>.weakObjects()

    /// Current toast (shown by any extension)
    var currentToast: ExtensionToast?

    /// Toast queue for rate limiting
    private var toastQueue: [ExtensionToast] = []
    private var settingsObserver: NSObjectProtocol?

    // MARK: - Persisted State

    private struct ManagerState: Codable {
        var sessionCount: Int = 0
        var lastSessionDate: Date?
        var totalMemoCount: Int = 0
        var totalDictationCount: Int = 0
        var totalPolishCount: Int = 0
        var totalWorkflowCount: Int = 0
        var totalWordCount: Int = 0
        var currentStreak: Int = 0
        var longestStreak: Int = 0
        var lastActiveDate: Date?
        var lastToastShownAt: Date?

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
            lastSessionDate = try container.decodeIfPresent(Date.self, forKey: .lastSessionDate)
            totalMemoCount = try container.decodeIfPresent(Int.self, forKey: .totalMemoCount) ?? 0
            totalDictationCount = try container.decodeIfPresent(Int.self, forKey: .totalDictationCount) ?? 0
            totalPolishCount = try container.decodeIfPresent(Int.self, forKey: .totalPolishCount) ?? 0
            totalWorkflowCount = try container.decodeIfPresent(Int.self, forKey: .totalWorkflowCount) ?? 0
            totalWordCount = try container.decodeIfPresent(Int.self, forKey: .totalWordCount) ?? 0
            currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
            longestStreak = try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
            lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate)
            lastToastShownAt = try container.decodeIfPresent(Date.self, forKey: .lastToastShownAt)
        }
    }

    private var state: ManagerState

    // MARK: - Constants

    private let stateKey = "extensionManagerState"
    private let toastCooldownSeconds: TimeInterval = 30
    private let toastAutoDismissSeconds: TimeInterval = 5

    private var isFrameworkEnabled: Bool {
        SettingsManager.shared.extensionsFrameworkEnabled
    }

    // MARK: - Init

    private init() {
        // Load persisted state
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(ManagerState.self, from: data) {
            self.state = decoded
        } else {
            self.state = ManagerState()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .extensionsFrameworkSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleFrameworkSettingDidChange()
            }
        }

        if isFrameworkEnabled {
            incrementSession()
            log.info("ExtensionManager initialized: session=\(state.sessionCount)")
        } else {
            log.info("ExtensionManager initialized: framework disabled")
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    // MARK: - Session Management

    private func incrementSession() {
        let now = Date()
        let calendar = Calendar.current

        if let lastDate = state.lastSessionDate {
            if !calendar.isDate(lastDate, inSameDayAs: now) {
                state.sessionCount += 1
                updateStreak()
            }
        } else {
            state.sessionCount += 1
            state.currentStreak = 1
        }

        state.lastSessionDate = now
        state.lastActiveDate = now
        save()

        if isFrameworkEnabled {
            // Notify extensions of new session
            notifySessionStart()
        }
    }

    private func handleFrameworkSettingDidChange() {
        if isFrameworkEnabled {
            incrementSession()
            return
        }

        currentToast = nil
        toastQueue.removeAll()
        unloadAll()
        AppsRuntime.shared.stop()
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = Date()

        guard let lastActive = state.lastActiveDate else {
            state.currentStreak = 1
            return
        }

        let daysSinceLastActive = calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0

        if daysSinceLastActive == 1 {
            state.currentStreak += 1
            if state.currentStreak > state.longestStreak {
                state.longestStreak = state.currentStreak
            }
        } else if daysSinceLastActive > 1 {
            state.currentStreak = 1
        }
    }

    // MARK: - Extension Registration

    /// Register an extension
    func register(_ ext: TalkieExtension) {
        guard !extensions.contains(where: { $0.id == ext.id }) else {
            log.warning("Extension already registered: \(ext.id)")
            return
        }

        extensions.append(ext)
        log.info("Registered extension: \(ext.name) (\(ext.id))")
    }

    /// Unregister an extension
    func unregister(_ ext: TalkieExtension) {
        ext.onUnload()
        extensions.removeAll { $0.id == ext.id }
        log.info("Unregistered extension: \(ext.name)")
    }

    /// Load all registered extensions
    func loadAll() {
        for ext in extensions where ext.isEnabled {
            ext.onLoad(host: self)
            log.info("Loaded extension: \(ext.name) v\(ext.version)")
        }
    }

    /// Unload all extensions
    func unloadAll() {
        for ext in extensions {
            ext.onUnload()
        }
        log.info("Unloaded all extensions")
    }

    // MARK: - TalkieExtensionHost - Event Subscriptions

    func subscribe(_ delegate: TalkieExtensionDelegate) {
        delegates.add(delegate as AnyObject)
    }

    func unsubscribe(_ delegate: TalkieExtensionDelegate) {
        delegates.remove(delegate as AnyObject)
    }

    // MARK: - TalkieExtensionHost - State Access

    var memoCount: Int { state.totalMemoCount }
    var dictationCount: Int { state.totalDictationCount }
    var totalWords: Int { state.totalWordCount }
    var currentStreak: Int { state.currentStreak }
    var sessionCount: Int { state.sessionCount }
    var polishCount: Int { state.totalPolishCount }
    var workflowCount: Int { state.totalWorkflowCount }

    // MARK: - TalkieExtensionHost - UI Injection

    func showToast(_ toast: ExtensionToast) {
        guard isFrameworkEnabled else { return }

        // Check cooldown
        if let lastShown = state.lastToastShownAt {
            let elapsed = Date().timeIntervalSince(lastShown)
            if elapsed < toastCooldownSeconds {
                toastQueue.append(toast)
                return
            }
        }

        displayToast(toast)
    }

    func dismissToast() {
        dismissCurrentToast()
    }

    private func displayToast(_ toast: ExtensionToast) {
        state.lastToastShownAt = Date()
        save()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentToast = toast
        }

        // Auto-dismiss after delay
        Task {
            try? await Task.sleep(for: .seconds(toastAutoDismissSeconds))
            await MainActor.run {
                if self.currentToast?.id == toast.id {
                    self.dismissCurrentToast()
                }
            }
        }
    }

    func dismissCurrentToast() {
        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }

        // Show next queued toast after a short delay
        if !toastQueue.isEmpty {
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                await MainActor.run {
                    if let next = self.toastQueue.first {
                        self.toastQueue.removeFirst()
                        self.displayToast(next)
                    }
                }
            }
        }
    }

    // MARK: - Event Broadcasting

    /// Called when a memo is created
    func notifyMemoCreated(wordCount: Int) {
        guard isFrameworkEnabled else { return }

        state.totalMemoCount += 1
        state.totalWordCount += wordCount
        state.lastActiveDate = Date()
        updateStreak()
        save()

        for delegate in delegates.allObjects {
            (delegate as? TalkieExtensionDelegate)?.extensionHost(self, didCreateMemo: wordCount)
        }
    }

    /// Called when a dictation is completed
    func notifyDictationCompleted(wordCount: Int) {
        guard isFrameworkEnabled else { return }

        state.totalDictationCount += 1
        state.totalWordCount += wordCount
        state.lastActiveDate = Date()
        updateStreak()
        save()

        for delegate in delegates.allObjects {
            (delegate as? TalkieExtensionDelegate)?.extensionHost(self, didCompleteDictation: wordCount)
        }

        // Notify Apps (JS extensions)
        AppsRuntime.shared.notifyDictationCompleted(
            wordCount: wordCount,
            dictationCount: state.totalDictationCount
        )
    }

    /// Called when a polish operation completes
    func notifyPolishCompleted(instruction: String) {
        guard isFrameworkEnabled else { return }

        state.totalPolishCount += 1
        save()

        for delegate in delegates.allObjects {
            (delegate as? TalkieExtensionDelegate)?.extensionHost(self, didCompletePolish: instruction)
        }
    }

    /// Called when a workflow is run
    func notifyWorkflowRun(name: String) {
        guard isFrameworkEnabled else { return }

        state.totalWorkflowCount += 1
        save()

        for delegate in delegates.allObjects {
            (delegate as? TalkieExtensionDelegate)?.extensionHost(self, didRunWorkflow: name)
        }
    }

    /// Called at session start
    private func notifySessionStart() {
        guard isFrameworkEnabled else { return }

        for delegate in delegates.allObjects {
            (delegate as? TalkieExtensionDelegate)?.extensionHost(self, didStartSession: state.sessionCount)
        }

        // Notify Apps (JS extensions)
        if AppsRuntime.shared.isStarted {
            AppsRuntime.shared.notifySessionStarted(sessionNumber: state.sessionCount)
        }
    }

    // MARK: - Database Sync

    /// Sync manager state with actual database counts.
    /// Called from HomeScreen after data loads to catch up on any missed events.
    func syncWithDatabaseCounts(memoCount: Int, dictationCount: Int, totalWords: Int, streak: Int) {
        guard isFrameworkEnabled else { return }

        state.totalMemoCount = max(state.totalMemoCount, memoCount)
        state.totalDictationCount = max(state.totalDictationCount, dictationCount)
        state.totalWordCount = max(state.totalWordCount, totalWords)
        state.currentStreak = max(state.currentStreak, streak)
        if state.currentStreak > state.longestStreak {
            state.longestStreak = state.currentStreak
        }
        save()

        log.debug("Synced with database: memos=\(memoCount), dictations=\(dictationCount), words=\(totalWords), streak=\(streak)")
    }

    // MARK: - Reset (for testing)

    func resetState() {
        state = ManagerState()
        state.sessionCount = 1
        state.lastSessionDate = Date()
        currentToast = nil
        toastQueue.removeAll()
        save()
        log.info("Extension manager state reset")
    }
}
