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
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "APIKeyStore")

/// Encrypted storage for API keys - simpler than Keychain, no prompts
final class APIKeyStore {
    static let shared = APIKeyStore()

    // Provider keys
    enum Provider: String, CaseIterable, Codable {
        case openai
        case anthropic
        case gemini
        case groq
        case elevenLabs = "elevenlabs"

        var displayName: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .gemini: return "Google Gemini"
            case .groq: return "Groq"
            case .elevenLabs: return "ElevenLabs"
            }
        }

        var icon: String {
            switch self {
            case .openai: return "brain.head.profile"
            case .anthropic: return "sparkles"
            case .gemini: return "diamond"
            case .groq: return "bolt"
            case .elevenLabs: return "speaker.wave.3"
            }
        }

        var helpURL: URL? {
            switch self {
            case .openai: return URL(string: "https://platform.openai.com/api-keys")
            case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
            case .gemini: return URL(string: "https://aistudio.google.com/apikey")
            case .groq: return URL(string: "https://console.groq.com/keys")
            case .elevenLabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
            }
        }

        var placeholder: String {
            switch self {
            case .openai: return "sk-..."
            case .anthropic: return "sk-ant-..."
            case .gemini: return "AI..."
            case .groq: return "gsk_..."
            case .elevenLabs: return "sk_..."
            }
        }
    }

    // MARK: - Storage

    private var cache: [String: String] = [:]
    private let fileURL: URL
    private let encryptionKey: SymmetricKey

    private init() {
        // Store in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)

        self.fileURL = talkieDir.appendingPathComponent(".apikeys")

        // Derive encryption key from machine + app
        self.encryptionKey = Self.deriveKey()

        // Load existing keys
        load()
    }

    // MARK: - Public API

    /// Get API key for a provider
    func get(_ provider: Provider) -> String? {
        cache[provider.rawValue]
    }

    /// Set API key for a provider (empty string or nil removes it)
    func set(_ value: String?, for provider: Provider) {
        if let value = value, !value.isEmpty {
            cache[provider.rawValue] = value
        } else {
            cache.removeValue(forKey: provider.rawValue)
        }
        save()
    }

    /// Check if a provider has a key configured
    func hasKey(for provider: Provider) -> Bool {
        guard let key = cache[provider.rawValue] else { return false }
        return !key.isEmpty
    }

    /// Get all configured providers
    var configuredProviders: [Provider] {
        Provider.allCases.filter { hasKey(for: $0) }
    }

    /// Delete all stored keys
    func deleteAll() {
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
        var seed = "jdi.talkie.apikeys"

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
