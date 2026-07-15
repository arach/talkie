import XCTest
@testable import Talkie_iOS

@MainActor
final class AskAISessionTests: XCTestCase {
    func testMissingConfigurationKeepsDraftAndCreatesNoFailedTurn() {
        let executor = SequencedInferenceExecutor(
            readiness: .configurationRequired,
            outcomes: []
        )
        let session = AskAISession(executor: executor, store: nil)
        session.updatePrompt("Keep this prompt")

        session.send()

        XCTAssertEqual(session.prompt, "Keep this prompt")
        XCTAssertEqual(session.failure, .configurationRequired)
        XCTAssertTrue(session.turns.isEmpty)
    }

    func testRetryReusesFailedMessagesWithoutCreatingAnErrorAssistantTurn() async throws {
        let executor = SequencedInferenceExecutor(
            readiness: .ready(providerName: "OpenAI", modelId: "gpt-5.5", route: .iPhone),
            outcomes: [
                .failure(.network(message: "Connection lost")),
                .success(Self.successResult),
            ]
        )
        let session = AskAISession(executor: executor, store: nil)
        session.updatePrompt("Outline the launch")

        session.send()
        try await waitUntilSettled(session)

        XCTAssertEqual(session.failure, .network(message: "Connection lost"))
        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns.first?.speaker, .user)
        XCTAssertTrue(session.canRetry)

        session.retry()
        try await waitUntilSettled(session)

        XCTAssertNil(session.failure)
        XCTAssertEqual(session.turns.count, 2)
        XCTAssertEqual(session.turns.last?.speaker, .talkie)
        XCTAssertEqual(session.turns.last?.body, "Here is the plan")
        XCTAssertEqual(executor.receivedMessages.count, 2)
        XCTAssertEqual(executor.receivedMessages[0], executor.receivedMessages[1])
    }

    func testConversationUsesStructuredRolesAcrossTurns() async throws {
        let executor = SequencedInferenceExecutor(
            readiness: .ready(providerName: "OpenAI", modelId: "gpt-5.5", route: .iPhone),
            outcomes: [.success(Self.successResult), .success(Self.successResult)]
        )
        let session = AskAISession(executor: executor, store: nil)

        session.updatePrompt("First question")
        session.send()
        try await waitUntilSettled(session)

        session.updatePrompt("Follow-up question")
        session.send()
        try await waitUntilSettled(session)

        XCTAssertEqual(
            executor.receivedMessages[1].map(\.role),
            [.system, .user, .assistant, .user]
        )
        XCTAssertEqual(executor.receivedMessages[1].last?.content, "Follow-up question")
    }

    private func waitUntilSettled(_ session: AskAISession) async throws {
        for _ in 0..<100 where session.isThinking {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(session.isThinking, "Inference did not settle in time")
    }

    private static let successResult = InferenceResult(
        content: "Here is the plan",
        providerName: "OpenAI",
        modelId: "gpt-5.5",
        route: .iPhone
    )
}

@MainActor
private final class SequencedInferenceExecutor: InferenceExecuting {
    var readiness: InferenceReadiness
    private var outcomes: [Result<InferenceResult, InferenceError>]
    private(set) var receivedMessages: [[InferenceMessage]] = []

    init(
        readiness: InferenceReadiness,
        outcomes: [Result<InferenceResult, InferenceError>]
    ) {
        self.readiness = readiness
        self.outcomes = outcomes
    }

    func execute(messages: [InferenceMessage]) async throws -> InferenceResult {
        receivedMessages.append(messages)
        guard !outcomes.isEmpty else {
            throw InferenceError.request(message: "No test outcome")
        }
        return try outcomes.removeFirst().get()
    }
}
