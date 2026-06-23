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
    /// Desktop ink: the toolbar's screenshot button asks the host to snap. The
    /// host runs region selection and bakes the strokes in. Recording leaves
    /// this nil (it commits via Done instead).
    var onCapture: (() -> Void)?

    /// Swaps the toolbar's commit cluster: `false` (default) shows Done for the
    /// recording-markup flow; `true` shows the screenshot button for desktop ink.
    var showsCaptureAction = false {
        didSet { applyToolbarContext() }
    }

    var showsDock = true {
        didSet { applyDockVisibility() }
    }

    private var panel: NSPanel?
    private var passthroughControlsPanel: NSPanel?
    private var webView: WKWebView?
    private(set) var layers: [CaptureMarkupLayer] = []
    private var selectedTool = "ink"
    private var selectedColor = "#D03A1C"
    private var selectedStrokeWidth = 4.0

    /// Lets clicks fall through to the apps beneath while keeping strokes
    /// visible (arrange mode for the desktop ink layer). Drawing resumes when
    /// set back to false. Recording never sets it, so its behavior is unchanged.
    var passthrough = false {
        didSet {
            guard let panel else { return }
            panel.ignoresMouseEvents = passthrough
            if passthrough {
                panel.resignKey()
                setWebDockHidden(true)
                showPassthroughControls()
            } else {
                hidePassthroughControls()
                applyDockVisibility()
                panel.makeKeyAndOrderFront(nil)
                if let webView { panel.makeFirstResponder(webView) }
            }
        }
    }

    /// When true, the toolbar's Done keeps the strokes and flips to arrange mode
    /// instead of dismissing. The desktop ink layer sets this; recording leaves
    /// it false so Done commits and tears down as before.
    var persistsLayersOnDone = false

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
        panel.ignoresMouseEvents = passthrough
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
        hidePassthroughControls()

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

    /// Make the overlay non-interactive for the duration of a screenshot
    /// capture so the capture's own selection overlay (`.statusBar`) receives
    /// the mouse — but keep the strokes ON SCREEN, AS-IS, so you can frame the
    /// shot around them. The panel sits at `.screenSaver + 1`, so the ink stays
    /// visible above the dimmed selection; `ignoresMouseEvents` + `resignKey`
    /// let the crosshair below take the drag. The strokes bake in afterward.
    func yieldForCapture() {
        panel?.ignoresMouseEvents = true
        panel?.resignKey()
        hidePassthroughControls()
    }

    /// Restore interactivity after a capture that did NOT consume the ink
    /// (cancelled, or the shot didn't overlap the inked screen). The panel never
    /// left the screen, so there's nothing to re-show — just re-arm input.
    func resumeAfterCapture() {
        guard let panel else { return }
        panel.ignoresMouseEvents = passthrough
        if !passthrough {
            panel.makeKeyAndOrderFront(nil)
            if let webView { panel.makeFirstResponder(webView) }
        } else {
            showPassthroughControls()
        }
    }

    func moveBy(_ delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        if let panel {
            panel.setFrameOrigin(NSPoint(
                x: panel.frame.minX + delta.width,
                y: panel.frame.minY + delta.height
            ))
        }
        if let passthroughControlsPanel {
            passthroughControlsPanel.setFrameOrigin(NSPoint(
                x: passthroughControlsPanel.frame.minX + delta.width,
                y: passthroughControlsPanel.frame.minY + delta.height
            ))
        }
    }

    func setFrame(_ frame: CGRect) {
        let next = frame.standardized
        guard next.width >= 8, next.height >= 8 else { return }
        panel?.setFrame(next, display: true)
        webView?.frame = NSRect(origin: .zero, size: next.size)
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

    func redo() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.redo();")
    }

    func finish() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.done();")
    }

    func requestCapture() {
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.capture();")
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

    private func setWebDockHidden(_ hidden: Bool) {
        let value = hidden ? "true" : "false"
        evaluate("""
        (() => {
          const dock = document.getElementById("markup-dock");
          if (dock) dock.hidden = \(value);
        })();
        """)
    }

    private func showPassthroughControls() {
        guard showsCaptureAction, passthroughControlsPanel == nil, let panel else { return }

        let size = NSSize(width: 202, height: 42)
        let origin = Self.passthroughControlsOrigin(panelFrame: panel.frame, size: size)
        let controlsPanel = LiveCapturePassthroughControlsPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        controlsPanel.level = .screenSaver + 2
        controlsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        controlsPanel.isOpaque = false
        controlsPanel.backgroundColor = .clear
        controlsPanel.hasShadow = false
        controlsPanel.hidesOnDeactivate = false
        controlsPanel.canHide = false
        controlsPanel.sharingType = .none
        controlsPanel.contentView = LiveCapturePassthroughControlsView(
            onEdit: { [weak self] in
                self?.passthrough = false
            },
            onUndo: { [weak self] in
                self?.undo()
            },
            onCapture: { [weak self] in
                self?.requestCapture()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        controlsPanel.orderFrontRegardless()
        passthroughControlsPanel = controlsPanel
    }

    private func hidePassthroughControls() {
        passthroughControlsPanel?.orderOut(nil)
        passthroughControlsPanel?.contentView = nil
        passthroughControlsPanel = nil
    }

    private static func passthroughControlsOrigin(panelFrame: NSRect, size: NSSize) -> NSPoint {
        NSPoint(
            x: (panelFrame.midX - size.width / 2).rounded(),
            y: (panelFrame.minY + 26).rounded()
        )
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
            if persistsLayersOnDone {
                // Desktop ink: keep the strokes and drop into arrange mode so the
                // user can move windows under them, rather than tearing down.
                passthrough = true
            } else {
                dismiss(discardLayers: false)
            }
        case "liveMarkup.capture":
            onCapture?()
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
        applyToolbarContext()
        applyDockVisibility()
    }

    private func applyToolbarContext() {
        let context = showsCaptureAction ? "desktopInk" : "recording"
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setContext(\(Self.jsString(context)));")
    }

    private func applyDockVisibility() {
        guard !passthrough else {
            setWebDockHidden(true)
            return
        }
        setWebDockHidden(!showsDock)
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

private final class LiveCapturePassthroughControlsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LiveCapturePassthroughControlsView: NSView {
    private let onEdit: () -> Void
    private let onUndo: () -> Void
    private let onCapture: () -> Void
    private let onCancel: () -> Void

    init(
        onEdit: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onEdit = onEdit
        self.onUndo = onUndo
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: NSRect(x: 0, y: 0, width: 202, height: 42))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        setupButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButtons() {
        let stack = NSStackView(views: [
            makeButton(symbolName: "cursorarrow", title: "Edit", action: #selector(editPressed)),
            makeButton(symbolName: "arrow.uturn.backward", title: "Undo", action: #selector(undoPressed)),
            makeButton(symbolName: "camera.viewfinder", title: "Shot", action: #selector(capturePressed), emphasized: true),
            makeButton(symbolName: "xmark", title: "Close", action: #selector(cancelPressed), destructive: true),
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 5
        stack.frame = bounds.insetBy(dx: 6, dy: 6)
        stack.autoresizingMask = [.width, .height]
        addSubview(stack)
    }

    private func makeButton(
        symbolName: String,
        title: String,
        action: Selector,
        emphasized: Bool = false,
        destructive: Bool = false
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.toolTip = title
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.contentTintColor = destructive
            ? NSColor.systemRed
            : (emphasized ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.86))
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = emphasized
            ? NSColor.systemOrange.withAlphaComponent(0.16).cgColor
            : NSColor.white.withAlphaComponent(0.07).cgColor
        return button
    }

    @objc private func editPressed() {
        onEdit()
    }

    @objc private func undoPressed() {
        onUndo()
    }

    @objc private func capturePressed() {
        onCapture()
    }

    @objc private func cancelPressed() {
        onCancel()
    }
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
