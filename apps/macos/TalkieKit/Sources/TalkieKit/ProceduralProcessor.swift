import Foundation

/// Deterministic dictation → syntax processor.
///
/// Converts voiced protocol input (e.g., "git space push space dash u") into
/// bash commands ("git push -u") using purely procedural token scanning.
///
/// No LLM, no ML model. Every output is deterministic.
///
/// Composed from three rule sets (checked in priority order):
///   1. CodeSyntaxProcessor — "space", symbols, casing directives, quote tracking
///   2. PunctuationProcessor — "question mark", "comma", brackets, etc.
///   3. NumberProcessor — "forty two" → "42", digit sequences
///
/// Ported from `datasets/procedural-processor.py`.
public struct ProceduralProcessor {
    public static let shared = ProceduralProcessor()

    private let composed: ComposedTokenProcessor

    public init() {
        // Code syntax first (catches "space", "dot", "dash", casing, etc.)
        // Punctuation second (catches "question mark", "comma", brackets not in code set)
        // Numbers last (catches "forty two", digit sequences)
        self.composed = ComposedTokenProcessor(
            ruleSets: [
                CodeSyntaxProcessor(),
                PunctuationProcessor(),
                NumberProcessor(convertSingleDigits: true),
            ],
            preNormalize: true
        )
    }

    /// Process dictated text into syntax.
    ///
    /// - Parameter text: Dictated input using the protocol vocabulary
    /// - Returns: Reconstructed bash/syntax output
    public func process(_ text: String) -> String {
        composed.process(text)
    }
}
