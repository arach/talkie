import Foundation

struct InferenceResult: Codable, Equatable, Sendable {
    enum Route: String, Codable, Equatable, Sendable {
        case iPhone
        case mac
    }

    let content: String
    let providerName: String
    let modelId: String
    let route: Route
}
