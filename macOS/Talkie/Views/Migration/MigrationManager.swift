//
//  MigrationManager.swift
//  Talkie
//
//  Utility for showing migration UI from anywhere in the app
//

import SwiftUI
import AppKit
import CoreData

/// Manages the migration window and provides utility functions
@MainActor
final class MigrationManager: ObservableObject {
    static let shared = MigrationManager()

    @Published var isShowingMigration = false

    private var migrationWindow: NSWindow?

    private init() {}

    // MARK: - Public API

    /// Show the migration window
    func showMigration() {
        // If window already exists, bring it to front
        if let window = migrationWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let context = PersistenceController.shared.container.viewContext
        let contentView = MigrationView()
            .environment(\.managedObjectContext, context)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Database Migration"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false

        // Store reference
        migrationWindow = window
        isShowingMigration = true

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Handle window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.migrationWindow = nil
                self?.isShowingMigration = false
            }
        }
    }

    /// Close the migration window
    func closeMigration() {
        migrationWindow?.close()
        migrationWindow = nil
        isShowingMigration = false
    }

    // MARK: - Migration State

    /// Check if migration is needed (Core Data has data, flag not set)
    var needsMigration: Bool {
        let flagSet = UserDefaults.standard.bool(forKey: "grdb_migration_complete")
        if flagSet { return false }

        // Check Core Data count
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<NSNumber>(entityName: "VoiceMemo")
        fetchRequest.resultType = .countResultType
        do {
            let results = try context.fetch(fetchRequest)
            return (results.first?.intValue ?? 0) > 0
        } catch {
            return false
        }
    }

    /// Mark migration as complete
    func markComplete() {
        UserDefaults.standard.set(true, forKey: "grdb_migration_complete")
        NotificationCenter.default.post(name: NSNotification.Name("MigrationCompleted"), object: nil)
    }

    /// Reset migration flag (for debugging)
    func resetFlag() {
        UserDefaults.standard.removeObject(forKey: "grdb_migration_complete")
    }
}
