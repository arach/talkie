#!/usr/bin/env swift
//
//  RunMigration.swift
//  Standalone migration runner
//
//  Run with: swift RunMigration.swift
//

import Foundation
import CoreData

print("🚀 Talkie Core Data → GRDB Migration")
print("=====================================\n")

// This would need to be a proper Swift Package Manager executable
// For now, let's run it through the app itself

print("Migration must be run through the app.")
print("\nTo run migration:")
print("1. Launch Talkie.app")
print("2. If migration UI doesn't show automatically, check UserDefaults:")
print("   defaults read jdi.talkie.core grdb_migration_complete")
print("3. To force show migration UI:")
print("   defaults delete jdi.talkie.core grdb_migration_complete")
print("   Then relaunch app\n")
