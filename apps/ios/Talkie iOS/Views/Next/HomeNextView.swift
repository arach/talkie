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
    @State private var commandMode: HomeCommandMode = .ask
    @State private var askPrompt = ""

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                HomeCockpit(model: feed.cockpit)
                    .padding(.horizontal, 12)

                HomeFrequentActionsStrip(onSearch: focusSearch)
                    .padding(.horizontal, 12)

                HomeCommandBar(
                    prompt: $askPrompt,
                    searchText: $feed.searchText,
                    mode: $commandMode,
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
            commandMode = .search
            feed.searchText = query
            isCommandFocused = true
            deepLinkManager.clearAction()
        case .openSearch:
            focusSearch()
            deepLinkManager.clearAction()
        default:
            break
        }
    }

    private func focusSearch() {
        commandMode = .search
        isCommandFocused = true
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

    // ── Amber-CRT terminal ink — the phosphor shared by the Message Line strip
    // (TerminalMessageStrip) and the Roll / Gauge amber. The terminal dark-glass
    // gradient stops now live with the reusable strip in TerminalMessageStrip.swift.
    /// The terminal's lit ink — amber phosphor (#FFB24A).
    static let phosphor = Color(hex: "FFB24A")
}

// MARK: - Command center

private enum HomeCommandMode: String {
    case ask
    case search

    var label: String {
        switch self {
        case .ask: "ASK"
        case .search: "FIND"
        }
    }

    var icon: String {
        switch self {
        case .ask: "sparkles"
        case .search: "magnifyingglass"
        }
    }

    var placeholder: String {
        switch self {
        case .ask: "Ask Talkie anything"
        case .search: "Search your captures"
        }
    }
}

private struct HomeAskShortcut: Identifiable {
    let label: String
    let prompt: String

    var id: String { label }

    static let all = [
        HomeAskShortcut(label: "PLAN", prompt: "Help me turn this into a practical plan: "),
        HomeAskShortcut(label: "DRAFT", prompt: "Draft a clear message about: "),
        HomeAskShortcut(label: "THINK", prompt: "Help me think through: "),
    ]
}

private struct HomeCommandBar: View {
    @Binding var prompt: String
    @Binding var searchText: String
    @Binding var mode: HomeCommandMode
    @FocusState.Binding var isFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggleMode) {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.label)
                            .talkieType(.channelLabelTiny)
                    }
                    .foregroundStyle(mode == .ask ? HomeTacticalPalette.accent : theme.colors.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background {
                        Capsule()
                            .fill(mode == .ask ? HomeTacticalPalette.accentSoft : theme.currentTheme.chrome.edgeFaint)
                            .overlay {
                                Capsule().strokeBorder(
                                    mode == .ask ? HomeTacticalPalette.accentEdge : theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                            }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .ask ? "Switch to search" : "Switch to Ask AI")
                .accessibilityIdentifier("home.command-mode")

                TextField(mode.placeholder, text: activeText)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .submitLabel(mode == .ask ? .send : .search)
                    .focused($isFocused)
                    .onSubmit(submit)
                    .accessibilityIdentifier("home.command-field")

                Button(action: submit) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(trailingForeground)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(trailingBackground)
                                .overlay {
                                    Circle().strokeBorder(
                                        trailingBorder,
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                                    )
                                }
                        }
                }
                .buttonStyle(.plain)
                .disabled(mode == .ask && trimmedActiveText.isEmpty)
                .accessibilityLabel(mode == .ask ? "Send to Ask AI" : "Finish searching")
                .accessibilityIdentifier("home.command-send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)

            commandRail
                .frame(height: 34)
                .padding(.horizontal, 11)
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(HomeTacticalPalette.accentSoft.opacity(mode == .ask ? (isFocused ? 0.7 : 0.28) : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isFocused && mode == .ask ? HomeTacticalPalette.accentEdge : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: isFocused ? 1 : theme.currentTheme.chrome.hairlineWidth
                        )
                }
        }
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .animation(.easeOut(duration: 0.18), value: mode)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var commandRail: some View {
        if mode == .ask {
            HStack(spacing: 6) {
                Text("START WITH")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                ForEach(HomeAskShortcut.all) { shortcut in
                    Button(shortcut.label) {
                        prompt = shortcut.prompt
                        isFocused = true
                    }
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textSecondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start with \(shortcut.label.capitalized)")
                }

                Spacer(minLength: 4)

                Button(action: switchToSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                    Text("RECENTS")
                        .talkieType(.channelLabelTiny)
                }
                .foregroundStyle(theme.colors.textTertiary)
                .buttonStyle(.plain)
                .accessibilityLabel("Search Recents")
            }
        } else {
            HStack(spacing: 8) {
                Text(searchText.isEmpty ? "RECENTS FILTER LIVE" : "FILTERING RECENTS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                Spacer()

                if !searchText.isEmpty {
                    Button("CLEAR") { searchText = "" }
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.action)
                        .buttonStyle(.plain)
                }

                Button("ASK AI", action: switchToAsk)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.accent)
                    .buttonStyle(.plain)
            }
        }
    }

    private var activeText: Binding<String> {
        mode == .ask ? $prompt : $searchText
    }

    private var trimmedActiveText: String {
        activeText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trailingIcon: String {
        if mode == .ask { return "arrow.up" }
        return isFocused ? "keyboard.chevron.compact.down" : "magnifyingglass"
    }

    private var trailingForeground: Color {
        if mode == .ask {
            return trimmedActiveText.isEmpty ? theme.colors.textTertiary : theme.colors.cardBackground
        }
        return theme.colors.textSecondary
    }

    private var trailingBackground: Color {
        if mode == .ask, !trimmedActiveText.isEmpty { return HomeTacticalPalette.accent }
        return theme.currentTheme.chrome.edgeFaint
    }

    private var trailingBorder: Color {
        mode == .ask && !trimmedActiveText.isEmpty
            ? HomeTacticalPalette.accentEdge
            : theme.currentTheme.chrome.edgeFaint
    }

    private func submit() {
        guard mode == .ask else {
            isFocused = false
            return
        }

        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        prompt = ""
        isFocused = false
        let isReadyToSend = InferenceService.shared.readiness.isReady
        AppShellRouter.shared.openAskAISeeded(
            prompt: command,
            autoSend: isReadyToSend,
            startsNewSession: true
        )
    }

    private func toggleMode() {
        if mode == .ask {
            switchToSearch()
        } else {
            switchToAsk()
        }
    }

    private func switchToSearch() {
        mode = .search
        isFocused = true
    }

    private func switchToAsk() {
        mode = .ask
        isFocused = true
    }
}

