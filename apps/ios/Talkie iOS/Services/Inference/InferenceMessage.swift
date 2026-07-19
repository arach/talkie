import Foundation

struct InferenceMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}
