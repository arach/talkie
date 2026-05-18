//
//  KeyboardActivationNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — keyboard extension activation flow. Three
//  states: not added / added but no Full Access / enabled. Donor is
//  KeyboardActivationView (829 lines); rich detection + deep-link
//  flows still live there.
//

import SwiftUI
import TalkieMobileKit
import UIKit

@MainActor
final class KeyboardActivationStore: ObservableObject {
    @Published var state: ActivationState

    enum ActivationState {
        case notAdded, partial, ready

        var heading: String {
            switch self {
            case .notAdded: return "Add the Talkie keyboard"
            case .partial:  return "One more step"
            case .ready:    return "You're all set"
            }
        }
        var subhead: String {
            switch self {
            case .notAdded: return "Talkie's keyboard is what unlocks voice everywhere — it works in any app the system keyboard does."
            case .partial:  return "The keyboard's added but needs Full Access to talk to your memos and dictate offline."
            case .ready:    return "Tap the globe key on any keyboard to switch to Talkie. Hold to talk."
            }
        }
        var glyph: String {
            switch self {
            case .notAdded: return "keyboard"
            case .partial:  return "exclamationmark.shield"
            case .ready:    return "checkmark.circle.fill"
            }
        }
    }

    init() {
        self.state = .partial
        refresh()
    }

    func refresh() {
        let bridge = KeyboardBridge.shared
        if bridge.getKeyboardModeEnabled() {
            state = .ready
        } else if bridge.isAppGroupAccessible {
            state = .partial
        } else {
            state = .notAdded
        }
    }
}

struct KeyboardActivationNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = KeyboardActivationStore()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    stepsCard
                        .padding(.horizontal, 12)

                    Spacer(minLength: 60)
                }
            }
            .scrollIndicators(.hidden)

            footer
        }
    }

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Keyboard")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: store.state.glyph)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text(store.state.heading)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(theme.colors.textPrimary)
                .lineSpacing(2)

            Text(store.state.subhead)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(n: 1, label: "Open Settings", done: store.state != .notAdded)
            divider
            stepRow(n: 2, label: "Add Talkie keyboard", done: store.state != .notAdded)
            divider
            stepRow(n: 3, label: "Enable Full Access", done: store.state == .ready)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeSubtle)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
            .padding(.leading, 50)
    }

    private func stepRow(n: Int, label: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? theme.currentTheme.chrome.accent : Color.clear)
                    .overlay(Circle().strokeBorder(
                        done ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    ))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.colors.cardBackground)
                } else {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .frame(width: 22, height: 22)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(done ? theme.colors.textSecondary : theme.colors.textPrimary)
                .strikethrough(done, color: theme.colors.textTertiary)

            Spacer()

            if done {
                Text("DONE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(action: footerTapped) {
                Text(footerCTA)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .onAppear { store.refresh() }
    }

    private func footerTapped() {
        if store.state == .ready {
            AppShellRouter.shared.openHome()
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var footerCTA: String {
        switch store.state {
        case .notAdded: return "Open Settings"
        case .partial:  return "Enable Full Access"
        case .ready:    return "Done ›"
        }
    }
}
