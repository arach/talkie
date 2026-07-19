import Foundation

enum InferenceError: Codable, LocalizedError, Equatable, Sendable {
    case configurationRequired
    case credentialsRejected(providerName: String)
    case network(message: String)
    case request(message: String)

    var errorDescription: String? {
        switch self {
        case .configurationRequired:
            return "Add an AI key on this iPhone or pair a Mac before sending."
        case .credentialsRejected(let providerName):
            return "\(providerName) rejected its saved credential. Update the key and try again."
        case .network(let message):
            return message
        case .request(let message):
            return message
        }
    }

    var needsConfiguration: Bool {
        switch self {
        case .configurationRequired, .credentialsRejected:
            return true
        case .network, .request:
            return false
        }
    }
}
