//
//  DictionaryURLExtractor.swift
//  Talkie
//
//  Extract domain-specific terminology from web pages using LLM
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - URL Extraction Service

@MainActor
final class DictionaryURLExtractor: ObservableObject {
    static let shared = DictionaryURLExtractor()

    @Published private(set) var isExtracting: Bool = false
    @Published private(set) var extractedEntries: [DictionaryEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var pageTitle: String?

    private init() {}

    // MARK: - Extraction

    func extractFromURL(
        _ urlString: String,
        providerId: String,
        modelId: String
    ) async {
        guard !isExtracting else { return }

        isExtracting = true
        lastError = nil
        extractedEntries = []
        pageTitle = nil

        do {
            // 1. Validate URL
            guard let url = URL(string: urlString), url.scheme != nil else {
                lastError = "Invalid URL format"
                isExtracting = false
                return
            }

            // 2. Fetch page content
            let (content, title) = try await fetchPageContent(url)
            pageTitle = title

            guard !content.isEmpty else {
                lastError = "Could not extract text from page"
                isExtracting = false
                return
            }

            // 3. Get the LLM provider
            guard let provider = LLMProviderRegistry.shared.provider(for: providerId) else {
                lastError = "Provider not found: \(providerId)"
                isExtracting = false
                return
            }

            guard await provider.isAvailable else {
                lastError = "Provider \(provider.name) is not available. Check API key."
                isExtracting = false
                return
            }

            // 4. Build prompt and call LLM
            let prompt = buildExtractionPrompt(content: content, url: urlString)
            let response = try await provider.generate(
                prompt: prompt,
                model: modelId,
                options: GenerationOptions(temperature: 0.3, maxTokens: 2000)
            )

            // 5. Parse response
            extractedEntries = parseResponse(response)

            log.info("Extracted \(extractedEntries.count) entries from URL")

        } catch {
            log.error("Failed to extract from URL", error: error)
            lastError = error.localizedDescription
        }

        isExtracting = false
    }

    private func fetchPageContent(_ url: URL) async throws -> (content: String, title: String?) {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Extract title
        var title: String?
        if let titleRange = html.range(of: "<title>"),
           let titleEndRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            title = String(html[titleRange.upperBound..<titleEndRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip HTML tags for content (simple approach)
        let content = stripHTML(html)

        return (content, title)
    }

    private func stripHTML(_ html: String) -> String {
        // Remove script and style blocks
        var text = html
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Normalize whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildExtractionPrompt(content: String, url: String) -> String {
        """
        Analyze the following web page content and extract domain-specific terminology that would be useful for a voice dictation dictionary.

        Focus on:
        1. Technical terms and their common misspellings/mishearings
        2. Product names, brand names, and proper nouns
        3. Abbreviations and their expansions
        4. Specialized jargon from this domain
        5. Names of people, places, or concepts specific to this content

        For each term, provide an entry showing how it might be misheard and the correct spelling.

        Return the results in this exact JSON format:
        ```json
        [
          {"from": "potential mishearing", "to": "correct term"},
          {"from": "another variant", "to": "correct term"}
        ]
        ```

        Only include terms that are specific to this domain/topic.
        Include 2-3 variants for important terms if there are multiple ways they could be misheard.
        Limit to 20 most important entries.

        URL: \(url)

        PAGE CONTENT:
        ---
        \(content.prefix(8000))
        ---

        Respond with ONLY the JSON array, no other text.
        """
    }

    private func parseResponse(_ response: String) -> [DictionaryEntry] {
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
            let entries = try JSONDecoder().decode([ExtractedEntry].self, from: data)
            return entries.map { entry in
                DictionaryEntry(
                    trigger: entry.from,
                    replacement: entry.to,
                    matchType: .phrase
                )
            }
        } catch {
            log.warning("Failed to parse extraction response as JSON", error: error)
            return []
        }
    }

    // MARK: - Actions

    func clearResults() {
        extractedEntries.removeAll()
        pageTitle = nil
        lastError = nil
    }
}

// MARK: - Internal Parse Model

private struct ExtractedEntry: Codable {
    let from: String
    let to: String
}
