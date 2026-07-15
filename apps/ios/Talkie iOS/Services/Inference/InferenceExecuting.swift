import Foundation

@MainActor
protocol InferenceExecuting: AnyObject {
    var readiness: InferenceReadiness { get }
    func execute(messages: [InferenceMessage]) async throws -> InferenceResult
}
