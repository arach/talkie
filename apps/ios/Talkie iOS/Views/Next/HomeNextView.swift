//
//  HomeNextView.swift
//  Talkie iOS
//
//  M1 — Talkie's canonical iPhone home, painted to match the
//  studio mock at http://localhost:3000/home.
//
//  Composition: TALKIE wordmark · communication cockpit · frequent-action strip ·
//  command/search bar · Recent list (2-line iOS-Notes style) ·
//  contextual suggestions strip.
//  The ambient voice button lives in AppShellNext, not here.
//
//  Spec: design/studio/app/home/SWIFT_PORT.md
//  Visual reference: design/studio/app/home/page.tsx
//
//  Type system: TalkieTypeStyle tokens (see TalkieType.swift).
//  No raw .font(.system(...)) calls here — channel labels, body
//  serif, and instrument readouts all flow through .talkieType(...).
//

import SwiftUI
import TalkieMobileKit
import UIKit

struct HomeNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var iCloudStatus = iCloudStatusManager.shared
    @ObservedObject private var recordingSheet = RecordingSheetController.shared
    @StateObject private var feed: HomeFeed
    @FocusState private var isCommandFocused: Bool

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                HomeCockpit()
                    .padding(.horizontal, 12)

                HomeFrequentActionsStrip()
                    .padding(.horizontal, 12)

                HomeCommandBar(
                    query: $feed.searchText,
                    isFocused: $isCommandFocused
                )
                    .padding(.horizontal, 12)

                RecentSection(
                    items: feed.recentItems,
                    totalCount: feed.totalRecentCount,
                    isLoading: feed.isLoading,
                    errorMessage: feed.errorMessage,
                    isSearching: feed.isSearching,
                    hasMore: feed.hasMoreRecentItems,
                    remainingCount: feed.remainingRecentItems,
                    contentFilter: $feed.contentFilter,
                    sortOption: $feed.sortOption,
                    showsSyncPrompt: iCloudStatus.status == .noAccount && !iCloudStatus.isDismissed,
                    onLoadMore: { feed.loadMoreRecentItems() },
                    onPromote: { feed.promoteToMemo($0) },
                    onDelete: { feed.delete($0) },
                    onOpenICloudSettings: openICloudSettings,
                    onDismissSyncPrompt: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            iCloudStatus.dismissBanner()
                        }
                    }
                )
                .padding(.horizontal, 12)

                HomeSuggestionsStrip()
                    .padding(.horizontal, 12)

                Spacer(minLength: 80)   // breathing room for the shell voice button
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemosDidChange)) { _ in feed.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in feed.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .composeNotesDidChange)) { _ in feed.reload() }
        .onChange(of: recordingSheet.isPresented) { wasPresented, isPresented in
            guard wasPresented && !isPresented else { return }
            feed.reload()
        }
        .onChange(of: deepLinkManager.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
        .onAppear {
            feed.reload()
            handleDeepLinkAction(deepLinkManager.pendingAction)
        }
    }

    private func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .search(let query):
            feed.searchText = query
            isCommandFocused = true
            deepLinkManager.clearAction()
        case .openSearch:
            isCommandFocused = true
            deepLinkManager.clearAction()
        default:
            break
        }
    }

    private func openICloudSettings() {
        if let url = URL(string: "App-Prefs:root=APPLE_ACCOUNT") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

enum SharedCaptureIngress {
    static func importURLContent(
        from url: URL,
        suggestedTitle: String? = nil,
        ingestionMethod: String,
        onCapture: @escaping @MainActor (Capture) -> Void
    ) {
        Task {
            let result = await URLBookmarkMetadataService.buildCapture(
                from: url,
                suggestedTitle: suggestedTitle,
                sourceDevice: "iPhone",
                ingestionMethod: ingestionMethod
            )

            var capture = result.capture
            if let imageData = result.imageData {
                let filename = CaptureStore.shared.saveImage(imageData, id: capture.id)
                capture = capture.copyWithImage(filename: filename)
            }

            await MainActor.run {
                onCapture(capture)
            }
        }
    }

    static func processQueuedShare(
        id: String,
        onCapture: @escaping @MainActor (Capture) -> Void
    ) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else {
            AppLogger.app.warning("Share queue: app group unavailable")
            return
        }

        let fileURL = containerURL
            .appending(path: "Library/Application Support/Talkie/share-queue")
            .appending(path: "\(id).json")

        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.app.warning("Share queue: file not found for \(id)")
            return
        }

        let payload: QueuedSharePayload
        do {
            payload = try JSONDecoder().decode(QueuedSharePayload.self, from: data)
        } catch {
            AppLogger.app.error("Share queue: failed to decode \(id): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        try? FileManager.default.removeItem(at: fileURL)

        switch payload.sourceType {
        case "url":
            guard let urlString = payload.sourceURL, let url = URL(string: urlString) else { return }
            importURLContent(
                from: url,
                suggestedTitle: payload.title,
                ingestionMethod: "share-extension",
                onCapture: onCapture
            )
        case "photo":
            Task {
                await processSharedPhoto(imageBase64: payload.imageBase64, onCapture: onCapture)
            }
        case "text":
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                onCapture(Capture(sourceType: "text", text: text, title: payload.title))
            }
        default:
            AppLogger.app.warning("Share queue: unknown source type \(payload.sourceType)")
        }
    }

    private static func processSharedPhoto(
        imageBase64: String?,
        onCapture: @escaping @MainActor (Capture) -> Void
    ) async {
        guard let imageBase64,
              let imageData = Data(base64Encoded: imageBase64),
              let image = UIImage(data: imageData) else {
            AppLogger.app.warning("Share queue: could not decode image payload")
            return
        }

        let ocrText: String
        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            ocrText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.ai.info("Share OCR extracted \(ocrText.count) characters")
        } catch {
            ocrText = ""
            AppLogger.ai.info("Share OCR found no text in image")
        }

        let captureID = UUID()
        let imageFilename = CaptureStore.shared.saveImage(imageData, id: captureID)
        let capture = Capture(
            id: captureID,
            sourceType: "photo",
            text: ocrText.isEmpty ? "Image shared from iPhone" : ocrText,
            title: "Image · \(Date().formatted(.dateTime.month().day().hour().minute()))",
            imageFilename: imageFilename
        )

        await MainActor.run {
            onCapture(capture)
        }
    }
}

