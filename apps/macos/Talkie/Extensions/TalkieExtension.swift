//
//  TalkieExtension.swift
//  Talkie
//
//  Extension framework protocols for self-contained "apps" that add capabilities.
//  Extensions subscribe to app events and can inject UI (toasts, settings).
//

import SwiftUI

// MARK: - TalkieExtension Protocol

/// Protocol for Talkie extensions - self-contained modules that add capabilities
protocol TalkieExtension: AnyObject {
    /// Unique identifier (reverse DNS recommended: com.talkie.milestones)
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Version string
    var version: String { get }

    /// Called when extension is loaded - receive host for callbacks
    func onLoad(host: TalkieExtensionHost)

    /// Called when extension is unloaded
    func onUnload()

    /// Optional: Settings UI for this extension
    @MainActor var settingsView: AnyView? { get }

    /// Whether the extension is currently enabled
    var isEnabled: Bool { get set }
}

// MARK: - TalkieExtensionHost Protocol

/// What the app exposes to extensions - event subscriptions, state access, UI injection
@MainActor
protocol TalkieExtensionHost: AnyObject {
    // MARK: - Event Subscriptions

    /// Subscribe to app events
    func subscribe(_ delegate: TalkieExtensionDelegate)

    /// Unsubscribe from app events
    func unsubscribe(_ delegate: TalkieExtensionDelegate)

    // MARK: - State Access

    /// Total number of memos
    var memoCount: Int { get }

    /// Total number of dictations
    var dictationCount: Int { get }

    /// Total words transcribed
    var totalWords: Int { get }

    /// Current streak (days in a row)
    var currentStreak: Int { get }

    /// Number of app sessions
    var sessionCount: Int { get }

    /// Number of polish operations
    var polishCount: Int { get }

    /// Number of workflow runs
    var workflowCount: Int { get }

    // MARK: - UI Injection

    /// Show a toast notification from an extension
    func showToast(_ toast: ExtensionToast)

    /// Dismiss the current toast
    func dismissToast()
}

// MARK: - TalkieExtensionDelegate Protocol

/// Delegate for receiving app events in extensions
protocol TalkieExtensionDelegate: AnyObject {
    /// Called when a memo is created
    func extensionHost(_ host: TalkieExtensionHost, didCreateMemo wordCount: Int)

    /// Called when a dictation is completed
    func extensionHost(_ host: TalkieExtensionHost, didCompleteDictation wordCount: Int)

    /// Called when a polish operation completes
    func extensionHost(_ host: TalkieExtensionHost, didCompletePolish instruction: String)

    /// Called when a workflow is run
    func extensionHost(_ host: TalkieExtensionHost, didRunWorkflow name: String)

    /// Called when an app session starts
    func extensionHost(_ host: TalkieExtensionHost, didStartSession number: Int)
}

// MARK: - Default Implementations

extension TalkieExtensionDelegate {
    func extensionHost(_ host: TalkieExtensionHost, didCreateMemo wordCount: Int) {}
    func extensionHost(_ host: TalkieExtensionHost, didCompleteDictation wordCount: Int) {}
    func extensionHost(_ host: TalkieExtensionHost, didCompletePolish instruction: String) {}
    func extensionHost(_ host: TalkieExtensionHost, didRunWorkflow name: String) {}
    func extensionHost(_ host: TalkieExtensionHost, didStartSession number: Int) {}
}

extension TalkieExtension {
    var settingsView: AnyView? { nil }
}

// MARK: - ExtensionToast

/// Toast notification that extensions can show
struct ExtensionToast: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let icon: String
    let tip: String?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        icon: String = "star.fill",
        tip: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tip = tip
        self.metadata = metadata
    }

    static func == (lhs: ExtensionToast, rhs: ExtensionToast) -> Bool {
        lhs.id == rhs.id
    }
}
