//
//  DictionarySuggestionService.swift
//  Talkie
//
//  AI-powered dictionary suggestions by analyzing recent transcriptions
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Suggestion Entry

struct DictionarySuggestion: Identifiable, Codable {
    let id: UUID
    let from: String         // The misspelled/misheard word
    let to: String           // The suggested correction
    let confidence: Double   // 0.0 - 1.0
    let context: String?     // Where it was found

    init(id: UUID = UUID(), from: String, to: String, confidence: Double, context: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.confidence = confidence
        self.context = context
    }
}

// MARK: - Pending Suggestions Storage

struct PendingSuggestions: Codable {
    let generatedAt: Date
    let llmUsed: String
    let timeRange: String
    let entries: [DictionarySuggestion]
}

// MARK: - Time Range

enum SuggestionTimeRange: String, CaseIterable, Identifiable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case all = "all"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenDays: return "Last 7 days"
        case .thirtyDays: return "Last 30 days"
        case .all: return "All time"
        }
    }

    var daysAgo: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .all: return nil
        }
    }
}

// MARK: - Suggestion Service

@MainActor
final class DictionarySuggestionService: ObservableObject {
    static let shared = DictionarySuggestionService()

    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var pendingSuggestions: [DictionarySuggestion] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastAnalyzedAt: Date?

    private let suggestionsFileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let suggestionsDir = appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
            .appendingPathComponent("_suggestions", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: suggestionsDir, withIntermediateDirectories: true)

        suggestionsFileURL = suggestionsDir.appendingPathComponent("pending.json")

