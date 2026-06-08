//
//  AgentVoiceSession.swift
//  TalkieAgent
//
//  Live state for one agent voice transmission. Observable so the SwiftUI
//  scope view binds to it.
//
//  Phase progression (Unit 3 — closed loop):
//      .ready    →  .arming         (press; immediate UI feedback)
//      .arming   →  .transmitting   (mic ready)
//      .transmitting → .over        (release; brief 400ms beat)
//      .over     →  .thinking       (transcript captured, LLM in flight)
//      .thinking →  .receiving      (LLM reply ready, panel extends)
//                or .error          (transcription or LLM failed)
//      .receiving / .error  →  .ready  (user dismisses, panel hides)
//      .receiving → .followUpRecording → .followUpOver → .thinking
//                                      (in-panel continuation turn)
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
final class AgentVoiceSession: ObservableObject {
    @Published private(set) var phase: AgentVoiceScopePhase = .ready
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsedMs: Int = 0
    @Published private(set) var transcript: String?
    @Published private(set) var replyText: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var llmLatencyMs: Int?
    @Published private(set) var topLevelProviderName: String?
    @Published private(set) var topLevelModelId: String?
    @Published private(set) var executorRuntimeName: String?
    @Published private(set) var continuationSessionId: String?
    @Published private(set) var executorBranchState: AgentVoiceExecutorBranchState = .idle
    @Published private(set) var routeMode: AgentVoiceTransmissionMode?
    @Published private(set) var toolInvocations: [AgentVoiceToolInvocation] = []
    @Published private(set) var offersVoiceRetry = false
    @Published private(set) var isLatchedTransmission = false
    @Published var autoPlayEnabled: Bool {
        didSet {
            TalkieSharedSettings.set(autoPlayEnabled, forKey: AgentSettingsKey.agentVoiceAutoPlay)
        }
    }

    private var meter: AgentVoiceAudioMeter?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var pipelineTask: Task<Void, Never>?
    private var executorReportTask: Task<Void, Never>?
    private var latestTopLevelModel: AgentModelUse?

    init() {
        self.autoPlayEnabled = TalkieSharedSettings.bool(forKey: AgentSettingsKey.agentVoiceAutoPlay)
    }

    // MARK: - Lifecycle

    func prepareTransmission() {
        resetCaptureState(clearsVisibleTurn: true, clearsContinuation: true)
        phase = .arming
        startedAt = Date()
        elapsedMs = 0
    }

    func beginTransmission() {
        guard phase == .arming || phase == .ready else { return }
        startCapture(
            phase: .transmitting,
            clearsVisibleTurn: true,
            clearsContinuation: true,
            isLatched: false
        )
    }

    func beginVoiceFollowUp() {
        guard phase == .receiving, executorBranchState != .working else { return }
        startCapture(
            phase: .followUpRecording,
            clearsVisibleTurn: false,
            clearsContinuation: false,
            isLatched: false
        )
    }

    func toggleVoiceFollowUp() {
        switch phase {
        case .receiving where executorBranchState != .working:
            beginVoiceFollowUp()
        case .followUpRecording:
            Task { @MainActor in
                await endVoiceFollowUp()
            }
        default:
            break
        }
    }

