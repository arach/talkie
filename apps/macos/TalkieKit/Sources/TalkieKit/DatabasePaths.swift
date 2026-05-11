//
//  DatabasePaths.swift
//  TalkieKit
//
//  Shared database path constants for Talkie + TalkieAgent
//  Single source of truth for database locations
//

import Foundation
import SQLite3

/// Database path constants shared between Talkie and TalkieAgent
/// Both apps access the same talkie.sqlite file
public enum TalkieDatabase {

    // MARK: - Filenames

    /// Current GRDB database filename
    public static let filename = "talkie.sqlite"

    /// Legacy GRDB filename (for migration)
    public static let legacyFilename = "talkie_grdb.sqlite"

    /// Core Data database filename (separate from GRDB)
    public static let coreDataFilename = "talkie_coredata.sqlite"

    /// Shared folder name in Application Support
    public static let folderName = "Talkie"

    // MARK: - URLs

    /// ~/Library/Application Support/Talkie/
    public static var folderURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// ~/Library/Application Support/Talkie/talkie.sqlite
    public static var databaseURL: URL {
        folderURL.appendingPathComponent(filename)
    }

    /// ~/Library/Application Support/Talkie/talkie_grdb.sqlite (legacy)
    public static var legacyDatabaseURL: URL {
        folderURL.appendingPathComponent(legacyFilename)
    }

    /// ~/Library/Application Support/Talkie/talkie_coredata.sqlite
    public static var coreDataDatabaseURL: URL {
        folderURL.appendingPathComponent(coreDataFilename)
    }

    // MARK: - Migration

    /// Separate Core Data from GRDB databases if needed
    /// This handles the case where talkie.sqlite was previously used by Core Data
    /// and talkie_grdb.sqlite contains the actual GRDB data
    ///
    /// Migration steps:
    /// 1. If talkie.sqlite contains Core Data tables (ZVOICEMEMO), move it to talkie_coredata.sqlite
    /// 2. Then migrateFilenameIfNeeded() will move talkie_grdb.sqlite to talkie.sqlite
    ///
    /// Returns true if migration occurred, false if not needed
    @discardableResult
    public static func separateCoreDataIfNeeded() -> Bool {
        let fm = FileManager.default
        let talkiePath = databaseURL.path
        let coreDataPath = coreDataDatabaseURL.path
        let grdbLegacyPath = legacyDatabaseURL.path

        // Only migrate if:
        // 1. talkie.sqlite exists
        // 2. talkie_coredata.sqlite does NOT exist (haven't migrated yet)
        // 3. talkie_grdb.sqlite exists (we have GRDB data to migrate)
        guard fm.fileExists(atPath: talkiePath),
              !fm.fileExists(atPath: coreDataPath),
              fm.fileExists(atPath: grdbLegacyPath) else {
            return false
        }

        // Check if talkie.sqlite is a Core Data database (contains ZVOICEMEMO table)
        // If so, it needs to move to talkie_coredata.sqlite
        guard isCoreDataDatabase(at: databaseURL) else {
            return false
        }

        do {
            // Move Core Data's talkie.sqlite to talkie_coredata.sqlite
            try fm.moveItem(atPath: talkiePath, toPath: coreDataPath)

            // Move WAL file if it exists
            let walOld = talkiePath + "-wal"
            let walNew = coreDataPath + "-wal"
            if fm.fileExists(atPath: walOld) {
                try fm.moveItem(atPath: walOld, toPath: walNew)
            }

            // Move SHM file if it exists
            let shmOld = talkiePath + "-shm"
            let shmNew = coreDataPath + "-shm"
            if fm.fileExists(atPath: shmOld) {
                try fm.moveItem(atPath: shmOld, toPath: shmNew)
            }

            return true
        } catch {
            // Migration failed - don't crash
            return false
        }
    }

    /// Check if a SQLite database at the given URL is a Core Data database
    /// by looking for Core Data's characteristic tables (Z_METADATA, ZVOICEMEMO, etc.)
    private static func isCoreDataDatabase(at url: URL) -> Bool {
        // Use sqlite3 to check for Core Data tables
        // Core Data databases have tables prefixed with Z_ and Z_METADATA
        guard let db = try? openSQLite(at: url) else { return false }
        defer { sqlite3_close(db) }

        // Check for Z_METADATA table (Core Data's internal table)
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='Z_METADATA'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func openSQLite(at url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            throw NSError(domain: "TalkieDatabase", code: Int(result), userInfo: nil)
        }
        return db
    }

    /// Migrate from talkie_grdb.sqlite to talkie.sqlite if needed
    /// Safe to call multiple times - only migrates once
    /// Returns true if migration occurred, false if not needed
    @discardableResult
    public static func migrateFilenameIfNeeded() -> Bool {
        let fm = FileManager.default
        let legacyPath = legacyDatabaseURL.path
        let newPath = databaseURL.path

        // Only migrate if legacy exists and new doesn't
        guard fm.fileExists(atPath: legacyPath) && !fm.fileExists(atPath: newPath) else {
            return false
        }

        do {
            // Ensure target directory exists
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // Rename main database file
            try fm.moveItem(atPath: legacyPath, toPath: newPath)

            // Rename WAL file if it exists
            let walLegacy = legacyPath + "-wal"
            let walNew = newPath + "-wal"
            if fm.fileExists(atPath: walLegacy) {
                try fm.moveItem(atPath: walLegacy, toPath: walNew)
            }

            // Rename SHM file if it exists
            let shmLegacy = legacyPath + "-shm"
            let shmNew = newPath + "-shm"
            if fm.fileExists(atPath: shmLegacy) {
                try fm.moveItem(atPath: shmLegacy, toPath: shmNew)
            }

            return true
        } catch {
            // Migration failed - log but don't crash
            // User may need manual intervention if both files somehow exist
            return false
        }
    }
}
