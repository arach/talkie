import AppKit
import Darwin
import Foundation
import WebKit

final class WindowSnapshotDriver: NSObject, WKNavigationDelegate {
    private let htmlURL: URL
    private let outputURL: URL
    private let replayURL: URL?
    private let application = NSApplication.shared
    private var window: NSWindow?
    private var webView: WKWebView?

    init(htmlURL: URL, outputURL: URL, replayURL: URL?) {
        self.htmlURL = htmlURL
        self.outputURL = outputURL
        self.replayURL = replayURL
        super.init()
    }

    func run() {
        application.setActivationPolicy(.prohibited)

        let configuration = WKWebViewConfiguration()
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 1100)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.webView = webView

        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        application.run()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForReplayTarget(in: webView, attemptsRemaining: 24)
    }

    private func waitForReplayTarget(in webView: WKWebView, attemptsRemaining: Int) {
        let readinessScript = """
        (() => {
          if (window.talkieGlyphLab?.setChunkRecords || window.talkieGlyphLab?.setBytes) {
            return 'glyph-lab';
          }
          if (window.talkieTerminal?.writeBytes || window.talkieTerminal?.resetBytes) {
            return 'live-terminal';
          }
          return '';
        })();
        """

        webView.evaluateJavaScript(readinessScript) { [weak self, weak webView] result, _ in
            guard let self, let webView else { return }
            let target = result as? String ?? ""

            if !target.isEmpty {
                self.injectReplayIfNeeded(into: webView)
                let delays: [TimeInterval] = [0.6, 1.2, 2.0]
                self.attemptSnapshot(after: delays, index: 0)
                return
            }

            guard attemptsRemaining > 0 else {
                fputs("replay target never became ready\n", stderr)
                self.application.terminate(nil)
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

                let script = """
                (() => {
                  const records = \(literal);
                  if (window.talkieGlyphLab?.setChunkRecords) {
                    window.talkieGlyphLab.setChunkRecords(records);
                    return 'glyph-lab chunk replay';
                  }
                  if (window.talkieTerminal?.clear && window.talkieTerminal?.writeBytes) {
                    window.talkieTerminal.clear();
                    for (const record of records) {
                      if (record?.data) {
                        window.talkieTerminal.writeBytes(record.data);
                      }
                    }
                    return 'live terminal chunk replay';
                  }
                  return 'no replay target';
                })();
                """
                webView.evaluateJavaScript(script)
            default:
                let data = try Data(contentsOf: replayURL)
                let encoded = data.base64EncodedString()
                let literalData = try JSONSerialization.data(withJSONObject: [encoded], options: [])
                guard let literalArray = String(data: literalData, encoding: .utf8),
                      literalArray.count >= 2 else {
                    fputs("failed to encode transcript literal\n", stderr)
                    return
                }

                let literal = String(literalArray.dropFirst().dropLast())
                let script = """
                (() => {
                  const payload = \(literal);
                  if (window.talkieGlyphLab?.setBytes) {
                    window.talkieGlyphLab.setBytes(payload);
                    return 'glyph-lab flat replay';
                  }
                  if (window.talkieTerminal?.resetBytes) {
                    window.talkieTerminal.resetBytes(payload);
                    return 'live terminal flat replay';
                  }
                  return 'no replay target';
                })();
                """
                webView.evaluateJavaScript(script)
            }
        } catch {
            fputs("failed to load replay payload: \(error)\n", stderr)
        }
    }

    private func attemptSnapshot(after delays: [TimeInterval], index: Int) {
        guard index < delays.count else {
            fputs("failed to capture window snapshot\n", stderr)
            application.terminate(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) { [weak self] in
            guard let self, let window, let contentView = window.contentView else { return }

            contentView.layoutSubtreeIfNeeded()
            let bounds = contentView.bounds

            guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
                self.attemptSnapshot(after: delays, index: index + 1)
                return
            }

            contentView.cacheDisplay(in: bounds, to: rep)

            guard let png = rep.representation(using: .png, properties: [:]) else {
                self.attemptSnapshot(after: delays, index: index + 1)
                return
            }

            do {
                try png.write(to: self.outputURL)
                fputs("\(self.outputURL.path)\n", stdout)
                self.application.terminate(nil)
            } catch {
                fputs("failed to write snapshot: \(error)\n", stderr)
                self.application.terminate(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("navigation failed: \(error)\n", stderr)
        application.terminate(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fputs("provisional navigation failed: \(error)\n", stderr)
        application.terminate(nil)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    fputs("usage: swift wk_terminal_replay.swift <html-file> <output-png> [transcript-bin|chunks-json]\n", stderr)
    exit(64)
}

let htmlURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let replayURL = arguments.count == 4 ? URL(fileURLWithPath: arguments[3]) : nil
WindowSnapshotDriver(htmlURL: htmlURL, outputURL: outputURL, replayURL: replayURL).run()
