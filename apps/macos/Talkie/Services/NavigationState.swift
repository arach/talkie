//
//  NavigationState.swift
//  Talkie
//
//  Per-window navigation state for the app.
//  `NavigationState.shared` is an active-window proxy so legacy global
//  navigation call sites route to the focused window.
//
//  Usage:
//    NavigationState.shared.navigate(to: .settings)
//    NavigationState.shared.navigateToSettings(.context)
//    NavigationState.shared.navigateToMemo(memoID)
//

import Foundation
import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Navigation State

@MainActor
@Observable
final class NavigationState {
    nonisolated static let shared = NavigationState(isActiveWindowProxy: true)

    private static let fallbackState = NavigationState()
    private static weak var activeState: NavigationState?

    let id = UUID()

    private let isActiveWindowProxy: Bool

    init() {
        self.isActiveWindowProxy = false
    }

    nonisolated private init(isActiveWindowProxy: Bool) {
        self.isActiveWindowProxy = isActiveWindowProxy
    }

    static var active: NavigationState {
        activeState ?? fallbackState
    }

    static var activeWindowID: UUID? {
        activeState?.id
    }

    static func activate(_ state: NavigationState, reason: String) {
        guard !state.isActiveWindowProxy else { return }
        guard activeState !== state else { return }

        activeState = state
        log.debug("Navigation active window changed", detail: "id=\(state.id.uuidString.prefix(8)) reason=\(reason)")
    }

    private var target: NavigationState {
        isActiveWindowProxy ? Self.active : self
    }

    // MARK: - Navigation State

    /// Currently selected sidebar section
    var selectedSection: NavigationSection? {
        get { target._selectedSection }
        set { target._selectedSection = newValue }
    }

    /// Previous section (for back navigation)
    var previousSection: NavigationSection? {
        get { target._previousSection }
        set { target._previousSection = newValue }
    }

    /// Current settings subsection
    var settingsSection: SettingsSection {
        get { target._settingsSection }
        set { target._settingsSection = newValue }
    }

    /// Selected memo ID (for deep linking)
    var selectedMemoID: UUID? {
        get { target._selectedMemoID }
        set { target._selectedMemoID = newValue }
    }

    /// Selected dictation ID (for deep linking)
    var selectedDictationID: UUID? {
        get { target._selectedDictationID }
        set { target._selectedDictationID = newValue }
    }

    /// Filter state for dictations
    var dictationFilter: DictationFilter {
        get { target._dictationFilter }
        set { target._dictationFilter = newValue }
    }

    /// Selected date (for navigating to date-filtered Recordings)
    var selectedDate: Date? {
        get { target._selectedDate }
        set { target._selectedDate = newValue }
    }

    /// Generic navigation params — each destination reads the keys it understands.
    /// Replaced on every `navigate(to:params:)` call (not merged).
    var params: [String: AnyHashable] {
        get { target._params }
        set { target._params = newValue }
    }

    private var _selectedSection: NavigationSection? = .home
    private var _previousSection: NavigationSection?
    private var _settingsSection: SettingsSection = .appearance
    private var _selectedMemoID: UUID?
    private var _selectedDictationID: UUID?
    private var _dictationFilter: DictationFilter = .all
    private var _selectedDate: Date?
    private var _params: [String: AnyHashable] = [:]
    private var backStack: [NavigationSection] = []
    private let maxBackStackCount = 50
    private var isRestoringHistory = false

    // MARK: - Navigation Methods

    /// Navigate to a section with optional params dictionary
    func navigate(to section: NavigationSection, params: [String: AnyHashable] = [:]) {
        guard !isActiveWindowProxy else {
            target.navigate(to: section, params: params)
            return
        }

        log.debug("Navigation route", detail: "id=\(id.uuidString.prefix(8)) section=\(String(describing: section)) params=\(params.keys.sorted().joined(separator: ","))")
        rememberCurrentSection(beforeNavigatingTo: section)
        // Set params BEFORE selectedSection — the destination view reads params
        // in onAppear, which fires as soon as selectedSection changes.
        self.params = params
        selectedSection = section

        applySectionSideEffects(for: section)
    }

    /// Mirror sidebar/chrome selections into the central state while preserving history.
    func navigateFromUI(to section: NavigationSection) {
        guard !isActiveWindowProxy else {
            target.navigateFromUI(to: section)
            return
        }

        navigate(to: section)
    }

    /// Navigate to settings with a specific subsection
    func navigateToSettings(_ section: SettingsSection) {
        guard !isActiveWindowProxy else {
            target.navigateToSettings(section)
            return
        }

        log.debug("Navigation route settings", detail: "id=\(id.uuidString.prefix(8)) section=\(String(describing: section))")
        rememberCurrentSection(beforeNavigatingTo: .settings)
        selectedSection = .settings
        settingsSection = section
        applySectionSideEffects(for: .settings)
    }

