//
//  RecordingSidecarSession.swift
//  Talkie iOS
//
//  Local persistence envelope for sidecar requests tied to a memo.
//

import Foundation

struct RecordingSidecarSession: Codable {
    let memoId: String
    var memoTitle: String
    let createdAt: Date
    var updatedAt: Date
    var requests: [RecordingSidecarRequest]

    init(
        memoId: String,
        memoTitle: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        requests: [RecordingSidecarRequest] = []
    ) {
        self.memoId = memoId
        self.memoTitle = memoTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.requests = requests
    }
}
