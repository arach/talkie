//
//  MarkdownStudioDocumentStore.swift
//  TalkieKit
//
//  Local, git-backed persistence for a Talkie Markdown document. Each document
//  lives in its own folder that is a git repository:
//    <base>/<docId>/document.md   — the working draft (autosaved)
//    <base>/<docId>/assets/       — embedded audio / screenshots (block assets)
//    <base>/<docId>/.git/         — version history
//  Autosave writes the working tree; "Save version" / dictation commit. The
//  Revisions timeline is `git log`; Restore reads a blob at a commit. Everything
//  is local — "Local only · no cloud" is literally true.
//

import Foundation

@MainActor
public final class MarkdownStudioDocumentStore {
    public private(set) var text: String = ""
    public private(set) var title: String = "Home screen — redesign notes"

    /// The document's folder (contains document.md, assets/, .git/).
    public let documentDirectory: URL
    /// Folder for embedded block assets (audio, screenshots).
    public let assetsDirectory: URL

    private let docURL: URL
    private let repo: GitDocumentRepo
    private var autosaveWork: DispatchWorkItem?
    private var loaded = false

    private static let documentFileName = "document.md"

    public init(documentId: String = "home-notes") {
        let base: URL
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) {
            base = support.appendingPathComponent("TalkieMarkdownStudio", isDirectory: true)
        } else {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("TalkieMarkdownStudio", isDirectory: true)
        }
        documentDirectory = base.appendingPathComponent(documentId, isDirectory: true)
        assetsDirectory = documentDirectory.appendingPathComponent("assets", isDirectory: true)
        docURL = documentDirectory.appendingPathComponent(Self.documentFileName)
        repo = GitDocumentRepo(dir: documentDirectory)
    }

    // MARK: - Load / seed

    public func load() {
        guard !loaded else { return }
        loaded = true

        try? FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        if !repo.isRepo {
            repo.initialize()
            try? Self.seedMarkdown.data(using: .utf8)?.write(to: docURL, options: .atomic)
            repo.commitAll(subject: "Created by dictation", kind: "created")
        }

        if let data = try? Data(contentsOf: docURL), let onDisk = String(data: data, encoding: .utf8) {
            text = onDisk
        } else {
            text = Self.seedMarkdown
            try? text.data(using: .utf8)?.write(to: docURL, options: .atomic)
        }
    }

    // MARK: - Text updates (debounced autosave — writes the working tree, no commit)

    public func updateText(_ newText: String, onSaved: @escaping () -> Void) {
        text = newText
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.text.data(using: .utf8)?.write(to: self.docURL, options: .atomic)
            onSaved()
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Versions (git commits)

    /// Commits the current working draft as a new version. No-op if nothing changed.
    @discardableResult
    public func saveVersion(reason: String) -> Bool {
        let kind = normalizeKind(reason)
        try? text.data(using: .utf8)?.write(to: docURL, options: .atomic)
        return repo.commitAll(subject: Self.title(for: kind), kind: kind)
    }

    /// Restores a commit's document as the working draft and records a restore commit.
    /// `id` is a commit hash from `revisionsPayload`.
    public func restore(id: String) -> String? {
        guard let restored = repo.blob(id, path: Self.documentFileName) else { return nil }
        text = restored
        try? text.data(using: .utf8)?.write(to: docURL, options: .atomic)
        repo.commitAll(subject: "Restored from \(String(id.prefix(7)))", kind: "restore")
        return text
    }

    // MARK: - Dictation blocks (bound assets + explicit-text commits)

    /// Moves a recorded audio file into the document's assets folder and returns
    /// the doc-relative path (e.g. `assets/tkd_9f3a2c.m4a`). The source is
    /// consumed. Used to bind a dictation block to its captured audio.
    public func importAudio(from url: URL, id: String) -> String? {
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let dest = assetsDirectory.appendingPathComponent("\(id).\(ext)")
        try? FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            try? FileManager.default.removeItem(at: url)
            return "assets/\(id).\(ext)"
        } catch {
            return nil
        }
    }

    /// Sets the working draft to an explicit text and commits it as a version.
    /// Used when the caller already holds the authoritative post-edit text
    /// (e.g. a dictation block inserted through the editor) and must not race
    /// the debounced autosave. No-op commit if nothing changed.
    @discardableResult
    public func commit(text newText: String, reason: String) -> Bool {
        autosaveWork?.cancel()
        text = newText
        try? newText.data(using: .utf8)?.write(to: docURL, options: .atomic)
        let kind = normalizeKind(reason)
        return repo.commitAll(subject: Self.title(for: kind), kind: kind)
    }

    // MARK: - Compare (diff two revisions)

    /// The document's text at a given commit (id from `revisionsPayload`).
    /// `"working"` returns the current working draft.
    public func documentText(at id: String) -> String? {
        if id == "working" { return text }
        return repo.blob(id, path: Self.documentFileName)
    }

    /// Block-aware diff payload for `window.TalkieStudio.setCompare(...)`.
    /// `fromId` is the older (A) side, `toId` the newer (B) side; either may be
    /// `"working"` for the live draft.
    public func comparePayload(fromId: String, toId: String) -> [String: Any]? {
        guard let old = documentText(at: fromId), let new = documentText(at: toId) else { return nil }
        var payload = MarkdownDiff.comparePayload(old: old, new: new)
        payload["from"] = fromId
        payload["to"] = toId
        return payload
    }

    // MARK: - JS payload

    /// Payload for `window.TalkieStudio.setRevisions(...)`.
    public func revisionsPayload() -> [String: Any] {
        let commits = repo.log()
        let count = commits.count

        // Word counts per commit (for deltas). Cheap for the small histories we expect.
        let words: [Int] = commits.map { Self.wordCount(repo.blob($0.hash, path: Self.documentFileName) ?? "") }

        let items: [[String: Any]] = commits.enumerated().map { index, commit in
            let versionNumber = count - index
            let olderWords = index + 1 < words.count ? words[index + 1] : 0
            let deltaValue = words[index] - olderWords
            var delta = ""
            var deltaTone = "muted"
            if deltaValue > 0 { delta = "+\(deltaValue) w"; deltaTone = "green" }
            else if deltaValue < 0 { delta = "\u{2212}\(abs(deltaValue)) w" }
            return [
                "v": "v\(versionNumber)",
                "id": commit.hash,
                "kind": commit.kind,
                "title": commit.subject,
                "time": Self.relativeTime(fromISO: commit.isoDate),
                "delta": delta,
                "deltaTone": deltaTone,
            ]
        }

        return [
            "current": "v\(count + 1)",
            "total": count + 1,
            "items": items,
        ]
    }

    // MARK: - Helpers

    private func normalizeKind(_ reason: String) -> String {
        switch reason {
        case "dictation", "voice", "restore", "autoclean", "created": return reason
        default: return "manual"
        }
    }

    private static func title(for kind: String) -> String {
        switch kind {
        case "dictation": return "Dictation inserted"
        case "voice": return "Voice edit"
        case "restore": return "Restored"
        case "autoclean": return "Auto-clean"
        default: return "Manual save"
        }
    }

    nonisolated static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func relativeTime(fromISO iso: String) -> String {
        guard let date = isoFormatter.date(from: iso) else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Seed

    static let seedMarkdown = """
    # Home screen — redesign notes

    Captured by voice · May 27 · cleaned up with Talkie

    ## What's working

    The **agent bar** finally reads like an instrument — the amber trace draws the eye first.

    ::: dictation title="shelf-and-sheet" duration="0:24" words="61"
    I like the shelf and the sheet — basically the sheet with the list of names, and room to breathe on the right.
    :::

    - Empty states feel *inviting*, not empty
    - Recent has room to breathe
    - Waveforms are duration-accurate now

    ## Still open

    1. Should the console live in its own tab?
    2. Tighten the tips row on small windows

    > "Talk, it moves." Keep the whole thing this quiet

    Reference the [style guide](#) first. Then run:

    ```bash
    talkie export --home > notes.md
    ```

    ## Next steps

    - [x] Ship the agent bar
    - [x] Warm up the empty states
    - [ ] Decide console-in-tab
    - [ ] Tips row responsive pass

    ---

    ### Signal check

    How the redesign scored, screen by screen.

    | Screen | Before | After |
    | --- | --- | --- |
    | Home | 3.1 | 4.6 |
    | Editor | — | 4.8 |
    """
}
