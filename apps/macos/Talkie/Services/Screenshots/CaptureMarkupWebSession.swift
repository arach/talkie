//
//  CaptureMarkupWebSession.swift
//  Talkie
//
//  Ephemeral WKWebView host for capture markup preview and touch-up.
//

import AppKit
import Foundation
import TalkieKit
import WebKit

@MainActor
final class CaptureMarkupWebSession: NSObject {
    var onMessage: ((CaptureMarkupBridgeMessage) -> Void)?

    private var webView: WKWebView?
    private var sessionId = UUID().uuidString
    private var sessionDirectory: URL?
    private var tempImageURL: URL?
    private var pendingDocument: CaptureMarkupDocument?

    func attach(to container: NSView) {
        teardown(clearCallbacks: false)

        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        config.userContentController.add(self, name: "talkie")

        let webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        container.addSubview(webView)
        self.webView = webView
    }

    func start(imageURL: URL, document: CaptureMarkupDocument, instruction: String?) {
        pendingDocument = document
        guard let bundleURL = Self.bundledMarkupDirectory() else {
            Log(.ui).error("CaptureMarkup web resources missing from bundle")
            return
        }

        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-markup-\(sessionId)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            try copyMarkupResources(from: bundleURL, to: sessionDir)
            let localImage = sessionDir.appendingPathComponent("capture.png")
            if FileManager.default.fileExists(atPath: localImage.path) {
                try FileManager.default.removeItem(at: localImage)
            }
            try FileManager.default.copyItem(at: imageURL, to: localImage)
            tempImageURL = localImage
            sessionDirectory = sessionDir

            let indexURL = sessionDir.appendingPathComponent("index.html")
            webView?.loadFileURL(indexURL, allowingReadAccessTo: sessionDir)
        } catch {
            Log(.ui).error("CaptureMarkup session setup failed", detail: error.localizedDescription)
        }
    }

    func push(document: CaptureMarkupDocument) {
        guard let webView else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(document),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.talkieMarkup && window.talkieMarkup.push({ document: \(json) });"
        webView.evaluateJavaScript(script)
    }

    func clearSelection() {
        webView?.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.clearSelection();")
    }

    // MARK: - Work Thread (streamed run log → webview right rail)
    //
    // The right rail is contextual: it shows the Work Thread while/after a
    // run, the layer Inspector on selection. Swift owns the thread state and
    // pushes whole snapshots; the JS side is a dumb renderer. Each meta step
    // fills its detail in as the agent learns it (region count, plan summary);
    // the resulting marks are revealed one at a time so the pass streams.

    private var threadInstruction = ""
    private var threadModel = ""
    private var threadPass: Int?
    private var threadAttachmentCount = 0
    private var threadRows: [(verb: String, detail: String, status: String)] = []
    private var threadMarks: [(verb: String, detail: String)] = []

    /// First frame of a run — the three meta steps pending, the instruction
    /// pinned at the head.
    func beginThread(instruction: String, model: String? = nil, pass: Int? = nil, attachmentCount: Int = 0) {
        threadInstruction = instruction
        threadModel = model ?? ""
        threadPass = pass
        threadAttachmentCount = attachmentCount
        threadRows = [
            ("read", "the capture", "pending"),
            ("describe", "the scene", "pending"),
            ("plan", "the marks", "pending"),
        ]
        threadMarks = []
        pushThread(live: true, statusText: "starting the pass…", elapsed: 0, summary: nil)
    }

    func updateThreadModel(_ model: String, elapsed: Double) {
        guard !model.isEmpty else { return }
        threadModel = model
        pushThread(live: true, statusText: "starting the pass…", elapsed: elapsed, summary: nil)
    }

    /// Fold a phase event into the row state, filling in detail as it arrives.
    func handlePhase(_ phase: CaptureMarkupRunPhase, elapsed: Double) {
        func activate(_ i: Int) {
            for j in threadRows.indices where j < i && threadRows[j].status != "done" {
                threadRows[j].status = "done"
            }
            if threadRows.indices.contains(i) { threadRows[i].status = "active" }
        }
        func finish(_ i: Int, _ detail: String?) {
            guard threadRows.indices.contains(i) else { return }
            threadRows[i].status = "done"
            if let detail, !detail.isEmpty { threadRows[i].detail = detail }
        }

        let status: String
        switch phase {
        case .reading: activate(0); status = "reading the capture…"
        case .read(let d): finish(0, d); status = "read the capture"
        case .describing: activate(1); status = "describing the scene…"
        case .described: finish(1, nil); status = "described the scene"
        case .planning(let model): threadModel = model; activate(2); status = "planning the marks…"
        case .planned(let d): finish(2, d); status = "planned the marks"
        case .applying:
            for j in threadRows.indices { threadRows[j].status = "done" }
            status = "drawing the marks…"
        }
        pushThread(live: true, statusText: status, elapsed: elapsed, summary: nil)
    }

    /// Settle the thread into its record. Marks are appended one at a time so
    /// the pass visibly streams onto the thread, then the footer summary lands.
    func finishThread(added: [CaptureMarkupLayer], elapsed: Double, pass: Int) async {
        for j in threadRows.indices { threadRows[j].status = "done" }
        threadMarks = []
        for layer in added {
            threadMarks.append((layer.kind.rawValue, Self.markDetail(layer)))
            pushThread(live: true, statusText: "drawing the marks…", elapsed: elapsed, summary: nil)
            try? await Task.sleep(nanoseconds: 110_000_000)
        }
        let count = added.count
        let summary = "pass \(pass) · \(count) mark\(count == 1 ? "" : "s") · \(Self.elapsedLabel(elapsed))"
        pushThread(live: false, statusText: nil, elapsed: elapsed, summary: summary)
    }

    func failThread(elapsed: Double) {
        pushThread(live: false, statusText: nil, elapsed: elapsed, summary: "run failed · nothing applied")
    }

    private func pushThread(live: Bool, statusText: String?, elapsed: Double, summary: String?) {
        var entries: [[String: Any]] = []
        for row in threadRows {
            entries.append(["verb": row.verb, "detail": row.detail, "kind": "meta", "status": row.status])
        }
        for mark in threadMarks {
            entries.append(["verb": mark.verb, "detail": mark.detail, "kind": "mark", "status": "done"])
        }
        var payload: [String: Any] = [
            "entries": entries,
            "live": live,
            "elapsed": Self.elapsedLabel(elapsed),
        ]
        if let threadPass { payload["pass"] = threadPass }
        if threadAttachmentCount > 0 { payload["attachments"] = threadAttachmentCount }
        if !threadInstruction.isEmpty { payload["instruction"] = threadInstruction }
        if !threadModel.isEmpty { payload["model"] = threadModel }
        if let statusText { payload["statusText"] = statusText }
        if let summary { payload["summary"] = summary }
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.thread(\(json));")
    }

    private static func markDetail(_ layer: CaptureMarkupLayer) -> String {
        if let label = layer.label, !label.isEmpty { return label }
        if let text = layer.text, !text.isEmpty { return text }
        switch layer.kind {
        case .rect: return "box"
        case .highlight: return "highlight"
        case .arrow: return "arrow"
        case .label: return "label"
        case .guide: return "guide grid"
        default: return "mark"
        }
    }

    private static func elapsedLabel(_ seconds: Double) -> String {
        String(format: "%.1fs", max(0, seconds))
    }

    private static func javaScriptStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func undo() {
        webView?.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.undo();")
    }

    func redo() {
        webView?.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.redo();")
    }

    func fetchDocument() async -> CaptureMarkupDocument? {
        guard let webView else { return nil }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.exportDocument()") { result, _ in
                guard let dict = result as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dict),
                      let document = try? JSONDecoder().decode(CaptureMarkupDocument.self, from: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: document)
            }
        }
    }

    func fetchMessageLayers() async -> [CaptureMarkupLayer] {
        guard let webView else { return [] }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.exportMessageLayers()") { result, _ in
                guard let array = result as? [[String: Any]],
                      let data = try? JSONSerialization.data(withJSONObject: array),
                      let layers = try? JSONDecoder().decode([CaptureMarkupLayer].self, from: data) else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: layers)
            }
        }
    }

    func clearMessageLayers() {
        webView?.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.clearMessageLayers();")
    }

    func removeMessageLayer(id: String) {
        guard let idJSON = Self.javaScriptStringLiteral(id) else { return }
        webView?.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.removeMessageLayer(\(idJSON));")
    }

    func teardown(clearCallbacks: Bool = true) {
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "talkie")
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
        if clearCallbacks {
            onMessage = nil
        }
        threadInstruction = ""
        threadModel = ""
        threadPass = nil
        threadAttachmentCount = 0
        threadRows.removeAll(keepingCapacity: false)
        threadMarks.removeAll(keepingCapacity: false)
        if let sessionDirectory {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        tempImageURL = nil
        sessionDirectory = nil
        pendingDocument = nil
    }

    private static func bundledMarkupDirectory() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Resources/CaptureMarkup", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("CaptureMarkup", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func copyMarkupResources(from source: URL, to destination: URL) throws {
        let names = ["index.html", "markup.css", "markup.js"]
        for name in names {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            try FileManager.default.copyItem(at: from, to: to)
        }
    }
}

extension CaptureMarkupWebSession: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "talkie",
              let bridge = CaptureMarkupBridgeMessage.parse(message.body) else { return }
        onMessage?(bridge)
    }
}

extension CaptureMarkupWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let localImage = tempImageURL else { return }
        let doc = pendingDocument ?? CaptureMarkupDocument(imageWidth: 1, imageHeight: 1)

        var payload: [String: Any] = [
            "sessionId": sessionId,
            "imageURL": localImage.absoluteString,
            "document": (try? JSONEncoder().encode(doc)).flatMap {
                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
            } ?? [:],
        ]
        if let data = try? Data(contentsOf: localImage) {
            payload["imageDataURL"] = "data:image/png;base64,\(data.base64EncodedString())"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.talkieMarkup && window.talkieMarkup.init(\(json));")
    }
}
