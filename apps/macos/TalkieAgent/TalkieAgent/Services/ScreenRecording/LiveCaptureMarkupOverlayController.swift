//
//  LiveCaptureMarkupOverlayController.swift
//  Talkie
//
//  Transparent drawing overlay for live screen recording markup.
//

import AppKit
import CoreImage
import ImageIO
import TalkieKit
import UniformTypeIdentifiers
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
    /// Agent quick markup can provide local OCR-backed text redaction.
    var onAutoBlurText: (() -> Void)?
    /// Called for keyboard-level safety exits that need owner cleanup beyond
    /// the web overlay itself, such as agent quick-markup chrome panels.
    var onDismissRequest: (() -> Void)?

    /// Swaps the toolbar's commit cluster: `false` (default) shows Done for the
    /// recording-markup flow; `true` shows the screenshot button for desktop ink.
    var showsCaptureAction = false {
        didSet { applyToolbarContext() }
    }

    var showsDock = true {
        didSet { applyDockVisibility() }
    }

    var showsWindowChrome = true {
        didSet { applyWindowChromeVisibility() }
    }

    var usesCompactDock = false {
        didSet { applyCompactDockMode() }
    }

    var supportsAutoBlurText = false {
        didSet { applyAutoBlurTextAvailability() }
    }

    var additionalMousePassthroughScreenRects: (() -> [CGRect])? {
        didSet { applyMousePassthroughState() }
    }

    /// Most live markup overlays are intentionally invisible to ScreenCaptureKit
    /// and get baked into artifacts later. Agent quick-markup is an inspectable
    /// popup, so it opts in to being directly screenshottable.
    var isVisibleInScreenCapture = false {
        didSet { applyPanelSharingType() }
    }

    private var panel: NSPanel?
    private var passthroughControlsPanel: NSPanel?
    private var webView: WKWebView?
    private(set) var layers: [CaptureMarkupLayer] = []
    private var selectedTool = "ink"
    private var selectedColor = "#D03A1C"
    private var selectedStrokeWidth = 4.0
    private var drawableRect: CGRect?
    private var localSafetyKeyMonitor: Any?
    private var globalSafetyKeyMonitor: Any?
    private var localSafeAreaMouseMonitor: Any?
    private var globalSafeAreaMouseMonitor: Any?
    private var captureYieldActive = false
    private var sourceImageDataURL: String?
    private let protectedCornerSize = CGSize(width: 96, height: 96)

    /// Lets clicks fall through to the apps beneath while keeping strokes
    /// visible (arrange mode for the desktop ink layer). Drawing resumes when
    /// set back to false. Recording never sets it, so its behavior is unchanged.
    var passthrough = false {
        didSet {
            guard let panel else { return }
            applyMousePassthroughState()
            if passthrough {
                panel.resignKey()
                setWebDockHidden(true)
                showPassthroughControls()
            } else {
                hidePassthroughControls()
                applyDockVisibility()
                if !panel.ignoresMouseEvents {
                    panel.makeKeyAndOrderFront(nil)
                    if let webView { panel.makeFirstResponder(webView) }
                }
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
        panel.sharingType = sharingType
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
        installSafetyMonitors()
        applyMousePassthroughState()
        loadOverlayResources()
    }

    func dismiss(discardLayers: Bool) {
        removeSafetyMonitors()
        hidePassthroughControls()
        captureYieldActive = false

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
        captureYieldActive = true
        applyMousePassthroughState()
        panel?.resignKey()
        hidePassthroughControls()
    }

    /// Restore interactivity after a capture that did NOT consume the ink
    /// (cancelled, or the shot didn't overlap the inked screen). The panel never
    /// left the screen, so there's nothing to re-show — just re-arm input.
    func resumeAfterCapture() {
        guard let panel else { return }
        captureYieldActive = false
        applyMousePassthroughState()
        if !passthrough, !panel.ignoresMouseEvents {
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
        applyDrawableRect()
    }

    func setDrawableRect(_ rect: CGRect?) {
        drawableRect = rect
        applyDrawableRect()
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

    /// A lightweight preview copy lets the transparent web overlay pixelate
    /// the actual source pixels while the native image remains underneath.
    func setSourceImage(_ image: CGImage?) {
        guard let image,
              let data = NSBitmapImageRep(cgImage: image).representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.58]
              ) else {
            sourceImageDataURL = nil
            applySourceImage()
            return
        }
        sourceImageDataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
        applySourceImage()
    }

    func setAutoBlurTextRunning(_ running: Bool) {
        let value = running ? "true" : "false"
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setAutoBlurTextRunning(\(value));")
    }

    func replaceAutoBlurTextLayers(_ layers: [CaptureMarkupLayer]) {
        guard let data = try? JSONEncoder().encode(layers),
              let json = String(data: data, encoding: .utf8) else {
            setAutoBlurTextRunning(false)
            return
        }
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.replaceAutoBlurTextLayers(\(json));")
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

    private func installSafetyMonitors() {
        removeSafetyMonitors()

        localSafetyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isKeyboardDismissEvent(event) else { return event }
            self?.requestSafetyDismiss()
            return nil
        }
        globalSafetyKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isKeyboardDismissEvent(event) else { return }
            Task { @MainActor in
                self?.requestSafetyDismiss()
            }
        }

        let mouseMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        localSafeAreaMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            self?.applyMousePassthroughState()
            return event
        }
        globalSafeAreaMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            Task { @MainActor in
                self?.applyMousePassthroughState()
            }
        }
    }

    private func removeSafetyMonitors() {
        if let localSafetyKeyMonitor {
            NSEvent.removeMonitor(localSafetyKeyMonitor)
            self.localSafetyKeyMonitor = nil
        }
        if let globalSafetyKeyMonitor {
            NSEvent.removeMonitor(globalSafetyKeyMonitor)
            self.globalSafetyKeyMonitor = nil
        }
        if let localSafeAreaMouseMonitor {
            NSEvent.removeMonitor(localSafeAreaMouseMonitor)
            self.localSafeAreaMouseMonitor = nil
        }
        if let globalSafeAreaMouseMonitor {
            NSEvent.removeMonitor(globalSafeAreaMouseMonitor)
            self.globalSafeAreaMouseMonitor = nil
        }
    }

    private func applyMousePassthroughState() {
        guard let panel else { return }
        panel.ignoresMouseEvents = passthrough
            || captureYieldActive
            || mouseIsInProtectedCorner(of: panel)
            || mouseIsInAdditionalPassthroughRect(of: panel)
    }

    private func mouseIsInProtectedCorner(of panel: NSPanel) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse),
              let screen = Self.screen(for: mouse) ?? panel.screen else {
            return false
        }

        let size = protectedCornerSize
        let topLeft = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let topRight = NSRect(
            x: screen.frame.maxX - size.width,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return topLeft.contains(mouse) || topRight.contains(mouse)
    }

    private func mouseIsInAdditionalPassthroughRect(of panel: NSPanel) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse),
              let passthroughRects = additionalMousePassthroughScreenRects?() else {
            return false
        }
        return passthroughRects.contains { $0.standardized.contains(mouse) }
    }

    private static func screen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private static func isKeyboardDismissEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }

    private func requestSafetyDismiss() {
        if let onDismissRequest {
            onDismissRequest()
        } else {
            dismiss(discardLayers: false)
        }
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

    private func setWebWindowChromeHidden(_ hidden: Bool) {
        let value = hidden ? "true" : "false"
        evaluate("""
        (() => {
          document.querySelectorAll(".window-close, .surface-actions").forEach((element) => {
            element.hidden = \(value);
          });
        })();
        """)
    }

    private func setWebCompactDockEnabled(_ enabled: Bool) {
        let value = enabled ? "true" : "false"
        evaluate("""
        (() => {
          document.body.dataset.agentCompactDock = \(Self.jsString(value));
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
        controlsPanel.sharingType = sharingType
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
                self?.requestSafetyDismiss()
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

    private var sharingType: NSWindow.SharingType {
        isVisibleInScreenCapture ? .readOnly : .none
    }

    private func applyPanelSharingType() {
        panel?.sharingType = sharingType
        passthroughControlsPanel?.sharingType = sharingType
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
        case "liveMarkup.sampleMaterial":
            if let requestID = message.requestID, let rect = message.rect {
                sampleAdaptiveGlass(requestID: requestID, webRect: rect)
            }
        case "liveMarkup.autoBlurText":
            onAutoBlurText?()
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

    private static func jsJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func sampleAdaptiveGlass(requestID: String, webRect: CGRect) {
        guard let panel else { return }
        let localRect = webRect.standardized.intersection(NSRect(origin: .zero, size: panel.frame.size))
        guard !localRect.isNull, localRect.width >= 1, localRect.height >= 1 else { return }

        let screenRect = CGRect(
            x: panel.frame.minX + localRect.minX,
            y: panel.frame.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
        let excludedWindowIDs = [panel, passthroughControlsPanel]
            .compactMap { window -> CGWindowID? in
                guard let window else { return nil }
                return CGWindowID(window.windowNumber)
            }
        let panelNumber = panel.windowNumber

        Task { @MainActor [weak self] in
            guard let image = await ScreenshotCaptureService.shared.captureScreenRegion(
                screenRect: screenRect,
                excludingWindowIDs: excludedWindowIDs
            ), let sample = AdaptiveGlassSample.make(
                requestID: requestID,
                image: image,
                pointWidth: screenRect.width
            ), let json = Self.jsJSON(sample),
              self?.panel?.windowNumber == panelNumber else {
                return
            }
            self?.evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.applyMaterialSample(\(json));")
        }
    }

    private func applyCurrentToolState() {
        setTool(selectedTool)
        setColor(selectedColor)
        setStrokeWidth(selectedStrokeWidth)
        applyDrawableRect()
        applyToolbarContext()
        applyDockVisibility()
        applyWindowChromeVisibility()
        applyCompactDockMode()
        applyAutoBlurTextAvailability()
        applySourceImage()
    }

    private func applyDrawableRect() {
        guard let drawableRect else {
            evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setDrawableRect(null);")
            return
        }
        let rect = drawableRect.standardized
        evaluate("""
        window.talkieLiveMarkup && window.talkieLiveMarkup.setDrawableRect({
          x: \(Double(rect.minX)),
          y: \(Double(rect.minY)),
          width: \(Double(rect.width)),
          height: \(Double(rect.height))
        });
        """)
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

    private func applyWindowChromeVisibility() {
        setWebWindowChromeHidden(!showsWindowChrome)
    }

    private func applyCompactDockMode() {
        setWebCompactDockEnabled(usesCompactDock)
    }

    private func applyAutoBlurTextAvailability() {
        let value = supportsAutoBlurText ? "true" : "false"
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setAutoBlurTextAvailable(\(value));")
    }

    private func applySourceImage() {
        let value = sourceImageDataURL.map(Self.jsString) ?? "null"
        evaluate("window.talkieLiveMarkup && window.talkieLiveMarkup.setSourceImage(\(value));")
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
    let requestID: String?
    let rect: CGRect?

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

        return LiveCaptureMarkupBridgeMessage(
            name: name,
            layers: layers,
            requestID: dict["requestID"] as? String,
            rect: decodeRect(dict["rect"])
        )
    }

    private static func decodeRect(_ raw: Any?) -> CGRect? {
        guard let raw = raw as? [String: Any],
              let x = (raw["x"] as? NSNumber)?.doubleValue,
              let y = (raw["y"] as? NSNumber)?.doubleValue,
              let width = (raw["width"] as? NSNumber)?.doubleValue,
              let height = (raw["height"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
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

@MainActor
private struct AdaptiveGlassSample: Encodable {
    let requestID: String
    let textColor: String
    let backgroundColor: String
    let backgroundAlpha: Double
    let borderColor: String
    let borderAlpha: Double
    let borderWidth: Double
    let backgroundBlur: Double
    let shadowColor: String
    let shadowBlur: Double
    let shadowOffsetY: Double
    let backdropDataURL: String?

    private static let analysisSize = 16
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func make(requestID: String, image: CGImage, pointWidth: CGFloat) -> AdaptiveGlassSample? {
        guard let statistics = statistics(for: image) else { return nil }
        let luminance = statistics.luminance
        let activity = min(1, statistics.deviation / 0.24)
        let nearMidtone = max(0, 1 - abs(luminance - 0.5) / 0.5)
        let usesLightMaterial = luminance >= 0.58
        let alpha = min(
            0.78,
            (usesLightMaterial ? 0.46 : 0.50) + activity * 0.20 + nearMidtone * 0.05
        )
        let blur = 10 + activity * 13
        let background = usesLightMaterial
            ? mixedHex(base: (0.97, 0.98, 1), sample: statistics.averageColor, sampleAmount: 0.18)
            : mixedHex(base: (0.055, 0.065, 0.085), sample: statistics.averageColor, sampleAmount: 0.24)
        let pixelScale = max(1, CGFloat(image.width) / max(1, pointWidth))

        return AdaptiveGlassSample(
            requestID: requestID,
            textColor: usesLightMaterial ? "#15171B" : "#F8F7F3",
            backgroundColor: background,
            backgroundAlpha: alpha,
            borderColor: "#FFFFFF",
            borderAlpha: usesLightMaterial ? 0.62 : 0.30,
            borderWidth: activity > 0.62 ? 0.9 : 0.75,
            backgroundBlur: blur,
            shadowColor: usesLightMaterial ? "rgba(24, 28, 36, 0.18)" : "rgba(0, 0, 0, 0.28)",
            shadowBlur: 10 + activity * 8,
            shadowOffsetY: 3,
            backdropDataURL: blurredDataURL(image: image, radius: blur * pixelScale)
        )
    }

    private static func statistics(
        for image: CGImage
    ) -> (luminance: Double, deviation: Double, averageColor: (Double, Double, Double))? {
        let count = analysisSize * analysisSize
        var pixels = [UInt8](repeating: 0, count: count * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: analysisSize,
                height: analysisSize,
                bitsPerComponent: 8,
                bytesPerRow: analysisSize * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: analysisSize, height: analysisSize))
            return true
        }
        guard rendered else { return nil }

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var luminances: [Double] = []
        luminances.reserveCapacity(count)
        for index in 0..<count {
            let offset = index * 4
            let r = Double(pixels[offset]) / 255
            let g = Double(pixels[offset + 1]) / 255
            let b = Double(pixels[offset + 2]) / 255
            red += r
            green += g
            blue += b
            luminances.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        let divisor = Double(count)
        let averageLuminance = luminances.reduce(0, +) / divisor
        let variance = luminances.reduce(0) { partial, value in
            let difference = value - averageLuminance
            return partial + difference * difference
        } / divisor
        return (
            averageLuminance,
            sqrt(variance),
            (red / divisor, green / divisor, blue / divisor)
        )
    }

    private static func mixedHex(
        base: (Double, Double, Double),
        sample: (Double, Double, Double),
        sampleAmount: Double
    ) -> String {
        func channel(_ base: Double, _ sample: Double) -> Int {
            Int((min(1, max(0, base * (1 - sampleAmount) + sample * sampleAmount)) * 255).rounded())
        }
        func hex(_ value: Int) -> String {
            let component = String(value, radix: 16, uppercase: true)
            return component.count == 1 ? "0\(component)" : component
        }
        return "#\(hex(channel(base.0, sample.0)))\(hex(channel(base.1, sample.1)))\(hex(channel(base.2, sample.2)))"
    }

    private static func blurredDataURL(image: CGImage, radius: CGFloat) -> String? {
        let input = CIImage(cgImage: image)
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        guard let output = ciContext.createCGImage(blurred, from: input.extent) else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:image/png;base64,\((data as Data).base64EncodedString())"
    }
}
