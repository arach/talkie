//
//  DesktopMagnifierController.swift
//  TalkieAgent
//
//  Freeze-first desktop magnifier. The user drags a source region, Talkie
//  captures that frozen crop with ScreenCaptureKit, then places a movable
//  magnified copy on the desktop. It is a pasted still, not a live sampler.
//

import AppKit
import TalkieKit

@MainActor
final class DesktopMagnifierController {
    static let shared = DesktopMagnifierController()

    private let log = Log(.system)
    private var panels: [UUID: DesktopMagnifierPanel] = [:]
    private var selectionTask: Task<Void, Never>?
    private weak var selectionOverlay: ScreenCaptureOverlay?

    private init() {}

    var isSelecting: Bool { selectionTask != nil }
    var hasPanels: Bool { !panels.isEmpty }

    func startSelection() {
        guard selectionTask == nil else {
            selectionOverlay?.cancel()
            return
        }

        let previousApp = NSWorkspace.shared.frontmostApplication
        selectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.selectionTask = nil
                self.selectionOverlay = nil
                CaptureFreezeStore.shared.clear()
            }

            CaptureFreezeStore.shared.prime()

            let overlay = ScreenCaptureOverlay()
            self.selectionOverlay = overlay
            guard let rect = await overlay.selectRegion(freezesDesktop: true),
                  rect.width >= 8,
                  rect.height >= 8 else {
                return
            }

            guard let capture = await ScreenshotCaptureService.shared.captureStandalone(
                mode: .region,
                preselectedRegion: rect
            ) else {
                self.log.warning("Desktop magnifier capture failed")
                return
            }

            self.showMagnifier(image: capture.image, sourceRect: capture.captureRect ?? rect)

