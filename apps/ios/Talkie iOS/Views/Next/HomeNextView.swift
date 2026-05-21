//
//  HomeNextView.swift
//  Talkie iOS
//
//  M1 — Talkie's canonical iPhone home, painted to match the
//  studio mock at http://localhost:3000/home.
//
//  Composition: TALKIE wordmark · PICK UP card (continue last
//  document) · smart Action Bus (auto-rolling 24h→7d→30d) ·
//  Recent list (2-line iOS-Notes style). The ambient voice
//  button lives in AppShellNext, not here.
//
//  Spec: design/studio/app/home/SWIFT_PORT.md
//  Visual reference: design/studio/app/home/page.tsx
//
//  Type system: TalkieTypeStyle tokens (see TalkieType.swift).
//  No raw .font(.system(...)) calls here — channel labels, body
//  serif, and instrument readouts all flow through .talkieType(...).
//

import SwiftUI

struct HomeNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var feed: HomeFeed

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                StationCard(
                    pickUp: feed.lastDocument,
                    tally: feed.recentTally
                )
                .padding(.horizontal, 12)

                RecentSection(items: feed.recentItems)
                    .padding(.horizontal, 12)

                Spacer(minLength: 80)   // breathing room for the shell voice button
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        // Gear is 40×40 with the same chrome as the corner Settings
        // complication (`ChromeOverlay.CornerSlot`) so when the shell
        // summons, the gear stays visually in place — it doesn't shift
        // size or move. Right-edge inset matches the corner slot
        // padding (20pt) so x-coordinates line up. Left side mirrors
        // that 40pt footprint with a row of three ambient status
        // pixels (Mac · iCloud · Account) so the wordmark stays
        // centered while the chrome carries live system state.
        HStack {
            // Single Mac connection complication on the left.
            // Hidden entirely when no Mac is paired. Frame stays
            // 40pt tall so the header keeps its rhythm even when
            // the chip is absent (Spacer takes over).
            MacConnectionChip()
                .frame(minHeight: 40, alignment: .leading)
            Spacer()
            Text("TALKIE")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
            Spacer()
            Button(action: { AppShellRouter.shared.openSettings() }) {
                ZStack {
                    Circle().fill(theme.colors.cardBackground)
                    Circle().strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Ambient status row (Mac · iCloud · Account)

/// Single Mac connection complication at the top-left of Home.
/// Replaces the prior four-pixel AmbientStatusRow — fingers can't
/// reliably hit 6pt dots, and the row was visually noisy without
/// being useful. This chip uses the `point.3.connected.trianglepath`
/// SF Symbol (same one ConnectionCenterNext uses as its hero) and
/// adapts based on bridge + deck state:
///
///   - Connected + deck snapshot available → tap opens DeckMirrorNext
///   - Any other paired state                → tap opens ConnectionCenter
///   - Not paired                            → chip hidden entirely
///
/// Account sign-in and iCloud sync pixels were removed from the
/// home header — both live in Settings → CONNECT where they can be
/// acted on. They didn't earn the home real estate.
private struct MacConnectionChip: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if bridgeManager.isPaired {
            Button(action: handleTap) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor)
                    Text(chipLabel)
                        .talkieType(.channelLabelSmall)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    borderColor,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
        }
    }

    // MARK: - State derivation

    private var hasDeckBoard: Bool {
        guard let board = deck.board else { return false }
        return !board.spaces.isEmpty
    }

    private var isConnected: Bool {
        bridgeManager.status == .connected
    }

    private func handleTap() {
        if isConnected && hasDeckBoard {
            AppShellRouter.shared.openDeck()
        } else {
            AppShellRouter.shared.openConnectionCenter()
        }
    }

    private var showsChevron: Bool {
        isConnected && hasDeckBoard
    }

    // MARK: - Visual treatment per state

    private var chipLabel: String {
        if bridgeManager.awaitingPairingApproval {
            return "PENDING APPROVAL"
        }
        switch bridgeManager.status {
        case .connected:
            if hasDeckBoard { return "DECK" }
            let name = bridgeManager.pairedMacDisplayName ?? "MAC"
            return name.uppercased()
        case .connecting:
            return "CONNECTING…"
        case .disconnected:
            return "MAC · OFFLINE"
        case .error:
            return "MAC · ERROR"
        }
    }

    private var iconColor: Color {
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
        if isConnected {
            return hasDeckBoard
                ? theme.currentTheme.chrome.accent
                : Color(red: 0.36, green: 0.74, blue: 0.50)
        }
        return theme.colors.textTertiary
    }

    private var labelColor: Color {
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
        if isConnected && hasDeckBoard {
            return theme.colors.textPrimary
        }
        return theme.colors.textSecondary
    }

    private var borderColor: Color {
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.5)
        }
        if isConnected && hasDeckBoard {
            return theme.currentTheme.chrome.accent.opacity(0.55)
        }
        return theme.currentTheme.chrome.edgeFaint
    }

    private var accessibilityLabel: String {
        let mac = bridgeManager.pairedMacDisplayName ?? "Mac"
        if bridgeManager.awaitingPairingApproval { return "\(mac), pending approval" }
        switch bridgeManager.status {
        case .connected:
            return hasDeckBoard ? "\(mac) deck" : "\(mac) connected"
        case .connecting: return "\(mac) connecting"
        case .disconnected: return "\(mac) offline"
        case .error: return "\(mac) error"
        }
    }

    private var accessibilityHint: String {
        isConnected && hasDeckBoard ? "Opens deck" : "Opens connection center"
    }
}

