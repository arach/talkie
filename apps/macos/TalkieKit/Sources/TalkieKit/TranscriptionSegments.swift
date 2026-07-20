//
//  TranscriptionSegments.swift
//  TalkieKit
//
//  Word-level timing data from transcription engines.
//  Unified abstraction over WhisperKit WordTiming and Parakeet TokenTiming.
//

import Foundation

// MARK: - Word Segment

/// A single word with its timing relative to audio start
public struct WordSegment: Codable, Sendable, Equatable {
    public let word: String
    public let start: Double    // seconds from audio start
    public let end: Double      // seconds from audio start
    public let confidence: Float?

    public init(word: String, start: Double, end: Double, confidence: Float? = nil) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - Timed Transcription

/// Full transcription with word-level timing data
public struct TimedTranscription: Codable, Sendable {
    public let text: String
    public let words: [WordSegment]

    public init(text: String, words: [WordSegment]) {
        self.text = text
        self.words = words
    }

    /// Encode to Data for XPC transport
    public func toData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Encode to JSON string for DB storage
    public func toJSON() -> String? {
        guard let data = toData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode from Data (XPC transport)
    public static func from(data: Data) -> TimedTranscription? {
        try? JSONDecoder().decode(TimedTranscription.self, from: data)
    }

    /// Decode from JSON string (DB storage)
    public static func from(json: String?) -> TimedTranscription? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return from(data: data)
    }
}

// MARK: - Recording Screenshot

/// Metadata for a screenshot captured during recording
public struct RecordingScreenshot: Codable, Sendable, Equatable {
    public let filename: String
    public let timestampMs: Int       // ms from recording start
    public let captureMode: String    // "region", "scrolling-region", "fullscreen", "window"
    public let width: Int?
    public let height: Int?
    public let windowTitle: String?
    public let appName: String?
    /// Bundle identifier of the app that was active when the capture was
    /// taken. Lets the UI disambiguate apps that share a display name and
    /// resolve an icon. Optional so older records decode unchanged.
    public let appBundleID: String?
    public let displayName: String?

    public init(
        filename: String, timestampMs: Int, captureMode: String,
        width: Int? = nil, height: Int? = nil,
        windowTitle: String? = nil, appName: String? = nil,
        appBundleID: String? = nil, displayName: String? = nil
    ) {
        self.filename = filename
        self.timestampMs = timestampMs
        self.captureMode = captureMode
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.appName = appName
        self.appBundleID = appBundleID
        self.displayName = displayName
    }

    /// Decode array from JSON string
    public static func fromArray(json: String?) -> [RecordingScreenshot] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecordingScreenshot].self, from: data)) ?? []
    }

    /// Encode array to JSON string
    public static func toJSON(_ screenshots: [RecordingScreenshot]) -> String? {
        guard let data = try? JSONEncoder().encode(screenshots) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