            if let previousApp,
               previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp.activate()
            }
        }
    }

    func closeAll() {
        for id in Array(panels.keys) {
            closePanel(id)
        }
    }

    func dismissForSafety() {
        selectionTask?.cancel()
        selectionTask = nil
        selectionOverlay?.cancel()
        selectionOverlay = nil
        CaptureFreezeStore.shared.clear()
    }

    private func showMagnifier(image: CGImage, sourceRect: CGRect) {
        let id = UUID()
        let screen = screen(for: sourceRect)
        let geometry = panelGeometry(
            sourceSize: sourceRect.size,
            requestedZoom: 2,
            on: screen
        )
        let frame = initialFrame(
            sourceRect: sourceRect,
            panelSize: geometry.size,
            on: screen
        )

        let panel = DesktopMagnifierPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovableByWindowBackground = false
        panel.sharingType = .readOnly

        let content = DesktopMagnifierContentView(
            image: image,
            sourcePointSize: sourceRect.size,
            zoom: geometry.zoom
        )
        content.frame = NSRect(origin: .zero, size: frame.size)
        content.autoresizingMask = [.width, .height]
        content.onClose = { [weak self] in
            self?.closePanel(id)
        }
        content.onZoomRequested = { [weak self, weak panel, weak content] zoom in
            guard let self, let panel, let content else { return }
            self.setZoom(zoom, for: panel, content: content)
        }

        panel.contentView = content
        panels[id] = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(content)

        log.info(
            "Desktop magnifier placed",
            detail: "source=\(Int(sourceRect.width))x\(Int(sourceRect.height)) zoom=\(Self.zoomText(geometry.zoom, places: 2))"
        )
    }

    private func closePanel(_ id: UUID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func setZoom(
        _ requestedZoom: CGFloat,
        for panel: DesktopMagnifierPanel,
        content: DesktopMagnifierContentView
    ) {
        let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, panel.frame) })
            ?? screen(for: panel.frame)
        let geometry = panelGeometry(
            sourceSize: content.sourcePointSize,
            requestedZoom: requestedZoom,
            on: screen
        )

        let currentFrame = panel.frame
        var nextFrame = NSRect(
            x: currentFrame.midX - geometry.size.width / 2,
            y: currentFrame.midY - geometry.size.height / 2,
            width: geometry.size.width,
            height: geometry.size.height
        )
        if let visible = screen?.visibleFrame {
            nextFrame = clamped(nextFrame, to: visible.insetBy(dx: 10, dy: 10))
        }

        content.updateZoom(geometry.zoom)
        panel.setFrame(nextFrame, display: true, animate: true)
    }

    private func screen(for rect: CGRect) -> NSScreen? {
        let midpoint = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(midpoint, $0.frame, false) })
            ?? NSScreen.screens.first(where: { NSIntersectsRect($0.frame, rect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func panelGeometry(
        sourceSize: CGSize,
        requestedZoom: CGFloat,
        on screen: NSScreen?
    ) -> (size: CGSize, zoom: CGFloat) {
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        let zoom = min(6, max(1, requestedZoom))
        var width = sourceWidth * zoom
        var height = sourceHeight * zoom

        let minWidth: CGFloat = 180
        let minHeight: CGFloat = 132
        let grow = max(1, minWidth / width, minHeight / height)
        width *= grow
        height *= grow

        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let maxWidth = max(220, min(920, visible.width - 28))
        let maxHeight = max(180, min(680, visible.height - 28))
        let shrink = min(1, maxWidth / width, maxHeight / height)
        width *= shrink
        height *= shrink

        let actualZoom = min(width / sourceWidth, height / sourceHeight)
        return (CGSize(width: width, height: height), actualZoom)
    }

    private func initialFrame(
        sourceRect: CGRect,
        panelSize: CGSize,
        on screen: NSScreen?
    ) -> NSRect {
        let visible = (screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sourceRect)
            .insetBy(dx: 10, dy: 10)
        let gap: CGFloat = 14
        let candidates = [
            NSRect(
                x: sourceRect.maxX + gap,
                y: sourceRect.midY - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            NSRect(
                x: sourceRect.minX - gap - panelSize.width,
                y: sourceRect.midY - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            NSRect(
                x: sourceRect.midX - panelSize.width / 2,
                y: sourceRect.maxY + gap,
                width: panelSize.width,
                height: panelSize.height
            ),
            NSRect(
                x: sourceRect.midX - panelSize.width / 2,
                y: sourceRect.minY - gap - panelSize.height,
                width: panelSize.width,
                height: panelSize.height
            ),
        ]

        if let frame = candidates.first(where: { visible.contains($0) }) {
            return frame
        }
        return clamped(candidates[0], to: visible)
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        if result.width > visible.width {
            result.size.width = visible.width
        }
        if result.height > visible.height {
            result.size.height = visible.height
        }
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private static func zoomText(_ zoom: CGFloat, places: Int) -> String {
        Double(zoom).formatted(.number.precision(.fractionLength(places)))
    }
}

private final class DesktopMagnifierPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DesktopMagnifierContentView: NSView {
    enum Control {
        case close
        case zoomIn
        case zoomOut
    }

    let sourcePointSize: CGSize
    var onClose: (() -> Void)?
    var onZoomRequested: ((CGFloat) -> Void)?

    private let image: NSImage
    private var zoom: CGFloat
    private var dragStart: (mouse: NSPoint, frame: NSRect)?

    private var imageRect: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    private var chromeRect: NSRect {
        NSRect(x: 8, y: bounds.maxY - 34, width: max(0, bounds.width - 16), height: 28)
    }
    private var closeRect: NSRect {
        NSRect(x: bounds.maxX - 34, y: bounds.maxY - 29, width: 22, height: 22)
    }
    private var zoomInRect: NSRect {
        closeRect.offsetBy(dx: -28, dy: 0)
    }
    private var zoomOutRect: NSRect {
        closeRect.offsetBy(dx: -56, dy: 0)
    }

    init(image: CGImage, sourcePointSize: CGSize, zoom: CGFloat) {
        self.sourcePointSize = CGSize(
            width: max(1, sourcePointSize.width),
            height: max(1, sourcePointSize.height)
        )
        self.image = NSImage(cgImage: image, size: self.sourcePointSize)
        self.zoom = zoom
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func updateZoom(_ zoom: CGFloat) {
        self.zoom = zoom
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawImage()
        drawChrome()
        drawBorder()
    }

    private func drawImage() {
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
        NSColor.black.setFill()
        rect.fill()
        image.draw(
            in: rect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawChrome() {
        let chrome = NSBezierPath(roundedRect: chromeRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.04, alpha: 0.70).setFill()
        chrome.fill()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        chrome.lineWidth = 0.75
        chrome.stroke()

        let label = "\(Double(zoom).formatted(.number.precision(.fractionLength(1))))x"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.88),
        ]
        label.draw(
            at: NSPoint(x: chromeRect.minX + 10, y: chromeRect.midY - 6),
            withAttributes: attrs
        )

        drawButton(rect: zoomOutRect, title: "-")
        drawButton(rect: zoomInRect, title: "+")
        drawButton(rect: closeRect, title: "x")
    }

    private func drawButton(rect: NSRect, title: String) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.86),
        ]
        let size = title.size(withAttributes: attrs)
        title.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawBorder() {
        let border = NSBezierPath(roundedRect: imageRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: 1, alpha: 0.30).setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch control(at: point) {
        case .close:
            onClose?()
        case .zoomIn:
            onZoomRequested?(zoom * 1.2)
        case .zoomOut:
            onZoomRequested?(zoom / 1.2)
        case nil:
            dragStart = (mouse: NSEvent.mouseLocation, frame: window?.frame ?? .zero)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let window else { return }
        let location = NSEvent.mouseLocation
        let dx = location.x - dragStart.mouse.x
        let dy = location.y - dragStart.mouse.y
        var frame = dragStart.frame
        frame.origin.x += dx
        frame.origin.y += dy
        window.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              abs(event.scrollingDeltaY) > 0.1 else {
            super.scrollWheel(with: event)
            return
        }
        let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.08 : 1 / 1.08
        onZoomRequested?(zoom * factor)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }

        switch event.charactersIgnoringModifiers ?? "" {
        case "+", "=":
            onZoomRequested?(zoom * 1.2)
        case "-", "_":
            onZoomRequested?(zoom / 1.2)
        default:
            super.keyDown(with: event)
        }
    }

    private func control(at point: NSPoint) -> Control? {
        if closeRect.contains(point) { return .close }
        if zoomInRect.contains(point) { return .zoomIn }
        if zoomOutRect.contains(point) { return .zoomOut }
        return nil
    }
}
