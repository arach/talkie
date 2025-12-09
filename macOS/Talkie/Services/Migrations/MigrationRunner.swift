//
//  MigrationRunner.swift
//  Talkie macOS
//
//  Orchestrates one-time data migrations.
//  Migrations run in order and are tracked in UserDefaults.
//

import Foundation
import CoreData
import os

private let logger = Logger(subsystem: "live.talkie.core", category: "Migration")

// MARK: - Migration Type

struct Migration {
    let id: String
    let description: String
    let run: (NSManagedObjectContext) throws -> Int
}

// MARK: - Migration Runner

@MainActor
class MigrationRunner {
    static let shared = MigrationRunner()

    private init() {}

    // MARK: - Public API

    /// Run all pending migrations. Call once at app startup.
    func runPending(context: NSManagedObjectContext) {
        let migrations = allMigrations
        logger.info("Checking \(migrations.count) migration(s)...")

        var completed = 0
        var skipped = 0

        for migration in migrations {
            let key = "migration.\(migration.id)"

            if UserDefaults.standard.bool(forKey: key) {
                skipped += 1
                continue
            }

            do {
                let count = try migration.run(context)

                if count > 0 {
                    try context.save()
                    logger.info("✅ \(migration.id): \(migration.description) (\(count) records)")
                } else {
                    logger.info("✅ \(migration.id): \(migration.description) (no records)")
                }

                UserDefaults.standard.set(true, forKey: key)
                completed += 1

            } catch {
                logger.error("❌ \(migration.id) failed: \(error.localizedDescription)")
                // Don't mark complete - retry next launch
            }
        }

        if completed > 0 || skipped > 0 {
            logger.info("Migrations: \(completed) completed, \(skipped) already done")
        }
    }

    // MARK: - Debug Helpers

    /// Reset a specific migration by ID (for testing)
    func reset(id: String) {
        let key = "migration.\(id)"
        UserDefaults.standard.removeObject(forKey: key)
        logger.warning("Reset migration: \(id)")
    }

    /// Reset all migrations (for testing)
    func resetAll() {
        for migration in allMigrations {
            UserDefaults.standard.removeObject(forKey: "migration.\(migration.id)")
        }
        logger.warning("Reset all \(allMigrations.count) migration(s)")
    }

    /// List migration status
    func status() -> [(id: String, description: String, completed: Bool)] {
        allMigrations.map { migration in
            (
                id: migration.id,
                description: migration.description,
                completed: UserDefaults.standard.bool(forKey: "migration.\(migration.id)")
            )
        }
    }
}
