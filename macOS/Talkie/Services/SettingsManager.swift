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

    // Internal storage
    @Published private var _geminiApiKey: String = ""
    @Published private var _openaiApiKey: String?
    @Published private var _anthropicApiKey: String?
    @Published private var _groqApiKey: String?
    @Published private var _selectedModel: String = "gemini-1.5-flash-latest"

    // Public accessors that ensure initialization
    var geminiApiKey: String {
        get { ensureInitialized(); return _geminiApiKey }
        set { _geminiApiKey = newValue }
    }

    var openaiApiKey: String? {
        get { ensureInitialized(); return _openaiApiKey }
        set { _openaiApiKey = newValue }
    }

    var anthropicApiKey: String? {
        get { ensureInitialized(); return _anthropicApiKey }
        set { _anthropicApiKey = newValue }
    }

    var groqApiKey: String? {
        get { ensureInitialized(); return _groqApiKey }
        set { _groqApiKey = newValue }
    }

    var selectedModel: String {
        get { ensureInitialized(); return _selectedModel }
        set { _selectedModel = newValue }
    }

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
        performLoadSettings()
    }

    // MARK: - Load Settings
    func loadSettings() {
        // Public method - always reload
        performLoadSettings()
    }

    private func performLoadSettings() {
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                self._geminiApiKey = settings.geminiApiKey ?? ""
                self._openaiApiKey = settings.openaiApiKey
                self._anthropicApiKey = settings.anthropicApiKey
                self._groqApiKey = settings.groqApiKey
                self._selectedModel = settings.selectedModel ?? "gemini-1.5-flash-latest"
                print("✅ Loaded settings: model=\(_selectedModel)")
                print("   - Gemini API key: \(_geminiApiKey.isEmpty ? "not set" : "set (\(_geminiApiKey.prefix(8))...)")")
                print("   - OpenAI API key: \(_openaiApiKey == nil ? "not set" : "set")")
                print("   - Anthropic API key: \(_anthropicApiKey == nil ? "not set" : "set")")
                print("   - Groq API key: \(_groqApiKey == nil ? "not set" : "set")")
            } else {
                print("⚠️ No settings found in Core Data, creating defaults...")
                createDefaultSettings()
            }
        } catch {
            print("❌ Failed to load settings: \(error)")
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
            settings.openaiApiKey = openaiApiKey
            settings.anthropicApiKey = anthropicApiKey
            settings.groqApiKey = groqApiKey
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
            self._geminiApiKey = ""
            self._selectedModel = "gemini-1.5-flash-latest"
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
