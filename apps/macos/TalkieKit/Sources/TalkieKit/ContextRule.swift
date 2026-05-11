//
//  ContextRule.swift
//  TalkieKit
//
//  Context rules: app-aware post-transcription prompting
//  Matches dictation target app → applies LLM refinement or routes to interstitial
//

import Foundation

// MARK: - Data Model

public struct ContextRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String              // "Slack - Casual"
    public var appBundleIDs: [String]    // ["com.tinyspeck.slackmacgap", "com.apple.mail"]
    public var isEnabled: Bool
    public var behavior: ContextRuleBehavior
    public var prompt: String            // LLM instruction
    public var llmProviderId: String?    // nil = use global default
    public var llmModelId: String?       // nil = use global default
    public var selectionRoutine: SelectionRoutine?  // nil = no selection handling for this context
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        appBundleIDs: [String] = [],
        isEnabled: Bool = true,
        behavior: ContextRuleBehavior = .autoRefine,
        prompt: String,
        llmProviderId: String? = nil,
        llmModelId: String? = nil,
        selectionRoutine: SelectionRoutine? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.appBundleIDs = appBundleIDs
        self.isEnabled = isEnabled
        self.behavior = behavior
        self.prompt = prompt
        self.llmProviderId = llmProviderId
        self.llmModelId = llmModelId
        self.selectionRoutine = selectionRoutine
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Backward-Compatible Codable

extension ContextRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, appBundleIDs, appBundleID, appName
        case isEnabled, behavior, prompt
        case llmProviderId, llmModelId
        case selectionRoutine
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Try new format first, fall back to wrapping old single-app field
        if let ids = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) {
            appBundleIDs = ids
        } else if let singleID = try container.decodeIfPresent(String.self, forKey: .appBundleID),
                  !singleID.isEmpty {
            appBundleIDs = [singleID]
        } else {
            appBundleIDs = []
        }

        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        behavior = try container.decode(ContextRuleBehavior.self, forKey: .behavior)
        prompt = try container.decode(String.self, forKey: .prompt)
        llmProviderId = try container.decodeIfPresent(String.self, forKey: .llmProviderId)
        llmModelId = try container.decodeIfPresent(String.self, forKey: .llmModelId)
        selectionRoutine = try container.decodeIfPresent(SelectionRoutine.self, forKey: .selectionRoutine)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(appBundleIDs, forKey: .appBundleIDs)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(llmProviderId, forKey: .llmProviderId)
        try container.encodeIfPresent(llmModelId, forKey: .llmModelId)
        try container.encodeIfPresent(selectionRoutine, forKey: .selectionRoutine)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Convenience Helpers (macOS)

#if os(macOS)
import AppKit

extension ContextRule {
    /// Resolves display names from bundle IDs via NSWorkspace
    public var resolvedAppNames: [String] {
        appBundleIDs.compactMap { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return bundleID
            }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return name.isEmpty ? bundleID : name
        }
    }

    /// Summary for list display: "Slack" / "Slack, Mail" / "Slack +2"
    public var appSummary: String {
        let names = resolvedAppNames
        switch names.count {
        case 0: return "No app"
        case 1: return names[0]
        case 2: return "\(names[0]), \(names[1])"
        default: return "\(names[0]) +\(names.count - 1)"
        }
    }
}
#endif

public enum ContextRuleBehavior: String, Codable, CaseIterable, Sendable {
    case autoRefine          // Wait for LLM, paste refined text
    case autoInterstitial    // Route to interstitial with prompt pre-applied
    case protocolProcessor   // Run procedural processor (deterministic, no LLM)
}

// MARK: - Selection Routine

/// Frozen workflow for how selections are handled in a given context.
/// Same primitive as a Workflow, but rendered inline as a settings card.
public struct SelectionRoutine: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var processMode: SelectionMode       // verbatim / summary / explanation
    public var prompt: String?                   // custom LLM prompt (nil = use default for mode)
    public var delivery: SelectionDelivery       // speak / paste / clipboard
    public var voiceOverride: String?            // TTS voice ID (nil = use default)
    public var thenWorkflowId: UUID?             // optional workflow to chain after delivery

    public init(
        enabled: Bool = false,
        processMode: SelectionMode = .auto,
        prompt: String? = nil,
        delivery: SelectionDelivery = .speak,
        voiceOverride: String? = nil,
        thenWorkflowId: UUID? = nil
    ) {
        self.enabled = enabled
        self.processMode = processMode
        self.prompt = prompt
        self.delivery = delivery
        self.voiceOverride = voiceOverride
        self.thenWorkflowId = thenWorkflowId
    }

    public static let `default` = SelectionRoutine()
}

/// How a selection routine delivers its output
public enum SelectionDelivery: String, Codable, CaseIterable, Sendable, Identifiable {
    case speak      // TTS readback
    case paste      // Paste into active app
    case clipboard  // Copy to clipboard silently
    case save       // Save as TalkieObject

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .speak: return "Speak"
        case .paste: return "Paste"
        case .clipboard: return "Clipboard"
        case .save: return "Save"
        }
    }

    public var icon: String {
        switch self {
        case .speak: return "speaker.wave.2"
        case .paste: return "doc.on.clipboard"
        case .clipboard: return "clipboard"
        case .save: return "square.and.arrow.down"
        }
    }
}

// MARK: - Preset Prompts

