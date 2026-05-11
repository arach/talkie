//
//  AttachmentStorage.swift
//  TalkieKit
//
//  File management for attachments added to recordings.
//  Attachments are stored in ~/Library/Application Support/Talkie/Attachments/
//

import Foundation

public enum AttachmentStorage {

    public static var attachmentsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("Talkie/Attachments", isDirectory: true)
    }

    /// Copy a file into attachment storage. Returns the stored filename.
    /// Filename: {recordingId}_{timestamp}_{originalName}
    public static func save(from sourceURL: URL, recordingId: UUID) -> (filename: String, size: Int64)? {
        let dir = attachmentsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let sanitized = sourceURL.lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(recordingId.uuidString)_\(timestamp)_\(sanitized)"
        let destURL = dir.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
            let size = (attrs[.size] as? Int64) ?? 0
            return (filename, size)
        } catch {
            Log(.system).error("Failed to save attachment: \(error)")
            return nil
        }
    }

    /// Save raw data as an attachment. Returns the stored filename.
    public static func save(data: Data, originalName: String, recordingId: UUID) -> (filename: String, size: Int64)? {
        let dir = attachmentsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let sanitized = originalName.replacingOccurrences(of: " ", with: "_")
        let filename = "\(recordingId.uuidString)_\(timestamp)_\(sanitized)"
        let destURL = dir.appendingPathComponent(filename)

        do {
            try data.write(to: destURL)
            return (filename, Int64(data.count))
        } catch {
            Log(.system).error("Failed to save attachment data: \(error)")
            return nil
        }
    }

    /// Get the full URL for an attachment filename
    public static func url(for filename: String) -> URL {
        attachmentsDirectory.appendingPathComponent(filename)
    }

    /// Delete a single attachment file
    public static func delete(filename: String) {
        let fileURL = url(for: filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Delete all attachments for a recording
    public static func deleteAll(for recordingId: UUID) {
        let dir = attachmentsDirectory
        let prefix = recordingId.uuidString
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
