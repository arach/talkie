//
//  WebCaptureBrowserNext.swift
//  Talkie iOS
//
//  Faithful re-port of WebCaptureBrowser (apps/ios/Talkie iOS/
//  Views/WebCaptureBrowser.swift, 543 lines). Donor structure:
//
//  - URL bar row: back / forward / URL pill (search-or-loading
//    icon + TextField + voice mic) / history-or-reload-or-done
//    button on the right.
//  - When URL bar focused with text: autocomplete suggestions
//    overlay (BrowseHistoryEntry rows).
//  - When URL bar focused with empty text: history list.
//  - Otherwise: WKWebView body (Codex wires
//    WebViewRepresentable + WebViewState).
//  - Top toolbar: Cancel (left), Capture button (right, with
//    progress spinner when isCapturing, disabled when !hasContent).
//  - Voice search states (donor's InlineDictationController.State):
//    idle / recording / transcribing. Recording shows "Listening…"
//    placeholder, transcribing shows spinner, idle shows
//    magnifyingglass.
//

import SwiftUI
import TalkieMobileKit

@MainActor
final class WebCaptureBrowserStore: ObservableObject {
    @Published var urlBarText: String = ""
    @Published var currentURL: String?
    @Published var currentTitle: String?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var hasContent: Bool = false
    @Published var isCapturing: Bool = false
    @Published var voiceSearchState: VoiceSearchState = .idle
    @Published var voiceSearchError: String?
    @Published var history: [HistoryEntry] = []

    private let browseHistory = BrowseHistory.shared

    enum VoiceSearchState { case idle, recording, transcribing }

    struct HistoryEntry: Identifiable {
        let id: UUID
        let url: String
        let title: String?
        let domain: String?
        let lastVisited: Date

        init(entry: BrowseHistoryEntry) {
            self.id = entry.id
            self.url = entry.url
            self.title = entry.title
            self.domain = entry.domain
            self.lastVisited = entry.visitedAt
        }
    }

    init() {
        refreshHistory()
    }

    func bind(webState: WebViewState) {
        currentURL = webState.currentURL?.absoluteString
        currentTitle = webState.currentTitle
        isLoading = webState.isLoading
        canGoBack = webState.canGoBack
        canGoForward = webState.canGoForward
        hasContent = webState.hasContent
    }

    func refreshHistory() {
        history = browseHistory.recentEntries().map(HistoryEntry.init(entry:))
    }

    func recordHistory(url: String, title: String?) {
        browseHistory.record(url: url, title: title)
        refreshHistory()
    }

    func suggestions(for query: String) -> [HistoryEntry] {
        browseHistory.suggestions(for: query).map(HistoryEntry.init(entry:))
    }

    func updateVoiceSearchState(_ state: InlineDictationController.State) {
        switch state {
        case .idle:
            voiceSearchState = .idle
        case .recording:
            voiceSearchState = .recording
        case .transcribing:
            voiceSearchState = .transcribing
        }
    }
}

struct WebCaptureBrowserNext: View {
    var initialURL: URL?

    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = WebCaptureBrowserStore()
    @StateObject private var webState = WebViewState()
    @FocusState private var urlFieldFocused: Bool

    private let voiceSearch = InlineDictationController()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            urlBar

            ZStack {
                if urlFieldFocused && !store.urlBarText.isEmpty {
                    suggestionsOverlay
                } else if urlFieldFocused && store.urlBarText.isEmpty {
                    historyList
                } else {
                    webViewBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.bind(webState: webState)
            store.urlBarText = webState.currentURL?.absoluteString ?? store.currentURL ?? ""
            store.refreshHistory()
            wireVoiceSearch()
        }
        .onChange(of: webState.currentURL) { _, url in
            store.bind(webState: webState)
            if !urlFieldFocused && store.voiceSearchState == .idle {
                store.urlBarText = url?.absoluteString ?? ""
            }
        }
        .onChange(of: webState.currentTitle) { _, title in
            store.bind(webState: webState)
            if let url = webState.currentURL?.absoluteString {
                store.recordHistory(url: url, title: title)
            }
        }
        .onChange(of: webState.isLoading) { _, _ in store.bind(webState: webState) }
        .onChange(of: webState.canGoBack) { _, _ in store.bind(webState: webState) }
        .onChange(of: webState.canGoForward) { _, _ in store.bind(webState: webState) }
        .onChange(of: webState.hasContent) { _, _ in store.bind(webState: webState) }
        .onChange(of: urlFieldFocused) { _, focused in
            if focused {
                if store.voiceSearchState == .recording {
                    voiceSearch.stop(insertTranscript: false)
                }
                store.urlBarText = webState.currentURL?.absoluteString ?? store.urlBarText
            }
        }
    }

    // MARK: - Top bar (Cancel · Browse & Capture · Capture)

