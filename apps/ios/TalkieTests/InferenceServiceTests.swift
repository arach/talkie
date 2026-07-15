import XCTest
@testable import Talkie_iOS

@MainActor
final class InferenceServiceTests: XCTestCase {
    private let messages = [
        InferenceMessage(role: .system, content: "Be useful"),
        InferenceMessage(role: .user, content: "Hello"),
    ]

    func testDirectProviderUsesPhoneTransport() async throws {
        var macWasCalled = false
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { Self.openAIProvider },
                isMacPaired: { true },
                directComplete: { provider, messages in
                    XCTAssertEqual(provider.providerId, "openai")
                    XCTAssertEqual(messages.map(\.role), [.system, .user])
                    return "Direct response"
                },
                macInference: { _ in
                    macWasCalled = true
                    return Self.macResult
                }
            )
        )

        let result = try await service.execute(messages: messages)

        XCTAssertEqual(result.content, "Direct response")
        XCTAssertEqual(result.route, .iPhone)
        XCTAssertFalse(macWasCalled)
    }

    func testPairedMacUsesReusableGatewayTransport() async throws {
        var directWasCalled = false
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { nil },
                isMacPaired: { true },
                directComplete: { _, _ in
                    directWasCalled = true
                    return "Unexpected"
                },
                macInference: { messages in
                    XCTAssertEqual(messages.map(\.role), [.system, .user])
                    return Self.macResult
                }
            )
        )

        let result = try await service.execute(messages: messages)

        XCTAssertEqual(result, Self.macResult)
        XCTAssertFalse(directWasCalled)
    }

    func testMissingProviderReportsConfigurationRequired() async {
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { nil },
                isMacPaired: { false },
                directComplete: { _, _ in "Unexpected" },
                macInference: { _ in Self.macResult }
            )
        )

        XCTAssertEqual(service.readiness, .configurationRequired)
        await assertExecutionError(.configurationRequired) {
            try await service.execute(messages: messages)
        }
    }

    func testPairedMacWithoutProviderRequestsConfiguration() async {
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { nil },
                isMacPaired: { true },
                directComplete: { _, _ in "Unexpected" },
                macInference: { _ in throw InferenceError.configurationRequired }
            )
        )

        await assertExecutionError(.configurationRequired) {
            try await service.execute(messages: messages)
        }
    }

    func testAuthenticationFailureRequestsCredentialRecovery() async {
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { Self.openAIProvider },
                isMacPaired: { false },
                directComplete: { _, _ in
                    throw DirectAIError.apiError(statusCode: 401, message: "Invalid key")
                },
                macInference: { _ in Self.macResult }
            )
        )

        await assertExecutionError(.credentialsRejected(providerName: "OpenAI")) {
            try await service.execute(messages: messages)
        }
    }

    func testNetworkFailureRemainsRetryable() async {
        let service = InferenceService(
            dependencies: .init(
                phoneProvider: { Self.openAIProvider },
                isMacPaired: { false },
                directComplete: { _, _ in
                    throw URLError(.notConnectedToInternet)
                },
                macInference: { _ in Self.macResult }
            )
        )

        do {
            _ = try await service.execute(messages: messages)
            XCTFail("Expected a network error")
        } catch let error as InferenceError {
            guard case .network = error else {
                return XCTFail("Expected network error, got \(error)")
            }
        } catch {
            XCTFail("Expected InferenceError, got \(error)")
        }
    }

    private func assertExecutionError(
        _ expected: InferenceError,
        operation: () async throws -> InferenceResult
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as InferenceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected InferenceError, got \(error)")
        }
    }

    private static let openAIProvider = ComposeBorrowedProvider(
        providerId: "openai",
        providerName: "OpenAI",
        modelId: "gpt-5.5",
        apiKey: "sk-test",
        assistantPrompt: "Test",
        fallbackReason: nil
    )

    private static let macResult = InferenceResult(
        content: "Mac response",
        providerName: "Anthropic",
        modelId: "claude-sonnet-4-6",
        route: .mac
    )
}
