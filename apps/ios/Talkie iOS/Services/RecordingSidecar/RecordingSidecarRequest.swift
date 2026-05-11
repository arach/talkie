//
//  RecordingSidecarRequest.swift
//  Talkie iOS
//
//  A queued sidecar request captured during recording and resolved later.
//

import Foundation

struct RecordingSidecarRequest: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case queued
        case processing
        case completed
        case failed
    }

    let id: UUID
    let kind: RecordingSidecarKind
    let createdAt: Date
    let queuedAtOffset: TimeInterval
    var note: String
    var status: Status
    var transcriptExcerpt: String?
    var output: String?
    var failureMessage: String?
    var resolvedAt: Date?

    init(
        id: UUID = UUID(),
        kind: RecordingSidecarKind,
        createdAt: Date = Date(),
        queuedAtOffset: TimeInterval,
        note: String = "",
        status: Status = .queued,
        transcriptExcerpt: String? = nil,
        output: String? = nil,
        failureMessage: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.queuedAtOffset = queuedAtOffset
        self.note = note
        self.status = status
        self.transcriptExcerpt = transcriptExcerpt
        self.output = output
        self.failureMessage = failureMessage
        self.resolvedAt = resolvedAt
    }
}