// MARK: - Communication cockpit (the Console)
//
// The converged "Cockpit Two-Row Console" (design/studio/components/studies/
// CockpitTwoRow.tsx). A raised metal Bezel (bezelChassis) around a dark-glass
// Screen — the Message Line straight on top (NO header row) over a fixed-height
// Bay that toggles between two pages via a user-controlled Bay Selector:
//
//   1. Message Line — a slim amber-CRT terminal readout of ONE derived fact,
//      carrying an optional right-docked Docked Readout (STRK n / take count).
//   2. The Bay      — one recessed 144pt well holding both pages so the Selector
//      swaps content with no reflow: THE ROLL (18×7 contribution calendar) ⁄
//      GAUGES (TAKES count + Meter · TIME m:ss + Meter · STRK Life-in-Dots).
//      The list-replay Take Log is retired; GAUGES read as instruments only.
//
// Nominal tap opens the Library (the tape it summarizes); first-run standby taps
// open the recorder. Screen ink only — always dark. The Bay Selector's 0.4s
// crossfade is the only animation.
//
// Vocabulary: design/studio/app/cockpit-two-row/page.tsx (NamesMarginalia —
// Console · Bezel · Message Line · Docked Readout · Toggle · Bay · Roll Bay ·
// Gauge Bay · Meter · Life-in-Dots). Data: HomeFeed.makeCockpit (one pass).

/// Studio-mirrored Console geometry. Named so studio · Swift · chat share one
/// vocabulary; values track CockpitTwoRow.tsx exactly. The Roll grid geometry
/// lives on HomeFeed (the data owner); these are the visual + message knobs.
private enum HomeCockpitMetrics {
    // Bezel + Screen (BEZEL_PAD 7 · SCREEN_PAD 10 · STACK_GAP 8 → CONSOLE_H 220)
    static let bezelPad: CGFloat = 7
    static let bezelCorner: CGFloat = 14
    static let screenPad: CGFloat = 10
    static let screenCorner: CGFloat = 12
    static let stackGap: CGFloat = 8

    // Message Line
    static let messageHeight: CGFloat = 32      // MSG_H

    // The Roll (CELL 12 · CGAP 3 → grid 102pt tall)
    static let rollCell: CGFloat = 12           // CELL
    static let rollGap: CGFloat = 3             // CGAP

