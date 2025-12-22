//
//  MemoModel.swift
//  Talkie
//
//  Pure Swift data model for voice memos
//  Decoupled from Core Data and CloudKit
//

import Foundation
import SwiftUI
import GRDB

// MARK: - Voice Memo Model

struct MemoModel: Identifiable, Codable, Hashable {
    // MARK: - Core Properties

    let id: UUID
    var createdAt: Date
    var lastModified: Date
    var title: String?
    var duration: Double
    var sortOrder: Int

    // MARK: - Content

    /// Current transcript (computed from latest version)
    var transcription: String?
    var notes: String?
    var summary: String?
    var tasks: String?
    var reminders: String?

    // MARK: - Audio

    /// Relative path to audio file (stored separately)
    var audioFilePath: String?
    /// Binary waveform data for visualization
    var waveformData: Data?

    // MARK: - Processing State

    var isTranscribing: Bool
    var isProcessingSummary: Bool
    var isProcessingTasks: Bool
    var isProcessingReminders: Bool
    var autoProcessed: Bool

    // MARK: - Provenance

    /// Device identifier (e.g., "mac-MacBook Pro", "live-auto")
    var originDeviceId: String?
    var macReceivedAt: Date?

    // MARK: - Sync

    var cloudSyncedAt: Date?

    // MARK: - Workflows

    /// JSON array of pending workflow IDs
    var pendingWorkflowIds: String?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        title: String? = nil,
        duration: Double = 0,
        sortOrder: Int = 0,
        transcription: String? = nil,
        notes: String? = nil,
        summary: String? = nil,
        tasks: String? = nil,
        reminders: String? = nil,
        audioFilePath: String? = nil,
        waveformData: Data? = nil,
        isTranscribing: Bool = false,
        isProcessingSummary: Bool = false,
        isProcessingTasks: Bool = false,
        isProcessingReminders: Bool = false,
        autoProcessed: Bool = false,
        originDeviceId: String? = nil,
        macReceivedAt: Date? = nil,
        cloudSyncedAt: Date? = nil,
        pendingWorkflowIds: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.title = title
        self.duration = duration
        self.sortOrder = sortOrder
        self.transcription = transcription
        self.notes = notes
        self.summary = summary
        self.tasks = tasks
        self.reminders = reminders
        self.audioFilePath = audioFilePath
        self.waveformData = waveformData
        self.isTranscribing = isTranscribing
        self.isProcessingSummary = isProcessingSummary
        self.isProcessingTasks = isProcessingTasks
        self.isProcessingReminders = isProcessingReminders
        self.autoProcessed = autoProcessed
        self.originDeviceId = originDeviceId
        self.macReceivedAt = macReceivedAt
        self.cloudSyncedAt = cloudSyncedAt
        self.pendingWorkflowIds = pendingWorkflowIds
    }
}

// MARK: - GRDB Record

extension MemoModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "voice_memos"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastModified = Column(CodingKeys.lastModified)
        static let title = Column(CodingKeys.title)
        static let duration = Column(CodingKeys.duration)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let transcription = Column(CodingKeys.transcription)
        static let notes = Column(CodingKeys.notes)
        static let summary = Column(CodingKeys.summary)
        static let tasks = Column(CodingKeys.tasks)
        static let reminders = Column(CodingKeys.reminders)
        static let audioFilePath = Column(CodingKeys.audioFilePath)
        static let waveformData = Column(CodingKeys.waveformData)
        static let isTranscribing = Column(CodingKeys.isTranscribing)
        static let isProcessingSummary = Column(CodingKeys.isProcessingSummary)
        static let isProcessingTasks = Column(CodingKeys.isProcessingTasks)
        static let isProcessingReminders = Column(CodingKeys.isProcessingReminders)
        static let autoProcessed = Column(CodingKeys.autoProcessed)
        static let originDeviceId = Column(CodingKeys.originDeviceId)
        static let macReceivedAt = Column(CodingKeys.macReceivedAt)
        static let cloudSyncedAt = Column(CodingKeys.cloudSyncedAt)
        static let pendingWorkflowIds = Column(CodingKeys.pendingWorkflowIds)
    }

    /// Associations
    static let transcriptVersions = hasMany(TranscriptVersionModel.self)
    static let workflowRuns = hasMany(WorkflowRunModel.self)
}

