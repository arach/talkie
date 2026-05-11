//
//  VoiceIntentRecognizer.swift
//  TalkieKit
//
//  Voice intent recognition using NLEmbedding for semantic similarity matching.
//  Maps vague voice commands to navigation intents.
//

import Foundation
import NaturalLanguage

// MARK: - Voice Intent

/// Navigation intents that can be triggered by voice commands
public enum VoiceIntent: String, CaseIterable, Sendable, Codable {
    // MARK: - Main Navigation
    case navigateHome
    case navigateRecordings
    case navigateDictations
    case navigateSettings
    case navigateWorkflows
    case navigateModels
    case navigateDrafts
    case navigateStats
    case navigateActivityLog
    case navigateSystemConsole
    case navigatePendingActions
    case navigateAIResults

    // MARK: - Settings Subsections
    case settingsAppearance
    case settingsHelpers
    case settingsVoiceIO
    case settingsDictionary
    case settingsAIProviders
    case settingsModels
    case settingsStorage
    case settingsSync
    case settingsActions
    case settingsAutomations
    case settingsExtensions
    case settingsPermissions
    case settingsDebug

    // MARK: - Actions
    case openSearch
    case openCommandPalette
    case goBack
    case startDictation
    case stopDictation
    case syncNow
    case unknown

