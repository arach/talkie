//
//  MemoStorageStatus.swift
//  Talkie
//
//  Represents a memo's presence across all storage layers.
//  Used by DataInventoryView to show users where their data lives.
//

import Foundation

/// Status of a memo's sync across storage layers
enum MemoSyncStatus: String, CaseIterable {
    case synced           // Present in all layers
    case localOnly        // GRDB only, not in CloudKit/remote
    case pendingUpload    // In GRDB, queued for sync
    case pendingDownload  // In remote, not yet in GRDB
    case audioMissing     // Record exists but audio file missing locally
    case orphaned         // In remote but deleted locally
    case unknown          // Status cannot be determined

    var displayName: String {
        switch self {
        case .synced: return "Synced"
        case .localOnly: return "Local Only"
        case .pendingUpload: return "Uploading"
        case .pendingDownload: return "Downloading"
        case .audioMissing: return "Audio Missing"
        case .orphaned: return "Orphaned"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .localOnly: return "iphone"
        case .pendingUpload: return "arrow.up.circle"
        case .pendingDownload: return "arrow.down.circle"
        case .audioMissing: return "exclamationmark.triangle.fill"
        case .orphaned: return "trash.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .synced: return "green"
        case .localOnly: return "blue"
        case .pendingUpload: return "orange"
        case .pendingDownload: return "orange"
        case .audioMissing: return "red"
        case .orphaned: return "gray"
        case .unknown: return "gray"
        }
    }

    var isHealthy: Bool {
        switch self {
        case .synced, .localOnly: return true
        case .pendingUpload, .pendingDownload: return true  // Transient states
        case .audioMissing, .orphaned, .unknown: return false
        }
    }
}

/// Snapshot of a memo's storage state across all layers
struct MemoStorageStatus: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let duration: TimeInterval

    // MARK: - Local File System

    /// Audio file exists in ~/Library/.../Talkie/Audio/{uuid}.m4a
    let hasLocalAudioFile: Bool

    /// Size of local audio file in bytes (nil if file doesn't exist)
    let localAudioSize: Int64?

    /// Path to local audio file (relative, e.g., "{uuid}.m4a")
    let localAudioPath: String?

    // MARK: - Local Database (GRDB)

    /// Record exists in talkie_grdb.sqlite
    let hasLocalDBRecord: Bool

    /// Has transcription in local DB
    let hasTranscription: Bool

    // MARK: - Sync Database (CoreData)

    /// Record exists in CoreData (CloudKit's local mirror)
    let hasSyncDBRecord: Bool

    /// CoreData has audio data (external blob reference)
    let syncDBHasAudio: Bool

    // MARK: - Remote (CloudKit)

    /// Record exists in CloudKit (nil = unknown/not checked)
    let hasRemoteRecord: Bool?

    /// Last sync timestamp from CloudKit
    let cloudSyncedAt: Date?

    // MARK: - Computed Properties

    /// Derived sync status based on presence across layers
    var status: MemoSyncStatus {
        // If we don't know remote status, base on local + sync DB
        let remotePresent = hasRemoteRecord ?? hasSyncDBRecord

        // Check for issues first
        if hasLocalDBRecord && !hasLocalAudioFile && localAudioPath != nil {
            // Record says there should be audio but file is missing
            return .audioMissing
        }

        if !hasLocalDBRecord && hasSyncDBRecord {
            // In sync DB but not local - needs download
            return .pendingDownload
        }

        if hasLocalDBRecord && !hasSyncDBRecord && !remotePresent {
            // Local only, not synced
            return .localOnly
        }

        if hasLocalDBRecord && hasSyncDBRecord && remotePresent {
            // Present everywhere
            return .synced
        }

        if !hasLocalDBRecord && !hasSyncDBRecord && remotePresent {
            // Only in remote, orphaned or needs sync
            return .orphaned
        }

        if hasLocalDBRecord && hasSyncDBRecord && !remotePresent {
            // Pending upload to cloud
            return .pendingUpload
        }

        return .unknown
    }

    /// Human-readable summary of storage locations
    var storageSummary: String {
        var locations: [String] = []

        if hasLocalAudioFile {
            let sizeStr = localAudioSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
            locations.append("Local \(sizeStr)")
        }

        if hasSyncDBRecord {
            locations.append("CoreData")
        }

        if hasRemoteRecord == true {
            locations.append("iCloud")
        }

        return locations.isEmpty ? "No storage" : locations.joined(separator: " + ")
    }

    /// Total known size across all storage layers
    var totalSize: Int64 {
        localAudioSize ?? 0
    }
}

// MARK: - Equatable & Hashable

extension MemoStorageStatus: Equatable {
    static func == (lhs: MemoStorageStatus, rhs: MemoStorageStatus) -> Bool {
        lhs.id == rhs.id
    }
}

extension MemoStorageStatus: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Sorting

extension MemoStorageStatus {
    /// Sort by status priority (issues first), then by date
    static func sortByStatusThenDate(_ lhs: MemoStorageStatus, _ rhs: MemoStorageStatus) -> Bool {
        if lhs.status.isHealthy != rhs.status.isHealthy {
            return !lhs.status.isHealthy  // Issues first
        }
        return lhs.createdAt > rhs.createdAt  // Newest first
    }
}

// MARK: - Inventory Summary

/// Summary statistics for a collection of MemoStorageStatus
struct StorageInventorySummary {
    let totalMemos: Int
    let syncedCount: Int
    let localOnlyCount: Int
    let pendingCount: Int
    let issueCount: Int
    let totalLocalSize: Int64
    let timestamp: Date

    var healthyPercentage: Double {
        guard totalMemos > 0 else { return 100 }
        return Double(syncedCount + localOnlyCount) / Double(totalMemos) * 100
    }

    init(from statuses: [MemoStorageStatus]) {
        self.totalMemos = statuses.count
        self.syncedCount = statuses.filter { $0.status == .synced }.count
        self.localOnlyCount = statuses.filter { $0.status == .localOnly }.count
        self.pendingCount = statuses.filter { $0.status == .pendingUpload || $0.status == .pendingDownload }.count
        self.issueCount = statuses.filter { !$0.status.isHealthy }.count
        self.totalLocalSize = statuses.compactMap(\.localAudioSize).reduce(0, +)
        self.timestamp = Date()
    }
}