    /// Navigate to a specific memo — opens unified Recordings with selection + detail
    func navigateToMemo(_ id: UUID) {
        guard !isActiveWindowProxy else {
            target.navigateToMemo(id)
            return
        }

        selectedMemoID = id
        navigate(to: .recordings, params: [
            "typeFilter": "memos",
            "selectedID": id
        ])
    }

    /// Navigate to a specific dictation — opens unified Recordings with selection + detail
    func navigateToDictation(_ id: UUID) {
        guard !isActiveWindowProxy else {
            target.navigateToDictation(id)
            return
        }

        selectedDictationID = id
        navigate(to: .recordings, params: [
            "typeFilter": "dictations",
            "selectedID": id
        ])
    }

    /// Navigate to dictations with pending filter
    func navigateToDictationsPending() {
        guard !isActiveWindowProxy else {
            target.navigateToDictationsPending()
            return
        }

        dictationFilter = .pending
        navigate(to: .dictations, params: [
            "dictationFilter": "pending"
        ])
    }

    /// Go back to the previous app section.
    @discardableResult
    func goBack() -> Bool {
        guard !isActiveWindowProxy else {
            return target.goBack()
        }

        if SettingsManager.shared.isMarkupSessionActive {
            NotificationCenter.default.post(name: .dismissCaptureMarkupHost, object: nil)
            return true
        }

        guard let previous = backStack.popLast() ?? previousSection,
              previous != selectedSection else {
            previousSection = backStack.last
            return false
        }

        isRestoringHistory = true
        defer { isRestoringHistory = false }

        params = [:]
        selectedSection = previous
        previousSection = backStack.last
        applySectionSideEffects(for: previous)

        return true
    }

    private func rememberCurrentSection(beforeNavigatingTo destination: NavigationSection) {
        guard !isRestoringHistory,
              let current = selectedSection,
              current != destination else {
            return
        }

        if backStack.last != current {
            backStack.append(current)
            if backStack.count > maxBackStackCount {
                backStack.removeFirst(backStack.count - maxBackStackCount)
            }
        }

        previousSection = current
    }

    private func applySectionSideEffects(for section: NavigationSection) {
        let recordingSections: Set<NavigationSection> = [.allMemos, .recordings, .dictations]
        if !recordingSections.contains(section) {
            selectedMemoID = nil
            selectedDictationID = nil
            dictationFilter = .all
        }
    }

    // MARK: - Convenience Methods

    func navigateToWorkflows() {
        navigate(to: .workflows)
    }

    func navigateToAgent() {
        navigate(to: .liveDashboard)
    }

    func navigateToLearn(articleID: String? = nil) {
        var params: [String: AnyHashable] = [:]
        if let articleID, !articleID.isEmpty {
            params["learnArticleId"] = articleID
        }
        navigate(to: .liveDashboard, params: params)
    }

    func navigateToDictations() {
        navigate(to: .dictations)
    }

    func navigateToConsole(
        profile: ManagedAgentConsoleProfile = .defaultProfile(),
        systemPrompt: String? = nil,
        prompt: String? = nil,
        notes: String? = nil,
        examples: String? = nil
    ) {
        guard !isActiveWindowProxy else {
            target.navigateToConsole(
                profile: profile,
                systemPrompt: systemPrompt,
                prompt: prompt,
                notes: notes,
                examples: examples
            )
            return
        }

        ManagedAgentConsoleStore.shared.open(
            profile: profile,
            systemPrompt: systemPrompt,
            prompt: prompt,
            notes: notes,
            examples: examples
        )
    }

    @discardableResult
    func navigateToConsoleTab(
        _ tabID: String,
        createIfMissing fallbackDefinition: TabDefinition? = nil
    ) -> ManagedAgentConsoleSession? {
        guard !isActiveWindowProxy else {
            return target.navigateToConsoleTab(tabID, createIfMissing: fallbackDefinition)
        }

        let registry = TabDefinitionRegistry.shared
        let pool = ConsoleSessionPool.shared

        registry.bootstrap()

        if registry.tab(for: tabID) == nil, let fallbackDefinition {
            registry.create(fallbackDefinition)
        }

        guard let tab = registry.tab(for: tabID) else {
            navigate(to: .systemConsole)
            return nil
        }

        registry.activeTabId = tab.id
        navigate(to: .systemConsole)

        let needsLaunch = if let session = pool.session(for: tab.id) {
            pool.isStale(tab.id) || !session.isRunning
        } else {
            true
        }

        if needsLaunch {
            pool.launch(tab: tab, registry: registry)
        }

        return pool.session(for: tab.id)
    }

    @discardableResult
    func navigateToTalkieShell(command: String? = nil) -> ManagedAgentConsoleSession? {
        let session = navigateToConsoleTab(
            "talkie-shell",
            createIfMissing: TabPresets.talkieShell
        )

        guard let command,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let session else {
            return session
        }

        let normalizedCommand: String
        if command.hasSuffix("\n") || command.hasSuffix("\r") {
            normalizedCommand = command
        } else {
            normalizedCommand = command + "\r"
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard session.isRunning else { return }
            session.send(normalizedCommand)
        }

        return session
    }

