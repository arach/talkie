//
//  SyncProvider.swift
//  TalkieSync
//
//  Protocol for sync providers (iCloud, S3, Dropbox, etc.)
//  Allows TalkieSync to support multiple sync backends.
//

import Foundation

/// Result of a sync operation
public struct SyncResult {
    public let recordsPushed: Int
    public let recordsPulled: Int
    public let errors: [String]

    public var totalSynced: Int { recordsPushed + recordsPulled }
    public var hasErrors: Bool { !errors.isEmpty }

    public init(recordsPushed: Int = 0, recordsPulled: Int = 0, errors: [String] = []) {
        self.recordsPushed = recordsPushed
        self.recordsPulled = recordsPulled
        self.errors = errors
    }

    public static let empty = SyncResult()
}

/// Connection status for a sync provider
public enum ProviderConnectionStatus {
    case connected
    case disconnected
    case connecting
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Protocol for sync providers
///
/// Each provider implements sync to/from a specific backend.
/// Providers are managed by TalkieSync and can be enabled/disabled.
public protocol SyncProvider: AnyObject {
    /// Unique identifier for this provider (e.g., "icloud", "s3", "dropbox")
    var id: String { get }

    /// Display name for UI (e.g., "iCloud", "Amazon S3", "Dropbox")
    var displayName: String { get }

    /// Whether this provider is currently enabled
    var isEnabled: Bool { get }

    /// Current connection status
    var connectionStatus: ProviderConnectionStatus { get }

    /// Last successful sync date
    var lastSyncDate: Date? { get }

    /// Configure the provider with settings
    /// - Parameter config: Provider-specific configuration as JSON data
    func configure(_ config: Data?) async throws

    /// Check if the provider is available and authenticated
    func checkConnection() async -> ProviderConnectionStatus

    /// Perform a full sync (push local changes, pull remote changes)
    func sync() async throws -> SyncResult

    /// Push local changes to the remote
    func pushChanges() async throws -> SyncResult

    /// Pull remote changes to local
    func pullChanges() async throws -> SyncResult

    /// Disconnect from the provider (logout, clear credentials)
    func disconnect() async
}

/// Errors that can occur during sync
public enum SyncProviderError: Error, LocalizedError {
    case notAuthenticated
    case networkUnavailable
    case quotaExceeded
    case conflict(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with sync provider"
        case .networkUnavailable:
            return "Network unavailable"
        case .quotaExceeded:
            return "Storage quota exceeded"
        case .conflict(let message):
            return "Sync conflict: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
