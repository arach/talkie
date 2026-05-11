import Foundation

/// Event emitted by streaming ASR pods and forwarded through engine transports.
public struct StreamingASREvent: Codable, Sendable {
    public let type: String
    public let text: String?
    public let confidence: Double?
    public let isFinal: Bool?
    public let silenceDuration: Double?
    public let message: String?
    public let isFatal: Bool?

    public init(
        type: String,
        text: String? = nil,
        confidence: Double? = nil,
        isFinal: Bool? = nil,
        silenceDuration: Double? = nil,
        message: String? = nil,
        isFatal: Bool? = nil
    ) {
        self.type = type
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
        self.silenceDuration = silenceDuration
        self.message = message
        self.isFatal = isFatal
    }
}