        // Load any existing pending suggestions
        loadPendingSuggestions()
    }

    // MARK: - File Operations

    private func loadPendingSuggestions() {
        guard FileManager.default.fileExists(atPath: suggestionsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: suggestionsFileURL)
            let pending = try JSONDecoder().decode(PendingSuggestions.self, from: data)
            pendingSuggestions = pending.entries
            lastAnalyzedAt = pending.generatedAt
            log.info("Loaded \(pending.entries.count) pending suggestions")
        } catch {
            log.warning("Failed to load pending suggestions", error: error)
        }
    }

    private func savePendingSuggestions(llmUsed: String, timeRange: String) {
        let pending = PendingSuggestions(
            generatedAt: Date(),
            llmUsed: llmUsed,
            timeRange: timeRange,
            entries: pendingSuggestions
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(pending)
            try data.write(to: suggestionsFileURL, options: .atomic)
            log.info("Saved \(pendingSuggestions.count) pending suggestions")
        } catch {
            log.error("Failed to save pending suggestions", error: error)
        }
    }

    // MARK: - Analysis

    func generateSuggestions(
        providerId: String,
        modelId: String,
        timeRange: SuggestionTimeRange
    ) async {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        lastError = nil

        do {
            // 1. Fetch recent memos
            let memos = try await fetchRecentMemos(timeRange: timeRange)

            guard !memos.isEmpty else {
                lastError = "No transcriptions found in the selected time range"
                isAnalyzing = false
                return
            }

            // 2. Aggregate transcription text
            let aggregatedText = memos
                .compactMap { $0.transcription }
                .joined(separator: "\n\n")

            guard !aggregatedText.isEmpty else {
                lastError = "No transcription text found"
                isAnalyzing = false
                return
            }

            // 3. Get the LLM provider
            guard let provider = LLMProviderRegistry.shared.provider(for: providerId) else {
                lastError = "Provider not found: \(providerId)"
                isAnalyzing = false
                return
            }

            guard await provider.isAvailable else {
                lastError = "Provider \(provider.name) is not available. Check API key."
                isAnalyzing = false
                return
            }

            // 4. Build prompt and call LLM
            let prompt = buildAnalysisPrompt(text: aggregatedText)
            let response = try await provider.generate(
                prompt: prompt,
                model: modelId,
                options: GenerationOptions(temperature: 0.3, maxTokens: 2000)
            )

            // 5. Parse response
            let suggestions = parseResponse(response)

            // 6. Update state
            pendingSuggestions = suggestions
            lastAnalyzedAt = Date()
            savePendingSuggestions(llmUsed: "\(providerId)/\(modelId)", timeRange: timeRange.rawValue)

            log.info("Generated \(suggestions.count) suggestions from LLM")

        } catch {
            log.error("Failed to generate suggestions", error: error)
            lastError = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func fetchRecentMemos(timeRange: SuggestionTimeRange) async throws -> [MemoModel] {
        let repository = LocalRepository()

        // Get transcribed memos
        var memos = try await repository.fetchTranscribedMemos(limit: 500)

        // Filter by time range
        if let daysAgo = timeRange.daysAgo {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            memos = memos.filter { $0.createdAt >= cutoffDate }
        }

        return memos
    }

    private func buildAnalysisPrompt(text: String) -> String {
        """
        Analyze the following transcription text and identify words that appear to be:
        1. Commonly misspelled or misheard technical terms
        2. Names that are consistently spelled incorrectly
        3. Abbreviations that should be expanded
        4. Domain-specific terms that the speech recognition got wrong

        For each issue found, provide the correction in this exact JSON format:
        ```json
        [
          {"from": "misspelled word", "to": "correct word", "confidence": 0.9},
          {"from": "another issue", "to": "correction", "confidence": 0.8}
        ]
        ```

        Only include entries where you're reasonably confident (>0.7) the correction is accurate.
        Focus on patterns that appear multiple times.
        Do not include common words or phrases that are likely intentional.

        TRANSCRIPTION TEXT:
        ---
        \(text.prefix(10000))
        ---

        Respond with ONLY the JSON array, no other text.
        """
    }

    private func parseResponse(_ response: String) -> [DictionarySuggestion] {
        // Try to extract JSON from response
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle markdown code blocks
        if let startRange = jsonString.range(of: "```json"),
           let endRange = jsonString.range(of: "```", range: startRange.upperBound..<jsonString.endIndex) {
            jsonString = String(jsonString[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = jsonString.range(of: "```"),
                  let endRange = jsonString.range(of: "```", range: startRange.upperBound..<jsonString.endIndex) {
            jsonString = String(jsonString[startRange.upperBound..<endRange.lowerBound])
        }

        // Try to find JSON array
        if let arrayStart = jsonString.firstIndex(of: "["),
           let arrayEnd = jsonString.lastIndex(of: "]") {
            jsonString = String(jsonString[arrayStart...arrayEnd])
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let entries = try JSONDecoder().decode([SuggestionEntry].self, from: data)
            return entries.map { entry in
                DictionarySuggestion(
                    from: entry.from,
                    to: entry.to,
                    confidence: entry.confidence
                )
            }
        } catch {
            log.warning("Failed to parse LLM response as JSON", error: error)
            return []
        }
    }

    // MARK: - Suggestion Management

    func acceptSuggestion(_ suggestion: DictionarySuggestion, toDictionaryId: UUID) async {
        // Create entry and add to dictionary
        let entry = DictionaryEntry(
            trigger: suggestion.from,
            replacement: suggestion.to,
            matchType: .phrase
        )

        await DictionaryManager.shared.addEntry(to: toDictionaryId, entry: entry)

        // Remove from pending
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        savePendingSuggestions(llmUsed: "manual", timeRange: "accepted")

        log.info("Accepted suggestion: '\(suggestion.from)' -> '\(suggestion.to)'")
    }

    func dismissSuggestion(_ suggestion: DictionarySuggestion) {
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        savePendingSuggestions(llmUsed: "manual", timeRange: "dismissed")
    }

    func clearAllSuggestions() {
        pendingSuggestions.removeAll()
        try? FileManager.default.removeItem(at: suggestionsFileURL)
        log.info("Cleared all pending suggestions")
    }
}

// MARK: - Internal Parse Model

private struct SuggestionEntry: Codable {
    let from: String
    let to: String
    let confidence: Double
}
