//
//  TranscriptionRetryManager.swift
//  TalkieLive
//
//  Automatically retries failed transcriptions when Engine reconnects
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "RetryManager")

@MainActor
final class TranscriptionRetryManager: ObservableObject {
    static let shared = TranscriptionRetryManager()

    @Published private(set) var isRetrying = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastRetryAt: Date?

    private var cancellables = Set<AnyCancellable>()
    private var wasConnected = false

    private init() {
        // Observe engine connection state changes
        EngineClient.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)

        // Initial count
        refreshPendingCount()

        AppLogger.shared.log(.system, "RetryManager initialized", detail: "Pending retries: \(self.pendingCount)")
    }

    private func handleConnectionStateChange(_ state: EngineConnectionState) {
        // Consider both .connected and .connectedWrongBuild as connected for retry purposes
        let isNowConnected = (state == .connected || state == .connectedWrongBuild)

        let wasStr = wasConnected ? "connected" : "disconnected"
        let nowStr = isNowConnected ? "connected" : "disconnected"
        AppLogger.shared.log(.system, "Engine state changed", detail: "\(state.rawValue) (was: \(wasStr), now: \(nowStr))")

        // If we just reconnected, trigger retry
        if isNowConnected && !wasConnected {
            AppLogger.shared.log(.system, "Engine reconnected", detail: "Checking for failed transcriptions (pendingCount: \(self.pendingCount))")
            Task {
                await retryFailedTranscriptions()
            }
        }

        wasConnected = isNowConnected
    }

    func refreshPendingCount() {
        pendingCount = LiveDatabase.countNeedsRetry()
    }

    /// Retry all failed/pending transcriptions
    func retryFailedTranscriptions() async {
        guard !isRetrying else {
            AppLogger.shared.log(.system, "Retry already in progress", detail: "Skipping duplicate retry trigger", level: .notice)
            return
        }

        AppLogger.shared.log(.system, "Retry batch starting", detail: "isRetrying flag set to true")

        // Check engine connection first
        let client = EngineClient.shared
        let connectedStr = client.isConnected ? "YES" : "NO"
        logger.debug("[RetryManager] Engine connected: \(connectedStr), state: \(client.connectionState.rawValue)")

        if !client.isConnected {
            AppLogger.shared.log(.system, "Engine not connected", detail: "Attempting to connect before retry", level: .notice)
            let connected = await client.ensureConnected()
            if !connected {
                AppLogger.shared.log(.error, "Failed to connect to engine", detail: "Cannot retry transcriptions")
                return
            }
            AppLogger.shared.log(.system, "Engine connection established", detail: "Proceeding with retry")
        }

        let pending = LiveDatabase.fetchNeedsRetry()
        logger.info("[RetryManager] fetchNeedsRetry returned \(pending.count) records")

        guard !pending.isEmpty else {
            AppLogger.shared.log(.system, "No retries needed", detail: "fetchNeedsRetry returned 0 records")
            pendingCount = 0
            return
        }

        // Log details about what we're retrying
        let details = pending.prefix(3).map { "ID \($0.id ?? -1)" }.joined(separator: ", ")
        AppLogger.shared.log(.system, "Starting retry batch", detail: "\(pending.count) failed transcriptions (\(details)...)")
        isRetrying = true
        pendingCount = pending.count

        let modelId = LiveSettings.shared.selectedModelId

        for (index, utterance) in pending.enumerated() {
            let progress = "[\(index + 1)/\(pending.count)]"

            guard let audioURL = utterance.audioURL, utterance.hasAudio else {
                let audioPath = utterance.audioURL?.path ?? "nil"
                let hasAudioStr = utterance.hasAudio ? "true" : "false"
                AppLogger.shared.log(.error, "Skipping retry \(progress)", detail: "ID \(utterance.id ?? -1) - audioURL=\(audioPath), hasAudio=\(hasAudioStr)", level: .notice)
                // Mark as failed permanently (no audio to retry with)
                LiveDatabase.markTranscriptionFailed(id: utterance.id, error: "Audio file missing")
                pendingCount = max(0, pendingCount - 1)
                continue
            }

            AppLogger.shared.log(.transcription, "Retry attempt \(progress)", detail: "ID \(utterance.id ?? -1), file: \(audioURL.lastPathComponent)")

            do {
                // Transcribe via Engine - pass path directly, engine reads the file
                let startTime = Date()
                let externalRefId = utterance.id != nil ? "retry-\(utterance.id!)" : nil
                let text = try await client.transcribe(audioPath: audioURL.path, modelId: modelId, externalRefId: externalRefId)
                let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Update database with success
                LiveDatabase.markTranscriptionSuccess(
                    id: utterance.id,
                    text: text,
                    perfEngineMs: transcriptionMs,
                    model: modelId
                )

                AppLogger.shared.log(.transcription, "Retry succeeded", detail: "ID \(utterance.id ?? -1) in \(transcriptionMs)ms")

                // Refresh DictationStore to pick up the updated record from DB
                DictationStore.shared.refresh()

            } catch {
                AppLogger.shared.log(.error, "Retry failed", detail: "ID \(utterance.id ?? -1): \(error.localizedDescription)")

                // Update database with new error
                LiveDatabase.markTranscriptionFailed(id: utterance.id, error: error.localizedDescription)

                // If connection lost, stop retrying
                if !client.isConnected {
                    AppLogger.shared.log(.error, "Engine connection lost during retry", detail: "Stopping batch", level: .notice)
                    break
                }
            }

            pendingCount = max(0, pendingCount - 1)
        }

        isRetrying = false
        lastRetryAt = Date()
        refreshPendingCount()

        AppLogger.shared.log(.system, "Retry batch complete", detail: "Remaining: \(self.pendingCount), isRetrying flag cleared")
    }

    /// Manually trigger retry for a single utterance
    func retrySingle(_ utterance: LiveDictation) async -> Bool {
        guard let audioURL = utterance.audioURL, utterance.hasAudio else {
            logger.warning("[RetryManager] Cannot retry - no audio file")
            return false
        }

        let client = EngineClient.shared
        let modelId = LiveSettings.shared.selectedModelId

        do {
            // Pass path directly - engine reads the file
            let startTime = Date()
            let externalRefId = utterance.id != nil ? "retry-\(utterance.id!)" : nil
            let text = try await client.transcribe(audioPath: audioURL.path, modelId: modelId, externalRefId: externalRefId)
            let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

            LiveDatabase.markTranscriptionSuccess(
                id: utterance.id,
                text: text,
                perfEngineMs: transcriptionMs,
                model: modelId
            )

            refreshPendingCount()
            return true

        } catch {
            LiveDatabase.markTranscriptionFailed(id: utterance.id, error: error.localizedDescription)
            return false
        }
    }
}
