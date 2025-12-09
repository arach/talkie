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

    private static let dismissedKey = "iCloudBannerDismissed"

    @Published private(set) var status: iCloudStatus = .checking
    @Published var isDismissed: Bool {
        didSet {
            UserDefaults.standard.set(isDismissed, forKey: Self.dismissedKey)
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
        self.isDismissed = UserDefaults.standard.bool(forKey: Self.dismissedKey)

        checkStatus()

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

    func checkStatus() {
        #if DEBUG
        // If simulating, don't update from real status
        if simulatedStatus != nil { return }
        #endif

        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")

        container.accountStatus { [weak self] accountStatus, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                var newStatus: iCloudStatus

                if let error = error {
                    AppLogger.persistence.error("iCloud status check error: \(error.localizedDescription)")
                    newStatus = .error(error.localizedDescription)
                } else {
                    switch accountStatus {
                    case .available:
                        newStatus = .available
                        AppLogger.persistence.info("iCloud status: Available")
                    case .noAccount:
                        newStatus = .noAccount
                        AppLogger.persistence.warning("iCloud status: No Account")
                    case .restricted:
                        newStatus = .restricted
                        AppLogger.persistence.warning("iCloud status: Restricted")
                    case .couldNotDetermine:
                        newStatus = .couldNotDetermine
                        AppLogger.persistence.warning("iCloud status: Could not determine")
                    case .temporarilyUnavailable:
                        newStatus = .temporarilyUnavailable
                        AppLogger.persistence.warning("iCloud status: Temporarily unavailable")
                    @unknown default:
                        newStatus = .couldNotDetermine
                        AppLogger.persistence.warning("iCloud status: Unknown")
                    }
                }

                self.realStatus = newStatus

                #if DEBUG
                // Only update published status if not simulating
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
