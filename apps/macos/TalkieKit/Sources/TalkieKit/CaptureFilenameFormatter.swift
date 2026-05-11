//
//  CaptureFilenameFormatter.swift
//  TalkieKit
//
//  Human-readable filenames for screenshot and screen/camera clip assets.
//

import Foundation

public enum CaptureFilenameFormatter {
    public static func screenshotFilename(
        id: UUID,
        capturedAt: Date = Date(),
        timestampMs: Int? = nil,
        index: Int = 0,
        mode: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil
    ) -> String {
        filename(
            prefix: "Talkie Capture",
            extension: "png",
            id: id,
            capturedAt: capturedAt,
            timestampMs: timestampMs,
            index: index,
            mode: mode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
    }

    public static func clipFilename(
        id: UUID,
        capturedAt: Date = Date(),
        timestampMs: Int? = nil,
        index: Int = 0,
        mode: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil
    ) -> String {
        let prefix = mode == "camera" ? "Talkie Camera Clip" : "Talkie Screen Clip"
        return filename(
            prefix: prefix,
            extension: "mp4",
            id: id,
            capturedAt: capturedAt,
            timestampMs: timestampMs,
            index: index,
            mode: mode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
    }

    private static func filename(
        prefix: String,
        extension ext: String,
        id: UUID,
        capturedAt: Date,
        timestampMs: Int?,
        index: Int,
        mode: String?,
        width: Int?,
        height: Int?,
        windowTitle: String?,
        appName: String?,
        displayName: String?
    ) -> String {
        let dimensions = dimensions(width: width, height: height)
        let identity = identity(id: id, timestampMs: timestampMs, index: index)
        let parts = [
            prefix,
            timestampString(from: capturedAt),
            contextSummary(mode: mode, windowTitle: windowTitle, appName: appName, displayName: displayName),
            dimensions,
            identity,
        ].compactMap { sanitize($0, maxLength: 72) }

        return "\(parts.joined(separator: " - ")).\(ext)"
    }

    private static func contextSummary(
        mode: String?,
        windowTitle: String?,
        appName: String?,
        displayName: String?
    ) -> String? {
        switch mode {
        case "window":
            return joined(["Window", appName, distinct(windowTitle, from: appName)])
        case "region":
            return "Region"
        case "fullscreen":
            return joined(["Fullscreen", displayName])
        case "camera":
            return "Camera"
        case "bookmark":
            return joined(["Bookmark", windowTitle, appName])
        case "capture":
            return "Capture"
        case let mode?:
            return mode.isEmpty ? nil : mode.capitalized
        case nil:
            return nil
        }
    }

    private static func identity(id: UUID, timestampMs: Int?, index: Int) -> String {
        var parts = [String(id.uuidString.prefix(8)).lowercased()]
        if let timestampMs {
            parts.append("t\(timestampMs)ms")
        }
        if index > 0 {
            parts.append("part\(index + 1)")
        }
        return parts.joined(separator: " ")
    }

    private static func dimensions(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }

    private static func distinct(_ value: String?, from other: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let other, !other.isEmpty else { return value }
        return value.localizedCaseInsensitiveCompare(other) == .orderedSame ? nil : value
    }

    private static func joined(_ parts: [String?]) -> String? {
        let compact = parts.compactMap { sanitize($0, maxLength: 48) }
        return compact.isEmpty ? nil : compact.joined(separator: " ")
    }

    private static func sanitize(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_."))
        let mapped = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : " "
        }.joined()
        let compact = mapped
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }
        return String(compact.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