    // The Bay (BAY_PAD 10 · BAY_LABEL_H 14 · BAY_LABEL_GAP 8 · BAY_CONTENT_H 102 → BAY_H 144)
    static let bayPad: CGFloat = 10
    static let bayCorner: CGFloat = 8
    static let bayLabelHeight: CGFloat = 14
    static let bayLabelGap: CGFloat = 8
    static let bayContentHeight: CGFloat = 102
    static let bayHeight: CGFloat = 144

    // Gauge lanes (G_TAKES_H 28 · G_TIME_H 28 · G_STRK_H 38 · G_GAP 4 → 102)
    static let gaugeTakesHeight: CGFloat = 28
    static let gaugeTimeHeight: CGFloat = 28
    static let gaugeStrkHeight: CGFloat = 38
    static let gaugeGap: CGFloat = 4
    static let gaugeCorner: CGFloat = 6

    // Life-in-Dots (DOT 7 · DOT_GAP 4 · last 12 days, 6×2)
    static let dot: CGFloat = 7
    static let dotGap: CGFloat = 4

    // Meter full-bar scales (a full 12-seg bar = a strong day)
    static let scaleTakes: Double = 4           // SCALE_TAKES — 4 takes fills the bar
    static let scaleTimeSeconds: Double = 360   // SCALE_TIME — 6:00 fills the bar

    // Bay Selector crossfade (user-initiated)
    static let baySelectorCrossfade: Double = 0.4

    // Message-line derivation
    static let milestoneWindow = 5              // "just crossed" a 100 boundary
    static let recencyDays = 7                  // recency inside a week, else station ident

    /// Clamp a level to the meter's [0, 1] fill range.
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// The single derived fact on the Message Line, priority-ordered. Pure so both
/// the terminal render and the accessibility label read the same string.
private enum CockpitMessage {
    static func line(model: HomeFeed.CockpitModel, parakeetDownloading: Bool, now: Date) -> String {
        if model.isEmpty { return "STANDING BY — ROLL TAPE TO BEGIN" }
        if parakeetDownloading { return "PARAKEET DOWNLOADING" }
        if model.totalTakes >= 100, model.totalTakes % 100 < HomeCockpitMetrics.milestoneWindow {
            return "TAKE #\(model.totalTakes) ON TAPE"
        }
        if let last = model.lastTakeDate {
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            if days < HomeCockpitMetrics.recencyDays {
                return "LAST TAKE \(HomeFeed.compactAge(from: last, now: now)) AGO"
            }
        }
        return stationIdent(now: now)
    }

    private static func stationIdent(now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 9 { return "TALKIE · EARLY SHIFT" }
        if hour >= 22 { return "NIGHT DESK" }
        return "TALKIE · ON AIR"
    }
}

private struct HomeActivityEvent: Identifiable {
    let time: String
    let title: String
    let kind: String

    var id: String { "\(time)-\(title)" }
}

private struct HomeCockpit: View {
    let model: HomeFeed.CockpitModel
    @ObservedObject private var parakeet = ParakeetModelManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if isScreenshotMode {
            VStack(alignment: .leading, spacing: 8) {
                Text("· TODAY")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.leading, 4)

                Button(action: open) {
                    VStack(spacing: 8) {
                        HomeActivityScreen(events: screenshotEvents)

                        Text("3 COMPLETED TODAY · LATEST 5 MIN AGO")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .softCard(
                        padding: 10,
                        corner: 14,
                        emphasis: .edge,
                        fill: HomeTacticalPalette.matte
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Today's Talkie activity: roadmap memo recorded, product brief summarized, follow-up added to Reminders")
                .accessibilityHint("Shows today's completed Talkie activity")
            }
        } else {
            // The production cockpit retains master's latest Roll/Gauges bay.
            Button(action: open) {
                CockpitScreen(model: model, parakeetDownloading: parakeetDownloading)
                    .frame(maxWidth: .infinity)
                    .bezelChassis(
                        padding: HomeCockpitMetrics.bezelPad,
                        corner: HomeCockpitMetrics.bezelCorner,
                        metal: true,
                        fill: HomeTacticalPalette.matte
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(model.isEmpty ? "Opens the recorder to capture your first take" : "Opens your library")
        }
    }

    private var parakeetDownloading: Bool {
        if case .downloading = parakeet.state { return true }
        return false
    }

    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    }

    // Routing: nominal → the Library (the tape this instrument summarizes);
    // first-run standby → the recorder, since there is nothing to browse yet.
    private func open() {
        if model.isEmpty {
            RecordingSheetController.shared.isPresented = true
        } else {
            AppShellRouter.shared.openLibrary()
        }
    }

    private var screenshotEvents: [HomeActivityEvent] {
        [
            HomeActivityEvent(time: "9:36", title: "Roadmap memo recorded", kind: "VOICE"),
            HomeActivityEvent(time: "9:18", title: "Product brief summarized", kind: "AI"),
            HomeActivityEvent(time: "8:54", title: "Follow-up added to Reminders", kind: "ACTION"),
        ]
    }

    // Describes both bay pages regardless of which is up: the message line, the
    // Roll streak, and today's take count. Standby leads with the recorder cue.
    private var accessibilitySummary: String {
        let message = CockpitMessage.line(model: model, parakeetDownloading: parakeetDownloading, now: Date())
        if model.isEmpty {
            return "Cockpit, standing by. \(message). Tap to record your first take."
        }
        let streakPart = model.streak == 1 ? "the Roll, 1 day streak" : "the Roll, \(model.streak) day streak"
        let todayPart = model.todayTakes == 1 ? "1 take today" : "\(model.todayTakes) takes today"
        let totalPart = model.totalTakes == 1 ? "1 take on tape" : "\(model.totalTakes) takes on tape"
        return "Cockpit. \(message). \(totalPart). \(streakPart). \(todayPart)."
    }

}

/// Screenshot-mode event log. Unlike the production communication cockpit,
/// this shows discrete outcomes in time order—no synthetic levels or telemetry.
private struct HomeActivityScreen: View {
    let events: [HomeActivityEvent]
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
                Text("ACTIVITY")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.accent)
                Spacer()
                Text("9:41")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeTacticalPalette.screenInkFaint)
            }

