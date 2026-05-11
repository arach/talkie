//
//  DictationMigrationService.swift
//  Talkie
//
//  One-time migration of dictations from live.sqlite to unified recordings table
//  Runs at app startup, tracks progress in UserDefaults
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)

/// Service to migrate dictations from live.sqlite to the unified recordings table
actor DictationMigrationService {
    static let shared = DictationMigrationService()

    private let recordingRepository = TalkieObjectRepository()

    /// UserDefaults key to track migration state
    private let migrationCompletedKey = "dictationMigrationCompleted_v1"
    private let migrationCountKey = "dictationMigrationCount_v1"

    /// Check if migration has been completed
    var isMigrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: migrationCompletedKey)
    }

    /// Number of dictations migrated
    var migratedCount: Int {
        UserDefaults.standard.integer(forKey: migrationCountKey)
    }

    /// Run the migration if needed.
    /// Returns the number of dictations migrated (0 if already done)
    func migrateIfNeeded() async throws -> Int {
        if !isMigrationCompleted {
            return try await migrate()
        } else {
            log.info("📦 Dictation migration already completed (\(migratedCount) records)")
            return 0
        }
    }

    /// Force run the migration (for testing or re-migration)
    func migrate() async throws -> Int {
        log.info("📦 Starting dictation migration from live.sqlite...")

        // Fetch all dictations from LiveDatabase
        let dictations = try await fetchAllDictations()

        if dictations.isEmpty {
            log.info("📦 No dictations to migrate")
            markMigrationCompleted(count: 0)
            return 0
        }

        log.info("📦 Found \(dictations.count) dictations to migrate")

        // Import dictations using repository method (has duplicate detection)
        var totalMigrated = 0

        for dictation in dictations {
            do {
                try await recordingRepository.importDictation(dictation)
                totalMigrated += 1

                if totalMigrated % 50 == 0 {
                    log.info("📦 Migrated \(totalMigrated)/\(dictations.count) dictations")
                }
            } catch {
                log.warning("📦 Skipped dictation: \(error.localizedDescription)")
            }
        }

        // Mark migration as complete
        markMigrationCompleted(count: totalMigrated)

        log.info("✅ Dictation migration complete: \(totalMigrated) records")
        return totalMigrated
    }

    /// Fetch all dictations - DEPRECATED
    /// Now that TalkieAgent writes directly to the unified recordings table,
    /// this migration is no longer needed. Returns empty to skip migration.
    private func fetchAllDictations() async throws -> [LiveDictation] {
        // Migration is no longer needed - TalkieAgent writes directly to recordings table
        // Return empty to skip migration
        return []
    }


    /// Mark migration as completed
    private nonisolated func markMigrationCompleted(count: Int) {
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
        UserDefaults.standard.set(count, forKey: migrationCountKey)
    }

    /// Reset migration state (for testing)
    nonisolated func resetMigrationState() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: migrationCountKey)
        log.info("📦 Dictation migration state reset")
    }
}