/// Legacy ambient row primitives below this point are no longer
/// used in HomeNextView's header. Kept as private types so any
/// downstream/per-test reference doesn't break — to be removed once
/// the new chip is verified.
private struct AmbientStatusRow_legacy: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var iCloudStatus = iCloudStatusManager.shared

    @ObservedObject private var deck = DeckMirrorStore.shared

    var body: some View {
        HStack(spacing: 0) {
            StatusPixel(state: macPixelState, label: "Mac bridge", value: macPixelLabel) {
                AppShellRouter.shared.openConnectionCenter()
            }
            StatusPixel(state: iCloudPixelState, label: "iCloud sync", value: iCloudPixelLabel) {
                AppShellRouter.shared.openConnectionCenter()
            }
            StatusPixel(state: signInPixelState, label: "Account", value: isSignedIn ? "signed in" : "signed out") {
                if isSignedIn {
                    AppShellRouter.shared.openConnectionCenter()
                } else {
                    AppShellRouter.shared.openSignIn()
                }
            }
            if bridgeManager.isPaired {
                StatusPixel(state: deckPixelState, label: "Mac deck", value: deckPixelLabel) {
                    AppShellRouter.shared.openDeck()
                }
            }
        }
    }

    private var deckPixelState: StatusPixel.State {
        if bridgeManager.status == .error { return .error }
        if let board = deck.board, !board.spaces.isEmpty { return .good }
        return .transient
    }

    private var deckPixelLabel: String {
        if bridgeManager.status == .error { return "error" }
        if let board = deck.board, !board.spaces.isEmpty {
            return "\(board.spaces.count) space\(board.spaces.count == 1 ? "" : "s")"
        }
        return "waiting"
    }

    private var macPixelLabel: String {
        switch macPixelState {
        case .good: return "connected"
        case .transient: return bridgeManager.isPaired ? "reconnecting" : "connecting"
        case .dim: return "not paired"
        case .error: return "connection failed"
        }
    }

    private var iCloudPixelLabel: String {
        switch iCloudPixelState {
        case .good: return "available"
        case .transient: return "syncing"
        case .dim: return "no iCloud account"
        case .error: return "error"
        }
    }

    private var macPixelState: StatusPixel.State {
        switch bridgeManager.status {
        case .connected:    return .good
        case .connecting:   return .transient
        case .error:        return .error
        case .disconnected: return bridgeManager.isPaired ? .transient : .dim
        }
    }

    private var iCloudPixelState: StatusPixel.State {
        switch iCloudStatus.status {
        case .available:                                        return .good
        case .checking, .temporarilyUnavailable,
             .couldNotDetermine:                                return .transient
        case .noAccount, .restricted:                           return .dim
        case .error:                                            return .error
        }
    }

    private var signInPixelState: StatusPixel.State {
        isSignedIn ? .good : .dim
    }

    private var isSignedIn: Bool {
        UserDefaults.standard.bool(forKey: SignInStore.signedInDefaultsKey)
    }
}