    private var topBar: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("Browse & Capture")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.colors.textPrimary)
                if let title = store.currentTitle, !urlFieldFocused {
                    Text(title)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: capture) {
                HStack(spacing: 4) {
                    if store.isCapturing {
                        ProgressView().scaleEffect(0.6)
                    }
                    Text("Capture")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(store.hasContent && !store.isCapturing
                    ? theme.currentTheme.chrome.accent
                    : theme.colors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(store.isCapturing || !store.hasContent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - URL bar (back/forward · pill · reload-or-done)

    private var urlBar: some View {
        HStack(spacing: 8) {
            navIcon("chevron.left", enabled: store.canGoBack) { webState.goBack() }
            navIcon("chevron.right", enabled: store.canGoForward) { webState.goForward() }

            urlPill

            trailingControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func navIcon(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled
                    ? theme.currentTheme.chrome.accent
                    : theme.colors.textTertiary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var urlPill: some View {
        HStack(spacing: 6) {
            switch store.voiceSearchState {
            case .transcribing:
                ProgressView().scaleEffect(0.6)
            default:
                if store.isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            if store.voiceSearchState == .recording {
                Text(store.urlBarText.isEmpty ? "Listening…" : store.urlBarText)
                    .font(.system(size: 14))
                    .foregroundStyle(store.urlBarText.isEmpty
                        ? theme.colors.textTertiary
                        : theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            } else {
                TextField("Search or enter URL", text: $store.urlBarText)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($urlFieldFocused)
                    .onSubmit {
                        navigateTo(store.urlBarText)
                        urlFieldFocused = false
                    }
            }

            Button(action: toggleVoiceSearch) {
                Image(systemName: store.voiceSearchState == .recording ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(store.voiceSearchState == .recording ? .red : theme.colors.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(store.voiceSearchState == .transcribing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(store.voiceSearchState == .recording
                    ? Color.red.opacity(0.08)
                    : theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: store.voiceSearchState)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if store.voiceSearchState == .recording {
            Button("Stop") {
                voiceSearch.stop(insertTranscript: true)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
        } else if urlFieldFocused {
            Button("Done") { urlFieldFocused = false }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.currentTheme.chrome.accent)
        } else {
            Button(action: { webState.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - WKWebView

    private var webViewBody: some View {
        WebViewRepresentable(state: webState, initialURL: initialURL)
            .background(theme.colors.background)
            .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Autocomplete suggestions

    private var suggestionsOverlay: some View {
        let suggestions = store.suggestions(for: store.urlBarText)
        return VStack(spacing: 0) {
            if suggestions.isEmpty {
                emptyHint("No matches")
            } else {
                ForEach(suggestions) { entry in
                    suggestionRow(entry, icon: "clock.arrow.circlepath")
                }
            }
            Spacer()
        }
        .background(theme.colors.background)
    }

    // MARK: - History list

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("· HISTORY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text("\(store.history.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth),
                alignment: .bottom
            )

            if store.history.isEmpty {
                emptyHint("No history yet")
            } else {
                ForEach(store.history) { entry in
                    suggestionRow(entry, icon: "clock")
                }
            }
            Spacer()
        }
        .background(theme.colors.background)
    }

    private func suggestionRow(_ entry: WebCaptureBrowserStore.HistoryEntry, icon: String) -> some View {
        Button(action: {
            store.urlBarText = entry.url
            navigateTo(entry.url)
            urlFieldFocused = false
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    if let title = entry.title {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                    }
                    Text(entry.url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeSubtle)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
                .padding(.leading, 40),
            alignment: .bottom
        )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.colors.textTertiary)
            .padding(20)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions (stubs Codex wires)

    private func navigateTo(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let url: URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            url = URL(string: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: "https://" + trimmed)
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://www.google.com/search?q=\(encoded)")
        }

        if let url {
            webState.load(url)
            store.currentURL = url.absoluteString
            store.urlBarText = url.absoluteString
        }
    }

    private func toggleVoiceSearch() {
        if store.voiceSearchState == .recording {
            voiceSearch.stop(insertTranscript: true)
        } else {
            urlFieldFocused = false
            store.urlBarText = ""
            Task { await voiceSearch.start() }
        }
    }

    private func capture() {
        store.isCapturing = true

        webState.extractContent { result in
            store.isCapturing = false
            guard let result else { return }

            let sourceURL = result.url
            let host = URL(string: sourceURL)?.host
            let bookmark = CaptureBookmark(
                url: sourceURL,
                canonicalURL: sourceURL,
                host: host,
                title: result.title,
                siteName: host,
                sourceApplicationName: "Talkie Browser",
                sourceDevice: "iPhone",
                ingestionMethod: "web-browser"
            )

            let capture = Capture(
                sourceType: "url",
                text: result.text,
                title: result.title ?? host ?? "Bookmark",
                sourceURL: sourceURL,
                bookmark: bookmark
            )

            CaptureStore.shared.add(capture)
            CaptureSyncService.shared.syncIfConnected()
            AppShellRouter.shared.openCaptureDetail(captureID: capture.id.uuidString)
        }
    }

    private func wireVoiceSearch() {
        voiceSearch.onStateChange = { state in
            store.updateVoiceSearchState(state)
        }
        voiceSearch.onTranscript = { transcript in
            store.urlBarText = transcript
            navigateTo(transcript)
        }
        voiceSearch.onError = { error in
            store.voiceSearchError = error
        }
        store.updateVoiceSearchState(voiceSearch.currentState)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