private struct QueuedSharePayload: Codable {
    let sourceType: String
    let text: String
    let title: String?
    let sourceURL: String?
    let imageBase64: String?
}

private extension Capture {
    func copyWithImage(filename: String?) -> Capture {
        Capture(
            id: id,
            sourceType: sourceType,
            text: text,
            title: title,
            sourceURL: sourceURL,
            bookmark: bookmark,
            imageFilename: filename,
            deferredPageFilenames: deferredPageFilenames,
            totalPageCount: totalPageCount,
            timestamp: timestamp,
            syncedToMac: syncedToMac
        )
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            DeckComplication()
            Spacer()
            Text("TALKIE")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button(action: { AppShellRouter.shared.openSettings() }) {
                HomeHeaderButtonGlyph(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("dock.settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Deck complication

private struct HomeHeaderButtonGlyph: View {
    let systemName: String
    var isEnabled: Bool = true
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            Circle().fill(theme.colors.cardBackground)
            Circle().strokeBorder(
                theme.currentTheme.chrome.edgeFaint,
                lineWidth: theme.currentTheme.chrome.hairlineWidth
            )
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isEnabled ? theme.colors.textSecondary : theme.colors.textTertiary)
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}

/// Resting Command Deck complication at the top-left of Home. It shares the
/// settings button treatment; bridge state is exposed through accessibility and
/// the Deck surface itself instead of a separate status bead.
private struct DeckComplication: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared

    var body: some View {
        Button(action: openDeck) {
            HomeHeaderButtonGlyph(systemName: "square.grid.3x3")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Deck remote")
    }

    // MARK: - State derivation

    private var hasDeckBoard: Bool {
        guard let board = deck.board else { return false }
        return !board.spaces.isEmpty
    }

    private func openDeck() {
        AppShellRouter.shared.openDeck()
    }

    private var accessibilityLabel: String {
        let mac = bridgeManager.pairedMacDisplayName ?? "Mac"
        if !bridgeManager.isPaired {
            return "Command Deck, not paired"
        }
        if bridgeManager.awaitingPairingApproval {
            return "Command Deck, \(mac) pending approval"
        }
        switch bridgeManager.status {
        case .connected:
            return hasDeckBoard ? "Command Deck on \(mac)" : "Command Deck, waiting for \(mac)"
        case .connecting: return "Command Deck, \(mac) connecting"
        case .disconnected: return "Command Deck, \(mac) offline"
        case .error: return "Command Deck, \(mac) error"
        }
    }
}

// MARK: - Home tactical palette

private enum HomeTacticalPalette {
    static let accent = Color(hex: "FF8800")
    static let accentSoft = Color(hex: "FF8800").opacity(0.14)
    static let accentEdge = Color(hex: "FF8800").opacity(0.34)
    static let matte = Color(hex: "303030", darkHex: "181818")
    static let matteLow = Color(hex: "242424", darkHex: "101010")
    static let screen = Color(hex: "050505")
    static let screenAlt = Color(hex: "121212")
    static let screenInk = Color(hex: "F3F1EA")
    static let screenInkFaint = Color(hex: "A6A29A")
}

// MARK: - Command center

private struct HomeCommandBar: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HomeTacticalPalette.accent)
                .frame(width: 22, height: 22)

            TextField("Ask, find, send, or route...", text: $query)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit(submit)

            Button(action: startRecording) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(theme.colors.cardBackground.opacity(0.72))
                            .overlay {
                                Circle().strokeBorder(
                                    theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start recording")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(theme.colors.cardBackground.opacity(0.82))
                .overlay {
                    Capsule()
                        .fill(HomeTacticalPalette.accentSoft.opacity(isFocused ? 1 : 0.46))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isFocused ? HomeTacticalPalette.accentEdge : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: isFocused ? 1 : theme.currentTheme.chrome.hairlineWidth
                        )
                }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 9, x: 0, y: 5)
        .accessibilityIdentifier("home.command-bar")
    }

    private func submit() {
        let command = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            isFocused = false
            return
        }
        AppShellRouter.shared.openAskAISeeded(prompt: command)
    }

