//
//  AgentCaptureMarkupController.swift
//  TalkieAgent
//
//  Lightweight in-place screenshot markup for Agent-owned captures. This reuses
//  the live recording markup overlay, then bakes the resulting layers into the
//  captured PNG so the drag-out artifact is immediately shareable.
//

import AppKit
import ImageIO
import TalkieKit

@MainActor
final class AgentCaptureMarkupController {
    static let shared = AgentCaptureMarkupController()

    private let log = Log(.ui)
    private let dragPanel = FileDragPanel()
    private var overlay: LiveCaptureMarkupOverlayController?
    private var backgroundPanel: NSPanel?
    private var dragHandlePanel: NSPanel?
    private var dragExportURLs: [URL] = []

    private init() {}

    @discardableResult
    func open(fileURL: URL, captureRect: CGRect? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            log.warning("Agent capture markup skipped: screenshot file missing", detail: fileURL.path)
            return false
        }
        guard let sourceImage = Self.loadCGImage(at: fileURL) else {
            log.error("Agent capture markup skipped: unable to load image", detail: fileURL.path)
            return false
        }

        let item = AgentLiveTrayItem(
            id: UUID(),
            kind: .screenshot,
            capturedAt: Date(),
            filename: fileURL.lastPathComponent,
            width: sourceImage.width,
            height: sourceImage.height,
            captureMode: "markup",
            fileURL: fileURL
        )
        open(item: item, captureRect: captureRect, updatesLibrary: false)
        return true
    }

    func open(item: AgentLiveTrayItem, captureRect: CGRect? = nil) {
        open(item: item, captureRect: captureRect, updatesLibrary: true)
    }

    private func open(item: AgentLiveTrayItem, captureRect: CGRect?, updatesLibrary: Bool) {
        guard item.isScreenshot else { return }
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            log.warning("Agent capture markup skipped: screenshot file missing", detail: item.fileURL.path)
            return
        }
        guard let sourceImage = Self.loadCGImage(at: item.fileURL) else {
            log.error("Agent capture markup skipped: unable to load image", detail: item.fileURL.path)
            return
        }
        guard let placement = Self.placement(for: item, captureRect: captureRect) else {
            log.error("Agent capture markup skipped: no screen available")
            return
        }

        dismiss()
        showBackground(image: sourceImage, placement: placement)

        let overlay = LiveCaptureMarkupOverlayController()
        overlay.passthrough = false
        overlay.persistsLayersOnDone = false
        overlay.showsCaptureAction = false
        overlay.onDone = { [weak self] layers in
            self?.finish(item: item, sourceImage: sourceImage, layers: layers, updatesLibrary: updatesLibrary)
        }
        overlay.onCancel = { [weak self] in
            self?.cancel(item: item)
        }
        overlay.show(on: placement.screen, targetRect: placement.imageRect)
        overlay.setTool("ink")
        showDragHandle(
            item: item,
            sourceImage: sourceImage,
            frame: placement.surfaceRect
        )

        self.overlay = overlay
        log.info(
            "Agent quick markup opened",
            detail: "file=\(item.fileURL.lastPathComponent) imageRect=\(Int(placement.imageRect.width))x\(Int(placement.imageRect.height))"
        )
    }

    func dismiss() {
        overlay?.dismiss(discardLayers: true)
        overlay = nil
        hideDragHandle()
        hideBackground()
        cleanupDragExports()
    }

    private func finish(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        layers: [CaptureMarkupLayer],
        updatesLibrary: Bool
    ) {
        hideBackground()
        hideDragHandle()
        overlay = nil

        Task { @MainActor in
            await bakeIfNeeded(
                item: item,
                sourceImage: sourceImage,
                layers: layers,
                updatesLibrary: updatesLibrary
            )
            dragPanel.show(item: item)
        }
    }

    private func cancel(item: AgentLiveTrayItem) {
        hideBackground()
        hideDragHandle()
        overlay = nil
        log.info("Agent quick markup cancelled", detail: item.fileURL.lastPathComponent)
    }

    private func bakeIfNeeded(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        layers: [CaptureMarkupLayer],
        updatesLibrary: Bool
    ) async {
        guard !layers.isEmpty else {
            log.info("Agent quick markup finished without layers", detail: item.fileURL.lastPathComponent)
            return
        }

        let document = CaptureMarkupDocument(
            imageWidth: Double(sourceImage.width),
            imageHeight: Double(sourceImage.height),
            layers: layers
        )

        let data = await Task.detached(priority: .userInitiated) {
            CaptureMarkupRenderer.encodedData(
                image: sourceImage,
                document: document,
                format: .png,
                scale: 1
            )
        }.value

        guard let data else {
            log.error("Agent quick markup bake failed", detail: item.fileURL.lastPathComponent)
            return
        }

        do {
            try data.write(to: item.fileURL, options: .atomic)
            CaptureMarkupStorage.deleteSidecar(forImageURL: item.fileURL)
            if updatesLibrary {
                AgentCaptureLibraryWriter.persistScreenshot(
                    data: data,
                    id: item.id,
                    capturedAt: item.capturedAt,
                    captureMode: item.captureMode,
                    width: sourceImage.width,
                    height: sourceImage.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    appBundleID: item.appBundleID,
                    displayName: item.displayName,
                    ocrText: item.ocrText
                )
                Self.postAssetsDidChange()
            }
            log.info(
                "Agent quick markup saved",
                detail: "file=\(item.fileURL.lastPathComponent) layers=\(layers.count)"
            )
        } catch {
            log.error("Agent quick markup save failed: \(error.localizedDescription)", detail: item.fileURL.path)
        }
    }

    private func showBackground(image: CGImage, placement: AgentCaptureMarkupPlacement) {
        let view = AgentCaptureMarkupBackgroundView(
            image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            imageRect: NSRect(
                x: placement.imageRect.minX - placement.surfaceRect.minX,
                y: placement.imageRect.minY - placement.surfaceRect.minY,
                width: placement.imageRect.width,
                height: placement.imageRect.height
            ),
            onDragDelta: { [weak self] delta in
                self?.moveSurface(by: delta)
            },
            onDone: { [weak self] in
                self?.overlay?.finish()
            },
            onCancel: { [weak self] in
                self?.overlay?.cancel()
            }
        )
        view.frame = NSRect(origin: .zero, size: placement.surfaceRect.size)

        let panel = AgentCaptureMarkupBackgroundPanel(
            contentRect: placement.surfaceRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.setFrameOrigin(placement.surfaceRect.origin)
        panel.orderFrontRegardless()
        backgroundPanel = panel
    }

    private func moveSurface(by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        Self.move(backgroundPanel, by: delta)
        overlay?.moveBy(delta)
        Self.move(dragHandlePanel, by: delta)
    }

    private static func move(_ panel: NSPanel?, by delta: CGSize) {
        guard let panel else { return }
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + delta.width,
            y: panel.frame.minY + delta.height
        ))
    }

    private func hideBackground() {
        backgroundPanel?.orderOut(nil)
        backgroundPanel?.contentView = nil
        backgroundPanel = nil
    }

    private func showDragHandle(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        frame: CGRect
    ) {
        hideDragHandle()

        let size = NSSize(width: 132, height: 34)
        let handleFrame = NSRect(
            x: (frame.midX - size.width / 2).rounded(),
            y: (frame.minY + 14).rounded(),
            width: size.width,
            height: size.height
        )
        let view = AgentCaptureMarkupDragHandleView(
            fileURLProvider: { [weak self] in
                self?.dragURL(item: item, sourceImage: sourceImage)
            }
        )
        view.frame = NSRect(origin: .zero, size: size)

        let panel = AgentCaptureMarkupDragHandlePanel(
            contentRect: handleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none
        panel.orderFrontRegardless()
        dragHandlePanel = panel
    }

    private func hideDragHandle() {
        dragHandlePanel?.orderOut(nil)
        dragHandlePanel?.contentView = nil
        dragHandlePanel = nil
    }

    private func dragURL(item: AgentLiveTrayItem, sourceImage: CGImage) -> URL? {
        let layers = overlay?.layers ?? []
        guard !layers.isEmpty else { return item.fileURL }

        let document = CaptureMarkupDocument(
            imageWidth: Double(sourceImage.width),
            imageHeight: Double(sourceImage.height),
            layers: layers
        )
        guard let data = CaptureMarkupRenderer.encodedData(
            image: sourceImage,
            document: document,
            format: .png,
            scale: 1
        ) else {
            log.error("Agent quick markup drag render failed", detail: item.fileURL.lastPathComponent)
            return item.fileURL
        }

        let base = item.fileURL.deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-markup-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            dragExportURLs.append(url)
            return url
        } catch {
            log.error("Agent quick markup drag write failed: \(error.localizedDescription)", detail: url.path)
            return item.fileURL
        }
    }

    private func cleanupDragExports() {
        for url in dragExportURLs {
            try? FileManager.default.removeItem(at: url)
        }
        dragExportURLs.removeAll(keepingCapacity: false)
    }

    private static func placement(
        for item: AgentLiveTrayItem,
        captureRect: CGRect?
    ) -> AgentCaptureMarkupPlacement? {
        let screen = screen(for: captureRect)
            ?? screen(containing: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let imageSize = CGSize(width: max(1, item.width), height: max(1, item.height))
        if let rect = usableInPlaceRect(captureRect, on: screen),
           let exactPlacement = exactInPlacePlacement(imageRect: rect, on: screen) {
            return exactPlacement
        }

        let preferredCenter = captureRect.map { NSPoint(x: $0.midX, y: $0.midY) }
        let surfaceRect = fittedPreviewRect(
            imageSize: imageSize,
            on: screen,
            preferredCenter: preferredCenter
        )
        let imageRect = aspectFitRect(
            imageSize: imageSize,
            in: contentRect(in: surfaceRect)
        )
        return AgentCaptureMarkupPlacement(screen: screen, surfaceRect: surfaceRect, imageRect: imageRect)
    }

    private static func usableInPlaceRect(_ rect: CGRect?, on screen: NSScreen) -> CGRect? {
        guard let rect = rect?.standardized,
              rect.width >= 420,
              rect.height >= 260 else {
            return nil
        }
        let clipped = rect.intersection(screen.frame)
        guard !clipped.isNull, clipped.width >= 420, clipped.height >= 260 else { return nil }
        return clipped
    }

    private static func exactInPlacePlacement(
        imageRect: CGRect,
        on screen: NSScreen
    ) -> AgentCaptureMarkupPlacement? {
        let safe = screen.frame.insetBy(dx: 4, dy: 4)
        let surfaceRect = CGRect(
            x: imageRect.minX - AgentCaptureMarkupLayout.edgePadding,
            y: imageRect.minY - AgentCaptureMarkupLayout.edgePadding,
            width: imageRect.width + AgentCaptureMarkupLayout.edgePadding * 2,
            height: imageRect.height + AgentCaptureMarkupLayout.edgePadding * 2 + AgentCaptureMarkupLayout.titlebarHeight
        )

        guard safe.contains(surfaceRect) else { return nil }
        return AgentCaptureMarkupPlacement(
            screen: screen,
            surfaceRect: surfaceRect,
            imageRect: imageRect
        )
    }

    private static func fittedPreviewRect(
        imageSize: CGSize,
        on screen: NSScreen,
        preferredCenter: NSPoint?
    ) -> CGRect {
        let visible = screen.visibleFrame.insetBy(dx: 22, dy: 44)
        let ratio = max(0.05, imageSize.width / max(1, imageSize.height))
        let maxWidth = min(1100, visible.width)
        let maxHeight = min(760, visible.height)

        let chromeWidth = AgentCaptureMarkupLayout.edgePadding * 2
        let chromeHeight = AgentCaptureMarkupLayout.edgePadding * 2 + AgentCaptureMarkupLayout.titlebarHeight
        let maxImageWidth = max(1, maxWidth - chromeWidth)
        let maxImageHeight = max(1, maxHeight - chromeHeight)
        var imageWidth = maxImageWidth
        var imageHeight = imageWidth / ratio
        if imageHeight > maxImageHeight {
            imageHeight = maxImageHeight
            imageWidth = imageHeight * ratio
        }

        imageWidth = min(max(imageWidth, min(420, maxImageWidth)), maxImageWidth)
        imageHeight = min(max(imageHeight, min(260, maxImageHeight)), maxImageHeight)

        let width = min(maxWidth, imageWidth + chromeWidth)
        let height = min(maxHeight, imageHeight + chromeHeight)

        let center = preferredCenter ?? NSPoint(x: visible.midX, y: visible.midY)
        let x = clamp(center.x - width / 2, min: visible.minX, max: visible.maxX - width)
        let y = clamp(center.y - height / 2, min: visible.minY, max: visible.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    private static func contentRect(in surfaceRect: CGRect) -> CGRect {
        CGRect(
            x: surfaceRect.minX + AgentCaptureMarkupLayout.edgePadding,
            y: surfaceRect.minY + AgentCaptureMarkupLayout.edgePadding,
            width: max(1, surfaceRect.width - AgentCaptureMarkupLayout.edgePadding * 2),
            height: max(1, surfaceRect.height - AgentCaptureMarkupLayout.edgePadding * 2 - AgentCaptureMarkupLayout.titlebarHeight)
        )
    }

    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        let ratio = max(0.05, imageSize.width / max(1, imageSize.height))
        var width = rect.width
        var height = width / ratio
        if height > rect.height {
            height = rect.height
            width = height * ratio
        }
        return CGRect(
            x: (rect.midX - width / 2).rounded(),
            y: (rect.midY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private static func screen(for rect: CGRect?) -> NSScreen? {
        guard let rect, rect.width > 1, rect.height > 1 else { return nil }
        let midpoint = NSPoint(x: rect.midX, y: rect.midY)
        return screen(containing: midpoint)
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func loadCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private static func postAssetsDidChange() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(LiveTrayNotifications.assetsDidChange),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

private final class AgentCaptureMarkupBackgroundPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AgentCaptureMarkupPlacement {
    let screen: NSScreen
    let surfaceRect: CGRect
    let imageRect: CGRect
}

private enum AgentCaptureMarkupLayout {
    static let titlebarHeight: CGFloat = 34
    static let edgePadding: CGFloat = 8
}

private final class AgentCaptureMarkupDragHandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class AgentCaptureMarkupBackgroundView: NSView {
    private let image: NSImage
    private let imageRect: NSRect
    private let onDragDelta: (CGSize) -> Void
    private let onDone: () -> Void
    private let onCancel: () -> Void
    private var lastDragScreenPoint: NSPoint?

    init(
        image: NSImage,
        imageRect: NSRect,
        onDragDelta: @escaping (CGSize) -> Void,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.imageRect = imageRect
        self.onDragDelta = onDragDelta
        self.onDone = onDone
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(dragRegion, cursor: .openHand)
        addCursorRect(doneButtonRect, cursor: .pointingHand)
        addCursorRect(cancelButtonRect, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if doneButtonRect.contains(point) {
            onDone()
            return
        }
        if cancelButtonRect.contains(point) {
            onCancel()
            return
        }
        guard dragRegion.contains(point) else {
            lastDragScreenPoint = nil
            return
        }
        lastDragScreenPoint = screenPoint(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragScreenPoint,
              let current = screenPoint(for: event) else {
            return
        }
        lastDragScreenPoint = current
        onDragDelta(CGSize(width: current.x - last.x, height: current.y - last.y))
    }

    override func mouseUp(with event: NSEvent) {
        lastDragScreenPoint = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let shell = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.055, alpha: 0.98).setFill()
        shell.fill()

        let titleRect = NSRect(
            x: 0,
            y: bounds.maxY - AgentCaptureMarkupLayout.titlebarHeight,
            width: bounds.width,
            height: AgentCaptureMarkupLayout.titlebarHeight
        )
        NSColor(calibratedWhite: 0.075, alpha: 0.98).setFill()
        titleRect.fill()

        drawBrand(in: titleRect)
        drawChromeButtons()

        let imageClip = NSBezierPath(roundedRect: imageRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        imageClip.addClip()
        NSColor.black.setFill()
        imageRect.fill()
        image.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let imageBorder = NSBezierPath(roundedRect: imageRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        imageBorder.lineWidth = 1
        imageBorder.stroke()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        let shellBorder = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        shellBorder.lineWidth = 1
        shellBorder.stroke()
    }

    private func drawBrand(in rect: NSRect) {
        let markRect = NSRect(x: 12, y: rect.midY - 6, width: 12, height: 12)
        let mark = NSBezierPath(roundedRect: markRect, xRadius: 3, yRadius: 3)
        NSColor(calibratedRed: 0.49, green: 0.55, blue: 1.0, alpha: 0.96).setFill()
        mark.fill()

        let dotColor = NSColor.white.withAlphaComponent(0.9)
        dotColor.setFill()
        for row in 0..<2 {
            for column in 0..<2 {
                let dot = NSRect(
                    x: markRect.minX + 3 + CGFloat(column) * 4,
                    y: markRect.minY + 3 + CGFloat(row) * 4,
                    width: 2,
                    height: 2
                )
                NSBezierPath(ovalIn: dot).fill()
            }
        }

        let title = "Talkie Markup"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
        ]
        (title as NSString).draw(
            at: NSPoint(x: markRect.maxX + 8, y: rect.midY - 7),
            withAttributes: attrs
        )

        let hint = "drag bezel to move"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.42),
        ]
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
        (hint as NSString).draw(
            at: NSPoint(x: max(markRect.maxX + 110, cancelButtonRect.minX - hintSize.width - 12), y: rect.midY - 6),
            withAttributes: hintAttrs
        )
    }

    private func drawChromeButtons() {
        drawButton(
            rect: doneButtonRect,
            title: "Done",
            foreground: NSColor.white.withAlphaComponent(0.92),
            fill: NSColor(calibratedRed: 0.38, green: 0.47, blue: 1.0, alpha: 0.84),
            border: NSColor.white.withAlphaComponent(0.20)
        )
        drawButton(
            rect: cancelButtonRect,
            title: "Esc / X",
            foreground: NSColor.white.withAlphaComponent(0.78),
            fill: NSColor.white.withAlphaComponent(0.08),
            border: NSColor.white.withAlphaComponent(0.14)
        )
    }

    private func drawButton(
        rect: NSRect,
        title: String,
        foreground: NSColor,
        fill: NSColor,
        border: NSColor
    ) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: foreground,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private var dragRegion: NSRect {
        let title = titleRect
        return NSRect(
            x: title.minX,
            y: title.minY,
            width: max(1, doneButtonRect.minX - title.minX - 8),
            height: title.height
        )
    }

    private var titleRect: NSRect {
        NSRect(
            x: 0,
            y: bounds.maxY - AgentCaptureMarkupLayout.titlebarHeight,
            width: bounds.width,
            height: AgentCaptureMarkupLayout.titlebarHeight
        )
    }

    private var doneButtonRect: NSRect {
        NSRect(
            x: max(12, bounds.maxX - 150),
            y: bounds.maxY - 27,
            width: 58,
            height: 21
        )
    }

    private var cancelButtonRect: NSRect {
        NSRect(
            x: max(12, bounds.maxX - 86),
            y: bounds.maxY - 27,
            width: 62,
            height: 21
        )
    }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }
}

private final class AgentCaptureMarkupDragHandleView: NSView {
    private let fileURLProvider: () -> URL?
    private let dragSource = FileDragSourceDelegate()

    init(fileURLProvider: @escaping () -> URL?) {
        self.fileURLProvider = fileURLProvider
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = "DRAG COPY"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.48, alpha: 0.96),
            .kern: 0.8,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.midX - size.width / 2).rounded(),
            y: (bounds.midY - size.height / 2).rounded()
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard let url = fileURLProvider(),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let dragImage = Self.thumbnail(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        draggingItem.setDraggingFrame(
            NSRect(origin: .zero, size: dragImage.size),
            contents: dragImage
        )
        beginDraggingSession(with: [draggingItem], event: event, source: dragSource)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    private static func thumbnail(for url: URL, maxSize: CGFloat = 180) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
