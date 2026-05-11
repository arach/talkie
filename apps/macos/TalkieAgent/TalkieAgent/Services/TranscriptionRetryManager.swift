//
//  TranscriptionRetryManager.swift
//  TalkieAgent
//
//  Automatically retries failed transcriptions when Engine reconnects
//

import Foundation
import Combine
import TalkieKit

private let log = Log(.transcription)

@MainActor
final class TranscriptionRetryManager: ObservableObject {
    static let shared = TranscriptionRetryManager()

    @Published private(set) var isRetrying = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastRetryAt: Date?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Just track pending count for UI display — no automatic retries.
        // Auto-retry was disabled because old audio files get cleaned up,
        // causing a flood of "File not found" errors on every Engine reconnect.
        refreshPendingCount()

        AppLogger.shared.log(.system, "RetryManager initialized", detail: "Pending: \(self.pendingCount) (auto-retry disabled)")
    }

    func refreshPendingCount() {
        pendingCount = UnifiedDatabase.countNeedsRetry()
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
        log.debug("[RetryManager] Engine connected: \(connectedStr), state: \(client.connectionState.rawValue)")

        if !client.isConnected {
            AppLogger.shared.log(.system, "Engine not connected", detail: "Attempting to connect before retry", level: .notice)
            let connected = await client.ensureConnected()
            if !connected {
                AppLogger.shared.log(.error, "Failed to connect to engine", detail: "Cannot retry transcriptions")
                return
            }
            AppLogger.shared.log(.system, "Engine connection established", detail: "Proceeding with retry")
        }

        let pending = UnifiedDatabase.fetchNeedsRetry()
        log.info("[RetryManager] fetchNeedsRetry returned \(pending.count) records")

        guard !pending.isEmpty else {
            AppLogger.shared.log(.system, "No retries needed", detail: "fetchNeedsRetry returned 0 records")
            pendingCount = 0
            return
        }

        // Log details about what we're retrying
        let details = pending.prefix(3).map { "ID \($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
        AppLogger.shared.log(.system, "Starting retry batch", detail: "\(pending.count) failed transcriptions (\(details)...)")
        isRetrying = true
        pendingCount = pending.count

        let modelId = LiveSettings.shared.selectedModelId

        for (index, recording) in pending.enumerated() {
            let progress = "[\(index + 1)/\(pending.count)]"

            // Get audio URL from filename or recording ID
            let audioURL: URL?
            if let filename = recording.audioFilename {
                audioURL = AudioStorage.url(for: filename)
            } else {
                audioURL = AudioStorage.url(forRecordingID: recording.id)
            }

            guard let audioURL = audioURL, recording.hasAudio else {
                let audioPath = audioURL?.path ?? "nil"
                let hasAudioStr = recording.hasAudio ? "true" : "false"
                AppLogger.shared.log(.error, "Skipping retry \(progress)", detail: "ID \(recording.id.uuidString.prefix(8)) - audioURL=\(audioPath), hasAudio=\(hasAudioStr)", level: .notice)
                // Mark as failed permanently (no audio to retry with)
                UnifiedDatabase.markTranscriptionFailed(id: recording.id, error: "Audio file missing")
                pendingCount = max(0, pendingCount - 1)
                continue
            }

            AppLogger.shared.log(.transcription, "Retry attempt \(progress)", detail: "ID \(recording.id.uuidString.prefix(8)), file: \(audioURL.lastPathComponent)")

            do {
                // Transcribe via Engine - pass path directly, engine reads the file
                let startTime = Date()
                let externalRefId = "retry-\(recording.id.uuidString)"
                let text = try await client.transcribe(audioPath: audioURL.path, modelId: modelId, externalRefId: externalRefId)
                let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Update database with success
                UnifiedDatabase.markTranscriptionSuccess(
                    id: recording.id,
                    text: text,
                    perfEngineMs: transcriptionMs,
                    model: modelId
                )

                AppLogger.shared.log(.transcription, "Retry succeeded", detail: "ID \(recording.id.uuidString.prefix(8)) in \(transcriptionMs)ms")

                // Refresh DictationStore to pick up the updated record from DB
                DictationStore.shared.refresh()

            } catch {
                AppLogger.shared.log(.error, "Retry failed", detail: "ID \(recording.id.uuidString.prefix(8)): \(error.localizedDescription)")

                // Track consecutive failures for this recording
                let isEmptyResponse = error.localizedDescription.contains("Empty response")
                let currentRetryCount = parseRetryCount(from: recording.transcriptionError)
                let newRetryCount = currentRetryCount + 1

                // After 3 consecutive empty responses, mark as permanently failed
                // This prevents infinite retry loops for audio that can't be transcribed
                if isEmptyResponse && newRetryCount >= 3 {
                    UnifiedDatabase.markTranscriptionFailed(
                        id: recording.id,
                        error: "No speech detected after \(newRetryCount) attempts - audio may be silent or corrupted"
                    )
                    AppLogger.shared.log(.error, "Retry exhausted", detail: "ID \(recording.id.uuidString.prefix(8)) marked as permanently failed")
                } else {
                    // Include retry count in error for tracking
                    let errorWithCount = isEmptyResponse
                        ? "Empty response (attempt \(newRetryCount)/3)"
                        : error.localizedDescription
                    UnifiedDatabase.markTranscriptionFailed(id: recording.id, error: errorWithCount)
                }

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

    /// Clear all pending/failed transcriptions (mark as dismissed)
    /// Use this when user wants to dismiss stuck items without retrying
    func clearPending() {
        let pending = UnifiedDatabase.fetchNeedsRetry()
        for recording in pending {
            UnifiedDatabase.markTranscriptionFailed(id: recording.id, error: "Dismissed by user")
        }
        pendingCount = 0
        AppLogger.shared.log(.system, "Cleared pending retries", detail: "Dismissed \(pending.count) items")
    }

    /// Parse retry count from error message (e.g., "Empty response (attempt 2/3)" -> 2)
    private func parseRetryCount(from errorMessage: String?) -> Int {
        guard let error = errorMessage else { return 0 }
        // Match "attempt N/3" pattern
        if let range = error.range(of: #"attempt (\d+)/3"#, options: .regularExpression),
           let match = error[range].split(separator: " ").last,
           let numStr = match.split(separator: "/").first,
           let count = Int(numStr) {
            return count
        }
        return 0
    }

    /// Manually trigger retry for a single recording
    func retrySingle(_ recording: LiveRecording) async -> Bool {
        // Get audio URL from filename or recording ID
        let audioURL: URL?
        if let filename = recording.audioFilename {
            audioURL = AudioStorage.url(for: filename)
        } else {
            audioURL = AudioStorage.url(forRecordingID: recording.id)
        }

        guard let audioURL = audioURL, recording.hasAudio else {
            log.warning("[RetryManager] Cannot retry - no audio file")
            return false
        }

        let client = EngineClient.shared
        let modelId = LiveSettings.shared.selectedModelId

        do {
            // Pass path directly - engine reads the file
            let startTime = Date()
            let externalRefId = "retry-\(recording.id.uuidString)"
            let text = try await client.transcribe(audioPath: audioURL.path, modelId: modelId, externalRefId: externalRefId)
            let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

            UnifiedDatabase.markTranscriptionSuccess(
                id: recording.id,
                text: text,
                perfEngineMs: transcriptionMs,
                model: modelId
            )

            refreshPendingCount()
            return true

        } catch {
            // Track consecutive failures
            let isEmptyResponse = error.localizedDescription.contains("Empty response")
            let currentRetryCount = parseRetryCount(from: recording.transcriptionError)
            let newRetryCount = currentRetryCount + 1

            if isEmptyResponse && newRetryCount >= 3 {
                UnifiedDatabase.markTranscriptionFailed(
                    id: recording.id,
                    error: "No speech detected after \(newRetryCount) attempts"
                )
            } else {
                let errorWithCount = isEmptyResponse
                    ? "Empty response (attempt \(newRetryCount)/3)"
                    : error.localizedDescription
                UnifiedDatabase.markTranscriptionFailed(id: recording.id, error: errorWithCount)
            }
            return false
        }
    }
}
