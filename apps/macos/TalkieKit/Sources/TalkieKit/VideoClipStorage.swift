//
//  VideoClipStorage.swift
//  TalkieKit
//
//  File management for video clips captured via the face camera bubble.
//  Clips are stored as MP4 files in ~/Library/Application Support/Talkie/Videos/
//  Mirrors ScreenshotStorage.swift.
//

import Foundation
import TalkieCore

public enum VideoClipStorage {

    /// Videos directory
    public static var videosDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("Talkie/Videos", isDirectory: true)
    }

    /// Save a video clip file and return the permanent URL.
    public static func save(
        _ tempURL: URL,
        recordingId: UUID,
        timestampMs: Int,
        index: Int = 0,
        capturedAt: Date = Date(),
        captureMode: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil
    ) -> URL? {
        let dir = videosDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = CaptureFilenameFormatter.clipFilename(
            id: recordingId,
            capturedAt: capturedAt,
            timestampMs: timestampMs,
            index: index,
            mode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        let url = dir.appendingPathComponent(filename)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: tempURL, to: url)
            return url
        } catch {
            Log(.system).error("Failed to save video clip: \(error)")
            return nil
        }
    }

    /// List all clips for a recording, sorted by timestamp
    public static func clips(for recordingId: UUID) -> [(url: URL, timestampMs: Int)] {
        let dir = videosDirectory
        let legacyPrefix = recordingId.uuidString
        let readableID = String(recordingId.uuidString.prefix(8)).lowercased()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter {
                let name = $0.lastPathComponent.lowercased()
                return $0.pathExtension == "mp4"
                    && (name.hasPrefix(legacyPrefix.lowercased()) || name.contains(readableID))
            }
            .compactMap { url -> (url: URL, timestampMs: Int)? in
                // Legacy: {uuid}_{timestampMs}[_{index}].mp4
                let name = url.deletingPathExtension().lastPathComponent
                let parts = name.split(separator: "_")
                if name.lowercased().hasPrefix(legacyPrefix.lowercased()),
                   parts.count >= 2,
                   let ts = Int(parts[1]) {
                    return (url: url, timestampMs: ts)
                }

                // Readable: ... {shortID} t{timestampMs}ms ...
                let tokens = name.split(whereSeparator: \.isWhitespace)
                let timestamp = tokens.compactMap { token -> Int? in
                    guard token.hasPrefix("t"), token.hasSuffix("ms") else { return nil }
                    return Int(token.dropFirst().dropLast(2))
                }.first ?? 0
                return (url: url, timestampMs: timestamp)
            }
            .sorted { $0.timestampMs < $1.timestampMs }
    }

    /// Delete all clips for a recording
    public static func delete(for recordingId: UUID) {
        for item in clips(for: recordingId) {
            try? FileManager.default.removeItem(at: item.url)
        }
    }
}
