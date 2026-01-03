//
//  DictionaryTestPlayground.swift
//  Talkie
//
//  Test playground for dictionary rules - input text, see processed output
//

import SwiftUI
import TalkieKit

struct DictionaryTestPlayground: View {
    @ObservedObject private var manager = DictionaryManager.shared

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var replacements: [DictionaryProcessingResult.ReplacementInfo] = []
    @State private var isProcessing: Bool = false

    // Recent memos for loading sample text
    @State private var recentMemos: [MemoModel] = []
    @State private var selectedMemoId: UUID?
    @State private var isLoadingMemos: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            header

            // Input section
            inputSection

            // Run button
            runButton

            // Output section
            outputSection

            // Replacements summary
            if !replacements.isEmpty {
                replacementsSummary
            }

            Spacer()
        }
        .padding(Spacing.lg)
        .task {
            await loadRecentMemos()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("TEST PLAYGROUND")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Test your dictionary rules against sample text")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Input")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                // Load from recent memo
                if !recentMemos.isEmpty {
                    Picker("Load from memo", selection: $selectedMemoId) {
                        Text("Load from memo...").tag(nil as UUID?)
                        ForEach(recentMemos) { memo in
                            Text(memo.title ?? memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .tag(memo.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .onChange(of: selectedMemoId) { _, newValue in
                        if let memoId = newValue,
                           let memo = recentMemos.first(where: { $0.id == memoId }),
                           let transcription = memo.transcription {
                            inputText = transcription
                            selectedMemoId = nil
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

    // MARK: - Actions

    private func loadRecentMemos() async {
        isLoadingMemos = true
        defer { isLoadingMemos = false }

        do {
            let repository = LocalRepository()
            let memos = try await repository.fetchTranscribedMemos(limit: 20)
            await MainActor.run {
                recentMemos = memos
            }
        } catch {
            // Silently fail - user can still type manually
        }
    }

    private func processText() {
        guard !inputText.isEmpty else { return }

        isProcessing = true
        let result = processWithLocalRules(inputText)
        outputText = result.processed
        replacements = result.replacements
        isProcessing = false
    }

    /// Process text locally using DictionaryManager's entries
    /// Mirrors TextPostProcessor logic for testing
    private func processWithLocalRules(_ text: String) -> DictionaryProcessingResult {
        let entries = manager.allEnabledEntries

        guard !entries.isEmpty else {
            return DictionaryProcessingResult(original: text, processed: text, replacements: [])
        }

        var result = text
        var replacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        // Process word/phrase types
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

        // Process regex types
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

        // Process fuzzy types
        let fuzzyEntries = entries.filter { $0.matchType == .fuzzy }
        if !fuzzyEntries.isEmpty {
            let (newResult, fuzzyInfos) = applyFuzzyMatching(to: result, entries: fuzzyEntries)
            result = newResult
            replacementInfos.append(contentsOf: fuzzyInfos)
        }

        return DictionaryProcessingResult(original: text, processed: result, replacements: replacementInfos)
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
