//
//  OnboardingProgressManager.swift
//  Talkie
//
//  DEPRECATED: This file is deprecated. Use ExtensionManager and MilestoneExtension instead.
//  The onboarding/milestone system has been migrated to the Extension Framework.
//
//  See:
//  - Extensions/ExtensionManager.swift
//  - Extensions/Milestones/MilestoneExtension.swift
//  - Extensions/Milestones/MilestoneDefinitions.swift
//
//  This file is kept for backwards compatibility. The types (Milestone, TipID, ToastItem)
//  are still used by legacy code and previews.
//

import SwiftUI
import Observation
import TalkieKit

private let log = Log(.system)

// MARK: - Milestone Enum

enum Milestone: String, CaseIterable {
    // First-time achievements
    case firstMemo
    case firstDictation
    case firstPolish
    case firstWorkflow

    // Volume milestones
    case tenMemos
    case fiftyMemos
    case hundredMemos

    // Word count milestones
    case thousandWords
    case tenThousandWords
    case fiftyThousandWords

    // Streak milestones
    case sevenDayStreak
    case thirtyDayStreak

    var title: String {
        switch self {
        case .firstMemo: return "Your first memo!"
        case .firstDictation: return "Agent dictation unlocked!"
        case .firstPolish: return "Polish master!"
        case .firstWorkflow: return "Workflow wizard!"
        case .tenMemos: return "Double digits!"
        case .fiftyMemos: return "Half century!"
        case .hundredMemos: return "Centurion!"
        case .thousandWords: return "Short story!"
        case .tenThousandWords: return "Novelist vibes!"
        case .fiftyThousandWords: return "Epic writer!"
        case .sevenDayStreak: return "One week streak!"
        case .thirtyDayStreak: return "Monthly champion!"
        }
    }

    var subtitle: String {
        switch self {
        case .firstMemo: return "You've captured your first thought"
        case .firstDictation: return "Real-time transcription at your fingertips"
        case .firstPolish: return "AI refinement makes it shine"
        case .firstWorkflow: return "Automation is your superpower"
        case .tenMemos: return "10 memos recorded"
        case .fiftyMemos: return "50 memos in your library"
        case .hundredMemos: return "100 thoughts captured"
        case .thousandWords: return "1,000 words transcribed"
        case .tenThousandWords: return "10,000 words in your vault"
        case .fiftyThousandWords: return "50,000 words and counting"
        case .sevenDayStreak: return "Recording for 7 days straight"
        case .thirtyDayStreak: return "A whole month of voice notes"
        }
    }

    var icon: String {
        switch self {
        case .firstMemo: return "mic.fill"
        case .firstDictation: return "keyboard"
        case .firstPolish: return "sparkles"
        case .firstWorkflow: return "gearshape.2"
        case .tenMemos, .fiftyMemos, .hundredMemos: return "square.stack.3d.up.fill"
        case .thousandWords, .tenThousandWords, .fiftyThousandWords: return "doc.text.fill"
        case .sevenDayStreak, .thirtyDayStreak: return "flame.fill"
        }
    }

    var tip: String? {
        switch self {
        case .firstMemo: return "Tip: Hold \u{2325} to dictate anywhere"
        case .firstDictation: return "Tip: Press \u{2318}R to start recording"
        case .firstPolish: return "Tip: Try 'make it concise' as a command"
        case .firstWorkflow: return nil
        case .tenMemos: return nil
        case .fiftyMemos: return nil
        case .hundredMemos: return nil
        case .thousandWords: return nil
        case .tenThousandWords: return nil
        case .fiftyThousandWords: return nil
        case .sevenDayStreak: return nil
        case .thirtyDayStreak: return nil
        }
    }
}

// MARK: - Tip ID Enum

enum TipID: String, CaseIterable {
    case commandButton        // First time in interstitial
    case workflowsIntro       // After 3 polishes
    case liveMode            // After first memo
    case keyboardShortcuts   // After 5 sessions

    var title: String {
        switch self {
        case .commandButton: return "Voice Command"
        case .workflowsIntro: return "Discover Workflows"
        case .liveMode: return "Agent Mode"
        case .keyboardShortcuts: return "Keyboard Shortcuts"
        }
    }

