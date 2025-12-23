//
//  BuildInfo.swift
//  Talkie
//
//  Build identification for worktree/branch awareness
//

import Foundation

struct BuildInfo {
    /// Worktree name if running from a worktree, nil otherwise
    static let worktreeName: String? = detectWorktree()

    /// Whether this is a worktree build
    static var isWorktree: Bool { worktreeName != nil }

    /// Short display label for the build (shown in sidebar)
    static var displayLabel: String? {
        guard isWorktree else { return nil }
        return "WT"
    }

    /// Full worktree info for tooltip
    static var tooltipLabel: String? {
        if let worktree = worktreeName {
            return "Worktree: \(worktree)"
        }
        return nil
    }

    private static func detectWorktree() -> String? {
        #if DEBUG
        // Get the source file path at compile time
        let sourceFile = #file

        // Navigate up to find the repo root (look for .git)
        var url = URL(fileURLWithPath: sourceFile)
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            let gitPath = url.appendingPathComponent(".git")

            // In a worktree, .git is a FILE containing "gitdir: /path/to/main/.git/worktrees/name"
            // In main repo, .git is a DIRECTORY
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDir) {
                if !isDir.boolValue {
                    // It's a file - this is a worktree!
                    // Read the file to extract worktree name
                    if let content = try? String(contentsOf: gitPath, encoding: .utf8) {
                        // Format: "gitdir: /path/to/.git/worktrees/worktree-name"
                        if let range = content.range(of: "/worktrees/") {
                            let name = String(content[range.upperBound...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            return name.isEmpty ? nil : name
                        }
                    }
                    return "unknown"
                } else {
                    // It's a directory - main repo, not a worktree
                    return nil
                }
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}
