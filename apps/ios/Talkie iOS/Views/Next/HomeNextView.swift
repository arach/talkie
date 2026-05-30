//
//  HomeNextView.swift
//  Talkie iOS
//
//  M1 — Talkie's canonical iPhone home, painted to match the
//  studio mock at http://localhost:3000/home.
//
//  Composition: TALKIE wordmark · frequent-action strip · Recent
//  list (2-line iOS-Notes style) · contextual suggestions strip.
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
    @State private var isSearchPresented = false

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                HomeFrequentActionsStrip()
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
        .searchable(
            text: $feed.searchText,
            isPresented: $isSearchPresented,
            prompt: "Search memos, dictations, and captures"
        )
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
            isSearchPresented = true
            deepLinkManager.clearAction()
        case .openSearch:
            isSearchPresented = true
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
        // Gear and Deck share a 40pt footprint so the wordmark stays
        // centered while the chrome carries the two persistent home
        // destinations: remote control on the left, settings on the
        // right.
        HStack {
            // Command Deck rests in the top-left slot. It keeps the
            // same 40pt footprint as the settings gear so the wordmark
            // stays centered while the remote remains discoverable.
            ZStack {
                DeckComplication()
            }
            .frame(width: 40, height: 40)
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

// MARK: - Deck complication

/// Resting Command Deck complication at the top-left of Home.
/// It opens the remote even before pairing so the empty state can
/// explain what is needed, while color and the tiny status bead carry
/// the Mac bridge/deck state without turning the header into a status
/// dashboard.
private struct DeckComplication: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: openDeck) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(theme.colors.cardBackground)
                    Circle().strokeBorder(
                        borderColor,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 40, height: 40)

                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(theme.colors.background, lineWidth: 2)
                        )
                        .offset(x: -6, y: -6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
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

    private var isConnected: Bool {
        bridgeManager.status == .connected
    }

    private func openDeck() {
        AppShellRouter.shared.openDeck()
    }

    // MARK: - Visual treatment per state

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

    private var borderColor: Color {
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.5)
        }
        if isConnected && hasDeckBoard {
            return theme.currentTheme.chrome.accent.opacity(0.55)
        }
        if isConnected {
            return Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.45)
        }
        return theme.currentTheme.chrome.edgeFaint
    }

    private var statusColor: Color? {
        if !bridgeManager.isPaired {
            return nil
        }
        if bridgeManager.status == .error {
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
        if hasDeckBoard {
            return theme.currentTheme.chrome.accent
        }
        if isConnected {
            return Color(red: 0.36, green: 0.74, blue: 0.50)
        }
        if bridgeManager.awaitingPairingApproval || bridgeManager.status == .connecting {
            return theme.currentTheme.chrome.accent.opacity(0.75)
        }
        return theme.colors.textTertiary.opacity(0.7)
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

// MARK: - Frequent actions (above recents)

private struct HomeFrequentActionsStrip: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· QUICK")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.leading, 4)

            HStack(spacing: 0) {
                actionCell(label: "RECORD", icon: "waveform") {
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

    private func actionCell(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text(label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
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
            title: "Library",
            icon: "books.vertical",
            action: { AppShellRouter.shared.openLibrary() }
        ))
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
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button(action: suggestion.action) {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.currentTheme.chrome.accent)
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
                                            .strokeBorder(
                                                theme.currentTheme.chrome.edgeFaint,
                                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
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
}

// MARK: - RECENT

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
                Text("· RECENT · \(totalCount)")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                Spacer()

                filterMenu
                sortMenu

                Button(action: { AppShellRouter.shared.openLibrary() }) {
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
                            RecentRow(item: item, showDivider: idx > 0)
                                .contentShape(Rectangle())
                                .onTapGesture { open(item) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if item.canPromoteToMemo {
                                        Button {
                                            onPromote(item)
                                        } label: {
                                            Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                        }
                                        .tint(theme.currentTheme.chrome.accent)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
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
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(items.count) * 72)

                    if hasMore {
                        Button(action: {
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
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Rectangle()
                                .fill(theme.currentTheme.chrome.edgeSubtle)
                                .frame(height: theme.currentTheme.chrome.hairlineWidth)
                                .padding(.leading, 36),
                            alignment: .top
                        )
                    }
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

                        if let meta = item.meta {
                            Text(meta)
                                .talkieType(.hint)
                                .foregroundStyle(theme.colors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
