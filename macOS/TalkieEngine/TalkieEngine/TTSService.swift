//
//  TTSService.swift
//  TalkieEngine
//
//  Text-to-Speech service using subprocess isolation.
//  TTS runs in TalkieEnginePod process - kill it to instantly reclaim ~800MB.
//

import Foundation
import TalkieKit

/// Text-to-Speech synthesis service (subprocess-based)
@MainActor
final class TTSService {
    static let shared = TTSService()

    // MARK: - State

    private var isPodSpawned = false
    private var isSpawning = false
    private var totalSyntheses = 0

    private init() {
        AppLogger.shared.info(.system, "TTSService initialized (subprocess mode)")
    }

    // MARK: - Voice ID Parsing

    private func parseVoiceId(_ fullId: String) -> (provider: String, voiceId: String) {
        let parts = fullId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return ("kokoro", fullId)
    }

    // MARK: - Synthesis

    /// Synthesize text to speech and return path to audio file
    func synthesize(text: String, voiceId: String) async throws -> URL {
        let (provider, voice) = parseVoiceId(voiceId)

        guard provider == "kokoro" else {
            throw TTSError.unsupportedProvider(provider)
        }

        // Ensure pod is spawned
        if !isPodSpawned {
            try await spawnPod()
        }

        AppLogger.shared.info(.system, "TTS synthesizing (pod)", detail: "\(text.prefix(50))...")
        EngineStatusManager.shared.log(.info, "TTS", "Synthesizing \(text.count) chars (subprocess)...")

        let startTime = Date()

        // Send request to pod
        var payload: [String: String] = ["text": text]
        if voice != "default" {
            payload["voice"] = voice
        }

        let response = try await PodManager.shared.request(
            capability: "tts",
            action: "synthesize",
            payload: payload
        )

        guard response.success, let result = response.result, let audioPath = result["audioPath"] else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.shared.error(.system, "TTS pod failed", detail: errorMsg)
            EngineStatusManager.shared.log(.error, "TTS", "Pod failed: \(errorMsg)")
            throw TTSError.synthesisFailed(NSError(domain: "TTSPod", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
        }

        let elapsed = Date().timeIntervalSince(startTime)
        totalSyntheses += 1

        let fileSizeKB = result["fileSizeKB"] ?? "?"
        AppLogger.shared.info(.system, "TTS complete (pod)", detail: "\(String(format: "%.1f", elapsed))s, \(fileSizeKB) KB")
        EngineStatusManager.shared.log(.info, "TTS", "Synthesized in \(String(format: "%.2f", elapsed))s (\(fileSizeKB) KB) [subprocess]")

        return URL(fileURLWithPath: audioPath)
    }

    // MARK: - Pod Management

    /// Preload the TTS model (spawns pod)
    func preloadModel(voiceId: String) async throws {
        let (provider, _) = parseVoiceId(voiceId)

        guard provider == "kokoro" else {
            throw TTSError.unsupportedProvider(provider)
        }

        try await spawnPod()
    }

    private func spawnPod() async throws {
        guard !isSpawning else {
            // Wait for current spawn to complete
            while isSpawning {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return
        }

        guard !isPodSpawned else { return }

        isSpawning = true
        defer { isSpawning = false }

        AppLogger.shared.info(.system, "Spawning TTS pod...")
        EngineStatusManager.shared.log(.info, "TTS", "Spawning subprocess...")

        let startTime = Date()

        do {
            _ = try await PodManager.shared.spawn(capability: "tts")
            isPodSpawned = true

            let elapsed = Date().timeIntervalSince(startTime)
            AppLogger.shared.info(.system, "TTS pod ready", detail: "\(String(format: "%.1f", elapsed))s")
            EngineStatusManager.shared.log(.info, "TTS", "Subprocess ready in \(String(format: "%.1f", elapsed))s")

        } catch {
            AppLogger.shared.error(.system, "Failed to spawn TTS pod", detail: error.localizedDescription)
            EngineStatusManager.shared.log(.error, "TTS", "Pod spawn failed: \(error.localizedDescription)")
            throw TTSError.modelLoadFailed(error)
        }
    }

    // MARK: - Available Voices

    func getAvailableVoices() -> [TTSVoiceInfo] {
        return [
            TTSVoiceInfo(
                id: "kokoro:default",
                provider: "kokoro",
                voiceId: "default",
                displayName: "Kokoro",
                description: "Fast local TTS (American English)",
                language: "en-US",
                isDownloaded: true,  // Model files are always available
                isLoaded: isPodSpawned
            )
        ]
    }

    // MARK: - Unload

    /// Unload the TTS model (kills pod, instantly reclaims ~800MB)
    func unloadModel() {
        guard isPodSpawned else { return }

        AppLogger.shared.info(.system, "Killing TTS pod to reclaim memory...")
        EngineStatusManager.shared.log(.info, "TTS", "Killing subprocess...")

        Task {
            await PodManager.shared.kill(capability: "tts")
        }

        isPodSpawned = false

        AppLogger.shared.info(.system, "TTS pod killed, ~800MB reclaimed")
        EngineStatusManager.shared.log(.info, "TTS", "Subprocess killed, memory reclaimed")
    }

    /// Check if TTS pod is running
    var isLoaded: Bool {
        isPodSpawned
    }

    // MARK: - Cleanup

    /// Clean up old TTS files (called periodically)
    func cleanupOldFiles(olderThan: TimeInterval = 3600) {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ttsDir = supportDir.appendingPathComponent("Talkie/TTS")

        let cutoff = Date().addingTimeInterval(-olderThan)

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: ttsDir,
                includingPropertiesForKeys: [.creationDateKey]
            )

            for file in files where file.pathExtension == "wav" {
                if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let created = attrs.creationDate,
                   created < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            AppLogger.shared.warning(.system, "TTS cleanup failed", detail: error.localizedDescription)
        }
    }
}

// MARK: - TTS Errors

enum TTSError: LocalizedError {
    case unsupportedProvider(String)
    case modelLoadFailed(Error)
    case synthesisFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported TTS provider: \(provider)"
        case .modelLoadFailed(let error):
            return "Failed to load TTS model: \(error.localizedDescription)"
        case .synthesisFailed(let error):
            return "TTS synthesis failed: \(error.localizedDescription)"
        }
    }
}
