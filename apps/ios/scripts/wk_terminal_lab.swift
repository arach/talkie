import AppKit
import Foundation
import WebKit

final class TerminalLabDriver: NSObject, WKNavigationDelegate {
    private let htmlURL: URL
    private let replayURL: URL?
    private let application = NSApplication.shared
    private var window: NSWindow?
    private var webView: WKWebView?

    init(htmlURL: URL, replayURL: URL?) {
        self.htmlURL = htmlURL
        self.replayURL = replayURL
        super.init()
    }

    func run() {
        application.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 1100)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Talkie Terminal Glyph Lab"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.window = window
        self.webView = webView

        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        application.activate(ignoringOtherApps: true)
        application.run()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForReplayTarget(in: webView, attemptsRemaining: 60)
    }

    private func waitForReplayTarget(in webView: WKWebView, attemptsRemaining: Int) {
        let readinessScript = """
        (() => {
          if (window.talkieGlyphLab?.setChunkRecords || window.talkieGlyphLab?.setBytes || window.talkieGlyphLab?.setText) {
            return 'glyph-lab';
          }
          return '';
        })();
        """

        webView.evaluateJavaScript(readinessScript) { [weak self, weak webView] result, _ in
            guard let self, let webView else { return }
            let target = result as? String ?? ""

            if !target.isEmpty {
                self.injectReplayIfNeeded(into: webView)
                return
            }

            guard attemptsRemaining > 0 else {
                fputs("replay target never became ready\n", stderr)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.waitForReplayTarget(in: webView, attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    private func injectReplayIfNeeded(into webView: WKWebView) {
        guard let replayURL else { return }

        do {
            switch replayURL.pathExtension.lowercased() {
            case "json":
                let data = try Data(contentsOf: replayURL)
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard JSONSerialization.isValidJSONObject(object) else {
                    fputs("invalid chunk record json\n", stderr)
                    return
                }

                let literalData = try JSONSerialization.data(withJSONObject: object, options: [])
                guard let literal = String(data: literalData, encoding: .utf8) else {
                    fputs("failed to encode chunk record literal\n", stderr)
                    return
                }

                let script = "window.talkieGlyphLab?.setChunkRecords(\(literal));"
                webView.evaluateJavaScript(script)

            case "txt":
                let text = try String(contentsOf: replayURL, encoding: .utf8)
                let literalData = try JSONEncoder().encode(text)
                guard let literal = String(data: literalData, encoding: .utf8) else {
                    fputs("failed to encode text fixture literal\n", stderr)
                    return
                }

                let script = "window.talkieGlyphLab?.setText(\(literal));"
                webView.evaluateJavaScript(script)

            case "b64":
                let encoded = try String(contentsOf: replayURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let literalData = try JSONEncoder().encode(encoded)
                guard let literal = String(data: literalData, encoding: .utf8) else {
                    fputs("failed to encode base64 literal\n", stderr)
                    return
                }

                let script = "window.talkieGlyphLab?.setBytes(\(literal));"
                webView.evaluateJavaScript(script)

            default:
                let data = try Data(contentsOf: replayURL)
                let encoded = data.base64EncodedString()
                let literalData = try JSONEncoder().encode(encoded)
                guard let literal = String(data: literalData, encoding: .utf8) else {
                    fputs("failed to encode binary literal\n", stderr)
                    return
                }

                let script = "window.talkieGlyphLab?.setBytes(\(literal));"
                webView.evaluateJavaScript(script)
            }
        } catch {
            fputs("failed to load replay payload: \(error)\n", stderr)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("navigation failed: \(error)\n", stderr)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fputs("provisional navigation failed: \(error)\n", stderr)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else {
    fputs("usage: swift wk_terminal_lab.swift <html-file> [fixture.txt|fixture.b64|capture.bin|chunks.json]\n", stderr)
    exit(64)
}

let htmlURL = URL(fileURLWithPath: arguments[1])
let replayURL = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]) : nil
TerminalLabDriver(htmlURL: htmlURL, replayURL: replayURL).run()
