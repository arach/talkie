//
//  ScreenshotInserter.swift
//  TalkieKit
//
//  Interleaves screenshots with timestamped transcript text.
//  Uses the original transcript text and splits at character positions
//  derived from word timestamps, preserving correct spacing.
//

import Foundation

// MARK: - Content Block

/// A block of content in the interleaved result
public enum ContentBlock: Sendable {
    case text(String)
    case screenshot(RecordingScreenshot)
}

// MARK: - Interleave Result

public struct InterleaveResult: Sendable {
    /// Ordered content blocks (text and screenshots interleaved by timestamp)
    public let blocks: [ContentBlock]

    /// Markdown representation with screenshot placeholders
    public let markdown: String
}

// MARK: - Screenshot Inserter

public enum ScreenshotInserter {

    /// Render transcript text for a delivery surface with screenshot
    /// references, without changing the canonical transcript text.
    public static func deliveryMarkdown(
        text: String,
        timedTranscription: TimedTranscription?,
        screenshots: [RecordingScreenshot],
        screenshotDirectory: URL? = nil,
        visualContexts: [RecordingVisualContext] = []
    ) -> String {
        guard !screenshots.isEmpty else {
            return appendVisualContextReferences(to: text, visualContexts: visualContexts)
        }

        if let timedTranscription,
           !timedTranscription.words.isEmpty,
           deliveryTextMatchesTimedTranscript(text, timedTranscription.text) {
            let markdown = interleave(
                timedTranscription: TimedTranscription(
                    text: text,
                    words: timedTranscription.words
                ),
                screenshots: screenshots,
                screenshotDirectory: screenshotDirectory
            ).markdown
            return appendVisualContextReferences(to: markdown, visualContexts: visualContexts)
        }

        let links = screenshots
            .sorted { $0.timestampMs < $1.timestampMs }
            .enumerated()
            .map { index, screenshot in
                "[Screenshot \(index + 1)](\(markdownDestination(screenshotRef(screenshot, directory: screenshotDirectory))))"
            }
            .joined(separator: "\n")

        let markdown = [text.trimmingCharacters(in: .whitespacesAndNewlines), links]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return appendVisualContextReferences(to: markdown, visualContexts: visualContexts)
    }