    var body: String {
        switch self {
        case .commandButton: return "Speak an instruction like \"make it concise\" to transform your text"
        case .workflowsIntro: return "Create custom workflows to automate your voice-to-text pipeline"
        case .liveMode: return "Enable Agent Mode for real-time transcription as you speak"
        case .keyboardShortcuts: return "Press ? to see all keyboard shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .commandButton: return "mic.badge.plus"
        case .workflowsIntro: return "gearshape.2"
        case .liveMode: return "keyboard"
        case .keyboardShortcuts: return "command"
        }
    }
}

// MARK: - Onboarding State (Persistence)

struct OnboardingState: Codable {
    var sessionCount: Int = 0
    var lastSessionDate: Date?
    var completedMilestones: Set<String> = []
    var dismissedTips: Set<String> = []
    var powerUserMode: Bool = false
    var lastToastShownAt: Date?

    // Activity tracking
    var totalMemoCount: Int = 0
    var totalDictationCount: Int = 0
    var totalPolishCount: Int = 0
    var totalWorkflowCount: Int = 0
    var totalWordCount: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: Date?

    // Decode with defaults for missing keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        lastSessionDate = try container.decodeIfPresent(Date.self, forKey: .lastSessionDate)
        completedMilestones = try container.decodeIfPresent(Set<String>.self, forKey: .completedMilestones) ?? []
        dismissedTips = try container.decodeIfPresent(Set<String>.self, forKey: .dismissedTips) ?? []
        powerUserMode = try container.decodeIfPresent(Bool.self, forKey: .powerUserMode) ?? false
        lastToastShownAt = try container.decodeIfPresent(Date.self, forKey: .lastToastShownAt)
        totalMemoCount = try container.decodeIfPresent(Int.self, forKey: .totalMemoCount) ?? 0
        totalDictationCount = try container.decodeIfPresent(Int.self, forKey: .totalDictationCount) ?? 0
        totalPolishCount = try container.decodeIfPresent(Int.self, forKey: .totalPolishCount) ?? 0
        totalWorkflowCount = try container.decodeIfPresent(Int.self, forKey: .totalWorkflowCount) ?? 0
        totalWordCount = try container.decodeIfPresent(Int.self, forKey: .totalWordCount) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate)
    }

    init() {}
}

// MARK: - Toast Display Item

struct ToastItem: Identifiable {
    let id = UUID()
    let milestone: Milestone
    let metadata: [String: String]

    init(milestone: Milestone, metadata: [String: String] = [:]) {
        self.milestone = milestone
        self.metadata = metadata
    }
}

// MARK: - Onboarding Progress Manager

@MainActor
@Observable
final class OnboardingProgressManager {
    static let shared = OnboardingProgressManager()

    // MARK: - Published State

    private(set) var state: OnboardingState

    /// Current toast to display (nil = no toast)
    var currentToast: ToastItem?

    /// Queue of pending toasts (rate-limited)
    private var toastQueue: [ToastItem] = []

    // MARK: - Constants

    private let stateKey = "onboardingProgressState"
    private let toastCooldownSeconds: TimeInterval = 30
    private let toastAutoDismissSeconds: TimeInterval = 5

    // MARK: - Init

