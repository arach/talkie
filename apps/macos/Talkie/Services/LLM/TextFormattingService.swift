//
//  TextFormattingService.swift
//  Talkie
//
//  Conservative Apple Intelligence passes for text readability.
//

import Foundation
import TalkieKit

#if canImport(FoundationModels)
import FoundationModels
#endif

private let textFormattingLog = Log(.transcription)

actor TextFormattingService {
    static let shared = TextFormattingService()

    struct Result: Sendable {
        let activeText: String
        let didFormat: Bool
        let outcome: Outcome

        var stepSubtitle: String {
            switch outcome {
            case .formatted:
                return "Paragraphs added"
            case .skipped(let reason):
                return reason.stepSubtitle
            case .rejected(let reason):
                return reason.stepSubtitle
            case .failed:
                return "Raw transcript kept"
            }
        }
    }

    enum Outcome: Sendable {
        case formatted
        case skipped(SkipReason)
        case rejected(ValidationFailure)
        case failed(String)
    }

    enum SkipReason: Sendable {
        case empty
        case tooShort
        case tooFewWords
        case alreadyStructured
        case notEnoughStructureSignal
        case tooLongForFirstSlice
        case unavailable
        case unsupportedLocale
        case unchanged

        var stepSubtitle: String {
            switch self {
            case .empty:
                return "No text"
            case .tooShort, .tooFewWords:
                return "Short memo"
            case .alreadyStructured:
                return "Already structured"
            case .notEnoughStructureSignal:
                return "Not needed"
            case .tooLongForFirstSlice:
                return "Too long for first slice"
            case .unavailable:
                return "Apple Intelligence unavailable"
            case .unsupportedLocale:
                return "Locale unsupported"
            case .unchanged:
                return "No changes"
            }
        }
    }

    enum ValidationFailure: Sendable {
        case empty
        case preamble
        case characterRatio
        case tokenRatio
        case tokenPreservation
        case noParagraphBreaks

        var stepSubtitle: String {
            "Raw transcript kept"
        }
    }

    private let minimumCharacterCount = 800
    private let minimumWordCount = 120
    private let maxCharacterCount = 18_000
    private let minimumSentenceCountForMediumText = 3
    private let mediumTextWordCount = 220
    private let maximumStructuredParagraphLength = 1_500

    private init() {}

    func formatTranscriptIfUseful(_ rawText: String) async -> Result {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let skipReason = skipReason(for: trimmed) {
            return Result(activeText: rawText, didFormat: false, outcome: .skipped(skipReason))
        }

        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return Result(activeText: rawText, didFormat: false, outcome: .skipped(.unavailable))
        }

        do {
            let formatted = try await generateFormattedTranscript(from: trimmed)
            let cleaned = formatted.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedWhitespace(cleaned) == normalizedWhitespace(trimmed),
               paragraphBreakCount(in: cleaned) == paragraphBreakCount(in: trimmed) {
                return Result(activeText: rawText, didFormat: false, outcome: .skipped(.unchanged))
            }

            if let validationFailure = validationFailure(raw: trimmed, formatted: cleaned) {
                textFormattingLog.debug("Rejected Apple transcript formatting: \(String(describing: validationFailure))")
                return Result(activeText: rawText, didFormat: false, outcome: .rejected(validationFailure))
            }

            return Result(activeText: cleaned, didFormat: true, outcome: .formatted)
        } catch TextFormattingError.appleIntelligenceUnavailable {
            return Result(activeText: rawText, didFormat: false, outcome: .skipped(.unavailable))
        } catch TextFormattingError.unsupportedLocale {
            return Result(activeText: rawText, didFormat: false, outcome: .skipped(.unsupportedLocale))
        } catch {
            textFormattingLog.debug("Apple transcript formatting failed: \(error.localizedDescription)")
            return Result(activeText: rawText, didFormat: false, outcome: .failed(error.localizedDescription))
        }
        #else
        return Result(activeText: rawText, didFormat: false, outcome: .skipped(.unavailable))
        #endif
    }

    private func skipReason(for text: String) -> SkipReason? {
        guard !text.isEmpty else {
            return .empty
        }

        guard text.count >= minimumCharacterCount else {
            return .tooShort
        }

        guard text.count <= maxCharacterCount else {
            return .tooLongForFirstSlice
        }

        let words = wordTokens(in: text)
        guard words.count >= minimumWordCount else {
            return .tooFewWords
        }

        if hasUsefulParagraphStructure(text) {
            return .alreadyStructured
        }

        let sentenceCount = sentenceTerminatorCount(in: text)
        if words.count < mediumTextWordCount,
           sentenceCount < minimumSentenceCountForMediumText {
            return .notEnoughStructureSignal
        }

        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func generateFormattedTranscript(from transcript: String) async throws -> String {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        switch model.availability {
        case .available:
            break
        case .unavailable:
            throw TextFormattingError.appleIntelligenceUnavailable
        @unknown default:
            throw TextFormattingError.appleIntelligenceUnavailable
        }

        guard model.supportsLocale() else {
            throw TextFormattingError.unsupportedLocale
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You format voice transcripts conservatively. Preserve the speaker's wording and order. Add structure only when it improves readability.
            """
        )

        let prompt = """
        Format this voice transcript into readable paragraphs.

        Rules:
        - Preserve the exact wording as much as possible.
        - Do not summarize.
        - Do not rewrite tone.
        - Do not remove fillers.
        - Do not add facts, headings, labels, or commentary.
        - Add bullets only if the speaker clearly dictated a list.
        - Return only the formatted transcript.

        TRANSCRIPT:
        \(transcript)
        """

        let response = try await session.respond(
            to: prompt,
            options: FoundationModels.GenerationOptions(temperature: 0.0)
        )
        return response.content
    }
    #endif

    private func validationFailure(raw: String, formatted: String) -> ValidationFailure? {
        guard !formatted.isEmpty else {
            return .empty
        }

        if startsWithPreamble(formatted) {
            return .preamble
        }

        let characterRatio = Double(formatted.count) / Double(max(raw.count, 1))
        guard characterRatio >= 0.75 && characterRatio <= 1.30 else {
            return .characterRatio
        }

        let rawTokens = wordTokens(in: raw)
        let formattedTokens = wordTokens(in: formatted)
        let tokenRatio = Double(formattedTokens.count) / Double(max(rawTokens.count, 1))
        guard tokenRatio >= 0.85 && tokenRatio <= 1.15 else {
            return .tokenRatio
        }

        let preservation = tokenPreservation(rawTokens: rawTokens, formattedTokens: formattedTokens)
        guard preservation >= 0.84 else {
            return .tokenPreservation
        }

        if paragraphBreakCount(in: raw) == 0,
           paragraphBreakCount(in: formatted) == 0 {
            return .noParagraphBreaks
        }

        return nil
    }

    private func hasUsefulParagraphStructure(_ text: String) -> Bool {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 2 else {
            return false
        }

        return paragraphs.map(\.count).max() ?? 0 <= maximumStructuredParagraphLength
    }

    private func paragraphBreakCount(in text: String) -> Int {
        max(text.components(separatedBy: "\n\n").count - 1, 0)
    }

    private func sentenceTerminatorCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character == "." || character == "?" || character == "!" {
                count += 1
            }
        }
    }

    private func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func startsWithPreamble(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = [
            "here is",
            "here's",
            "sure,",
            "certainly,",
            "formatted transcript",
            "the formatted transcript"
        ]
        return prefixes.contains { lowercased.hasPrefix($0) }
    }

    private func wordTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private func tokenPreservation(rawTokens: [String], formattedTokens: [String]) -> Double {
        guard !rawTokens.isEmpty else {
            return 1
        }

        var counts: [String: Int] = [:]
        for token in rawTokens {
            counts[token, default: 0] += 1
        }

        var preserved = 0
        for token in formattedTokens {
            guard let count = counts[token], count > 0 else {
                continue
            }
            preserved += 1
            counts[token] = count - 1
        }

        return Double(preserved) / Double(rawTokens.count)
    }
}

private enum TextFormattingError: LocalizedError {
    case appleIntelligenceUnavailable
    case unsupportedLocale

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence unavailable"
        case .unsupportedLocale:
            return "Locale unsupported"
        }
    }
}
