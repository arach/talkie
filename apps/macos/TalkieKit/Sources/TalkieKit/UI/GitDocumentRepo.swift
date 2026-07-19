//
//  GitDocumentRepo.swift
//  TalkieKit
//
//  A thin wrapper over `/usr/bin/git` for versioning a single-document folder.
//  Each Talkie Markdown document lives in its own folder that is a git repo:
//  autosave writes the working tree; "Save version" commits; the Revisions
//  timeline is `git log`; Restore reads a blob at a commit; Compare will diff
//  two commits. Shelling out matches the repo's existing Process patterns.
//

import Foundation

struct GitCommit {
    var hash: String
    var subject: String
    var isoDate: String
    var kind: String
}

struct GitDocumentRepo {
    let dir: URL

    private static let unit = "\u{1f}"   // ASCII unit separator for --format fields

    @discardableResult
    private func run(_ args: [String]) -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = dir
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()   // swallow stderr
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    var isRepo: Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path)
    }

    func initialize() {
        _ = run(["init", "-q"])
        _ = run(["config", "user.email", "studio@talkie.local"])
        _ = run(["config", "user.name", "Talkie Markdown"])
        _ = run(["config", "commit.gpgsign", "false"])
    }

    /// Stages everything and commits. Returns false when the working tree is clean.
    @discardableResult
    func commitAll(subject: String, kind: String) -> Bool {
        _ = run(["add", "-A"])
        let status = run(["status", "--porcelain"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty else { return false }
        return run(["commit", "-m", subject, "-m", "Talkie-Kind: \(kind)"]).status == 0
    }

    func commitCount() -> Int {
        Int(run(["rev-list", "--count", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Newest-first commit log with the Talkie-Kind trailer parsed out.
    func log() -> [GitCommit] {
        let u = Self.unit
        let format = "%H\(u)%s\(u)%aI\(u)%(trailers:key=Talkie-Kind,valueonly)"
        let out = run(["log", "--format=\(format)"]).out
        return out.split(separator: "\n").compactMap { line -> GitCommit? in
            let parts = line.components(separatedBy: u)
            guard parts.count >= 3 else { return nil }
            let kind = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return GitCommit(hash: parts[0], subject: parts[1], isoDate: parts[2], kind: kind.isEmpty ? "manual" : kind)
        }
    }

    /// File contents at a given commit (e.g. `blob(hash, "document.md")`).
    func blob(_ hash: String, path: String) -> String? {
        let r = run(["show", "\(hash):\(path)"])
        return r.status == 0 ? r.out : nil
    }

    /// Whether the working tree differs from HEAD (an unsaved draft exists).
    func hasUncommittedChanges() -> Bool {
        !run(["status", "--porcelain"]).out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
