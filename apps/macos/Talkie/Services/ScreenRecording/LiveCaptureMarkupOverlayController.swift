//
//  LiveCaptureMarkupOverlayController.swift
//  Talkie
//
//  Transparent drawing overlay for live screen recording markup.
//

import AppKit
import TalkieKit
import WebKit

@MainActor
final class LiveCaptureMarkupOverlayController: NSObject {
    var onLayersChanged: (([CaptureMarkupLayer]) -> Void)?
    var onDone: (([CaptureMarkupLayer]) -> Void)?
    var onCancel: (() -> Void)?

    private var panel: NSPanel?
    private var webView: WKWebView?
    private(set) var layers: [CaptureMarkupLayer] = []
    private var selectedTool = "ink"
    private var selectedColor = "#D03A1C"
    private var selectedStrokeWidth = 4.0

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(on screen: NSScreen, targetRect: CGRect) {
        dismiss(discardLayers: false)

        let frame = targetRect
            .standardized
            .intersection(screen.frame)
        let panelFrame = frame.isNull || frame.width < 8 || frame.height < 8
            ? screen.frame
            : frame

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "talkie")

        let webView = WKWebView(frame: NSRect(origin: .zero, size: panelFrame.size), configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")

        let panel = LiveCaptureMarkupPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = webView
        panel.level = .screenSaver + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.setFrameOrigin(panelFrame.origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(webView)

        self.panel = panel
        self.webView = webView
        loadOverlayResources()
    }

    func dismiss(discardLayers: Bool) {
        if discardLayers {
            layers.removeAll()
            onLayersChanged?(layers)
        }

        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "talkie")
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func setTool(_ tool: String) {
        selectedTool = tool
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setTool(\(Self.jsString(tool)));")
    }

    func setColor(_ color: String) {
        selectedColor = color
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setColor(\(Self.jsString(color)));")
    }

    func setStrokeWidth(_ width: Double) {
        selectedStrokeWidth = width
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setStrokeWidth(\(width));")
    }

    func undo() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.undo();")
    }

    func finish() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.done();")
    }

    func cancel() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.cancel();")
    }

    private func loadOverlayResources() {
        guard let directory = Self.bundledMarkupDirectory() else {
            Log(.ui).error("Live capture markup resources missing from bundle")
            return
        }
        let indexURL = directory.appendingPathComponent("overlay.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            Log(.ui).error("Live capture markup overlay.html missing")
            return
        }
        webView?.loadFileURL(indexURL, allowingReadAccessTo: directory)
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private func handle(_ message: LiveCaptureMarkupBridgeMessage) {
        switch message.name {
        case "liveMarkup.ready":
            applyCurrentToolState()
        case "liveMarkup.update":
            layers = message.layers
            onLayersChanged?(layers)
        case "liveMarkup.done":
            layers = message.layers
            onLayersChanged?(layers)
            onDone?(layers)
            dismiss(discardLayers: false)
        case "liveMarkup.cancel":
            onCancel?()
            dismiss(discardLayers: true)
        default:
            break
        }
    }

    private static func bundledMarkupDirectory() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidates = [
            resourceURL.appendingPathComponent("Resources/CaptureMarkup", isDirectory: true),
            resourceURL.appendingPathComponent("CaptureMarkup", isDirectory: true),
            resourceURL,
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("overlay.html").path)
        }
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    private func applyCurrentToolState() {
        setTool(selectedTool)
        setColor(selectedColor)
        setStrokeWidth(selectedStrokeWidth)
    }
}

extension LiveCaptureMarkupOverlayController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "talkie",
              let parsed = LiveCaptureMarkupBridgeMessage.parse(message.body) else { return }
        handle(parsed)
    }
}

extension LiveCaptureMarkupOverlayController: WKNavigationDelegate {}

private final class LiveCaptureMarkupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LiveCaptureMarkupBridgeMessage {
    let name: String
    let layers: [CaptureMarkupLayer]

    static func parse(_ body: Any) -> LiveCaptureMarkupBridgeMessage? {
        guard let dict = body as? [String: Any],
              let name = dict["name"] as? String else {
            return nil
        }

        let layers: [CaptureMarkupLayer]
        if let rawLayers = dict["layers"] {
            layers = Self.decodeLayers(rawLayers)
        } else if let rawDocument = dict["document"] as? [String: Any],
                  let rawLayers = rawDocument["layers"] {
            layers = Self.decodeLayers(rawLayers)
        } else {
            layers = []
        }

        return LiveCaptureMarkupBridgeMessage(name: name, layers: layers)
    }

    private static func decodeLayers(_ raw: Any) -> [CaptureMarkupLayer] {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode([CaptureMarkupLayer].self, from: data) else {
            return []
        }
        return decoded
    }
}