            VStack(spacing: 0) {
                ForEach(events.enumerated(), id: \.element.id) { index, event in
                    HomeActivityRow(event: event, showsDivider: index < events.count - 1)
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(HomeTacticalPalette.accent.opacity(0.14), lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                HomeTacticalPalette.screen
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.black.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [HomeTacticalPalette.accent.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.72, y: 0.36),
                    startRadius: 0,
                    endRadius: 140
                )
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(HomeTacticalPalette.accentEdge, lineWidth: hairline)
        }
    }
}

private struct HomeActivityRow: View {
    let event: HomeActivityEvent
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 9) {
            Text(event.time)
                .talkieType(.timestamp)
                .foregroundStyle(HomeTacticalPalette.screenInkFaint)
                .frame(width: 34, alignment: .leading)

            Circle()
                .fill(HomeTacticalPalette.accent)
                .frame(width: 5, height: 5)
                .shadow(color: HomeTacticalPalette.accent.opacity(0.65), radius: 3)

            Text(event.title)
                .talkieType(.preview)
                .foregroundStyle(HomeTacticalPalette.screenInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(event.kind)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(HomeTacticalPalette.accent)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.leading, 52)
            }
        }
    }
}

/// The always-dark instrument screen inside the cockpit chassis: the Message Line
/// on top (now the sole status carrier — no more TALKIE/status/clock header row)
/// over the shared slot where the Take Log and the Roll alternate. Panel ink only
/// — the screen ignores light/dark so it reads as lit glass everywhere. The
/// 60-second timeline keeps the message-line age and the time-of-day station ident
/// fresh without any per-frame animation.
private struct CockpitScreen: View {
    let model: HomeFeed.CockpitModel
    let parakeetDownloading: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let hairline = max(theme.currentTheme.chrome.hairlineWidth, 0.8)
        let shape = RoundedRectangle(cornerRadius: HomeCockpitMetrics.screenCorner, style: .continuous)

        VStack(spacing: HomeCockpitMetrics.stackGap) {
            // Message Line — straight on top (no header). Its own 60s timeline
            // keeps the age / station-ident fresh with no per-frame animation.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                TerminalMessageStrip(
                    text: CockpitMessage.line(
                        model: model,
                        parakeetDownloading: parakeetDownloading,
                        now: context.date
                    ),
                    height: HomeCockpitMetrics.messageHeight,
                    dock: dockReadout
                )
            }

            // The Bay — the toggled 144pt well (Roll ⁄ Gauges).
            CockpitBay(model: model)
        }
        .padding(HomeCockpitMetrics.screenPad)
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

    /// The Docked Readout for the Message Line, resolved from the dial. Hidden in
    /// first-run standby (DAY 1 semantics haven't started yet).
    private var dockReadout: TerminalDockReadout? {
        guard !model.isEmpty else { return nil }
        switch CockpitDockDial.current {
        case .none:
            return nil
        case .streak:
            return TerminalDockReadout(label: "STRK", value: "\(model.streak)", hot: model.streak > 0)
        case .takesToday:
            return TerminalDockReadout(label: "TAKES", value: "\(model.todayTakes)", hot: model.todayTakes > 0)
        }
    }
}

