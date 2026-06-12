//
//  CaptureMediaFileResolver.swift
//  TalkieKit
//
//  Resolves persisted capture media pointers to files on disk.
//

import Foundation

public enum CaptureMediaAsset: Equatable, Sendable {
    case image(URL)
    case video(URL)

    public var url: URL {
        switch self {
        case .image(let url), .video(let url):
            return url
        }
    }

    public var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

public enum CaptureMediaFileResolver {
    public static var applicationSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static var appSupportTalkieDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Talkie", directoryHint: .isDirectory)
    }

    public static var trayScreenshotsDirectory: URL {
        appSupportTalkieDirectory
            .appending(path: "Tray", directoryHint: .isDirectory)
            .appending(path: "screenshots", directoryHint: .isDirectory)
    }

    public static var trayClipsDirectory: URL {
        appSupportTalkieDirectory
            .appending(path: "Tray", directoryHint: .isDirectory)
            .appending(path: "clips", directoryHint: .isDirectory)
    }

    public static var attachmentsDirectory: URL {
        AttachmentStorage.attachmentsDirectory
    }

    public static func primaryMedia(for object: TalkieObject) -> CaptureMediaAsset? {
        if let shot = object.screenshots.first,
           let url = screenshotURL(filename: shot.filename) {
            return .image(url)
        }

        if let clip = object.clips.first,
           let url = clipURL(filename: clip.filename) {
            return .video(url)
        }

        if let context = object.visualContexts.first {
            if let url = visualContextSourceURL(for: context) {
                return .video(url)
            }
            if let url = visualContextContactSheetURL(for: context) {
                return .image(url)
            }
        }

        if let attachmentAsset = object.attachments.lazy.compactMap(mediaAsset(for:)).first {
            return attachmentAsset
        }

        return nil
    }

    public static func screenshotURL(filename: String) -> URL? {
        existingFileURL(
            filename: filename,
            searchDirectories: [
                ScreenshotStorage.screenshotsDirectory,
                trayScreenshotsDirectory,
                appSupportTalkieDirectory,
                applicationSupportDirectory,
            ]
        )
    }

    public static func clipURL(filename: String) -> URL? {
        existingFileURL(
            filename: filename,
            searchDirectories: [
                VideoClipStorage.videosDirectory,
                trayClipsDirectory,
                appSupportTalkieDirectory,
                applicationSupportDirectory,
            ]
        )
    }

    public static func mediaAsset(for attachment: RecordingAttachment) -> CaptureMediaAsset? {
        guard let url = attachmentURL(filename: attachment.filename) else { return nil }

        switch mediaKind(for: attachment) {
        case .image:
            return .image(url)
        case .video:
            return .video(url)
        case .audio, .document, .pdf, .other:
            return nil
        }
    }

    public static func attachmentURL(filename: String) -> URL? {
        existingFileURL(
            filename: filename,
            searchDirectories: [
                attachmentsDirectory,
                appSupportTalkieDirectory,
                applicationSupportDirectory,
            ]
        )
    }

    public static func visualContextSourceURL(for context: RecordingVisualContext) -> URL? {
        let bundleURL = VisualContextStorage.bundleURL(for: context)
        let sourceURL = bundleURL.appendingPathComponent(context.sourceClipFilename)
        if FileManager.default.fileExists(atPath: sourceURL.path) { return sourceURL }

        return existingFileURL(
            filename: context.sourceClipFilename,
            searchDirectories: [
                bundleURL,
                VideoClipStorage.videosDirectory,
                trayClipsDirectory,
                appSupportTalkieDirectory,
                applicationSupportDirectory,
            ]
        )
    }

    public static func visualContextContactSheetURL(for context: RecordingVisualContext) -> URL? {
        guard let filename = context.contactSheetFilename else { return nil }
        let bundleURL = VisualContextStorage.bundleURL(for: context)
        return existingFileURL(
            filename: filename,
            searchDirectories: [
                bundleURL,
                appSupportTalkieDirectory,
                applicationSupportDirectory,
            ]
        )
    }

    private static func mediaKind(for attachment: RecordingAttachment) -> AttachmentKind {
        switch attachment.kind {
        case .image, .video:
            return attachment.kind
        case .audio, .document, .pdf, .other:
            let filenameExtension = (attachment.filename as NSString).pathExtension
            let originalExtension = (attachment.originalName as NSString).pathExtension
            let ext = originalExtension.isEmpty ? filenameExtension : originalExtension
            let inferredKind = AttachmentKind.from(extension: ext)
            guard inferredKind == .image || inferredKind == .video else {
                return attachment.kind
            }
            return inferredKind
        }
    }

    public static func existingFileURL(filename: String, searchDirectories: [URL]) -> URL? {
        let fileManager = FileManager.default
        let expandedFilename = (filename as NSString).expandingTildeInPath
        let absoluteURL = URL(fileURLWithPath: expandedFilename)

        if expandedFilename.hasPrefix("/"),
           fileManager.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        let pathComponents = filename
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        var candidates: [URL] = []
        if !pathComponents.isEmpty {
            candidates += searchDirectories.map { directory in
                pathComponents.reduce(directory) { partial, component in
                    partial.appending(path: component)
                }
            }

            if let lastComponent = pathComponents.last {
                candidates += searchDirectories.map { directory in
                    directory.appending(path: lastComponent)
                }
            }
        }

        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }
}
