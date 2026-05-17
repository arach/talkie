//
//  ScreenshotStorage.swift
//  TalkieKit
//
//  File management for screenshots captured during recording.
//  Screenshots are stored as PNG files in ~/Library/Application Support/Talkie/Screenshots/
//

import Foundation

public enum ScreenshotStorage {

    /// Screenshots directory
    public static var screenshotsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("Talkie/Screenshots", isDirectory: true)
    }

    public static var companionCapturesDirectory: URL {
        screenshotsDirectory
            .appending(path: "devices", directoryHint: .isDirectory)
            .appending(path: "companion", directoryHint: .isDirectory)
    }

    /// Save screenshot data and return the URL.
    public static func save(
        _ data: Data,
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
        let dir = screenshotsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = CaptureFilenameFormatter.screenshotFilename(
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
            try data.write(to: url)
            return url
        } catch {
            Log(.system).error("Failed to save screenshot: \(error)")
            return nil
        }
    }

    /// Save a standalone screenshot (not tied to a recording).
    public static func saveStandalone(
        _ data: Data,
        capturedAt: Date = Date(),
        captureMode: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil,
        relativeDirectory: String? = nil
    ) -> URL? {
        let dir = storageDirectory(relativeDirectory: relativeDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = CaptureFilenameFormatter.screenshotFilename(
            id: UUID(),
            capturedAt: capturedAt,
            mode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        let url = dir.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            return url
        } catch {
            Log(.system).error("Failed to save standalone screenshot: \(error)")
            return nil
        }
    }

    private static func storageDirectory(relativeDirectory: String?) -> URL {
        guard let relativeDirectory else { return screenshotsDirectory }

        let parts = relativeDirectory
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        return parts.reduce(screenshotsDirectory) { partialResult, component in
            partialResult.appending(path: component, directoryHint: .isDirectory)
        }
    }

    /// List all screenshots for a recording, sorted by timestamp
    public static func screenshots(for recordingId: UUID) -> [(url: URL, timestampMs: Int)] {
        let dir = screenshotsDirectory
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
                return name.hasPrefix(legacyPrefix.lowercased()) || name.contains(readableID)
            }
            .compactMap { url -> (url: URL, timestampMs: Int)? in
                // Legacy: {uuid}_{timestampMs}[_{index}].png
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

    /// Delete all screenshots for a recording
    public static func delete(for recordingId: UUID) {
        for item in screenshots(for: recordingId) {
            try? FileManager.default.removeItem(at: item.url)
        }
    }
}
