//
//  APIKeyStore.swift
//  Talkie
//
//  Simple encrypted storage for API keys.
//  Uses AES encryption with a machine-derived key.
//  No password prompts, no Keychain complexity.
//

import Foundation
import CryptoKit
import TalkieKit

private let logger = Log(.system)

/// Encrypted storage for API keys - simpler than Keychain, no prompts
final class APIKeyStore {
    static let shared = APIKeyStore()

    // Provider keys
    enum Provider: String, CaseIterable, Codable {
        case openai
        case anthropic
        case gemini
        case groq
        case minimax
        case elevenLabs = "elevenlabs"

        var displayName: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .gemini: return "Google Gemini"
            case .groq: return "Groq"
            case .minimax: return "MiniMax"
            case .elevenLabs: return "ElevenLabs"
            }
        }

        var icon: String {
            switch self {
            case .openai: return "brain.head.profile"
            case .anthropic: return "sparkles"
            case .gemini: return "diamond"
            case .groq: return "bolt"
            case .minimax: return "rectangle.3.group.bubble.left"
            case .elevenLabs: return "speaker.wave.3"
            }
        }

        var helpURL: URL? {
            switch self {
            case .openai: return URL(string: "https://platform.openai.com/api-keys")
            case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
            case .gemini: return URL(string: "https://aistudio.google.com/apikey")
            case .groq: return URL(string: "https://console.groq.com/keys")
            case .minimax: return URL(string: "https://platform.minimax.io/")
            case .elevenLabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
            }
        }

        var placeholder: String {
            switch self {
            case .openai: return "sk-..."
            case .anthropic: return "sk-ant-..."
            case .gemini: return "AI..."
            case .groq: return "gsk_..."
            case .minimax: return "MiniMax API key"
            case .elevenLabs: return "sk_..."
            }
        }

        var slot: ProviderSlot {
            ProviderSlot(
                id: rawValue,
                displayName: displayName,
                icon: icon,
                placeholder: placeholder,
                helpURL: helpURL
            )
        }
    }

    struct ProviderSlot: Identifiable, Hashable {
        let id: String
        let displayName: String
        let icon: String
        let placeholder: String
        let helpURL: URL?
    }

    // MARK: - Storage

    private var cache: [String: String] = [:]
    private let fileURL: URL
    private let encryptionKey: SymmetricKey

    private init() {
        // Store in Application Support
        let appSupport = URL.applicationSupportDirectory
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)

        self.fileURL = talkieDir.appendingPathComponent(".apikeys")

        // Derive encryption key from machine + app
        self.encryptionKey = Self.deriveKey()

        // Load existing keys
        load()

        // Sync all existing keys to shared settings for TalkieAgent
        syncAllToSharedSettings()
    }

    /// Sync all cached keys to TalkieSharedSettings
    private func syncAllToSharedSettings() {
        for (providerId, value) in cache where !value.isEmpty {
            if let key = sharedSettingsKey(forProviderId: providerId) {
                TalkieSharedSettings.set(value, forKey: key)
            }
        }
        logger.debug("Synced \(self.cache.count) API keys to shared settings")
    }

    // MARK: - Public API

    /// Get API key for a provider
    func get(_ provider: Provider) -> String? {
        get(providerId: provider.rawValue)
    }

    func get(providerId: String) -> String? {
        cache[Self.normalizeProviderId(providerId)]
    }

    /// Set API key for a provider (empty string or nil removes it)
    func set(_ value: String?, for provider: Provider) {
        set(value, forProviderId: provider.rawValue)
    }

    func set(_ value: String?, forProviderId providerId: String) {
        let normalizedProviderId = Self.normalizeProviderId(providerId)
        if let value = value, !value.isEmpty {
            cache[normalizedProviderId] = value
        } else {
            cache.removeValue(forKey: normalizedProviderId)
        }
        save()
        syncToSharedSettings(providerId: normalizedProviderId, value: value)
    }

    private func syncToSharedSettings(providerId: String, value: String?) {
        let normalizedProviderId = Self.normalizeProviderId(providerId)
        guard let key = sharedSettingsKey(forProviderId: normalizedProviderId) else { return }

        if let value = value, !value.isEmpty {
            TalkieSharedSettings.set(value, forKey: key)
            logger.debug("Synced \(normalizedProviderId) API key to shared settings")
        } else {
            TalkieSharedSettings.removeObject(forKey: key)
            logger.debug("Removed \(normalizedProviderId) API key from shared settings")
        }
    }

    private func sharedSettingsKey(forProviderId providerId: String) -> String? {
        switch Self.normalizeProviderId(providerId) {
        case Provider.openai.rawValue:
            return AgentSettingsKey.openaiApiKey
        case Provider.anthropic.rawValue:
            return AgentSettingsKey.anthropicApiKey
        case Provider.gemini.rawValue:
            return AgentSettingsKey.geminiApiKey
        case Provider.groq.rawValue:
            return AgentSettingsKey.groqApiKey
        case Provider.minimax.rawValue:
            return AgentSettingsKey.minimaxApiKey
        case Provider.elevenLabs.rawValue:
            return AgentSettingsKey.elevenLabsApiKey
        case let providerId where !providerId.isEmpty:
            return "\(providerId)_api_key"
        default:
            return nil
        }
    }

    /// Check if a provider has a key configured
    func hasKey(for provider: Provider) -> Bool {
        hasKey(forProviderId: provider.rawValue)
    }

    func hasKey(forProviderId providerId: String) -> Bool {
        guard let key = cache[Self.normalizeProviderId(providerId)] else { return false }
        return !key.isEmpty
    }

    /// Get all configured providers
    var configuredProviders: [Provider] {
        Provider.allCases.filter { hasKey(for: $0) }
    }

    var configuredProviderIDs: [String] {
        cache.keys
            .map(Self.normalizeProviderId)
            .filter { !$0.isEmpty && hasKey(forProviderId: $0) }
            .sorted()
    }

    func providerSlots(includePresets: Bool = true, additionalProviderIDs: [String] = []) -> [ProviderSlot] {
        var seen = Set<String>()
        var slots: [ProviderSlot] = []

        func appendSlot(for providerId: String) {
            let normalizedProviderId = Self.normalizeProviderId(providerId)
            guard !normalizedProviderId.isEmpty, seen.insert(normalizedProviderId).inserted else { return }
            slots.append(Self.providerSlot(forProviderId: normalizedProviderId))
        }

        if includePresets {
            Provider.allCases.forEach { appendSlot(for: $0.rawValue) }
        }

        configuredProviderIDs.forEach(appendSlot)
        additionalProviderIDs.forEach(appendSlot)
        return slots
    }

    static func providerSlot(forProviderId providerId: String) -> ProviderSlot {
        let normalizedProviderId = normalizeProviderId(providerId)
        if let provider = Provider(rawValue: normalizedProviderId) {
            return provider.slot
        }

        return ProviderSlot(
            id: normalizedProviderId,
            displayName: normalizedProviderId
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " "),
            icon: "key",
            placeholder: "API key",
            helpURL: nil
        )
    }

    static func normalizeProviderId(_ providerId: String) -> String {
        let trimmed = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = String(trimmed.map { character in
            character.isLetter || character.isNumber ? character : "_"
        })
            .split(separator: "_")
            .joined(separator: "_")

        switch normalized {
        case "google", "google_gemini":
            return Provider.gemini.rawValue
        case "eleven_labs", "eleven_labs_io":
            return Provider.elevenLabs.rawValue
        case "mini_max":
            return Provider.minimax.rawValue
        default:
            return normalized
        }
    }

    /// Delete all stored keys
    func deleteAll() {
        for providerId in cache.keys {
            syncToSharedSettings(providerId: providerId, value: nil)
        }
        cache.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        logger.info("All API keys deleted")
    }

    // MARK: - Migration from Keychain

    /// Migrate keys from KeychainManager to this store
    func migrateFromKeychain() {
        let keychain = KeychainManager.shared

        var migrated = 0

        // Migrate each key if not already in new store
        if !hasKey(for: .openai), let key = keychain.retrieve(for: .openaiApiKey), !key.isEmpty {
            set(key, for: .openai)
            keychain.delete(.openaiApiKey)
            migrated += 1
        }

        if !hasKey(for: .anthropic), let key = keychain.retrieve(for: .anthropicApiKey), !key.isEmpty {
            set(key, for: .anthropic)
            keychain.delete(.anthropicApiKey)
            migrated += 1
        }

        if !hasKey(for: .gemini), let key = keychain.retrieve(for: .geminiApiKey), !key.isEmpty {
            set(key, for: .gemini)
            keychain.delete(.geminiApiKey)
            migrated += 1
        }

        if !hasKey(for: .groq), let key = keychain.retrieve(for: .groqApiKey), !key.isEmpty {
            set(key, for: .groq)
            keychain.delete(.groqApiKey)
            migrated += 1
        }

        if migrated > 0 {
            logger.info("Migrated \(migrated) API keys from Keychain")
        }
    }

    // MARK: - Encryption

    private static func deriveKey() -> SymmetricKey {
        // Derive key from machine UUID + bundle ID
        // This isn't Fort Knox security, but it's good enough for API keys
        var seed = "to.talkie.app.apikeys"

        // Add hardware UUID if available
        if let uuid = getHardwareUUID() {
            seed += ".\(uuid)"
        }

        // Hash to get consistent 256-bit key
        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }

    private static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        return uuid
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug("No existing API keys file")
            return
        }

        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

            if let decoded = try? JSONDecoder().decode([String: String].self, from: decryptedData) {
                cache = decoded
                logger.debug("Loaded \(decoded.count) API keys")
            }
        } catch {
            logger.error("Failed to load API keys: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(cache)
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)

            guard let combined = sealedBox.combined else {
                logger.error("Failed to get combined sealed box")
                return
            }

            try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
            logger.debug("Saved \(self.cache.count) API keys")
        } catch {
            logger.error("Failed to save API keys: \(error.localizedDescription)")
        }
    }
}
