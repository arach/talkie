//
//  StatusBarViewModel.swift
//  Talkie
//
//  Aggregates status from multiple services for StatusBar UI
//

import Foundation
import Observation
import TalkieKit

@MainActor
@Observable
final class StatusBarViewModel {
    private static let syncStatusRefreshInterval: TimeInterval = 60

    // MARK: - Aggregated UI State

    var recordingState: LiveState = .idle
    var isRecording: Bool { recordingState != .idle }

    var engineStatus: EngineStatus?
    var engineConnected: Bool = false

    var syncStatus: String = ""
    var isSyncing: Bool = false

    var microphoneName: String?

    var errorCount: Int = 0
    var warningCount: Int = 0
    var infoCount: Int = 0

    var processId: pid_t?
    var showOnAir: Bool = false

    // MARK: - Service References (for direct queries)

    @ObservationIgnored private let liveMonitor: TalkieLiveStateMonitor
    @ObservationIgnored private let engineClient: EngineClient
    @ObservationIgnored private let syncManager: CloudKitSyncManager
    @ObservationIgnored private let eventManager: SystemEventManager
    @ObservationIgnored private let audioDevices: AudioDeviceManager
    @ObservationIgnored private let liveSettings: LiveSettings
    @ObservationIgnored private var syncStatusTimer: Timer?

    // MARK: - Initialization

    init(
        liveMonitor: TalkieLiveStateMonitor = .shared,
        engineClient: EngineClient = .shared,
        syncManager: CloudKitSyncManager = .shared,
        eventManager: SystemEventManager = .shared,
        audioDevices: AudioDeviceManager = .shared,
        liveSettings: LiveSettings = .shared
    ) {
        self.liveMonitor = liveMonitor
        self.engineClient = engineClient
        self.syncManager = syncManager
        self.eventManager = eventManager
        self.audioDevices = audioDevices
        self.liveSettings = liveSettings

        refresh()
        observe()
        startSyncStatusTimer()
    }

    deinit {
        syncStatusTimer?.invalidate()
    }

    // MARK: - Refresh Aggregated State

    func refresh() {
        // Recording state
        recordingState = liveMonitor.state
        processId = liveMonitor.processId

        // Engine status
        engineStatus = engineClient.status
        engineConnected = engineClient.connectionState == .connected

        // Sync status
        isSyncing = syncManager.isSyncing
        syncStatus = formatSyncStatus()

        // Audio device
        microphoneName = currentMicrophoneName()

        // Event counts
        errorCount = eventManager.events.filter { $0.type == .error }.count
        warningCount = eventManager.events.filter { $0.type == .workflow }.count
        infoCount = eventManager.events.filter {
            $0.type == .system || $0.type == .transcribe || $0.type == .sync || $0.type == .record
        }.count

        // Settings
        showOnAir = liveSettings.showOnAir
    }

    private func observe() {
        withObservationTracking {
            _ = liveMonitor.state
            _ = liveMonitor.processId
            _ = engineClient.connectionState
            _ = engineClient.status
            _ = syncManager.isSyncing
            _ = syncManager.lastSyncDate
            _ = eventManager.events
            _ = audioDevices.inputDevices
            _ = liveSettings.selectedMicrophoneID
            _ = liveSettings.showOnAir
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observe()
            }
        }
    }

    private func startSyncStatusTimer() {
        syncStatusTimer?.invalidate()
        syncStatusTimer = Timer.scheduledTimer(withTimeInterval: Self.syncStatusRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // MARK: - Private Helpers

    private func formatSyncStatus() -> String {
        if syncManager.isSyncing {
            return "Syncing..."
        } else if let lastSync = syncManager.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: lastSync, relativeTo: Date())
        } else {
            return "Not synced"
        }
    }

    private func currentMicrophoneName() -> String? {
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return nil
    }
}
