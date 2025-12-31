//
//  DictionaryTypes.swift
//  TalkieKit
//
//  Shared dictionary types for word replacement
//  - Talkie: Storage & UI
//  - TalkieEngine: In-memory processing
//

import Foundation

// MARK: - Match Type

public enum DictionaryMatchType: String, Codable, CaseIterable, Sendable {
    case exact           // Word boundary match (e.g., "react" matches "react" but not "reaction")
    case caseInsensitive // Case-insensitive anywhere (e.g., "React", "REACT", "react" all match)

    public var displayName: String {
        switch self {
        case .exact: return "Exact Word"
        case .caseInsensitive: return "Case Insensitive"
        }
    }

    public var description: String {
        switch self {
        case .exact: return "Match whole words only"
        case .caseInsensitive: return "Match anywhere, ignore case"
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
        matchType: DictionaryMatchType = .exact,
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
