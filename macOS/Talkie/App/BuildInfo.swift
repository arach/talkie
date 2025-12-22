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

    /// Current branch name
    static let branchName: String = "feature/dashboard-to-home"

    /// Whether this is a worktree build
    static var isWorktree: Bool { worktreeName != nil }

    /// Display label for the build
    static var displayLabel: String? {
        if let worktree = worktreeName {
            return "WT: \(worktree)"
        }
        return nil
    }

    private static func detectWorktree() -> String? {
        // Check if .git is a file (worktree) vs directory (main repo)
        // For now, hardcode based on build location
        #if DEBUG
        // This gets set by build script - default to checking compile path
        return "dashboard-to-home"
        #else
        return nil
        #endif
    }
}
