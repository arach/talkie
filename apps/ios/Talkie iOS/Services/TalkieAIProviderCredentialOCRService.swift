//
//  TalkieAIProviderCredentialOCRService.swift
//  Talkie iOS
//
//  Extracts provider API keys from local OCR text.
//

import Foundation

enum TalkieAIProviderCredentialOCRService {
    static let localTestAPIKey = ""

    static func payload(from recognizedText: String) throws -> TalkieAIProviderCredentialPayload {
        guard let candidate = candidates(in: recognizedText).first else {
            throw TalkieAIProviderCredentialOCRError.noKeyFound
        }

        return try payload(providerId: candidate.providerId, apiKey: candidate.apiKey)
    }

    static func payload(providerId: String, apiKey: String) throws -> TalkieAIProviderCredentialPayload {
        let providerId = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let apiKey = cleanedAPIKey(apiKey)

        guard isValidAPIKey(apiKey, providerId: providerId) else {
            throw TalkieAIProviderCredentialOCRError.invalidKey
        }

        return TalkieAIProviderCredentialPayload(
            providerId: providerId,
            providerName: TalkieAIProviderCredentialPayload.displayName(for: providerId),
            modelId: TalkieAIProviderCredentialPayload.defaultModel(for: providerId),
            apiKey: apiKey,
            assistantPrompt: TalkieAIProviderCredentialPayload.defaultAssistantPrompt
        )
    }

    static func localComparison(
        candidate: String,
        expected: String
    ) -> TalkieAIProviderCredentialLocalComparison {
        let candidate = cleanedAPIKey(candidate)
        let expected = cleanedAPIKey(expected)

        guard !candidate.isEmpty, !expected.isEmpty else {
            return TalkieAIProviderCredentialLocalComparison(
                isMatch: false,
                similarity: 0,
                editDistance: max(candidate.count, expected.count),
                candidateLength: candidate.count,
                expectedLength: expected.count
            )
        }

        let editDistance = levenshteinDistance(
            candidate,
            expected,
            maximum: max(candidate.count, expected.count)
        )
        let denominator = max(candidate.count, expected.count, 1)
        let similarity = max(0, 1 - (Double(editDistance) / Double(denominator)))

        return TalkieAIProviderCredentialLocalComparison(
            isMatch: candidate == expected,
            similarity: similarity,
            editDistance: editDistance,
            candidateLength: candidate.count,
            expectedLength: expected.count
        )
    }

    static func candidates(in text: String) -> [TalkieAIProviderCredentialOCRCandidate] {
        let searchSpaces = [text] + lineBreakCompactedKeyStrings(in: text)

        var candidates: [TalkieAIProviderCredentialOCRCandidate] = []
        var seen = Set<String>()

        for searchText in searchSpaces {
            for candidate in matches(in: searchText, providerId: "openai", pattern: #"sk-[A-Za-z0-9_-]{20,}"#) {
                guard seen.insert(candidate.apiKey).inserted else { continue }
                candidates.append(candidate)
            }

            for candidate in matches(in: searchText, providerId: "groq", pattern: #"gsk_[A-Za-z0-9_-]{20,}"#) {
                guard seen.insert(candidate.apiKey).inserted else { continue }
                candidates.append(candidate)
            }
        }

        return candidates.sorted { $0.apiKey.count > $1.apiKey.count }
    }

