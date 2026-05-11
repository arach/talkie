//
//  SyncConfig.swift
//  TalkieSync
//
//  Runtime configuration for sync service.
//  Supports test mode with isolated database copies.
//

import Foundation
import TalkieKit

/// Configuration for TalkieSync service
enum SyncConfig {

    /// Enable test mode with isolated database copies
    /// Set via launch argument: -TalkieSyncTestMode YES
    static var useTestDatabases: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "TalkieSyncTestMode")
        #else
        return false
        #endif
    }

    /// Test database folder (copies of production databases)
    static var testFolderURL: URL {
        TalkieDatabase.folderURL.appendingPathComponent("test-sync", isDirectory: true)
    }

    // MARK: - Database Paths

    /// Core Data database path (respects test mode)
    static var coreDataURL: URL {
        if useTestDatabases {
            return testFolderURL.appendingPathComponent(TalkieDatabase.coreDataFilename)
        }
        return TalkieDatabase.coreDataDatabaseURL
    }

    /// GRDB database path (respects test mode)
    static var grdbURL: URL {
        if useTestDatabases {
            return testFolderURL.appendingPathComponent(TalkieDatabase.filename)
        }
        return TalkieDatabase.databaseURL
    }

    /// Folder URL for database directory (respects test mode)
    static var folderURL: URL {
        if useTestDatabases {
            return testFolderURL
        }
        return TalkieDatabase.folderURL
    }
}
