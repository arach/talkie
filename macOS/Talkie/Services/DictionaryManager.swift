//
//  DictionaryManager.swift
//  Talkie
//
//  Manages multiple dictionaries - coordinates between UI and file storage
//  Syncs enabled entries to Engine for processing
//

import Foundation
import TalkieKit

private let log = Log(.system)

@MainActor
final class DictionaryManager: ObservableObject {
    static let shared = DictionaryManager()

    // MARK: - Published State

    @Published private(set) var dictionaries: [TalkieDictionary] = []
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false

    /// Global enable/disable for dictionary processing
    @Published var isGloballyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isGloballyEnabled, forKey: "dictionaryEnabled")
            syncToEngine()
        }
    }

    // MARK: - Computed

    /// Total entry count across all dictionaries
    var totalEntryCount: Int {
        dictionaries.reduce(0) { $0 + $1.entries.count }
    }

    /// Total enabled entry count
    var enabledEntryCount: Int {
        dictionaries
            .filter { $0.isEnabled }
            .reduce(0) { $0 + $1.enabledEntryCount }
    }

    /// All enabled entries from enabled dictionaries (for Engine)
    var allEnabledEntries: [DictionaryEntry] {
        dictionaries
            .filter { $0.isEnabled }
            .flatMap { $0.enabledEntries }
    }

    // MARK: - Init

    private init() {
        self.isGloballyEnabled = UserDefaults.standard.bool(forKey: "dictionaryEnabled")
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            // Load manifest first
            try await DictionaryFileManager.shared.loadManifest()

            // Migrate legacy format if needed
            try await DictionaryFileManager.shared.migrateFromLegacyFormat()

            // Reload manifest after migration
            try await DictionaryFileManager.shared.loadManifest()

            // Load all dictionaries
            let loaded = try await DictionaryFileManager.shared.loadAllDictionaries()
            dictionaries = loaded
            isLoaded = true

            log.info("Dictionaries loaded", detail: "\(dictionaries.count) dictionaries, \(totalEntryCount) total entries")

            // Sync to engine
            syncToEngine()

        } catch {
            log.error("Failed to load dictionaries", error: error)
            isLoaded = true
        }

        isLoading = false
    }

    // MARK: - Dictionary CRUD

    func createDictionary(name: String, description: String? = nil) async {
        do {
            let dictionary = try await DictionaryFileManager.shared.createDictionary(
                name: name,
                description: description
            )
            dictionaries.append(dictionary)
            log.info("Dictionary created", detail: name)
        } catch {
            log.error("Failed to create dictionary", error: error)
        }
    }

    func updateDictionary(_ dictionary: TalkieDictionary) async {
        do {
            var updated = dictionary
            updated.modifiedAt = Date()
            try await DictionaryFileManager.shared.saveDictionary(updated)

            if let index = dictionaries.firstIndex(where: { $0.id == dictionary.id }) {
                dictionaries[index] = updated
            }

            syncToEngine()
            log.debug("Dictionary updated", detail: dictionary.name)
        } catch {
            log.error("Failed to update dictionary", error: error)
        }
    }

    func deleteDictionary(_ dictionary: TalkieDictionary) async {
        do {
            try await DictionaryFileManager.shared.deleteDictionary(id: dictionary.id)
            dictionaries.removeAll { $0.id == dictionary.id }
            syncToEngine()
            log.info("Dictionary deleted", detail: dictionary.name)
        } catch {
            log.error("Failed to delete dictionary", error: error)
        }
    }

    func toggleDictionary(_ dictionary: TalkieDictionary) async {
        do {
            try await DictionaryFileManager.shared.toggleDictionary(id: dictionary.id)

            if let index = dictionaries.firstIndex(where: { $0.id == dictionary.id }) {
                dictionaries[index].isEnabled.toggle()
            }

            syncToEngine()
        } catch {
            log.error("Failed to toggle dictionary", error: error)
        }
    }

    // MARK: - Entry CRUD

    func addEntry(to dictionaryId: UUID, entry: DictionaryEntry) async {
        guard let index = dictionaries.firstIndex(where: { $0.id == dictionaryId }) else { return }

        dictionaries[index].entries.append(entry)
        dictionaries[index].modifiedAt = Date()

        await updateDictionary(dictionaries[index])
        log.info("Entry added", detail: "'\(entry.trigger)' -> '\(entry.replacement)'")
    }

    func updateEntry(in dictionaryId: UUID, entry: DictionaryEntry) async {
        guard let dictIndex = dictionaries.firstIndex(where: { $0.id == dictionaryId }) else { return }
        guard let entryIndex = dictionaries[dictIndex].entries.firstIndex(where: { $0.id == entry.id }) else { return }

        dictionaries[dictIndex].entries[entryIndex] = entry
        dictionaries[dictIndex].modifiedAt = Date()

        await updateDictionary(dictionaries[dictIndex])
        log.debug("Entry updated", detail: entry.trigger)
    }

    func deleteEntry(from dictionaryId: UUID, entry: DictionaryEntry) async {
        guard let dictIndex = dictionaries.firstIndex(where: { $0.id == dictionaryId }) else { return }

        dictionaries[dictIndex].entries.removeAll { $0.id == entry.id }
        dictionaries[dictIndex].modifiedAt = Date()

        await updateDictionary(dictionaries[dictIndex])
        log.info("Entry deleted", detail: entry.trigger)
    }

    func toggleEntry(in dictionaryId: UUID, entry: DictionaryEntry) async {
        guard let dictIndex = dictionaries.firstIndex(where: { $0.id == dictionaryId }) else { return }
        guard let entryIndex = dictionaries[dictIndex].entries.firstIndex(where: { $0.id == entry.id }) else { return }

        dictionaries[dictIndex].entries[entryIndex].isEnabled.toggle()
        dictionaries[dictIndex].modifiedAt = Date()

        await updateDictionary(dictionaries[dictIndex])
    }

    // MARK: - Import

    func importDictionary(from url: URL) async throws -> TalkieDictionary {
        let dictionary = try await DictionaryFileManager.shared.importDictionary(from: url)
        dictionaries.append(dictionary)
        syncToEngine()
        log.info("Dictionary imported", detail: "\(dictionary.name) with \(dictionary.entries.count) entries")
        return dictionary
    }

    func importDictionary(from data: Data, name: String? = nil) async throws -> TalkieDictionary {
        let dictionary = try await DictionaryFileManager.shared.importDictionary(from: data, name: name)
        dictionaries.append(dictionary)
        syncToEngine()
        log.info("Dictionary imported", detail: "\(dictionary.name) with \(dictionary.entries.count) entries")
        return dictionary
    }

    // MARK: - Engine Sync

    private func syncToEngine() {
        guard isGloballyEnabled else {
            // Disable dictionary in engine
            Task {
                await EngineClient.shared.setDictionaryEnabled(false)
            }
            return
        }

        let entries = allEnabledEntries
        Task {
            do {
                try await EngineClient.shared.updateDictionary(entries)
                await EngineClient.shared.setDictionaryEnabled(true)
                log.debug("Dictionary synced to Engine", detail: "\(entries.count) entries")
            } catch {
                log.warning("Failed to sync dictionary to Engine", error: error)
            }
        }
    }

    /// Force reload dictionaries from disk and sync to Engine
    func reload() async {
        isLoaded = false
        await load()
    }

    // MARK: - Quick Actions

    /// Create a default personal dictionary if none exist
    func ensureDefaultDictionary() async {
        guard dictionaries.isEmpty else { return }
        await createDictionary(name: "Personal", description: "Your personal word replacements")
    }
}
