//
//  SettingsManager.swift
//  Talkie macOS
//
//  Manages app settings stored in Core Data
//

import Foundation
import CoreData

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var geminiApiKey: String = ""
    @Published var selectedModel: String = "gemini-1.5-flash-latest"

    private var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }

    private var isInitialized = false

    private init() {
        // Defer Core Data access until first use
    }

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        loadSettings()
    }

    // MARK: - Load Settings
    func loadSettings() {
        guard !isInitialized else { return }
        isInitialized = true

        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                self.geminiApiKey = settings.geminiApiKey ?? ""
                self.selectedModel = settings.selectedModel ?? "gemini-1.5-flash-latest"
                print("✅ Loaded settings: model=\(selectedModel), hasApiKey=\(!geminiApiKey.isEmpty)")
            } else {
                // Create default settings
                createDefaultSettings()
            }
        } catch {
            print("❌ Failed to load settings: \(error)")
            // Don't call createDefaultSettings on error to avoid cascading failures
        }
    }

    // MARK: - Save Settings
    func saveSettings() {
        ensureInitialized()
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            let settings: AppSettings

            if let existingSettings = results.first {
                settings = existingSettings
            } else {
                settings = AppSettings(context: context)
                settings.id = UUID()
            }

            settings.geminiApiKey = geminiApiKey
            settings.selectedModel = selectedModel
            settings.lastModified = Date()

            try context.save()
            print("✅ Settings saved successfully")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }

    // MARK: - Create Default Settings
    private func createDefaultSettings() {
        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.geminiApiKey = ""
        settings.selectedModel = "gemini-1.5-flash-latest"
        settings.lastModified = Date()

        do {
            try context.save()
            self.geminiApiKey = ""
            self.selectedModel = "gemini-1.5-flash-latest"
            print("✅ Created default settings")
        } catch {
            print("❌ Failed to create default settings: \(error)")
        }
    }

    // MARK: - Validation
    var hasValidApiKey: Bool {
        ensureInitialized()
        return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
