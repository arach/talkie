//
//  CoreDataSyncGateway.swift
//  Talkie macOS
//
//  SINGLE POINT OF ACCESS for all Core Data operations.
//  Core Data is used ONLY as a CloudKit sync layer - GRDB is the source of truth.
//
//  This gateway:
//  - Ensures Core Data stores are loaded before any access
//  - Provides sync-specific methods (not general CRUD)
//  - Makes the sync-only purpose explicit in the API
//
//  ⚠️ DO NOT use PersistenceController.shared.container.viewContext directly.
//  All Core Data access should go through this gateway.
//

import Foundation
import CoreData
import TalkieKit

private let log = Log(.sync)

/// Central gateway for all Core Data sync operations.
/// Core Data is used ONLY for CloudKit sync - GRDB is the local source of truth.
@MainActor
final class CoreDataSyncGateway {
    static let shared = CoreDataSyncGateway()

    private init() {}

    // MARK: - Readiness Check

    /// Returns true if Core Data stores are loaded and ready for operations
    var isReady: Bool {
        PersistenceController.isReady
    }

    /// Returns the managed object context if ready, nil otherwise.
    /// Callers should check isReady or handle nil gracefully.
    var context: NSManagedObjectContext? {
        guard isReady else {
            log.debug("CoreDataSyncGateway: Stores not ready, returning nil context")
            return nil
        }
        return PersistenceController.shared.container.viewContext
    }

    // MARK: - Safe Context Access

    /// Execute a sync operation with the Core Data context.
    /// Returns nil if stores aren't ready yet.
    func withContext<T>(_ operation: (NSManagedObjectContext) throws -> T) rethrows -> T? {
        guard let ctx = context else {
            log.debug("CoreDataSyncGateway: Skipping operation - stores not ready")
            return nil
        }
        return try operation(ctx)
    }

    /// Execute a sync operation asynchronously with the Core Data context.
    /// Safely handles the case where stores aren't ready.
    func performSync(_ operation: @escaping (NSManagedObjectContext) -> Void) {
        guard let ctx = context else {
            log.debug("CoreDataSyncGateway: Skipping sync operation - stores not ready")
            return
        }
        ctx.perform {
            operation(ctx)
        }
    }

    // MARK: - Sync-Specific Operations

    /// Mark memos as received by this Mac (for iOS → Mac sync tracking)
    func markMemosAsReceivedByMac() {
        guard let ctx = context else {
            log.debug("CoreDataSyncGateway: Cannot mark memos - stores not ready")
            return
        }
        PersistenceController.markMemosAsReceivedByMac(context: ctx)
    }

    /// Fetch all VoiceMemo IDs from Core Data (for sync comparison)
    func fetchAllMemoIDs() async -> Set<UUID> {
        guard let ctx = context else {
            log.debug("CoreDataSyncGateway: Cannot fetch memo IDs - stores not ready")
            return []
        }

        return await ctx.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "VoiceMemo")
            request.propertiesToFetch = ["id"]
            request.resultType = .dictionaryResultType

            do {
                let results = try ctx.fetch(request) as? [[String: Any]] ?? []
                let ids = results.compactMap { dict -> UUID? in
                    dict["id"] as? UUID
                }
                return Set(ids)
            } catch {
                log.error("Failed to fetch memo IDs from Core Data: \(error)")
                return []
            }
        }
    }

    /// Count VoiceMemos in Core Data (for sync status display)
    func countMemos() async -> Int {
        guard let ctx = context else {
            return 0
        }

        return await ctx.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "VoiceMemo")
            return (try? ctx.count(for: request)) ?? 0
        }
    }

    // MARK: - MacStatus Sync (Power Lifecycle)

    /// Update Mac status for iOS visibility
    func updateMacStatus(
        powerState: PowerStateManager.PowerState,
        capabilities: PowerStateManager.Capabilities,
        idleTime: TimeInterval
    ) async {
        guard let ctx = context else {
            log.debug("CoreDataSyncGateway: Cannot update MacStatus - stores not ready")
            return
        }

        await ctx.perform {
            do {
                let deviceId = Self.deviceIdentifier
                let request = NSFetchRequest<NSManagedObject>(entityName: "MacStatus")
                request.predicate = NSPredicate(format: "deviceId == %@", deviceId)

                let results = try ctx.fetch(request)
                let status: NSManagedObject

                if let existing = results.first {
                    status = existing
                } else {
                    guard let entity = NSEntityDescription.entity(forEntityName: "MacStatus", in: ctx) else {
                        log.error("MacStatus entity not found in Core Data model")
                        return
                    }
                    status = NSManagedObject(entity: entity, insertInto: ctx)
                    status.setValue(deviceId, forKey: "deviceId")
                }

                status.setValue(Self.hostname, forKey: "hostname")
                status.setValue(powerState.rawValue, forKey: "powerState")
                status.setValue(capabilities.canProcessMemos, forKey: "canProcessMemos")
                status.setValue(capabilities.canRunWorkflows, forKey: "canRunWorkflows")
                status.setValue(capabilities.estimatedAvailability, forKey: "estimatedAvailability")
                status.setValue(Date(), forKey: "lastSeen")
                status.setValue(Int16(idleTime / 60), forKey: "idleMinutes")

                try ctx.save()
                log.debug("MacStatus updated: \(powerState.rawValue)")
            } catch {
                log.error("Failed to update MacStatus: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static var deviceIdentifier: String {
        if let uuid = getHardwareUUID() {
            return uuid
        }
        return hostname
    }

    private static var hostname: String {
        Host.current().localizedName ?? "Mac"
    }

    private static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0 else { return nil }

        let uuidProperty = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )

        return uuidProperty?.takeRetainedValue() as? String
    }
}