    private func startRecording() {
        RecordingSheetController.shared.isPresented = true
    }
}

// MARK: - Communication cockpit
//
// Replaces the Today ticker. One compact retrofuturist comms instrument — a
// raised metal chassis around an always-dark instrument screen — summarizing
// live communication state: the Mac bridge lane plus shares/replies lanes,
// with a Life-in-Dots module on the right and a single truncated detail line
// under the screen. Tapping routes to Deck when the bridge is live, Bridge
// detail otherwise.
//
// Spec: design/studio/app/home/COCKPIT_IMPLEMENTATION_BRIEF.md
// Visual donor: design/studio/components/studies/Home.tsx (`communication-cockpit`).

private struct CockpitLaneModel {
    let label: String
    let shortLabel: String
    let value: String
    let meta: String
    let level: Double
}

private struct HomeCockpit: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· COCKPIT")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.leading, 4)

            Button(action: open) {
                VStack(spacing: 8) {
                    CockpitScreen(
                        statusLabel: statusLabel,
                        statusIsLive: isConnected,
                        lanes: lanes
                    )

                    Text(detailLine)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                .bezelChassis(padding: 10, corner: 14, metal: true, fill: HomeTacticalPalette.matte)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(isConnected ? "Opens Deck remote" : "Opens Bridge detail")
        }
    }

    // MARK: - Routing

    private var isConnected: Bool {
        bridgeManager.isPaired && bridgeManager.status == .connected
    }

    private func open() {
        if isConnected {
            AppShellRouter.shared.openDeck()
        } else {
            AppShellRouter.shared.openBridgeDetail()
        }
    }

    // MARK: - State derivation

    private var statusLabel: String {
        guard bridgeManager.isPaired else { return "STANDBY" }
        switch bridgeManager.status {
        case .connected: return "LIVE"
        case .connecting: return "LINKING"
        case .disconnected: return "OFFLINE"
        case .error: return "ERROR"
        }
    }

    private var lanes: [CockpitLaneModel] {
        [bridgeLane, sharesLane, repliesLane]
    }

    private var bridgeLane: CockpitLaneModel {
        let mac = bridgeManager.pairedMacDisplayName ?? "Mac"
        guard bridgeManager.isPaired else {
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: "Not paired", meta: "PAIR", level: 0.12)
        }
        if bridgeManager.awaitingPairingApproval {
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: mac, meta: "APPROVE", level: 0.30)
        }
        switch bridgeManager.status {
        case .connected:
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: mac, meta: "READY", level: 0.92)
        case .connecting:
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: mac, meta: "LINKING", level: 0.50)
        case .disconnected:
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: mac, meta: "OFFLINE", level: 0.24)
        case .error:
            return CockpitLaneModel(label: "BRIDGE", shortLabel: "BRDG", value: mac, meta: "ERROR", level: 0.24)
        }
    }

    // Shares/replies have no HomeFeed source yet — static instrument content
    // until the share queue / reply prompts get a real publisher.
    private var sharesLane: CockpitLaneModel {
        CockpitLaneModel(label: "SHARES", shortLabel: "SEND", value: "2 drafts", meta: "QUEUED", level: 0.54)
    }

    private var repliesLane: CockpitLaneModel {
        CockpitLaneModel(label: "REPLIES", shortLabel: "WAIT", value: "1 prompt", meta: "WAITING", level: 0.36)
    }

    private var detailLine: String {
        let bridgePart: String
        if isConnected {
            bridgePart = "Bridge live on \(bridgeManager.pairedMacDisplayName ?? "Mac")"
        } else if bridgeManager.isPaired {
            bridgePart = "Bridge \(statusLabel.lowercased())"
        } else {
            bridgePart = "Pair your Mac"
        }
        return "\(bridgePart) / 2 shares / 1 reply"
    }

    private var accessibilitySummary: String {
        let bridge: String
        if isConnected {
            bridge = "bridge ready on \(bridgeManager.pairedMacDisplayName ?? "Mac")"
        } else if bridgeManager.isPaired {
            bridge = "bridge \(statusLabel.lowercased()) for \(bridgeManager.pairedMacDisplayName ?? "Mac")"
        } else {
            bridge = "no Mac paired"
        }
        return "Communication cockpit, \(bridge), 2 shares queued, 1 reply waiting"
    }
}

