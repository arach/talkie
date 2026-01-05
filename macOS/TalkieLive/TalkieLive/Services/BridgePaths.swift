//
//  BridgePaths.swift
//  TalkieLive
//
//  Central path configuration for bridge-related services.
//  All paths consolidated under ~/Library/Application Support/Talkie/
//

import Foundation

/// Centralized path constants for bridge-related files
enum BridgePaths {
    // MARK: - Base Directories

    /// Talkie Application Support root: ~/Library/Application Support/Talkie/
    static let appSupport: URL = {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("Talkie", isDirectory: true)
        }
        // Fallback (should never happen on macOS)
        return fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Talkie", isDirectory: true)
    }()

    /// Bridge data directory: ~/Library/Application Support/Talkie/Bridge/
    static let bridgeData: URL = {
        appSupport.appendingPathComponent("Bridge", isDirectory: true)
    }()

    /// Context directory (hidden): ~/Library/Application Support/Talkie/.context/
    static let contextDir: URL = {
        appSupport.appendingPathComponent(".context", isDirectory: true)
    }()

    // MARK: - Bridge Subdirectories

    /// Fingerprints directory: ~/Library/Application Support/Talkie/Bridge/fingerprints/
    static let fingerprintsDir: URL = {
        bridgeData.appendingPathComponent("fingerprints", isDirectory: true)
    }()

    // MARK: - Files

    /// Fingerprint index: ~/Library/Application Support/Talkie/Bridge/fingerprints/index.json
    static let fingerprintIndex: URL = {
        fingerprintsDir.appendingPathComponent("index.json")
    }()

    /// Session contexts: ~/Library/Application Support/Talkie/.context/session-contexts.json
    static let sessionContexts: URL = {
        contextDir.appendingPathComponent("session-contexts.json")
    }()

    // MARK: - Helpers

    /// Ensure all required directories exist
    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: bridgeData, withIntermediateDirectories: true)
        try fm.createDirectory(at: fingerprintsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: contextDir, withIntermediateDirectories: true)
    }

    /// Get fingerprint file for a given UUID
    static func fingerprintFile(for uuid: String) -> URL {
        fingerprintsDir.appendingPathComponent("\(uuid).jsonl")
    }
}
