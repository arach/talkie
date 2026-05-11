//
//  RecordingClip.swift
//  TalkieKit
//
//  Metadata for a video clip captured via the face camera bubble.
//  Mirrors RecordingScreenshot in TranscriptionSegments.swift.
//

import Foundation

// MARK: - Recording Clip

/// Metadata for a video clip captured during recording
public struct RecordingClip: Codable, Sendable, Equatable {
    public let filename: String
    public let timestampMs: Int       // ms from recording start
    public let durationMs: Int        // clip duration in ms
    public let width: Int?
    public let height: Int?
    public let captureMode: String?   // "camera", "region", "fullscreen", "window"
    public let windowTitle: String?
    public let appName: String?
    public let displayName: String?

    public init(
        filename: String,
        timestampMs: Int,
        durationMs: Int,
        width: Int? = nil,
        height: Int? = nil,
        captureMode: String? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil
    ) {
        self.filename = filename
        self.timestampMs = timestampMs
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.captureMode = captureMode
        self.windowTitle = windowTitle
        self.appName = appName
        self.displayName = displayName
    }

    /// Decode array from JSON string
    public static func fromArray(json: String?) -> [RecordingClip] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecordingClip].self, from: data)) ?? []
    }

    /// Encode array to JSON string
    public static func toJSON(_ clips: [RecordingClip]) -> String? {
        guard let data = try? JSONEncoder().encode(clips) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