/// The Docked Readout dial — the single knob picking which useful fact the
/// Message Line's right-docked lane carries (studio "Docked Readout"). Defaults
/// to `.streak`; `.none` bares the strip and `.takesToday` shows the day's count.
/// The lane is hidden entirely in first-run standby (see `dockReadout`).
private enum CockpitDockDial {
    case none, streak, takesToday
    static let current: CockpitDockDial = .streak
}

// MARK: - The Bay (Roll ⁄ Gauges)

/// Which page the Bay is showing. Persisted via @AppStorage so the chosen bay
/// survives relaunch.
private enum CockpitBayPage: String {
    case roll, gauges
    var toggled: CockpitBayPage { self == .roll ? .gauges : .roll }
}

/// The toggled big section under the Message Line — one recessed 144pt well that
/// both pages fill (ZStack, opacity), so the Bay Selector swaps content with no
/// reflow. Its label row carries the Selector on the left and a contextual
/// readout on the right (STRK n on ROLL · TODAY · 7-DAY AVG on GAUGES).
private struct CockpitBay: View {
    let model: HomeFeed.CockpitModel
    @AppStorage("home.cockpit.bayPage") private var bayPageRaw = CockpitBayPage.roll.rawValue

    private var page: CockpitBayPage { CockpitBayPage(rawValue: bayPageRaw) ?? .roll }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeCockpitMetrics.bayCorner, style: .continuous)

        VStack(spacing: HomeCockpitMetrics.bayLabelGap) {
            // Label row — the Bay Selector + a contextual readout.
            HStack(spacing: 8) {
                BaySelector(page: page, onToggle: toggle)
                Spacer(minLength: 0)
                Text(readout)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8) // 0.1em at 8pt
                    .foregroundStyle(readoutHot ? HomeTacticalPalette.accent : HomeTacticalPalette.screenInkFaint)
                    .accessibilityHidden(true)
            }
            .frame(height: HomeCockpitMetrics.bayLabelHeight)

            // Content — both pages laid out; the chosen one lit. Fixed 102pt.
            ZStack {
                CockpitRollPage(model: model)
                    .opacity(page == .roll ? 1 : 0)
                CockpitGaugePage(model: model)
                    .opacity(page == .gauges ? 1 : 0)
            }
            .frame(height: HomeCockpitMetrics.bayContentHeight)
        }
        .padding(HomeCockpitMetrics.bayPad)
        .frame(height: HomeCockpitMetrics.bayHeight)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: HomeCockpitMetrics.baySelectorCrossfade)) {
            bayPageRaw = page.toggled.rawValue
        }
    }

    private var readout: String {
        if model.isEmpty { return page == .roll ? "DAY 1" : "DAY 1 · STANDBY" }
        return page == .roll ? "STRK \(model.streak)" : "TODAY · 7-DAY AVG"
    }

    private var readoutHot: Bool {
        page == .roll && (model.isEmpty || model.streak > 0)
    }
}

// MARK: - Bay Selector (the two-position Toggle)

/// The tiny hardware two-position Bay Selector on the Bay's label row — a
/// recessed dark track with ROLL ⁄ GAUGES segments, the active bay lit amber
/// phosphor. A nested Button: tapping it toggles the bay (0.4s crossfade) and,
/// because SwiftUI gives the innermost button the tap, never fires the outer
/// whole-Console tap.
private struct BaySelector: View {
    let page: CockpitBayPage
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 1) {
                segment(.roll, "ROLL")
                segment(.gauges, "GAUGES")
            }
            .padding(1)
            .frame(height: HomeCockpitMetrics.bayLabelHeight)
            .background(
                LinearGradient(
                    colors: [Color(hex: "050301"), Color(hex: "0B0704")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(HomeTacticalPalette.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bay selector")
        .accessibilityValue(page == .roll ? "The Roll" : "Gauges")
        .accessibilityHint("Toggles the cockpit bay between the Roll and the Gauges")
    }

    @ViewBuilder
    private func segment(_ key: CockpitBayPage, _ label: String) -> some View {
        let on = key == page
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.96) // 0.12em at 8pt
            .foregroundStyle(on ? HomeTacticalPalette.phosphor : HomeTacticalPalette.phosphor.opacity(0.5))
            .shadow(color: on ? HomeTacticalPalette.accent.opacity(0.55) : .clear, radius: on ? 3 : 0)
            .padding(.horizontal, 7)
            .frame(maxHeight: .infinity)
            .background(on ? HomeTacticalPalette.accent.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(HomeTacticalPalette.accent.opacity(0.4), lineWidth: 0.5)
                }
            }
    }
}

