//
//  VoiceMemo+Transcripts.swift
//  Talkie
//
//  Created by Claude Code on 2025-11-28.
//

import Foundation
import CoreData

// MARK: - Transcript Source Types

enum TranscriptSourceType: String {
    case systemIOS = "system_ios"
    case systemMacOS = "system_macos"
    case user = "user"

    var displayName: String {
        switch self {
        case .systemIOS: return "iOS"
        case .systemMacOS: return "macOS"
        case .user: return "Edited"
        }
    }
}

// MARK: - Transcript Engine Constants
// Free-form strings - add new engines without schema migration
struct TranscriptEngines {
    static let appleSpeech = "apple_speech"      // iOS SFSpeechRecognizer
    static let whisperKit = "whisper_kit"        // WhisperKit on-device
    static let mlxWhisper = "mlx_whisper"        // macOS MLX Whisper
    static let parakeet = "parakeet"             // NVIDIA Parakeet
    static let openaiWhisper = "openai_whisper"  // OpenAI Whisper API

    /// Human-readable name for an engine string
    static func displayName(for engine: String?) -> String {
        guard let engine = engine else { return "" }
        switch engine {
        case appleSpeech: return "Apple Speech"
        case whisperKit: return "WhisperKit"
        case mlxWhisper: return "MLX Whisper"
        case parakeet: return "Parakeet"
        case openaiWhisper: return "Whisper API"
        default: return engine // Show raw string for unknown engines
        }
    }
}

// MARK: - VoiceMemo Transcript Helpers

extension VoiceMemo {

    /// Get all transcript versions sorted by version number (newest first)
    var sortedTranscriptVersions: [TranscriptVersion] {
        guard let versions = transcriptVersions as? Set<TranscriptVersion> else {
            return []
        }
        return versions.sorted { $0.version > $1.version }
    }

    /// Get the latest (most recent) transcript version
    var latestTranscriptVersion: TranscriptVersion? {
        sortedTranscriptVersions.first
    }

    /// Get the current transcript content (latest version or legacy field)
    var currentTranscript: String? {
        // Prefer versioned transcripts, fall back to legacy field
        if let latest = latestTranscriptVersion {
            return latest.content
        }
        return transcription
    }

    /// Get the next version number
    var nextVersionNumber: Int32 {
        (latestTranscriptVersion?.version ?? 0) + 1
    }

    /// Add a new transcript version
    /// - Parameters:
    ///   - content: The transcript text
    ///   - sourceType: Where this transcript came from (iOS, macOS, user)
    ///   - engine: The transcription engine used (nil for user edits) - free-form string
    /// - Returns: The newly created TranscriptVersion
    @discardableResult
    func addTranscriptVersion(
        content: String,
        sourceType: TranscriptSourceType,
        engine: String? = nil
    ) -> TranscriptVersion? {
        guard let context = managedObjectContext else { return nil }

        let version = TranscriptVersion(context: context)
        version.id = UUID()
        version.content = content
        version.version = nextVersionNumber
        version.sourceType = sourceType.rawValue
        version.engine = engine
        version.createdAt = Date()
        version.memo = self

        // Also update the legacy transcription field for compatibility
        self.transcription = content

        return version
    }

    /// Add a system transcript (from iOS or macOS automatic transcription)
    @discardableResult
    func addSystemTranscript(
        content: String,
        fromMacOS: Bool = false,
        engine: String
    ) -> TranscriptVersion? {
        let sourceType: TranscriptSourceType = fromMacOS ? .systemMacOS : .systemIOS
        return addTranscriptVersion(content: content, sourceType: sourceType, engine: engine)
    }

    /// Add a user-edited transcript
    @discardableResult
    func addUserTranscript(content: String) -> TranscriptVersion? {
        return addTranscriptVersion(content: content, sourceType: .user, engine: nil)
    }

    /// Migrate existing legacy transcription to versioned format
    /// Call this once per memo to create an initial version from legacy data
    func migrateToVersionedTranscripts(engine: String = TranscriptEngines.appleSpeech) {
        // Only migrate if we have a legacy transcript and no versions yet
        guard let legacyTranscript = transcription,
              !legacyTranscript.isEmpty,
              sortedTranscriptVersions.isEmpty else {
            return
        }

        // Determine source type based on device origin
        let sourceType: TranscriptSourceType
        if let deviceId = originDeviceId, deviceId.hasPrefix("mac-") {
            sourceType = .systemMacOS
        } else {
            sourceType = .systemIOS
        }

        addTranscriptVersion(content: legacyTranscript, sourceType: sourceType, engine: engine)
    }
}

// MARK: - TranscriptVersion Helpers

extension TranscriptVersion {

    var sourceTypeEnum: TranscriptSourceType? {
        guard let type = sourceType else { return nil }
        return TranscriptSourceType(rawValue: type)
    }

    /// Human-readable name for the engine
    var engineDisplayName: String {
        TranscriptEngines.displayName(for: engine)
    }

    /// Human-readable description of the version source
    var sourceDescription: String {
        var parts: [String] = []

        if let source = sourceTypeEnum {
            parts.append(source.displayName)
        }

        let engineName = engineDisplayName
        if !engineName.isEmpty {
            parts.append(engineName)
        }

        return parts.isEmpty ? "Unknown" : parts.joined(separator: " · ")
    }

    /// Formatted date string
    var formattedDate: String {
        guard let date = createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
