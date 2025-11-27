//
//  AppDelegate.swift
//  Talkie iOS
//
//  Handles push notifications for instant CloudKit sync
//

import UIKit
import CloudKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications
        application.registerForRemoteNotifications()

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Set up CloudKit subscription for instant sync
        setupCloudKitSubscription()

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLogger.app.info("✅ Registered for remote notifications: \(tokenString.prefix(20))...")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.app.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        AppLogger.app.info("📬 Received remote notification")

        // Check if this is a CloudKit notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo as! [String: NSObject]) {
            handleCloudKitNotification(ckNotification)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    private func handleCloudKitNotification(_ notification: CKNotification) {
        AppLogger.app.info("☁️ CloudKit notification received: \(notification.notificationType.rawValue)")

        // The NSPersistentCloudKitContainer will automatically fetch changes
        // We just log the sync event
        AppLogger.persistence.info("📥 CloudKit push notification - sync triggered")
    }

    private func setupCloudKitSubscription() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase

        // Create a subscription to the Core Data CloudKit zone
        // NSPersistentCloudKitContainer uses "com.apple.coredata.cloudkit.zone"
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        let subscriptionID = "talkie-ios-private-db-subscription"

        // Check if subscription already exists
        privateDB.fetch(withSubscriptionID: subscriptionID) { [weak self] existingSubscription, error in
            if existingSubscription != nil {
                AppLogger.app.info("✅ CloudKit subscription already exists")
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
        notificationInfo.shouldSendContentAvailable = true  // Silent push for background fetch
        subscription.notificationInfo = notificationInfo

        database.save(subscription) { savedSubscription, error in
            if let error = error {
                AppLogger.app.error("❌ Failed to create CloudKit subscription: \(error.localizedDescription)")
            } else {
                AppLogger.app.info("✅ CloudKit subscription created successfully")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Handle foreground notifications if needed
        completionHandler([])
    }
}
