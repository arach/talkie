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

    enum VoiceSearchState { case idle, recording, transcribing }

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let url: String
        let title: String?
        let lastVisited: Date
    }

    init() {
        // Codex wires the live WebViewState + BrowseHistory store.
        // Mocks for paint:
        self.currentURL = "https://arxiv.org/abs/2403.09919"
        self.currentTitle = "Speculative decoding for long context"
        self.canGoBack = true
        self.hasContent = true
        self.history = [
            HistoryEntry(url: "https://news.ycombinator.com",        title: "Hacker News",        lastVisited: Date().addingTimeInterval(-3600)),
            HistoryEntry(url: "https://linear.app/team/issue/INF-412", title: "INF-412 · Linear", lastVisited: Date().addingTimeInterval(-7200)),
            HistoryEntry(url: "https://arxiv.org/abs/2403.09919",   title: "Speculative decoding for long context", lastVisited: Date().addingTimeInterval(-86400)),
        ]
    }

    func suggestions(for query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return history.filter { $0.url.lowercased().contains(q) || ($0.title ?? "").lowercased().contains(q) }
    }
}

struct WebCaptureBrowserNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = WebCaptureBrowserStore()
    @FocusState private var urlFieldFocused: Bool

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
            store.urlBarText = store.currentURL ?? ""
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
            navIcon("chevron.left", enabled: store.canGoBack) { /* TODO M3+: store.goBack() */ }
            navIcon("chevron.right", enabled: store.canGoForward) { /* TODO M3+: store.goForward() */ }

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
                // TODO M3+: voiceSearch.stop(insertTranscript: true)
                store.voiceSearchState = .idle
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
        } else if urlFieldFocused {
            Button("Done") { urlFieldFocused = false }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.currentTheme.chrome.accent)
        } else {
            Button(action: { /* TODO M3+: store.reload() */ }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - WKWebView placeholder

    private var webViewBody: some View {
        ZStack {
            theme.colors.background
            // TODO M3+: WebViewRepresentable(state: ..., initialURL: ...)
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("· WKWebView slot")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("Wired in M3 — paint frame only for now")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary.opacity(0.7))
            }
        }
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
        // TODO M3+: parse + WebViewState.load(URL(...)).
        store.currentURL = urlString
        store.urlBarText = urlString
    }

    private func toggleVoiceSearch() {
        // TODO M3+: bind to the InlineDictationController used by
        // the donor (voiceSearch instance). For now flip the state
        // so the visual transitions are observable.
        switch store.voiceSearchState {
        case .idle:        store.voiceSearchState = .recording
        case .recording:   store.voiceSearchState = .transcribing
        case .transcribing: store.voiceSearchState = .idle
        }
    }

    private func capture() {
        // TODO M3+: capture flow against CaptureStore + bookmark
        // metadata extraction.
        store.isCapturing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            store.isCapturing = false
            AppShellRouter.shared.openHome()
        }
    }
}
