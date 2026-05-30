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
        teardown()

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

    func teardown() {
        if let webView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "talkie")
        }
        webView?.removeFromSuperview()
        webView = nil
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
