//
//  DictionaryTestPlayground.swift
//  Talkie
//
//  Test playground for dictionary rules - input text, see processed output
//

import SwiftUI
import TalkieKit

struct DictionaryTestPlayground: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = DictionaryManager.shared

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var replacements: [DictionaryProcessingResult.ReplacementInfo] = []
    @State private var isProcessing: Bool = false

    // Performance metrics
    @State private var metrics: ProcessingMetrics?

    // Sample text sources
    @State private var recentMemos: [MemoModel] = []
    @State private var recentDictations: [LiveDictation] = []
    @State private var selectedMemoId: UUID?
    @State private var selectedDictationId: Int64?
    @State private var isLoadingSamples: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with close button
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Input section
                    inputSection

                    // Run button
                    runButton

                    // Performance metrics
                    if let metrics = metrics {
                        metricsSection(metrics)
                    }

                    // Output section
                    outputSection

                    // Replacements summary
                    if !replacements.isEmpty {
                        replacementsSummary
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(Theme.current.background)
        .task {
            await loadSampleSources()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Playground")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text("Test your dictionary rules against sample text")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Theme.current.divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Input")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                if !inputText.isEmpty {
                    Text("(\(inputText.count) chars, ~\(inputText.split(separator: " ").count) words)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                // Load from recent memos
                if !recentMemos.isEmpty {
                    Picker("Memos", selection: $selectedMemoId) {
                        Text("Load memo...").tag(nil as UUID?)
                        ForEach(recentMemos) { memo in
                            Text("📝 " + (memo.title ?? memo.createdAt.formatted(date: .abbreviated, time: .shortened)))
                                .tag(memo.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 150)
                    .onChange(of: selectedMemoId) { _, newValue in
                        if let memoId = newValue,
                           let memo = recentMemos.first(where: { $0.id == memoId }),
                           let transcription = memo.transcription {
                            inputText = transcription
                            selectedMemoId = nil
                            metrics = nil
                        }
                    }
                }

                // Load from recent dictations
                if !recentDictations.isEmpty {
                    Picker("Dictations", selection: $selectedDictationId) {
                        Text("Load dictation...").tag(nil as Int64?)
                        ForEach(recentDictations, id: \.id) { dictation in
                            Text("🎙️ " + dictation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .tag(dictation.id as Int64?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 150)
                    .onChange(of: selectedDictationId) { _, newValue in
                        if let dictationId = newValue,
                           let dictation = recentDictations.first(where: { $0.id == dictationId }) {
                            inputText = dictation.text
                            selectedDictationId = nil
                            metrics = nil
                        }
                    }
                }
            }

            TextEditor(text: $inputText)
                .font(Theme.current.fontSM.monospaced())
                .frame(minHeight: 120, maxHeight: 200)
                .padding(Spacing.sm)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Theme.current.border, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Run Button

    private var runButton: some View {
        HStack {
            Spacer()

            Button(action: processText) {
                HStack(spacing: Spacing.xs) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text("Run")
                        .font(Theme.current.fontSMMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Theme.current.accent)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isProcessing)

            Spacer()
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Output")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            ScrollView {
                Text(outputText.isEmpty ? "Processed text will appear here..." : outputText)
                    .font(Theme.current.fontSM.monospaced())
                    .foregroundColor(outputText.isEmpty ? Theme.current.foregroundMuted : Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .padding(Spacing.sm)
            .background(Theme.current.backgroundTertiary)
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Replacements Summary

    private var replacementsSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Replacements Applied")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(replacements, id: \.trigger) { info in
                    HStack(spacing: Spacing.sm) {
                        Text(info.trigger)
                            .font(Theme.current.fontXS.monospaced())
                            .foregroundColor(Theme.current.foregroundMuted)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)

                        Text(info.replacement)
                            .font(Theme.current.fontXS.monospaced())
                            .foregroundColor(Theme.current.accent)

                        Spacer()

                        Text("×\(info.count)")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.sm)
        }
    }

    // MARK: - Performance Metrics

    private struct ProcessingMetrics {
        let totalMs: Double
        let trieMs: Double
        let regexMs: Double
        let fuzzyMs: Double
        let inputChars: Int
        let inputWords: Int
        let entryCount: Int
        let replacementCount: Int

        var throughputCharsPerSec: Double {
            guard totalMs > 0 else { return 0 }
            return Double(inputChars) / (totalMs / 1000.0)
        }
    }

    private func metricsSection(_ metrics: ProcessingMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Performance")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            HStack(spacing: Spacing.lg) {
                // Total time
                metricPill(
                    label: "Total",
                    value: String(format: "%.2fms", metrics.totalMs),
                    color: metrics.totalMs < 5 ? .green : (metrics.totalMs < 20 ? .orange : .red)
                )

                // Breakdown
                metricPill(label: "Trie", value: String(format: "%.2fms", metrics.trieMs), color: .blue)
                metricPill(label: "Regex", value: String(format: "%.2fms", metrics.regexMs), color: .purple)
                metricPill(label: "Fuzzy", value: String(format: "%.2fms", metrics.fuzzyMs), color: .cyan)

                Spacer()

                // Throughput
                Text(String(format: "%.0f chars/sec", metrics.throughputCharsPerSec))
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Summary
            Text("\(metrics.inputWords) words • \(metrics.entryCount) dictionary entries • \(metrics.replacementCount) replacements")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Actions

    private func loadSampleSources() async {
        isLoadingSamples = true
        defer { isLoadingSamples = false }

        // Load memos
        do {
            let repository = LocalRepository()
            let memos = try await repository.fetchTranscribedMemos(limit: 20)
            await MainActor.run {
                recentMemos = memos
            }
        } catch {
            // Silently fail
        }

        // Load live dictations
        await MainActor.run {
            recentDictations = LiveDatabase.recent(limit: 20).filter { !$0.text.isEmpty }
        }
    }

    private func processText() {
        guard !inputText.isEmpty else { return }

        isProcessing = true
        let (result, timing) = processWithLocalRulesAndTiming(inputText)
        outputText = result.processed
        replacements = result.replacements
        metrics = timing
        isProcessing = false
    }

    /// Process text with timing metrics
    private func processWithLocalRulesAndTiming(_ text: String) -> (DictionaryProcessingResult, ProcessingMetrics) {
        let entries = manager.allEnabledEntries
        let wordCount = text.split(separator: " ").count

        guard !entries.isEmpty else {
            let emptyMetrics = ProcessingMetrics(
                totalMs: 0, trieMs: 0, regexMs: 0, fuzzyMs: 0,
                inputChars: text.count, inputWords: wordCount,
                entryCount: 0, replacementCount: 0
            )
            return (DictionaryProcessingResult(original: text, processed: text, replacements: []), emptyMetrics)
        }

        let totalStart = CFAbsoluteTimeGetCurrent()
        var result = text
        var replacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        // Step 1: Trie (word/phrase) matching
        let trieStart = CFAbsoluteTimeGetCurrent()
        let trieEntries = entries.filter { $0.matchType == .word || $0.matchType == .phrase }
        for entry in trieEntries {
            let (newResult, count) = applyTrieReplacement(entry, to: result)
            if count > 0 {
                result = newResult
                replacementInfos.append(DictionaryProcessingResult.ReplacementInfo(
                    trigger: entry.trigger,
                    replacement: entry.replacement,
                    count: count
                ))
            }
        }
        let trieMs = (CFAbsoluteTimeGetCurrent() - trieStart) * 1000

        // Step 2: Regex matching
        let regexStart = CFAbsoluteTimeGetCurrent()
        let regexEntries = entries.filter { $0.matchType == .regex }
        for entry in regexEntries {
            let (newResult, count) = applyRegexReplacement(entry, to: result)
            if count > 0 {
                result = newResult
                replacementInfos.append(DictionaryProcessingResult.ReplacementInfo(
                    trigger: entry.trigger,
                    replacement: entry.replacement,
                    count: count
                ))
            }
        }
        let regexMs = (CFAbsoluteTimeGetCurrent() - regexStart) * 1000

        // Step 3: Fuzzy matching
        let fuzzyStart = CFAbsoluteTimeGetCurrent()
        let fuzzyEntries = entries.filter { $0.matchType == .fuzzy }
        if !fuzzyEntries.isEmpty {
            let (newResult, fuzzyInfos) = applyFuzzyMatching(to: result, entries: fuzzyEntries)
            result = newResult
            replacementInfos.append(contentsOf: fuzzyInfos)
        }
        let fuzzyMs = (CFAbsoluteTimeGetCurrent() - fuzzyStart) * 1000

        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        let totalReplacements = replacementInfos.reduce(0) { $0 + $1.count }

        let metrics = ProcessingMetrics(
            totalMs: totalMs,
            trieMs: trieMs,
            regexMs: regexMs,
            fuzzyMs: fuzzyMs,
            inputChars: text.count,
            inputWords: wordCount,
            entryCount: entries.count,
            replacementCount: totalReplacements
        )

        return (DictionaryProcessingResult(original: text, processed: result, replacements: replacementInfos), metrics)
    }

    private func applyTrieReplacement(_ entry: DictionaryEntry, to text: String) -> (String, Int) {
        var result = text
        var count = 0

        switch entry.matchType {
        case .word:
            // Word boundary match
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, options: [], range: range)
                count = matches.count

                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: entry.replacement
                )
            }

        case .phrase:
            // Case-insensitive literal match
            var searchRange = result.startIndex..<result.endIndex

            while let range = result.range(of: entry.trigger, options: .caseInsensitive, range: searchRange) {
                result.replaceSubrange(range, with: entry.replacement)
                count += 1

                let newStart = result.index(range.lowerBound, offsetBy: entry.replacement.count, limitedBy: result.endIndex) ?? result.endIndex
                searchRange = newStart..<result.endIndex
            }

        case .regex, .fuzzy:
            // Handled separately
            break
        }

        return (result, count)
    }

    private func applyRegexReplacement(_ entry: DictionaryEntry, to text: String) -> (String, Int) {
        guard entry.matchType == .regex else { return (text, 0) }

        do {
            let regex = try NSRegularExpression(pattern: entry.trigger, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            guard !matches.isEmpty else { return (text, 0) }

            var result = text

            // Apply from end to start to preserve indices
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }

                // Build replacement with capture groups
                var replacement = entry.replacement
                for i in 1..<match.numberOfRanges {
                    let groupRange = match.range(at: i)
                    if groupRange.location != NSNotFound,
                       let range = Range(groupRange, in: result) {
                        let captured = String(result[range])
                        replacement = replacement.replacingOccurrences(of: "$\(i)", with: captured)
                    }
                }

                result.replaceSubrange(matchRange, with: replacement)
            }

            return (result, matches.count)
        } catch {
            return (text, 0)
        }
    }

    // MARK: - Fuzzy Matching (mirrors TextPostProcessor)

    private struct WordToken {
        let text: String
        let startOffset: Int
        let endOffset: Int
    }

    private func applyFuzzyMatching(
        to text: String,
        entries: [DictionaryEntry]
    ) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        let tokens = tokenize(text)
        guard !tokens.isEmpty, !entries.isEmpty else { return (text, []) }

        let knownTriggers = Set(entries.map { $0.trigger.lowercased() })
        var replacements: [(token: WordToken, entry: DictionaryEntry)] = []

        for token in tokens {
            // Skip short words (< 4 chars)
            guard token.text.count >= 4 else { continue }

            // Skip known triggers
            if knownTriggers.contains(token.text.lowercased()) { continue }

            // Find best fuzzy match
            var bestMatch: (entry: DictionaryEntry, score: Double)?
            var secondBestScore: Double = 0

            for entry in entries {
                let score = similarityScore(token.text, entry.trigger)
                if score >= 0.7 {  // Threshold
                    if bestMatch == nil || score > bestMatch!.score {
                        secondBestScore = bestMatch?.score ?? 0
                        bestMatch = (entry, score)
                    } else if score > secondBestScore {
                        secondBestScore = score
                    }
                }
            }

            // Apply if best match has sufficient margin
            if let best = bestMatch, best.score - secondBestScore >= 0.1 {
                replacements.append((token, best.entry))
            }
        }

        guard !replacements.isEmpty else { return (text, []) }

        // Apply replacements from end to start
        var result = text
        var counts: [UUID: (entry: DictionaryEntry, count: Int)] = [:]

        for (token, entry) in replacements.reversed() {
            let startIdx = result.index(result.startIndex, offsetBy: token.startOffset)
            let endIdx = result.index(result.startIndex, offsetBy: token.endOffset)
            result.replaceSubrange(startIdx..<endIdx, with: entry.replacement)

            if let existing = counts[entry.id] {
                counts[entry.id] = (existing.entry, existing.count + 1)
            } else {
                counts[entry.id] = (entry, 1)
            }
        }

        let infos = counts.values.map { entry, count in
            DictionaryProcessingResult.ReplacementInfo(
                trigger: entry.trigger,
                replacement: entry.replacement,
                count: count
            )
        }

        return (result, infos)
    }

    private func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var currentWord = ""
        var wordStart = 0

        for (offset, char) in text.enumerated() {
            if char.isLetter || char.isNumber {
                if currentWord.isEmpty { wordStart = offset }
                currentWord.append(char)
            } else {
                if !currentWord.isEmpty {
                    tokens.append(WordToken(text: currentWord, startOffset: wordStart, endOffset: offset))
                    currentWord = ""
                }
            }
        }

        if !currentWord.isEmpty {
            tokens.append(WordToken(text: currentWord, startOffset: wordStart, endOffset: text.count))
        }

        return tokens
    }

    private func similarityScore(_ s1: String, _ s2: String) -> Double {
        let distance = damerauLevenshtein(s1, s2)
        let maxLen = max(s1.count, s2.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func damerauLevenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.lowercased())
        let b = Array(s2.lowercased())
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var d = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { d[i][0] = i }
        for j in 0...n { d[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)

                if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
                    d[i][j] = min(d[i][j], d[i-2][j-2] + 1)
                }
            }
        }

        return d[m][n]
    }
}

// MARK: - Preview

#Preview("Dictionary Test Playground") {
    DictionaryTestPlayground()
        .frame(width: 500, height: 600)
}
