import Foundation

/// Reusable inference router shared by Ask AI and future phone features.
/// Intent-specific surfaces provide structured messages; this service only
/// chooses a transport and normalizes provider, network, and credential errors.
@MainActor
final class InferenceService: InferenceExecuting {
    struct Dependencies {
        let phoneProvider: () -> ComposeBorrowedProvider?
        let isMacPaired: () -> Bool
        let directComplete: (ComposeBorrowedProvider, [InferenceMessage]) async throws -> String
        let macInference: ([InferenceMessage]) async throws -> InferenceResult
    }

    static let shared = InferenceService()

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? Self.liveDependencies()
    }

    var readiness: InferenceReadiness {
        if let provider = dependencies.phoneProvider() {
            return .ready(
                providerName: provider.providerName,
                modelId: provider.modelId,
                route: .iPhone
            )
        }

        if dependencies.isMacPaired() {
            return .ready(providerName: "Paired Mac", modelId: nil, route: .mac)
        }

        return .configurationRequired
    }

    func execute(messages: [InferenceMessage]) async throws -> InferenceResult {
        if let provider = dependencies.phoneProvider() {
            do {
                let content = try await dependencies.directComplete(provider, messages)
                return InferenceResult(
                    content: content,
                    providerName: provider.providerName,
                    modelId: provider.modelId,
                    route: .iPhone
                )
            } catch {
                throw Self.map(error, providerName: provider.providerName)
            }
        }

        guard dependencies.isMacPaired() else {
            throw InferenceError.configurationRequired
        }

        do {
            return try await dependencies.macInference(messages)
        } catch {
            throw Self.map(error, providerName: "Paired Mac")
        }
    }

    private static func liveDependencies() -> Dependencies {
        Dependencies(
            phoneProvider: {
                if ProcessInfo.processInfo.arguments.contains("--askaiNoProviders") { return nil }
                return TalkieAIProviderResolver.shared.configuredProvider()
            },
            isMacPaired: {
                if ProcessInfo.processInfo.arguments.contains("--askaiNoProviders") { return false }
                return BridgeManager.shared.isPaired
            },
            directComplete: { provider, messages in
                try await DirectAIClient.shared.complete(provider: provider, messages: messages)
            },
            macInference: { messages in
                try await BridgeManager.shared.configuredInference(messages: messages)
            }
        )
    }

    private static func map(_ error: Error, providerName: String) -> InferenceError {
        if let inferenceError = error as? InferenceError {
            return inferenceError
        }

        if let directError = error as? DirectAIError {
            switch directError {
            case .apiError(let statusCode, _) where statusCode == 401 || statusCode == 403:
                return .credentialsRejected(providerName: providerName)
            default:
                return .request(message: directError.localizedDescription)
            }
        }

        if let urlError = error as? URLError {
            return .network(message: urlError.localizedDescription)
        }

        if let bridgeError = error as? BridgeError {
            switch bridgeError {
            case .notConfigured:
                return .configurationRequired
            case .connectionFailed:
                return .network(message: bridgeError.localizedDescription)
            case .httpError(let statusCode, _) where statusCode == 401 || statusCode == 403:
                return .credentialsRejected(providerName: providerName)
            default:
                return .request(message: bridgeError.localizedDescription)
            }
        }

        return .request(message: error.localizedDescription)
    }
}
