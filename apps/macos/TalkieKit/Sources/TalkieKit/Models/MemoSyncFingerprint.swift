//
//  MemoSyncFingerprint.swift
//  TalkieKit
//
//  Lightweight sync fingerprint for cross-store verification.
//

import Foundation
import CryptoKit

/// Compact signature for memo change detection across Core Data and GRDB.
public struct MemoSyncFingerprint: Codable, Sendable, Hashable {
    public let id: UUID
    public let lastModified: Date
    public let signature: String

    public init(id: UUID, lastModified: Date, signature: String) {
        self.id = id
        self.lastModified = lastModified
        self.signature = signature
    }

    /// Stable SHA-256 signature for sync-relevant memo fields.
    public static func signature(
        title: String?,
        transcription: String?,
        notes: String?,
        summary: String?,
        tasks: String?,
        reminders: String?,
        duration: Double,
        sortOrder: Int,
        deletedAt: Date?,
        audioFilePath: String?,
        originDeviceId: String?,
        isTranscribing: Bool,
        isProcessingSummary: Bool,
        isProcessingTasks: Bool,
        isProcessingReminders: Bool,
        autoProcessed: Bool
    ) -> String {
        let parts: [String] = [
            canonical(title),
            canonical(transcription),
            canonical(notes),
            canonical(summary),
            canonical(tasks),
            canonical(reminders),
            String(Int((duration * 1000).rounded())),
            String(sortOrder),
            canonicalDate(deletedAt),
            canonical(audioFilePath),
            canonical(originDeviceId),
            isTranscribing ? "1" : "0",
            isProcessingSummary ? "1" : "0",
            isProcessingTasks ? "1" : "0",
            isProcessingReminders ? "1" : "0",
            autoProcessed ? "1" : "0"
        ]
        let payload = parts.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonical(_ value: String?) -> String {
        value ?? ""
    }

    private static func canonicalDate(_ value: Date?) -> String {
        guard let value else { return "" }
        return String(value.timeIntervalSince1970)
    }
}