/// The always-dark instrument screen inside the cockpit chassis: TALKIE /
/// status / clock header, three comms lanes, and the dots module. Panel ink
/// only — the screen ignores light/dark so it reads as lit glass everywhere.
private struct CockpitScreen: View {
    let statusLabel: String
    let statusIsLive: Bool
    let lanes: [CockpitLaneModel]
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let hairline = max(theme.currentTheme.chrome.hairlineWidth, 0.8)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(spacing: 8) {
            HStack {
                Text("TALKIE")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.screenInkFaint)
                Spacer()
                Text(statusLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(statusIsLive ? HomeTacticalPalette.accent : HomeTacticalPalette.screenInkFaint)
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(HomeTacticalPalette.screenInkFaint)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 6) {
                    ForEach(lanes, id: \.label) { lane in
                        CockpitLaneRow(lane: lane)
                    }
                }
                CockpitDotsModule(lanes: lanes)
                    .frame(width: 84)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                HomeTacticalPalette.screen
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.08), location: 0),
                        .init(color: Color.white.opacity(0.02), location: 0.45),
                        .init(color: Color.black.opacity(0.24), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [HomeTacticalPalette.accent.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: 0,
                    endRadius: 110
                )
                LinearGradient(
                    colors: [
                        HomeTacticalPalette.screenAlt.opacity(0.00),
                        HomeTacticalPalette.screenAlt.opacity(0.45),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(HomeTacticalPalette.accentEdge, lineWidth: hairline)
        }
    }
}

