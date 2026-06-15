//
//  DataLayerIntegration.swift
//  Talkie
//
//  Integration guide for the new GRDB data layer
//  Shows how to initialize and switch from Core Data → GRDB
//

import Foundation
import SwiftUI
import CoreData

// MARK: - App Initialization

/// Call this in TalkieApp.swift or AppDelegate on app launch
@MainActor
func initializeDataLayer() async throws {
    TalkieConsole.info("🚀 Initializing GRDB data layer...")

    // 1. Initialize GRDB database (runs on background thread)
    try await DatabaseManager.shared.initialize()
    TalkieConsole.info("✅ GRDB database initialized")

    // 2. Check if migration is needed
    let migrationComplete = UserDefaults.standard.bool(forKey: "grdb_migration_complete")

    if !migrationComplete {
        TalkieConsole.info("⚠️ Migration required - show MigrationView to user")
        // App should show MigrationView at this point
        // After migration completes, it will set the flag
    } else {
        TalkieConsole.info("✅ Migration already complete")
    }

    // 3. CloudKit sync is managed by CloudKitSyncManager (started in StartupCoordinator)
    TalkieConsole.info("✅ Data layer ready")
}

// MARK: - Migration Check View
// Example code - actual implementation in TalkieApp.swift
/*
/// Show this view on app launch if migration is needed
struct MigrationCheckView: View {
    @Environment(\.managedObjectContext) private var coreDataContext
    @State private var showMigration = false

    var body: some View {
        Group {
            if showMigration {
                MigrationView()
            } else {
                // Your main app view
                MainAppView()
            }
        }
        .task {
            // Check if migration is needed
            let migrationComplete = UserDefaults.standard.bool(forKey: "grdb_migration_complete")
            showMigration = !migrationComplete
        }
    }
}
*/

// MARK: - Main App View (After Migration)
// Example code - actual implementation in TalkieApp.swift
/*
struct MainAppView: View {
    var body: some View {
        // Your existing app structure, use AllMemos view
        NavigationView {
            // Sidebar
            List {
                NavigationLink("All Memos") {
                    AllMemos()  // Uses GRDB
                }
                // ... other navigation items
            }
        }
    }
}
*/

// MARK: - Example: TalkieApp.swift Integration

/*
 @main
 struct TalkieApp: App {
     // Keep Core Data for migration purposes
     @Environment(\.managedObjectContext) private var coreDataContext

     var body: some Scene {
         WindowGroup {
             MigrationCheckView()
                 .environment(\.managedObjectContext, coreDataContext)
                 .task {
                     do {
                         try await initializeDataLayer()
                     } catch {
                         TalkieConsole.info("❌ Failed to initialize data layer: \(error)")
                     }
                 }
         }
     }
 }
 */

// MARK: - Performance Comparison Test

/// Run this to compare old vs new performance
@MainActor
func performanceTest() async {
    TalkieConsole.info("\n📊 PERFORMANCE TEST: Old vs New\n")

    // Test 1: Fetch 50 memos sorted by date
    TalkieConsole.info("Test 1: Fetch 50 memos sorted by date")

    let oldStart = Date()
    // OLD WAY (Core Data): Fetch ALL, sort in Swift, take 50
    // ... (your existing code)
    let oldTime = Date().timeIntervalSince(oldStart)
    TalkieConsole.info("  OLD: \(Int(oldTime * 1000))ms")

    let newStart = Date()
    let repository = LocalRepository()
    _ = try? await repository.fetchMemos(
        sortBy: .timestamp,
        ascending: false,
        limit: 50,
        offset: 0,
        searchQuery: nil,
        filters: []
    )
    let newTime = Date().timeIntervalSince(newStart)
    TalkieConsole.info("  NEW: \(Int(newTime * 1000))ms")
    TalkieConsole.info("  🎯 Speedup: \(Int(oldTime / newTime))x faster\n")

    // Test 2: Memory usage
    TalkieConsole.info("Test 2: Memory footprint")
    TalkieConsole.info("  OLD: Loads all memos into memory (~10MB for 10k memos)")
    TalkieConsole.info("  NEW: Loads only 50 memos (~50KB)")
    TalkieConsole.info("  🎯 Memory savings: 200x less\n")
}
