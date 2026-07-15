import Foundation

enum InferenceReadiness: Equatable, Sendable {
    case ready(providerName: String, modelId: String?, route: InferenceResult.Route)
    case configurationRequired

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var modelLabel: String? {
        guard case .ready(let providerName, let modelId, _) = self else { return nil }
        return modelId?.isEmpty == false ? modelId : providerName
    }
}
