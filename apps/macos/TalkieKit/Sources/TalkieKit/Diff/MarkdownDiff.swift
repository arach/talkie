//
//  MarkdownDiff.swift
//  TalkieKit
//
//  Block-aware markdown diff for the Talkie Markdown "Compare" view. It splits
//  each document into logical blocks (headings, paragraphs, lists, fences,
//  tables, and atomic `:::` tk-blocks), aligns the two block sequences with an
//  LCS, and classifies each into equal / added / removed / changed. Changed
//  prose carries a word-level diff (via `DiffEngine`) so edits read as a writer
//  revising, not a code review. tk-blocks (dictation / memo) stay atomic and
//  align by id, so an edited transcript shows as one changed card rather than a
//  remove + add. The result is a JS-serializable payload the webview renders.
//

import Foundation

public enum MarkdownDiff {

    public enum BlockKind: String {
        case heading, paragraph, list, code, quote, table, hr, dictation, memo, other
    }

    private struct Block {
        var kind: BlockKind
        var raw: String   // exact source (may be multi-line)
        var key: String   // identity for alignment (id for tk-blocks; normalized text otherwise)
    }

    // MARK: - Public payload

    /// Compare two document versions. `old` is the A (earlier) side, `new` is B.
    public static func comparePayload(old: String, new: String) -> [String: Any] {
        let a = splitBlocks(old)
        let b = splitBlocks(new)
        let ops = align(a, b)

        var segments: [[String: Any]] = []
        var added = 0, removed = 0, changed = 0

        for op in ops {
            switch op {
            case let .equal(ai, bi):
                // Keys matched but the raw text can still differ (e.g. a
                // dictation block keyed by id whose transcript was edited).
                if a[ai].raw == b[bi].raw {
                    segments.append(segment(.equal, kind: b[bi].kind, a: a[ai].raw, b: b[bi].raw))
                } else {
                    changed += 1
                    segments.append(changedSegment(a[ai], b[bi]))
                }
            case let .added(bi):
                added += 1
                segments.append(segment(.added, kind: b[bi].kind, a: nil, b: b[bi].raw))
            case let .removed(ai):
                removed += 1
                segments.append(segment(.removed, kind: a[ai].kind, a: a[ai].raw, b: nil))
            case let .changed(ai, bi):
                changed += 1
                segments.append(changedSegment(a[ai], b[bi]))
            }
        }

        return [
            "segments": segments,
            "stats": ["added": added, "removed": removed, "changed": changed],
            "identical": added == 0 && removed == 0 && changed == 0,
        ]
    }

    private static func changedSegment(_ a: Block, _ b: Block) -> [String: Any] {
        let wordOps: [[String: Any]]? = isProse(b.kind) ? wordOps(a.raw, b.raw) : nil
        return segment(.changed, kind: b.kind, a: a.raw, b: b.raw, wordOps: wordOps)
    }

    private static func segment(
        _ status: String, kind: BlockKind, a: String?, b: String?, wordOps: [[String: Any]]? = nil
    ) -> [String: Any] {
        var seg: [String: Any] = ["status": status, "kind": kind.rawValue]
        if let a { seg["a"] = a }
        if let b { seg["b"] = b }
        if let wordOps { seg["wordOps"] = wordOps }
        return seg
    }

    private static func segment(
        _ status: Status, kind: BlockKind, a: String?, b: String?, wordOps: [[String: Any]]? = nil
    ) -> [String: Any] {
        segment(status.rawValue, kind: kind, a: a, b: b, wordOps: wordOps)
    }

    private enum Status: String { case equal, added, removed, changed }

    // MARK: - Word-level diff (for changed prose)

    private static func wordOps(_ old: String, _ new: String) -> [[String: Any]] {
        DiffEngine.diff(original: old, proposed: new).operations.map { op in
            switch op {
            case .equal(let w):  return ["t": "eq", "w": DiffEngine.isNewline(w) ? "\n" : w]
            case .delete(let w): return ["t": "del", "w": DiffEngine.isNewline(w) ? "\n" : w]
            case .insert(let w): return ["t": "ins", "w": DiffEngine.isNewline(w) ? "\n" : w]
            }
        }
    }

    private static func isProse(_ kind: BlockKind) -> Bool {
        switch kind {
        case .heading, .paragraph, .list, .quote: return true
        case .code, .table, .hr, .dictation, .memo, .other: return false
        }
    }

    // MARK: - Block splitting

    /// Split markdown into logical blocks. Blank lines separate blocks; fenced
    /// code and `:::` tk-blocks are consumed whole (they may contain blanks).
    private static func splitBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var group: [String] = []

