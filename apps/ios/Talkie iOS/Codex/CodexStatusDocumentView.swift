import SwiftUI
import UIKit
import WebKit

/// Native trust/loading shell around a host-rendered, read-only technical document.
struct CodexStatusDocumentView: View {
    @ObservedObject private var theme = ThemeManager.shared
    let taskID: String
    let jobID: String?

    @State private var document: String?
    @State private var isLoading = false
    @State private var loadFailure: String?
    @Environment(\.colorScheme) private var colorScheme

    private var requestIdentity: String { "\(taskID):\(jobID ?? "latest")" }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            if let document {
                VStack(spacing: 0) {
                    if let loadFailure {
                        connectionBanner(loadFailure)
                    }
                    CodexStatusWebView(
                        document: document,
                        palette: statusPalette
                    ) {
                        Task { await loadStatus(resetDocument: false) }
                    }
                }
            } else if let loadFailure, !isLoading {
                failureView(loadFailure)
            } else {
                loadingView
            }
        }
        .task(id: requestIdentity) {
            await loadStatus(resetDocument: true)
        }
    }

    private var statusPalette: CodexStatusPalette {
        CodexStatusPalette(
            background: cssColor(theme.colors.background),
            raised: cssColor(theme.colors.cardBackground),
            ink: cssColor(theme.colors.textPrimary),
            secondary: cssColor(theme.colors.textSecondary),
            faint: cssColor(theme.colors.textTertiary),
            rule: cssColor(theme.chrome.edgeFaint),
            ruleStrong: cssColor(theme.chrome.edge),
            accent: cssColor(theme.chrome.accent),
            success: cssColor(theme.chrome.accent),
            failure: cssColor(Color(red: 0.92, green: 0.42, blue: 0.30))
        )
    }

    private func cssColor(_ color: Color) -> String {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            resolved.getWhite(&white, alpha: &alpha)
            red = white
            green = white
            blue = white
        }
        return "#\(hex(red))\(hex(green))\(hex(blue))\(hex(alpha))"
    }

    private func hex(_ component: CGFloat) -> String {
        let integer = Int((min(max(component, 0), 1) * 255).rounded())
        let value = String(integer, radix: 16, uppercase: true)
        return value.count == 1 ? "0\(value)" : value
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CODEX / TASK STATUS")
                Spacer()
                Text("READING HOST")
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.chrome.accent)
            .padding(.bottom, 18)

            ForEach(0..<7, id: \.self) { index in
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.colors.textTertiary.opacity(0.18))
                        .frame(width: index.isMultiple(of: 2) ? 72 : 104, height: 8)
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.colors.textSecondary.opacity(0.14))
                        .frame(width: index.isMultiple(of: 3) ? 92 : 142, height: 9)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.colors.textTertiary.opacity(0.18))
                        .frame(height: 0.5)
                }
            }
            Spacer()
        }
        .padding(22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Codex task status")
    }

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOST STATUS UNAVAILABLE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(failureColor)
            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await loadStatus(resetDocument: true) }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private func connectionBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text("Showing the last host document. \(message)")
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(failureColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(failureColor.opacity(0.08))
    }

    private var failureColor: Color {
        Color(red: 0.92, green: 0.42, blue: 0.30)
    }

    private func loadStatus(resetDocument: Bool) async {
        if resetDocument { document = nil }
        isLoading = true
        loadFailure = nil
        defer { isLoading = false }
        do {
            document = try await BridgeManager.shared.codexStatusDocument(
                taskId: taskID,
                jobId: jobID
            )
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}

/// Displays only HTML already authenticated and decrypted by BridgeClient.
private struct CodexStatusWebView: UIViewRepresentable {
    let document: String
    let palette: CodexStatusPalette
    let onRefresh: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsLinkPreview = false

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .secondaryLabel
        refreshControl.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.parent.onRefresh()
        }, for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        context.coordinator.load(document, palette: palette, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(document, palette: palette, into: webView)
        webView.scrollView.refreshControl?.endRefreshing()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CodexStatusWebView
        private var loadedDocument: String?

        init(parent: CodexStatusWebView) {
            self.parent = parent
        }

        func load(_ document: String, palette: CodexStatusPalette, into webView: WKWebView) {
            let themedDocument = palette.applying(to: document)
            guard loadedDocument != themedDocument else { return }
            loadedDocument = themedDocument
            webView.loadHTMLString(themedDocument, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let isDocumentLoad = navigationAction.navigationType == .other
                && (navigationAction.request.url == nil || navigationAction.request.url?.absoluteString == "about:blank")
            decisionHandler(isDocumentLoad ? .allow : .cancel)
        }
    }
}

private struct CodexStatusPalette: Equatable {
    let background: String
    let raised: String
    let ink: String
    let secondary: String
    let faint: String
    let rule: String
    let ruleStrong: String
    let accent: String
    let success: String
    let failure: String

    func applying(to document: String) -> String {
        let style = """
        <style id="talkie-phone-theme">
        :root {
          --bg: \(background);
          --raised: \(raised);
          --ink: \(ink);
          --secondary: \(secondary);
          --faint: \(faint);
          --rule: \(rule);
          --rule-strong: \(ruleStrong);
          --accent: \(accent);
          --success: \(success);
          --red: \(failure);
        }
        </style>
        """
        guard let headEnd = document.range(of: "</head>", options: .caseInsensitive) else {
            return style + document
        }
        var themed = document
        themed.insert(contentsOf: style, at: headEnd.lowerBound)
        return themed
    }
}