/// One comms lane: LABEL · value · META over a 12-segment level bar. Raw
/// white opacities are deliberate — the screen is always dark, so lane
/// surfaces don't theme.
private struct CockpitLaneRow: View {
    let lane: CockpitLaneModel
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.screenInkFaint)
                    .lineLimit(1)
                    .frame(width: 56, alignment: .leading)
                Text(lane.value)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(HomeTacticalPalette.screenInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(lane.meta)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.accent)
                    .lineLimit(1)
            }

            levelBar()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(HomeTacticalPalette.accent.opacity(0.12), lineWidth: 1)
        }
    }

    private func levelBar() -> some View {
        let filled = Int((lane.level * 12).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < filled ? HomeTacticalPalette.accent : Color.white.opacity(0.12))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .shadow(
                        color: index == filled - 1 ? HomeTacticalPalette.accent.opacity(0.50) : .clear,
                        radius: index == filled - 1 ? 3 : 0
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Compact Life-in-Dots module: BRDG / SEND / WAIT rows, each a 6x2 dot grid
/// whose fill mirrors the lane level. The leading-edge marker uses the
/// homepage tactical accent, keeping the cockpit vocabulary coherent.
private struct CockpitDotsModule: View {
    let lanes: [CockpitLaneModel]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(lanes, id: \.shortLabel) { lane in
                dotRow(for: lane)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func dotRow(for lane: CockpitLaneModel) -> some View {
        let filled = Int((lane.level * 12).rounded())
        let marker = filled - 1
        return VStack(spacing: 3) {
            HStack {
                Text(lane.shortLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.screenInkFaint)
                Spacer(minLength: 4)
                Text("\(Int((lane.level * 100).rounded()))%")
                    .talkieType(.timestamp)
                    .foregroundStyle(HomeTacticalPalette.screenInkFaint)
            }
            .lineLimit(1)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 6),
                spacing: 3
            ) {
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(dotFill(index: index, filled: filled, marker: marker))
                        .overlay {
                            if index >= filled && index != marker {
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                            }
                        }
                        .frame(width: 5, height: 5)
                        .shadow(
                            color: index == marker ? HomeTacticalPalette.accent.opacity(0.75) : .clear,
                            radius: index == marker ? 3 : 0
                        )
                }
            }
        }
    }

    private func dotFill(index: Int, filled: Int, marker: Int) -> Color {
        if index == marker { return HomeTacticalPalette.accent }
        if index < filled { return Color.white.opacity(0.92) }
        return .clear
    }
}

// MARK: - Frequent actions (above recents)

private struct HomeFrequentActionsStrip: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· QUICK")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.leading, 4)

            HStack(spacing: 0) {
                actionCell(label: "RECORD", icon: "waveform", accessibilityID: "dock.record") {
                    RecordingSheetController.shared.isPresented = true
                }
                divider
                actionCell(label: "COMPOSE", icon: "square.and.pencil") {
                    AppShellRouter.shared.openCompose(
                        documentID: "blank-\(UUID().uuidString.prefix(8))"
                    )
                }
                divider
                actionCell(label: "SCAN", icon: "camera") {
                    AppShellRouter.shared.openCameraCapture()
                }
                divider
                actionCell(label: "ASK AI", icon: "sparkles") {
                    AppShellRouter.shared.openAskAI()
                }
            }
            .frame(height: 56)
            // Chrome tier — raised metal chassis. Machined sheen + composite
            // bezel shadow read as "lifted metal" above the recessed Recent
            // screen below it. Replaces the flat fill/stroke/whisper-shadow.
            .bezelChassis(padding: 0, corner: 12, metal: true)
        }
    }

    private func actionCell(
        label: String,
        icon: String,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(iconColor(label: label))
                Text(label)
                    .talkieType(.channelLabelTiny)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
        .accessibilityIdentifier(accessibilityID ?? "home.quick.\(label.lowercased().replacing(" ", with: "-"))")
    }

    private func iconColor(label: String) -> Color {
        switch label {
        case "RECORD", "ASK AI":
            return HomeTacticalPalette.accent
        default:
            return theme.currentTheme.chrome.action
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(width: theme.currentTheme.chrome.hairlineWidth)
            .padding(.vertical, 10)
    }
}

// MARK: - Suggestions (below recents)

private struct HomeSuggestionsStrip: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    private var suggestions: [HomeSuggestion] {
        var items: [HomeSuggestion] = []

        if !bridgeManager.isPaired {
            items.append(HomeSuggestion(
                title: "Pair Mac",
                icon: "qrcode.viewfinder",
                action: { AppShellRouter.shared.openBridgeDetail() }
            ))
        } else if bridgeManager.status != .connected {
            items.append(HomeSuggestion(
                title: "Connections",
                icon: "link",
                action: { AppShellRouter.shared.openConnectionCenter() }
            ))
        } else {
            items.append(HomeSuggestion(
                title: "Deck",
                icon: "square.grid.3x3",
                action: { AppShellRouter.shared.openDeck() }
            ))
        }

