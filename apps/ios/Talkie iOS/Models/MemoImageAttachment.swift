//
//  MemoImageAttachment.swift
//  Talkie iOS
//
//  File-backed image attachment metadata for a voice memo.
//

import Foundation

struct MemoImageAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    let filename: String
    let originalName: String
    let fileSizeBytes: Int64
    let addedAt: Date
    let pixelWidth: Int?
    let pixelHeight: Int?

    init(
        id: UUID = UUID(),
        filename: String,
        originalName: String,
        fileSizeBytes: Int64,
        addedAt: Date = Date(),
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.id = id
        self.filename = filename
        self.originalName = originalName
        self.fileSizeBytes = fileSizeBytes
        self.addedAt = addedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
