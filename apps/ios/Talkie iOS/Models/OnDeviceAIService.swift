//
//  OnDeviceAIService.swift
//  Talkie
//
//  On-device AI processing using Apple Foundation Models (iOS 26+)
//  Falls back gracefully when not available
//

import Foundation
import CoreData
import SwiftUI
import TalkieMobileKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for on-device AI processing using Apple Intelligence
@MainActor
class OnDeviceAIService: ObservableObject {

    static let shared = OnDeviceAIService()

    @Published var isProcessing = false
    @Published var isAvailable = false

    private init() {
        Task {
            await checkAvailability()
        }
    }

    /// Check if on-device AI is available
    func checkAvailability() async {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            isAvailable = true
            AppLogger.ai.info("On-device AI: Available")
        case .unavailable(let reason):
            isAvailable = false
            AppLogger.ai.info("On-device AI unavailable: \(reason)")
        @unknown default:
            isAvailable = false
            AppLogger.ai.info("On-device AI: Unknown availability status")
        }
        #else
        isAvailable = false
        AppLogger.ai.info("On-device AI: FoundationModels not available on this platform")
        #endif
    }

    // MARK: - Smart Title Generation

    /// Generate a smart title for a voice memo based on its transcript
    func generateSmartTitle(for transcript: String) async throws -> String {
        guard FeatureFlags.aiMemoTitlesEnabled else { throw OnDeviceAIError.notAvailable }
        return try await generateTitle(
            from: transcript,
            systemPrompt: Self.memoTitleSystemPrompt,
            maxInputLength: 2000
        )
    }

    /// Generate a smart title for a capture based on its content and source type.
    /// Content-aware: detects social media posts, articles, emails, code, etc.
    func generateCaptureTitle(text: String, sourceType: String, sourceURL: String? = nil) async throws -> String {
        guard FeatureFlags.aiCaptureTitlesEnabled else { throw OnDeviceAIError.notAvailable }
        var input = text
        if let url = sourceURL {
            input = "Source URL: \(url)\n\n\(text)"
        }

        return try await generateTitle(
            from: input,
            systemPrompt: Self.captureTitleSystemPrompt,
            maxInputLength: 1500
        )
    }

    /// Core title generation using Apple Intelligence
    private func generateTitle(from text: String, systemPrompt: String, maxInputLength: Int) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        let trimmed = String(text.prefix(maxInputLength))
        guard !trimmed.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession(instructions: systemPrompt)
        let options = FoundationModels.GenerationOptions(temperature: 0.3)

        let response = try await session.respond(to: trimmed, options: options)
        let title = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // Sanity check — reject if too long or suspiciously explanatory
        guard !title.isEmpty, title.count < 80 else {
            throw OnDeviceAIError.generationFailed("Title too long or empty")
        }

        AppLogger.ai.info("Generated smart title: \(title)")
        return title
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    // MARK: - Title Prompts

    /// System prompt for voice memo titles
    static let memoTitleSystemPrompt = """
    Generate a short, descriptive title (3-6 words) for a voice memo transcript. \
    Capture the main topic or purpose. Return ONLY the title, nothing else.
    """

    /// System prompt for capture/screenshot titles — content-type aware
    static let captureTitleSystemPrompt = """
    You generate concise titles for captured content (screenshots, shared text, URLs). \
    Analyze the text to detect what kind of content it is, then title it appropriately.

    Format rules by content type:
    - Social media post (X/Twitter): "Post by @{handle}" or "{Name} on X: {topic}" — look for @handles, "Repost", "Like", timestamps like "7:01 PM"
    - Social media (Instagram): "{Name} on Instagram: {topic}"
    - Social media (LinkedIn, Threads, etc.): "{Name} on {Platform}: {topic}"
    - Web article or blog: Use the article's own headline/title if visible
    - Email: "Email from {sender}: {subject}"
    - Chat/message: "Message from {name}: {topic}"
    - Code snippet: "Code: {brief description}"
    - Product/app UI: "{App/Product}: {what's shown}"
    - General text: 3-6 word descriptive title

    Detection hints:
    - @username + timestamps + "Reply"/"Repost"/"Like" → X/Twitter
    - "Liked by" + username → Instagram
    - "From:" + "Subject:" + "To:" → Email
    - import/function/class/def/const → Code
    - URL in "Source URL:" line helps identify the platform

    Return ONLY the title. No quotes, no explanation, no prefixes like "Title:".
    """

    // MARK: - Memo Formatting

    /// Structure-preserving formatting of a voice memo transcript.
    /// Fixes casing, punctuation, filler, and paragraph breaks without
    /// summarizing or rewording the memo.
    func formatMemo(_ text: String, instruction: String = "Format this memo") async throws -> String {
        guard FeatureFlags.aiMemoFormattingEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        if !isAvailable {
            await checkAvailability()
        }

        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = Self.formatChunks(from: text)
        guard !chunks.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        isProcessing = true
        defer { isProcessing = false }

        var formattedChunks: [String] = []
        formattedChunks.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession(instructions: Self.memoFormatSystemPrompt)
            let response = try await session.respond(
                to: Self.memoFormatUserPrompt(
                    chunk: chunk,
                    instruction: trimmedInstruction.isEmpty ? "Format this memo" : trimmedInstruction,
                    chunkIndex: index,
                    chunkCount: chunks.count
                ),
                options: FoundationModels.GenerationOptions(temperature: 0.2)
            )
            let formatted = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !formatted.isEmpty else {
                throw OnDeviceAIError.generationFailed("Formatter returned an empty chunk")
            }
            formattedChunks.append(formatted)
        }

        let result = formattedChunks.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw OnDeviceAIError.generationFailed("Formatter returned no text")
        }

        return result
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    private static let memoFormatSystemPrompt = """
    You clean up raw voice-transcribed memo text. Your only job is formatting:
    - Fix capitalization, punctuation, spacing, and obvious transcript artifacts.
    - Remove filler words such as um, uh, like, you know, I mean, kind of, sort of, and basically only where they add nothing.
    - Insert paragraph breaks between distinct topics.
    Do not summarize, reword, reorder, translate, or add content.
    Preserve the speaker's wording, meaning, and sequence.
    Return only the cleaned memo text. No preamble, notes, bullets, or markdown unless the source already uses them.
    """

    private static func memoFormatUserPrompt(
        chunk: String,
        instruction: String,
        chunkIndex: Int,
        chunkCount: Int
    ) -> String {
        [
            "User instruction:",
            instruction,
            "",
            "Memo chunk \(chunkIndex + 1) of \(chunkCount):",
            chunk,
            "",
            "Return only this chunk after formatting.",
        ].joined(separator: "\n")
    }

    private static func formatChunks(from text: String, maxCharacters: Int = 1500) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            let chunk = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            current = ""
        }

        for paragraph in paragraphs {
            if paragraph.count > maxCharacters {
                flushCurrent()
                chunks.append(contentsOf: splitLongParagraph(paragraph, maxCharacters: maxCharacters))
                continue
            }

            let candidate = current.isEmpty ? paragraph : "\(current)\n\n\(paragraph)"
            if candidate.count > maxCharacters {
                flushCurrent()
                current = paragraph
            } else {
                current = candidate
            }
        }

        flushCurrent()
        return chunks
    }

    private static func splitLongParagraph(_ paragraph: String, maxCharacters: Int) -> [String] {
        let words = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = word
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    /// Generate a brief summary of a voice memo
    func generateSummary(for transcript: String) async throws -> String {
        guard FeatureFlags.aiMemoSummariesEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Summarize this voice memo in 2-3 sentences. Focus on the key points and action items.

        Transcript:
        \(transcript.prefix(4000))
        """

        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Answer a short Apple Watch voice request in speech-friendly prose.
    func answerWatchQuestion(_ question: String) async throws -> String {
        guard FeatureFlags.aiWatchAssistantEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        if !isAvailable {
            await checkAvailability()
        }

        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession(instructions: Self.watchAssistantSystemPrompt)
        let response = try await session.respond(
            to: String(trimmedQuestion.prefix(3000)),
            options: FoundationModels.GenerationOptions(temperature: 0.4)
        )
        let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else {
            throw OnDeviceAIError.generationFailed("Watch AI returned no answer")
        }

        return answer
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    private static let watchAssistantSystemPrompt = """
    You are Talkie's Apple Watch voice assistant. Answer the user's spoken request directly, \
    briefly, and naturally. Prefer one or two short paragraphs. If the request is ambiguous, \
    give the most useful answer and ask one concise follow-up question only when necessary.
    """

    /// Generate concise sidecar output for a bookmarked moment in a recording.
    func generateRecordingSidecarOutput(
        kind: RecordingSidecarKind,
        memoTitle: String,
        transcriptExcerpt: String,
        note: String,
        queuedAtOffset: TimeInterval
    ) async throws -> String {
        guard FeatureFlags.aiRecordingSidecarEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        let trimmedExcerpt = transcriptExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExcerpt.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession(instructions: sidecarSystemPrompt(for: kind))
        let response = try await session.respond(
            to: sidecarUserPrompt(
                kind: kind,
                memoTitle: memoTitle,
                transcriptExcerpt: trimmedExcerpt,
                note: note,
                queuedAtOffset: queuedAtOffset
            ),
            options: FoundationModels.GenerationOptions(temperature: 0.3)
        )

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Summarize Claude Code session messages into a brief description
    func summarizeSession(messages: [SessionMessage]) async throws -> String {
        guard FeatureFlags.aiSessionSummariesEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        // Take last few messages for context
        let recentMessages = messages.suffix(6)
        let conversationText = recentMessages.map { msg in
            let role = msg.role == "user" ? "User" : "Claude"
            return "\(role): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        guard !conversationText.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Summarize this Claude Code conversation in 4-8 words. Focus on the main task or topic. \
        Be specific and technical. Return ONLY the summary, no quotes.

        Examples of good summaries:
        - "Fixing auth token refresh bug"
        - "Adding dark mode toggle"
        - "Refactoring database queries"
        - "Debugging API timeout issue"

        Conversation:
        \(conversationText)
        """

        let response = try await session.respond(to: prompt)
        let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.ai.info("Generated session summary: \(summary)")
        return summary
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Extract action items/tasks from a voice memo
    func extractTasks(from transcript: String) async throws -> String {
        guard FeatureFlags.aiTaskExtractionEnabled else { throw OnDeviceAIError.notAvailable }
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Extract any action items or tasks mentioned in this voice memo. \
        List them as bullet points. If no tasks are found, say "No tasks identified."

        Transcript:
        \(transcript.prefix(4000))
        """

        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Apply smart title to a VoiceMemo
    func applySmartTitle(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        let title = try await generateSmartTitle(for: transcript)

        await MainActor.run {
            memo.title = title
            do {
                try context.save()
                VoiceMemoStore.publishChange(context: context)
                AppLogger.ai.info("Applied smart title to memo: \(title)")
            } catch {
                AppLogger.ai.error("Failed to save smart title: \(error.localizedDescription)")
            }
        }
    }

    /// Auto-title a voice memo if it doesn't already have a user-set title.
    /// Call this after transcription completes. Fails silently.
    func autoTitleMemoIfNeeded(_ memo: VoiceMemo, context: NSManagedObjectContext) async {
        // Skip if already titled
        guard memo.title == nil || memo.title?.isEmpty == true else { return }
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else { return }

        do {
            let title = try await generateSmartTitle(for: transcript)
            await MainActor.run {
                memo.title = title
                do {
                    try context.save()
                    VoiceMemoStore.publishChange(context: context)
                    AppLogger.ai.info("Auto-titled memo: \(title)")
                } catch {
                    AppLogger.ai.error("Failed to save auto-title: \(error.localizedDescription)")
                }
            }
        } catch {
            AppLogger.ai.debug("Auto-title skipped: \(error.localizedDescription)")
        }
    }

    /// Auto-title a capture using content-aware generation. Fails silently.
    func autoTitleCapture(_ capture: Capture) async {
        guard capture.title == nil || capture.title?.isEmpty == true else { return }
        guard !capture.text.isEmpty, capture.text != "Photo (no text detected)" else { return }

        do {
            let title = try await generateCaptureTitle(
                text: capture.text,
                sourceType: capture.sourceType,
                sourceURL: capture.sourceURL
            )
            CaptureStore.shared.updateTitle(title, for: capture.id)
            AppLogger.ai.info("Auto-titled capture: \(title)")
        } catch {
            AppLogger.ai.debug("Auto-title capture skipped: \(error.localizedDescription)")
        }
    }

    /// Generate and save summary for a VoiceMemo
    func applySummary(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        await MainActor.run {
            memo.isProcessingSummary = true
            try? context.save()
        }

        defer {
            Task { @MainActor in
                memo.isProcessingSummary = false
                try? context.save()
            }
        }

        let summary = try await generateSummary(for: transcript)

        await MainActor.run {
            memo.summary = summary
            try? context.save()
            AppLogger.ai.info("Applied summary to memo")
        }
    }

    /// Generate and save tasks for a VoiceMemo
    func applyTasks(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        await MainActor.run {
            memo.isProcessingTasks = true
            try? context.save()
        }

        defer {
            Task { @MainActor in
                memo.isProcessingTasks = false
                try? context.save()
            }
        }

        let tasks = try await extractTasks(from: transcript)

        await MainActor.run {
            memo.tasks = tasks
            try? context.save()
            AppLogger.ai.info("Applied tasks to memo")
        }
    }

    private func sidecarSystemPrompt(for kind: RecordingSidecarKind) -> String {
        switch kind {
        case .feedback:
            return """
            You are a quiet sidecar assistant for a live brainstorming session.
            Give grounded, constructive feedback on the user's most recent idea.
            Focus on blind spots, tradeoffs, stronger framing, and the most useful next moves.
            Do not invent outside facts.
            Keep the response concise and directly useful.
            """
        case .research:
            return """
            You are a quiet sidecar assistant for a live research workflow.
            Based only on the provided transcript excerpt, identify the best next research directions.
            Call out open questions, terms worth checking, and why each thread matters.
            If the excerpt is underspecified, say what is missing instead of inventing facts.
            Keep the response concise and directly useful.
            """
        }
    }

    private func sidecarUserPrompt(
        kind: RecordingSidecarKind,
        memoTitle: String,
        transcriptExcerpt: String,
        note: String,
        queuedAtOffset: TimeInterval
    ) -> String {
        let offsetMinutes = Int(queuedAtOffset) / 60
        let offsetSeconds = Int(queuedAtOffset) % 60
        let formattedOffset = "\(offsetMinutes):\(offsetSeconds.formatted(.number.precision(.integerLength(2))))"

        var lines = [
            "Task: \(kind == .feedback ? "Give concise feedback on the bookmarked moment." : "Identify the best next research directions for the bookmarked moment.")",
            "Memo title: \(memoTitle)",
            "Bookmark offset: \(formattedOffset)"
        ]

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            lines.append("User focus note: \(trimmedNote)")
        }

        lines.append("")
        lines.append("Transcript excerpt:")
        lines.append(transcriptExcerpt)
        lines.append("")
        lines.append("Return only the result as 3 to 5 short bullets.")
        return lines.joined(separator: "\n")
    }
}

enum OnDeviceAIError: LocalizedError {
    case notAvailable
    case noTranscript
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "On-device AI is not available. Enable Apple Intelligence in Settings."
        case .noTranscript:
            return "No transcript available. Please wait for transcription to complete."
        case .generationFailed(let reason):
            return "AI generation failed: \(reason)"
        }
    }
}
