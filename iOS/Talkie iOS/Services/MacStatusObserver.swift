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
    private(set) var isLoading = false

    // MARK: - Mac Status Info

    struct MacStatusInfo {
        let hostname: String
        let powerState: String
        let canProcessMemos: Bool
        let canRunWorkflows: Bool
        let estimatedAvailability: String
        let lastSeen: Date
        let idleMinutes: Int

        var statusDescription: String {
            switch powerState {
            case "active":
                return "Mac is active"
            case "idle":
                return "Mac is idle (\(idleMinutes) min)"
            case "screenOff":
                return canProcessMemos
                    ? "Display off, still processing"
                    : "Display off, may sleep soon"
            case "powerNap":
                return "Mac in Power Nap mode"
            case "sleeping":
                return "Mac is sleeping"
            case "shuttingDown":
                return "Mac is shutting down"
            default:
                return "Mac status unknown"
            }
        }

        var timeSinceLastSeen: String {
            let interval = Date().timeIntervalSince(lastSeen)
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                return "\(Int(interval / 60)) min ago"
            } else {
                return "\(Int(interval / 3600)) hours ago"
            }
        }

        var isAvailable: Bool {
            canProcessMemos || canRunWorkflows
        }
    }

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let context = PersistenceController.shared.container.viewContext

        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "MacStatus")
            request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
            request.fetchLimit = 1

            do {
                guard let status = try context.fetch(request).first else {
                    self.macStatus = nil
                    return
                }

                self.macStatus = MacStatusInfo(
                    hostname: status.value(forKey: "hostname") as? String ?? "Mac",
                    powerState: status.value(forKey: "powerState") as? String ?? "unknown",
                    canProcessMemos: status.value(forKey: "canProcessMemos") as? Bool ?? false,
                    canRunWorkflows: status.value(forKey: "canRunWorkflows") as? Bool ?? false,
                    estimatedAvailability: status.value(forKey: "estimatedAvailability") as? String ?? "unknown",
                    lastSeen: status.value(forKey: "lastSeen") as? Date ?? Date.distantPast,
                    idleMinutes: Int(status.value(forKey: "idleMinutes") as? Int16 ?? 0)
                )
            } catch {
                print("Failed to fetch MacStatus: \(error)")
                self.macStatus = nil
            }
        }
    }

    // MARK: - Observation

    private var remoteChangeObserver: Any?

    func startObserving() {
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

    func stopObserving() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
}