    @available(*, deprecated, renamed: "navigateToAgent")
    func navigateToLive() {
        navigateToAgent()
    }

    @available(*, deprecated, renamed: "navigateToDictations")
    func navigateToLiveRecent() {
        navigateToDictations()
    }

    func navigateToAllMemos() {
        navigate(to: .allMemos)
    }

    func navigateToHelpers() {
        navigateToSettings(.helpers)
    }

    func navigateToHome() {
        navigate(to: .home)
    }

    /// Navigate to Compose with optional initial text and source recording
    func navigateToCompose(withText text: String? = nil, sourceRecordingId: UUID? = nil) {
        var params: [String: AnyHashable] = [:]
        if let text = text, !text.isEmpty {
            params["initialText"] = text
        }
        if let sourceId = sourceRecordingId {
            params["sourceRecordingId"] = sourceId
        }
        navigate(to: .drafts, params: params)
    }

    /// Navigate to recordings filtered by a specific date
    func navigateToDate(_ date: Date) {
        selectedDate = date
        navigate(to: .recordings, params: [
            "dateFilter": date
        ])
    }

    // MARK: - Voice Navigation

    /// Handle voice navigation intent from TalkieAgent
    /// - Parameters:
    ///   - intent: The recognized intent string (matches VoiceIntent.rawValue)
    ///   - rawText: The original voice command text
    func handleVoiceNavigation(intent: String, rawText: String) {
        guard !isActiveWindowProxy else {
            target.handleVoiceNavigation(intent: intent, rawText: rawText)
            return
        }

        log.info("[VoiceCmd:Route] handleVoiceNavigation() intent=\(intent) rawText=\"\(rawText)\"")
        switch intent {
        // MARK: - Main Navigation
        case "navigateHome":
            log.info("[VoiceCmd:Route] → Navigating to home")
            navigate(to: .home)
        case "navigateRecordings":
            navigate(to: .recordings)
        case "navigateDictations":
            navigate(to: .dictations)
        case "navigateSettings":
            navigate(to: .settings)
        case "navigateWorkflows":
            navigate(to: .workflows)
        case "navigateModels":
            navigate(to: .models)
        case "navigateDrafts":
            navigate(to: .drafts)
        case "navigateStats":
            navigate(to: .liveDashboard)
        case "navigateActivityLog":
            navigate(to: .activityLog)
        case "navigateSystemConsole":
            navigateToConsole()
        case "navigatePendingActions":
            navigate(to: .pendingActions)
        case "navigateAIResults":
            navigate(to: .aiResults)

        // MARK: - Settings Subsections
        case "settingsAppearance":
            navigateToSettings(.appearance)
        case "settingsHelpers":
            navigateToSettings(.helpers)
        case "settingsVoiceIO":
            navigateToSettings(.voiceIO)
        case "settingsShortcutKeyboard":
            navigateToSettings(.shortcutKeyboard)
        case "settingsDictionary":
            navigateToSettings(.context)
        case "settingsAIProviders":
            navigateToSettings(.aiProviders)
        case "settingsModels":
            navigateToSettings(.models)
        case "settingsStorage":
            navigateToSettings(.storage)
        case "settingsSync":
            navigateToSettings(.sync)
        case "settingsActions":
            navigateToSettings(.context)
        case "settingsAutomations":
            navigateToSettings(.automations)
        case "settingsExtensions":
            navigateToSettings(.extensions)
        case "settingsPermissions":
            navigateToSettings(.permissions)
        case "settingsDebug":
            navigateToSettings(.debug)

        // MARK: - Actions
        case "openSearch":
            SettingsManager.shared.isContentSearchPresented = true
        case "openCommandPalette":
            SettingsManager.shared.isCommandPalettePresented = true
        case "goBack":
            goBack()
        case "startDictation", "stopDictation":
            // Toggle dictation via TalkieAgent
            ServiceManager.shared.live.toggleRecording()
        case "syncNow":
            // Trigger sync
            Task {
                await CloudKitSyncManager.shared.syncNow()
            }

        default:
            // Unknown intent - log but don't navigate
            log.warning("[VoiceCmd:Route] Unknown intent: \(intent)")
            break
        }
        log.info("[VoiceCmd:Route] ✓ handleVoiceNavigation() complete")
    }
}

// MARK: - Dictation Filter

enum DictationFilter: String, CaseIterable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
    case today = "Today"
}

// MARK: - Environment Key

private struct NavigationStateKey: EnvironmentKey {
    static let defaultValue = NavigationState.shared
}

extension EnvironmentValues {
    var navigationState: NavigationState {
        get { self[NavigationStateKey.self] }
        set { self[NavigationStateKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Inject navigation state into environment
    func withNavigationState(_ state: NavigationState) -> some View {
        environment(\.navigationState, state)
    }
}