    static func bestDraft(in text: String) -> TalkieAIProviderCredentialOCRCandidate? {
        if let completeCandidate = candidates(in: text).first {
            return completeCandidate
        }

        let searchSpaces = [text] + lineBreakCompactedKeyStrings(in: text)
        let openAIDrafts = searchSpaces.flatMap {
            drafts(in: $0, providerId: "openai", pattern: #"sk-[A-Za-z0-9_-]{8,}"#)
        }

        if let openAI = openAIDrafts.max(by: { $0.apiKey.count < $1.apiKey.count }) {
            return openAI
        }

        return searchSpaces
            .flatMap { drafts(in: $0, providerId: "groq", pattern: #"gsk_[A-Za-z0-9_-]{8,}"#) }
            .max(by: { $0.apiKey.count < $1.apiKey.count })
    }

    static func keyFragments(in text: String) -> [String] {
        let searchSpaces = [text] + lineBreakCompactedKeyStrings(in: text)

        var fragments: [String] = []
        var seen = Set<String>()

        for searchText in searchSpaces {
            for fragment in rawKeyFragments(in: searchText) {
                guard seen.insert(fragment).inserted else { continue }
                fragments.append(fragment)
            }
        }

        return fragments
    }

    static func stitchedKeyText(from fragments: [String]) -> String {
        if let candidate = stitchCandidates(from: fragments).first {
            return candidate.apiKey
        }

        let fragments = fragments.reduce(into: [String]()) { partialResult, fragment in
            guard !partialResult.contains(where: { $0.contains(fragment) }) else { return }
            partialResult.removeAll { fragment.contains($0) }
            partialResult.append(fragment)
        }

        guard var stitched = fragments.first else {
            return ""
        }

        for fragment in fragments.dropFirst() {
            stitched = mergeKeyFragments(stitched, fragment)
        }

        return stitched
    }

    static func stitchCandidates(from fragments: [String]) -> [TalkieAIProviderCredentialStitchCandidate] {
        let fragments = normalizedKeyFragments(fragments)

        guard !fragments.isEmpty else {
            return []
        }

        var candidatesByKey: [String: TalkieAIProviderCredentialStitchCandidate] = [:]
        let starts = fragments.sorted { keyFragmentRank($0) > keyFragmentRank($1) }

        for start in starts.prefix(18) {
            let path = stitchPath(startingWith: start, fragments: fragments)
            addStitchCandidate(path, to: &candidatesByKey)
        }

        for fragment in fragments {
            addStitchCandidate(
                StitchPath(
                    text: fragment,
                    fragments: [fragment],
                    averageMergeConfidence: 0,
                    fuzzyMergeCount: 0,
                    exactMergeCount: 0
                ),
                to: &candidatesByKey
            )
        }

        return Array(candidatesByKey.values)
            .sorted(by: stitchCandidateSort)
            .prefix(4)
            .map { $0 }
    }

    static func searchText(currentText: String, capturedFragments: [String]) -> String {
        let stitchedTexts = stitchCandidates(from: capturedFragments).map(\.apiKey)
        return ([currentText] + capturedFragments + stitchedTexts)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func characterConfidences(
        for candidate: TalkieAIProviderCredentialStitchCandidate
    ) -> [TalkieAIProviderCredentialCharacterConfidence] {
        let characters = Array(candidate.apiKey)
        guard !characters.isEmpty else {
            return []
        }

        var weights = Array(repeating: 0.0, count: characters.count)

        for fragment in candidate.fragments {
            if let placement = exactPlacement(of: fragment, in: candidate.apiKey) ??
                fuzzyPlacement(of: fragment, in: candidate.apiKey) {
                let upperBound = min(placement.startIndex + placement.length, weights.count)
                guard placement.startIndex < upperBound else {
                    continue
                }

                for index in placement.startIndex..<upperBound {
                    weights[index] += placement.confidence
                }
            }
        }

        let maximumWeight = max(weights.max() ?? 0, 1)
        return characters.enumerated().map { index, character in
            let confidence = min(1, 0.18 + (weights[index] / maximumWeight) * 0.82)
            return TalkieAIProviderCredentialCharacterConfidence(
                index: index,
                character: character,
                confidence: confidence
            )
        }
    }

    private static func matches(
        in text: String,
        providerId: String,
        pattern: String
    ) -> [TalkieAIProviderCredentialOCRCandidate] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }

            let apiKey = cleanedAPIKey(String(text[matchRange]))

            guard isValidAPIKey(apiKey, providerId: providerId) else {
                return nil
            }

            return TalkieAIProviderCredentialOCRCandidate(providerId: providerId, apiKey: apiKey)
        }
    }

    private static func drafts(
        in text: String,
        providerId: String,
        pattern: String
    ) -> [TalkieAIProviderCredentialOCRCandidate] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }

            let apiKey = cleanedAPIKey(String(text[matchRange]))
            guard apiKey.count >= 8,
                  !apiKey.contains("*"),
                  !apiKey.contains("•") else {
                return nil
            }