        func flush() {
            guard !group.isEmpty else { return }
            let raw = group.joined(separator: "\n")
            blocks.append(makeBlock(raw))
            group = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); i += 1; continue }

            // Atomic tk-block: ::: type ... :::
            if trimmed.hasPrefix(":::") {
                flush()
                var buf = [line]; i += 1
                while i < lines.count {
                    buf.append(lines[i])
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    i += 1
                    if t == ":::" { break }
                }
                blocks.append(makeBlock(buf.joined(separator: "\n")))
                continue
            }

            // Fenced code: ``` or ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var buf = [line]; i += 1
                while i < lines.count {
                    buf.append(lines[i])
                    let closed = lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence)
                    i += 1
                    if closed { break }
                }
                blocks.append(makeBlock(buf.joined(separator: "\n")))
                continue
            }

            group.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    private static func makeBlock(_ raw: String) -> Block {
        let kind = classify(raw)
        return Block(kind: kind, raw: raw, key: key(for: raw, kind: kind))
    }

    private static func classify(_ raw: String) -> BlockKind {
        let first = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
        let t = first.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix(":::") {
            let type = t.dropFirst(3).trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            if type == "dictation" { return .dictation }
            if type == "memo" { return .memo }
            return .other
        }
        if t.hasPrefix("```") || t.hasPrefix("~~~") { return .code }
        if t.hasPrefix("#") { return .heading }
        if t.hasPrefix(">") { return .quote }
        if t == "---" || t == "***" || t == "___" { return .hr }
        if t.hasPrefix("|") { return .table }
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") || firstIsOrderedList(t) { return .list }
        return .paragraph
    }

    private static func firstIsOrderedList(_ t: String) -> Bool {
        // "1. " / "12) " …
        var seenDigit = false
        for ch in t {
            if ch.isNumber { seenDigit = true; continue }
            if seenDigit && (ch == "." || ch == ")") { return true }
            return false
        }
        return false
    }

    /// Alignment identity. tk-blocks key by id (so an edited transcript stays
    /// the same block); everything else keys by whitespace-normalized text.
    private static func key(for raw: String, kind: BlockKind) -> String {
        if kind == .dictation || kind == .memo, let id = blockId(raw) {
            return "\(kind.rawValue):\(id)"
        }
        let collapsed = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
        return collapsed
    }

    private static func blockId(_ raw: String) -> String? {
        // id="..." on the fence line
        guard let range = raw.range(of: #"id="([^"]*)""#, options: .regularExpression) else { return nil }
        let match = String(raw[range])
        return match.split(separator: "\"").dropFirst().first.map(String.init)
    }

    // MARK: - Block alignment (LCS + change pairing)

    private enum Op {
        case equal(Int, Int)
        case added(Int)
        case removed(Int)
        case changed(Int, Int)
    }

    private static func align(_ a: [Block], _ b: [Block]) -> [Op] {
        let lcs = lcsPairs(a.map(\.key), b.map(\.key))

        // Walk both sequences, emitting equal on matched pairs and collecting
        // the removed/added runs between matches.
        var ops: [Op] = []
        var ai = 0, bi = 0
        var matchIdx = 0

        func drainRun(untilA: Int, untilB: Int) {
            var dels: [Int] = []
            var adds: [Int] = []
            while ai < untilA { dels.append(ai); ai += 1 }
            while bi < untilB { adds.append(bi); bi += 1 }
            pair(dels: dels, adds: adds, a: a, b: b, into: &ops)
        }

        while matchIdx < lcs.count {
            let (ma, mb) = lcs[matchIdx]
            drainRun(untilA: ma, untilB: mb)
            ops.append(.equal(ma, mb))
            ai = ma + 1
            bi = mb + 1
            matchIdx += 1
        }
        drainRun(untilA: a.count, untilB: b.count)
        return ops
    }

    /// Pair removed + added blocks of the same kind into `changed`; leftovers
    /// stay removed / added. Keeps a-order then b-order for the leftovers.
    /// Atomic id-keyed blocks (dictation / memo) are never paired — a different
    /// id is a different recording, so it stays remove + add (two cards).
    private static func pair(dels: [Int], adds: [Int], a: [Block], b: [Block], into ops: inout [Op]) {
        var usedAdd = Set<Int>()
        var emitted: [Op] = []
        for d in dels {
            let atomic = a[d].kind == .dictation || a[d].kind == .memo
            if !atomic, let matchPos = adds.firstIndex(where: { !usedAdd.contains($0) && b[$0].kind == a[d].kind }) {
                let addIdx = adds[matchPos]
                usedAdd.insert(addIdx)
                emitted.append(.changed(d, addIdx))
            } else {
                emitted.append(.removed(d))
            }
        }
        for add in adds where !usedAdd.contains(add) {
            emitted.append(.added(add))
        }
        ops.append(contentsOf: emitted)
    }

    /// Indices of the LCS as matched (aIndex, bIndex) pairs, in order.
    private static func lcsPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count, n = b.count
        if m == 0 || n == 0 { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < m && j < n {
            if a[i] == b[j] { pairs.append((i, j)); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return pairs
    }
}
