//
//  DeckMirrorNext.swift
//  Talkie iOS
//
//  iOS-side mirror of the macOS Command Deck. Renders the same 4×4
//  shortcut grid the user has on the Mac, with Space tabs along the
//  top. Single-tap a tile to fire the slot on the Mac via the bridge.
//
//  Paint pass — view reads `DeckMirrorStore.shared`. Codex wires the
//  store from the bridge event stream + the send-slot endpoint.
//

import SwiftUI

struct DeckMirrorNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var selectedSpaceID: String?
    @State private var showingAppSwitcher = false
    @State private var activatingAppID: String?
    @State private var appSwitcherErrorMessage: String?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                if let board = deck.board, !board.spaces.isEmpty {
                    boardContent(board)
                } else {
                    emptyState
                }
            }
        }
        .onAppear {
            if selectedSpaceID == nil {
                selectedSpaceID = deck.board?.activeSpaceID ?? deck.board?.spaces.first?.id
            }
        }
        .sheet(isPresented: $showingAppSwitcher) {
            DeckAppSwitcherSheet(
                apps: appSwitcherApps,
                activeAppID: frontmostApp?.id,
                activatingAppID: activatingAppID,
                errorMessage: appSwitcherErrorMessage,
                onRefresh: refreshAppSwitcher,
                onActivate: activateApp
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · DECK")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            if let macName = bridgeManager.pairedMacDisplayName {
                Button(action: openAppSwitcher) {
                    HStack(spacing: 4) {
                        Text("· \(macName)")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if frontmostApp != nil {
                            Circle()
                                .fill(Color(red: 0.36, green: 0.74, blue: 0.50))
                                .frame(width: 5, height: 5)
                                .accessibilityLabel("Active Mac app")
                        }

                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mac app switcher")
                .accessibilityHint("Shows running apps on \(macName)")
            }

            Spacer()

            Button(action: { AppShellRouter.shared.openHome() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close deck")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Board

    @ViewBuilder
    private func boardContent(_ board: DeckBoardSnapshot) -> some View {
        VStack(spacing: 0) {
            spaceTabs(board.spaces, mirroredActiveID: board.activeSpaceID)

            if let space = currentSpace(in: board) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if deckNetworkStatus != .ok {
                            NetworkStatusBanner(status: deckNetworkStatus, onRetry: retryBridge)
                                .padding(.horizontal, 16)
                        }

                        if let result = deck.lastTriggerResult {
                            triggerResultBanner(result)
                                .padding(.horizontal, 16)
                        }

                        if let error = deck.lastErrorMessage {
                            errorBanner(error)
                                .padding(.horizontal, 16)
                        }

                        tileGrid(space.tiles)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        Spacer(minLength: 96)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            if deckNetworkStatus != .ok {
                NetworkStatusBanner(status: deckNetworkStatus, onRetry: retryBridge)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            VStack(spacing: 14) {
                Spacer(minLength: 60)

                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                        .frame(width: 68, height: 68)
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }

                Text("Deck not available")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)

                Text(emptyStateMessage)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !bridgeManager.isPaired {
            return "Pair a Mac to mirror its Command Deck here."
        }
        if bridgeManager.status != .connected {
            return "Waiting for the Mac to come online so it can ship the deck state across."
        }
        return "The Mac hasn't sent a deck snapshot yet. Open the deck on the Mac side to populate this surface."
    }

    // MARK: - Space tabs

    private func spaceTabs(_ spaces: [DeckSpace], mirroredActiveID: String?) -> some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                let isSelected = space.id == (selectedSpaceID ?? mirroredActiveID)
                let isMacActive = space.id == mirroredActiveID
                Button(action: { selectedSpaceID = space.id }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(space.title.uppercased())
                                .talkieType(.channelLabel)
                                .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textTertiary)
                            if isMacActive {
                                Circle()
                                    .fill(Color(red: 0.36, green: 0.74, blue: 0.50))
                                    .frame(width: 5, height: 5)
                                    .accessibilityLabel("Active on Mac")
                            }
                        }
                        Rectangle()
                            .fill(isSelected ? theme.currentTheme.chrome.accent : Color.clear)
                            .frame(height: 1.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    private func currentSpace(in board: DeckBoardSnapshot) -> DeckSpace? {
        let target = selectedSpaceID ?? board.activeSpaceID
        return board.spaces.first { $0.id == target } ?? board.spaces.first
    }

    // MARK: - Tile grid

    private func tileGrid(_ tiles: [DeckTile]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(tiles) { tile in
                tileView(tile)
            }
        }
    }

    private func tileView(_ tile: DeckTile) -> some View {
        let isFiring = deck.firingSlotID == tile.slotID
        let isEmpty = tile.slotID == nil
        let triggerResult = triggerResult(for: tile)
        let isResultTile = triggerResult != nil
        let isActive = isFiring || isResultTile
        let activeColor = triggerResult.map(triggerResultColor) ?? theme.currentTheme.chrome.accent

        return Button(action: {
            guard let slot = tile.slotID else { return }
            deck.fire(slotID: slot)
        }) {
            VStack(spacing: 6) {
                Image(systemName: tile.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(
                        isEmpty
                            ? theme.colors.textTertiary.opacity(0.45)
                            : activeColor
                    )
                    .frame(height: 24)

                Text(tile.label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(
                        isEmpty
                            ? theme.colors.textTertiary
                            : theme.colors.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let hint = tile.hint {
                    Text(hint.uppercased())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                } else {
                    Color.clear.frame(height: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isActive
                            ? activeColor.opacity(0.22)
                            : theme.colors.cardBackground.opacity(isEmpty ? 0.4 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isActive
                                    ? activeColor
                                    : (isEmpty
                                        ? theme.currentTheme.chrome.edgeFaint.opacity(0.5)
                                        : theme.currentTheme.chrome.edgeFaint),
                                style: isEmpty
                                    ? StrokeStyle(
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth,
                                        dash: [3, 3]
                                    )
                                    : StrokeStyle(lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            )
                    )
            )
            .shadow(
                color: isActive ? activeColor.opacity(0.45) : .clear,
                radius: isActive ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || deck.firingSlotID != nil)
        .accessibilityLabel(isEmpty ? "Empty slot" : tile.label)
        .accessibilityHint(isEmpty ? "" : "Fires on the Mac")
    }

    private func triggerResult(for tile: DeckTile) -> DeckMirrorStore.TriggerResult? {
        guard let slotID = tile.slotID,
              let result = deck.lastTriggerResult,
              result.slotID == slotID else {
            return nil
        }

        return result
    }

    // MARK: - App switcher

    private var appSwitcherApps: [CompanionAppSwitcherApp] {
        bridgeManager.companionState?.appSwitcherApps ?? []
    }

    private var frontmostApp: CompanionAppSwitcherApp? {
        appSwitcherApps.first(where: { $0.isFrontmost })
    }

    private func openAppSwitcher() {
        appSwitcherErrorMessage = nil
        showingAppSwitcher = true
        refreshAppSwitcher()
    }

    private func refreshAppSwitcher() {
        Task {
            await bridgeManager.refreshCompanionState()
        }
    }

    private func activateApp(_ app: CompanionAppSwitcherApp) {
        guard activatingAppID == nil else { return }
        appSwitcherErrorMessage = nil
        activatingAppID = app.id

        Task {
            do {
                let response = try await bridgeManager.activateCompanionApp(app)
                if response.ok {
                    showingAppSwitcher = false
                } else {
                    appSwitcherErrorMessage = response.error
                        ?? response.message
                        ?? "The Mac could not activate \(app.displayName)."
                }
            } catch {
                appSwitcherErrorMessage = error.localizedDescription
            }

            activatingAppID = nil
        }
    }

    private var deckNetworkStatus: NetworkStatus {
        if bridgeManager.isPaired,
           bridgeManager.status != .connected,
           reachability.status == .offline {
            return .offline
        }

        if bridgeManager.status == .error,
           let message = bridgeManager.errorMessage {
            return .requestFailed(message: message)
        }

        return .ok
    }

    private func retryBridge() {
        Task {
            await bridgeManager.retry()
        }
    }

    private func triggerResultBanner(_ result: DeckMirrorStore.TriggerResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: triggerResultIcon(result))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(triggerResultColor(result))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(triggerResultTitle(result))
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(result.message)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            triggerResultColor(result).opacity(0.45),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    private func triggerResultTitle(_ result: DeckMirrorStore.TriggerResult) -> String {
        switch result.outcome {
        case .pending: return "Sending to Mac"
        case .running: return "Running on Mac"
        case .succeeded: return "Mac shortcut complete"
        case .failed: return "Mac shortcut failed"
        }
    }

    private func triggerResultIcon(_ result: DeckMirrorStore.TriggerResult) -> String {
        switch result.outcome {
        case .pending, .running: return "bolt.horizontal.circle"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func triggerResultColor(_ result: DeckMirrorStore.TriggerResult) -> Color {
        switch result.outcome {
        case .pending, .running:
            return theme.currentTheme.chrome.accent
        case .succeeded:
            return Color(red: 0.36, green: 0.74, blue: 0.50)
        case .failed:
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                .accessibilityHidden(true)
            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct DeckAppSwitcherSheet: View {
    let apps: [CompanionAppSwitcherApp]
    let activeAppID: String?
    let activatingAppID: String?
    let errorMessage: String?
    let onRefresh: () -> Void
    let onActivate: (CompanionAppSwitcherApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage {
                        errorRow(errorMessage)
                    }

                    if apps.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 8) {
                            ForEach(apps) { app in
                                appRow(app)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Mac Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        onRefresh()
                    }
                    .disabled(activatingAppID != nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No running apps yet")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Keep the Mac bridge connected, then refresh to load the current app runtime list.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    private func appRow(_ app: CompanionAppSwitcherApp) -> some View {
        let isActive = app.id == activeAppID
        let isActivating = app.id == activatingAppID

        return Button(action: { onActivate(app) }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.currentTheme.chrome.accent.opacity(isActive ? 0.14 : 0.08))
                    Image(systemName: isActive ? "macwindow.on.rectangle" : "macwindow")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            isActive
                                ? theme.currentTheme.chrome.accent
                                : theme.colors.textSecondary
                        )
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.displayName)
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(app.bundleIdentifier ?? "pid \(app.processIdentifier)")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                } else if isActive {
                    Text("ACTIVE")
                        .talkieType(.chipLabel)
                        .foregroundStyle(Color(red: 0.36, green: 0.74, blue: 0.50))
                } else {
                    Text("OPEN")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isActive
                                    ? theme.currentTheme.chrome.accent.opacity(0.45)
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isActive || activatingAppID != nil)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                .accessibilityHidden(true)
            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }
}
