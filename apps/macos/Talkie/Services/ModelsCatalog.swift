//
//  ModelsCatalog.swift
//  Talkie
//
//  Central catalog of all model definitions and metadata
//

import AVFoundation
import Foundation
import SwiftUI

// MARK: - Whisper STT Models Metadata

struct WhisperModelMetadata {
    let model: WhisperModel
    let displayName: String
    let sizeMB: Int
    let accuracy: Int          // Word error rate improvement %
    let rtf: Double            // Real-time factor
    let description: String
}

enum WhisperModelCatalog {
    static let repoURL = URL(string: "https://github.com/argmaxinc/WhisperKit")!
    static let paperURL = URL(string: "https://arxiv.org/abs/2212.04356")!

    static let metadata: [WhisperModelMetadata] = [
        WhisperModelMetadata(
            model: .tiny,
            displayName: "Tiny",
            sizeMB: 39,
            accuracy: 72,
            rtf: 0.07,
            description: "Fastest, basic quality"
        ),
        WhisperModelMetadata(
            model: .base,
            displayName: "Base",
            sizeMB: 74,
            accuracy: 81,
            rtf: 0.10,
            description: "Fast, good quality"
        ),
        WhisperModelMetadata(
            model: .small,
            displayName: "Small",
            sizeMB: 244,
            accuracy: 88,
            rtf: 0.17,
            description: "Balanced speed/quality"
        ),
        WhisperModelMetadata(
            model: .distilLargeV3,
            displayName: "Large",
            sizeMB: 756,
            accuracy: 95,
            rtf: 0.33,
            description: "Best quality, slower"
        )
    ]

    static func metadata(for model: WhisperModel) -> WhisperModelMetadata? {
        metadata.first { $0.model == model }
    }
}

// MARK: - Parakeet STT Models Metadata

struct ParakeetModelMetadata {
    let model: ParakeetModel
    let displayName: String
    let languages: Int
    let languagesBadge: String // "EN" or "ML" (multilingual)
    let sizeMB: Int
    let rtf: Double
    let description: String
}

enum ParakeetModelCatalog {
    static let repoURL = URL(string: "https://github.com/FluidInference/FluidAudio")!
    static let paperURL = URL(string: "https://arxiv.org/abs/2409.17143")!

    static let metadata: [ParakeetModelMetadata] = [
        ParakeetModelMetadata(
            model: .v2,
            displayName: "V2",
            languages: 1,
            languagesBadge: "EN",
            sizeMB: 600,
            rtf: 0.05,
            description: "English only, highest accuracy"
        ),
        ParakeetModelMetadata(
            model: .v3,
            displayName: "V3",
            languages: 25,
            languagesBadge: "25L",
            sizeMB: 600,
            rtf: 0.05,
            description: "25 languages, fast"
        )
    ]

    static func metadata(for model: ParakeetModel) -> ParakeetModelMetadata? {
        metadata.first { $0.model == model }
    }
}

// MARK: - TTS Voice Catalog

enum TTSVoiceProvider: String, CaseIterable {
    case apple = "apple"
    case elevenLabs = "elevenlabs"
    case openAI = "openai"

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .elevenLabs: return "ElevenLabs"
        case .openAI: return "OpenAI"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .apple: return .blue
        case .elevenLabs: return .orange
        case .openAI: return .green
        }
    }

    var badge: String {
        switch self {
        case .apple: return "APL"
        case .elevenLabs: return "11L"
        case .openAI: return "OAI"
        }
    }
}

enum TTSVoiceAccessTier: String {
    case included
    case premium

    var badgeText: String {
        switch self {
        case .included: return "FREE"
        case .premium: return "PRO"
        }
    }

    var displayName: String {
        switch self {
        case .included: return "Free Plan"
        case .premium: return "Premium"
        }
    }
}

