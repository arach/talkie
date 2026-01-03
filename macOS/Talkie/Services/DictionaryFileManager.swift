//
//  DictionaryFileManager.swift
//  Talkie
//
//  Manages multiple dictionary files on disk
//  Storage: ~/Library/Application Support/Talkie/Dictionaries/
//
//  Each dictionary is stored as: {name}.dict.json (e.g., personal.dict.json)
//  Manifest file tracks all dictionaries: manifest.json
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Dictionary File Manager

actor DictionaryFileManager {
    static let shared = DictionaryFileManager()

    // MARK: - Storage Paths

    private let dictionariesDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)
        let dictDir = talkieDir.appendingPathComponent("Dictionaries", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dictDir, withIntermediateDirectories: true)

        return dictDir
    }()

    private var manifestURL: URL {
        dictionariesDirectory.appendingPathComponent("manifest.json")
    }

    // MARK: - Manifest

    /// Manifest tracks dictionary metadata without loading all entries
    struct Manifest: Codable {
        var dictionaries: [DictionaryManifestEntry]
        var version: Int = 1

        struct DictionaryManifestEntry: Codable, Identifiable {
            let id: UUID
            var name: String
            var description: String?
            var isEnabled: Bool
            var entryCount: Int
            var source: DictionarySource
            var fileName: String
            var createdAt: Date
            var modifiedAt: Date
        }
    }

    private var manifest: Manifest = Manifest(dictionaries: [])

    // MARK: - Init

    private init() {}

    // MARK: - Load/Save Manifest

    func loadManifest() async throws {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            log.info("No manifest found, starting fresh")
            manifest = Manifest(dictionaries: [])
            return
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        manifest = try decoder.decode(Manifest.self, from: data)
        log.info("Manifest loaded", detail: "\(manifest.dictionaries.count) dictionaries")
    }

    private func saveManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        log.debug("Manifest saved")
    }

    // MARK: - Filename Helpers

    /// Generate a clean filename from dictionary name
    private func generateFileName(for name: String, excludingId: UUID? = nil) -> String {
        // Create slug: lowercase, replace spaces with dashes, remove special chars
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()

        let baseSlug = slug.isEmpty ? "dictionary" : slug
        var fileName = "\(baseSlug).dict.json"

        // Check for conflicts with other dictionaries
        var counter = 2
        while manifest.dictionaries.contains(where: { $0.fileName == fileName && $0.id != excludingId }) {
            fileName = "\(baseSlug)-\(counter).dict.json"
            counter += 1
        }

        return fileName
    }

    // MARK: - Dictionary Operations

    /// Get all dictionary metadata (without loading entries)
    func getAllDictionaryMetadata() -> [Manifest.DictionaryManifestEntry] {
        manifest.dictionaries
    }

    /// Load a specific dictionary with all its entries
    func loadDictionary(id: UUID) async throws -> TalkieDictionary {
        guard let entry = manifest.dictionaries.first(where: { $0.id == id }) else {
            throw DictionaryFileError.notFound(id)
        }

        let fileURL = dictionariesDirectory.appendingPathComponent(entry.fileName)
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TalkieDictionary.self, from: data)
    }

    /// Load all enabled dictionaries
    func loadAllEnabledDictionaries() async throws -> [TalkieDictionary] {
        var dictionaries: [TalkieDictionary] = []

        for entry in manifest.dictionaries where entry.isEnabled {
            do {
                let dict = try await loadDictionary(id: entry.id)
                dictionaries.append(dict)
            } catch {
                log.error("Failed to load dictionary '\(entry.name)'", error: error)
            }
        }

        return dictionaries
    }

    /// Load all dictionaries (enabled and disabled)
    func loadAllDictionaries() async throws -> [TalkieDictionary] {
        var dictionaries: [TalkieDictionary] = []

        for entry in manifest.dictionaries {
            do {
                let dict = try await loadDictionary(id: entry.id)
                dictionaries.append(dict)
            } catch {
                log.error("Failed to load dictionary '\(entry.name)'", error: error)
            }
        }

        return dictionaries
    }

    /// Save a dictionary to disk
    func saveDictionary(_ dictionary: TalkieDictionary) async throws {
        // Check if this dictionary already exists with a different filename
        let existingEntry = manifest.dictionaries.first(where: { $0.id == dictionary.id })
        let oldFileName = existingEntry?.fileName

        // Generate filename from name (handles conflicts)
        let fileName = generateFileName(for: dictionary.name, excludingId: dictionary.id)
        let fileURL = dictionariesDirectory.appendingPathComponent(fileName)

        // If name changed and old file exists, delete it
        if let oldFileName = oldFileName, oldFileName != fileName {
            let oldFileURL = dictionariesDirectory.appendingPathComponent(oldFileName)
            if FileManager.default.fileExists(atPath: oldFileURL.path) {
                try? FileManager.default.removeItem(at: oldFileURL)
                log.debug("Renamed dictionary file", detail: "\(oldFileName) → \(fileName)")
            }
        }

        // Save dictionary file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dictionary)
        try data.write(to: fileURL, options: .atomic)

        // Update manifest
        let manifestEntry = Manifest.DictionaryManifestEntry(
            id: dictionary.id,
            name: dictionary.name,
            description: dictionary.description,
            isEnabled: dictionary.isEnabled,
            entryCount: dictionary.entries.count,
            source: dictionary.source,
            fileName: fileName,
            createdAt: dictionary.createdAt,
            modifiedAt: dictionary.modifiedAt
        )

        if let index = manifest.dictionaries.firstIndex(where: { $0.id == dictionary.id }) {
            manifest.dictionaries[index] = manifestEntry
        } else {
            manifest.dictionaries.append(manifestEntry)
        }

        try saveManifest()
        log.info("Dictionary saved", detail: "'\(dictionary.name)' → \(fileName)")
    }

    /// Create a new dictionary
    func createDictionary(name: String, description: String? = nil, source: DictionarySource = .manual) async throws -> TalkieDictionary {
        let dictionary = TalkieDictionary(
            name: name,
            description: description,
            source: source
        )
        try await saveDictionary(dictionary)
        return dictionary
    }

    /// Delete a dictionary
    func deleteDictionary(id: UUID) async throws {
        guard let index = manifest.dictionaries.firstIndex(where: { $0.id == id }) else {
            throw DictionaryFileError.notFound(id)
        }

        let entry = manifest.dictionaries[index]
        let fileURL = dictionariesDirectory.appendingPathComponent(entry.fileName)

        // Delete file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        // Remove from manifest
        manifest.dictionaries.remove(at: index)
        try saveManifest()

        log.info("Dictionary deleted", detail: entry.name)
    }

    /// Toggle dictionary enabled state
    func toggleDictionary(id: UUID) async throws {
        guard let index = manifest.dictionaries.firstIndex(where: { $0.id == id }) else {
            throw DictionaryFileError.notFound(id)
        }

        manifest.dictionaries[index].isEnabled.toggle()
        try saveManifest()

        // Also update the dictionary file
        var dict = try await loadDictionary(id: id)
        dict.isEnabled = manifest.dictionaries[index].isEnabled
        try await saveDictionary(dict)
    }

    // MARK: - Import

    /// Import a dictionary from JSON data
    func importDictionary(from data: Data, name: String? = nil) async throws -> TalkieDictionary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode as TalkieDictionary first
        if var dictionary = try? decoder.decode(TalkieDictionary.self, from: data) {
            // Generate new ID for imported dictionary
            dictionary = TalkieDictionary(
                id: UUID(),
                name: name ?? dictionary.name,
                description: dictionary.description,
                isEnabled: true,
                entries: dictionary.entries,
                createdAt: Date(),
                modifiedAt: Date(),
                source: .imported
            )
            try await saveDictionary(dictionary)
            return dictionary
        }

        // Try to decode as array of DictionaryEntry (legacy format)
        if let entries = try? decoder.decode([DictionaryEntry].self, from: data) {
            let dictionary = TalkieDictionary(
                name: name ?? "Imported Dictionary",
                description: "Imported from JSON file",
                entries: entries,
                source: .imported
            )
            try await saveDictionary(dictionary)
            return dictionary
        }

        throw DictionaryFileError.invalidFormat
    }

    /// Import from a file URL
    func importDictionary(from url: URL) async throws -> TalkieDictionary {
        let data = try Data(contentsOf: url)
        let fileName = url.deletingPathExtension().lastPathComponent
        return try await importDictionary(from: data, name: fileName)
    }

    // MARK: - Migration

    /// Migrate UUID-based filenames to name-based filenames
    func migrateToNameBasedFilenames() async throws {
        var needsSave = false

        for (index, entry) in manifest.dictionaries.enumerated() {
            // Check if filename is UUID-based (contains UUID pattern)
            if entry.fileName.contains("-") && entry.fileName.count > 40 {
                let newFileName = generateFileName(for: entry.name, excludingId: entry.id)
                let oldFileURL = dictionariesDirectory.appendingPathComponent(entry.fileName)
                let newFileURL = dictionariesDirectory.appendingPathComponent(newFileName)

                // Rename the file
                if FileManager.default.fileExists(atPath: oldFileURL.path) {
                    try FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
                    manifest.dictionaries[index].fileName = newFileName
                    needsSave = true
                    log.info("Migrated dictionary filename", detail: "\(entry.fileName) → \(newFileName)")
                }
            }
        }

        if needsSave {
            try saveManifest()
        }
    }

    /// Migrate from old single-dictionary format
    func migrateFromLegacyFormat() async throws {
        let legacyURL: URL = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport
                .appendingPathComponent("Talkie", isDirectory: true)
                .appendingPathComponent("dictionary.json")
        }()

        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            log.debug("No legacy dictionary to migrate")
            return
        }

        // Check if we've already migrated
        guard manifest.dictionaries.isEmpty else {
            log.debug("Manifest already has dictionaries, skipping migration")
            return
        }

        let data = try Data(contentsOf: legacyURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([DictionaryEntry].self, from: data)

        guard !entries.isEmpty else {
            log.debug("Legacy dictionary is empty, skipping migration")
            return
        }

        // Create new dictionary from legacy entries
        let dictionary = TalkieDictionary(
            name: "Personal",
            description: "Migrated from legacy dictionary",
            entries: entries,
            source: .manual
        )

        try await saveDictionary(dictionary)
        log.info("Migrated legacy dictionary", detail: "\(entries.count) entries")

        // Optionally rename the old file
        let backupURL = legacyURL.deletingPathExtension().appendingPathExtension("json.migrated")
        try? FileManager.default.moveItem(at: legacyURL, to: backupURL)
    }

    // MARK: - Get all entries flattened

    /// Get all enabled entries from all enabled dictionaries (for Engine sync)
    func getAllEnabledEntries() async throws -> [DictionaryEntry] {
        let dictionaries = try await loadAllEnabledDictionaries()
        return dictionaries.flatMap { $0.enabledEntries }
    }

    // MARK: - Presets

    /// Directory containing bundled preset dictionaries
    private var presetsDirectory: URL? {
        Bundle.main.url(forResource: "Presets", withExtension: nil)
    }

    /// List all available presets from the app bundle
    func listAvailablePresets() async -> [PresetInfo] {
        guard let presetsDir = presetsDirectory else {
            log.warning("Presets directory not found in bundle")
            return []
        }

        var presets: [PresetInfo] = []

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: presetsDir,
                includingPropertiesForKeys: nil
            )

            for fileURL in contents where fileURL.pathExtension == "json" && fileURL.lastPathComponent.contains(".dict.") {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let preset = try JSONDecoder().decode(PresetDictionary.self, from: data)

                    // Check if already installed by matching name
                    let isInstalled = manifest.dictionaries.contains { entry in
                        entry.source == .preset && entry.name == preset.name
                    }

                    let presetId = fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent
                    presets.append(PresetInfo(
                        id: presetId,
                        name: preset.name,
                        description: preset.description,
                        version: preset.version,
                        entryCount: preset.entries.count,
                        isInstalled: isInstalled
                    ))
                } catch {
                    log.error("Failed to parse preset \(fileURL.lastPathComponent)", error: error)
                }
            }
        } catch {
            log.error("Failed to list presets", error: error)
        }

        return presets.sorted { $0.name < $1.name }
    }

    /// Install a preset dictionary
    func installPreset(id: String) async throws -> TalkieDictionary {
        guard let presetsDir = presetsDirectory else {
            throw DictionaryFileError.presetNotFound(id)
        }

        let fileURL = presetsDir.appendingPathComponent("\(id).dict.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DictionaryFileError.presetNotFound(id)
        }

        let data = try Data(contentsOf: fileURL)
        let preset = try JSONDecoder().decode(PresetDictionary.self, from: data)

        // Check if already installed
        if let existingEntry = manifest.dictionaries.first(where: { $0.source == .preset && $0.name == preset.name }) {
            // Already installed - return existing
            log.info("Preset already installed", detail: preset.name)
            return try await loadDictionary(id: existingEntry.id)
        }

        // Convert and save
        let dictionary = preset.toTalkieDictionary()
        try await saveDictionary(dictionary)

        log.info("Preset installed", detail: "\(preset.name) (\(preset.entries.count) entries)")
        return dictionary
    }

    /// Uninstall a preset dictionary
    func uninstallPreset(name: String) async throws {
        guard let entry = manifest.dictionaries.first(where: { $0.source == .preset && $0.name == name }) else {
            throw DictionaryFileError.notFound(UUID())
        }

        try await deleteDictionary(id: entry.id)
        log.info("Preset uninstalled", detail: name)
    }

    /// Check if a preset is installed
    func isPresetInstalled(name: String) -> Bool {
        manifest.dictionaries.contains { $0.source == .preset && $0.name == name }
    }
}

