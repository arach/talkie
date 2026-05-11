//
//  MacStatusObserver.swift
//  Talkie iOS
//
//  Observes Mac power state from CloudKit to help iOS users
//  understand when their Mac is available for async memo processing.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class MacStatusObserver {
    static let shared = MacStatusObserver()

    private(set) var macStatus: MacStatusInfo?
    private(set) var macStatuses: [MacStatusInfo] = []
    private(set) var isLoading = false

    // MARK: - Mac Status Info

    struct MacStatusInfo: Identifiable {
        let hostname: String
        let powerState: String
        let canProcessMemos: Bool
        let canRunWorkflows: Bool
        let estimatedAvailability: String
        let lastSeen: Date
        let idleMinutes: Int

        var id: String { hostname }

        var age: TimeInterval {
            Date().timeIntervalSince(lastSeen)
        }

        /// Power-state heartbeats are frequent. Once a Mac hasn't reported in for a while,
        /// we should stop presenting its last known state as if it were current.
        var isStale: Bool {
            age > 15 * 60
        }

        var statusDescription: String {
            if isStale {
                return "Status needs refresh"
            }

            switch powerState {
            case "active":
                return "Mac is active"
            case "idle":
                return "Mac is idle (\(idleMinutes) min)"
            case "screenOff":
                return canProcessMemos
                    ? "Display off, still processing"
                    : "Display off, may sleep soon"
            case "sleeping":
                return "Mac is sleeping"
            case "shuttingDown":
                return "Mac is shutting down"
            default:
                return "Mac status unknown"
            }
        }

        var timeSinceLastSeen: String {
            let interval = age
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                return "\(Int(interval / 60)) min ago"
            } else if interval < 86_400 {
                return "\(Int(interval / 3600)) hr ago"
            } else if interval < 604_800 {
                return "\(Int(interval / 86_400)) days ago"
            } else if interval < 2_592_000 {
                return "\(Int(interval / 604_800)) weeks ago"
            } else {
                return "\(Int(interval / 2_592_000)) months ago"
            }
        }

        var isAvailable: Bool {
            !isStale && (canProcessMemos || canRunWorkflows)
        }
    }

    private init() {}

    // MARK: - Refresh

    /// Debounce tracking to prevent multiple concurrent refreshes
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var pendingRefresh = false

    func refresh() async {
        // Debounce: if already refreshing, mark pending and return
        if isRefreshing {
            pendingRefresh = true
            return
        }

        // Check if Core Data stores are ready
        guard PersistenceController.isReady else {
            AppLogger.persistence.debug("MacStatusObserver: Core Data not ready, skipping refresh")
            return
        }

        isRefreshing = true
        isLoading = true
        defer {
            isLoading = false
            isRefreshing = false
            // If a refresh was requested while we were busy, do one more
            if pendingRefresh {
                pendingRefresh = false
                Task { await refresh() }
            }
        }

        let context = PersistenceController.shared.container.viewContext

        // Fetch on Core Data's queue, then update MainActor property
        let fetchedStatuses: [MacStatusInfo] = await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "MacStatus")
            request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]

            do {
                let fetchedObjects = try context.fetch(request)
                var seenHosts = Set<String>()
                var results: [MacStatusInfo] = []

                for status in fetchedObjects {
                    let hostname = status.value(forKey: "hostname") as? String ?? "Mac"
                    guard seenHosts.insert(hostname).inserted else { continue }

                    results.append(
                        MacStatusInfo(
                            hostname: hostname,
                            powerState: status.value(forKey: "powerState") as? String ?? "unknown",
                            canProcessMemos: status.value(forKey: "canProcessMemos") as? Bool ?? false,
                            canRunWorkflows: status.value(forKey: "canRunWorkflows") as? Bool ?? false,
                            estimatedAvailability: status.value(forKey: "estimatedAvailability") as? String ?? "unknown",
                            lastSeen: status.value(forKey: "lastSeen") as? Date ?? Date.distantPast,
                            idleMinutes: Int(status.value(forKey: "idleMinutes") as? Int16 ?? 0)
                        )
                    )
                }

                return results
            } catch {
                AppLogger.persistence.error("Failed to fetch MacStatus: \(error.localizedDescription)")
                return []
            }
        }

        // Update on MainActor
        self.macStatuses = fetchedStatuses
        self.macStatus = fetchedStatuses.first
    }

    // MARK: - Observation

    @ObservationIgnored private var remoteChangeObserver: Any?
    @ObservationIgnored private var observerCount = 0

    /// Start observing CloudKit changes. Uses reference counting so multiple
    /// callers can start/stop without interfering with each other.
    func startObserving() {
        let status = iCloudStatusManager.shared.status

        // Skip if iCloud unavailable or still checking
        guard status.isAvailable else {
            // Only log if we know it's unavailable (not just still checking)
            if status != .checking {
                AppLogger.persistence.debug("MacStatusObserver: Skipping - iCloud not available")
            }
            return
        }

        observerCount += 1

        // Only add observer once
        guard remoteChangeObserver == nil else { return }

        AppLogger.persistence.debug("MacStatusObserver: Starting CloudKit observation")

        // Observe CloudKit changes
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }

        // Initial fetch
        Task { await refresh() }
    }

    /// Stop observing CloudKit changes. Only removes the observer when all
    /// callers have stopped.
    func stopObserving() {
        observerCount = max(0, observerCount - 1)

        guard observerCount == 0 else {
            AppLogger.persistence.debug("MacStatusObserver: Still has \(observerCount) observer(s)")
            return
        }

        if let observer = remoteChangeObserver {
            AppLogger.persistence.info("MacStatusObserver: Stopping CloudKit observation")
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
}