        items.append(HomeSuggestion(
            title: "Workflows",
            icon: "point.3.connected.trianglepath.dotted",
            action: { AppShellRouter.shared.openWorkflows() }
        ))
        items.append(HomeSuggestion(
            title: "Terminal",
            icon: "terminal",
            action: { AppShellRouter.shared.openTerminal() }
        ))
        items.append(HomeSuggestion(
            title: "Keyboard",
            icon: "keyboard",
            action: { AppShellRouter.shared.openKeyboardActivation() }
        ))

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· EXPLORE")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button(action: suggestion.action) {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(HomeTacticalPalette.accent)
                                Text(suggestion.title)
                                    .talkieType(.fieldLabel)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(theme.colors.cardBackground)
                                    .overlay(
                                        Capsule()
                                            .fill(HomeTacticalPalette.accent.opacity(0.035))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                theme.currentTheme.chrome.edgeFaint,
                                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(suggestion.accessibilityIdentifier)
                    }
                }
            }
        }
    }
}

private struct HomeSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void

    var accessibilityIdentifier: String {
        title == "Keyboard" ? "dock.keyboard" : "home.suggestion.\(title.lowercased().replacing(" ", with: "-"))"
    }
}

// MARK: - RECENT

private enum HomeRecentMetrics {
    static let rowHeight: CGFloat = 38
}

private struct RecentSection: View {
    let items: [HomeFeed.RecentItem]
    let totalCount: Int
    let isLoading: Bool
    let errorMessage: String?
    let isSearching: Bool
    let hasMore: Bool
    let remainingCount: Int
    @Binding var contentFilter: HomeFeed.ContentFilter
    @Binding var sortOption: HomeFeed.SortOption
    let showsSyncPrompt: Bool
    let onLoadMore: () -> Void
    let onPromote: (HomeFeed.RecentItem) -> Void
    let onDelete: (HomeFeed.RecentItem) -> Void
    let onOpenICloudSettings: () -> Void
    let onDismissSyncPrompt: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("· RECENT")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(totalCountLabel)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recent, \(totalCountLabel)")

                Spacer()

                filterMenu
                sortMenu