private struct StatusPixel: View {
    enum State { case good, transient, dim, error }

    let state: State
    let label: String
    let value: String
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                Circle()
                    .fill(fillColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .frame(width: 13, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) · \(value)")
        .accessibilityHint("Opens connection center")
    }

    private var fillColor: Color {
        switch state {
        case .good:      return Color(red: 0.36, green: 0.74, blue: 0.50)
        case .transient: return theme.currentTheme.chrome.accent
        case .dim:       return theme.colors.textTertiary.opacity(0.45)
        case .error:     return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
    }
}

// MARK: - STATION (PICK UP + Action Bus)

private struct StationCard: View {
    let pickUp: HomeFeed.PickUp?
    let tally: HomeFeed.Tally

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PICK UP")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)

                    if let pickUp {
                        Text(pickUp.title)
                            .talkieType(.headline)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(pickUp.meta)
                            .talkieType(.metaMono)
                            .foregroundStyle(theme.colors.textTertiary)
                    } else {
                        Text("Nothing recent")
                            .talkieType(.headlineSecondary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                if let pickUp {
                    Button(action: pickUp.continueAction) {
                        Text("CONTINUE ›")
                            .talkieType(.chipLabel)
                            .foregroundStyle(theme.colors.cardBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ActionBus(tally: tally)
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct ActionBus: View {
    let tally: HomeFeed.Tally
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.currentTheme.chrome.accent)
                    .frame(width: 5, height: 5)
                Text(tally.eyebrow)
                    .talkieType(.channelLabelSmall)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                if let cta = tally.cta {
                    Text(cta)
                        .talkieType(.channelLabelSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if !tally.cells.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(tally.cells.enumerated()), id: \.offset) { idx, cell in
                        VStack(spacing: 4) {
                            Text(cell.value)
                                .talkieType(.instrumentReadout)
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                            Text(cell.label)
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        if idx < tally.cells.count - 1 {
                            Rectangle()
                                .fill(theme.currentTheme.chrome.edgeFaint)
                                .frame(width: theme.currentTheme.chrome.hairlineWidth)
                                .padding(.vertical, 8)
                        }
                    }
                }
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .background(theme.colors.background)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }
}

// MARK: - RECENT

private struct RecentSection: View {
    let items: [HomeFeed.RecentItem]
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· RECENT · \(items.count)")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                Spacer()

                Button(action: { AppShellRouter.shared.openLibrary() }) {
                    Text("ALL ›")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    RecentRow(item: item, showDivider: idx > 0)
                }
            }
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
    }
}

private struct RecentRow: View {
    let item: HomeFeed.RecentItem
    let showDivider: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: openItem) {
            VStack(spacing: 0) {
                if showDivider {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeSubtle)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                        .padding(.leading, 36)
                }
                HStack(alignment: .top, spacing: 8) {
                    sourceGlyph
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .talkieType(.listTitle)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.relativeTime)
                                .talkieType(.timestamp)
                                .foregroundStyle(theme.colors.textTertiary)
                        }

                        if let preview = item.preview {
                            Text(preview)
                                .talkieType(.preview)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func openItem() {
        switch item.source {
        case .dictation:        AppShellRouter.shared.openMemoDetail(memoID: item.id)
        case .typed:            AppShellRouter.shared.openCompose(documentID: item.id)
        case .link, .scan:      AppShellRouter.shared.openCaptureDetail(captureID: item.id)
        }
    }

    @ViewBuilder
    private var sourceGlyph: some View {
        switch item.source {
        case .dictation:
            Image(systemName: "waveform").font(.system(size: 13))
        case .typed:
            Image(systemName: "keyboard").font(.system(size: 12))
        case .link:
            Image(systemName: "link").font(.system(size: 12))
        case .scan:
            Image(systemName: "viewfinder").font(.system(size: 12))
        }
    }
}
