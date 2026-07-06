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

/// Material skin for the deck. Layout + proportions are identical across
/// treatments; only the texture changes — how the keycaps catch light and
/// lift, and whether the keybed reads as a flush face or a recessed pocket.
/// Mirrors the studio (`design/studio/components/studies/IOSDeck.tsx`).
enum DeckTreatment: String, CaseIterable {
    /// Matte aluminium, flat chamfered caps, a recessed brushed pocket.
    case milled
    /// Satin caps with pronounced lift off a flush brushed face (figure/ground).
    case relief

    var next: DeckTreatment { self == .milled ? .relief : .milled }
    var label: String { rawValue.uppercased() }
}

struct DeckMirrorNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var selectedSpaceID: String?
    @State private var showingPairedMacSwitcher = false
    @State private var switchingPairedMacID: String?
    @State private var isTrackpadInteracting = false
    @State private var trackpadErrorMessage: String?

    /// The active material skin (Milled / Relief). Persisted so it can be
    /// flipped from settings later; tap the wordmark to cycle it in-app.
    @AppStorage("deckTreatment") private var treatmentRaw = DeckTreatment.relief.rawValue
    private var treatment: DeckTreatment {
        DeckTreatment(rawValue: treatmentRaw) ?? .relief
    }

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

    /// Mac-side runtime detail for the dictation slot. Exposes the
    /// phase (preparing/recording/processing), elapsed seconds, and
    /// signal level. Nil when the Mac isn't actively running the
    /// dictation shortcut.
    private var dictationRuntime: CompanionShortcutRuntimeState? {
        guard let state = deck.lastRuntimeState,
              state.shortcutId == dictationSlotID else { return nil }
        return state
    }

    @State private var imageSharePickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            // Anodised sheen over the chassis — a faint top→bottom metal
            // fall-off so the face reads as brushed metal. Zones are set
            // apart by material (this + the dark trackpad + the keybed
            // pocket), not by dividing lines.
            LinearGradient(
                colors: [Color.white.opacity(0.04), .clear, Color.black.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            BrushedMetal()

            VStack(spacing: 0) {
                header

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
        .sheet(isPresented: $showingPairedMacSwitcher) {
            DeckPairedMacSwitcherSheet(
                macs: bridgeManager.pairedMacs,
                activeMacID: bridgeManager.activePairedMacID,
                connectedMacID: bridgeManager.status == .connected ? bridgeManager.activePairedMacID : nil,
                switchingMacID: switchingPairedMacID,
                onSelect: selectPairedMac,
                onPair: {
                    showingPairedMacSwitcher = false
                    AppShellRouter.shared.openBridgeDetail()
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("TALKIE · DECK")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
                .contentShape(Rectangle())
                // Tap the wordmark to cycle the material skin in-app so both
                // are reviewable without a settings screen.
                .onTapGesture { treatmentRaw = treatment.next.rawValue }

            Text(treatment.label)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary.opacity(0.7))

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
                    // Cockpit AND keypad both go full-bleed horizontally so
                    // the keypad's keys line up edge-for-edge with the
                    // cockpit's key row (Dictate ↔ esc on the left, last
                    // column ↔ enter on the right). Each insets its keys by
                    // the same 10pt from the instrument edge.
                    cockpitSurface(space)
                        // FIXED console height — a maxHeight cap let the
                        // greedy keybed starve it down to a cramped strip.
                        // 248 is smaller than the old 40% share (which
                        // dominated big phones) but tall enough that the
                        // trackpad + signals + key row breathe; the keybed
                        // takes the rest → tall rectangular keys.
                        .frame(height: 248)
                    tileGrid(space.tiles)
                        .layoutPriority(60)
                        .gesture(deckSpaceSwipeGesture(for: board))
                }
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

    private func deckSpaceSwipeGesture(for board: DeckBoardSnapshot) -> some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 44,
                      abs(horizontal) > abs(vertical) * 1.35 else {
                    return
                }

                selectAdjacentSpace(in: board, step: horizontal < 0 ? 1 : -1)
            }
    }

    private func selectAdjacentSpace(in board: DeckBoardSnapshot, step: Int) {
        guard board.spaces.count > 1,
              let current = currentSpace(in: board),
              let index = board.spaces.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        let nextIndex = (index + step + board.spaces.count) % board.spaces.count
        withAnimation(.easeOut(duration: 0.18)) {
            selectedSpaceID = board.spaces[nextIndex].id
        }
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
            dictationPhase: dictationRuntime?.phase,
            liveTranscript: transcriptForCard,
            lastTriggerResult: echoSuppress ? nil : deck.lastTriggerResult,
            onIdentityTap: openPairedMacSwitcher,
            onTrackpadEvent: sendTrackpadEvent,
            onTrackpadInteractionChanged: { isTrackpadInteracting = $0 },
            onCommand: runDeckCommand
        )
    }

    private var cockpitStatusTitle: String {
        // Phase-aware while a dictation runtime is live: distinguish
        // the recording window (with mm:ss timer for context) from
        // the processing tail. Falls back to a plain "DICTATING"
        // when only the trigger result is in flight.
        if let runtime = dictationRuntime {
            switch runtime.phase {
            case .preparing:
                return "PREPARING"
            case .recording:
                let elapsed = formatElapsed(runtime.elapsedSeconds ?? 0)
                return "REC · \(elapsed)"
            case .processing:
                return "TRANSCRIBING…"
            }
        }
        if isDictating { return "DICTATING" }
        if deck.firingSlotID != nil { return "SENDING" }
        if bridgeManager.status == .connected { return "LIVE" }
        if bridgeManager.status == .connecting { return "LINKING" }
        if bridgeManager.status == .error { return "ERROR" }
        return "IDLE"
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var cockpitStatusColor: Color {
        if isDictating { return theme.chrome.panelInkFaint }
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
        // Manual 4×4 so every row STRETCHES to fill the keybed height —
        // LazyVGrid sizes rows to content, which left the caps square. Here
        // each row + cell is maxHeight:.infinity, so the keys grow into tall
        // rectangular caps that fill the space.
        let rows = stride(from: 0, to: tiles.count, by: 4).map {
            Array(tiles[$0 ..< min($0 + 4, tiles.count)])
        }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { colIndex, tile in
                        let index = rowIndex * 4 + colIndex
                        Group {
                            if tile.slotID == dictationSlotID {
                                dictationTile(tile, index: index)
                            } else {
                                tileView(tile, index: index)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        // Full-bleed keybed. 10pt horizontal bezel keeps the keys lined up
        // with the cockpit key row above. The surround is the treatment's
        // job — flush for Relief, a recessed pocket for Milled.
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(keybedWell)
    }

    /// The keybed surround. Relief is FLUSH — keys lift straight off the
    /// brushed chassis, no plate. Milled sits in a recessed pocket: a
    /// slightly darker well with a soft top recess but NO hard rim, so the
    /// zone reads by material, not a line.
    @ViewBuilder
    private var keybedWell: some View {
        switch treatment {
        case .relief:
            Color.clear
        case .milled:
            Rectangle()
                .fill(Color.black.opacity(0.11))
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.30), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 16)
                    .allowsHitTesting(false)
                }
                .allowsHitTesting(false)
        }
    }

    /// Keycap surface shared by every tile, treatment-aware. No resting
    /// hairline on either skin — caps read by finish + lift, not an
    /// outline. Relief: a satin top-light + a pronounced drop shadow so the
    /// cap stands off a flush face. Milled: a flat chamfer (top light →
    /// bottom shadow) + a tight seat shadow in its recessed pocket. `active`
    /// swaps to the amber armed look (tint + ring + glow); `isEmpty` reads
    /// as a socket (a faint ring on Relief, a dark dimple on Milled).
    private func keycapSurface(active: Bool, activeColor: Color, isEmpty: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let isRelief = treatment == .relief
        return shape
            .fill(
                active
                    ? activeColor.opacity(0.20)
                    : (isEmpty
                        ? Color.black.opacity(isRelief ? 0.04 : 0.14)
                        : theme.colors.cardBackground)
            )
            .overlay {
                // Cap finish. Relief: a soft satin top-light. Milled: a flat
                // chamfer, light top → shadow bottom. No glossy dome.
                if !isEmpty && !active {
                    shape.fill(
                        LinearGradient(
                            colors: isRelief
                                ? [Color.white.opacity(0.22), .clear]
                                : [Color.white.opacity(0.16), .clear, Color.black.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                // The only crisp edges: the armed ring, and Relief's printed
                // empty-socket ring. No resting hairline on a live cap.
                if active {
                    shape.strokeBorder(activeColor, lineWidth: theme.chrome.hairlineWidth * 1.5)
                } else if isEmpty && isRelief {
                    shape.strokeBorder(Color.black.opacity(0.10), lineWidth: theme.chrome.hairlineWidth)
                }
            }
            .compositingGroup()
            // Lift = two layers. A soft AMBIENT shadow (the cap floating off
            // the face, thrown well below) + a tight CONTACT shadow (the dark
            // line where it meets the surface). One flat blur reads like a
            // sticker; two layers read as real elevation. Relief lifts hard;
            // Milled still lifts but seats nearer its recessed pocket.
            .shadow(
                color: active
                    ? activeColor.opacity(0.5)
                    : (isEmpty ? .clear : Color.black.opacity(isRelief ? 0.34 : 0.26)),
                radius: active ? 9 : (isEmpty ? 0 : (isRelief ? 13 : 7)),
                x: 0,
                y: active ? 0 : (isEmpty ? 0 : (isRelief ? 9 : 4))
            )
            .shadow(
                color: active
                    ? .clear
                    : (isEmpty ? .clear : Color.black.opacity(isRelief ? 0.28 : 0.24)),
                radius: active ? 0 : (isEmpty ? 0 : (isRelief ? 3 : 2)),
                x: 0,
                y: active ? 0 : (isEmpty ? 0 : (isRelief ? 2 : 1))
            )
    }

    /// Tiny corner index (01–16) — the TE step/pad numbering from the
    /// studio. Low-contrast so it reads as a system, not clutter.
    private func keyIndexLabel(_ index: Int) -> some View {
        Text(String(format: "%02d", index + 1))
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.colors.textTertiary.opacity(0.55))
            .padding(.top, 7)
            .padding(.leading, 8)
            .allowsHitTesting(false)
    }

    /// Top-left grid slot — state-aware dictation toggle. Tap when
    /// idle to start; tap again (in the same physical position) to
    /// commit. Visual matches the studio mock: mic glyph in idle,
    /// theme-armed stop glyph while dictating.
    private func dictationTile(_ tile: DeckTile, index: Int) -> some View {
        let activeColor = theme.currentTheme.chrome.accent
        return Button {
            toggleDictation()
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: isDictating ? "stop.fill" : "mic")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(activeColor)
                    .frame(height: 24)

                Text(isDictating ? "Stop" : tile.label)
                    .talkieType(.fieldValue)
                    .foregroundStyle(
                        isDictating
                            ? activeColor
                            : theme.colors.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background {
                keycapSurface(active: isDictating, activeColor: activeColor, isEmpty: false)
            }
            .overlay(alignment: .topLeading) { keyIndexLabel(index) }
            .overlay(alignment: .topTrailing) {
                // The one always-on accent dot — marks the live/dictation key.
                if !isDictating {
                    Circle()
                        .fill(theme.chrome.accent)
                        .frame(width: 4, height: 4)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            .scaleEffect(isDictating ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isDictating)
        }
        .buttonStyle(.plain)
        .disabled(deck.firingSlotID != nil)
        .accessibilityLabel(isDictating ? "Stop dictation" : "Start dictation")
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
    private func tileView(_ tile: DeckTile, index: Int) -> some View {
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
                    index: index,
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
                    index: index,
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
        index: Int,
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

                Text(tileCaption(for: tile))
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 6)
        .background {
            keycapSurface(active: isActive, activeColor: activeColor, isEmpty: isEmpty)
        }
        .overlay(alignment: .topLeading) {
            if !isEmpty { keyIndexLabel(index) }
        }
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isActive)
    }

    private func tileCaption(for tile: DeckTile) -> String {
        guard let hint = tile.hint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hint.isEmpty else {
            return tile.label
        }

        return "\(tile.label) · \(hint.uppercased())"
    }

    private func triggerResult(for tile: DeckTile) -> DeckMirrorStore.TriggerResult? {
        guard let slotID = tile.slotID,
              let result = deck.lastTriggerResult,
              result.slotID == slotID else {
            return nil
        }

        return result
    }

    // MARK: - Paired Mac switcher

    private func openPairedMacSwitcher() {
        guard bridgeManager.hasPairedMacs else {
            AppShellRouter.shared.openBridgeDetail()
            return
        }

        showingPairedMacSwitcher = true
    }

    private func selectPairedMac(_ mac: BridgeManager.PairedMac) {
        guard switchingPairedMacID == nil else { return }
        guard bridgeManager.activePairedMacID != mac.id else {
            showingPairedMacSwitcher = false
            return
        }

        switchingPairedMacID = mac.id
        selectedSpaceID = nil

        Task {
            await bridgeManager.activatePairedMac(id: mac.id)
            await bridgeManager.refreshCompanionState()
            switchingPairedMacID = nil
            showingPairedMacSwitcher = false
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

/// Fine brushed-metal grain drawn over the whole chassis. Paired faint
/// dark+light ridges so the texture reads on both light and dark themes.
/// The dark trackpad + the keybed pocket sit on top, so the grain only
/// shows on the exposed metal — separating the zones by material, not lines.
private struct BrushedMetal: View {
    var body: some View {
        Canvas { ctx, size in
            let period: CGFloat = 3
            let slant = size.height * 0.10
            var x: CGFloat = -slant
            while x < size.width {
                var dark = Path()
                dark.move(to: CGPoint(x: x, y: 0))
                dark.addLine(to: CGPoint(x: x + slant, y: size.height))
                ctx.stroke(dark, with: .color(.black.opacity(0.030)), lineWidth: 0.5)

                var light = Path()
                light.move(to: CGPoint(x: x + period / 2, y: 0))
                light.addLine(to: CGPoint(x: x + period / 2 + slant, y: size.height))
                ctx.stroke(light, with: .color(.white.opacity(0.040)), lineWidth: 0.5)

                x += period
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

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
    /// Live phase from the Mac. Drives the waveform variant — real
    /// audio bars during `.recording`, frozen + processing shimmer
    /// during `.processing`. Nil means no runtime is in flight.
    let dictationPhase: CompanionShortcutRuntimeState.Phase?
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
            // Identity slides to 20pt leading so MAC · TALKIE aligns under
            // the app title (also 20pt) instead of hanging 10pt further
            // left. Status pill keeps its 10pt trailing inset.
            header.padding(.leading, 20).padding(.trailing, 10).padding(.top, 8)
        }
        .overlay(alignment: .center) {
            // Waveform sits in the cockpit's centerline — the
            // dictation centerpiece. Transcript card overlays it
            // on top when partials arrive (next .overlay below).
            if isDictating {
                DictationWaveform(
                    color: accent,
                    phase: dictationPhase ?? .recording
                )
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .center) { transcriptOverlay }
        .overlay(alignment: .bottom) {
            keyRow
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) {
            // Last trigger echo sits between the waveform band and
            // the key row; only renders when not dictating.
            lastTriggerEcho.padding(.bottom, 44)
        }
        .frame(maxHeight: .infinity)
        // Contain the waveform (and any other overlay) within the
        // trackpad's rounded shape — without this the 96pt band
        // bleeds out the top/bottom of the chassis on smaller phones.
        .clipShape(Rectangle())
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
                    .fill(statusDotColor)
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

    private var statusDotColor: Color {
        guard isDictating else { return statusColor }
        if dictationPhase == .processing { return accent }
        return Color.recording
    }

    // Elevated transcript card — sticky-note feel sitting on the
    // dark trackpad. Suppressed while dictating: the centered mag-
    // tape waveform is the recording indicator and overlaying the
    // "TRANSCRIBING…" caption on it reads as clutter. Card returns
    // when the result lands so the final transcript still gets the
    // sticky-note treatment.
    @ViewBuilder
    private var transcriptOverlay: some View {
        if let liveTranscript, !liveTranscript.isEmpty, !isDictating {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if hasDictationResult {
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
            Rectangle()
                .fill(theme.chrome.panelAlt.opacity(0.88))
                .overlay(
                    Rectangle()
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
        // Full-bleed, square — the dark glass runs edge to edge and reads as
        // a distinct material band against the brushed chassis (no rounded
        // card, no rim).
        .screenRecess(padding: 0, corner: 0)
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

/// Magnetic-tape waveform — sprocket-railed amber tape with bars
/// drawn from the iPhone mic's rolling envelope buffer. Each bar is
/// a real moment of audio that just happened; new samples push in
/// at the right edge (the playhead position) and the oldest fall
/// off the left. No synthetic seed pattern.
///
/// Anatomy:
///   • Brass sprocket rails (1pt dashed) top + bottom
///   • Warm-tan substrate (brass tint, vertical sheen)
///   • Bars from `DictationMicMonitor.samples` — newest on the right
///   • During `.processing` the bars dim and an amber shimmer sweeps
///     across the strip to read as "Mac is transcribing", distinct
///     from the live recording state
private struct DictationWaveform: View {
    let color: Color
    var phase: CompanionShortcutRuntimeState.Phase = .recording

    @ObservedObject private var mic = DictationMicMonitor.shared

    // Mag-tape palette — brand DNA, not theme-tinted. Bars pick up
    // the deck accent so the recording reads as the deck's voice;
    // the substrate, sprockets, and shimmer stay brass/amber so the
    // tape identity holds across themes.
    private static let brass = Color(red: 0.604, green: 0.416, blue: 0.133) // #9A6A22
    private static let amber = Color(red: 0.910, green: 0.604, blue: 0.235) // #E89A3C

    private let bandHeight: CGFloat = 96
    private let railInset: CGFloat = 3   // sprocket row + 2pt breathing room

    private var isRecording: Bool {
        phase == .recording || phase == .preparing
    }
    private var isProcessing: Bool { phase == .processing }

    var body: some View {
        ZStack {
            // Tape substrate — warm-tan, soft vertical sheen.
            LinearGradient(
                colors: [
                    Self.brass.opacity(0.06),
                    Self.brass.opacity(0.14),
                    Self.brass.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(.vertical, railInset)

            // Real-audio bars. mic.samples is a rolling buffer that
            // updates at 30Hz while the monitor is retained; during
            // .processing the mic keeps running (so ambient noise
            // still trickles in) but the bars dim to signal that
            // the user's voice is no longer the protagonist.
            RealtimeBars(
                fill: color.opacity(isProcessing ? 0.42 : 0.85),
                railInset: railInset
            )

            // Processing shimmer — a soft amber gradient sweeps
            // across the band to mark "Mac is transcribing". Lives
            // on its own TimelineView so the recording path stays
            // free of unrelated animation work.
            if isProcessing {
                ProcessingShimmer(accent: Self.amber)
                    .padding(.vertical, railInset + 1)
                    .allowsHitTesting(false)
            }

            // Sprocket rails — dashed brass, top + bottom.
            VStack(spacing: 0) {
                SprocketRail()
                Spacer(minLength: 0)
                SprocketRail()
            }
        }
        .frame(height: bandHeight)
        .onAppear {
            if isRecording || isProcessing { mic.retain() }
        }
        .onDisappear {
            if isRecording || isProcessing { mic.release() }
        }
        .onChange(of: phase) { _, _ in
            // The view stays mounted across phase changes inside
            // a dictation session; mic stays retained the whole
            // time. Released only when the view disappears (i.e.
            // dictation truly ends).
        }
    }
}

/// Canvas-drawn bars sourced from `DictationMicMonitor.samples`. One
/// bar per sample, left-to-right, with the newest sample at the right
/// edge — that IS the playhead, so no separate write-head line is
/// needed. Bar widths stretch to fill whatever width the band has.
private struct RealtimeBars: View {
    let fill: Color
    let railInset: CGFloat

    @ObservedObject private var mic = DictationMicMonitor.shared

    var body: some View {
        Canvas { ctx, size in
            let samples = mic.samples
            let n = samples.count
            guard n > 0 else { return }

            // Outer padding inside the trackpad edges — small breathing
            // room so the leftmost / rightmost bars don't kiss the
            // chassis corner radius.
            let padding: CGFloat = 8
            // 3pt gap between bars gives the strip visible "comb"
            // character rather than reading as a solid block. Each
            // bar is a pill (corner radius 1.5pt) so the silhouette
            // is softer and the tape feels less mechanical.
            let gap: CGFloat = 3
            let innerWidth = max(0, size.width - padding * 2)
            let barWidth = max(2, (innerWidth - CGFloat(n - 1) * gap) / CGFloat(n))
            let bodyHeight = size.height - railInset * 2 - 4
            let centerY = size.height / 2

            for i in 0..<n {
                let s = CGFloat(samples[i])
                // Power curve (^0.65) lifts mid-levels so ordinary
                // speech reads as visibly bouncy — without it, bars
                // sit flatter than the actual envelope feels. 0.05
                // floor keeps a faint ridge through silence; the
                // minimum rendered height of 3pt keeps the silent
                // strip readable as "tape" rather than "blank line".
                let shaped = pow(max(0.05, s), 0.65)
                let h = max(3, bodyHeight * shaped)
                let x = padding + CGFloat(i) * (barWidth + gap)
                let rect = CGRect(
                    x: x,
                    y: centerY - h / 2,
                    width: barWidth,
                    height: h
                )
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(fill)
                )
            }
        }
    }
}

/// Soft amber gradient that sweeps left→right on a 2.4s loop. Marks
/// the "Mac is transcribing" phase visually — distinct from the
/// active-recording look so the user knows they don't have to hold
/// their breath, the recording window has closed.
private struct ProcessingShimmer: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                let period: TimeInterval = 2.4
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: period)) / period
                // Sweep one strip-width past either edge so the
                // band has a clean off-frame entry and exit.
                let bandWidth: CGFloat = geo.size.width * 0.35
                let xOffset = -bandWidth + CGFloat(phase) * (geo.size.width + bandWidth * 2)

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: accent.opacity(0), location: 0),
                        .init(color: accent.opacity(0.40), location: 0.5),
                        .init(color: accent.opacity(0), location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: xOffset)
                .blendMode(.plusLighter)
            }
        }
    }
}

/// 1pt-tall dashed brass rail — matches the studio's
/// `repeating-linear-gradient(90deg, brass 0 2px, transparent 2px 6px)`.
private struct SprocketRail: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(
                path,
                with: .color(Color(red: 0.604, green: 0.416, blue: 0.133).opacity(0.50)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 4])
            )
        }
        .frame(height: 1)
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
        let ink = isTriggering ? theme.chrome.accent : theme.chrome.panelInkFaint.opacity(0.82)
        let fill = isTriggering ? theme.chrome.accentTint : theme.chrome.panel.opacity(0.92)
        let stroke = isTriggering ? theme.chrome.accent.opacity(0.34) : theme.chrome.panelEdge

        Button(action: { onCommand(command) }) {
            HStack(spacing: showTitle ? 5 : 0) {
                ZStack {
                    if isTriggering {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(ink)
                    } else {
                        Image(systemName: command.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ink)
                    }
                }
                .frame(width: 16, height: 16)

                if showTitle {
                    Text(command.title.uppercased())
                        .talkieType(.chipLabel)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(minWidth: showTitle ? 58 : 31, minHeight: 30)
            .padding(.horizontal, showTitle ? 7 : 0)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .strokeBorder(stroke, lineWidth: theme.chrome.hairlineWidth)
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

private struct DeckPairedMacSwitcherSheet: View {
    let macs: [BridgeManager.PairedMac]
    let activeMacID: String?
    let connectedMacID: String?
    let switchingMacID: String?
    let onSelect: (BridgeManager.PairedMac) -> Void
    let onPair: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if macs.isEmpty {
                        emptyState
                    } else {
                        ForEach(macs) { mac in
                            macRow(mac)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(theme.colors.background.ignoresSafeArea())
        }
        .background(theme.colors.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private var sheetHeader: some View {
        ZStack {
            Text("Paired Macs")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            HStack {
                Button(action: { dismiss() }) {
                    Text("Done")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(
                            Capsule()
                                .fill(theme.colors.cardBackground)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(theme.chrome.edgeFaint,
                                                      lineWidth: theme.chrome.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onPair) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(theme.chrome.actionTint)
                                .overlay(
                                    Circle()
                                        .strokeBorder(theme.chrome.edgeFaint,
                                                      lineWidth: theme.chrome.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pair another Mac")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No paired Macs")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Pair a Mac to use the deck from this phone.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(sheetRowBackground(isActive: false))
    }

    private func macRow(_ mac: BridgeManager.PairedMac) -> some View {
        let isActive = mac.id == activeMacID
        let isConnected = mac.id == connectedMacID
        let isSwitching = mac.id == switchingMacID
        let isBusy = switchingMacID != nil

        return Button(action: { onSelect(mac) }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isConnected ? Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.14) : theme.currentTheme.chrome.edgeFaint.opacity(0.35))

                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isActive ? "desktopcomputer.and.macbook" : "desktopcomputer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isActive ? theme.colors.textPrimary : theme.colors.textSecondary)
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(displayName(for: mac))
                            .talkieType(.listTitle)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)

                        if isActive {
                            Text(isConnected ? "LIVE" : "ACTIVE")
                                .talkieType(.chipLabel)
                                .foregroundStyle(isConnected ? Color(red: 0.36, green: 0.74, blue: 0.50) : theme.currentTheme.chrome.accent)
                        }
                    }

                    Text(mac.hostname)
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isConnected ? Color(red: 0.36, green: 0.74, blue: 0.50) : theme.currentTheme.chrome.accent)
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(12)
            .background(sheetRowBackground(isActive: isActive))
        }
        .buttonStyle(.plain)
        .disabled(isBusy && !isSwitching)
    }

    private func sheetRowBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive ? theme.currentTheme.chrome.accent.opacity(0.42) : theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
    }

    private func displayName(for mac: BridgeManager.PairedMac) -> String {
        let name = mac.pairedMacName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? mac.hostname : name
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
