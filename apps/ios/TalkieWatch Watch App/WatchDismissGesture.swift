//
//  WatchDismissGesture.swift
//  TalkieWatch
//
//  Long press to take a capture the phone has not finished with off the wrist.
//
//  Confirmed rather than immediate. A long press is easy to trigger by resting
//  a wrist on a desk or a pocket, and what it removes is the wearer's only
//  record that they said anything at all — a surface whose whole job is to stop
//  captures disappearing silently cannot itself disappear one by accident.
//

import SwiftUI
import WatchKit

struct DismissOnLongPress: ViewModifier {
    let title: String
    let confirmLabel: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isConfirming = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                // Simultaneous rather than `onLongPressGesture`, because a row
                // that also opens something wraps a link, and the link's own
                // button gesture claims the press first — the plain modifier
                // simply never fires there.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            // Fired on recognition, before the sheet draws, so
                            // the press is acknowledged by the wrist rather than
                            // by the screen — which is the point of pressing
                            // something you are not necessarily looking at.
                            WKInterfaceDevice.current().play(.click)
                            isConfirming = true
                        }
                )
                .confirmationDialog(
                    title,
                    isPresented: $isConfirming,
                    titleVisibility: .visible
                ) {
                    Button(confirmLabel, role: .destructive, action: action)
                    Button("Keep", role: .cancel) {}
                }
                // VoiceOver never gets a long press: the rotor is the only way
                // in, and it needs the action named on the element itself.
                .accessibilityAction(named: confirmLabel, action)
        } else {
            content
        }
    }
}

extension View {
    /// - Parameters:
    ///   - isEnabled: Off for anything already settled. A finished capture ages
    ///     out on its own and lives on the phone, so offering to remove it here
    ///     would promise a deletion this surface cannot perform.
    func dismissOnLongPress(
        title: String,
        confirmLabel: String = "Dismiss",
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            DismissOnLongPress(
                title: title,
                confirmLabel: confirmLabel,
                isEnabled: isEnabled,
                action: action
            )
        )
    }
}