            return TalkieAIProviderCredentialOCRCandidate(providerId: providerId, apiKey: apiKey)
        }
        .sorted { $0.apiKey.count > $1.apiKey.count }
    }

    private static func rawKeyFragments(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:sk-|gsk_)?[A-Za-z0-9_-]{6,}"#) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }

            let fragment = cleanedAPIKey(String(text[matchRange]))
            guard isLikelyKeyFragment(fragment) else {
                return nil
            }

            return fragment
        }
    }

    /// Rejoins OCR fragments only when a provider-prefixed token is followed
    /// by whole lines that still look like key material. Compacting every
    /// whitespace boundary also swallowed labels and adjacent keys, producing
    /// strings such as `sk-...middlesk-...end`.
    private static func lineBreakCompactedKeyStrings(in text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let patterns = [#"sk-[A-Za-z0-9_-]+"#, #"gsk_[A-Za-z0-9_-]+"#]
        var compacted: [String] = []
        var seen = Set<String>()

        for lineIndex in lines.indices {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let line = lines[lineIndex]
                let range = NSRange(line.startIndex..<line.endIndex, in: line)

                for match in regex.matches(in: line, range: range) {
                    guard let matchRange = Range(match.range, in: line) else { continue }
                    let firstFragment = cleanedAPIKey(String(line[matchRange]))
                    var candidate = firstFragment

                    for nextLine in lines.index(after: lineIndex)..<lines.endIndex {
                        let continuation = lines[nextLine]
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard isLikelyLineBreakContinuation(continuation) else { break }
                        candidate += continuation
                    }

                    guard candidate != firstFragment,
                          seen.insert(candidate).inserted else { continue }
                    compacted.append(candidate)
                }
            }
        }

        return compacted
    }

    private static func isLikelyLineBreakContinuation(_ fragment: String) -> Bool {
        guard (4...64).contains(fragment.count),
              fragment.allSatisfy({ character in
                  character.isLetter || character.isNumber || character == "_" || character == "-"
              }) else {
            return false
        }

        let letters = fragment.filter(\.isLetter)
        let hasDigitOrSeparator = fragment.contains { character in
            character.isNumber || character == "_" || character == "-"
        }
        let isUppercaseRun = !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        let hasMixedCase = letters.contains(where: \.isUppercase) && letters.contains(where: \.isLowercase)

        return hasDigitOrSeparator || isUppercaseRun || (hasMixedCase && fragment.count >= 10)
    }

    private static func isLikelyKeyFragment(_ fragment: String) -> Bool {
        if fragment.hasPrefix("sk-") || fragment.hasPrefix("gsk_") {
            return fragment.count >= 6
        }

        guard fragment.count >= 10 else {
            return false
        }

        guard fragment.allSatisfy({ character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }) else {
            return false
        }

        let hasDigitOrSeparator = fragment.contains { character in
            character.isNumber || character == "_" || character == "-"
        }
        let hasMixedCase = fragment.contains(where: \.isUppercase) && fragment.contains(where: \.isLowercase)

        if hasDigitOrSeparator {
            return fragment.count >= 10
        }

        if hasMixedCase {
            return fragment.count >= 16
        }

        return fragment.count >= 24
    }

    private static func normalizedKeyFragments(_ fragments: [String]) -> [String] {
        fragments.reduce(into: [String]()) { partialResult, rawFragment in
            let fragment = cleanedAPIKey(rawFragment)
            guard isLikelyKeyFragment(fragment) else {
                return
            }

            guard !partialResult.contains(where: { $0.contains(fragment) }) else {
                return
            }

            partialResult.removeAll { fragment.contains($0) }
            partialResult.append(fragment)
        }
    }

    private static func stitchPath(startingWith start: String, fragments: [String]) -> StitchPath {
        var stitched = start
        var usedFragments = [start]
        var remaining = fragments.filter { $0 != start }
        var confidenceTotal = 0.0
        var mergeCount = 0
        var fuzzyMergeCount = 0
        var exactMergeCount = 0

        while let merge = bestMerge(for: stitched, from: remaining) {
            stitched = merge.text
            usedFragments.append(merge.fragment)
            remaining.removeAll { $0 == merge.fragment }
            confidenceTotal += merge.confidence
            mergeCount += 1

            if merge.isFuzzy {
                fuzzyMergeCount += 1
            } else {
                exactMergeCount += 1
            }

            if usedFragments.count >= 16 {
                break
            }
        }

        return StitchPath(
            text: stitched,
            fragments: usedFragments,
            averageMergeConfidence: mergeCount == 0 ? 0 : confidenceTotal / Double(mergeCount),
            fuzzyMergeCount: fuzzyMergeCount,
            exactMergeCount: exactMergeCount
        )
    }

    private static func bestMerge(for stitched: String, from fragments: [String]) -> StitchMerge? {
        fragments
            .compactMap { stitchMerge(stitched, $0) }
            .sorted {
                if $0.overlapLength != $1.overlapLength {
                    return $0.overlapLength > $1.overlapLength
                }

                if abs($0.confidence - $1.confidence) > 0.01 {
                    return $0.confidence > $1.confidence
                }

                return $0.text.count > $1.text.count
            }
            .first
    }

    private static func mergeKeyFragments(_ base: String, _ fragment: String) -> String {
        stitchMerge(base, fragment)?.text ?? fallbackMergeKeyFragments(base, fragment)
    }

    private static func stitchMerge(_ base: String, _ fragment: String) -> StitchMerge? {
        guard !base.isEmpty else {
            return StitchMerge(
                text: fragment,
                fragment: fragment,
                confidence: 0,
                overlapLength: 0,
                isFuzzy: false
            )
        }

        guard !fragment.isEmpty else {
            return nil
        }

        if base.contains(fragment) {
            return StitchMerge(
                text: base,
                fragment: fragment,
                confidence: 1,
                overlapLength: fragment.count,
                isFuzzy: false
            )
        }

        if fragment.contains(base) {
            return StitchMerge(
                text: fragment,
                fragment: fragment,
                confidence: 1,
                overlapLength: base.count,
                isFuzzy: false
            )
        }

        let baseThenFragment = bestOverlap(suffixOf: base, prefixOf: fragment)
        let fragmentThenBase = bestOverlap(suffixOf: fragment, prefixOf: base)
        let shouldUseBaseThenFragment = shouldPrefer(baseThenFragment, over: fragmentThenBase)

        if shouldUseBaseThenFragment, let baseThenFragment {
            return StitchMerge(
                text: base + fragment.dropFirst(baseThenFragment.length),
                fragment: fragment,
                confidence: baseThenFragment.confidence,
                overlapLength: baseThenFragment.length,
                isFuzzy: baseThenFragment.editDistance > 0
            )
        }

        if let fragmentThenBase {
            return StitchMerge(
                text: fragment + base.dropFirst(fragmentThenBase.length),
                fragment: fragment,
                confidence: fragmentThenBase.confidence,
                overlapLength: fragmentThenBase.length,
                isFuzzy: fragmentThenBase.editDistance > 0
            )
        }

        if shouldAppendLowConfidenceContinuation(to: base, fragment: fragment) {
            return StitchMerge(
                text: base + fragment,
                fragment: fragment,
                confidence: 0.15,
                overlapLength: 0,
                isFuzzy: true
            )
        }

        if shouldAppendLowConfidenceContinuation(to: fragment, fragment: base) {
            return StitchMerge(
                text: fragment + base,
                fragment: fragment,
                confidence: 0.15,
                overlapLength: 0,
                isFuzzy: true
            )
        }

        return nil
    }

    private static func shouldPrefer(_ left: FragmentOverlap?, over right: FragmentOverlap?) -> Bool {
        guard let left else {
            return false
        }

        guard let right else {
            return true
        }

        if left.length != right.length {
            return left.length > right.length
        }

        return left.confidence >= right.confidence
    }

    private static func fallbackMergeKeyFragments(_ base: String, _ fragment: String) -> String {
        if base.hasPrefix("sk-") || base.hasPrefix("gsk_") {
            return base + fragment
        }

        if fragment.hasPrefix("sk-") || fragment.hasPrefix("gsk_") {
            return fragment + base
        }

        return base.count >= fragment.count ? base : fragment
    }

    private static func bestOverlap(suffixOf left: String, prefixOf right: String) -> FragmentOverlap? {
        let maximum = min(left.count, right.count, 32)

        guard maximum >= 4 else {
            return nil
        }

        var best: FragmentOverlap?

        for length in stride(from: maximum, through: 4, by: -1) {
            let leftSuffix = String(left.suffix(length))
            let rightPrefix = String(right.prefix(length))
            let allowedDistance = max(1, length / 5)
            let editDistance = levenshteinDistance(leftSuffix, rightPrefix, maximum: allowedDistance)

            guard editDistance <= allowedDistance else {
                continue
            }

            let confidence = Double(length - editDistance) / Double(length)
            guard confidence >= 0.72 else {
                continue
            }

            let overlap = FragmentOverlap(
                length: length,
                editDistance: editDistance,
                confidence: confidence
            )

            if let current = best {
                if overlap.length > current.length ||
                    (overlap.length == current.length && overlap.confidence > current.confidence) {
                    best = overlap
                }
            } else {
                best = overlap
            }
        }

        return best
    }

    private static func overlapLength(suffixOf left: String, prefixOf right: String) -> Int {
        let maximum = min(left.count, right.count)

        guard maximum > 0 else {
            return 0
        }

        for length in stride(from: maximum, through: 1, by: -1) {
            let leftSuffix = left.suffix(length)
            let rightPrefix = right.prefix(length)
            if leftSuffix == rightPrefix {
                return length
            }
        }

        return 0
    }

    private static func shouldAppendLowConfidenceContinuation(to base: String, fragment: String) -> Bool {
        guard base.hasPrefix("sk-") || base.hasPrefix("gsk_") else {
            return false
        }

        guard !fragment.hasPrefix("sk-"),
              !fragment.hasPrefix("gsk_"),
              fragment.count >= 10,
              base.count + fragment.count <= 140 else {
            return false
        }

        return isLikelyKeyFragment(fragment)
    }

    private static func exactPlacement(of fragment: String, in text: String) -> FragmentPlacement? {
        guard let range = text.range(of: fragment) else {
            return nil
        }

        return FragmentPlacement(
            startIndex: text.distance(from: text.startIndex, to: range.lowerBound),
            length: fragment.count,
            confidence: 1
        )
    }

    private static func fuzzyPlacement(of fragment: String, in text: String) -> FragmentPlacement? {
        let textCharacters = Array(text)
        let fragmentCharacters = Array(fragment)

        guard textCharacters.count >= 4,
              fragmentCharacters.count >= 4 else {
            return nil
        }

        let minimumLength = max(4, fragmentCharacters.count - 2)
        let maximumLength = min(textCharacters.count, fragmentCharacters.count + 2)
        var bestPlacement: FragmentPlacement?

        for length in minimumLength...maximumLength {
            guard length <= textCharacters.count else {
                continue
            }

            for startIndex in 0...(textCharacters.count - length) {
                let window = String(textCharacters[startIndex..<(startIndex + length)])
                let allowedDistance = max(1, min(fragmentCharacters.count, length) / 5)
                let editDistance = levenshteinDistance(fragment, window, maximum: allowedDistance)

                guard editDistance <= allowedDistance else {
                    continue
                }

                let confidence = 1 - (Double(editDistance) / Double(max(fragmentCharacters.count, length)))
                guard confidence >= 0.68 else {
                    continue
                }

                let placement = FragmentPlacement(
                    startIndex: startIndex,
                    length: length,
                    confidence: confidence
                )

                if let current = bestPlacement {
                    if placement.confidence > current.confidence ||
                        (abs(placement.confidence - current.confidence) < 0.01 && placement.length > current.length) {
                        bestPlacement = placement
                    }
                } else {
                    bestPlacement = placement
                }
            }
        }

        return bestPlacement
    }

    private static func addStitchCandidate(
        _ path: StitchPath,
        to candidatesByKey: inout [String: TalkieAIProviderCredentialStitchCandidate]
    ) {
        let apiKey = cleanedAPIKey(path.text)

        guard apiKey.count >= 8,
              !apiKey.contains("*"),
              !apiKey.contains("•") else {
            return
        }

        let providerId = providerId(for: apiKey)
        let validShape = isValidAPIKey(apiKey, providerId: providerId)
        let hasPrefix = apiKey.hasPrefix("sk-") || apiKey.hasPrefix("gsk_")
        let lengthScore = min(Double(apiKey.count) / 100, 1) * 0.35
        let fragmentScore = min(Double(path.fragments.count) / 6, 1) * 0.2
        let prefixScore = hasPrefix ? 0.12 : 0
        let validShapeScore = validShape ? 0.18 : 0
        let mergeScore = path.averageMergeConfidence * 0.15
        let score = min(lengthScore + fragmentScore + prefixScore + validShapeScore + mergeScore, 1)

        let candidate = TalkieAIProviderCredentialStitchCandidate(
            providerId: providerId,
            apiKey: apiKey,
            fragments: path.fragments,
            score: score,
            fuzzyMergeCount: path.fuzzyMergeCount,
            exactMergeCount: path.exactMergeCount,
            isValidShape: validShape
        )

        if let current = candidatesByKey[apiKey],
           stitchCandidateSort(current, candidate) {
            return
        }

        candidatesByKey[apiKey] = candidate
    }

    private static func stitchCandidateSort(
        _ left: TalkieAIProviderCredentialStitchCandidate,
        _ right: TalkieAIProviderCredentialStitchCandidate
    ) -> Bool {
        if left.isValidShape != right.isValidShape {
            return left.isValidShape
        }

        if left.hasProviderPrefix != right.hasProviderPrefix {
            return left.hasProviderPrefix
        }

        if abs(left.score - right.score) > 0.01 {
            return left.score > right.score
        }

        if left.apiKey.count != right.apiKey.count {
            return left.apiKey.count > right.apiKey.count
        }

        return left.fragments.count > right.fragments.count
    }

    private static func providerId(for apiKey: String) -> String {
        apiKey.hasPrefix("gsk_") ? "groq" : "openai"
    }

    private static func keyFragmentRank(_ fragment: String) -> Double {
        var rank = Double(fragment.count)

        if fragment.hasPrefix("sk-") || fragment.hasPrefix("gsk_") {
            rank += 100
        }

        if fragment.contains(where: \.isNumber) {
            rank += 10
        }

        return rank
    }

    private static func levenshteinDistance(_ left: String, _ right: String, maximum: Int) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)

        guard !leftCharacters.isEmpty else {
            return rightCharacters.count
        }

        guard !rightCharacters.isEmpty else {
            return leftCharacters.count
        }

        var previous = Array(0...rightCharacters.count)

        for leftIndex in 1...leftCharacters.count {
            var current = Array(repeating: 0, count: rightCharacters.count + 1)
            current[0] = leftIndex
            var rowMinimum = current[0]

            for rightIndex in 1...rightCharacters.count {
                let substitutionCost = leftCharacters[leftIndex - 1] == rightCharacters[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }

            if rowMinimum > maximum {
                return rowMinimum
            }

            previous = current
        }

        return previous[rightCharacters.count]
    }

    private static func cleanedAPIKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’<>[](){}.,;:"))
    }

    private static func isValidAPIKey(_ apiKey: String, providerId: String) -> Bool {
        guard apiKey.count >= 20,
              !apiKey.contains("*"),
              !apiKey.contains("•") else {
            return false
        }

        switch providerId {
        case "groq":
            return apiKey.hasPrefix("gsk_")
        default:
            return apiKey.hasPrefix("sk-")
        }
    }
}

