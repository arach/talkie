//
//  VoiceNavigationHandler.swift
//  TalkieAgent
//
//  Handles voice navigation intent detection and routing to Talkie via XPC.
//  Sits between AmbientController and the XPC layer.
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Voice Navigation Handler

/// Handles voice navigation by recognizing intents and sending them to Talkie
@MainActor
final class VoiceNavigationHandler {
    static let shared = VoiceNavigationHandler()

    /// Minimum confidence required to trigger navigation (vs typing the text)
    private let navigationThreshold: Float = 0.7

    /// Whether voice navigation is enabled
    var isEnabled: Bool = true

    private init() {}

    // MARK: - Public API

    /// Process transcribed text for potential navigation intent
    /// - Parameters:
    ///   - text: The transcribed command text
    ///   - completion: Called with true if navigation was triggered, false if text should be typed
    /// - Returns: Whether the text was handled as navigation (true) or should be typed (false)
    func processCommand(_ text: String) async -> Bool {
        guard isEnabled else {
            log.debug("Voice navigation disabled, skipping intent check")
            return false
        }

        let result = await VoiceIntentRecognizer.shared.recognize(text)

        log.info("Intent recognition result",
                 detail: "intent=\(result.intent.rawValue) confidence=\(String(format: "%.2f", result.confidence)) text='\(text.prefix(50))'")

        // Check if confidence meets navigation threshold
        guard result.confidence >= navigationThreshold && result.intent != .unknown else {
            log.debug("Below navigation threshold or unknown intent")
            return false
        }

        // Send navigation intent to Talkie via XPC
        sendNavigationToTalkie(result)

        return true
    }

    /// Check if text looks like a navigation command (quick pre-filter)
    /// Used for fast rejection before full intent recognition
    func looksLikeNavigation(_ text: String) -> Bool {
        let lowered = text.lowercased()

        // Quick keyword check for navigation-like phrases
        let navigationKeywords = [
            "go to", "open", "show", "navigate",
            "search", "find", "back", "home",
            "settings", "recordings", "workflows",
            "models", "drafts", "stats", "commands"
        ]

        return navigationKeywords.contains { lowered.contains($0) }
    }

    // MARK: - Private

    private func sendNavigationToTalkie(_ result: IntentResult) {
        log.info("Sending voice navigation to Talkie",
                 detail: "\(result.intent.displayName) (confidence: \(String(format: "%.0f%%", result.confidence * 100)))")

        TalkieAgentXPCService.shared.notifyVoiceNavigation(
            intent: result.intent.rawValue,
            confidence: result.confidence,
            rawText: result.rawText
        )
    }
}
