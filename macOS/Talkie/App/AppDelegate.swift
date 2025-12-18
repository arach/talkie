//
//  AppDelegate.swift
//  Talkie macOS
//
//  Handles push notifications for instant CloudKit sync
//

import AppKit
import CloudKit
import UserNotifications
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure window appearance to match theme before SwiftUI renders
        // This prevents the "flicker" of default colors before theme loads
        configureWindowAppearance()

        // Set notification delegate to show notifications while app is in foreground
        UNUserNotificationCenter.current().delegate = self

        // Request local notification permissions for workflow notifications
        requestNotificationPermissions()

        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Set up CloudKit subscription for instant sync
        setupCloudKitSubscription()

        // Ensure helper apps (TalkieLive, TalkieEngine) are running
        // This registers them as login items and launches them if needed
        Task { @MainActor in
            AppLauncher.shared.ensureHelpersRunning()
        }

        // Register URL handler for Apple Events
        let eventManager = NSAppleEventManager.shared()
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        logger.info("URL handler registered")
    }

    // MARK: - URL Handling

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("[AppDelegate] Invalid URL event received")
            logger.warning("Invalid URL event received")
            return
        }

        NSLog("[AppDelegate] Received URL: \(urlString)")
        logger.info("Received URL: \(urlString)")

        guard url.scheme == "talkie" else {
            NSLog("[AppDelegate] URL not handled: invalid scheme")
            return
        }

        // Handle talkie://live - navigate to Live section
        if url.host == "live" {
            NSLog("[AppDelegate] Navigating to Live section")
            logger.info("Navigating to Live section")
            NotificationCenter.default.post(name: .navigateToLive, object: nil)
        }
        // Handle talkie://interstitial/{id}
        else if url.host == "interstitial",
           let idString = url.pathComponents.dropFirst().first,
           let id = Int64(idString) {
            NSLog("[AppDelegate] Opening interstitial for utterance ID: \(id)")
            logger.info("Opening interstitial for utterance ID: \(id)")
            Task { @MainActor in
                InterstitialManager.shared.show(utteranceId: id)
            }
        } else {
            NSLog("[AppDelegate] URL not handled: scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
        }
    }

    private func configureWindowAppearance() {
        // Apply appearance mode from saved preferences
        let settings = SettingsManager.shared

        // Set the application-wide appearance to match user preference
        switch settings.appearanceMode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil  // Follow system
        }

        // Configure window style for any existing windows
        for window in NSApp.windows {
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isOpaque = true
            // Prevent blur effect when window is inactive by disabling layer caching
            window.contentView?.wantsLayer = true
            window.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Force redraw when app becomes active to ensure crisp rendering
        for window in NSApp.windows {
            window.contentView?.needsDisplay = true
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logger.info("✅ Local notification permissions granted")
            } else if let error = error {
                logger.warning("⚠️ Notification permission error: \(error.localizedDescription)")
            } else {
                logger.info("ℹ️ Local notification permissions denied")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is active
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("📬 User tapped notification: \(response.notification.request.identifier)")
        completionHandler()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("✅ Registered for remote notifications: \(tokenString.prefix(20))...")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // This is expected in debug builds without Push Notification entitlement
        // Sync still works via 5-minute timer; push is only for instant sync in production
        #if DEBUG
        logger.info("Push notifications unavailable (debug build) - using timer sync")
        #else
        logger.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        logger.info("📬 Received remote notification")

        // Check if this is a CloudKit notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            handleCloudKitNotification(ckNotification)
        }
    }

    private func handleCloudKitNotification(_ notification: CKNotification) {
        logger.info("☁️ CloudKit notification received: \(notification.notificationType.rawValue)")

        // Trigger a token-based sync to fetch only changed records
        Task { @MainActor in
            CloudKitSyncManager.shared.syncNow()
        }
    }

    private func setupCloudKitSubscription() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase

        // Create a subscription to the Core Data CloudKit zone
        // NSPersistentCloudKitContainer uses "com.apple.coredata.cloudkit.zone"
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        let subscriptionID = "talkie-private-db-subscription"

        // Check if subscription already exists
        privateDB.fetch(withSubscriptionID: subscriptionID) { [weak self] existingSubscription, error in
            if existingSubscription != nil {
                logger.info("✅ CloudKit subscription already exists")
                return
            }

            // Create new subscription
            self?.createDatabaseSubscription(database: privateDB, subscriptionID: subscriptionID, zoneID: zoneID)
        }
    }

    private func createDatabaseSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        // Use CKRecordZoneSubscription for zone-specific changes
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)

        // Configure notification info for silent push
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        database.save(subscription) { savedSubscription, error in
            if let error = error {
                logger.error("❌ Failed to create CloudKit subscription: \(error.localizedDescription)")
            } else {
                logger.info("✅ CloudKit subscription created successfully")
            }
        }
    }
}
