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
    }

    private func handleConnectionStateChange(_ state: EngineConnectionState) {
        let isNowConnected = state == .connected

        // If we just reconnected, trigger retry
        if isNowConnected && !wasConnected {
            logger.info("[RetryManager] Engine reconnected - checking for failed transcriptions")
            Task {
                await retryFailedTranscriptions()
            }
        }

        wasConnected = isNowConnected
    }

    func refreshPendingCount() {
        pendingCount = PastLivesDatabase.countNeedsRetry()
    }

    /// Retry all failed/pending transcriptions
    func retryFailedTranscriptions() async {
        guard !isRetrying else {
            logger.info("[RetryManager] Already retrying, skipping")
            return
        }

        let pending = PastLivesDatabase.fetchNeedsRetry()
        guard !pending.isEmpty else {
            logger.info("[RetryManager] No failed transcriptions to retry")
            pendingCount = 0
            return
        }

        logger.info("[RetryManager] Found \(pending.count) transcriptions to retry")
        isRetrying = true
        pendingCount = pending.count

        let client = EngineClient.shared
        let modelId = LiveSettings.shared.selectedModelId

        for utterance in pending {
            guard let audioURL = utterance.audioURL, utterance.hasAudio else {
                logger.warning("[RetryManager] Skipping \(utterance.id ?? -1) - no audio file")
                // Mark as failed permanently (no audio to retry with)
                PastLivesDatabase.markTranscriptionFailed(id: utterance.id, error: "Audio file missing")
                continue
            }

            logger.info("[RetryManager] Retrying transcription for \(utterance.id ?? -1)")

            do {
                // Read audio file
                let audioData = try Data(contentsOf: audioURL)

                // Transcribe via Engine
                let startTime = Date()
                let text = try await client.transcribe(audioData: audioData, modelId: modelId)
                let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Update database with success
                PastLivesDatabase.markTranscriptionSuccess(
                    id: utterance.id,
                    text: text,
                    transcriptionMs: transcriptionMs,
                    model: modelId
                )

                logger.info("[RetryManager] ✓ Retry succeeded for \(utterance.id ?? -1): \(text.prefix(50))...")

                // Also update UtteranceStore for UI (legacy)
                var metadata = UtteranceMetadata()
                metadata.whisperModel = modelId
                metadata.transcriptionDurationMs = transcriptionMs
                metadata.audioFilename = utterance.audioFilename
                UtteranceStore.shared.add(
                    text,
                    durationSeconds: utterance.durationSeconds,
                    metadata: metadata
                )

            } catch {
                logger.error("[RetryManager] ✗ Retry failed for \(utterance.id ?? -1): \(error.localizedDescription)")

                // Update database with new error
                PastLivesDatabase.markTranscriptionFailed(id: utterance.id, error: error.localizedDescription)
            }

            pendingCount = max(0, pendingCount - 1)
        }

        isRetrying = false
        lastRetryAt = Date()
        refreshPendingCount()

        logger.info("[RetryManager] Retry batch complete. Remaining: \(self.pendingCount)")
    }

    /// Manually trigger retry for a single utterance
    func retrySingle(_ utterance: LiveUtterance) async -> Bool {
        guard let audioURL = utterance.audioURL, utterance.hasAudio else {
            logger.warning("[RetryManager] Cannot retry - no audio file")
            return false
        }

        let client = EngineClient.shared
        let modelId = LiveSettings.shared.selectedModelId

        do {
            let audioData = try Data(contentsOf: audioURL)
            let startTime = Date()
            let text = try await client.transcribe(audioData: audioData, modelId: modelId)
            let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

            PastLivesDatabase.markTranscriptionSuccess(
                id: utterance.id,
                text: text,
                transcriptionMs: transcriptionMs,
                model: modelId
            )

            refreshPendingCount()
            return true

        } catch {
            PastLivesDatabase.markTranscriptionFailed(id: utterance.id, error: error.localizedDescription)
            return false
        }
    }
}
