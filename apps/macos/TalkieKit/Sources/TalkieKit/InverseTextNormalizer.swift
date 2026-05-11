import Foundation

/// Shared inverse text normalization for natural-language ASR output.
///
/// Converts spoken punctuation and spoken-form numbers into written form while
/// leaving standalone single digits spelled out to preserve natural prose.
public enum InverseTextNormalizer {
    private static let naturalLanguageProcessor = ComposedTokenProcessor(
        ruleSets: [PunctuationProcessor(), NumberProcessor(convertSingleDigits: false)],
        spacing: .natural
    )

    public static func normalize(_ text: String) -> String {
        naturalLanguageProcessor
            .process(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Updates the user-visible transcript text while preserving the original
    /// timing spans. This keeps timing-sensitive features working even when ITN
    /// collapses multiple spoken tokens into one written token.
    public static func normalize(_ timedTranscription: TimedTranscription) -> TimedTranscription {
        let normalizedText = normalize(timedTranscription.text)
        guard normalizedText != timedTranscription.text else { return timedTranscription }
        return TimedTranscription(text: normalizedText, words: timedTranscription.words)
    }
}