    public var displayName: String {
        switch self {
        // Main Navigation
        case .navigateHome: return "Go Home"
        case .navigateRecordings: return "Open Recordings"
        case .navigateDictations: return "Open Dictations"
        case .navigateSettings: return "Open Settings"
        case .navigateWorkflows: return "Open Workflows"
        case .navigateModels: return "Open Models"
        case .navigateDrafts: return "Open Drafts"
        case .navigateStats: return "Open Stats"
        case .navigateActivityLog: return "Activity Log"
        case .navigateSystemConsole: return "System Console"
        case .navigatePendingActions: return "Pending Actions"
        case .navigateAIResults: return "AI Results"

        // Settings Subsections
        case .settingsAppearance: return "Appearance Settings"
        case .settingsHelpers: return "Background Services"
        case .settingsVoiceIO: return "Voice Settings"
        case .settingsDictionary: return "Dictionary"
        case .settingsAIProviders: return "API Keys"
        case .settingsModels: return "Model Settings"
        case .settingsStorage: return "Storage Settings"
        case .settingsSync: return "Sync Settings"
        case .settingsActions: return "Actions Settings"
        case .settingsAutomations: return "Automations"
        case .settingsExtensions: return "Extensions"
        case .settingsPermissions: return "Permissions"
        case .settingsDebug: return "Debug Info"

        // Actions
        case .openSearch: return "Open Search"
        case .openCommandPalette: return "Open Commands"
        case .goBack: return "Go Back"
        case .startDictation: return "Start Dictation"
        case .stopDictation: return "Stop Dictation"
        case .syncNow: return "Sync Now"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Intent Result

/// Result of intent recognition with confidence score
public struct IntentResult: Sendable, Codable, Equatable {
    public let intent: VoiceIntent
    public let confidence: Float
    public let rawText: String
    public let matchedPhrase: String?

    public init(intent: VoiceIntent, confidence: Float, rawText: String, matchedPhrase: String? = nil) {
        self.intent = intent
        self.confidence = confidence
        self.rawText = rawText
        self.matchedPhrase = matchedPhrase
    }

    /// Whether the confidence meets the threshold for action
    public var isActionable: Bool {
        confidence >= 0.6 && intent != .unknown
    }

    /// Decode from JSON string (returned by Engine when using .intentRecognition post-processing)
    public static func decode(from jsonString: String) -> IntentResult? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(IntentResult.self, from: data)
    }
}

// MARK: - Intent Phrase Mapping

/// Maps intents to their canonical phrases for embedding comparison
private struct IntentPhraseMapping {
    let intent: VoiceIntent
    let phrases: [String]

    static let all: [IntentPhraseMapping] = [
        // MARK: - Main Navigation

        // Home
        IntentPhraseMapping(intent: .navigateHome, phrases: [
            "go home",
            "go to home",
            "main screen",
            "dashboard",
            "home page",
            "back to home",
            "show home",
            "return to home",
            "return home",
            "take me home",
            "main page",
            "start screen",
            "beginning"
        ]),

        // Recordings
        IntentPhraseMapping(intent: .navigateRecordings, phrases: [
            "recordings",
            "open recordings",
            "show recordings",
            "go to recordings",
            "voice memos",
            "memos",
            "my recordings",
            "show my memos",
            "recs",
            "show recs",
            "my recs",
            "saved memos",
            "saved recordings",
            "voice notes",
            "my voice notes",
            "what I recorded",
            "recorded yesterday",
            "saved memo"
        ]),

        // Dictations
        IntentPhraseMapping(intent: .navigateDictations, phrases: [
            "dictations",
            "open dictations",
            "show dictations",
            "live dictation",
            "recent dictations",
            "go to dictations",
            "utterances",
            "transcriptions",
            "show transcriptions",
            "my transcriptions",
            "transcription history",
            "transcribed text",
            "what I said",
            "dicts",
            "show dicts",
            "my dicts",
            "dictation list"
        ]),

        // Settings (general)
        IntentPhraseMapping(intent: .navigateSettings, phrases: [
            "settings",
            "open settings",
            "preferences",
            "options",
            "go to settings",
            "show settings",
            "configuration"
        ]),

        // Workflows
        IntentPhraseMapping(intent: .navigateWorkflows, phrases: [
            "workflows",
            "open workflows",
            "go to workflows",
            "show workflows",
            "my workflows",
            "workflow editor"
        ]),

        // Models (main screen)
        IntentPhraseMapping(intent: .navigateModels, phrases: [
            "models",
            "open models",
            "ai models",
            "transcription models",
            "go to models",
            "show models",
            "model manager"
        ]),

        // Drafts / Compose
        IntentPhraseMapping(intent: .navigateDrafts, phrases: [
            "drafts",
            "open drafts",
            "compose",
            "new draft",
            "scratch pad",
            "go to drafts",
            "write something",
            "text editor"
        ]),

        // Stats / Insights
        IntentPhraseMapping(intent: .navigateStats, phrases: [
            "stats",
            "statistics",
            "analytics",
            "show stats",
            "go to stats",
            "insights",
            "live dashboard"
        ]),

        // Activity Log
        IntentPhraseMapping(intent: .navigateActivityLog, phrases: [
            "activity log",
            "activity",
            "event log",
            "history",
            "show activity",
            "recent activity",
            "see the log",
            "view log",
            "what I did",
            "what happened",
            "event history"
        ]),

        // System Console
        IntentPhraseMapping(intent: .navigateSystemConsole, phrases: [
            "system console",
            "console",
            "logs",
            "debug logs",
            "system logs",
            "show console"
        ]),

        // Pending Actions
        IntentPhraseMapping(intent: .navigatePendingActions, phrases: [
            "pending actions",
            "pending",
            "queued actions",
            "action queue",
            "show pending"
        ]),

        // AI Results
        IntentPhraseMapping(intent: .navigateAIResults, phrases: [
            "ai results",
            "results",
            "ai output",
            "actions",
            "show results",
            "ai generated",
            "what ai generated",
            "generated content",
            "ai responses"
        ]),

        // MARK: - Settings Subsections

        // Appearance
        IntentPhraseMapping(intent: .settingsAppearance, phrases: [
            "appearance settings",
            "appearance",
            "theme settings",
            "theme",
            "colors",
            "dark mode",
            "light mode",
            "visual settings"
        ]),

        // Helpers / Background Services
        IntentPhraseMapping(intent: .settingsHelpers, phrases: [
            "helper settings",
            "helpers",
            "background services",
            "services",
            "talkie agent settings",
            "talkie live settings",
            "engine settings"
        ]),

        // Voice I/O
        IntentPhraseMapping(intent: .settingsVoiceIO, phrases: [
            "voice settings",
            "voice io",
            "microphone settings",
            "audio settings",
            "capture settings",
            "dictation settings",
            "input settings",
            "mic settings",
            "change mic",
            "change microphone",
            "configure microphone",
            "microphone"
        ]),

        // Dictionary
        IntentPhraseMapping(intent: .settingsDictionary, phrases: [
            "dictionary settings",
            "dictionary",
            "word replacements",
            "replacements",
            "custom words",
            "vocabulary"
        ]),

        // AI Providers / API Keys
        IntentPhraseMapping(intent: .settingsAIProviders, phrases: [
            "api keys",
            "api settings",
            "ai providers",
            "providers",
            "openai settings",
            "anthropic settings",
            "provider settings",
            "api key settings",
            "add api key",
            "add key",
            "keys"
        ]),

        // Models (settings)
        IntentPhraseMapping(intent: .settingsModels, phrases: [
            "model settings",
            "transcription settings",
            "whisper settings",
            "tts settings",
            "text to speech settings",
            "llm settings",
            "model configuration",
            "configure models"
        ]),

        // Storage
        IntentPhraseMapping(intent: .settingsStorage, phrases: [
            "storage settings",
            "storage",
            "database settings",
            "files settings",
            "data settings",
            "disk usage"
        ]),

        // Sync
        IntentPhraseMapping(intent: .settingsSync, phrases: [
            "sync settings",
            "sync",
            "icloud settings",
            "ios sync",
            "cloud sync",
            "synchronization"
        ]),

        // Actions
        IntentPhraseMapping(intent: .settingsActions, phrases: [
            "action settings",
            "quick actions",
            "context actions",
            "action configuration"
        ]),

        // Automations
        IntentPhraseMapping(intent: .settingsAutomations, phrases: [
            "automation settings",
            "automations",
            "auto actions",
            "triggers"
        ]),

        // Extensions
        IntentPhraseMapping(intent: .settingsExtensions, phrases: [
            "extension settings",
            "extensions",
            "plugins",
            "apps",
            "add ons"
        ]),

        // Permissions
        IntentPhraseMapping(intent: .settingsPermissions, phrases: [
            "permission settings",
            "permissions",
            "privacy settings",
            "access settings",
            "security settings"
        ]),

        // Debug
        IntentPhraseMapping(intent: .settingsDebug, phrases: [
            "debug settings",
            "debug info",
            "debug",
            "diagnostics",
            "troubleshooting",
            "developer settings"
        ]),

        // MARK: - Actions

        // Search
        IntentPhraseMapping(intent: .openSearch, phrases: [
            "search",
            "open search",
            "find",
            "look for",
            "search for",
            "find something",
            "search memos",
            "search recordings"
        ]),

        // Command Palette
        IntentPhraseMapping(intent: .openCommandPalette, phrases: [
            "commands",
            "open commands",
            "command palette",
            "show commands",
            "quick commands"
        ]),

        // Go Back (be specific to avoid matching "back to home", "return to settings", etc.)
        IntentPhraseMapping(intent: .goBack, phrases: [
            "go back",
            "go to previous",
            "previous screen",
            "previous page",
            "navigate back"
        ]),

        // Start Dictation
        IntentPhraseMapping(intent: .startDictation, phrases: [
            "start dictation",
            "start recording",
            "start listening",
            "begin dictation",
            "record",
            "listen",
            "dictate",
            // Memo-related phrases
            "start a memo",
            "record a memo",
            "take a memo",
            "new memo",
            "capture a memo",
            "new recording",
            "start a voice memo",
            "record a voice memo",
            "take a note",
            "capture a thought",
            "jot this down",
            "voice memo"
        ]),

        // Stop Dictation
        IntentPhraseMapping(intent: .stopDictation, phrases: [
            "stop dictation",
            "stop recording",
            "stop listening",
            "end dictation",
            "stop",
            "finish recording",
            "done recording"
        ]),

        // Sync
        IntentPhraseMapping(intent: .syncNow, phrases: [
            "sync now",
            "sync",
            "synchronize",
            "sync data",
            "refresh sync",
            "update sync"
        ])
    ]
}

// MARK: - Voice Intent Recognizer

/// Recognizes voice navigation intents using NLEmbedding semantic similarity
@MainActor
public final class VoiceIntentRecognizer: Sendable {
    public static let shared = VoiceIntentRecognizer()

    /// Minimum confidence threshold for intent matching
    public let confidenceThreshold: Float = 0.6

    /// Pre-computed embeddings for all intent phrases
    private let phraseEmbeddings: [(intent: VoiceIntent, phrase: String, embedding: [Double])]

    /// NLEmbedding for English
    private let embedding: NLEmbedding?

    private init() {
        // Load English word embedding
        embedding = NLEmbedding.wordEmbedding(for: .english)

        // Pre-compute embeddings for all phrases
        var embeddings: [(VoiceIntent, String, [Double])] = []

        if let emb = embedding {
            for mapping in IntentPhraseMapping.all {
                for phrase in mapping.phrases {
                    if let vector = Self.computeSentenceEmbedding(phrase, using: emb) {
                        embeddings.append((mapping.intent, phrase, vector))
                    }
                }
            }
        }

        phraseEmbeddings = embeddings
    }

    // MARK: - Public API

    /// Recognize intent from transcribed text
    /// - Parameter text: The transcribed voice command text
    /// - Returns: IntentResult with the best matching intent and confidence
    public func recognize(_ text: String) async -> IntentResult {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            return IntentResult(intent: .unknown, confidence: 0, rawText: text)
        }

        // First try exact/substring matching for high confidence
        if let exactMatch = findExactMatch(normalizedText) {
            return exactMatch
        }

        // Fall back to semantic similarity
        guard let emb = embedding,
              let inputVector = Self.computeSentenceEmbedding(normalizedText, using: emb) else {
            return IntentResult(intent: .unknown, confidence: 0, rawText: text)
        }

        var bestMatch: (intent: VoiceIntent, phrase: String, similarity: Float) = (.unknown, "", 0)

        for (intent, phrase, phraseVector) in phraseEmbeddings {
            let similarity = Self.cosineSimilarity(inputVector, phraseVector)
            if similarity > bestMatch.similarity {
                bestMatch = (intent, phrase, similarity)
            }
        }

        return IntentResult(
            intent: bestMatch.similarity >= confidenceThreshold ? bestMatch.intent : .unknown,
            confidence: bestMatch.similarity,
            rawText: text,
            matchedPhrase: bestMatch.phrase
        )
    }

    // MARK: - Exact Matching

    /// Try to find an exact or substring match for common phrases
    /// Uses longest-match-wins strategy to prefer specific subsections over general categories
    private func findExactMatch(_ text: String) -> IntentResult? {
        var bestMatch: (intent: VoiceIntent, phrase: String, confidence: Float)?

        // Check for exact matches or key phrases contained in text
        for mapping in IntentPhraseMapping.all {
            for phrase in mapping.phrases {
                // Exact match - highest confidence
                if text == phrase {
                    // Exact matches always win, but prefer longer phrases
                    if bestMatch == nil || phrase.count > bestMatch!.phrase.count || bestMatch!.confidence < 1.0 {
                        bestMatch = (mapping.intent, phrase, 1.0)
                    }
                }
                // Text contains the phrase (for "open search please" matching "open search")
                else if text.contains(phrase) && phrase.count >= 4 {
                    // Prefer longer matching phrases (more specific)
                    // e.g., "appearance settings" (19 chars) beats "settings" (8 chars)
                    if bestMatch == nil || phrase.count > bestMatch!.phrase.count {
                        bestMatch = (mapping.intent, phrase, 0.95)
                    }
                }
            }
        }

        if let match = bestMatch {
            return IntentResult(
                intent: match.intent,
                confidence: match.confidence,
                rawText: text,
                matchedPhrase: match.phrase
            )
        }

        return nil
    }

    // MARK: - Embedding Computation

    /// Compute sentence embedding by averaging word embeddings
    private static func computeSentenceEmbedding(_ text: String, using embedding: NLEmbedding) -> [Double]? {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return nil }

        var sumVector: [Double]?
        var wordCount = 0

        for word in words {
            if let vector = embedding.vector(for: word) {
                if sumVector == nil {
                    sumVector = vector
                } else {
                    for i in 0..<vector.count {
                        sumVector![i] += vector[i]
                    }
                }
                wordCount += 1
            }
        }

        guard let sum = sumVector, wordCount > 0 else { return nil }

        // Average the vectors
        return sum.map { $0 / Double(wordCount) }
    }

    /// Compute cosine similarity between two vectors
    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return Float(dotProduct / denominator)
    }
}
