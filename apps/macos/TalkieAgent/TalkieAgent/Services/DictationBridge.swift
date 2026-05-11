import Foundation
import TalkieKit

@MainActor
final class DictationBridge {
    static let shared = DictationBridge()

    private let log = Log(.system)
    private let captureService = MicCaptureService()

    private let orphanGracePeriod: TimeInterval = 900  // 15 min without a client before cancelling
    private let orphanSweepInterval: TimeInterval = 30

    private(set) var activeSessions: [String: DictationSession] = [:]

    final class DictationSession {
        let clientId: String
        let sessionId: String
        let startTime: Date
        let persist: Bool
        var orphanedAt: Date?

        /// Monotonically increasing generation counter. Callbacks check this
        /// to ensure they don't fire into a stale handler after reclaim.
        private(set) var callbackGeneration: UInt64 = 0

        private var _progress: (_ event: String, _ data: [String: Any]) -> Void
        private var _reply: (_ result: [String: Any]?, _ error: String?) -> Void

        var isOrphaned: Bool { orphanedAt != nil }

        init(
            clientId: String,
            sessionId: String,
            startTime: Date,
            persist: Bool,
            progress: @escaping (_ event: String, _ data: [String: Any]) -> Void,
            reply: @escaping (_ result: [String: Any]?, _ error: String?) -> Void
        ) {
            self.clientId = clientId
            self.sessionId = sessionId
            self.startTime = startTime
            self.persist = persist
            self._progress = progress
            self._reply = reply
        }

        /// Atomically swap callbacks and bump generation so any in-flight
        /// calls through old closures are silently dropped.
        func replaceCallbacks(
            progress: @escaping (_ event: String, _ data: [String: Any]) -> Void,
            reply: @escaping (_ result: [String: Any]?, _ error: String?) -> Void
        ) {
            callbackGeneration &+= 1
            _progress = progress
            _reply = reply
        }

        /// Safe progress callback — only fires if generation hasn't changed.
        func progress(_ event: String, _ data: [String: Any], generation: UInt64? = nil) {
            guard generation == nil || generation == callbackGeneration else { return }
            _progress(event, data)
        }

        /// Safe reply callback — only fires if generation hasn't changed.
        func reply(_ result: [String: Any]?, _ error: String?, generation: UInt64? = nil) {
            guard generation == nil || generation == callbackGeneration else { return }
            _reply(result, error)
        }
    }

    private var orphanSweepTimer: Timer?

    private init() {
        startOrphanSweep()
    }