    private init() {
        // Load state from UserDefaults
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(OnboardingState.self, from: data) {
            self.state = decoded
        } else {
            self.state = OnboardingState()
        }

        // Increment session count on launch
        incrementSession()

        log.info("OnboardingProgressManager initialized: session=\(state.sessionCount), milestones=\(state.completedMilestones.count)")
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

        // Only count new session if last session was on a different day or doesn't exist
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
            // Consecutive day
            state.currentStreak += 1
            if state.currentStreak > state.longestStreak {
                state.longestStreak = state.currentStreak
            }
        } else if daysSinceLastActive > 1 {
            // Streak broken
            state.currentStreak = 1
        }
        // daysSinceLastActive == 0 means same day, no change
    }

    // MARK: - Power User Mode

    var isPowerUser: Bool {
        get { state.powerUserMode }
        set {
            state.powerUserMode = newValue
            save()
        }
    }

    // MARK: - Milestone Checking

    func hasMilestone(_ milestone: Milestone) -> Bool {
        state.completedMilestones.contains(milestone.rawValue)
    }

    func checkAndCelebrate(_ milestone: Milestone, metadata: [String: String] = [:]) {
        // Skip if already completed
        guard !hasMilestone(milestone) else { return }

        // Mark as completed
        state.completedMilestones.insert(milestone.rawValue)
        save()

        log.info("Milestone achieved: \(milestone.rawValue)")

        // Show celebration (unless power user mode)
        if !state.powerUserMode {
            queueToast(ToastItem(milestone: milestone, metadata: metadata))
        }
    }

    // MARK: - Activity Recording

    /// Record a new memo and check for milestones
    func recordMemoCreated(wordCount: Int = 0) {
        state.totalMemoCount += 1
        state.totalWordCount += wordCount
        state.lastActiveDate = Date()
        updateStreak()
        save()

        // Check milestones
        if state.totalMemoCount == 1 {
            checkAndCelebrate(.firstMemo)
        } else if state.totalMemoCount == 10 {
            checkAndCelebrate(.tenMemos)
        } else if state.totalMemoCount == 50 {
            checkAndCelebrate(.fiftyMemos)
        } else if state.totalMemoCount == 100 {
            checkAndCelebrate(.hundredMemos)
        }

        // Word count milestones
        if state.totalWordCount >= 1000 && !hasMilestone(.thousandWords) {
            checkAndCelebrate(.thousandWords)
        } else if state.totalWordCount >= 10000 && !hasMilestone(.tenThousandWords) {
            checkAndCelebrate(.tenThousandWords)
        } else if state.totalWordCount >= 50000 && !hasMilestone(.fiftyThousandWords) {
            checkAndCelebrate(.fiftyThousandWords)
        }

        // Streak milestones
        if state.currentStreak >= 7 && !hasMilestone(.sevenDayStreak) {
            checkAndCelebrate(.sevenDayStreak)
        } else if state.currentStreak >= 30 && !hasMilestone(.thirtyDayStreak) {
            checkAndCelebrate(.thirtyDayStreak)
        }
    }

    /// Record a live dictation completed
    func recordDictationCompleted() {
        state.totalDictationCount += 1
        save()

        if state.totalDictationCount == 1 {
            checkAndCelebrate(.firstDictation)
        }
    }

    /// Record a polish operation completed
    func recordPolishCompleted() {
        state.totalPolishCount += 1
        save()

        if state.totalPolishCount == 1 {
            checkAndCelebrate(.firstPolish)
        }
    }

    /// Record a workflow execution
    func recordWorkflowRun() {
        state.totalWorkflowCount += 1
        save()

        if state.totalWorkflowCount == 1 {
            checkAndCelebrate(.firstWorkflow)
        }
    }

    // MARK: - Sync with Database

    /// Sync milestone checks with actual database counts.
    /// Call this from HomeScreen after data loads to catch up on any milestones
    /// that might have been missed (e.g., user had data before onboarding system was added)
    func syncWithDatabaseCounts(memoCount: Int, dictationCount: Int, totalWords: Int, streak: Int) {
        // Update internal counts to match database (take the max to not lose tracked progress)
        state.totalMemoCount = max(state.totalMemoCount, memoCount)
        state.totalDictationCount = max(state.totalDictationCount, dictationCount)
        state.totalWordCount = max(state.totalWordCount, totalWords)
        state.currentStreak = max(state.currentStreak, streak)
        if state.currentStreak > state.longestStreak {
            state.longestStreak = state.currentStreak
        }
        save()

        // Check memo milestones (only if not already achieved)
        if memoCount >= 1 && !hasMilestone(.firstMemo) {
            // Don't celebrate retroactively for first memo - only celebrate new ones
            state.completedMilestones.insert(Milestone.firstMemo.rawValue)
            save()
        }
        if memoCount >= 10 && !hasMilestone(.tenMemos) {
            state.completedMilestones.insert(Milestone.tenMemos.rawValue)
            save()
        }
        if memoCount >= 50 && !hasMilestone(.fiftyMemos) {
            state.completedMilestones.insert(Milestone.fiftyMemos.rawValue)
            save()
        }
        if memoCount >= 100 && !hasMilestone(.hundredMemos) {
            state.completedMilestones.insert(Milestone.hundredMemos.rawValue)
            save()
        }

        // Check dictation milestones
        if dictationCount >= 1 && !hasMilestone(.firstDictation) {
            state.completedMilestones.insert(Milestone.firstDictation.rawValue)
            save()
        }

        // Check word count milestones
        if totalWords >= 1000 && !hasMilestone(.thousandWords) {
            state.completedMilestones.insert(Milestone.thousandWords.rawValue)
            save()
        }
        if totalWords >= 10000 && !hasMilestone(.tenThousandWords) {
            state.completedMilestones.insert(Milestone.tenThousandWords.rawValue)
            save()
        }
        if totalWords >= 50000 && !hasMilestone(.fiftyThousandWords) {
            state.completedMilestones.insert(Milestone.fiftyThousandWords.rawValue)
            save()
        }

        // Check streak milestones
        if streak >= 7 && !hasMilestone(.sevenDayStreak) {
            state.completedMilestones.insert(Milestone.sevenDayStreak.rawValue)
            save()
        }
        if streak >= 30 && !hasMilestone(.thirtyDayStreak) {
            state.completedMilestones.insert(Milestone.thirtyDayStreak.rawValue)
            save()
        }

        log.debug("Synced with database: memos=\(memoCount), dictations=\(dictationCount), words=\(totalWords), streak=\(streak)")
    }

    // MARK: - Tip Management

    func hasDismissedTip(_ tip: TipID) -> Bool {
        state.dismissedTips.contains(tip.rawValue)
    }

    func dismissTip(_ tip: TipID) {
        state.dismissedTips.insert(tip.rawValue)
        save()
    }

    func shouldShowTip(_ tip: TipID) -> Bool {
        guard !state.powerUserMode else { return false }
        guard !hasDismissedTip(tip) else { return false }

        switch tip {
        case .commandButton:
            // Show on first interstitial
            return state.totalPolishCount == 0
        case .workflowsIntro:
            // Show after 3 polishes
            return state.totalPolishCount >= 3 && state.totalWorkflowCount == 0
        case .liveMode:
            // Show after first memo
            return state.totalMemoCount >= 1 && state.totalDictationCount == 0
        case .keyboardShortcuts:
            // Show after 5 sessions
            return state.sessionCount >= 5
        }
    }

    // MARK: - Toast Queue Management

    private func queueToast(_ item: ToastItem) {
        // Check cooldown
        if let lastShown = state.lastToastShownAt {
            let elapsed = Date().timeIntervalSince(lastShown)
            if elapsed < toastCooldownSeconds {
                // Queue for later
                toastQueue.append(item)
                return
            }
        }

        showToast(item)
    }

    private func showToast(_ item: ToastItem) {
        state.lastToastShownAt = Date()
        save()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentToast = item
        }

        // Auto-dismiss after delay
        Task {
            try? await Task.sleep(for: .seconds(toastAutoDismissSeconds))
            await MainActor.run {
                if self.currentToast?.id == item.id {
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
                        self.showToast(next)
                    }
                }
            }
        }
    }

    // MARK: - Progress Stats

    var completedMilestoneCount: Int {
        state.completedMilestones.count
    }

    var totalMilestones: Int {
        Milestone.allCases.count
    }

    var progressPercentage: Double {
        guard totalMilestones > 0 else { return 0 }
        return Double(completedMilestoneCount) / Double(totalMilestones) * 100
    }

    // MARK: - Reset (for testing)

    func resetProgress() {
        state = OnboardingState()
        state.sessionCount = 1
        state.lastSessionDate = Date()
        currentToast = nil
        toastQueue.removeAll()
        save()
        log.info("Onboarding progress reset")
    }
}
