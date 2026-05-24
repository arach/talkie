//
//  LearnKnowledgeWebView.swift
//  Talkie macOS
//
//  WKWebView wrapper for Learn KB articles. The web view renders local
//  article content; navigation and app actions are handed back to Swift.
//

import AppKit
import SwiftUI
import TalkieKit
import WebKit

private let learnWebLog = Log(.ui)

struct LearnKnowledgeWebView: NSViewRepresentable {
    let article: LearnArticle
    let colorScheme: ColorScheme
    let onBridgeAction: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBridgeAction: onBridgeAction)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        #if DEBUG
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let contentController = configuration.userContentController
        contentController.addUserScript(themeScript(for: colorScheme))
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.currentArticleID = article.id
        load(article, in: webView, colorScheme: colorScheme)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onBridgeAction = onBridgeAction

        let theme = themeName(for: colorScheme)
        webView.evaluateJavaScript("document.documentElement.dataset.theme = '\(theme)'")

        guard context.coordinator.currentArticleID != article.id else { return }
        context.coordinator.currentArticleID = article.id
        load(article, in: webView, colorScheme: colorScheme)
    }

    private func load(_ article: LearnArticle, in webView: WKWebView, colorScheme: ColorScheme) {
        if let fileURL = article.fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(article.htmlDocument(theme: themeName(for: colorScheme)), baseURL: Bundle.main.resourceURL)
        }
    }

    private func themeName(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "midnight" : "scope"
    }

    private func themeScript(for colorScheme: ColorScheme) -> WKUserScript {
        WKUserScript(
            source: "document.documentElement.dataset.theme = '\(themeName(for: colorScheme))';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentArticleID: String?
        var onBridgeAction: (URL) -> Void

        init(onBridgeAction: @escaping (URL) -> Void) {
            self.onBridgeAction = onBridgeAction
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == TalkieEnvironment.current.talkieURLScheme || url.scheme == "talkie" {
                onBridgeAction(url)
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            learnWebLog.warning("Learn article navigation failed: \(error.localizedDescription)")
        }
    }
}

private extension LearnArticle {
    func htmlDocument(theme: String) -> String {
        """
        <!doctype html>
        <html data-theme="\(theme)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>\(LearnArticleHTML.css)</style>
        </head>
        <body>
          <main class="article-shell">
            <section class="hero">
              <div class="eyebrow">\(eyebrow.htmlEscaped)</div>
              <h1>\(title.htmlEscaped)</h1>
              <p class="summary">\(summary.htmlEscaped)</p>
            </section>
            \(metadataHTML)
            \(articleBodyHTML)
            \(shortcutHTML)
            <section class="callout">
              <div class="callout-kicker">NOTE</div>
              <h2>\(fallback.calloutTitle.htmlEscaped)</h2>
              <p>\(fallback.calloutBody.htmlEscaped)</p>
            </section>
            \(stepsHTML)
            \(actionsHTML)
            \(tagsHTML)
          </main>
        </body>
        </html>
        """
    }

    private var articleBodyHTML: String {
        if let bodyMarkdown, !bodyMarkdown.isEmpty {
            return "<section class=\"article-body\">\(LearnMarkdownRenderer.html(from: bodyMarkdown))</section>"
        }
        return "<p class=\"lead\">\(fallback.lead.htmlEscaped)</p>"
    }

    private var metadataHTML: String {
        guard !fallback.metadata.isEmpty else { return "" }
        let rows = fallback.metadata.map { item in
            """
            <div class="ledger-row">
              <span>\(item.label.htmlEscaped)</span>
              <strong>\(item.value.htmlEscaped)</strong>
            </div>
            """
        }.joined()
        return "<section class=\"ledger\">\(rows)</section>"
    }

    private var shortcutHTML: String {
        guard !shortcuts.isEmpty else { return "" }
        let rows = shortcuts.map { shortcut in
            """
            <div class="shortcut-row">
              <kbd>\(shortcut.keys.htmlEscaped)</kbd>
              <span>\(shortcut.label.htmlEscaped)</span>
            </div>
            """
        }.joined()
        return """
        <section class="block">
          <div class="block-title">Shortcuts</div>
          <div class="shortcut-strip">\(rows)</div>
        </section>
        """
    }

    private var stepsHTML: String {
        guard !fallback.steps.isEmpty else { return "" }
        let items = fallback.steps.enumerated().map { index, step in
            """
            <li>
              <span class="step-index">\(index + 1)</span>
              <span>\(step.htmlEscaped)</span>
            </li>
            """
        }.joined()
        return """
        <section class="block">
          <div class="block-title">How it works</div>
          <ol class="steps">\(items)</ol>
        </section>
        """
    }

    private var actionsHTML: String {
        guard !actions.isEmpty else { return "" }
        let rows = actions.map { action in
            """
            <a class="action-row" href="\(action.url.htmlAttributeEscaped)">
              <span>
                <strong>\(action.title.htmlEscaped)</strong>
                <em>\(action.detail.htmlEscaped)</em>
              </span>
              <b>OPEN</b>
            </a>
            """
        }.joined()
        return """
        <section class="block">
          <div class="block-title">Open in Talkie</div>
          <div class="actions">\(rows)</div>
        </section>
        """
    }

    private var tagsHTML: String {
        guard !tags.isEmpty else { return "" }
        return """
        <footer class="tags">
          \(tags.map { "<span>\($0.htmlEscaped)</span>" }.joined())
        </footer>
        """
    }
}

private enum LearnArticleHTML {
    static let css = """
    :root {
      color-scheme: light dark;
      --canvas: #F8F8F7;
      --paper: rgba(255,255,255,0.54);
      --paper-strong: rgba(255,255,255,0.76);
      --ink: #0F1112;
      --ink-muted: #4D5256;
      --ink-faint: #737878;
      --ink-subtle: #9A9E9E;
      --edge: rgba(15,17,18,0.16);
      --edge-strong: rgba(15,17,18,0.24);
      --amber: #C47D1C;
      --amber-deep: #7A521A;
      --amber-faint: rgba(196,125,28,0.08);
      --shadow: 0 18px 38px -34px rgba(0,0,0,0.38);
    }
    :root[data-theme="midnight"] {
      --canvas: #0A0A0A;
      --paper: rgba(255,255,255,0.035);
      --paper-strong: rgba(255,255,255,0.06);
      --ink: #FAFAFA;
      --ink-muted: #B8B8B8;
      --ink-faint: #8D8D8D;
      --ink-subtle: #686868;
      --edge: rgba(250,250,250,0.14);
      --edge-strong: rgba(250,250,250,0.26);
      --amber: #0084FF;
      --amber-deep: #66B7FF;
      --amber-faint: rgba(0,132,255,0.10);
      --shadow: none;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      min-height: 100%;
      background: transparent;
      color: var(--ink);
      font-family: Inter, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    body {
      padding: 0;
      user-select: text;
    }
    .article-shell {
      width: min(100%, 780px);
      margin: 0 auto;
      padding: 30px 34px 34px;
    }
    .hero {
      border-bottom: 1px solid var(--edge-strong);
      padding-bottom: 22px;
    }
    .eyebrow, .block-title, .callout-kicker {
      color: var(--amber);
      font: 700 10px/1 "JetBrains Mono", ui-monospace, "SF Mono", monospace;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    h1 {
      margin: 10px 0 0;
      font-family: "Cormorant Garamond", "Iowan Old Style", Georgia, serif;
      font-size: 58px;
      font-weight: 500;
      line-height: 0.92;
      letter-spacing: 0;
    }
    @media (max-width: 620px) {
      h1 { font-size: 42px; }
      .article-shell { padding: 24px 22px 30px; }
    }
    .summary {
      max-width: 620px;
      margin: 16px 0 0;
      color: var(--ink-muted);
      font-size: 14px;
      line-height: 1.65;
    }
    .lead {
      margin: 28px 0;
      color: var(--ink);
      font-size: 15px;
      line-height: 1.74;
    }
    .ledger {
      margin-top: 18px;
      border: 1px solid var(--edge);
      background: var(--paper);
      box-shadow: var(--shadow);
    }
    .ledger-row {
      display: grid;
      grid-template-columns: minmax(120px, 0.36fr) 1fr;
      gap: 20px;
      min-height: 38px;
      align-items: center;
      border-top: 1px solid var(--edge);
      padding: 0 14px;
    }
    .ledger-row:first-child { border-top: 0; }
    .ledger-row span, .shortcut-row span, .action-row b {
      color: var(--ink-faint);
      font: 700 9px/1.3 "JetBrains Mono", ui-monospace, "SF Mono", monospace;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    .ledger-row strong {
      color: var(--ink);
      font-size: 12px;
      font-weight: 500;
    }
    .block {
      margin-top: 30px;
    }
    .shortcut-strip {
      display: grid;
      gap: 8px;
      margin-top: 12px;
    }
    .shortcut-row {
      display: flex;
      align-items: center;
      gap: 14px;
      border-top: 1px solid var(--edge);
      padding: 12px 0;
    }
    kbd {
      min-width: 96px;
      border: 1px solid var(--edge-strong);
      background: var(--paper-strong);
      color: var(--ink);
      padding: 6px 9px;
      font: 700 11px/1 "JetBrains Mono", ui-monospace, "SF Mono", monospace;
      letter-spacing: 0;
      text-align: center;
    }
    .article-body {
      margin-top: 26px;
      color: var(--ink-muted);
      font-size: 14px;
      line-height: 1.72;
    }
    .article-body h2,
    .article-body h3 {
      margin: 28px 0 10px;
      color: var(--ink);
      font-weight: 650;
      line-height: 1.2;
      letter-spacing: 0;
    }
    .article-body h2 { font-size: 20px; }
    .article-body h3 { font-size: 16px; }
    .article-body p {
      margin: 0 0 14px;
    }
    .article-body ul {
      margin: 12px 0 16px;
      padding: 0;
      list-style: none;
      border-top: 1px solid var(--edge);
    }
    .article-body li {
      position: relative;
      border-bottom: 1px solid var(--edge);
      padding: 10px 0 10px 18px;
    }
    .article-body li::before {
      content: "";
      position: absolute;
      left: 0;
      top: 18px;
      width: 5px;
      height: 5px;
      border: 1px solid var(--amber);
      border-radius: 50%;
    }
    .article-body strong {
      color: var(--ink);
      font-weight: 650;
    }
    .callout {
      margin-top: 30px;
      border-left: 2px solid var(--amber);
      background: var(--amber-faint);
      padding: 16px 18px;
    }
    .callout h2 {
      margin: 8px 0 6px;
      font: 600 18px/1.2 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    .callout p {
      margin: 0;
      color: var(--ink-muted);
      font-size: 13px;
      line-height: 1.62;
    }
    .steps {
      margin: 12px 0 0;
      padding: 0;
      list-style: none;
      border-top: 1px solid var(--edge);
    }
    .steps li {
      display: grid;
      grid-template-columns: 34px 1fr;
      gap: 12px;
      border-bottom: 1px solid var(--edge);
      padding: 14px 0;
      color: var(--ink-muted);
      font-size: 13px;
      line-height: 1.55;
    }
    .step-index {
      color: var(--amber);
      font: 700 10px/1.5 "JetBrains Mono", ui-monospace, "SF Mono", monospace;
      letter-spacing: 0;
    }
    .actions {
      margin-top: 12px;
      border: 1px solid var(--edge);
      background: var(--paper);
    }
    .action-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 20px;
      min-height: 58px;
      border-top: 1px solid var(--edge);
      padding: 12px 14px;
      color: inherit;
      text-decoration: none;
    }
    .action-row:first-child { border-top: 0; }
    .action-row:hover {
      background: var(--amber-faint);
    }
    .action-row strong {
      display: block;
      color: var(--ink);
      font-size: 13px;
      font-weight: 650;
    }
    .action-row em {
      display: block;
      margin-top: 4px;
      color: var(--ink-faint);
      font-size: 11px;
      font-style: normal;
      line-height: 1.4;
    }
    .action-row b {
      color: var(--amber);
    }
    .tags {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 26px;
      padding-top: 16px;
      border-top: 1px solid var(--edge);
    }
    .tags span {
      border: 1px solid var(--edge);
      color: var(--ink-faint);
      padding: 5px 7px;
      font: 700 9px/1 "JetBrains Mono", ui-monospace, "SF Mono", monospace;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    """
}

private enum LearnMarkdownRenderer {
    static func html(from markdown: String) -> String {
        var html = ""
        var paragraphLines: [String] = []
        var isListOpen = false

        func closeParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.joined(separator: " ")
            html += "<p>\(inlineHTML(paragraph))</p>"
            paragraphLines.removeAll()
        }

        func closeList() {
            guard isListOpen else { return }
            html += "</ul>"
            isListOpen = false
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                closeParagraph()
                closeList()
                continue
            }

            if line.hasPrefix("### ") {
                closeParagraph()
                closeList()
                html += "<h3>\(line.dropFirst(4).description.htmlEscaped)</h3>"
            } else if line.hasPrefix("## ") {
                closeParagraph()
                closeList()
                html += "<h2>\(line.dropFirst(3).description.htmlEscaped)</h2>"
            } else if line.hasPrefix("- ") {
                closeParagraph()
                if !isListOpen {
                    html += "<ul>"
                    isListOpen = true
                }
                html += "<li>\(inlineHTML(String(line.dropFirst(2))))</li>"
            } else {
                paragraphLines.append(line)
            }
        }

        closeParagraph()
        closeList()
        return html
    }

    private static func inlineHTML(_ text: String) -> String {
        var result = ""
        var remainder = text[...]
        var isStrong = false

        while let range = remainder.range(of: "**") {
            result += remainder[..<range.lowerBound].description.htmlEscaped
            result += isStrong ? "</strong>" : "<strong>"
            isStrong.toggle()
            remainder = remainder[range.upperBound...]
        }

        result += remainder.description.htmlEscaped
        if isStrong {
            result += "</strong>"
        }
        return result
    }
}

private extension String {
    var htmlEscaped: String {
        replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
            .replacing("'", with: "&#39;")
    }

    var htmlAttributeEscaped: String {
        htmlEscaped.replacing("\n", with: " ")
    }
}