struct TTSVoiceMetadata {
    let id: String              // Full ID like "openai:alloy"
    let provider: TTSVoiceProvider
    let voiceId: String         // Short ID like "af_bella"
    let displayName: String
    let description: String
    let language: String
    let localeIdentifier: String?
    let gender: String          // "Female", "Male", "Neutral"
    let style: String           // "Conversational", "Narrative", "Expressive"
    let sizeMB: Int
    let sampleRate: Int         // Hz
    let isDefault: Bool
    var secondaryBadgeText: String? = nil
    var accessTier: TTSVoiceAccessTier = .included

    var infoURL: URL? { nil }
}

enum TTSVoiceCatalog {
    static let voices: [TTSVoiceMetadata] = [
        TTSVoiceMetadata(
            id: "elevenlabs:21m00Tcm4TlvDq8ikWAM",
            provider: TTSVoiceProvider.elevenLabs,
            voiceId: "21m00Tcm4TlvDq8ikWAM",
            displayName: "Rachel",
            description: "Clean, versatile ElevenLabs narrator",
            language: "en-US",
            localeIdentifier: "en-US",
            gender: "Female",
            style: "Narrative",
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false
        ),
        TTSVoiceMetadata(
            id: "elevenlabs:EXAVITQu4vr4xnSDxMaL",
            provider: TTSVoiceProvider.elevenLabs,
            voiceId: "EXAVITQu4vr4xnSDxMaL",
            displayName: "Sarah",
            description: "Warm ElevenLabs conversational voice",
            language: "en-US",
            localeIdentifier: "en-US",
            gender: "Female",
            style: "Conversational",
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false
        ),
        TTSVoiceMetadata(
            id: "elevenlabs:AZnzlk1XvdvUeBnXmlld",
            provider: TTSVoiceProvider.elevenLabs,
            voiceId: "AZnzlk1XvdvUeBnXmlld",
            displayName: "Domi",
            description: "Bold ElevenLabs performance voice",
            language: "en-US",
            localeIdentifier: "en-US",
            gender: "Female",
            style: "Expressive",
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false
        ),
        TTSVoiceMetadata(
            id: "elevenlabs:MF3mGyEYCl7XYWbV9V6O",
            provider: TTSVoiceProvider.elevenLabs,
            voiceId: "MF3mGyEYCl7XYWbV9V6O",
            displayName: "Elli",
            description: "Bright ElevenLabs read-aloud voice",
            language: "en-US",
            localeIdentifier: "en-US",
            gender: "Female",
            style: "Clear",
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false
        ),
        TTSVoiceMetadata(
            id: "elevenlabs:j9jfwdrw7BRfcR43Qohk",
            provider: TTSVoiceProvider.elevenLabs,
            voiceId: "j9jfwdrw7BRfcR43Qohk",
            displayName: "Frederick Surrey",
            description: "Voice Library pick for premium narration",
            language: "en-US",
            localeIdentifier: "en-US",
            gender: "Male",
            style: "Refined",
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false,
            accessTier: .premium
        )
    ]

    static var defaultSettingsVoiceId: String {
        OpenAITTSVoiceCatalog.defaultVoice.id
    }

    static var openAIVoices: [TTSVoiceMetadata] {
        voices(for: .openAI)
    }

    static var elevenLabsVoices: [TTSVoiceMetadata] {
        voices(for: .elevenLabs)
    }

    static var elevenLabsFreeVoices: [TTSVoiceMetadata] {
        elevenLabsVoices.filter { $0.accessTier == .included }
    }

    static var elevenLabsPremiumVoices: [TTSVoiceMetadata] {
        elevenLabsVoices.filter { $0.accessTier == .premium }
    }

    static func recommendedSettingsVoiceId(hasOpenAIKey: Bool) -> String {
        if hasOpenAIKey {
            return defaultSettingsVoiceId
        }

        return englishStarterSystemVoices(limit: 1).first?.id
            ?? systemVoices().first?.id
            ?? defaultSettingsVoiceId
    }

    static func voice(byId id: String) -> TTSVoiceMetadata? {
        voices.first { $0.id == id }
            ?? openAIVoices.first { $0.id == id }
            ?? systemVoices().first { $0.id == id }
    }

