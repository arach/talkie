//
//  WatchAnswerNotifier.swift
//  TalkieWatch
//
//  Puts a landed answer in Notification Center so it survives a lowered wrist.
//

import Foundation
import UserNotifications

/// The tap that says an answer arrived is gone the instant it happens. If the
/// wrist was down, or came up on a watch face, the only remaining evidence is
/// inside the app — which is exactly where the wearer is not looking. This
/// leaves a card behind.
@MainActor
final class WatchAnswerNotifier: NSObject, ObservableObject {
    static let shared = WatchAnswerNotifier()

    enum Identifier {
        static let category = "talkie.answer.ready"
        static let play = "talkie.answer.play"
        static let memoIDKey = "memoID"
    }

    /// The ask the wearer opened a notification for. Published rather than
    /// handed straight to a view because the notification may have cold-started
    /// the app, in which case there is no view yet to hand it to.
    @Published private(set) var pendingAskID: UUID?
    /// They tapped Play rather than the card itself, so open into the answer
    /// already speaking instead of into a page with a play button on it.
    @Published private(set) var pendingPlayback = false

    private var hasRequestedAuthorization = false

    private var center: UNUserNotificationCenter { .current() }

    // MARK: - Setup

    /// Registers the delegate and the Play action. Safe to call more than once.
    func configure() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Identifier.category,
                actions: [
                    UNNotificationAction(
                        identifier: Identifier.play,
                        title: "Play",
                        options: [.foreground]
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    /// Asked for once per launch. A denial is not an error state worth showing:
    /// the wrist tap still fires, so the app degrades to exactly its previous
    /// behaviour rather than to nothing.
    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                WatchConsole.info(
                    "⌚️ [Watch] Notification authorization failed: \(error.localizedDescription)"
                )
            } else {
                WatchConsole.info("⌚️ [Watch] Notification authorization granted=\(granted)")
            }
        }
    }

    // MARK: - Posting

    /// Leaves a card for a settled answer.
    ///
    /// Deliberately silent. The caller has already played, or deliberately
    /// suppressed, the wrist tap for this memo — that decision runs through a
    /// persisted ledger so a single answer taps once no matter how many
    /// carriers deliver it. Letting the notification bring its own alert would
    /// route around that ledger and tap twice.
    func post(memoID: UUID, question: String?, answer: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Answer ready"
        if let question, !question.isEmpty {
            content.subtitle = question
        }
        if let answer, !answer.isEmpty {
            content.body = answer
        }
        content.sound = nil
        content.categoryIdentifier = Identifier.category
        content.userInfo = [Identifier.memoIDKey: memoID.uuidString]

        // Keyed on the memo, so a redelivery of the same answer replaces its
        // card instead of stacking a second one.
        let request = UNNotificationRequest(
            identifier: memoID.uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                WatchConsole.info(
                    "⌚️ [Watch] Answer notification failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Called when the Asks page comes forward: the wearer is looking at the
    /// answers, so leaving the cards up would make them clear the same news
    /// twice.
    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Routing

    /// Queue an ask to open. Notifications get here through the delegate below;
    /// a complication tap gets here through `DeepLinkHandler`.
    func requestOpen(askID: UUID, play: Bool) {
        pendingAskID = askID
        pendingPlayback = play
    }

    func consumePendingAsk() -> (askID: UUID, play: Bool)? {
        guard let pendingAskID else { return nil }
        let play = pendingPlayback
        self.pendingAskID = nil
        pendingPlayback = false
        return (pendingAskID, play)
    }
}

extension WatchAnswerNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let rawID = userInfo[Identifier.memoIDKey] as? String
        let actionID = response.actionIdentifier

        Task { @MainActor in
            defer { completionHandler() }
            guard let rawID, let memoID = UUID(uuidString: rawID) else { return }
            self.requestOpen(askID: memoID, play: actionID == Identifier.play)
        }
    }

    /// The app is already open and showing this state. A card on top of it says
    /// nothing new.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
