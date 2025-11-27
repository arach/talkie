//
//  AppDelegate.swift
//  Talkie macOS
//
//  Handles push notifications for instant CloudKit sync
//

import AppKit
import CloudKit
import os

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Set up CloudKit subscription for instant sync
        setupCloudKitSubscription()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("✅ Registered for remote notifications: \(tokenString.prefix(20))...")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
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
