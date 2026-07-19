//
//  TalkieMarkdownStudioWebView.swift
//  TalkieKit
//
//  The "Talkie Markdown" editor surface: a WKWebView that loads the
//  MarkdownStudio web bundle (toolbar + Split/Preview/Source + revisions +
//  dictation HUD). It reuses the shipped ComposeWebEditor CodeMirror core for
//  the source pane; this host owns document persistence and the extended
//  `talkieEditor` bridge (change → autosave + live preview, saveVersion,
//  restore).
//

#if os(macOS)
import AppKit
import SwiftUI
import WebKit

public struct MarkdownStudioView: View {
    private let dictation: MarkdownStudioDictating?

    public init(dictation: MarkdownStudioDictating? = nil) {
        self.dictation = dictation
    }

    public var body: some View {
        TalkieMarkdownStudioWebView(dictation: dictation)
            .background(Color(red: 0.957, green: 0.945, blue: 0.914)) // --canvas, avoids white flash pre-load
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class MarkdownStudioEditingWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.rightMouseDown(with: event) }
}

public struct TalkieMarkdownStudioWebView: NSViewRepresentable {
    private let dictation: MarkdownStudioDictating?

    public init(dictation: MarkdownStudioDictating? = nil) {
        self.dictation = dictation
    }

    public func makeCoordinator() -> Coordinator { Coordinator(dictation: dictation) }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

        let webView = MarkdownStudioEditingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.attach(webView)

