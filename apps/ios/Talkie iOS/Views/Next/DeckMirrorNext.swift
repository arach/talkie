//
//  DeckMirrorNext.swift
//  Talkie iOS
//
//  iOS-side mirror of the macOS Command Deck. Renders the same 4×4
//  shortcut grid the user has on the Mac, with Space tabs along the
//  top. Single-tap a tile to fire the slot on the Mac via the bridge;
//  media slots can collect a local payload before sending.
//
//  Paint pass — view reads `DeckMirrorStore.shared`. Codex wires the
//  store from the bridge event stream + the send-slot endpoint.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DeckMirrorNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var selectedSpaceID: String?
    @State private var showingAppSwitcher = false
    @State private var activatingAppID: String?
    @State private var appSwitcherErrorMessage: String?
    @State private var isTrackpadInteracting = false
    @State private var trackpadErrorMessage: String?

    // MARK: Dictation (paint state — Codex wires the engine)
    //
    // Top-left grid tile is the dictation toggle. Idle = mic glyph,
    // label "Dictate". Active = enter glyph, label "Finish", amber-
    // armed. While active, the playback surface shows the live
    // transcript inside an elevated card.
    //
    // Contract for Codex:
    //   • Replace these @State props with bindings backed by
    //     DeckMirrorStore (suggest `isDictating: Bool` published +
    //     `liveTranscript: String?` published).
    //   • Wire start/finish to ParakeetModelManager (or Apple Speech
    //     on simulator). Stream tokens into liveTranscript; the
    //     elevated card lineLimit(3) handles overflow.
    //   • On `finish`, commit the transcript wherever the PM decides
    //     (Compose? pasteboard?). For now `finishDictation` just
    //     clears local state so the UI returns to idle.
    // Canonical Mac slot ID for "start or stop dictation". Defined in
    // apps/macos/.../DictationSettings.swift (`talkieDictate`).
    private let dictationSlotID = "talkie-dictate"

    // Derived from the Mac's runtime-state pipeline so the deck
    // reacts to dictation whether it was started from this tile,
    // from the Talkie keyboard, or from any other Mac affordance.
    // While dictating, partial transcripts arrive via
    // `runtimeState.detail`; on completion the final result lands
    // in the same `lastTriggerResult.message`.
    private var isDictating: Bool {
        guard let result = deck.lastTriggerResult else { return false }
        guard result.slotID == dictationSlotID else { return false }
        return result.outcome == .pending || result.outcome == .running
    }

    /// True while a dictation result (in any outcome) is still in
    /// flight on `lastTriggerResult`. The elevated transcript card
    /// stays visible through the post-`.succeeded` window so the
    /// final transcript reads in the same box, not as a one-line
    /// bottom echo.
    private var hasDictationResult: Bool {
        deck.lastTriggerResult?.slotID == dictationSlotID
    }

    private var liveTranscript: String {
        hasDictationResult ? (deck.lastTriggerResult?.message ?? "") : ""
    }
    @State private var imageSharePickerItem: PhotosPickerItem?

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
            // Debug-only: seed the mock board so the new cockpit/grid
            // is reviewable in the sim without a paired Mac. Triggered
            // by launching with `--deckMock`. No-op in production.
            if ProcessInfo.processInfo.arguments.contains("--deckMock"),
               deck.board == nil {
                deck.set(board: .mock)
            }
            if selectedSpaceID == nil {
                selectedSpaceID = deck.board?.activeSpaceID ?? deck.board?.spaces.first?.id
            }
            bridgeManager.setCompanionDeckVisible(true)
            warmDeckConnection()
        }
        .onDisappear {
            bridgeManager.setCompanionDeckVisible(false)
        }
        .onChange(of: deck.board) { _, board in
            guard selectedSpaceID == nil else { return }
            selectedSpaceID = board?.activeSpaceID ?? board?.spaces.first?.id
        }
        .onChange(of: imageSharePickerItem) { _, item in
            guard let item else { return }
            Task { await shareImagePickerItem(item) }
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
        .padding(.bottom, 8)
    }

    // MARK: - Board

    @ViewBuilder
    private func boardContent(_ board: DeckBoardSnapshot) -> some View {
        if let space = currentSpace(in: board) {
            VStack(spacing: 8) {
                // Floating banner slot for hard errors only. Trigger
                // results + transcripts now flow through the cockpit's
                // playback surface, so the body doesn't grow a stack.
                if let hardError = currentHardError() {
                    errorBanner(hardError)
                        .padding(.horizontal, 16)
                }

                // Cockpit ~40%, Grid ~60% via layoutPriority weights.
                // No ScrollView — the grid is a fixed 4×4 and the
                // cockpit's elevated transcript card handles overflow
                // via its own line-clamp.
                VStack(spacing: 12) {
                    cockpitSurface(space)
                        .layoutPriority(40)
                    tileGrid(space.tiles)
                        .layoutPriority(60)
                }
                .padding(.horizontal, 16)
                // 40pt lets the summon button (occupies y=16..64
                // above safe-area) barely encroach on the bottom-
                // left tile — ~24pt overlap at the tile's lower
                // edge — while keeping most of the tile visible.
                .padding(.bottom, 40)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer()
        }
    }

    /// The one banner the new layout still raises. Network outage and
    /// trackpad errors are real "something is wrong" signals; trigger
    /// results aren't (they ride the playback surface instead).
    private func currentHardError() -> String? {
        if deckNetworkStatus != .ok, let message = bridgeManager.errorMessage {
            return message
        }
        return trackpadErrorMessage
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

                Button(action: emptyStateAction) {
                    Label(emptyStateActionTitle, systemImage: emptyStateActionIcon)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint(emptyStateActionHint)

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
            return "Connect to your paired Mac to load its Command Deck."
        }
        return "The Mac is connected, but this phone has not received the deck yet."
    }

    private var emptyStateActionTitle: String {
        if !bridgeManager.isPaired {
            return "Pair Mac"
        }
        if bridgeManager.status == .connected {
            return "Refresh Deck"
        }
        return "Connect"
    }

    private var emptyStateActionIcon: String {
        if !bridgeManager.isPaired {
            return "qrcode.viewfinder"
        }
        if bridgeManager.status == .connected {
            return "arrow.clockwise"
        }
        return "wifi"
    }

    private var emptyStateActionHint: String {
        if !bridgeManager.isPaired {
            return "Opens Mac pairing"
        }
        return "Connects to the paired Mac and refreshes Deck"
    }

    private func emptyStateAction() {
        if !bridgeManager.isPaired {
            AppShellRouter.shared.openBridgeDetail()
            return
        }

        warmDeckConnection()
    }

    private func currentSpace(in board: DeckBoardSnapshot) -> DeckSpace? {
        let target = selectedSpaceID ?? board.activeSpaceID
        return board.spaces.first { $0.id == target } ?? board.spaces.first
    }

    private func activeTileCount(in space: DeckSpace) -> Int {
        space.tiles.filter { $0.slotID != nil }.count
    }

    private func spaceIcon(for space: DeckSpace) -> String {
        let normalized = "\(space.id) \(space.title)".lowercased()
        if normalized.contains("mac") || normalized.contains("app") {
            return "desktopcomputer"
        }
        if normalized.contains("mic") || normalized.contains("voice") {
            return "mic"
        }
        if normalized.contains("talkie") {
            return "waveform"
        }
        return "square.grid.2x2"
    }

    // MARK: - Cockpit

    private func cockpitSurface(_ space: DeckSpace) -> some View {
        // The elevated card carries both the live transcript and the
        // final result. Bottom echo is suppressed for the dictation
        // slot so the result doesn't leak there.
        let transcriptForCard: String? = liveTranscript.isEmpty ? nil : liveTranscript
        let echoSuppress = hasDictationResult

        return DeckCockpitSurface(
            computerName: bridgeManager.pairedMacDisplayName ?? "MAC",
            deckName: space.title,
            statusTitle: cockpitStatusTitle,
            statusColor: cockpitStatusColor,
            accent: cockpitAccent(for: space),
            firingSlotID: deck.firingSlotID,
            isDictating: isDictating,
            hasDictationResult: hasDictationResult,
            liveTranscript: transcriptForCard,
            lastTriggerResult: echoSuppress ? nil : deck.lastTriggerResult,
            onIdentityTap: openAppSwitcher,
            onTrackpadEvent: sendTrackpadEvent,
            onTrackpadInteractionChanged: { isTrackpadInteracting = $0 },
            onCommand: runDeckCommand
        )
    }

    private var cockpitStatusTitle: String {
        if isDictating { return "DICTATING" }
        if deck.firingSlotID != nil { return "SENDING" }
        if bridgeManager.status == .connected { return "LIVE" }
        if bridgeManager.status == .connecting { return "LINKING" }
        if bridgeManager.status == .error { return "ERROR" }
        return "IDLE"
    }

    private var cockpitStatusColor: Color {
        if isDictating { return theme.currentTheme.chrome.accent }
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
        if bridgeManager.status == .connected {
            return Color(red: 0.36, green: 0.74, blue: 0.50)
        }
        if bridgeManager.status == .connecting {
            return theme.currentTheme.chrome.accent
        }
        // IDLE — read the muted ink so the pill stays visible on a
        // light canvas. (Pure white at 0.32 disappears on Scope.)
        return theme.colors.textTertiary
    }

    private func cockpitAccent(for space: DeckSpace) -> Color {
        if isMacSpace(space) {
            return Color(red: 0.30, green: 0.76, blue: 0.78)
        }
        if "\(space.id) \(space.title)".lowercased().contains("mic") {
            return Color(red: 0.82, green: 0.54, blue: 0.56)
        }
        return theme.currentTheme.chrome.accent
    }

    private func isMacSpace(_ space: DeckSpace) -> Bool {
        let normalized = "\(space.id) \(space.title)".lowercased()
        return normalized.contains("mac") || normalized.contains("app")
    }

    private func runDeckCommand(_ command: DeckCommand) {
        deck.fire(slotID: command.id)
    }

    private func sendTrackpadEvent(_ event: BridgeClient.TrackpadEvent, _ dx: Double, _ dy: Double) {
        trackpadErrorMessage = nil
        Task {
            do {
                try await bridgeManager.sendCompanionTrackpad(event: event, dx: dx, dy: dy)
            } catch {
                trackpadErrorMessage = error.localizedDescription
            }
        }
    }

    private func shareImagePickerItem(_ item: PhotosPickerItem) async {
        let mimeType = item.preferredImageMimeType

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                deck.reportLocalTriggerFailure(
                    slotID: "mac-paste-image",
                    message: "Talkie could not load that image."
                )
                await MainActor.run { imageSharePickerItem = nil }
                return
            }

            await MainActor.run {
                deck.pasteImageToMac(imageData: data, mimeType: mimeType)
                imageSharePickerItem = nil
            }
        } catch {
            await MainActor.run {
                deck.reportLocalTriggerFailure(
                    slotID: "mac-paste-image",
                    message: "Couldn’t load that image: \(error.localizedDescription)"
                )
                imageSharePickerItem = nil
            }
        }
    }

    // MARK: - Tile grid

    private func tileGrid(_ tiles: [DeckTile]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if index == 0 {
                    dictationTile
                } else {
                    tileView(tile)
                }
            }
        }
    }

    /// Top-left grid slot — state-aware dictation toggle. Tap when
    /// idle to start; tap again (in the same physical position) to
    /// commit. Visual matches the studio mock: mic glyph in idle,
    /// amber-armed enter glyph while dictating.
    private var dictationTile: some View {
        Button {
            toggleDictation()
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: isDictating ? "return" : "mic")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(
                        isDictating
                            ? theme.currentTheme.chrome.accent
                            : theme.colors.textPrimary
                    )
                    .frame(height: 24)

                Text(isDictating ? "Finish" : "Dictate")
                    .talkieType(.fieldValue)
                    .foregroundStyle(
                        isDictating
                            ? theme.currentTheme.chrome.accent
                            : theme.colors.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isDictating
                                    ? theme.currentTheme.chrome.accent
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
            .shadow(
                color: isDictating
                    ? theme.currentTheme.chrome.accent.opacity(0.45)
                    : .clear,
                radius: isDictating ? 6 : 0
            )
            .scaleEffect(isDictating ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isDictating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDictating ? "Finish dictation" : "Start dictation")
    }

    /// Fires the Mac `talkie-dictate` shortcut. Mac side toggles
    /// dictation on/off when the same slot is re-triggered, so both
    /// start AND finish route through the same call. The deck's
    /// `isDictating` state then flips automatically because we derive
    /// it from `lastTriggerResult`.
    private func toggleDictation() {
        deck.fire(slotID: dictationSlotID)
    }

    @ViewBuilder
    private func tileView(_ tile: DeckTile) -> some View {
        let isImageShareTile = tile.slotID == "mac-paste-image"
        let isFiring = deck.firingSlotID == tile.slotID
        let isEmpty = tile.slotID == nil
        let triggerResult = triggerResult(for: tile)
        let isResultTile = triggerResult != nil
        let isActive = isFiring || isResultTile
        let activeColor = triggerResult.map(triggerResultColor) ?? theme.currentTheme.chrome.accent

        if isImageShareTile, !isEmpty {
            PhotosPicker(selection: $imageSharePickerItem, matching: .images) {
                tileSurface(
                    tile,
                    isEmpty: isEmpty,
                    isActive: isActive,
                    activeColor: activeColor
                )
            }
            .buttonStyle(.plain)
            .disabled(deck.firingSlotID != nil)
            .accessibilityLabel("Share image to Mac")
            .accessibilityHint("Choose a photo or screenshot to send to the Mac")
        } else {
            Button(action: {
                guard let slot = tile.slotID else { return }
                deck.fire(slotID: slot)
            }) {
                tileSurface(
                    tile,
                    isEmpty: isEmpty,
                    isActive: isActive,
                    activeColor: activeColor
                )
            }
            .buttonStyle(.plain)
            .disabled(isEmpty || deck.firingSlotID != nil)
            .accessibilityLabel(isEmpty ? "Empty slot" : tile.label)
            .accessibilityHint(isEmpty ? "" : "Fires on the Mac")
        }
    }

    private func tileSurface(
        _ tile: DeckTile,
        isEmpty: Bool,
        isActive: Bool,
        activeColor: Color
    ) -> some View {
        VStack(spacing: 6) {
            if isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.colors.textTertiary.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                Image(systemName: tile.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(activeColor)
                    .frame(height: 24)

                Text(tile.label)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let hint = tile.hint {
                    Text(hint.uppercased())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isEmpty ? 0 : 72)
        .padding(.vertical, isEmpty ? 0 : 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isActive
                        ? activeColor.opacity(0.22)
                        : theme.colors.cardBackground.opacity(isEmpty ? 0.45 : 1)
                )
                .overlay(
                    isActive
                        ? RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(activeColor, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        : nil
                )
        )
        .shadow(
            color: isActive ? activeColor.opacity(0.45) : .clear,
            radius: isActive ? 6 : 0
        )
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isActive)
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
            if bridgeManager.status != .connected {
                await bridgeManager.connect()
            }
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

    private func warmDeckConnection() {
        Task {
            guard bridgeManager.isPaired else { return }
            if bridgeManager.status != .connected {
                await bridgeManager.connect()
            }
            await bridgeManager.refreshCompanionState()
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

// MARK: - Cockpit Components

private struct DeckCockpitSurface: View {
    let computerName: String
    let deckName: String
    let statusTitle: String
    let statusColor: Color
    let accent: Color
    let firingSlotID: String?
    let isDictating: Bool
    /// True while a dictation result is still surfaced — covers the
    /// post-`.succeeded` window where the final transcript should
    /// stay visible in the elevated card.
    let hasDictationResult: Bool
    let liveTranscript: String?
    let lastTriggerResult: DeckMirrorStore.TriggerResult?
    let onIdentityTap: () -> Void
    let onTrackpadEvent: (BridgeClient.TrackpadEvent, Double, Double) -> Void
    let onTrackpadInteractionChanged: (Bool) -> Void
    let onCommand: (DeckCommand) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        // Trackpad IS the chassis. Identity floats at the top, key
        // row at the bottom, transcript card in the middle. During
        // dictation the cursor glyph hides and a VU waveform band
        // takes its own slot just above the key row — not overlaid
        // on the trackpad as a faint backdrop. Each element gets a
        // clean vertical lane.
        DeckInstrumentTrackpad(
            accent: accent,
            isLive: statusTitle == "LIVE" || statusTitle == "SENDING" || isDictating,
            // Hide the cursor glyph while the dictation card is up,
            // even after the result settles, so the box has clean
            // breathing room.
            isDictating: isDictating || hasDictationResult,
            onEvent: onTrackpadEvent,
            onInteractionChanged: onTrackpadInteractionChanged
        )
        .overlay(alignment: .top) {
            header.padding(.horizontal, 10).padding(.top, 8)
        }
        .overlay(alignment: .center) { transcriptOverlay }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if isDictating {
                    DictationWaveform(color: accent, isActive: true)
                        .padding(.horizontal, 14)
                        .allowsHitTesting(false)
                }
                keyRow.padding(.horizontal, 10)
            }
            .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) {
            // Last trigger echo sits between the waveform band and
            // the key row; only renders when not dictating.
            lastTriggerEcho.padding(.bottom, 44)
        }
        .frame(maxHeight: .infinity)
    }

    // Identity + status, floating inside the dark trackpad. Colors
    // pull from `panelInk` (the bright-on-dark ladder) so the text
    // reads against the instrument surface regardless of the active
    // app theme.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onIdentityTap) {
                HStack(spacing: 5) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 10, weight: .regular))
                    Text(computerName.uppercased())
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.chrome.panelInk)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(theme.chrome.panelInkFaint)
                    Text(deckName.uppercased())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.chrome.panelInkFaint)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(theme.chrome.panelInkFaint)
                }
                .foregroundStyle(theme.chrome.panelInkFaint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change computer or deck")

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusTitle)
                    .talkieType(.chipLabel)
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.14))
                    .overlay(
                        Capsule()
                            .strokeBorder(statusColor.opacity(0.40),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
    }

    // Elevated transcript card — sticky-note feel sitting on the
    // dark trackpad. Visible during dictation AND after, so the
    // final result reads in the same treatment as the live partials
    // (not as a one-line bottom echo).
    @ViewBuilder
    private var transcriptOverlay: some View {
        if let liveTranscript, !liveTranscript.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isDictating {
                        Text("TRANSCRIBING…")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(accent.opacity(0.85))
                    } else if hasDictationResult {
                        Text("TRANSCRIPT")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.chrome.panelInkFaint)
                    }
                    Text(liveTranscript)
                        .talkieType(.preview)
                        .foregroundStyle(theme.chrome.panelInk)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Spacer(minLength: 0)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.chrome.panelAlt.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 14)
        }
    }

    // Last trigger result echoes inline along the bottom of the
    // trackpad surface — no separate banner, no layout shift. Only
    // shown when not dictating.
    @ViewBuilder
    private var lastTriggerEcho: some View {
        if !isDictating, let result = lastTriggerResult {
            Text("↳ \(result.message)")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(triggerEchoColor(for: result).opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
    }

    private func triggerEchoColor(for result: DeckMirrorStore.TriggerResult) -> Color {
        switch result.outcome {
        case .pending, .running: return accent
        case .succeeded: return Color(red: 0.36, green: 0.74, blue: 0.50)
        case .failed: return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
    }

    // One row with three visually distinct groups — Spacer(minLength:)
    // between groups gives the wider separator, default HStack spacing
    // keeps buttons inside a group tight together.
    private var keyRow: some View {
        HStack(spacing: 4) {
            // Left group: ESC · Copy · Paste
            HStack(spacing: 3) {
                DeckCommandButton(command: .escape, isTriggering: firingSlotID == DeckCommand.escape.id, showTitle: false, onCommand: onCommand)
                DeckCommandButton(command: .copy, isTriggering: firingSlotID == DeckCommand.copy.id, showTitle: false, onCommand: onCommand)
                DeckCommandButton(command: .paste, isTriggering: firingSlotID == DeckCommand.paste.id, showTitle: false, onCommand: onCommand)
            }

            Spacer(minLength: 10)

            // Center group: arrows
            DeckArrowCluster(firingSlotID: firingSlotID, onCommand: onCommand)

            Spacer(minLength: 10)

            // Right group: Select all · Delete · Enter
            HStack(spacing: 3) {
                DeckCommandButton(command: .selectAll, isTriggering: firingSlotID == DeckCommand.selectAll.id, showTitle: false, onCommand: onCommand)
                DeckCommandButton(command: .delete, isTriggering: firingSlotID == DeckCommand.delete.id, showTitle: false, onCommand: onCommand)
                DeckCommandButton(command: .enter, isTriggering: firingSlotID == DeckCommand.enter.id, showTitle: false, onCommand: onCommand)
            }
        }
        .accessibilityLabel("Text and cursor commands")
    }

}

private struct DeckInstrumentTrackpad: View {
    let accent: Color
    let isLive: Bool
    var isDictating: Bool = false
    let onEvent: (BridgeClient.TrackpadEvent, Double, Double) -> Void
    let onInteractionChanged: (Bool) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var lastLocation: CGPoint?
    @State private var isTouching = false
    @State private var isDragging = false
    @State private var dragActivationTask: Task<Void, Never>?

    private let sensitivity: Double = 2.2

    var body: some View {
        ZStack {
            // Plain dark inset — the magnetic-tape transport was a
            // voice-UI motif that didn't belong on a cursor surface.
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(theme.chrome.panelAlt.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(accent.opacity(isTouching ? 0.10 : 0))
                )
                .allowsHitTesting(false)

            // Hide the cursor affordance while dictating — the
            // transcript card + waveform band carry that state and
            // the cursor glyph would compete.
            if !isDictating {
                VStack(spacing: 5) {
                    Image(systemName: isDragging ? "cursorarrow.click.2" : "cursorarrow.motionlines")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(trackpadInk.opacity(isTouching ? 0.86 : 0.36))
                        .talkieAccentGlow(radius: isTouching ? 4 : 0)

                    Text(isDragging ? "DRAGGING" : "TRACKPAD")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(trackpadInk.opacity(isTouching ? 0.62 : 0.28))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenRecess(padding: 0, corner: CornerRadius.sm)
        .contentShape(Rectangle())
        .gesture(trackpadDragGesture)
        .simultaneousGesture(TapGesture(count: 1).onEnded { onEvent(.click, 0, 0) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onEvent(.rightClick, 0, 0) })
        .onDisappear {
            dragActivationTask?.cancel()
            dragActivationTask = nil
            if isDragging {
                onEvent(.mouseUp, 0, 0)
            }
            isDragging = false
            onInteractionChanged(false)
        }
    }

    private var trackpadInk: Color {
        isTouching ? accent : theme.chrome.panelInk
    }

    private var trackpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isTouching {
                    isTouching = true
                    onInteractionChanged(true)
                    scheduleDragActivation()
                }

                if let lastLocation {
                    let dx = (value.location.x - lastLocation.x) * sensitivity
                    let dy = (lastLocation.y - value.location.y) * sensitivity
                    if abs(dx) > 0.5 || abs(dy) > 0.5 {
                        onEvent(isDragging ? .drag : .move, dx, dy)
                    }
                }

                lastLocation = value.location
            }
            .onEnded { _ in
                dragActivationTask?.cancel()
                dragActivationTask = nil
                if isDragging {
                    onEvent(.mouseUp, 0, 0)
                }
                isDragging = false
                lastLocation = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    isTouching = false
                }
                onInteractionChanged(false)
            }
    }

    private func scheduleDragActivation() {
        dragActivationTask?.cancel()
        dragActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard isTouching, !isDragging else { return }
            isDragging = true
            onEvent(.mouseDown, 0, 0)
        }
    }
}

/// VU-style waveform — ported from the pre-rebuild donor at
/// `docs/donors/command-deck-pre-ios-shell-rebuild/source/.../
/// CompanionShortcutModeView.swift` (`DeckWaveformView`). Bars are
/// bottom-anchored with a top-fade gradient mask so they read as
/// audio levels, not as a centered decoration.
///
/// Three states drive motion + opacity:
///   • `isActive=false` → small idle pulses, very low opacity
///   • `isActive=true,  isProcessing=false` → signal-driven (real mic
///       level if available; falls back to multi-frequency sin mix)
///   • `isProcessing=true` → "cooking" wave, slightly dimmer
///
/// `signalLevel` is the mic envelope (0…1). Codex wires it through
/// when the runtime-state pipeline exposes it; until then the view
/// falls back to a richer multi-frequency sine.
private struct DictationWaveform: View {
    let color: Color
    var signalLevel: Double? = nil
    var isProcessing: Bool = false
    var isActive: Bool = true

    private let barCount = 22
    private let maxBarHeight: CGFloat = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.066, paused: !isActive)) { context in
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let barWidth = max(2, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let h = barHeight(index: index, date: context.date)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(barOpacity(height: h)))
                            .frame(width: barWidth, height: h)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .mask(
                    LinearGradient(
                        colors: [.black.opacity(0.30), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: maxBarHeight)
        }
    }

    private func barOpacity(height: CGFloat) -> Double {
        guard isActive else { return 0.16 }
        let fraction = Double(height / maxBarHeight)
        let base: Double = isProcessing ? 0.55 : 0.88
        return base * (0.45 + fraction * 0.55)
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let i = Double(index)
        let n = Double(barCount)

        if !isActive {
            let phase = t * 0.7 + i * 0.55
            return CGFloat(2 + (sin(phase) + 1) * 0.9)
        }

        if isProcessing {
            let w1 = sin(t * 1.7 + i / n * .pi * 3.2)
            let w2 = sin(t * 0.55 + i / n * .pi * 1.1) * 0.35
            let norm = (w1 + w2 + 1.35) / 2.7
            return CGFloat(4 + norm * 20)
        }

        let base = max(0.2, min(signalLevel ?? 0.55, 1.0))
        let f1 = sin(t * 10.5 + i * 0.65) * 0.32
        let f2 = sin(t * 4.2 + i * 1.05) * 0.24
        let f3 = sin(t * 1.7 + i * 0.25) * 0.44
        let raw = base * 0.42 + (f1 + f2 + f3 + 1.0) * 0.29
        return CGFloat(3 + raw * 25)
    }
}