// MARK: - Computed Properties

extension MemoModel {
    /// Memo source (iPhone, Mac, Live, etc.)
    var source: MemoModel.Source {
        MemoModel.Source.from(originDeviceId: originDeviceId)
    }

    /// Display title (falls back to timestamp if no title)
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Format date as title
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Word count from transcription
    var wordCount: Int {
        guard let transcript = transcription, !transcript.isEmpty else { return 0 }
        return transcript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Preview snippet of transcript (first ~80 chars, cleaned up)
    var transcriptPreview: String? {
        guard let transcript = transcription, !transcript.isEmpty else { return nil }
        // Clean up whitespace and get first portion
        let cleaned = transcript
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 80 {
            return cleaned
        }
        // Truncate at word boundary
        let truncated = String(cleaned.prefix(80))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    /// Has audio file
    var hasAudio: Bool {
        audioFilePath != nil
    }

    /// Is processing any AI action
    var isProcessing: Bool {
        isTranscribing || isProcessingSummary || isProcessingTasks || isProcessingReminders
    }
}

// MARK: - Sendable Conformance

extension MemoModel: Sendable {}


// MARK: - Nested Types

extension MemoModel {
    enum Source: Equatable, Hashable {
        case iPhone(deviceName: String?)
        case watch(deviceName: String?)
        case mac(deviceName: String?)
        case live  // TalkieLive always-on recording
        case unknown

        /// Parse from originDeviceId string
        static func from(originDeviceId: String?) -> MemoModel.Source {
            guard let id = originDeviceId, !id.isEmpty else {
                return .unknown
            }

            // Check prefixes
            if id.hasPrefix("watch-") {
                let name = String(id.dropFirst(6))
                return .watch(deviceName: name.isEmpty ? nil : name)
            }
            if id.hasPrefix("mac-") {
                let name = String(id.dropFirst(4))
                return .mac(deviceName: name.isEmpty ? nil : name)
            }
            if id.hasPrefix("live-") {
                return .live
            }

            // No prefix = iPhone (legacy format)
            return .iPhone(deviceName: nil)
        }

        /// SF Symbol icon
        var icon: String {
            switch self {
            case .iPhone: return "iphone"
            case .watch: return "applewatch"
            case .mac: return "desktopcomputer"
            case .live: return "waveform.circle.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        /// Display name
        var displayName: String {
            switch self {
            case .iPhone: return "iPhone"
            case .watch: return "Watch"
            case .mac(let name):
                if let name = name, !name.isEmpty {
                    // Shorten "Arach's MacBook Pro" to just "MacBook Pro"
                    let shortened = name
                        .replacingOccurrences(of: "'s ", with: " ")
                        .components(separatedBy: " ")
                        .suffix(2)
                        .joined(separator: " ")
                    return shortened.isEmpty ? "Mac" : shortened
                }
                return "Mac"
            case .live: return "Live"
            case .unknown: return "Unknown"
            }
        }

        /// Badge color
        var color: Color {
            switch self {
            case .iPhone: return .blue
            case .watch: return .orange
            case .mac: return .purple
            case .live: return .cyan
            case .unknown: return .secondary
            }
        }
    }
}

// MARK: - Source Conformances
extension MemoModel.Source: Sendable {}


extension MemoModel {
    enum SortField {
        case timestamp    // Sort by createdAt
        case title        // Sort by title
        case duration     // Sort by duration
        case workflows    // Sort by workflow count (computed)
    }
}
