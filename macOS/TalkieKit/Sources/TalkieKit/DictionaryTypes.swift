//
//  DictionaryTypes.swift
//  TalkieKit
//
//  Shared dictionary types for word replacement
//  - Talkie: Storage & UI
//  - TalkieEngine: In-memory processing
//

import Foundation

// MARK: - Dictionary (Collection of Entries)

public struct TalkieDictionary: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var isEnabled: Bool
    public var entries: [DictionaryEntry]
    public var createdAt: Date
    public var modifiedAt: Date

    /// Source of this dictionary
    public var source: DictionarySource

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        isEnabled: Bool = true,
        entries: [DictionaryEntry] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        source: DictionarySource = .manual
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.entries = entries
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.source = source
    }

    /// Count of enabled entries
    public var enabledEntryCount: Int {
        entries.filter { $0.isEnabled }.count
    }

    /// All enabled entries
    public var enabledEntries: [DictionaryEntry] {
        entries.filter { $0.isEnabled }
    }
}

// MARK: - Dictionary Source

public enum DictionarySource: Codable, Equatable, Sendable {
    case manual           // Created by user in UI
    case imported         // Imported from file
    case preset           // Built-in preset

    public var displayName: String {
        switch self {
        case .manual: return "Personal"
        case .imported: return "Imported"
        case .preset: return "Preset"
        }
    }
}

// MARK: - Match Type

public enum DictionaryMatchType: String, Codable, CaseIterable, Sendable {
    case word            // Word boundary match (e.g., "clawd" matches "clawd" but not "clawding")
    case phrase          // Case-insensitive multi-word match (e.g., "open ai" → "OpenAI")
    case regex           // Regex with capture groups (e.g., "v(\d+)" → "version $1")
    case fuzzy           // Fuzzy match for technical terms (e.g., "Claude" catches "clawd", "claud")

    public var displayName: String {
        switch self {
        case .word: return "Word"
        case .phrase: return "Phrase"
        case .regex: return "Regex"
        case .fuzzy: return "Fuzzy"
        }
    }

    public var description: String {
        switch self {
        case .word: return "Match whole words only"
        case .phrase: return "Match phrase, ignore case"
        case .regex: return "Regular expression with $1, $2 capture groups"
        case .fuzzy: return "Approximate match for misspellings/mishearings"
        }
    }

    // MARK: - Legacy Decoding Support

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Map legacy values to new ones
        switch rawValue {
        case "exact":
            self = .word
        case "caseInsensitive":
            self = .phrase
        default:
            if let value = DictionaryMatchType(rawValue: rawValue) {
                self = value
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown matchType: \(rawValue)"
                )
            }
        }
    }
}

// MARK: - Dictionary Entry

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var trigger: String           // What to look for
    public var replacement: String       // What to replace with
    public var matchType: DictionaryMatchType
    public var isEnabled: Bool
    public var category: String?         // Optional grouping (e.g., "Technical", "Names")
    public var createdAt: Date
    public var usageCount: Int           // Track how often this fires

    public init(
        id: UUID = UUID(),
        trigger: String,
        replacement: String,
        matchType: DictionaryMatchType = .word,
        isEnabled: Bool = true,
        category: String? = nil,
        createdAt: Date = Date(),
        usageCount: Int = 0
    ) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
        self.matchType = matchType
        self.isEnabled = isEnabled
        self.category = category
        self.createdAt = createdAt
        self.usageCount = usageCount
    }
}

// MARK: - Processing Result

public struct DictionaryProcessingResult: Sendable {
    public let original: String
    public let processed: String
    public let replacements: [ReplacementInfo]

    public struct ReplacementInfo: Sendable {
        public let trigger: String
        public let replacement: String
        public let count: Int

        public init(trigger: String, replacement: String, count: Int) {
            self.trigger = trigger
            self.replacement = replacement
            self.count = count
        }
    }

    public var hasChanges: Bool {
        !replacements.isEmpty
    }

    public var replacementSummary: String {
        if replacements.isEmpty { return "No replacements" }

        let total = replacements.reduce(0) { $0 + $1.count }
        let details = replacements.map { "\($0.trigger) -> \($0.replacement)" }
            .joined(separator: ", ")

        return "\(total) replacement\(total == 1 ? "" : "s"): \(details)"
    }

    public init(original: String, processed: String, replacements: [ReplacementInfo]) {
        self.original = original
        self.processed = processed
        self.replacements = replacements
    }
}
