//
//  MacStatusSync.swift
//  Talkie macOS
//
//  Syncs Mac power state to CloudKit so iOS can see when the Mac
//  is available for async memo processing.
//
//  Uses CoreDataSyncGateway for all Core Data access.
//

import Foundation
import TalkieKit

private let log = Log(.sync)

actor MacStatusSync {
    static let shared = MacStatusSync()

    private init() {}

    /// Update Mac status in CloudKit via the sync gateway
    func updateStatus(
        powerState: PowerStateManager.PowerState,
        capabilities: PowerStateManager.Capabilities,
        idleTime: TimeInterval
    ) async {
        await CoreDataSyncGateway.shared.updateMacStatus(
            powerState: powerState,
            capabilities: capabilities,
            idleTime: idleTime
        )
    }
}
