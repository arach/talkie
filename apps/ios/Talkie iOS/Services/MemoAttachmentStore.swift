//
//  MemoAttachmentStore.swift
//  Talkie iOS
//
//  File-backed image attachments for voice memos.
//

import Foundation
import UIKit

final class MemoAttachmentStore {
    static let shared = MemoAttachmentStore()

    private let fileManager = FileManager.default

    private init() {}

    private var attachmentsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("MemoAttachments", isDirectory: true)
    }

    func attachments(for memoID: UUID) -> [MemoImageAttachment] {
        ensureDirectoryExists()

        let manifestURL = manifestURL(for: memoID)
        guard
            let data = try? Data(contentsOf: manifestURL),
            let attachments = try? JSONDecoder().decode([MemoImageAttachment].self, from: data)
        else {
            return []
        }

        return attachments.sorted { $0.addedAt > $1.addedAt }
    }

    @discardableResult
    func saveImage(data: Data, preferredName: String? = nil, memoID: UUID) -> MemoImageAttachment? {
        ensureDirectoryExists()

        guard let normalized = normalizedImageData(from: data) else {
            AppLogger.persistence.warning("Could not normalize memo attachment image")
            return nil
        }

        let baseName = sanitizedBaseName(from: preferredName) ?? defaultBaseName(for: normalized.fileExtension)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "\(memoID.uuidString)_\(timestamp)_\(baseName).\(normalized.fileExtension)"
        let destinationURL = attachmentsDirectory.appendingPathComponent(filename, isDirectory: false)

        do {
            try normalized.data.write(to: destinationURL, options: .atomic)

            let attachment = MemoImageAttachment(
                filename: filename,
                originalName: "\(baseName).\(normalized.fileExtension)",
                fileSizeBytes: Int64(normalized.data.count),
                pixelWidth: normalized.pixelWidth,
                pixelHeight: normalized.pixelHeight
            )

            var current = attachments(for: memoID)
            current.insert(attachment, at: 0)
            try saveManifest(current, for: memoID)
            return attachment
        } catch {
            AppLogger.persistence.error("Failed to save memo attachment: \(error.localizedDescription)")
            return nil
        }
    }

    func delete(_ attachment: MemoImageAttachment, memoID: UUID) {
        let fileURL = url(for: attachment)
        try? fileManager.removeItem(at: fileURL)

        var current = attachments(for: memoID)
        current.removeAll { $0.id == attachment.id }
        try? saveManifest(current, for: memoID)
    }

    func deleteAll(for memoID: UUID) {
        let current = attachments(for: memoID)

        for attachment in current {
            try? fileManager.removeItem(at: url(for: attachment))
        }

        try? fileManager.removeItem(at: manifestURL(for: memoID))
    }

    func url(for attachment: MemoImageAttachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.filename, isDirectory: false)
    }

    func image(for attachment: MemoImageAttachment) -> UIImage? {
        UIImage(contentsOfFile: url(for: attachment).path)
    }

    private func manifestURL(for memoID: UUID) -> URL {
        attachmentsDirectory.appendingPathComponent("\(memoID.uuidString).json", isDirectory: false)
    }

    private func saveManifest(_ attachments: [MemoImageAttachment], for memoID: UUID) throws {
        let data = try JSONEncoder().encode(attachments)
        try data.write(to: manifestURL(for: memoID), options: .atomic)
    }

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    private func sanitizedBaseName(from preferredName: String?) -> String? {
        guard let preferredName, !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmed = preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let basename = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        let allowed = basename.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                return Character(scalar)
            }
            return "_"
        }
        let cleaned = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? nil : cleaned
    }

    private func defaultBaseName(for fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let prefix = fileExtension == "png" ? "Screenshot" : "Image"
        return "\(prefix)_\(formatter.string(from: Date()))"
    }

    private func normalizedImageData(from sourceData: Data) -> (data: Data, fileExtension: String, pixelWidth: Int?, pixelHeight: Int?)? {
        guard let image = UIImage(data: sourceData) else { return nil }

        let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)

        if image.hasAlphaChannel, let pngData = image.pngData() {
            return (pngData, "png", pixelWidth, pixelHeight)
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.92) else { return nil }
        return (jpegData, "jpg", pixelWidth, pixelHeight)
    }
}

private extension UIImage {
    var hasAlphaChannel: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }

        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}
