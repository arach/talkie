//
//  TranscriptionService.swift
//  TalkieCore
//
//  Shared transcription protocol for Whisper, Parakeet, etc.
//

import Foundation

public struct TranscriptionRequest {
    public let audioData: Data
    public let languageHint: String?
    public let isLive: Bool

    public init(audioData: Data, languageHint: String? = nil, isLive: Bool = false) {
        self.audioData = audioData
        self.languageHint = languageHint
        self.isLive = isLive
    }
}

public struct Transcript {
    public let text: String
    public let confidence: Float?

    public init(text: String, confidence: Float? = nil) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol TranscriptionService: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}
