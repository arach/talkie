//
//  DictionaryManager.swift
//  Talkie
//
//  Manages personal dictionary storage and operations
//  Talkie owns the dictionary, syncs to Engine for processing
//

import Foundation
import TalkieKit

private let log = Log(.system)

@MainActor
final class DictionaryManager: ObservableObject {
    static let shared = DictionaryManager()

    // MARK: - Published State

    @Published private(set) var entries: [DictionaryEntry] = []
    @Published private(set) var isLoaded: Bool = false

    /// Whether dictionary processing is enabled in Engine
    /// This is the control Talkie uses to enable/disable dictionary globally
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "dictionaryEnabled")
            syncEnabledState()
        }
    }

    // MARK: - Storage

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)

        return talkieDir.appendingPathComponent("dictionary.json")
    }()

    // MARK: - Init

    private init() {
        // Load enabled state from UserDefaults
        self.isEnabled = UserDefaults.standard.bool(forKey: "dictionaryEnabled")
        load()
        // Sync enabled state to Engine on startup
        syncEnabledState()
    }

    // MARK: - CRUD Operations

    func addEntry(_ entry: DictionaryEntry) {
        entries.append(entry)
        save()
        syncToEngine()
        log.info("Dictionary entry added", detail: "'\(entry.trigger)' -> '\(entry.replacement)'")
    }

    func updateEntry(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
        syncToEngine()
        log.debug("Dictionary entry updated", detail: entry.trigger)
    }

    func deleteEntry(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
        syncToEngine()
        log.info("Dictionary entry deleted", detail: entry.trigger)
    }

    func deleteEntry(at offsets: IndexSet) {
        let toDelete = offsets.map { entries[$0].trigger }
        entries.remove(atOffsets: offsets)
        save()
        syncToEngine()
        log.info("Dictionary entries deleted", detail: toDelete.joined(separator: ", "))
    }

    func toggleEntry(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isEnabled.toggle()
        save()
        syncToEngine()
    }

    func incrementUsageCount(for entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[index].usageCount += 1
        // Don't save on every increment - batch save periodically
    }

    func batchIncrementUsage(for entryIds: [UUID]) {
        for id in entryIds {
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].usageCount += 1
            }
        }
        save()
    }

    // MARK: - Enabled Entries

    var enabledEntries: [DictionaryEntry] {
        entries.filter { $0.isEnabled }
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            log.info("No dictionary file found, starting fresh")
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            isLoaded = true
            log.info("Dictionary loaded", detail: "\(entries.count) entries")
            // Sync to Engine on load
            syncToEngine()
        } catch {
            log.error("Failed to load dictionary", error: error)
            isLoaded = true
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            log.debug("Dictionary saved", detail: "\(entries.count) entries")
        } catch {
            log.error("Failed to save dictionary", error: error)
        }
    }

    // MARK: - Engine Sync

    /// Sync dictionary content to Engine
    private func syncToEngine() {
        Task {
            do {
                try await EngineClient.shared.updateDictionary(enabledEntries)
                log.debug("Dictionary synced to Engine", detail: "\(enabledEntries.count) entries")
            } catch {
                log.warning("Failed to sync dictionary to Engine", error: error)
            }
        }
    }

    /// Sync enabled state to Engine
    private func syncEnabledState() {
        Task {
            await EngineClient.shared.setDictionaryEnabled(isEnabled)
            log.debug("Dictionary enabled state synced", detail: "\(isEnabled)")
        }
    }

    // MARK: - Import/Export

    func exportJSON() -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(entries)
        } catch {
            log.error("Failed to export dictionary", error: error)
            return nil
        }
    }

    func importJSON(_ data: Data, merge: Bool = true) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let imported = try decoder.decode([DictionaryEntry].self, from: data)

        if merge {
            // Merge: add new entries, skip duplicates (by trigger)
            let existingTriggers = Set(entries.map { $0.trigger.lowercased() })
            let newEntries = imported.filter { !existingTriggers.contains($0.trigger.lowercased()) }
            entries.append(contentsOf: newEntries)
            save()
            syncToEngine()
            log.info("Dictionary imported (merge)", detail: "\(newEntries.count) new entries")
            return newEntries.count
        } else {
            // Replace all
            entries = imported
            save()
            syncToEngine()
            log.info("Dictionary imported (replace)", detail: "\(imported.count) entries")
            return imported.count
        }
    }

    // MARK: - Presets

    func addCommonPresets() {
        let presets: [(String, String)] = [
            ("ios", "iOS"),
            ("macos", "macOS"),
            ("iphone", "iPhone"),
            ("ipad", "iPad"),
            ("wifi", "WiFi"),
            ("api", "API"),
            ("url", "URL"),
            ("html", "HTML"),
            ("css", "CSS"),
            ("json", "JSON"),
            ("sql", "SQL"),
        ]

        let existingTriggers = Set(entries.map { $0.trigger.lowercased() })

        for (trigger, replacement) in presets {
            if !existingTriggers.contains(trigger.lowercased()) {
                let entry = DictionaryEntry(
                    trigger: trigger,
                    replacement: replacement,
                    matchType: .exact,
                    category: "Tech"
                )
                entries.append(entry)
            }
        }

        save()
        syncToEngine()
        log.info("Added common presets")
    }

    func clearAll() {
        entries.removeAll()
        save()
        syncToEngine()
        log.info("Dictionary cleared")
    }
}