                Button(action: { AppShellRouter.shared.openLibrary(tab: libraryTabForCurrentFilter) }) {
                    Text("ALL ›")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let errorMessage {
                    FeedMessageState(
                        icon: "exclamationmark.triangle",
                        title: "Couldn’t load recents",
                        message: errorMessage
                    )
                } else if items.isEmpty {
                    EmptyHomeRecentState(
                        isSearching: isSearching,
                        showsSyncPrompt: showsSyncPrompt,
                        onOpenICloudSettings: onOpenICloudSettings,
                        onDismissSyncPrompt: onDismissSyncPrompt
                    )
                } else {
                    List {
                        ForEach(items.enumerated(), id: \.element.id) { idx, item in
                            Button(action: { open(item) }) {
                                RecentRow(item: item, showDivider: idx > 0)
                                    .contentShape(Rectangle())
                            }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("memo.row")
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if item.canPromoteToMemo {
                                        Button {
                                            Haptics.success.fire()  // earned: a keyboard dictation becomes a kept memo
                                            onPromote(item)
                                        } label: {
                                            Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                        }
                                        .tint(theme.currentTheme.chrome.accent)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Haptics.transition.fire()  // firm thud — a row is gone
                                        onDelete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .listRowSpacing(0)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, HomeRecentMetrics.rowHeight)
                    .frame(height: CGFloat(items.count) * HomeRecentMetrics.rowHeight)

                    if hasMore {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(theme.currentTheme.chrome.edgeSubtle.opacity(0.75))
                                .frame(height: theme.currentTheme.chrome.hairlineWidth)

                            Button(action: {
                                Haptics.confirm.fire()  // light "got it" as the next page reveals
                                withAnimation { onLoadMore() }
                            }) {
                                HStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Load \(min(10, remainingCount)) more")
                                        .talkieType(.preview)
                                    Spacer()
                                }
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(height: HomeRecentMetrics.rowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // Screen tier — recessed glass. Sinks below the raised Quick deck
            // above it; the inner top shadow + firmer frame read as content
            // sitting behind the panel face. Keeps card ink so rows stay legible.
            .recessedScreen(corner: 10)
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(HomeFeed.ContentFilter.allCases, id: \.self) { filter in
                Button {
                    contentFilter = filter
                } label: {
                    Label(filter.label, systemImage: filter.icon)
                }
            }
        } label: {
            Label(contentFilter.label, systemImage: contentFilter.icon)
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .accessibilityLabel("Content filter")
        .accessibilityValue(contentFilter.label)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(HomeFeed.SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    Label(option.label, systemImage: option.menuIcon)
                }
            }
        } label: {
            Image(systemName: sortOption.menuIcon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .accessibilityLabel("Sort recent items")
        .accessibilityValue(sortOption.label)
    }

    private var totalCountLabel: String {
        totalCount == 1 ? "1 item" : "\(totalCount) items"
    }

    private var libraryTabForCurrentFilter: LibraryTab? {
        switch contentFilter {
        case .all: return nil
        case .memos: return .memos
        case .dictations: return .dictations
        case .captures: return .items
        }
    }

    private func open(_ item: HomeFeed.RecentItem) {
        switch item.source {
        case .dictation:        AppShellRouter.shared.openMemoDetail(memoID: item.id)
        case .typed:            AppShellRouter.shared.openCompose(documentID: item.id)
        case .link, .scan:      AppShellRouter.shared.openCaptureDetail(captureID: item.id)
        }
    }
}

private struct RecentRow: View {
    let item: HomeFeed.RecentItem
    let showDivider: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                sourceGlyph
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16, height: 16)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if item.isTranscribing {
                        RecentTranscribingBadge()
                    }

                    Spacer(minLength: 8)

                    Text(item.relativeTime)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let syncStatus = item.syncStatus {
                        Image(systemName: syncIcon(for: syncStatus))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(syncColor(for: syncStatus))
                            .accessibilityLabel(syncAccessibilityLabel(for: syncStatus))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: HomeRecentMetrics.rowHeight)

            if showDivider {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle.opacity(0.75))
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
            }
        }
        .frame(height: HomeRecentMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func syncIcon(for status: HomeFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "checkmark.icloud.fill"
        case .pending: return "icloud.and.arrow.up"
        }
    }

    private func syncColor(for status: HomeFeed.SyncStatus) -> Color {
        switch status {
        case .synced: return theme.currentTheme.chrome.accent
        case .pending: return theme.colors.textTertiary
        }
    }

    private func syncAccessibilityLabel(for status: HomeFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "Synced"
        case .pending: return "Sync pending"
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

// MARK: - Transcribing badge

/// Tiny in-row marker shown only while a memo's background transcription pass
/// is running (VoiceMemo.isTranscribing). A pulsing accent pip + smallcap
/// label; the pip holds steady when Reduce Motion is on. Retry / empty-state
/// affordances live in the memo detail view, not here.
private struct RecentTranscribingBadge: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(theme.currentTheme.chrome.accent)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 0.4 : 1)
            Text("TRANSCRIBING")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
        .onAppear {
            guard !TalkieMotion.isReduced else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct FeedMessageState: View {
    let icon: String
    let title: String
    let message: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text(title)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textSecondary)
            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

private struct EmptyHomeRecentState: View {
    let isSearching: Bool
    let showsSyncPrompt: Bool
    let onOpenICloudSettings: () -> Void
    let onDismissSyncPrompt: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            FeedMessageState(
                icon: isSearching ? "magnifyingglass" : "tray",
                title: isSearching ? "· NO MATCHES" : "· NOTHING RECENT",
                message: isSearching ? "Try a different search term" : "Record, dictate, compose, or scan to start your feed."
            )

            if showsSyncPrompt {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud is not signed in")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("Sign in to sync memos with your Mac.")
                            .talkieType(.hint)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    Spacer()
                    Button("Open") {
                        onOpenICloudSettings()
                    }
                    .talkieType(.chipLabel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    Button(action: onDismissSyncPrompt) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(12)
                .background(theme.currentTheme.chrome.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}