// MARK: - Errors

enum DictionaryFileError: LocalizedError {
    case notFound(UUID)
    case invalidFormat
    case migrationFailed(String)
    case presetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Dictionary not found: \(id)"
        case .invalidFormat:
            return "Invalid dictionary file format"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .presetNotFound(let name):
            return "Preset not found: \(name)"
        }
    }
}

// MARK: - Preset Dictionary Format

/// JSON format for bundled preset dictionaries
struct PresetDictionary: Codable {
    let name: String
    let description: String?
    let version: String?
    let entries: [PresetEntry]

    struct PresetEntry: Codable {
        let trigger: String
        let replacement: String
        let matchType: String
        let category: String?
    }

    /// Convert to TalkieDictionary
    func toTalkieDictionary() -> TalkieDictionary {
        let dictionaryEntries = entries.compactMap { entry -> DictionaryEntry? in
            // Parse matchType string to enum
            let matchType: DictionaryMatchType
            switch entry.matchType.lowercased() {
            case "word", "exact":
                matchType = .word
            case "phrase", "caseinsensitive":
                matchType = .phrase
            case "regex":
                matchType = .regex
            case "fuzzy":
                matchType = .fuzzy
            default:
                matchType = .word
            }

            return DictionaryEntry(
                trigger: entry.trigger,
                replacement: entry.replacement,
                matchType: matchType,
                isEnabled: true,
                category: entry.category
            )
        }

        return TalkieDictionary(
            name: name,
            description: description,
            isEnabled: true,
            entries: dictionaryEntries,
            source: .preset
        )
    }
}

// MARK: - Preset Info

/// Metadata about an available preset (without loading all entries)
struct PresetInfo: Identifiable {
    let id: String  // filename without extension
    let name: String
    let description: String?
    let version: String?
    let entryCount: Int
    let isInstalled: Bool
}
