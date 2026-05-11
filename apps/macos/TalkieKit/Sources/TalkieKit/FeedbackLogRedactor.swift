//
//  FeedbackLogRedactor.swift
//  TalkieKit
//
//  Redacts user-authored content before logs are attached to feedback reports.
//

import Foundation

enum FeedbackLogRedactor {
    static func redact(_ text: String) -> String {
        var redacted = text
        redacted = redactUserPaths(in: redacted)
        redacted = redactQueryValues(in: redacted)
        redacted = redactJSONValues(in: redacted)
        redacted = redactLabeledValues(in: redacted)
        redacted = redactTranscriptionSnippets(in: redacted)
        return redacted
    }

    private static func redactUserPaths(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"/Users/[^/\s|"']+"#,
            withTemplate: "/Users/***"
        )
    }

    private static func redactQueryValues(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"([?&](?:prompt|systemPrompt|userPrompt|llmPrompt|promptTemplate|transcript|transcription|text|content|message|query|q)=)([^&\s]+)"#,
            withTemplate: "$1[redacted]",
            options: [.caseInsensitive]
        )
    }

    private static func redactJSONValues(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(\"(?:prompt|systemPrompt|userPrompt|llmPrompt|promptTemplate|llmPromptTemplate|transcript|transcription|transcriptExcerpt|rawText|inputTranscript|insertedText|selectedText|capturedTranscription|userMessage|message|content|text|title|body)\"\s*:\s*\")((?:\\.|[^\"\\])*)(\")"#,
            withTemplate: "$1[redacted]$3",
            options: [.caseInsensitive]
        )
    }

    private static func redactLabeledValues(in text: String) -> String {
        let sensitiveLabels = #"(?:(?:system|user|llm)\s*)?prompt(?:\s*template)?|promptTemplate|llmPromptTemplate|transcript(?:ion)?|transcriptExcerpt|transcribed|rawText|inputTranscript|insertedText|selectedText|capturedTranscription|userMessage"#
        return replacingMatches(
            in: text,
            pattern: #"\b("# + sensitiveLabels + #")(\s*[:=]\s*)(.+?)(?=(?:[,&]\s*[A-Za-z][A-Za-z0-9_ ]{0,32}\s*[:=])|(?:\s*\(\d+[^)]*\)\s*$)|(?:\.\.\.\s*$)|$)"#,
            withTemplate: "$1$2[redacted]",
            options: [.caseInsensitive]
        )
    }

    private static func redactTranscriptionSnippets(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"\b((?:Apple Speech|Whisper|Parakeet|SpeechAnalyzer)?\s*transcription\s+(?:complete|completed|succeeded|success):\s*)(.+?)(?=(?:\.\.\.\s*$)|(?:,\s*[A-Za-z][A-Za-z0-9_ ]{0,32}\s*[:=])|$)"#,
            withTemplate: "$1[redacted]",
            options: [.caseInsensitive]
        )
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        withTemplate template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