        if let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "MarkdownStudio") {
            // Read access to the resources root so ../ComposeWebEditor/editor.js and ../Fonts resolve.
            let root = indexURL.deletingLastPathComponent().deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: root)
        } else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {}

    public static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "talkieEditor"

        private let store = MarkdownStudioDocumentStore()
        private let dictation: MarkdownStudioDictating?
        private weak var webView: WKWebView?
        private var isReady = false
        private var lastForwarded = ""

        // Dictation lifecycle
        private enum DictationMode: String { case prose, block }
        private var isDictating = false
        private var dictationMode: DictationMode = .prose
        private var dictationStart: Date?
        private var dictationElapsed: TimeInterval = 0
        private var levelTimer: Timer?

        init(dictation: MarkdownStudioDictating?) {
            self.dictation = dictation
            super.init()
        }

        func attach(_ webView: WKWebView) { self.webView = webView }

        func teardown(webView: WKWebView) {
            levelTimer?.invalidate()
            levelTimer = nil
            if isDictating { dictation?.cancel(); isDictating = false }
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
            self.webView = nil
            isReady = false
        }

        public nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // WebKit delivers on the main thread; hop before touching the
            // main-actor-isolated message payload.
            MainActor.assumeIsolated {
                guard let body = message.body as? [String: Any],
                      let type = body["type"] as? String else { return }
                self.handle(type: type, body: body)
            }
        }

        private func handle(type: String, body: [String: Any]) {
            switch type {
            case "ready":
                store.load()
                isReady = true
                evaluate("window.TalkieEditor?.configure({accentColor:'#c47d1c',textColor:'#4a3f31',fontSize:13,lineHeight:1.92});")
                evaluate("window.TalkieStudio?.setDocTitle(\(jsLiteral(store.title)));")
                evaluate("window.TalkieStudio?.setDictationAvailable(\(dictation != nil ? "true" : "false"));")
                pushRevisions()
                // Leave lastForwarded empty so the change echoed by setText is
                // forwarded to the preview, rendering first paint deterministically.
                evaluate("window.TalkieEditor?.setText(\(jsLiteral(store.text)));")

            case "change":
                guard let text = body["text"] as? String else { return }
                store.updateText(text) { [weak self] in self?.evaluate("window.TalkieStudio?.setSaved(true);") }
                if text != lastForwarded {
                    lastForwarded = text
                    evaluate("window.TalkieStudio?.onText(\(jsLiteral(text)));")
                }

            case "saveVersion":
                let reason = (body["reason"] as? String) ?? "manual"
                store.saveVersion(reason: reason)
                pushRevisions()
                evaluate("window.TalkieStudio?.setSaved(true);")

            case "restore":
                guard let id = body["id"] as? String, let restored = store.restore(id: id) else { return }
                lastForwarded = restored
                evaluate("window.TalkieEditor?.setText(\(jsLiteral(restored)));")
                pushRevisions()

            case "dictate":
                let mode = DictationMode(rawValue: (body["mode"] as? String) ?? "prose") ?? .prose
                startDictation(mode: mode)

            case "dictateStop":
                stopDictation()

            case "dictateCancel":
                cancelDictation()

            case "compare":
                guard let from = body["from"] as? String, let to = body["to"] as? String else { return }
                if let payload = store.comparePayload(fromId: from, toId: to) {
                    evaluate("window.TalkieStudio?.setCompare(\(jsonObject(payload)));")
                }

            case "focus":
                webView?.window?.makeFirstResponder(webView)

            default:
                break
            }
        }

        // MARK: - Dictation (record → transcribe → insert)

        private func startDictation(mode: DictationMode) {
            guard let dictation, !isDictating else { return }
            isDictating = true
            dictationMode = mode
            setDictationState("starting", mode: mode)
            Task { @MainActor in
                do {
                    try await dictation.start()
                    guard isDictating else { return }   // stopped/cancelled during startup
                    dictationStart = Date()
                    setDictationState("listening", mode: mode)
                    startLevelTimer()
                } catch {
                    isDictating = false
                    setDictationError(error.localizedDescription)
                }
            }
        }

        private func stopDictation() {
            guard isDictating, let dictation else { return }
            let mode = dictationMode
            stopLevelTimer()
            dictationElapsed = dictationStart.map { Date().timeIntervalSince($0) } ?? 0
            setDictationState("transcribing", mode: mode)
            Task { @MainActor in
                defer { isDictating = false }
                do {
                    let result = try await dictation.stop()
                    finishDictation(mode: mode, text: result.text, audioURL: result.audioURL)
                } catch {
                    setDictationError(error.localizedDescription)
                }
            }
        }

        private func cancelDictation() {
            guard isDictating else { return }
            stopLevelTimer()
            dictation?.cancel()
            isDictating = false
            setDictationState("idle", mode: dictationMode)
        }

        private func finishDictation(mode: DictationMode, text: String, audioURL: URL) {
            let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !transcript.isEmpty else {
                try? FileManager.default.removeItem(at: audioURL)
                setDictationState("idle", mode: mode)
                return
            }

            switch mode {
            case .prose:
                // Prose is fast text entry: insert at the cursor and let the
                // normal change → autosave path pick it up. Audio isn't kept.
                try? FileManager.default.removeItem(at: audioURL)
                evaluate("window.TalkieEditor?.insertTextAtCursor(\(jsLiteral(" " + transcript)));")
                setDictationState("idle", mode: mode)

            case .block:
                // A bound block: copy the audio into assets, serialize a
                // dictation block, insert it, and commit the authoritative
                // post-insert text (read back atomically to avoid the
                // autosave-debounce race).
                let id = TKBlockParser.newId("tkd")
                let src = store.importAudio(from: audioURL, id: id)
                let capturedISO = ISO8601DateFormatter().string(from: Date())
                let block = TKBlockParser.dictationBlock(
                    id: id,
                    src: src,
                    durationSec: dictationElapsed,
                    transcript: transcript,
                    capturedISO: capturedISO
                )
                let blockText = "\n\n" + TKBlockParser.serialize(block) + "\n\n"
                let js = "window.TalkieEditor?.insertTextAtCursor(\(jsLiteral(blockText))); window.TalkieEditor?.getText();"
                webView?.evaluateJavaScript(js) { [weak self] result, _ in
                    let full = (result as? String) ?? ""
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if !full.isEmpty {
                            self.store.commit(text: full, reason: "dictation")
                            self.lastForwarded = full
                            // Forward for live preview explicitly — don't depend on the
                            // change-message vs getText-completion ordering.
                            self.evaluate("window.TalkieStudio?.onText(\(jsLiteral(full)));")
                            self.pushRevisions()
                            self.evaluate("window.TalkieStudio?.setSaved(true);")
                        }
                        self.setDictationState("idle", mode: mode)
                    }
                }
            }
        }

        private func startLevelTimer() {
            levelTimer?.invalidate()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let dictation = self.dictation, self.isDictating else { return }
                    let level = max(0, min(1, dictation.audioLevel))
                    let elapsedMs = Int((self.dictationStart.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
                    self.evaluate("window.TalkieStudio?.setDictationLevel(\(level), \(elapsedMs));")
                }
            }
            RunLoop.main.add(timer, forMode: .common)   // keep firing while the mouse is down on the HUD
            levelTimer = timer
        }

        private func stopLevelTimer() {
            levelTimer?.invalidate()
            levelTimer = nil
        }

        private func setDictationState(_ state: String, mode: DictationMode) {
            evaluate("window.TalkieStudio?.setDictationState('\(state)', {mode:'\(mode.rawValue)'});")
        }

        private func setDictationError(_ message: String) {
            stopLevelTimer()
            evaluate("window.TalkieStudio?.setDictationState('error', {message:\(jsLiteral(message))});")
        }

        private func pushRevisions() {
            evaluate("window.TalkieStudio?.setRevisions(\(jsonObject(store.revisionsPayload())));")
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script)
        }
    }
}

// MARK: - JS encoding

private func jsLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value), let s = String(data: data, encoding: .utf8) else { return "\"\"" }
    return s
}

private func jsonObject(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let s = String(data: data, encoding: .utf8) else { return "null" }
    return s
}
#endif
