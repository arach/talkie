import Foundation

/// Sync method identifier
enum SyncMethod: String, CaseIterable, Codable {
    case local = "local"
    case iCloud = "icloud"
    case bridge = "bridge"
    case dropbox = "dropbox"
    case googleDrive = "gdrive"
    case s3 = "s3"
    case vercel = "vercel"
}

// MARK: - SyncMethod UI Extensions

extension SyncMethod {
    /// SF Symbol icon for this sync method
    var icon: String {
        switch self {
        case .local: return "internaldrive"
        case .iCloud: return "icloud"
        case .bridge: return "network"
        case .dropbox: return "shippingbox"
        case .googleDrive: return "g.circle"
        case .s3: return "externaldrive.connected.to.line.below"
        case .vercel: return "bolt.trianglebadge.exclamationmark"
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .local: return "Local Storage"
        case .iCloud: return "iCloud"
        case .bridge: return "Direct Connect"
        case .dropbox: return "Dropbox"
        case .googleDrive: return "Google Drive"
        case .s3: return "S3 Compatible"
        case .vercel: return "Vercel Blob"
        }
    }

    /// Description of this sync method
    var description: String {
        switch self {
        case .local: return "Store memos only on this device"
        case .iCloud: return "Sync across all your Apple devices"
        case .bridge: return "Connect directly to another device"
        case .dropbox: return "Sync via Dropbox cloud storage"
        case .googleDrive: return "Sync via Google Drive"
        case .s3: return "Sync to S3, R2, or compatible storage"
        case .vercel: return "Sync via Vercel Blob storage"
        }
    }
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
    var icon: String { method.icon }
    var displayName: String { method.displayName }
}

// MARK: - Sync Credentials

/// Keys for provider credentials
enum SyncCredentialKey: String {
    case endpoint
    case accessKeyId
    case secretAccessKey
    case bucket
    case region
    case token
}

/// Credentials for sync providers
struct SyncCredentials {
    let provider: SyncMethod
    private var values: [SyncCredentialKey: String] = [:]

    init(provider: SyncMethod) {
        self.provider = provider
    }

    subscript(key: SyncCredentialKey) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

// MARK: - Sync Result

/// Result of a sync operation
struct SyncResult {
    let isSuccess: Bool
    let itemsSynced: Int
    let errorMessage: String?
    let timestamp: Date

    var summary: String {
        if isSuccess {
            return itemsSynced > 0 ? "\(itemsSynced) synced" : "Up to date"
        } else {
            return errorMessage ?? "Sync failed"
        }
    }

    static func success(itemsSynced: Int) -> SyncResult {
        SyncResult(isSuccess: true, itemsSynced: itemsSynced, errorMessage: nil, timestamp: Date())
    }

    static func failure(_ message: String) -> SyncResult {
        SyncResult(isSuccess: false, itemsSynced: 0, errorMessage: message, timestamp: Date())
    }
}
