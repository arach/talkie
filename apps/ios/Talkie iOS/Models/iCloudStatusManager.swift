//
//  iCloudStatusManager.swift
//  Talkie iOS
//
//  Monitors iCloud account status and notifies views when unavailable.
//

import Foundation
import CloudKit
import Combine
import UIKit
import TalkieMobileKit

enum iCloudStatus: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case error(String)

    var isAvailable: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .checking:
            return "Checking iCloud..."
        case .available:
            return "iCloud Connected"
        case .noAccount:
            return "iCloud Not Signed In"
        case .restricted:
            return "iCloud Restricted"
        case .temporarilyUnavailable:
            return "iCloud Temporarily Unavailable"
        case .couldNotDetermine:
            return "iCloud Status Unknown"
        case .error(let message):
            return "iCloud Error: \(message)"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking your iCloud account status..."
        case .available:
            return "Your recordings sync across all your devices."
        case .noAccount:
            return "Sign in to iCloud in Settings to back up your recordings and sync with Mac."
        case .restricted:
            return "iCloud access is restricted on this device. Check parental controls or MDM settings."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Your recordings will sync when it's back."
        case .couldNotDetermine:
            return "Unable to check iCloud status. Recordings are saved locally."
        case .error:
            return "There was an error connecting to iCloud. Recordings are saved locally."
        }
    }

    var icon: String {
        switch self {
        case .checking:
            return "icloud"
        case .available:
            return "checkmark.icloud.fill"
        case .noAccount:
            return "icloud.slash"
        case .restricted:
            return "lock.icloud"
        case .temporarilyUnavailable:
            return "exclamationmark.icloud"
        case .couldNotDetermine, .error:
            return "xmark.icloud"
        }
    }
}

class iCloudStatusManager: ObservableObject {
    static let shared = iCloudStatusManager()

    private let configurationStore = TalkieAppConfigurationStore.shared

    /// Synchronous check result - available immediately after init
    /// Use this for gating CloudKit-dependent code paths
    private(set) var initialCheckComplete = false

    @Published private(set) var status: iCloudStatus = .checking
    @Published var isDismissed: Bool {
        didSet {
            UserDefaults.standard.set(isDismissed, forKey: "iCloudBannerDismissed")
            configurationStore.update { configuration in
                configuration.sync.bannerDismissed = isDismissed
            }
        }
    }

    #if DEBUG
    /// Simulated status for debug testing (nil = use real status)
    @Published var simulatedStatus: iCloudStatus? = nil

    /// All available statuses for debug picker
    static let allStatuses: [iCloudStatus] = [
        .available,
        .noAccount,
        .restricted,
        .temporarilyUnavailable,
        .couldNotDetermine,
        .error("Simulated error")
    ]
    #endif

    private var cancellables = Set<AnyCancellable>()
    private var realStatus: iCloudStatus = .checking

    private init() {
        // Load persisted dismiss state
        self.isDismissed = configurationStore.configuration.sync.bannerDismissed

        // Start async iCloud check (non-blocking)
        // PersistenceController no longer waits for this - it uses CloudKit container always
        checkStatusAsync()

        // Re-check when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkStatus()
            }
            .store(in: &cancellables)

        // Listen for iCloud account changes
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .sink { [weak self] _ in
                self?.checkStatus()
            }
            .store(in: &cancellables)

        #if DEBUG
        // Update published status when simulation changes
        $simulatedStatus
            .sink { [weak self] simulated in
                guard let self = self else { return }
                self.status = simulated ?? self.realStatus
            }
            .store(in: &cancellables)
        #endif
    }

    /// Async initial check - non-blocking, for UI feedback only
    /// PersistenceController uses CloudKit container regardless; this is just for banner display
    private func checkStatusAsync() {
        guard let container = CloudKitContainerProvider.container() else {
            let reason = CloudKitContainerProvider.unavailableReason ?? "CloudKit unavailable"
            realStatus = .couldNotDetermine
            status = realStatus
            initialCheckComplete = true
            AppLogger.persistence.info("CloudKit status check skipped: \(reason)")
            return
        }

        container.accountStatus { [weak self] accountStatus, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if error != nil {
                    self.realStatus = .couldNotDetermine
                } else {
                    switch accountStatus {
                    case .available:
                        self.realStatus = .available
                    case .noAccount:
                        self.realStatus = .noAccount
                    case .restricted:
                        self.realStatus = .restricted
                    case .couldNotDetermine:
                        self.realStatus = .couldNotDetermine
                    case .temporarilyUnavailable:
                        self.realStatus = .temporarilyUnavailable
                    @unknown default:
                        self.realStatus = .couldNotDetermine
                    }
                }

                #if DEBUG
                if self.simulatedStatus == nil {
                    self.status = self.realStatus
                }
                #else
                self.status = self.realStatus
                #endif

                self.initialCheckComplete = true

                // Log once, cleanly
                if self.status.isAvailable {
                    AppLogger.persistence.info("☁️ iCloud available - sync enabled")
                } else {
                    AppLogger.persistence.info("📱 iCloud unavailable - local storage, will sync when available")
                }
            }
        }
    }

    func checkStatus() {
        #if DEBUG
        // If simulating, don't update from real status
        if simulatedStatus != nil { return }
        #endif

        guard let container = CloudKitContainerProvider.container() else {
            let reason = CloudKitContainerProvider.unavailableReason ?? "CloudKit unavailable"
            realStatus = .couldNotDetermine
            status = realStatus
            AppLogger.persistence.info("CloudKit status check skipped: \(reason)")
            return
        }

        container.accountStatus { [weak self] accountStatus, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let newStatus: iCloudStatus
                if let error = error {
                    newStatus = .error(error.localizedDescription)
                } else {
                    switch accountStatus {
                    case .available:
                        newStatus = .available
                    case .noAccount:
                        newStatus = .noAccount
                    case .restricted:
                        newStatus = .restricted
                    case .couldNotDetermine:
                        newStatus = .couldNotDetermine
                    case .temporarilyUnavailable:
                        newStatus = .temporarilyUnavailable
                    @unknown default:
                        newStatus = .couldNotDetermine
                    }
                }

                // Only log if status changed
                if self.realStatus != newStatus {
                    if newStatus.isAvailable {
                        AppLogger.persistence.info("☁️ iCloud became available")
                    } else if self.realStatus.isAvailable {
                        AppLogger.persistence.info("📱 iCloud became unavailable")
                    }
                }

                self.realStatus = newStatus

                #if DEBUG
                if self.simulatedStatus == nil {
                    self.status = newStatus
                }
                #else
                self.status = newStatus
                #endif
            }
        }
    }

    func dismissBanner() {
        isDismissed = true
    }

    func resetDismissal() {
        isDismissed = false
    }

    #if DEBUG
    /// Set simulated status (nil to use real status)
    func simulate(_ status: iCloudStatus?) {
        simulatedStatus = status
        if status != nil {
            isDismissed = false  // Show banner when simulating unavailable
        }
        AppLogger.persistence.info("iCloud status simulation: \(status?.title ?? "OFF")")
    }

    /// Check if currently simulating
    var isSimulating: Bool {
        simulatedStatus != nil
    }
    #endif
}