    static func voices(for provider: TTSVoiceProvider) -> [TTSVoiceMetadata] {
        switch provider {
        case .apple:
            return systemVoices()
        case .elevenLabs:
            return voices.filter { $0.provider == .elevenLabs }
        case .openAI:
            return OpenAITTSVoiceCatalog.voices.map {
                TTSVoiceMetadata(
                    id: $0.id, provider: .openAI, voiceId: $0.voiceId,
                    displayName: $0.displayName, description: $0.style,
                    language: "en-US", localeIdentifier: "en-US",
                    gender: $0.gender, style: $0.style,
                    sizeMB: 0, sampleRate: 0, isDefault: false
                )
            }
        }
    }

    static func systemVoices() -> [TTSVoiceMetadata] {
        AVSpeechSynthesisVoice.speechVoices()
            .map(makeSystemVoiceMetadata)
            .sorted(by: systemVoiceSort)
    }

    static func systemVoiceOptions() -> [(id: String, name: String)] {
        let installedVoices = systemVoices()
        guard !installedVoices.isEmpty else {
            return [
                ("com.apple.voice.compact.en-US.Samantha", "Samantha (Standard, English - United States)"),
                ("com.apple.voice.enhanced.en-US.Samantha", "Samantha (Enhanced, English - United States)"),
                ("com.apple.voice.compact.en-US.Alex", "Alex (Standard, English - United States)"),
                ("com.apple.voice.enhanced.en-US.Alex", "Alex (Enhanced, English - United States)")
            ]
        }

        return installedVoices.map { voice in
            (voice.voiceId, "\(voice.displayName) (\(voice.style), \(voice.language))")
        }
    }

    static func englishStarterSystemVoices(limit: Int = 8) -> [TTSVoiceMetadata] {
        let preferredNames = [
            "Samantha", "Alex", "Ava", "Allison",
            "Tom", "Daniel", "Serena", "Karen",
            "Moira", "Tessa", "Martha", "Arthur"
        ]

        let installed = systemVoices().filter { voice in
            guard let localeIdentifier = voice.localeIdentifier?.lowercased() else { return false }
            return localeIdentifier.hasPrefix("en")
        }

        var selected: [TTSVoiceMetadata] = []
        for preferredName in preferredNames {
            guard let match = installed.first(where: { canonicalVoiceName(for: $0.displayName) == preferredName }) else { continue }
            if !selected.contains(where: { $0.id == match.id }) {
                selected.append(match)
            }
            if selected.count >= limit { return selected }
        }

        for voice in installed {
            if selected.count >= limit { break }
            guard !selected.contains(where: { $0.id == voice.id }) else { continue }
            selected.append(voice)
        }

        return selected
    }

    private static func canonicalVoiceName(for displayName: String) -> String {
        displayName
            .replacingOccurrences(of: " (Premium)", with: "")
            .replacingOccurrences(of: " (Enhanced)", with: "")
            .replacingOccurrences(of: " (Default)", with: "")
    }

    private static func makeSystemVoiceMetadata(from voice: AVSpeechSynthesisVoice) -> TTSVoiceMetadata {
        let quality = qualityLabel(for: voice.quality)

        return TTSVoiceMetadata(
            id: voice.identifier,
            provider: .apple,
            voiceId: voice.identifier,
            displayName: voice.name,
            description: "\(quality) Apple system voice",
            language: localizedLanguageLabel(for: voice.language),
            localeIdentifier: voice.language,
            gender: "System",
            style: quality,
            sizeMB: 0,
            sampleRate: 0,
            isDefault: false,
            secondaryBadgeText: qualityBadge(for: voice.quality)
        )
    }

    private static func localizedLanguageLabel(for identifier: String) -> String {
        let normalizedIdentifier = identifier.replacing("-", with: "_")
        return Locale.current.localizedString(forIdentifier: normalizedIdentifier) ?? identifier
    }

