import Foundation

/// Sync method identifier
enum SyncMethod: String, CaseIterable, Codable {
    case local = "local"
    case iCloud = "icloud"
    case bridge = "bridge"
    case dropbox = "dropbox"
    case googleDrive = "gdrive"
    case s3 = "s3"
}

/// Connection status for a sync provider
enum ConnectionStatus: Equatable {
    case available
    case unavailable(reason: String)
    case connecting
    case syncing
}

/// Lightweight memo DTO for sync (no audio data inline)
struct MemoSyncDTO: Codable {
    let id: UUID
    let title: String?
    let duration: Double
    let transcription: String?
    let notes: String?
    let summary: String?
    let createdAt: Date
    let lastModified: Date
    let originDeviceId: String?
    let hasAudio: Bool
}

/// Represents a sync delta
struct MemoChange: Codable {
    let id: UUID
    let type: ChangeType
    let memo: MemoSyncDTO?  // nil for deletes
    let timestamp: Date

    enum ChangeType: String, Codable {
        case create
        case update
        case delete
    }
}

/// Protocol for sync providers (iCloud, Bridge, Dropbox, etc.)
protocol SyncProvider {
    /// Identifier for this provider
    var method: SyncMethod { get }

    /// Human-readable name
    var displayName: String { get }

    /// Check if provider is currently available
    var isAvailable: Bool { get async }

    /// Last successful sync timestamp
    var lastSyncDate: Date? { get async }

    /// Check connection and return status
    func checkConnection() async -> ConnectionStatus

    /// Push local changes to remote
    func pushChanges(_ changes: [MemoChange]) async throws

    /// Pull remote changes since timestamp
    func pullChanges(since: Date?) async throws -> [MemoChange]

    /// Full bidirectional sync
    func fullSync() async throws
}

/// Default implementations
extension SyncProvider {
    var displayName: String {
        switch method {
        case .local: return "Local"
        case .iCloud: return "iCloud"
        case .bridge: return "Direct Connect"
        case .dropbox: return "Dropbox"
        case .googleDrive: return "Google Drive"
        case .s3: return "S3"
        }
    }
}
