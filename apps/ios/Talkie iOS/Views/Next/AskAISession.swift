import Foundation

@MainActor
final class AskAISession: ObservableObject {
    @Published var turns: [AskAITurn] = []
    @Published var prompt = ""
    @Published var isThinking = false
    @Published var failure: InferenceError?

    private struct RetryRequest {
        let messages: [InferenceMessage]
    }

    private let executor: any InferenceExecuting
    private let store: AskAISessionStore?
    private var lastPreset: AskAIPreset?
    private var lastModel: String?
    private var retryRequest: RetryRequest?
    private var requestTask: Task<Void, Never>?

    var readiness: InferenceReadiness { executor.readiness }

    var canSend: Bool {
        readiness.isReady
            && !isThinking
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRetry: Bool {
        readiness.isReady && !isThinking && retryRequest != nil
    }

    var lastTurnID: AskAITurn.ID? { turns.last?.id }

    var nextTurnCode: String { Self.code(for: turns.count + 1) }

    convenience init() {
        self.init(executor: InferenceService.shared, store: .shared)
    }

    init(
        executor: any InferenceExecuting,
        store: AskAISessionStore?
    ) {
        self.executor = executor
        self.store = store

        guard let snapshot = store?.load() else { return }
        turns = snapshot.turns.filter { !$0.isThinking }
        prompt = snapshot.draftPrompt ?? ""
        lastPreset = snapshot.lastPreset
        lastModel = snapshot.lastModel
        failure = snapshot.failure
        if let messages = snapshot.retryMessages, !messages.isEmpty {
            retryRequest = RetryRequest(messages: messages)
        }
    }

    func updatePrompt(_ value: String) {
        prompt = value
    }

    func persistDraft() {
        persist()
    }

    func clearResolvedConfigurationFailure() {
        guard readiness.isReady, failure?.needsConfiguration == true else { return }
        failure = nil
        persist()
    }

    func receiveVoicePrompt(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompt = trimmed
        persist()
    }

    func applyPreset(_ preset: AskAIPreset) {
        prompt = preset.template
        lastPreset = preset
        persist()
    }

    func reset() {
        requestTask?.cancel()
        requestTask = nil
        turns = []
        prompt = ""
        isThinking = false
        failure = nil
        retryRequest = nil
        lastPreset = nil
        lastModel = nil
        store?.clear()
    }

    func send() {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        submit(instruction: instruction, clearsDraft: true)
    }

    /// Sends a voice turn without overwriting a typed draft already waiting
    /// in the composer.
    func submitVoiceTranscript(_ transcript: String) {
        let instruction = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        submit(instruction: instruction, clearsDraft: false)
    }

    private func submit(instruction: String, clearsDraft: Bool) {
        guard !instruction.isEmpty, !isThinking else { return }

        guard readiness.isReady else {
            failure = .configurationRequired
            persist()
            return
        }

        failure = nil
        retryRequest = nil
        if clearsDraft {
            prompt = ""
        }

        let messages = conversationMessages() + [
            InferenceMessage(role: .user, content: instruction)
        ]
        turns.append(
            AskAITurn(
                code: Self.code(for: turns.count + 1),
                speaker: .user,
                body: instruction,
                createdAt: .now
            )
        )

        execute(RetryRequest(messages: messages))
    }

    func retry() {
        guard let retryRequest, !isThinking else { return }
        guard readiness.isReady else {
            failure = .configurationRequired
            persist()
            return
        }

        failure = nil
        execute(retryRequest)
    }

    private func execute(_ request: RetryRequest) {
        let thinkingTurn = AskAITurn(
            code: Self.code(for: turns.count + 1),
            speaker: .talkie,
            body: "Thinking…",
            createdAt: .now,
            model: readiness.modelLabel,
            latency: "0.0s",
            tokens: nil,
            isThinking: true
        )
        turns.append(thinkingTurn)
        isThinking = true
        persist()

        requestTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()

            do {
                let result = try await executor.execute(messages: request.messages)
                guard !Task.isCancelled else { return }

                replaceThinkingTurn(
                    id: thinkingTurn.id,
                    body: result.content,
                    providerName: result.providerName,
                    modelId: result.modelId,
                    latency: Self.latencyString(Date().timeIntervalSince(startedAt)),
                    tokens: Self.estimatedTokens(for: result.content)
                )
                failure = nil
                retryRequest = nil
                isThinking = false
                requestTask = nil
                persist()
            } catch {
                guard !Task.isCancelled else { return }

                turns.removeAll { $0.id == thinkingTurn.id }
                failure = error as? InferenceError
                    ?? .request(message: error.localizedDescription)
                retryRequest = request
                isThinking = false
                requestTask = nil
                persist()
            }
        }
    }

    private func conversationMessages() -> [InferenceMessage] {
        let systemMessage = InferenceMessage(
            role: .system,
            content: """
            You are Talkie, a concise and practical thinking partner. Help the user answer questions, shape rough thoughts, draft useful material, and decide clear next steps. Preserve context across turns, state uncertainty plainly, and return only the helpful response.
            """
        )
        let priorMessages = turns.compactMap { turn -> InferenceMessage? in
            guard !turn.isThinking else { return nil }
            return InferenceMessage(
                role: turn.speaker == .user ? .user : .assistant,
                content: turn.body
            )
        }
        return [systemMessage] + priorMessages
    }

    private func replaceThinkingTurn(
        id: AskAITurn.ID,
        body: String,
        providerName: String,
        modelId: String,
        latency: String,
        tokens: Int?
    ) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[index] = AskAITurn(
            id: id,
            code: turns[index].code,
            speaker: .talkie,
            body: body,
            createdAt: turns[index].createdAt,
            providerName: providerName,
            model: modelId,
            latency: latency,
            tokens: tokens,
            isThinking: false
        )
    }

    private func persist() {
        lastModel = readiness.modelLabel
        let snapshot = AskAISessionSnapshot(
            turns: turns,
            lastPreset: lastPreset,
            lastModel: lastModel,
            lastTurnID: lastTurnID,
            draftPrompt: prompt.isEmpty ? nil : prompt,
            retryMessages: retryRequest?.messages,
            failure: failure
        )
        Task { await store?.save(snapshot) }
    }

    private static func code(for index: Int) -> String {
        let digits = String(index)
        let padding = String(repeating: "0", count: max(0, 2 - digits.count))
        return "T" + padding + digits
    }

    private static func latencyString(_ value: TimeInterval) -> String {
        max(0, value).formatted(.number.precision(.fractionLength(1))) + "s"
    }

    private static func estimatedTokens(for text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
