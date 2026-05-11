//
//  BunResolver.swift
//  TalkieKit
//
//  Shared utility for finding the Bun runtime binary.
//  Delegates to ExecutableResolver for the actual lookup.
//

import Foundation

public enum BunResolver {
    public static var searchPaths: [String] {
        ExecutableResolver.knownCandidates["bun"] ?? []
    }

    /// Find the first available bun binary on this machine.
    public static func findBunPath() -> String? {
        ExecutableResolver.resolvePath("bun")
    }
}