    private func startCapture(
        phase nextPhase: AgentVoiceScopePhase,
        clearsVisibleTurn: Bool,
        clearsContinuation: Bool,
        isLatched: Bool
    ) {
        resetCaptureState(clearsVisibleTurn: clearsVisibleTurn, clearsContinuation: clearsContinuation)

        phase = nextPhase
        isLatchedTransmission = isLatched
        startedAt = Date()
        elapsedMs = 0

        let m = AgentVoiceAudioMeter { [weak self] level in
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

    private func resetCaptureState(clearsVisibleTurn: Bool, clearsContinuation: Bool) {
        pipelineTask?.cancel()
        pipelineTask = nil
        executorReportTask?.cancel()
        executorReportTask = nil
        SelectionSpeechPlaybackController.shared.stop()
        meter?.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        executorBranchState = .idle

        transcript = nil
        errorMessage = nil
        if clearsVisibleTurn {
            replyText = nil
            llmLatencyMs = nil
            topLevelProviderName = nil
            topLevelModelId = nil
            executorRuntimeName = nil
            routeMode = nil
            toolInvocations = []
        }
        if clearsContinuation {
            continuationSessionId = nil
            latestTopLevelModel = nil
        }
        offersVoiceRetry = false
        isLatchedTransmission = false
    }

    /// Stop capture, hold the `.over` beat, then run the transcript +
    /// LLM pipeline. The panel stays visible the entire time.
    func endTransmission() async {
        guard phase != .arming else {
            await fail(
                "Didn't catch that. Want to try Talkie again?",
                offersVoiceRetry: true
            )
            return
        }
        await endCapture(overPhase: .over, isFollowUp: false)
    }

    func endVoiceFollowUp() async {
        guard phase == .followUpRecording else { return }
        await endCapture(overPhase: .followUpOver, isFollowUp: true)
    }

    private func endCapture(overPhase: AgentVoiceScopePhase, isFollowUp: Bool) async {
        meter?.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        level = 0
        phase = overPhase
        isLatchedTransmission = false
        try? await Task.sleep(for: .milliseconds(400))

        let recordedURL = meter?.recordedFileURL
        meter = nil

        guard let recordedURL else {
            await fail(
                "Didn't catch that. Want to try Talkie again?",
                offersVoiceRetry: !isFollowUp
            )
            return
        }

        phase = .thinking
        let startedAt = startedAt ?? Date()
        let durationMs = elapsedMs
        pipelineTask = Task { @MainActor [weak self] in
            await self?.runPipeline(
                audioURL: recordedURL,
                startedAt: startedAt,
                durationMs: durationMs,
                isFollowUp: isFollowUp
            )
        }
        await pipelineTask?.value
    }

    /// User dismissed the result panel. Reset to idle. Also stops any
    /// in-flight TTS so the next Hyper+T press starts clean.
    func dismiss() {
        pipelineTask?.cancel()
        pipelineTask = nil
        executorReportTask?.cancel()
        executorReportTask = nil
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
        executorBranchState = .idle
        toolInvocations = []
        offersVoiceRetry = false
        isLatchedTransmission = false
    }

    func startVoiceRetryFromFallback() {
        guard phase == .error, offersVoiceRetry else { return }
        startCapture(
            phase: .transmitting,
            clearsVisibleTurn: true,
            clearsContinuation: true,
            isLatched: true
        )
    }

    // MARK: - Manual playback (PLAY button)

    func playReply() {
        guard let reply = replyText, !reply.isEmpty else { return }
        Task { @MainActor in
            do {
                _ = try await SelectionSpeechPlaybackController.shared.speakSelection(reply)
            } catch {
                log.error("Agent voice playReply failed", detail: error.localizedDescription)
            }
        }
    }

    // MARK: - Pipeline

    private func runPipeline(
        audioURL: URL,
        startedAt: Date,
        durationMs: Int,
        isFollowUp: Bool
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
            log.error("Agent voice transcription failed", detail: error.localizedDescription)
            await fail("Couldn't transcribe that. \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled else { return }

        guard !transcript.isEmpty else {
            await fail(
                "Didn't catch any speech. Want to talk to the agent again?",
                offersVoiceRetry: !isFollowUp
            )
            return
        }
        self.transcript = transcript
        self.replyText = nil
        log.info("Agent voice transcript captured", detail: transcript)

        if isFollowUp, continuationSessionId != nil {
            await runFollowUp(invocationForFollowUp(text: transcript, source: "agent-voice-follow-up-voice"))
            return
        }

        // 2. Top-level orchestration: multi-LLM routing + optional executor handoff.
        let draft = AgentVoiceTransmissionDraft(
            userBody: transcript,
            userDurationMs: durationMs,
            startedAt: startedAt
        )
        let result: AgentVoiceTurnResult
        do {
            result = try await AgentVoiceOrchestrator.shared.run(draft: draft) { @Sendable invocation in
                Task { @MainActor [weak self] in
                    self?.toolInvocations.append(invocation)
                }
            }
        } catch {
            log.error("Agent voice orchestration failed", detail: error.localizedDescription)
            await fail(error.localizedDescription)
            return
        }

        guard !Task.isCancelled else { return }

        let transmission = result.transmission
        latestTopLevelModel = result.topLevelModel
        self.llmLatencyMs = transmission.latencyMs
        self.topLevelProviderName = transmission.topLevelProviderName
        self.topLevelModelId = transmission.topLevelModelId
        self.executorRuntimeName = transmission.executorRuntimeName
        if let executorSessionId = transmission.executorSessionId {
            self.continuationSessionId = executorSessionId
        }
        self.routeMode = transmission.mode
        self.replyText = transmission.talkieBody
        self.phase = .receiving
        log.info(
            "Agent voice reply ready",
            detail: "mode=\(transmission.mode.rawValue) model=\(transmission.topLevelModelId ?? "unknown")"
        )

        // 3. Auto-play if the toggle is on. Fires fire-and-forget;
        //    user can stop via dismiss or click PLAY again for replay.
        if autoPlayEnabled {
            playReply()
        }

        if transmission.mode == .async, let executorSessionId = transmission.executorSessionId {
            watchExecutorReport(sessionId: executorSessionId)
        }
    }

    func sendFollowUp(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pipelineTask?.cancel()
        executorReportTask?.cancel()
        executorReportTask = nil
        SelectionSpeechPlaybackController.shared.stop()
        transcript = trimmed
        replyText = nil
        errorMessage = nil
        llmLatencyMs = nil
        routeMode = .async
        executorBranchState = .idle
        toolInvocations = []
        phase = .thinking

        let invocation = invocationForFollowUp(text: trimmed, source: "agent-voice-follow-up")

        pipelineTask = Task { @MainActor [weak self] in
            await self?.runFollowUp(invocation)
        }
    }

    private func invocationForFollowUp(text: String, source: String) -> AgentInvocation {
        AgentInvocation(
            id: UUID(),
            channel: .defaultChannel,
            transcript: text,
            instruction: text,
            topLevelModel: latestTopLevelModel ?? AgentModelUse(
                providerId: "talkie-agent",
                providerName: "Talkie Agent",
                modelId: "agent-voice-follow-up"
            ),
            requestedAt: Date(),
            conversationId: "channel-\(AgentChannel.defaultChannel.code.lowercased())",
            parentSessionId: continuationSessionId,
            source: source
        )
    }

    private func runFollowUp(_ invocation: AgentInvocation) async {
        do {
            let result = try await AgentRuntimeClient.shared.invoke(invocation)
            if let sessionId = result.sessionId {
                continuationSessionId = sessionId
            }
            executorRuntimeName = agentRuntimeDisplayName(for: result.providerId) ?? "Agent Runtime Dispatcher"
            routeMode = .async
            replyText = result.ack
            executorBranchState = result.sessionId == nil ? .done : .working
            phase = .receiving
            if autoPlayEnabled {
                playReply()
            }

            let activity = try await waitForRuntimeActivity(sessionId: result.sessionId)
            guard !Task.isCancelled else { return }

            if let activity {
                let applied = await applyExecutorResult(activity, fallbackError: "The follow-up failed.")
                guard applied else { return }
                return
            }

            executorBranchState = .done
        } catch {
            log.error("Agent voice follow-up failed", detail: error.localizedDescription)
            await fail(error.localizedDescription)
        }
    }

    private func watchExecutorReport(sessionId: String) {
        executorReportTask?.cancel()
        executorBranchState = .working
        executorReportTask = Task { @MainActor [weak self] in
            await self?.reportBackWhenExecutorCompletes(sessionId: sessionId)
        }
    }

    private func reportBackWhenExecutorCompletes(sessionId: String) async {
        do {
            let activity = try await waitForRuntimeActivity(sessionId: sessionId)
            guard !Task.isCancelled else { return }

            guard let activity else { return }
            let applied = await applyExecutorResult(activity, fallbackError: "The agent did not finish cleanly.")
            guard applied else { return }
            log.info("Agent voice executor branch returned", detail: "session=\(activity.sessionId)")
        } catch {
            guard !Task.isCancelled else { return }
            executorBranchState = .failed
            log.error("Agent voice executor report failed", detail: error.localizedDescription)
        }
    }

    private func applyExecutorResult(
        _ activity: AgentRuntimeActivitySnapshot,
        fallbackError: String
    ) async -> Bool {
        continuationSessionId = activity.sessionId
        topLevelProviderName = activity.topLevelProviderName ?? topLevelProviderName
        topLevelModelId = activity.topLevelModelId ?? topLevelModelId
        executorRuntimeName = agentRuntimeDisplayName(for: activity.providerId)
            ?? activity.runtimeName
            ?? executorRuntimeName
        routeMode = .async

        let state = activity.state.lowercased()
        if ["failed", "cancelled", "canceled"].contains(state) {
            executorBranchState = .failed
            await fail(activity.error ?? fallbackError)
            return false
        }

        let spokenSummary = activity.spokenSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let fullOutput = activity.output?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        replyText = spokenSummary
            ?? fullOutput
            ?? "The agent replied."
        executorBranchState = .done
        phase = .receiving
        notifyReportBack(activity: activity, spokenSummary: spokenSummary, fullOutput: fullOutput)
        if autoPlayEnabled {
            playReply()
        }
        return true
    }

    private func notifyReportBack(
        activity: AgentRuntimeActivitySnapshot,
        spokenSummary: String?,
        fullOutput: String?
    ) {
        let body = spokenSummary
            ?? fullOutput
            ?? activity.ack.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "The background task is ready."
        let title = activity.agentSessionName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "Talkie report back"

        TalkieNotifier.shared.agentReport(
            sessionId: activity.sessionId,
            title: title,
            body: body,
            spokenSummary: spokenSummary,
            source: activity.source
        )
    }

    private func waitForRuntimeActivity(sessionId: String?) async throws -> AgentRuntimeActivitySnapshot? {
        guard let sessionId else { return nil }

        let startedAt = Date()
        var lastPartialOutput = ""
        while Date().timeIntervalSince(startedAt) < 600 {
            guard !Task.isCancelled else { return nil }
            let status = try await AgentRuntimeClient.shared.status()
            if let activity = status.activities.first(where: { $0.sessionId == sessionId }) {
                let state = activity.state.lowercased()
                if ["done", "completed", "complete", "succeeded", "failed", "cancelled", "canceled"].contains(state) {
                    return activity
                }
                updatePartialRuntimeOutput(activity, previousOutput: &lastPartialOutput)
            }
            try await Task.sleep(for: .milliseconds(600))
        }

        throw AgentRuntimeClientError.runtimeTimedOut
    }

    private func updatePartialRuntimeOutput(
        _ activity: AgentRuntimeActivitySnapshot,
        previousOutput: inout String
    ) {
        let partialOutput = activity.output?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        guard let partialOutput, partialOutput != previousOutput else { return }

        previousOutput = partialOutput
        replyText = partialOutput
        phase = .receiving
    }

    private func fail(_ message: String, offersVoiceRetry: Bool = false) async {
        log.error("Agent voice session error", detail: message)
        if executorBranchState == .working {
            executorBranchState = .failed
        }
        self.offersVoiceRetry = offersVoiceRetry
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