    private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            return "Standard"
        case .enhanced:
            return "Enhanced"
        #if swift(>=5.9)
        case .premium:
            return "Premium"
        #endif
        @unknown default:
            return "Standard"
        }
    }

    private static func qualityBadge(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            return "STD"
        case .enhanced:
            return "ENH"
        #if swift(>=5.9)
        case .premium:
            return "PRO"
        #endif
        @unknown default:
            return "STD"
        }
    }

    private static func qualityRank(for quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .default:
            return 0
        case .enhanced:
            return 1
        #if swift(>=5.9)
        case .premium:
            return 2
        #endif
        @unknown default:
            return 0
        }
    }

    private static func systemVoiceSort(_ lhs: TTSVoiceMetadata, _ rhs: TTSVoiceMetadata) -> Bool {
        let lhsQuality = qualityRank(for: AVSpeechSynthesisVoice(identifier: lhs.voiceId)?.quality ?? .default)
        let rhsQuality = qualityRank(for: AVSpeechSynthesisVoice(identifier: rhs.voiceId)?.quality ?? .default)
        if lhsQuality != rhsQuality {
            return lhsQuality > rhsQuality
        }

        if lhs.language != rhs.language {
            return lhs.language.localizedStandardCompare(rhs.language) == .orderedAscending
        }

        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

// MARK: - OpenAI TTS Voice Catalog

enum OpenAITTSVoiceCatalog {
    struct Voice: Identifiable {
        let id: String          // "openai:<voice_name>"
        let voiceId: String     // API voice name: "alloy", "echo", etc.
        let displayName: String
        let style: String
        let gender: String
    }

    static let voices: [Voice] = [
        Voice(id: "openai:alloy", voiceId: "alloy", displayName: "Alloy", style: "Neutral", gender: "Neutral"),
        Voice(id: "openai:ash", voiceId: "ash", displayName: "Ash", style: "Conversational", gender: "Male"),
        Voice(id: "openai:ballad", voiceId: "ballad", displayName: "Ballad", style: "Warm", gender: "Male"),
        Voice(id: "openai:coral", voiceId: "coral", displayName: "Coral", style: "Conversational", gender: "Female"),
        Voice(id: "openai:echo", voiceId: "echo", displayName: "Echo", style: "Clear", gender: "Male"),
        Voice(id: "openai:fable", voiceId: "fable", displayName: "Fable", style: "Narrative", gender: "Male"),
        Voice(id: "openai:nova", voiceId: "nova", displayName: "Nova", style: "Bright", gender: "Female"),
        Voice(id: "openai:onyx", voiceId: "onyx", displayName: "Onyx", style: "Deep", gender: "Male"),
        Voice(id: "openai:sage", voiceId: "sage", displayName: "Sage", style: "Composed", gender: "Female"),
        Voice(id: "openai:shimmer", voiceId: "shimmer", displayName: "Shimmer", style: "Expressive", gender: "Female"),
    ]

    static var defaultVoice: Voice {
        voices.first { $0.voiceId == "alloy" } ?? voices[0]
    }

    static func voice(byId id: String) -> Voice? {
        voices.first { $0.id == id }
    }
}

// MARK: - Cloud Provider Metadata (UI enrichment for LLMConfig)
// Note: Cloud model definitions live in LLMConfig.json - this provides UI-only metadata

enum CloudProviderMetadata {
    struct Info {
        let tagline: String
        let docsURL: URL?
        let pricingURL: URL?
    }

    static let providers: [String: Info] = [
        "openai": Info(
            tagline: "Industry standard for reasoning and vision",
            docsURL: URL(string: "https://platform.openai.com/docs"),
            pricingURL: URL(string: "https://openai.com/pricing")
        ),
        "anthropic": Info(
            tagline: "Extended thinking and nuanced understanding",
            docsURL: URL(string: "https://docs.anthropic.com"),
            pricingURL: URL(string: "https://anthropic.com/pricing")
        ),
        "gemini": Info(
            tagline: "Multimodal powerhouse with massive context",
            docsURL: URL(string: "https://ai.google.dev/docs"),
            pricingURL: URL(string: "https://ai.google.dev/pricing")
        ),
        "groq": Info(
            tagline: "Ultra-fast inference at scale",
            docsURL: URL(string: "https://console.groq.com/docs"),
            pricingURL: URL(string: "https://groq.com/pricing")
        )
    ]

    static func info(for providerId: String) -> Info? {
        providers[providerId]
    }
}