private struct StitchPath {
    let text: String
    let fragments: [String]
    let averageMergeConfidence: Double
    let fuzzyMergeCount: Int
    let exactMergeCount: Int
}

private struct StitchMerge {
    let text: String
    let fragment: String
    let confidence: Double
    let overlapLength: Int
    let isFuzzy: Bool
}

private struct FragmentOverlap: Equatable {
    let length: Int
    let editDistance: Int
    let confidence: Double
}

private struct FragmentPlacement {
    let startIndex: Int
    let length: Int
    let confidence: Double
}

struct TalkieAIProviderCredentialOCRCandidate: Identifiable, Equatable {
    var id: String { "\(providerId):\(apiKey)" }
    let providerId: String
    let apiKey: String

    var providerName: String {
        TalkieAIProviderCredentialPayload.displayName(for: providerId)
    }
}

struct TalkieAIProviderCredentialStitchCandidate: Identifiable, Equatable {
    var id: String { "\(providerId):\(apiKey):\(fragments.count)" }
    let providerId: String
    let apiKey: String
    let fragments: [String]
    let score: Double
    let fuzzyMergeCount: Int
    let exactMergeCount: Int
    let isValidShape: Bool

    var hasProviderPrefix: Bool {
        apiKey.hasPrefix("sk-") || apiKey.hasPrefix("gsk_")
    }

    var confidencePercent: Int {
        min(max(Int((score * 100).rounded()), 0), 100)
    }
}

struct TalkieAIProviderCredentialCharacterConfidence: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    let character: Character
    let confidence: Double
}

struct TalkieAIProviderCredentialLocalComparison: Equatable {
    let isMatch: Bool
    let similarity: Double
    let editDistance: Int
    let candidateLength: Int
    let expectedLength: Int

    var similarityPercent: Int {
        min(max(Int((similarity * 100).rounded()), 0), 100)
    }
}

enum TalkieAIProviderCredentialOCRError: LocalizedError {
    case noKeyFound
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .noKeyFound:
            return "No OpenAI or Groq API key was found in this image."
        case .invalidKey:
            return "This does not look like a complete OpenAI or Groq API key."
        }
    }
}