public enum ContextRulePreset: CaseIterable, Sendable {
    case casual
    case professional
    case technical
    case cleanup
    case bashDictation

    public var name: String {
        switch self {
        case .casual: return "Casual (Slack)"
        case .professional: return "Professional (Email)"
        case .technical: return "Technical (Terminal)"
        case .cleanup: return "Light cleanup"
        case .bashDictation: return "Bash Dictation (Terminal)"
        }
    }

    public var prompt: String {
        switch self {
        case .casual:
            return "Make this casual and concise. Use a friendly, conversational tone. Remove filler words. Keep it brief."
        case .professional:
            return "Make this professional and polished. Use a clear, business-appropriate tone. Fix grammar and structure."
        case .technical:
            return "Make this technically precise. Use exact terminology. Remove ambiguity. Keep it terse and direct."
        case .cleanup:
            return "Fix grammar, remove filler words (um, uh, like), and clean up punctuation. Preserve the original meaning and tone."
        case .bashDictation:
            return "Procedural processor: converts protocol words (dash, dot, space, etc.) to bash syntax. No LLM needed."
        }
    }

    public var behavior: ContextRuleBehavior {
        switch self {
        case .bashDictation: return .protocolProcessor
        default: return .autoRefine
        }
    }
}

// MARK: - Refinement Info (for history display)

public struct RefinementInfo: Codable, Hashable, Sendable {
    public var rawText: String?
    public var prompt: String?
    public var ruleName: String?
    public var model: String?

    public init(rawText: String? = nil, prompt: String? = nil, ruleName: String? = nil, model: String? = nil) {
        self.rawText = rawText
        self.prompt = prompt
        self.ruleName = ruleName
        self.model = model
    }
}

// MARK: - Context Rule Store

private struct ContextRulesConfiguration: Codable {
    var version: Int
    var isEnabled: Bool
    var rules: [ContextRule]

    init(version: Int = 1, isEnabled: Bool = false, rules: [ContextRule] = []) {
        self.version = version
        self.isEnabled = isEnabled
        self.rules = rules
    }
}

public final class ContextRuleStore: @unchecked Sendable {
    public static let shared = ContextRuleStore()

    private let storage: UserDefaults
    private let rulesKey: String
    private let enabledKey: String
    private let lock = NSLock()
    private let fileURL: URL
    private var configuration: ContextRulesConfiguration

    private init() {
        self.storage = TalkieSharedSettings
        self.rulesKey = AgentSettingsKey.contextRules
        self.enabledKey = AgentSettingsKey.contextRulesEnabled

        let directory = TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("context", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("rules.json")

        if let loaded = Self.loadConfiguration(from: fileURL) {
            self.configuration = loaded
            mirrorToSharedSettings(configuration: loaded)
        } else {
            let legacyRules: [ContextRule]
            if let data = storage.data(forKey: rulesKey),
               let decoded = try? JSONDecoder().decode([ContextRule].self, from: data) {
                legacyRules = decoded
            } else {
                legacyRules = []
            }

            let legacyEnabled = storage.object(forKey: enabledKey) as? Bool ?? false
            self.configuration = ContextRulesConfiguration(isEnabled: legacyEnabled, rules: legacyRules)
            saveLocked()
            mirrorToSharedSettings(configuration: configuration)
        }
    }

    // MARK: - Master Toggle

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return configuration.isEnabled
        }
        set {
            lock.lock()
            configuration.isEnabled = newValue
            saveLocked()
            lock.unlock()
        }
    }

    // MARK: - CRUD

    public var rules: [ContextRule] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return configuration.rules
        }
        set {
            lock.lock()
            configuration.rules = newValue
            saveLocked()
            lock.unlock()
        }
    }

    public func add(_ rule: ContextRule) {
        var current = rules
        current.append(rule)
        rules = current
    }

    public func update(_ rule: ContextRule) {
        var current = rules
        if let idx = current.firstIndex(where: { $0.id == rule.id }) {
            var updated = rule
            updated.updatedAt = Date()
            current[idx] = updated
            rules = current
        }
    }

    public func delete(id: UUID) {
        var current = rules
        current.removeAll { $0.id == id }
        rules = current
    }

    // MARK: - Matching

    /// Find the first enabled rule matching the given bundle ID
    public func matchingRule(for bundleID: String?) -> ContextRule? {
        guard isEnabled, let bundleID else { return nil }
        return rules.first { $0.isEnabled && $0.appBundleIDs.contains(bundleID) }
    }

    public var displayPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return fileURL.path.replacingOccurrences(of: homePath, with: "~")
    }

    public func reloadFromDisk() {
        guard let loaded = Self.loadConfiguration(from: fileURL) else { return }
        lock.lock()
        configuration = loaded
        mirrorToSharedSettings(configuration: loaded)
        lock.unlock()
    }

    private func saveLocked() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
            mirrorToSharedSettings(configuration: configuration)
        } catch {
            #if DEBUG
            print("Failed to save context rules config: \(error)")
            #endif
        }
    }

    private func mirrorToSharedSettings(configuration: ContextRulesConfiguration) {
        storage.set(configuration.isEnabled, forKey: enabledKey)
        if let data = try? JSONEncoder().encode(configuration.rules) {
            storage.set(data, forKey: rulesKey)
        }
    }

    private static func loadConfiguration(from fileURL: URL) -> ContextRulesConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ContextRulesConfiguration.self, from: data)
    }
}
