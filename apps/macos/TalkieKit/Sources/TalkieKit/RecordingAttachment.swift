//
//  RecordingAttachment.swift
//  TalkieKit
//
//  Metadata for a file attachment on a recording.
//  Supports any file type — images, PDFs, documents, etc.
//

import Foundation

// MARK: - Attachment Kind

public enum AttachmentKind: String, Codable, Sendable {
    case image      // png, jpg, heic, gif, webp, tiff
    case pdf
    case document   // txt, rtf, md, doc, docx, pages
    case video      // mp4, mov
    case audio      // m4a, mp3, wav
    case other

    public static func from(extension ext: String) -> AttachmentKind {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "svg":
            return .image
        case "pdf":
            return .pdf
        case "txt", "text", "rtf", "md", "markdown", "doc", "docx", "pages",
             "json", "jsonl", "yaml", "yml", "toml", "xml", "html", "htm", "css",
             "csv", "tsv", "log", "swift", "js", "jsx", "ts", "tsx", "py", "rb",
             "go", "rs", "java", "kt", "kts", "c", "cc", "cpp", "cxx", "h", "hpp",
             "m", "mm", "sh", "zsh", "bash", "fish", "sql", "graphql", "proto",
             "plist", "env":
            return .document
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return .video
        case "m4a", "mp3", "wav", "aac", "flac", "ogg", "caf", "aiff", "aif":
            return .audio
        default:
            return .other
        }
    }

    public var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .video: return "film"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }
}

// MARK: - Recording Attachment

public struct RecordingAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { filename }
    public let filename: String          // Stored filename in Attachments directory
    public let originalName: String      // Original filename for display
    public let kind: AttachmentKind
    public let fileSizeBytes: Int64
    public let addedAt: Date
    public let width: Int?               // For images
    public let height: Int?              // For images

    public init(
        filename: String,
        originalName: String,
        kind: AttachmentKind,
        fileSizeBytes: Int64,
        addedAt: Date = Date(),
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.filename = filename
        self.originalName = originalName
        self.kind = kind
        self.fileSizeBytes = fileSizeBytes
        self.addedAt = addedAt
        self.width = width
        self.height = height
    }

    public static func fromArray(json: String?) -> [RecordingAttachment] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecordingAttachment].self, from: data)) ?? []
    }

    public static func toJSON(_ attachments: [RecordingAttachment]) -> String? {
        guard let data = try? JSONEncoder().encode(attachments) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
