//
//  WebCaptureBrowser.swift
//  Talkie iOS
//
//  Mini in-app browser for capturing web page content.
//  Tracks its own browsing history (WKWebView doesn't share Safari's).
//  Autocompletes from Talkie history in the URL bar.
//

import SwiftUI
import WebKit

/// Result returned when the user captures a web page
struct WebCaptureResult {
    let url: String
    let title: String?
    let text: String
}

struct WebCaptureBrowser: View {
    /// Optional URL to load immediately on open
    var initialURL: URL?
    var onCapture: (WebCaptureResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var webState = WebViewState()
    @ObservedObject private var history = BrowseHistory.shared
    @State private var urlBarText = ""
    @State private var isCapturing = false
    @State private var isUrlBarFocused = false
    @State private var showingHistory = false
    @State private var voiceSearchState: InlineDictationController.State = .idle
    @State private var voiceSearchError: String?
    @FocusState private var urlFieldFocused: Bool

    private let voiceSearch = InlineDictationController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL bar + navigation
                urlBar

                // Autocomplete suggestions overlay
                if isUrlBarFocused && !urlBarText.isEmpty {
                    let suggestions = history.suggestions(for: urlBarText)
                    if !suggestions.isEmpty {
                        suggestionsOverlay(suggestions)
                    }
                }

                // History view when URL bar focused and empty
                if isUrlBarFocused && urlBarText.isEmpty {
                    historyList
                } else {
                    // Web view
                    WebViewRepresentable(state: webState, initialURL: initialURL)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Browse & Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        captureCurrentPage()
                    } label: {
                        HStack(spacing: 4) {
                            if isCapturing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Capture")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isCapturing || !webState.hasContent)
                }
            }
            .onChange(of: webState.currentURL) { _, url in
                if !isUrlBarFocused && voiceSearchState == .idle {
                    urlBarText = url?.absoluteString ?? ""
                }
            }
            .onChange(of: webState.currentTitle) { _, title in
                // Record to history when page finishes loading
                if let url = webState.currentURL?.absoluteString {
                    history.record(url: url, title: title)
                }
            }
            .onChange(of: urlFieldFocused) { _, focused in
                isUrlBarFocused = focused
                if focused {
                    // Stop voice search if URL bar gets keyboard focus
                    if voiceSearchState == .recording { voiceSearch.stop(insertTranscript: false) }
                    // Select all text when focusing URL bar
                    urlBarText = webState.currentURL?.absoluteString ?? urlBarText
                }
            }
            .onAppear {
                voiceSearch.onStateChange = { state in
                    voiceSearchState = state
                }
                voiceSearch.onTranscript = { transcript in
                    urlBarText = transcript
                    navigateTo(transcript)
                }
                voiceSearch.onError = { error in
                    voiceSearchError = error
                }
            }
        }
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            // Back
            Button {
                webState.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(webState.canGoBack ? Color.accentColor : Color.textTertiary)
            }
            .disabled(!webState.canGoBack)
            .buttonStyle(.plain)

            // Forward
            Button {
                webState.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(webState.canGoForward ? Color.accentColor : Color.textTertiary)
            }
            .disabled(!webState.canGoForward)
            .buttonStyle(.plain)

            // URL text field
            HStack(spacing: 6) {
                if voiceSearchState == .transcribing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if webState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }

                if voiceSearchState == .recording {
                    Text(urlBarText.isEmpty ? "Listening..." : urlBarText)
                        .font(.system(size: 14))
                        .foregroundStyle(urlBarText.isEmpty ? Color.textTertiary : Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                } else {
                    TextField("Search or enter URL", text: $urlBarText)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .focused($urlFieldFocused)
                        .onSubmit {
                            navigateTo(urlBarText)
                            urlFieldFocused = false
                        }
                }

                // Mic button
                Button {
                    toggleVoiceSearch()
                } label: {
                    Image(systemName: voiceSearchState == .recording ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(voiceSearchState == .recording ? Color.recording : Color.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(voiceSearchState == .transcribing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(voiceSearchState == .recording ? Color.recording.opacity(0.08) : Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.2), value: voiceSearchState)

            // History / Reload / Done toggle
            if voiceSearchState == .recording {
                Button("Stop") {
                    voiceSearch.stop(insertTranscript: true)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.recording)
            } else if isUrlBarFocused {
                Button("Done") {
                    urlFieldFocused = false
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            } else {
                Button {
                    webState.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surfacePrimary)
    }

    // MARK: - Autocomplete Suggestions

    private func suggestionsOverlay(_ suggestions: [BrowseHistoryEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { entry in
                Button {
                    urlBarText = entry.url
                    navigateTo(entry.url)
                    urlFieldFocused = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            if let title = entry.title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            }
                            Text(entry.domain ?? entry.url)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Populate URL bar with this suggestion
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 44)
            }
        }
        .background(Color.surfacePrimary)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if history.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                        Text("No browsing history yet")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    HStack {
                        TalkieEyebrow(text: "Recent")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    ForEach(history.recentEntries()) { entry in
                        Button {
                            urlBarText = entry.url
                            navigateTo(entry.url)
                            urlFieldFocused = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textTertiary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title ?? entry.domain ?? entry.url)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)

                                    Text(entry.domain ?? entry.url)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(relativeTime(entry.visitedAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .background(Color.surfacePrimary)
    }

    // MARK: - Navigation

    private func navigateTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
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
        }
    }

    // MARK: - Voice Search

    private func toggleVoiceSearch() {
        if voiceSearchState == .recording {
            voiceSearch.stop(insertTranscript: true)
        } else {
            urlFieldFocused = false
            urlBarText = ""
            Task { await voiceSearch.start() }
        }
    }

    // MARK: - Capture

    private func captureCurrentPage() {
        isCapturing = true

        webState.extractContent { result in
            isCapturing = false

            guard let result else { return }
            onCapture(result)
            dismiss()
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - WebView State

@MainActor
class WebViewState: ObservableObject {
    @Published var currentURL: URL?
    @Published var currentTitle: String?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var hasContent = false

    weak var webView: WKWebView?

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func extractContent(completion: @escaping (WebCaptureResult?) -> Void) {
        guard let webView else {
            completion(nil)
            return
        }

        let js = """
        (function() {
            var article = document.querySelector('article');
            var main = document.querySelector('main');
            var target = article || main || document.body;

            var clone = target.cloneNode(true);
            var remove = clone.querySelectorAll('script, style, nav, footer, header, .ad, .ads, [role="navigation"], [role="banner"], [role="contentinfo"]');
            remove.forEach(function(el) { el.remove(); });

            return {
                text: clone.innerText.trim(),
                title: document.title
            };
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            Task { @MainActor in
                guard let dict = result as? [String: Any],
                      let text = dict["text"] as? String,
                      !text.isEmpty else {
                    completion(nil)
                    return
                }

                let title = dict["title"] as? String
                let url = self?.currentURL?.absoluteString ?? ""

                completion(WebCaptureResult(
                    url: url,
                    title: title,
                    text: text
                ))
            }
        }
    }
}

// MARK: - WKWebView Representable

struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: WebViewState
    var initialURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Use default data store so cookies persist between sessions
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        state.webView = webView

        let startURL = initialURL ?? URL(string: "https://www.google.com")!
        webView.load(URLRequest(url: startURL))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let state: WebViewState

        init(state: WebViewState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = true
                state.currentURL = webView.url
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = false
                state.currentURL = webView.url
                state.currentTitle = webView.title
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                state.hasContent = webView.url != nil
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }
    }
}