// MARK: - The Roll page (Roll Bay)

/// THE ROLL page — the 18×7 contribution calendar reseated into the Bay's well
/// (the label + STRK readout now live on the Bay's shared label row). Cell
/// intensity = captures that day; the trailing Streak Run lights amber and ends
/// on the Today Marker. Standby ⇒ Ghost Cells + the amber Today Seed.
private struct CockpitRollPage: View {
    let model: HomeFeed.CockpitModel

    private var days: [Int] { model.rollDays }
    private var todayIndex: Int { model.todayIndex }
    private var streak: Int { model.streak }
    private var ghost: Bool { model.isEmpty }

    private func intensity(_ index: Int) -> Int {
        index >= 0 && index < days.count ? days[index] : 0
    }

    private var runEnd: Int {
        guard streak > 0 else { return -1 }
        return intensity(todayIndex) > 0 ? todayIndex : todayIndex - 1
    }

    var body: some View {
        let end = runEnd
        let runStart = end - streak + 1

        VStack(spacing: HomeCockpitMetrics.rollGap) {
            ForEach(0..<HomeFeed.rollDaysPerWeek, id: \.self) { row in
                HStack(spacing: HomeCockpitMetrics.rollGap) {
                    ForEach(0..<HomeFeed.rollWeeks, id: \.self) { col in
                        let index = col * HomeFeed.rollDaysPerWeek + row
                        RollCell(
                            intensity: intensity(index),
                            isToday: index == todayIndex,
                            inRun: streak > 0 && index >= runStart && index <= end,
                            isFuture: index > todayIndex,
                            ghost: ghost
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // center the grid in the well
        .accessibilityHidden(true)
    }
}

// MARK: - The Gauge page (Gauge Bay)

/// GAUGES page — three instrument lanes filling the well (NOT a Take Log replay):
/// TAKES (today's count + 12-seg Meter vs 7-day avg + pace) · TIME (today's m:ss
/// + Meter) · STRK (Life-in-Dots + run count). Lane heights sum to 102pt.
private struct CockpitGaugePage: View {
    let model: HomeFeed.CockpitModel

    private var standby: Bool { model.isEmpty }

    var body: some View {
        VStack(spacing: HomeCockpitMetrics.gaugeGap) {
            MeterLane(
                caption: "TAKES",
                readout: standby ? "0" : "\(model.todayTakes)",
                todayLevel: HomeCockpitMetrics.clamp01(Double(model.todayTakes) / HomeCockpitMetrics.scaleTakes),
                avgLevel: HomeCockpitMetrics.clamp01(model.avgTakes / HomeCockpitMetrics.scaleTakes),
                standby: standby,
                height: HomeCockpitMetrics.gaugeTakesHeight
            )
            MeterLane(
                caption: "TIME",
                readout: standby ? "0:00" : HomeFeed.compactDuration(model.todayDurationSeconds),
                todayLevel: HomeCockpitMetrics.clamp01(model.todayDurationSeconds / HomeCockpitMetrics.scaleTimeSeconds),
                avgLevel: HomeCockpitMetrics.clamp01(model.avgDurationSeconds / HomeCockpitMetrics.scaleTimeSeconds),
                standby: standby,
                height: HomeCockpitMetrics.gaugeTimeHeight
            )
            StrkLane(model: model, height: HomeCockpitMetrics.gaugeStrkHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Meter lane (TAKES · TIME)

/// One meter gauge lane — CAPTION · big phosphor readout · 12-segment Meter ·
/// pace label. Reused by the TAKES + TIME gauges.
private struct MeterLane: View {
    let caption: String
    let readout: String
    let todayLevel: Double
    let avgLevel: Double
    let standby: Bool
    let height: CGFloat

    var body: some View {
        let pace = MeterLane.pace(todayLevel: todayLevel, avgLevel: avgLevel, standby: standby)
        HStack(spacing: 9) {
            Text(caption)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8) // 0.1em at 8pt
                .foregroundStyle(HomeTacticalPalette.phosphor.opacity(0.5))
                .frame(width: 42, alignment: .leading)

            Text(readout)
                .font(.system(size: 15, weight: .bold, design: .monospaced).monospacedDigit())
                .tracking(0.3) // 0.02em at 15pt
                .foregroundStyle(standby ? HomeTacticalPalette.phosphor.opacity(0.5) : HomeTacticalPalette.phosphor)
                .shadow(color: standby ? .clear : HomeTacticalPalette.accent.opacity(0.55), radius: standby ? 0 : 4)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)

            SegMeter(todayLevel: todayLevel, avgLevel: avgLevel, standby: standby)
                .frame(maxWidth: .infinity)

            Text(pace.text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.48) // 0.06em at 8pt
                .foregroundStyle(pace.hot ? HomeTacticalPalette.accent : HomeTacticalPalette.phosphor.opacity(0.5))
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Pace from the today-vs-average delta (studio `paceOf`).
    static func pace(todayLevel: Double, avgLevel: Double, standby: Bool) -> (text: String, hot: Bool) {
        if standby { return ("—", false) }
        let d = todayLevel - avgLevel
        if d > 0.02 { return ("▲ ABOVE AVG", true) }
        if d < -0.02 { return ("▼ BELOW AVG", false) }
        return ("= AT AVG", false)
    }
}

// MARK: - Segment Meter

/// The slim 12-segment Meter — fill = today, a brighter amber tick marks where
/// the trailing 7-day average sits, so today reads against its own baseline.
/// Standby ⇒ 12 outlined Ghost segments.
private struct SegMeter: View {
    let todayLevel: Double
    let avgLevel: Double
    let standby: Bool

    var body: some View {
        let filled = standby ? 0 : Int((HomeCockpitMetrics.clamp01(todayLevel) * 12).rounded())
        let avgIndex = standby ? 0 : Int((HomeCockpitMetrics.clamp01(avgLevel) * 12).rounded())

        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                let lit = i < filled
                let isAvg = !standby && avgIndex > 0 && i == avgIndex - 1
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill(lit: lit, isAvg: isAvg))
                    .overlay {
                        if standby {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .shadow(
                        color: glow(i: i, filled: filled, lit: lit, isAvg: isAvg),
                        radius: (isAvg || (lit && i == filled - 1)) ? 3 : 0
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
    }

    private func fill(lit: Bool, isAvg: Bool) -> Color {
        if standby { return .clear }
        if isAvg && !lit { return HomeTacticalPalette.accent.opacity(0.5) }
        if lit { return HomeTacticalPalette.accent }
        return Color.white.opacity(0.12)
    }

    private func glow(i: Int, filled: Int, lit: Bool, isAvg: Bool) -> Color {
        if standby { return .clear }
        if isAvg { return HomeTacticalPalette.accent.opacity(0.7) }
        if lit && i == filled - 1 { return HomeTacticalPalette.accent.opacity(0.55) }
        return .clear
    }
}

// MARK: - STRK lane (Life-in-Dots)

/// The STRK gauge — the run count + the Life-in-Dots module (last 12 days, 6×2).
private struct StrkLane: View {
    let model: HomeFeed.CockpitModel
    let height: CGFloat

    private var standby: Bool { model.isEmpty }
    private var streak: Int { model.streak }

    var body: some View {
        HStack(spacing: 9) {
            Text("STRK")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8) // 0.1em at 8pt
                .foregroundStyle(HomeTacticalPalette.phosphor.opacity(0.5))
                .frame(width: 42, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(standby ? "0" : "\(streak)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(standby || streak > 0 ? HomeTacticalPalette.accent : HomeTacticalPalette.phosphor.opacity(0.5))
                    .shadow(
                        color: (!standby && streak > 0) ? HomeTacticalPalette.accent.opacity(0.5) : .clear,
                        radius: (!standby && streak > 0) ? 3 : 0
                    )
                Text(standby ? "DAY 1" : "DAY RUN")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(0.56) // 0.08em at 7pt
                    .foregroundStyle(HomeTacticalPalette.phosphor.opacity(0.5))
            }
            .frame(width: 66, alignment: .leading)

            Spacer(minLength: 0)

            LifeInDots(days: model.last12Days, standby: standby)
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// The Life-in-Dots module — the last 12 days as a 6×2 dot grid (row-major,
/// oldest→newest; today = bottom-right). Filled = captured · amber = today ·
/// outlined = empty. Standby ⇒ Ghost dots + the amber Today Seed.
private struct LifeInDots: View {
    let days: [Bool] // oldest→newest, length 12
    let standby: Bool

    var body: some View {
        VStack(spacing: HomeCockpitMetrics.dotGap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: HomeCockpitMetrics.dotGap) {
                    ForEach(0..<6, id: \.self) { col in
                        let i = row * 6 + col
                        Dot(filled: filled(i), isToday: i == 11, standby: standby)
                    }
                }
            }
        }
    }

    private func filled(_ i: Int) -> Bool { i >= 0 && i < days.count ? days[i] : false }
}

private struct Dot: View {
    let filled: Bool
    let isToday: Bool
    let standby: Bool

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: HomeCockpitMetrics.dot, height: HomeCockpitMetrics.dot)
            .overlay { stroke }
            .shadow(color: glowColor, radius: glowRadius)
    }

    private var fill: Color {
        if standby { return .clear }
        if isToday { return HomeTacticalPalette.accent }
        if filled { return Color.white.opacity(0.9) }
        return .clear
    }

    @ViewBuilder
    private var stroke: some View {
        if standby && isToday {
            Circle().strokeBorder(HomeTacticalPalette.accent, lineWidth: 1.5) // amber Today Seed
        } else if standby {
            Circle().strokeBorder(Color.white.opacity(0.11), lineWidth: 1) // Ghost dot
        } else if !filled && !isToday {
            Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) // empty day
        }
    }

    private var glowColor: Color {
        if standby && isToday { return HomeTacticalPalette.accent.opacity(0.7) }
        if !standby && isToday { return HomeTacticalPalette.accent.opacity(0.8) }
        return .clear
    }

    private var glowRadius: CGFloat {
        if isToday { return standby ? 3 : 4 }
        return 0
    }
}

// MARK: - Roll cell

/// One Roll cell. Precedence (matching studio RollCell): ghost (standby) → future
/// → today → in-run → active intensity → empty past day.
private struct RollCell: View {
    let intensity: Int
    let isToday: Bool
    let inRun: Bool
    let isFuture: Bool
    /// Standby / first-run — draw an outlined Ghost Cell, today as the amber Seed.
    var ghost: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .frame(width: HomeCockpitMetrics.rollCell, height: HomeCockpitMetrics.rollCell)
            .overlay { strokeOverlay }
            .shadow(color: glowColor, radius: glowRadius)
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        if ghost && isToday {
            // The amber Today Seed — the "you are here" the streak grows from.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(HomeTacticalPalette.accent, lineWidth: 1.5)
        } else if ghost {
            // A Ghost Cell — a faint outline sketching the grid that will fill in.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        } else if isToday && intensity == 0 {
            // Today, no capture yet — an unlit amber ring marker.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(HomeTacticalPalette.accent, lineWidth: 1)
        }
    }

    private var fill: Color {
        if ghost { return .clear }  // ghost cells are outlined only
        if isFuture { return Color.white.opacity(0.03) }
        if isToday && intensity > 0 { return HomeTacticalPalette.accent }
        if isToday { return .clear }  // ring drawn in the overlay
        if inRun { return HomeTacticalPalette.accent.opacity(0.7 + Double(intensity) * 0.1) }
        if intensity > 0 { return activeInk }
        return Color.white.opacity(0.05)   // empty past day
    }

    private var activeInk: Color {
        if intensity >= 3 { return Color.white.opacity(0.85) }
        if intensity == 2 { return Color.white.opacity(0.55) }
        return Color.white.opacity(0.30)
    }

    private var glowColor: Color {
        if ghost && isToday { return HomeTacticalPalette.accent.opacity(0.7) }
        if ghost { return .clear }
        if isToday && intensity > 0 { return HomeTacticalPalette.accent.opacity(0.85) }
        if inRun { return HomeTacticalPalette.accent.opacity(0.4) }
        return .clear
    }

    private var glowRadius: CGFloat {
        if ghost && isToday { return 4 }
        if ghost { return 0 }
        if isToday && intensity > 0 { return 4 }
        if inRun { return 2 }
        return 0
    }
}

// MARK: - Frequent actions (above recents)

private struct HomeFrequentActionsStrip: View {
    let onSearch: () -> Void

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
                actionCell(label: "SEARCH", icon: "magnifyingglass", action: onSearch)
            }
            .frame(height: 56)
            // A clean framed control rail. The hairline gives it enough
            // structure without repeating the cockpit's heavy depth cues.
            .softCard(padding: 0, corner: 12, emphasis: .faint)
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
        case "RECORD", "SEARCH":
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
            // Recents are a quiet reading surface, not another instrument
            // screen. A flat fill and hairline frame preserve grouping without
            // casting a gray falloff over the first row.
            .softCard(
                padding: 0,
                corner: 10,
                emphasis: .faint,
                fill: theme.colors.cardBackground.opacity(0.72)
            )
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
                        .talkieType(.preview)
                        .foregroundStyle(isContentPreview ? theme.colors.textSecondary : theme.colors.textPrimary)
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

    private var isContentPreview: Bool {
        if case .typed = item.source { return true }
        return false
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
