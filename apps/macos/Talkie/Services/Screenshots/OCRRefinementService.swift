//
//  OCRRefinementService.swift
//  Talkie
//
//  Runs a second-pass OCR cleanup using Apple Intelligence after Vision
//  extracts raw text from an image. Intended for difficult captures such as
//  handwriting where Vision gets the rough shape but misses key words.
//

import Foundation
import TalkieKit

private let refinementLog = Log(.system)

@MainActor
final class OCRRefinementService {
    static let shared = OCRRefinementService()

    struct Result: Sendable {
        let originalTexts: [String]
        let refinedText: String

        var didChange: Bool {
            !originalTexts.map(normalized).contains(normalized(refinedText))
        }

        private func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let provider = AppleLocalProvider()

    private init() {}

    func refineText(_ originalText: String) async throws -> Result {
        try await refineTexts([originalText])
    }

    func refineTexts(_ originalTexts: [String]) async throws -> Result {
        let trimmedCandidates = originalTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstCandidate = trimmedCandidates.first else {
            return Result(originalTexts: originalTexts, refinedText: originalTexts.first ?? "")
        }

        if trimmedCandidates.count == 1 {
            return try await refineSingleText(firstCandidate, originalTexts: originalTexts)
        }

        guard await provider.isAvailable else {
            refinementLog.debug("OCR refinement skipped: Apple Intelligence unavailable")
            return Result(originalTexts: originalTexts, refinedText: firstCandidate)
        }

        let prompt = """
        Reconcile multiple OCR outputs from the same handwritten note into one best-effort transcript.

        Rules:
        - Preserve the original structure, numbering, and bullets.
        - Prefer wording that appears consistently across candidates.
        - Correct obvious OCR mistakes when the intended text is reasonably inferable.
        - Keep names, products, and dates when reasonably inferable.
        - Do not invent new content.
        - If a fragment is too uncertain, keep the least-destructive wording rather than hallucinating.
        - Return only the cleaned transcript.

        CANDIDATE 1:
        \(trimmedCandidates[0])

        CANDIDATE 2:
        \(trimmedCandidates[1])

        \(trimmedCandidates.dropFirst(2).enumerated().map { index, candidate in
            "CANDIDATE \(index + 3):\n\(candidate)"
        }.joined(separator: "\n\n"))
        """

        let refined = try await provider.generate(
            prompt: prompt,
            model: "apple-on-device",
            options: GenerationOptions(
                temperature: 0.12,
                maxTokens: 700,
                systemPrompt: "You reconcile OCR transcripts conservatively and preserve formatting."
            )
        )

        let cleaned = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            originalTexts: originalTexts,
            refinedText: cleaned.isEmpty ? firstCandidate : cleaned
        )
    }

    private func refineSingleText(_ originalText: String, originalTexts: [String]) async throws -> Result {
        let trimmed = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(originalTexts: originalTexts, refinedText: originalText)
        }

        guard await provider.isAvailable else {
            refinementLog.debug("OCR refinement skipped: Apple Intelligence unavailable")
            return Result(originalTexts: originalTexts, refinedText: originalText)
        }

        let prompt = """
        Clean up OCR output from a handwritten note.

        Rules:
        - Correct likely OCR mistakes, spelling, and split words.
        - Preserve the original structure, numbering, and bullets.
        - Keep names, products, and dates when reasonably inferable.
        - Do not invent brand-new content.
        - If a fragment is too uncertain, keep it close to the source rather than hallucinating.
        - Return only the cleaned text.

        OCR INPUT:
        \(trimmed)
        """

        let refined = try await provider.generate(
            prompt: prompt,
            model: "apple-on-device",
            options: GenerationOptions(
                temperature: 0.15,
                maxTokens: 700,
                systemPrompt: "You repair OCR transcripts conservatively and preserve formatting."
            )
        )

        let cleaned = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            originalTexts: originalTexts,
            refinedText: cleaned.isEmpty ? originalText : cleaned
        )
    }
}
