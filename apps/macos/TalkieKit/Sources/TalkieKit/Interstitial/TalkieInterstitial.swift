//
//  TalkieInterstitial.swift
//  TalkieKit
//
//  Public facade for the interstitial editor component.
//  This is the ONLY public API - all internals are hidden.
//
//  Usage:
//    TalkieInterstitial.show(text: "Hello world", dictationId: 123)
//    TalkieInterstitial.dismiss()
//

import SwiftUI
import AppKit

// MARK: - Public API

/// Lightweight facade for the interstitial editor component
public enum TalkieInterstitial {

    /// Show the interstitial editor with text
    /// - Parameters:
    ///   - text: The text to edit
    ///   - dictationId: Optional ID for persistence tracking
    ///   - config: Optional configuration overrides
    @MainActor
    public static func show(
        text: String,
        dictationId: Int64? = nil,
        config: Config = .init()
    ) {
        InterstitialCore.shared.show(text: text, dictationId: dictationId, config: config)
    }

    /// Dismiss the interstitial
    @MainActor
    public static func dismiss() {
        InterstitialCore.shared.dismiss()
    }

    /// Whether the interstitial is currently visible
    @MainActor
    public static var isVisible: Bool {
        InterstitialCore.shared.isVisible
    }

    /// Current text (for reading state if needed)
    @MainActor
    public static var currentText: String? {
        guard isVisible else { return nil }
        return InterstitialCore.shared.text
    }

    /// Current revisions
    @MainActor
    public static var revisions: [Revision] {
        InterstitialCore.shared.revisions.map { rev in
            Revision(
                instruction: rev.instruction,
                textBefore: rev.before,
                textAfter: rev.after,
                wasAccepted: rev.accepted,
                timestamp: rev.timestamp
            )
        }
    }
}

// MARK: - Public Types

extension TalkieInterstitial {

    /// Configuration for the interstitial
    public struct Config {
        /// Called when draft is created/updated (for persistence)
        public var onDraftUpdate: ((Draft) -> Void)?

        /// Called when user dismisses
        public var onDismiss: ((DismissAction) -> Void)?

        /// LLM API key (reads from encrypted store if nil)
        public var llmAPIKey: String?

        /// LLM model to use
        public var llmModel: String

        /// LLM provider
        public var llmProvider: LLMProvider

        /// Initialize with explicit values or read from shared settings
        /// - Parameters:
        ///   - onDraftUpdate: Called when draft is updated
        ///   - onDismiss: Called when dismissed
        ///   - llmAPIKey: API key override (normally reads from encrypted store)
        ///   - llmModel: Model override (nil = read from shared settings)
        ///   - llmProvider: Provider override (nil = read from shared settings)
        public init(
            onDraftUpdate: ((Draft) -> Void)? = nil,
            onDismiss: ((DismissAction) -> Void)? = nil,
            llmAPIKey: String? = nil,
            llmModel: String? = nil,
            llmProvider: LLMProvider? = nil
        ) {
            self.onDraftUpdate = onDraftUpdate
            self.onDismiss = onDismiss
            self.llmAPIKey = llmAPIKey

            // Read from shared settings if not explicitly provided
            let settings = TalkieSharedSettings

            // Provider: explicit > shared settings > default (openai)
            if let provider = llmProvider {
                self.llmProvider = provider
            } else if let savedProvider = settings.string(forKey: AgentSettingsKey.polishProvider),
                      let provider = LLMProvider(rawValue: savedProvider) {
                self.llmProvider = provider
            } else {
                self.llmProvider = .openai  // Default to OpenAI (user's preference)
            }

            // Model: explicit > shared settings > default based on provider
            if let model = llmModel {
                self.llmModel = model
            } else if let savedModel = settings.string(forKey: AgentSettingsKey.polishModel) {
                self.llmModel = savedModel
            } else {
                // Default model based on provider
                switch self.llmProvider {
                case .openai:
                    self.llmModel = "gpt-4o-mini"
                case .anthropic:
                    self.llmModel = "claude-3-haiku-20240307"
                }
            }
        }
    }

    /// Current state of the draft
    public struct Draft: Sendable {
        public let text: String
        public let originalText: String
        public let revisions: [Revision]
        public let dictationId: Int64?
        public let createdAt: Date
        public let updatedAt: Date
    }

    /// A single revision in the editing session
    public struct Revision: Sendable {
        public let instruction: String
        public let textBefore: String
        public let textAfter: String
        public let wasAccepted: Bool
        public let timestamp: Date
    }

    /// How the user dismissed
    public enum DismissAction: Sendable {
        case copied
        case pasted
        case savedAsMemo
        case discarded
    }

    /// LLM Provider
    public enum LLMProvider: String, Sendable {
        case anthropic
        case openai
    }
}
