//
//  WalkieSession.swift
//  TalkieAgent
//
//  Live state for one walkie transmission. Observable so the SwiftUI
//  scope view binds to it.
//
//  Phase progression (Unit 3 — closed loop):
//      .ready    →  .transmitting   (press)
//      .transmitting → .over        (release; brief 400ms beat)
//      .over     →  .thinking       (transcript captured, LLM in flight)
//      .thinking →  .receiving      (LLM reply ready, panel extends)
//                or .error          (transcription or LLM failed)
//      .receiving / .error  →  .ready  (user dismisses, panel hides)
//
//  Auto-play (Unit 3.1) — when enabled, the session triggers TTS
//  automatically as soon as the reply lands. Persisted via
//  TalkieSharedSettings so the choice survives relaunches.
//

import AppKit
import Combine
import Foundation
import SwiftUI
import TalkieKit

private let log = Log(.workflow)

@MainActor
final class WalkieSession: ObservableObject {
    @Published private(set) var phase: WalkieScopePhase = .ready
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsedMs: Int = 0
    @Published private(set) var transcript: String?
    @Published private(set) var replyText: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var llmLatencyMs: Int?
    @Published private(set) var topLevelProviderName: String?
    @Published private(set) var topLevelModelId: String?
    @Published private(set) var executorRuntimeName: String?
    @Published private(set) var routeMode: WalkieTransmissionMode?
    @Published private(set) var toolInvocations: [WalkieToolInvocation] = []
    @Published var autoPlayEnabled: Bool {
        didSet {
            TalkieSharedSettings.set(autoPlayEnabled, forKey: AgentSettingsKey.walkieAutoPlay)
        }
    }

    private var meter: WalkieAudioMeter?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var pipelineTask: Task<Void, Never>?

    init() {
        self.autoPlayEnabled = TalkieSharedSettings.bool(forKey: AgentSettingsKey.walkieAutoPlay)
    }

    // MARK: - Lifecycle

    func beginTransmission() {
        pipelineTask?.cancel()
        pipelineTask = nil
        SelectionSpeechPlaybackController.shared.stop()
        meter?.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        // Fresh transmission — clear any previous reply state.
        transcript = nil
        replyText = nil
        errorMessage = nil
        llmLatencyMs = nil
        topLevelProviderName = nil
        topLevelModelId = nil
        executorRuntimeName = nil
        routeMode = nil
        toolInvocations = []

        phase = .transmitting
        startedAt = Date()
        elapsedMs = 0

        let m = WalkieAudioMeter { [weak self] level in
            guard let self else { return }
            self.level = self.level * 0.8 + level * 0.2
        }
        m.start()
        meter = m

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startedAt else { return }
                self.elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            }
        }
    }

    /// Stop capture, hold the `.over` beat, then run the transcript +
    /// LLM pipeline. The panel stays visible the entire time.
    func endTransmission() async {
        meter?.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        level = 0
        phase = .over
        try? await Task.sleep(for: .milliseconds(400))

        guard let recordedURL = meter?.recordedFileURL else {
            await fail("No audio captured.")
            return
        }
        meter = nil

        phase = .thinking
        let startedAt = startedAt ?? Date()
        let durationMs = elapsedMs
        pipelineTask = Task { @MainActor [weak self] in
            await self?.runPipeline(
                audioURL: recordedURL,
                startedAt: startedAt,
                durationMs: durationMs
            )
        }
        await pipelineTask?.value
    }

    /// User dismissed the result panel. Reset to idle. Also stops any
    /// in-flight TTS so the next Hyper+T press starts clean.
    func dismiss() {
        pipelineTask?.cancel()
        pipelineTask = nil
        SelectionSpeechPlaybackController.shared.stop()
        meter?.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        phase = .ready
        transcript = nil
        replyText = nil
        errorMessage = nil
        llmLatencyMs = nil
        topLevelProviderName = nil
        topLevelModelId = nil
        executorRuntimeName = nil
        routeMode = nil
        toolInvocations = []
    }

    // MARK: - Manual playback (PLAY button)

    func playReply() {
        guard let reply = replyText, !reply.isEmpty else { return }
        Task { @MainActor in
            do {
                _ = try await SelectionSpeechPlaybackController.shared.speakSelection(reply)
            } catch {
                log.error("Walkie playReply failed", detail: error.localizedDescription)
            }
        }
    }

    // MARK: - Pipeline

    private func runPipeline(
        audioURL: URL,
        startedAt: Date,
        durationMs: Int
    ) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        guard !Task.isCancelled else { return }

        // 1. Transcribe via existing EngineClient (Apple Speech / Parakeet).
        let transcript: String
        do {
            let client = EngineClient.shared
            let connected = await client.ensureConnected()
            guard connected else {
                await fail("Transcription engine isn't ready.")
                return
            }
            let modelId = LiveSettings.shared.selectedModelId
            transcript = try await client.transcribe(
                audioPath: audioURL.path,
                modelId: modelId,
                priority: .userInitiated,
                postProcess: .none
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            log.error("Walkie transcription failed", detail: error.localizedDescription)
            await fail("Couldn't transcribe that. \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled else { return }

        guard !transcript.isEmpty else {
            await fail("Didn't catch any speech.")
            return
        }
        self.transcript = transcript
        log.info("Walkie transcript captured", detail: transcript)

        // 2. Top-level orchestration: multi-LLM routing + optional executor handoff.
        let draft = WalkieTransmissionDraft(
            userBody: transcript,
            userDurationMs: durationMs,
            startedAt: startedAt
        )
        let result: WalkieTurnResult
        do {
            result = try await WalkieOrchestrator.shared.run(draft: draft) { @Sendable invocation in
                Task { @MainActor [weak self] in
                    self?.toolInvocations.append(invocation)
                }
            }
        } catch {
            log.error("Walkie orchestration failed", detail: error.localizedDescription)
            await fail(error.localizedDescription)
            return
        }

        guard !Task.isCancelled else { return }

        let transmission = result.transmission
        self.llmLatencyMs = transmission.latencyMs
        self.topLevelProviderName = transmission.topLevelProviderName
        self.topLevelModelId = transmission.topLevelModelId
        self.executorRuntimeName = transmission.executorRuntimeName
        self.routeMode = transmission.mode
        self.replyText = transmission.talkieBody
        self.phase = .receiving
        log.info(
            "Walkie reply ready",
            detail: "mode=\(transmission.mode.rawValue) model=\(transmission.topLevelModelId ?? "unknown")"
        )

        // 3. Auto-play if the toggle is on. Fires fire-and-forget;
        //    user can stop via dismiss or click PLAY again for replay.
        if autoPlayEnabled {
            playReply()
        }
    }

    private func fail(_ message: String) async {
        log.error("Walkie session error", detail: message)
        errorMessage = message
        phase = .error
    }

    // MARK: - Formatting helpers

    var formattedElapsed: String {
        let total = Double(elapsedMs) / 1000.0
        let minutes = Int(total) / 60
        let seconds = total.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
