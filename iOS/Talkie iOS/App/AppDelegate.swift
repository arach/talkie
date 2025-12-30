//
//  AppDelegate.swift
//  Talkie iOS
//
//  Handles push notifications for instant CloudKit sync
//

import UIKit
import CloudKit
import UserNotifications
import AVFoundation
import CoreMedia

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications
        application.registerForRemoteNotifications()

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions for local notifications (workflow completion alerts)
        requestNotificationPermissions()

        // Set up CloudKit subscription for instant sync
        setupCloudKitSubscription()

        // Activate Watch connectivity and set up audio handler
        setupWatchAudioHandler()

        return true
    }

    // MARK: - Watch Audio Handler

    private func setupWatchAudioHandler() {
        WatchSessionManager.shared.onAudioReceived = { [weak self] audioURL, metadata in
            Task {
                await self?.createMemoFromWatchAudio(audioURL: audioURL, metadata: metadata)
            }
        }
    }

    private func createMemoFromWatchAudio(audioURL: URL, metadata: [String: Any]) async {
        AppLogger.app.info("[Watch] Creating memo from Watch audio: \(audioURL.lastPathComponent)")

        let context = PersistenceController.shared.container.viewContext

        // Get audio duration
        let asset = AVURLAsset(url: audioURL)
        let durationValue = try? await asset.load(.duration)
        let duration = durationValue.map { CMTimeGetSeconds($0) } ?? 0

        // Create the memo
        let newMemo = VoiceMemo(context: context)
        newMemo.id = UUID()
        newMemo.title = "Watch Recording \(formatWatchDate(Date()))"
        newMemo.createdAt = Date()
        newMemo.duration = duration.isNaN ? 0 : duration
        newMemo.fileURL = audioURL.lastPathComponent
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
        newMemo.originDeviceId = "watch-\(PersistenceController.deviceId)"
        newMemo.autoProcessed = false  // Mark for macOS auto-run processing

        // Load and store audio data for CloudKit sync
        do {
            let audioData = try Data(contentsOf: audioURL)
            newMemo.audioData = audioData
            AppLogger.app.info("[Watch] Audio data loaded: \(audioData.count) bytes")
        } catch {
            AppLogger.app.warning("[Watch] Failed to load audio data: \(error.localizedDescription)")
        }

        do {
            try context.save()
            AppLogger.persistence.info("[Watch] Memo saved from Watch recording")

            // Update widget with new memo
            PersistenceController.refreshWidgetData(context: context)

            let memoObjectID = newMemo.objectID

            // Start transcription after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)

                if let savedMemo = context.object(with: memoObjectID) as? VoiceMemo {
                    AppLogger.transcription.info("[Watch] Starting transcription for Watch memo")
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: context)
                }
            }
        } catch {
            let nsError = error as NSError
            AppLogger.persistence.error("[Watch] Error saving Watch memo: \(nsError.localizedDescription)")
        }
    }

    private func formatWatchDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                AppLogger.app.error("Notification permission error: \(error.localizedDescription)")
            } else if granted {
                AppLogger.app.info("Notification permissions granted")
            } else {
                AppLogger.app.info("Notification permissions denied")
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLogger.app.info("Registered for remote notifications: \(tokenString.prefix(20))...")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.app.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        AppLogger.app.info("[Push] Received remote notification")

        // Log raw notification for debugging
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                let title = alert["title"] as? String ?? ""
                let body = alert["body"] as? String ?? ""
                AppLogger.app.info("[Push] Alert - title: '\(title)', body: '\(body)'")

                // Skip processing for test/example notifications
                if title.lowercased().contains("example") || body.lowercased().contains("example") {
                    AppLogger.app.info("[Push] Ignoring example notification")
                    completionHandler(.noData)
                    return
                }
            }
        }

        // Check if this is a CloudKit notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo as! [String: NSObject]) {
            handleCloudKitNotification(ckNotification)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    private func handleCloudKitNotification(_ notification: CKNotification) {
        AppLogger.app.info("[Push] CloudKit notification type: \(notification.notificationType.rawValue)")

        if let subscriptionID = notification.subscriptionID {
            AppLogger.app.info("[Push] Subscription ID: \(subscriptionID)")
        }

        // If this is a query notification (from PushNotification subscription), fetch the record
        if notification.subscriptionID == "talkie-ios-push-notification",
           let queryNotification = notification as? CKQueryNotification,
           let recordID = queryNotification.recordID {
            fetchPushNotificationRecord(recordID: recordID)
        }

        AppLogger.persistence.info("[Push] CloudKit sync triggered")
    }

    /// Fetch the PushNotification record to get memoId for deep linking
    private func fetchPushNotificationRecord(recordID: CKRecord.ID) {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase

        privateDB.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                AppLogger.app.error("[Push] Failed to fetch notification record: \(error.localizedDescription)")
                return
            }

            guard let record = record else { return }

            // Extract memoId from the record
            if let memoIdString = record["CD_memoId"] as? String,
               let memoId = UUID(uuidString: memoIdString) {
                AppLogger.app.info("[Push] Notification for memo: \(memoId)")

                // Store for when user taps the notification
                DispatchQueue.main.async {
                    self.pendingNotificationMemoId = memoId
                }
            }
        }
    }

    /// Memo ID from the most recent push notification (for deep linking on tap)
    private var pendingNotificationMemoId: UUID?

    private func setupCloudKitSubscription() {
        AppLogger.app.info("[Push] Setting up CloudKit subscriptions...")

        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase

        // Create a subscription to the Core Data CloudKit zone
        // NSPersistentCloudKitContainer uses "com.apple.coredata.cloudkit.zone"
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Set up zone subscription for general sync (silent push)
        let zoneSubscriptionID = "talkie-ios-private-db-subscription"
        setupZoneSubscription(database: privateDB, subscriptionID: zoneSubscriptionID, zoneID: zoneID)

        // Set up query subscription for PushNotification records (visible push notification from macOS)
        let pushNotificationSubscriptionID = "talkie-ios-push-notification"
        setupPushNotificationSubscription(database: privateDB, subscriptionID: pushNotificationSubscriptionID, zoneID: zoneID)
    }

    private func setupZoneSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        // Check if subscription already exists
        database.fetch(withSubscriptionID: subscriptionID) { [weak self] existingSubscription, error in
            if existingSubscription != nil {
                AppLogger.app.info("CloudKit zone subscription already exists")
                return
            }

            // Create new zone subscription for silent sync
            self?.createZoneSubscription(database: database, subscriptionID: subscriptionID, zoneID: zoneID)
        }
    }

    private func createZoneSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)

        // Minimal notification - just badge update, no background wake
        // NSPersistentCloudKitContainer handles sync automatically when app launches
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = false // Don't wake app for every change
        notificationInfo.shouldBadge = false
        subscription.notificationInfo = notificationInfo

        database.save(subscription) { savedSubscription, error in
            if let error = error {
                AppLogger.app.error("Failed to create zone subscription: \(error.localizedDescription)")
            } else {
                AppLogger.app.info("CloudKit zone subscription created successfully")
            }
        }
    }

    // Bump this version when changing subscription configuration to force recreation
    private static let pushSubscriptionVersion = 2

    private func setupPushNotificationSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        let versionKey = "pushSubscriptionVersion"
        let savedVersion = UserDefaults.standard.integer(forKey: versionKey)

        // Check if subscription already exists
        database.fetch(withSubscriptionID: subscriptionID) { [weak self] existingSubscription, error in
            if let error = error {
                AppLogger.app.error("[Push] Error checking subscription: \(error.localizedDescription)")
            }

            // If subscription exists but version changed, delete and recreate
            if existingSubscription != nil {
                if savedVersion < Self.pushSubscriptionVersion {
                    AppLogger.app.info("[Push] Subscription version changed (\(savedVersion) → \(Self.pushSubscriptionVersion)), recreating...")
                    database.delete(withSubscriptionID: subscriptionID) { _, deleteError in
                        if let deleteError = deleteError {
                            AppLogger.app.error("[Push] Failed to delete old subscription: \(deleteError.localizedDescription)")
                        } else {
                            AppLogger.app.info("[Push] Old subscription deleted")
                            self?.createPushNotificationSubscription(database: database, subscriptionID: subscriptionID, zoneID: zoneID)
                            UserDefaults.standard.set(Self.pushSubscriptionVersion, forKey: versionKey)
                        }
                    }
                } else {
                    AppLogger.app.info("[Push] PushNotification subscription already exists (v\(savedVersion))")
                }
                return
            }

            // Create new query subscription for PushNotification records
            self?.createPushNotificationSubscription(database: database, subscriptionID: subscriptionID, zoneID: zoneID)
            UserDefaults.standard.set(Self.pushSubscriptionVersion, forKey: versionKey)
        }
    }

    private func createPushNotificationSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        // Core Data prefixes record types with "CD_"
        // Subscribe to new PushNotification records created by macOS
        let predicate = NSPredicate(value: true) // All PushNotification records

        let subscription = CKQuerySubscription(
            recordType: "CD_PushNotification",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation] // Only notify on new records
        )

        // Configure visible push notification using record fields
        let notificationInfo = CKSubscription.NotificationInfo()
        // Use localization keys that map to Localizable.strings
        // PUSH_NOTIFICATION_TITLE = "%1$@" will substitute CD_title
        // PUSH_NOTIFICATION_BODY = "%1$@" will substitute CD_body
        notificationInfo.titleLocalizationKey = "PUSH_NOTIFICATION_TITLE"
        notificationInfo.titleLocalizationArgs = ["CD_title"]
        notificationInfo.alertLocalizationKey = "PUSH_NOTIFICATION_BODY"
        notificationInfo.alertLocalizationArgs = ["CD_body"]
        notificationInfo.soundName = "default"
        notificationInfo.shouldSendContentAvailable = true // Also trigger background fetch
        notificationInfo.shouldBadge = false
        // Include desired keys so we can fetch memoId for deep linking
        notificationInfo.desiredKeys = ["CD_memoId", "CD_title", "CD_body"]

        subscription.notificationInfo = notificationInfo
        subscription.zoneID = zoneID

        database.save(subscription) { savedSubscription, error in
            if let error = error {
                AppLogger.app.error("[Push] Failed to create subscription: \(error.localizedDescription)")
            } else {
                AppLogger.app.info("[Push] Subscription created successfully")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Filter out test/example notifications (likely from CloudKit schema initialization)
        let title = notification.request.content.title.lowercased()
        let body = notification.request.content.body.lowercased()
        if title.contains("example") || body.contains("example") ||
           title.contains("test") && title.contains("data") {
            AppLogger.app.info("[Push] Suppressing test/example notification: \(notification.request.content.title)")
            completionHandler([]) // Don't show
            return
        }

        // Show notifications even when app is in foreground (for workflow completions)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        AppLogger.app.info("[Push] User tapped notification")

        let userInfo = response.notification.request.content.userInfo

        // Try to extract memoId from CloudKit notification
        if let ckDict = userInfo as? [String: NSObject],
           let ckNotification = CKQueryNotification(fromRemoteNotificationDictionary: ckDict),
           let recordID = ckNotification.recordID {
            AppLogger.app.info("[Push] CloudKit notification tapped, fetching memoId...")

            // Fetch the record to get memoId
            let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
            let privateDB = container.privateCloudDatabase

            privateDB.fetch(withRecordID: recordID) { [weak self] record, error in
                DispatchQueue.main.async {
                    if let record = record,
                       let memoIdData = record["CD_memoId"],
                       let memoId = self?.extractUUID(from: memoIdData) {
                        AppLogger.app.info("[Push] Deep linking to memo: \(memoId)")
                        DeepLinkManager.shared.pendingAction = .openMemoActivity(id: memoId)
                    } else if let error = error {
                        AppLogger.app.error("[Push] Failed to fetch record: \(error.localizedDescription)")
                    }
                }
            }
        } else if let memoId = pendingNotificationMemoId {
            // Fallback to cached memoId
            AppLogger.app.info("[Push] Deep linking to memo (cached): \(memoId)")
            DeepLinkManager.shared.pendingAction = .openMemoActivity(id: memoId)
            pendingNotificationMemoId = nil
        }

        completionHandler()
    }

    /// Extract UUID from CloudKit record field (handles both String and Data formats)
    private func extractUUID(from value: Any) -> UUID? {
        if let uuidString = value as? String {
            return UUID(uuidString: uuidString)
        }
        // Core Data sometimes stores UUIDs as binary data
        if let data = value as? Data, data.count == 16 {
            return UUID(uuid: data.withUnsafeBytes { $0.load(as: uuid_t.self) })
        }
        return nil
    }
}
