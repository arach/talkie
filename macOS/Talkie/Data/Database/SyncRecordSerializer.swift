//
//  SyncRecordSerializer.swift
//  Talkie
//
//  Database helpers for serializing records during sync operations
//  Captures full state from both Core Data and GRDB for audit logging
//

import Foundation

// MARK: - Serialized Memo Record

/// Serialized memo record for sync audit
struct SerializedMemoRecord: Codable {
    let title: String?
    let lastModified: String  // ISO8601
    let createdAt: String?    // ISO8601
    let duration: Double
    let transcription: String?  // First 100 chars
    let summary: String?        // First 100 chars
}

extension SerializedMemoRecord {
    /// Create from Core Data VoiceMemo
    static func fromCoreData(_ memo: VoiceMemo) -> SerializedMemoRecord {
        SerializedMemoRecord(
            title: memo.title,
            lastModified: (memo.lastModified ?? Date()).ISO8601Format(),
            createdAt: (memo.createdAt ?? Date()).ISO8601Format(),
            duration: memo.duration,
            transcription: memo.transcription.map { String($0.prefix(100)) },
            summary: memo.summary.map { String($0.prefix(100)) }
        )
    }

    /// Create from GRDB MemoModel
    static func fromGRDB(_ memo: MemoModel) -> SerializedMemoRecord {
        SerializedMemoRecord(
            title: memo.title,
            lastModified: memo.lastModified.ISO8601Format(),
            createdAt: memo.createdAt.ISO8601Format(),
            duration: memo.duration,
            transcription: memo.transcription.map { String($0.prefix(100)) },
            summary: memo.summary.map { String($0.prefix(100)) }
        )
    }
}

// MARK: - Serialized Sync Records

/// Serialized sync records from both sides (Core Data + GRDB)
struct SerializedSyncRecords: Codable {
    let coredata: SerializedMemoRecord?
    let grdb: SerializedMemoRecord?
    let reason: String?

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
