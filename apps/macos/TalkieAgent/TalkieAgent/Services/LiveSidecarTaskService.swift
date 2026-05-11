//
//  LiveSidecarTaskService.swift
//  TalkieAgent
//
//  Runs lightweight background tasks against checkpointed recording segments.
//

import Foundation
import TalkieKit

private let log = Log(.workflow)

struct LiveSidecarRequest: Identifiable, Sendable {
    let id: UUID
    let captureSessionId: UUID
    let kind: LiveSidecarKind
    let targetSegmentIndex: Int
    let requestedAt: Date
    let requestedAtMs: Int
    let appName: String?
    let windowTitle: String?

    init(
        id: UUID = UUID(),
        captureSessionId: UUID,
        kind: LiveSidecarKind,
        targetSegmentIndex: Int,
        requestedAt: Date = Date(),
        requestedAtMs: Int,
        appName: String?,
        windowTitle: String?
    ) {
        self.id = id
        self.captureSessionId = captureSessionId
        self.kind = kind
        self.targetSegmentIndex = targetSegmentIndex
        self.requestedAt = requestedAt
        self.requestedAtMs = requestedAtMs
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

struct LiveSidecarTaskResult: Sendable {
    let kind: LiveSidecarKind
    let response: String
    let providerName: String
    let modelId: String
}

enum LiveSidecarTaskError: LocalizedError {
    case noProviderConfigured
    case emptyTranscript
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No LLM provider is configured for live sidecar tasks."
        case .emptyTranscript:
            return "The checkpoint transcript was empty."
        case .emptyResponse:
            return "The sidecar model returned an empty response."
        }
    }
}

actor LiveSidecarSessionStore {
    static let shared = LiveSidecarSessionStore()

    private struct SessionState {
        var pendingRequests: [LiveSidecarRequest] = []
        var inFlightRequestIds: Set<UUID> = []
        var completedProvenance: [ProvenanceSegment] = []
        var persistedRecordingId: UUID?
    }

    private var sessions: [UUID: SessionState] = [:]

    func queue(_ request: LiveSidecarRequest) {
        var session = sessions[request.captureSessionId] ?? SessionState()
        session.pendingRequests.append(request)
        sessions[request.captureSessionId] = session
    }

    func takeRequests(
        captureSessionId: UUID,
        segmentIndex: Int
    ) -> [LiveSidecarRequest] {
        guard var session = sessions[captureSessionId] else { return [] }
        let matched = session.pendingRequests.filter { $0.targetSegmentIndex == segmentIndex }
        session.pendingRequests.removeAll { $0.targetSegmentIndex == segmentIndex }
        for request in matched {
            session.inFlightRequestIds.insert(request.id)
        }
        sessions[captureSessionId] = session
        return matched
    }

    func completedProvenance(for captureSessionId: UUID) -> [ProvenanceSegment] {
        sessions[captureSessionId]?.completedProvenance ?? []
    }

    func setPersistedRecordingId(
        _ recordingId: UUID,
        for captureSessionId: UUID
    ) {
        var session = sessions[captureSessionId] ?? SessionState()
        session.persistedRecordingId = recordingId
        sessions[captureSessionId] = session
    }

    func complete(
        _ request: LiveSidecarRequest,
        provenance: ProvenanceSegment?
    ) -> UUID? {
        guard var session = sessions[request.captureSessionId] else {
            return nil
        }

        session.inFlightRequestIds.remove(request.id)
        if let provenance {
            session.completedProvenance.append(provenance)
        }

        let persistedRecordingId = session.persistedRecordingId
        store(session, for: request.captureSessionId)
        return persistedRecordingId
    }

    func clear(captureSessionId: UUID) {
        sessions.removeValue(forKey: captureSessionId)
    }

    func clearIfPersistedAndIdle(captureSessionId: UUID) {
        guard let session = sessions[captureSessionId], shouldClear(session) else { return }
        sessions.removeValue(forKey: captureSessionId)
    }

    private func store(_ session: SessionState, for captureSessionId: UUID) {
        if shouldClear(session) {
            sessions.removeValue(forKey: captureSessionId)
        } else {
            sessions[captureSessionId] = session
        }
    }

    private func shouldClear(_ session: SessionState) -> Bool {
        session.persistedRecordingId != nil
            && session.pendingRequests.isEmpty
            && session.inFlightRequestIds.isEmpty
    }
}

actor LiveSidecarTaskService {
    static let shared = LiveSidecarTaskService()

    func run(
        request: LiveSidecarRequest,
        transcript: String
    ) async throws -> LiveSidecarTaskResult {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw LiveSidecarTaskError.emptyTranscript
        }

        guard let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() else {
            throw LiveSidecarTaskError.noProviderConfigured
        }

        let prompt = LiveSidecarPromptBuilder.build(
            kind: request.kind,
            transcript: trimmedTranscript,
            appName: request.appName,
            windowTitle: request.windowTitle
        )

        let options = LLMGenerationOptions(
            temperature: request.kind == .feedback ? 0.35 : 0.2,
            maxTokens: 384,
            systemPrompt: prompt.system
        )

        log.info(
            "Running live sidecar task",
            detail: "\(request.kind.rawValue) segment=\(request.targetSegmentIndex)"
        )

        let response = try await resolved.provider.generate(
            prompt: prompt.user,
            model: resolved.modelId,
            options: options
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !response.isEmpty else {
            throw LiveSidecarTaskError.emptyResponse
        }

        return LiveSidecarTaskResult(
            kind: request.kind,
            response: response,
            providerName: resolved.provider.name,
            modelId: resolved.modelId
        )
    }
}