    /// Interleave screenshots into a timed transcription by timestamp.
    ///
    /// Uses the original transcript text (not reconstructed from word tokens)
    /// to preserve correct spacing. Maps word timestamps to character positions
    /// in the original text, then splits at those positions to insert screenshots.
    ///
    /// - Parameter screenshotDirectory: If provided, screenshot references use full paths.
    ///   Otherwise, just the filename.
    public static func interleave(
        timedTranscription: TimedTranscription,
        screenshots: [RecordingScreenshot],
        screenshotDirectory: URL? = nil
    ) -> InterleaveResult {
        guard !screenshots.isEmpty else {
            return InterleaveResult(
                blocks: [.text(timedTranscription.text)],
                markdown: timedTranscription.text
            )
        }

        let sortedScreenshots = screenshots.sorted { $0.timestampMs < $1.timestampMs }
        let words = timedTranscription.words
        let fullText = timedTranscription.text

        // Map each word to its character position in the original text.
        // Word tokens may be sub-word (e.g. "H", "ello" for "Hello"),
        // so we scan forward through the text matching each token.
        let wordCharStarts = mapWordsToCharPositions(words: words, in: fullText)

        // For each screenshot, find the character position where it goes.
        // A screenshot at time T is inserted before the first word starting after T.
        var insertions: [(charPos: Int, screenshot: RecordingScreenshot)] = []
        var wordIdx = 0

        for ss in sortedScreenshots {
            while wordIdx < words.count, Int(words[wordIdx].start * 1000) <= ss.timestampMs {
                wordIdx += 1
            }
            let charPos: Int
            if wordIdx < wordCharStarts.count {
                charPos = wordCharStarts[wordIdx]
            } else {
                charPos = fullText.count
            }
            insertions.append((charPos, ss))
        }

        // Split original text at insertion points. `[N]` markers go inline
        // at the screenshot's word position; the URL footnotes stack at the
        // end of the transcript.
        var blocks: [ContentBlock] = []
        var markdownParts: [String] = []
        var references: [String] = []
        var lastPos = 0
        var refNum = 0

        for (charPos, ss) in insertions {
            refNum += 1
            let clampedPos = min(charPos, fullText.count)
            if clampedPos > lastPos {
                let start = fullText.index(fullText.startIndex, offsetBy: lastPos)
                let end = fullText.index(fullText.startIndex, offsetBy: clampedPos)
                let segment = String(fullText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    blocks.append(.text(segment))
                    markdownParts.append(segment)
                }
            }

            blocks.append(.screenshot(ss))
            markdownParts.append("[\(refNum)]")

            let ref = screenshotRef(ss, directory: screenshotDirectory)
            references.append("[\(refNum)](\(markdownDestination(ref)))")

            lastPos = clampedPos
        }

        // Remaining text after last screenshot
        if lastPos < fullText.count {
            let start = fullText.index(fullText.startIndex, offsetBy: lastPos)
            let remaining = String(fullText[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                blocks.append(.text(remaining))
                markdownParts.append(remaining)
            }
        }

        let body = markdownParts.joined(separator: " ")
        let markdown = [body, references.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return InterleaveResult(
            blocks: blocks,
            markdown: markdown
        )
    }

    // MARK: - Private

    /// Map word tokens to character positions in the original text.
    ///
    /// ASR engines output sub-word tokens (e.g. "H", "ello" for "Hello").
    /// Post-processing may remove filler words ("um", "uh") from the text
    /// while the word tokens still contain them. Matching sub-word fragments
    /// of removed fillers against the text causes cascading misalignment
    /// (e.g. "h" from "Uh" matches "h" in "had", corrupting all subsequent
    /// positions).
    ///
    /// Fix: coalesce sub-word tokens into full words first, match full words
    /// against the text, then expand positions back to individual tokens.
    /// Full words are far less likely to produce false matches, and removed
    /// fillers fail cleanly as whole units.
    private static func mapWordsToCharPositions(words: [WordSegment], in text: String) -> [Int] {
        guard !words.isEmpty else { return [] }

        // Step 1: Coalesce sub-word tokens into full words.
        // A token starting with a space begins a new word; otherwise it continues the previous one.
        struct CoalescedWord {
            var text: String           // full word (trimmed)
            var tokenRange: Range<Int> // indices into `words`
        }
        var coalesced: [CoalescedWord] = []

        for (i, seg) in words.enumerated() {
            let raw = seg.word
            let startsNewWord = raw.hasPrefix(" ") || raw.hasPrefix("\n") || coalesced.isEmpty
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if startsNewWord || coalesced.isEmpty {
                coalesced.append(CoalescedWord(text: trimmed, tokenRange: i..<(i + 1)))
            } else {
                coalesced[coalesced.count - 1].text += trimmed
                coalesced[coalesced.count - 1].tokenRange = coalesced[coalesced.count - 1].tokenRange.lowerBound..<(i + 1)
            }
        }

        // Step 2: Map each coalesced word to its character position in the text.
        // Use word-boundary matching to avoid false substring hits
        // (e.g. "um" inside "column" would corrupt all subsequent positions).
        var wordPositions: [Int] = []
        wordPositions.reserveCapacity(coalesced.count)
        var searchFrom = text.startIndex

        for cw in coalesced {
            guard !cw.text.isEmpty else {
                wordPositions.append(text.distance(from: text.startIndex, to: searchFrom))
                continue
            }

            // Find the word with word-boundary awareness: keep searching past
            // substring-only matches until we find one at a word boundary.
            var candidate = searchFrom
            var found = false
            while candidate < text.endIndex {
                guard let range = text.range(of: cw.text, options: .caseInsensitive, range: candidate..<text.endIndex) else {
                    break
                }

                // Check word boundaries: character before match should not be a letter,
                // and character after match should not be a letter.
                let beforeOK = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
                let afterOK = range.upperBound == text.endIndex || !text[range.upperBound].isLetter

                if beforeOK && afterOK {
                    wordPositions.append(text.distance(from: text.startIndex, to: range.lowerBound))
                    searchFrom = range.upperBound
                    found = true
                    break
                }

                // Not at a word boundary — skip past this match and try again
                candidate = range.upperBound
            }

            if !found {
                // Word not found (likely a removed filler) — keep position stable
                wordPositions.append(text.distance(from: text.startIndex, to: searchFrom))
            }
        }

        // Step 3: Expand coalesced positions back to individual token positions.
        // All sub-word tokens of the same word get the same character position
        // (the position of the full word).
        var positions = [Int](repeating: 0, count: words.count)
        for (cwIdx, cw) in coalesced.enumerated() {
            let pos = wordPositions[cwIdx]
            for tokenIdx in cw.tokenRange {
                positions[tokenIdx] = pos
            }
        }

        return positions
    }

    private static func screenshotRef(_ ss: RecordingScreenshot, directory: URL?) -> String {
        if let dir = directory {
            return dir.appendingPathComponent(ss.filename).path
        }
        return ss.filename
    }

    private static func appendVisualContextReferences(
        to text: String,
        visualContexts: [RecordingVisualContext]
    ) -> String {
        guard !visualContexts.isEmpty else { return text }

        let references = visualContexts
            .sorted { $0.timestampMs < $1.timestampMs }
            .enumerated()
            .map { index, context in
                visualContextReference(context, index: index, total: visualContexts.count)
            }
            .joined(separator: "\n")

        return [
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            "Visual context captured:\n\(references)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func visualContextReference(
        _ context: RecordingVisualContext,
        index: Int,
        total: Int
    ) -> String {
        let bundleURL = VisualContextStorage.bundleURL(for: context)
        let label = total > 1 ? "Visual context \(index + 1)" : "Visual context"
        var lines = ["- \(label): [bundle](\(markdownDestination(bundleURL.path)))"]

        if let summaryFilename = context.summaryFilename {
            let summaryPath = bundleURL.appendingPathComponent(summaryFilename).path
            lines.append("  Summary: [\(summaryFilename)](\(markdownDestination(summaryPath)))")
        }

        let sourcePath = bundleURL.appendingPathComponent(context.sourceClipFilename).path
        lines.append("  Source clip: [\(context.sourceClipFilename)](\(markdownDestination(sourcePath)))")

        if let contactSheetFilename = context.contactSheetFilename {
            let contactSheetPath = bundleURL.appendingPathComponent(contactSheetFilename).path
            lines.append("  Contact sheet: [\(contactSheetFilename)](\(markdownDestination(contactSheetPath)))")
        }

        if context.frameCount != nil {
            let framesPath = bundleURL.appendingPathComponent("frames", isDirectory: true).path
            lines.append("  Frames: [frames](\(markdownDestination(framesPath)))")
        }

        return lines.joined(separator: "\n")
    }

    private static func deliveryTextMatchesTimedTranscript(_ deliveryText: String, _ timedText: String) -> Bool {
        deliveryText.trimmingCharacters(in: .whitespacesAndNewlines) == timedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownDestination(_ value: String) -> String {
        let needsAngleBrackets = value.contains { char in
            char.isWhitespace || char == "(" || char == ")"
        }
        guard needsAngleBrackets else { return value }
        return "<\(value.replacing(">", with: "%3E"))>"
    }

    private static func formatTimestamp(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds).\(String(format: "%01d", (ms % 1000) / 100))s"
    }
}
