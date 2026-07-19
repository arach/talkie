//
//  TKBlockParser.swift
//  TalkieKit
//
//  Talkie Markdown "tk blocks" — first-class embedded objects (dictation,
//  memo, capture, …) serialized as `:::type key="val"` directive containers
//  with a human-readable body. Attributes carry identity/linkage; the body
//  carries the text truth, so the document degrades gracefully to plain
//  markdown. This is the shared parser/serializer used by dictation insertion,
//  asset resolution, and (later) the block-aware diff.
//

import Foundation

public struct TKBlock: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case dictation, memo, capture, transcript, action, unknown
    }

    public var kind: Kind
    public var attrs: [String: String]
    public var body: String

    public init(kind: Kind, attrs: [String: String], body: String) {
        self.kind = kind
        self.attrs = attrs
        self.body = body
    }

    public var id: String? { attrs["id"] }
    public var src: String? { attrs["src"] }
}

public enum TKBlockParser {
    // ::: type  key="val" ...    /  body (non-greedy, may be multi-line)  /  :::
    private static let blockRegex = try! NSRegularExpression(
        pattern: #"(?m)^:::[ \t]*([A-Za-z][A-Za-z0-9_-]*)[ \t]*([^\n]*)\n([\s\S]*?)\n:::[ \t]*$"#
    )
    private static let attrRegex = try! NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_-]*)="([^"]*)""#)

    /// All tk blocks found in a markdown string, in document order.
    public static func parse(_ markdown: String) -> [TKBlock] {
        let ns = markdown as NSString
        let matches = blockRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        return matches.map { match in
            let kindRaw = ns.substring(with: match.range(at: 1)).lowercased()
            let attrsRaw = ns.substring(with: match.range(at: 2))
            let body = ns.substring(with: match.range(at: 3))
            return TKBlock(
                kind: TKBlock.Kind(rawValue: kindRaw) ?? .unknown,
                attrs: parseAttrs(attrsRaw),
                body: body
            )
        }
    }

    private static func parseAttrs(_ raw: String) -> [String: String] {
        let ns = raw as NSString
        var attrs: [String: String] = [:]
        for match in attrRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            attrs[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
        }
        return attrs
    }

    /// Serializes a block back to its `:::type …:::` text form.
    public static func serialize(_ block: TKBlock) -> String {
        // Stable attribute order: id, src, then the rest alphabetically.
        let priority = ["id", "src", "title", "duration", "words", "captured", "app", "window"]
        let ordered = priority.filter { block.attrs[$0] != nil }
            + block.attrs.keys.filter { !priority.contains($0) }.sorted()
        let attrString = ordered.map { "\($0)=\"\(block.attrs[$0] ?? "")\"" }.joined(separator: " ")
        let header = attrString.isEmpty ? "::: \(block.kind.rawValue)" : "::: \(block.kind.rawValue) \(attrString)"
        return "\(header)\n\(block.body)\n:::"
    }

    // MARK: - Builders

    /// A fresh block id, e.g. `tkd_9f3a2c` (dictation).
    public static func newId(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased())"
    }

    /// Builds a dictation block bound to a recorded utterance.
    public static func dictationBlock(
        id: String,
        src: String?,
        durationSec: Double,
        transcript: String,
        capturedISO: String
    ) -> TKBlock {
        var attrs: [String: String] = [
            "id": id,
            "duration": formatDuration(durationSec),
            "words": String(MarkdownStudioDocumentStore.wordCount(transcript)),
            "captured": capturedISO,
        ]
        if let src { attrs["src"] = src }
        return TKBlock(kind: .dictation, attrs: attrs, body: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