private struct DeckStatusLamp: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.28), lineWidth: 4)
                    .blur(radius: 2)
            )
            .shadow(color: color.opacity(0.42), radius: 7)
    }
}

private struct DeckCommandButton: View {
    let command: DeckCommand
    let isTriggering: Bool
    var showTitle = true
    let onCommand: (DeckCommand) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: { onCommand(command) }) {
            HStack(spacing: showTitle ? 5 : 0) {
                ZStack {
                    if isTriggering {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(theme.chrome.action)
                    } else {
                        Image(systemName: command.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.chrome.action)
                    }
                }
                .frame(width: 16, height: 16)

                if showTitle {
                    Text(command.title.uppercased())
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.chrome.action)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(minWidth: showTitle ? 58 : 31, minHeight: 30)
            .padding(.horizontal, showTitle ? 7 : 0)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(isTriggering ? theme.chrome.accentTint : theme.chrome.actionTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .strokeBorder(
                                isTriggering ? theme.chrome.accent.opacity(0.34) : theme.chrome.edgeFaint,
                                lineWidth: theme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(CardPressStyle())
        .disabled(isTriggering)
        .accessibilityLabel(command.accessibilityLabel)
    }
}

private struct DeckArrowCluster: View {
    let firingSlotID: String?
    let onCommand: (DeckCommand) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private let commands: [DeckCommand] = [.left, .up, .down, .right]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(commands) { command in
                Button(action: { onCommand(command) }) {
                    ZStack {
                        if firingSlotID == command.id {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(theme.chrome.panelInkFaint)
                        } else {
                            Image(systemName: command.icon)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.chrome.panelInkFaint)
                        }
                    }
                    .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(firingSlotID == command.id)
                .accessibilityLabel(command.accessibilityLabel)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(theme.chrome.panel.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .strokeBorder(theme.chrome.panelEdge,
                                      lineWidth: theme.chrome.hairlineWidth)
                )
        )
    }
}

private struct DeckCommandPair: View {
    let title: String
    let icon: String
    let previous: DeckCommand
    let next: DeckCommand
    let firingSlotID: String?
    var centerAction: (() -> Void)? = nil
    let onCommand: (DeckCommand) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 1) {
            pairButton(systemImage: "chevron.left", command: previous)

            Button(action: { centerAction?() }) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                    Text(title)
                        .talkieType(.chipLabel)
                        .lineLimit(1)
                }
                .foregroundStyle(centerAction == nil ? theme.chrome.panelInkFaint.opacity(0.55) : theme.chrome.panelInk)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .disabled(centerAction == nil)
            .accessibilityLabel(centerAction == nil ? title : "Open \(title.lowercased()) switcher")

            pairButton(systemImage: "chevron.right", command: next)
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(theme.chrome.panel.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .strokeBorder(theme.chrome.panelEdge,
                                      lineWidth: theme.chrome.hairlineWidth)
                )
        )
    }

    private func pairButton(systemImage: String, command: DeckCommand) -> some View {
        Button(action: { onCommand(command) }) {
            ZStack {
                if firingSlotID == command.id {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(theme.chrome.panelInkFaint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.chrome.panelInkFaint)
                }
            }
            .frame(width: 28, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(firingSlotID == command.id)
        .accessibilityLabel(command.accessibilityLabel)
    }
}

private struct DeckCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let accessibilityLabel: String

    static let enter = DeckCommand(
        id: "deck-enter",
        title: "Enter",
        icon: "return",
        accessibilityLabel: "Press return on Mac"
    )
    static let delete = DeckCommand(
        id: "deck-delete",
        title: "Del",
        icon: "delete.left",
        accessibilityLabel: "Press delete on Mac"
    )
    static let selectAll = DeckCommand(
        id: "deck-select-all",
        title: "All",
        icon: "selection.pin.in.out",
        accessibilityLabel: "Select all on Mac"
    )
    static let paste = DeckCommand(
        id: "deck-paste",
        title: "Paste",
        icon: "doc.on.clipboard",
        accessibilityLabel: "Paste on Mac"
    )
    static let copy = DeckCommand(
        id: "deck-copy",
        title: "Copy",
        icon: "doc.on.doc",
        accessibilityLabel: "Copy on Mac"
    )
    static let escape = DeckCommand(
        id: "deck-escape",
        title: "Esc",
        icon: "escape",
        accessibilityLabel: "Press escape on Mac"
    )
    static let up = DeckCommand(
        id: "deck-up",
        title: "Up",
        icon: "arrow.up",
        accessibilityLabel: "Move up on Mac"
    )
    static let down = DeckCommand(
        id: "deck-down",
        title: "Down",
        icon: "arrow.down",
        accessibilityLabel: "Move down on Mac"
    )
    static let left = DeckCommand(
        id: "deck-left",
        title: "Left",
        icon: "arrow.left",
        accessibilityLabel: "Move left on Mac"
    )
    static let right = DeckCommand(
        id: "deck-right",
        title: "Right",
        icon: "arrow.right",
        accessibilityLabel: "Move right on Mac"
    )
    static let windowPrevious = DeckCommand(
        id: "deck-window-previous",
        title: "Prev Window",
        icon: "rectangle.on.rectangle",
        accessibilityLabel: "Previous Mac window"
    )
    static let windowNext = DeckCommand(
        id: "deck-window-next",
        title: "Next Window",
        icon: "rectangle.on.rectangle",
        accessibilityLabel: "Next Mac window"
    )
    static let tabPrevious = DeckCommand(
        id: "deck-tab-previous",
        title: "Prev Tab",
        icon: "arrow.left.square",
        accessibilityLabel: "Previous Mac tab"
    )
    static let tabNext = DeckCommand(
        id: "deck-tab-next",
        title: "Next Tab",
        icon: "arrow.right.square",
        accessibilityLabel: "Next Mac tab"
    )
    static let appPrevious = DeckCommand(
        id: "deck-app-previous",
        title: "Prev App",
        icon: "square.stack.3d.up",
        accessibilityLabel: "Previous Mac app"
    )
    static let appNext = DeckCommand(
        id: "deck-app-next",
        title: "Next App",
        icon: "square.stack.3d.up.fill",
        accessibilityLabel: "Next Mac app"
    )
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

private extension PhotosPickerItem {
    var preferredImageMimeType: String {
        if supportedContentTypes.contains(where: { $0.conforms(to: .png) }) {
            return "image/png"
        }
        if supportedContentTypes.contains(where: { $0.conforms(to: .jpeg) }) {
            return "image/jpeg"
        }
        if let mimeType = supportedContentTypes
            .first(where: { $0.conforms(to: .image) })?
            .preferredMIMEType {
            return mimeType
        }
        return "image/jpeg"
    }
}