    private func startOrphanSweep() {
        orphanSweepTimer?.invalidate()
        orphanSweepTimer = Timer.scheduledTimer(withTimeInterval: orphanSweepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expireOrphanedSessions()
            }
        }
    }

    private func expireOrphanedSessions() {
        let now = Date()
        let expired = activeSessions.values.filter { session in
            guard let orphanedAt = session.orphanedAt else { return false }
            return now.timeIntervalSince(orphanedAt) >= orphanGracePeriod
        }

        for session in expired {
            log.info("[DictationBridge] Orphan expired after \(Int(orphanGracePeriod))s (client=\(session.clientId) session=\(session.sessionId))")
            cancelDictation(clientId: session.clientId)
        }
    }

    func startDictation(
        clientId: String,
        persist: Bool,
        progress: @escaping (_ event: String, _ data: [String: Any]) -> Void,
        reply: @escaping (_ result: [String: Any]?, _ error: String?) -> Void
    ) {
        // Reclaim orphaned session — client reconnected.
        // replaceCallbacks() bumps the generation counter so any in-flight
        // calls through old closures are silently dropped.
        if let existing = activeSessions[clientId], existing.isOrphaned {
            log.info("[DictationBridge] Reclaiming orphaned session (client=\(clientId) session=\(existing.sessionId))")
            existing.replaceCallbacks(progress: progress, reply: reply)
            existing.orphanedAt = nil
            existing.progress("stateChange", ["state": "recording", "previous": "reconnected"])
            return
        }

        guard activeSessions[clientId] == nil else {
            reply(nil, "mic_busy:\(clientId)")
            return
        }

        log.info("[DictationBridge] Starting dictation for client=\(clientId) persist=\(persist)")

        Task {
            do {
                let sessionId = try await captureService.startSession(
                    clientId: clientId,
                    persist: persist,
                    label: nil
                )

                activeSessions[clientId] = DictationSession(
                    clientId: clientId,
                    sessionId: sessionId,
                    startTime: Date(),
                    persist: persist,
                    progress: progress,
                    reply: reply
                )

                progress("stateChange", ["state": "recording", "previous": "starting"])
            } catch {
                log.error("[DictationBridge] Failed to start capture session", error: error)
                reply(nil, "mic_start_failed: \(error.localizedDescription)")
            }
        }
    }

    func stopDictation(clientId: String) {
        guard let session = activeSessions[clientId] else {
            log.info("[DictationBridge] stopDictation ignored — no active session for client=\(clientId)")
            return
        }

        log.info("[DictationBridge] Stopping dictation for client=\(clientId)")

        Task {
            do {
                let result = try await captureService.stopSession(sessionId: session.sessionId)
                guard activeSessions[clientId] != nil else { return }

                log.info("[DictationBridge] Audio captured: \(result.filePath) size=\(result.fileSize) duration=\(String(format: "%.1f", result.duration))s")
                await processAudio(
                    clientId: clientId,
                    filePath: result.filePath,
                    capturedDuration: result.duration
                )
            } catch {
                failSession(clientId: clientId, error: "mic_stop_failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelDictation(
        clientId: String,
        reply: ((_ result: [String: Any]?, _ error: String?) -> Void)? = nil
    ) {
        guard let session = activeSessions.removeValue(forKey: clientId) else {
            reply?(nil, "no_active_session")
            return
        }

        log.info("[DictationBridge] Cancelling dictation for client=\(clientId)")

        Task {
            do {
                try await captureService.cancelSession(sessionId: session.sessionId)
                session.progress("stateChange", ["state": "cancelled", "previous": "recording"])
                session.reply(["cancelled": true], nil)
                reply?(["cancelled": true], nil)
            } catch {
                let message = "mic_cancel_failed: \(error.localizedDescription)"
                session.reply(nil, message)
                reply?(nil, message)
            }
        }
    }

    func clientDisconnected(clientId: String) {
        guard let session = activeSessions[clientId], !session.isOrphaned else { return }
        log.info("[DictationBridge] Client disconnected, session orphaned (client=\(clientId) session=\(session.sessionId))")
        session.orphanedAt = Date()
    }

    private func processAudio(
        clientId: String,
        filePath: String,
        capturedDuration: TimeInterval
    ) async {
        guard let session = activeSessions[clientId] else { return }

        session.progress("stateChange", ["state": "processing", "previous": "recording"])

        let tempURL = URL(fileURLWithPath: filePath)
        guard let audioFilename = AudioStorage.copyToStorage(tempURL) else {
            failSession(clientId: clientId, error: "audio_save_failed")
            return
        }

        try? FileManager.default.removeItem(at: tempURL)

        let audioPath = AudioStorage.url(for: audioFilename).path
        let modelId = LiveSettings.shared.selectedModelId

        do {
            let service = EngineTranscriptionService(modelId: modelId)
            let request = TranscriptionRequest(audioPath: audioPath, isLive: true)
            let transcript = try await service.transcribe(request)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                activeSessions.removeValue(forKey: clientId)
                session.progress("stateChange", ["state": "done", "previous": "processing"])
                session.reply(["text": "", "silence": true], nil)
                return
            }

            if session.persist {
                let dictation = LiveDictation(
                    text: text,
                    mode: "bridge",
                    // Persist the recorder's measured audio duration, not elapsed wall time
                    // after transcription finishes.
                    durationSeconds: capturedDuration,
                    transcriptionModel: modelId,
                    audioFilename: audioFilename,
                    transcriptionStatus: .success
                )
                let recording = LiveRecording(from: dictation)
                UnifiedDatabase.store(recording)
                TalkieAgentXPCService.shared.notifyDictationAdded()
            }

            activeSessions.removeValue(forKey: clientId)
            session.progress("finalTranscript", ["text": text])
            session.progress("stateChange", ["state": "done", "previous": "processing"])
            session.reply(["text": text], nil)
        } catch {
            failSession(clientId: clientId, error: "transcription_failed: \(error.localizedDescription)")
        }
    }

    private func failSession(clientId: String, error: String) {
        guard let session = activeSessions.removeValue(forKey: clientId) else { return }
        session.progress("stateChange", ["state": "error", "previous": "processing"])
        session.reply(nil, error)
    }
}
