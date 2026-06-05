//
//  PasteBarResult.swift
//  Talkie
//
//  Paste format variants for the Quick Paste chord (Hyper+V).
//

import AppKit
import Foundation
import ImageIO
import TalkieKit

// MARK: - Paste Candidate

struct PasteCandidate: Identifiable {
    let id: String
    let fileURL: URL
    let capturedAt: Date
    let image: NSImage?
    let width: Int
    let height: Int
    let displayName: String?

    var previewText: String? { nil }
    var isClip: Bool { false }
    var tempURL: URL { fileURL }

    static func recentScreenshots(limit: Int = 5) -> [PasteCandidate] {
        recentImageURLs(limit: limit).compactMap(makeCandidate)
    }

    private static func recentImageURLs(limit: Int) -> [URL] {
        let directory = ScreenshotStorage.screenshotsDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }
            candidates.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
    }

    private static func makeCandidate(for url: URL) -> PasteCandidate? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let capturedAt = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
        let info = imageInfo(for: url)

        return PasteCandidate(
            id: url.path,
            fileURL: url,
            capturedAt: capturedAt,
            image: info.image,
            width: info.width,
            height: info.height,
            displayName: url.deletingPathExtension().lastPathComponent
        )
    }

    private static func imageInfo(for url: URL) -> (image: NSImage?, width: Int, height: Int) {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return (nil, 0, 0)
            }

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int
            let height = properties?[kCGImagePropertyPixelHeight] as? Int

            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 420,
            ] as CFDictionary

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return (nil, width ?? 0, height ?? 0)
            }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return (image, width ?? cgImage.width, height ?? cgImage.height)
        }
    }
}

// MARK: - Paste Format

enum PasteFormat: String, CaseIterable {
    case image    // PNG data → pasteboard .png
    case filePath // Absolute file path string
    case url      // file:// URL for the stored capture
    case base64   // data:image/png;base64,<encoded>
    case visionDescription // VLM UI description text
    case dragFile // Programmatic drag session with file

    var label: String {
        switch self {
        case .image:    "image"
        case .filePath: "path"
        case .url:      "url"
        case .base64:   "base64"
        case .visionDescription: "describe"
        case .dragFile: "drag"
        }
    }

    var shortLabel: String {
        switch self {
        case .image:    "IMG"
        case .filePath: "PATH"
        case .url:      "URL"
        case .base64:   "B64"
        case .visionDescription: "VLM"
        case .dragFile: "DRAG"
        }
    }

    var modifierSymbol: String {
        switch self {
        case .image:    ""
        case .filePath: "⇧"
        case .url:      "⌥"
        case .base64:   "⌃"
        case .visionDescription: "⇧⌥"
        case .dragFile: "⌘"
        }
    }

    /// Whether this format pastes via Cmd+V or uses a different delivery mechanism.
    var pastesByKeyboard: Bool {
        switch self {
        case .image, .filePath, .url, .base64, .visionDescription: true
        case .dragFile: false
        }
    }
}

// MARK: - Paste Bar Result

struct PasteBarResult {
    let item: PasteCandidate
    let format: PasteFormat
}
