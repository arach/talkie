//
//  WalkieOrchestrator.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let orchestratorLog = Log(.workflow)

actor WalkieOrchestrator {
    static let shared = WalkieOrchestrator()

    func run(
        draft: WalkieTransmissionDraft,
        onToolInvocation: @escaping @Sendable (WalkieToolInvocation) -> Void = { _ in }
    ) async throws -> WalkieTurnResult {
        _ = onToolInvocation

        let topLevel = try await resolveTopLevelModel(channel: draft.channel)
        let start = Date()
        let route = try await route(draft: draft, topLevel: topLevel)
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

        var transmission = WalkieTransmission(
            id: draft.id,
            channelId: draft.channel.id,
            code: draft.code,
            userBody: draft.userBody,
            userDurationMs: draft.userDurationMs,
            talkieBody: route.reply,
            mode: route.mode,
            topLevelProviderId: topLevel.providerId,
            topLevelProviderName: topLevel.providerName,
            topLevelModelId: topLevel.modelId,
            executorRuntimeId: nil,
            executorRuntimeName: nil,
            executorProviderId: draft.channel.executorProviderId,
            executorModelId: draft.channel.executorModelId,
            executorSessionId: nil,
            latencyMs: latencyMs,
            tokens: nil,
            startedAt: draft.startedAt,
            completedAt: route.mode == .verbal ? Date() : nil,
            jobState: route.mode == .async ? .acked : nil
        )

        if route.mode == .async {
            let runtimeId = draft.channel.executorRuntimeId
                ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.walkieExecutorRuntimeId)

            if let runtime = await WalkieRuntimeRegistry.shared.resolve(preferredId: runtimeId) {
                let invocation = WalkieAgentInvocation(
                    id: draft.id,
                    channel: draft.channel,
                    transcript: draft.userBody,
                    instruction: route.executorInstruction ?? draft.userBody,
                    topLevelModel: topLevel,
                    requestedAt: Date(),
                    conversationId: "channel-\(draft.channel.code.lowercased())",
                    parentSessionId: nil,
                    source: "voice"
                )
                let runtimeResult = try await runtime.invoke(invocation)
                transmission.talkieBody = runtimeResult.ack
                transmission.executorRuntimeId = runtime.id
                transmission.executorProviderId = runtimeResult.providerId
                transmission.executorModelId = runtimeResult.modelId
                transmission.executorRuntimeName = walkieAgentDisplayName(for: runtimeResult.providerId) ?? runtime.name
                transmission.executorSessionId = runtimeResult.sessionId
                transmission.jobState = runtimeResult.jobState
            } else {
                transmission.talkieBody = fallbackAsyncReply(route.reply)
                transmission.jobState = .failed
                transmission.completedAt = Date()
            }
        }

        orchestratorLog.info(
            "Walkie turn routed",
            detail: "mode=\(transmission.mode.rawValue) provider=\(topLevel.providerId) model=\(topLevel.modelId) latency=\(latencyMs)ms"
        )

        return WalkieTurnResult(
            transmission: transmission,
            route: route,
            topLevelModel: topLevel
        )
    }

    private func route(
        draft: WalkieTransmissionDraft,
        topLevel: WalkieModelUse
    ) async throws -> WalkieRouteDecision {
        let provider = try await resolveProvider(id: topLevel.providerId)
        let options = LLMGenerationOptions(
            temperature: 0.2,
            maxTokens: 420,
            systemPrompt: routeSystemPrompt(channel: draft.channel)
        )

        let response = try await provider.generate(
            prompt: routeUserPrompt(for: draft),
            model: topLevel.modelId,
            options: options
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let decision = parseRouteDecision(response)
        guard !decision.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WalkieOrchestratorError.emptyRouteReply
        }
        return decision
    }

    @MainActor
    private func resolveTopLevelModel(channel: WalkieChannel) async throws -> WalkieModelUse {
        let registry = LLMProviderRegistry.shared

        let preferredProviderId = channel.topLevelProviderId
            ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.walkieTopLevelProviderId)
            ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.llmProviderId)

        let preferredModelId = channel.topLevelModelId
            ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.walkieTopLevelModelId)
            ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.llmModelId)

        if let preferredProviderId,
           let provider = registry.provider(for: preferredProviderId),
           let preferredModelId,
           await provider.isAvailable {
            return WalkieModelUse(
                providerId: provider.id,
                providerName: provider.name,
                modelId: preferredModelId
            )
        }

        if let resolved = await registry.resolveProviderAndModel() {
            return WalkieModelUse(
                providerId: resolved.provider.id,
                providerName: resolved.provider.name,
                modelId: resolved.modelId
            )
        }

        throw WalkieOrchestratorError.noTopLevelModelConfigured
    }

    @MainActor
    private func resolveProvider(id: String) throws -> any LLMProvider {
        guard let provider = LLMProviderRegistry.shared.provider(for: id) else {
            throw LLMError.providerNotAvailable(id)
        }
        return provider
    }

    private func routeSystemPrompt(channel: WalkieChannel) -> String {
        """
        \(channel.systemPrompt)

        You are the top-level agent router. You are not the long-running agent worker.
        Decide whether the user's spoken turn should be answered immediately or handed to an agent runtime.

        Return one JSON object and nothing else:
        {
          "mode": "verbal" | "async",
          "reply": "short spoken answer or immediate ack",
          "executorInstruction": "specific instruction for the agent, or null",
          "confidence": 0.0,
          "rationale": "short private routing note"
        }

        Use "verbal" for short answers, quick explanations, small facts, and anything that can be handled in a few seconds.
        Use "async" for code changes, file edits, multi-step computer use, research, ambiguous outcomes, or work that an agent should report back on later.
        If using "verbal", answer directly in "reply" in 1-3 short sentences.
        If using "async", make "reply" a brief spoken ack and put the actionable task in "executorInstruction".
        """
    }

    private func routeUserPrompt(for draft: WalkieTransmissionDraft) -> String {
        """
        Channel: \(draft.channel.code) · \(draft.channel.label)
        Transmission: \(draft.code)
        Hold duration: \(draft.userDurationMs)ms

        User said:
        \(draft.userBody)
        """
    }

    private func parseRouteDecision(_ response: String) -> WalkieRouteDecision {
        let json = extractJSONObject(from: response)
        let data = Data(json.utf8)

        struct RouteDTO: Decodable {
            let mode: String?
            let reply: String?
            let executorInstruction: String?
            let confidence: Double?
            let rationale: String?
        }

        if let decoded = try? JSONDecoder().decode(RouteDTO.self, from: data) {
            let mode = decoded.mode == WalkieTransmissionMode.async.rawValue
                ? WalkieTransmissionMode.async
                : WalkieTransmissionMode.verbal
            return WalkieRouteDecision(
                mode: mode,
                reply: decoded.reply ?? "",
                executorInstruction: decoded.executorInstruction,
                confidence: decoded.confidence,
                rationale: decoded.rationale
            )
        }

        return WalkieRouteDecision(
            mode: .verbal,
            reply: response,
            executorInstruction: nil,
            confidence: nil,
            rationale: "Fallback: provider did not return JSON."
        )
    }

    private func extractJSONObject(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end
        else {
            return trimmed
        }

        return String(trimmed[start...end])
    }

    private func fallbackAsyncReply(_ ack: String) -> String {
        let trimmed = ack.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "I know this wants an agent, but no agent runtime is connected yet."
        }
        return "\(trimmed) I do not have an agent runtime connected yet."
    }
}
