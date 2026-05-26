//
//  ScreenshotPreviewPanel.swift
//  Talkie
//
//  Floating thumbnail preview shown after a screenshot capture.
//  Appears near the tray (top-center). Draggable for file drop into any app.
//  Auto-dismisses after timeout, click to dismiss, right-click for options.
//

import AppKit
import TalkieKit

@MainActor
final class ScreenshotPreviewPanel {

    static let shared = ScreenshotPreviewPanel()
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var currentPreviewID: UUID?

    private let autoDismissDelay: TimeInterval = 5

    private init() {}

    /// Show a thumbnail preview of the captured image.
    /// `fileURL` enables drag-to-drop; pass the tray screenshot's tempURL.
    @discardableResult
    func show(image: CGImage, fileURL: URL? = nil) -> UUID {
        return show(
            thumbnail: image,
            sourceWidth: image.width,
            sourceHeight: image.height,
            fileURL: fileURL
        )
    }

    /// Show a pre-scaled thumbnail preview of the captured image.
    /// The full-resolution image should stay on disk; preview, drag, and movement use this light image.
    @discardableResult
    func show(thumbnail image: CGImage, sourceWidth: Int, sourceHeight: Int, fileURL: URL? = nil) -> UUID {
        dismiss()
        let previewID = UUID()
        currentPreviewID = previewID

        let nsImage = NSImage(cgImage: image, size: NSSize(
            width: image.width,
            height: image.height
        ))

        // Scale to a reasonable thumbnail size
        let maxWidth: CGFloat = 220
        let maxHeight: CGFloat = 160
        let metadataWidth = max(sourceWidth, 1)
        let metadataHeight = max(sourceHeight, 1)
        let aspect = CGFloat(metadataWidth) / CGFloat(metadataHeight)
        var thumbWidth = maxWidth
        var thumbHeight = thumbWidth / aspect
        if thumbHeight > maxHeight {
            thumbHeight = maxHeight
            thumbWidth = thumbHeight * aspect
        }

        let padding: CGFloat = 8
        let stripHeight: CGFloat = 18
        let panelWidth = thumbWidth + padding * 2
        let panelHeight = thumbHeight + padding * 2 + stripHeight

        // Position top-center, just below menu bar (near tray)
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let panelOrigin = NSPoint(
            x: screen.visibleFrame.midX - panelWidth / 2,
            y: screen.visibleFrame.maxY - panelHeight - 8
        )
        let panelFrame = NSRect(origin: panelOrigin, size: NSSize(width: panelWidth, height: panelHeight))

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.setFrame(panelFrame, display: false)
        } else {
            panel = makePanel(frame: panelFrame)
            self.panel = panel
        }

        let view = PreviewView(
            image: nsImage,
            thumbSize: NSSize(width: thumbWidth, height: thumbHeight),
            imageWidth: metadataWidth,
            imageHeight: metadataHeight,
            fileURL: fileURL,
            onDismiss: { [weak self] in self?.dismiss() },
            onCopy: { [weak self] currentFileURL in
                let pb = NSPasteboard.general
                pb.clearContents()
                if let currentFileURL,
                   let data = try? Data(contentsOf: currentFileURL) {
                    pb.setData(data, forType: .png)
                } else {
                    pb.writeObjects([nsImage])
                }
                self?.dismiss()
            },
            onAnnotate: { [weak self] url in
                self?.dismiss()
                CaptureMarkupCoordinator.shared.openSession(imageURL: url)
            }
        )
        view.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
        panel.contentView = view

        let richAnimationsEnabled = FeatureFlags.shared.enableCaptureRichUI
        if richAnimationsEnabled {
            let startFrame = panelFrame.offsetBy(dx: 0, dy: -6)
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(panelFrame, display: false)
            }
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.animateDismiss()
            }
        }

        return previewID
    }

    /// Attach a saved file URL to the current preview after async storage completes.
    func attachFileURL(_ fileURL: URL, to previewID: UUID? = nil) {
        if let previewID, previewID != currentPreviewID { return }
        guard let view = panel?.contentView as? PreviewView else { return }
        view.attachFileURL(fileURL)
    }

    /// Pre-create the preview panel so first capture avoids panel allocation on the hot path.
    func prewarmIfNeeded() {
        guard panel == nil else { return }
        let frame = NSRect(x: 0, y: 0, width: 120, height: 90)
        let panel = makePanel(frame: frame)
        panel.orderOut(nil)
        self.panel = panel
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        currentPreviewID = nil
        panel?.orderOut(nil)
    }

    private func animateDismiss() {
        guard let panel else { return }
        let richAnimationsEnabled = FeatureFlags.shared.enableCaptureRichUI
        let endFrame = richAnimationsEnabled ? panel.frame.offsetBy(dx: 0, dy: 4) : panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if richAnimationsEnabled {
                panel.animator().setFrame(endFrame, display: false)
            }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        })
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        return panel
    }
}

// MARK: - Preview View

private final class PreviewView: NSView, NSDraggingSource {

    private let image: NSImage
    private let thumbSize: NSSize
    private let imageWidth: Int
    private let imageHeight: Int
    private var fileURL: URL?
    private let onDismiss: () -> Void
    private let onCopy: (URL?) -> Void
    private let onAnnotate: (URL) -> Void
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var dragOrigin: NSPoint?
    private var annotateButton: NSButton?

    init(image: NSImage, thumbSize: NSSize, imageWidth: Int, imageHeight: Int,
         fileURL: URL?, onDismiss: @escaping () -> Void, onCopy: @escaping (URL?) -> Void,
         onAnnotate: @escaping (URL) -> Void) {
        self.image = image
        self.thumbSize = thumbSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileURL = fileURL
        self.onDismiss = onDismiss
        self.onCopy = onCopy
        self.onAnnotate = onAnnotate
        super.init(frame: .zero)
        configureAnnotateButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()

        let padding: CGFloat = 8
        let size: CGFloat = 24
        annotateButton?.frame = NSRect(
            x: padding + thumbSize.width - size - 6,
            y: padding + 6,
            width: size,
            height: size
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        // Pause auto-dismiss while hovering
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL, let origin = dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - origin.x, current.y - origin.y)

        // Only start drag after moving 4pt (distinguish from click)
        guard distance > 4 else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: fileURL))
        draggingItem.setDraggingFrame(
            NSRect(x: 0, y: 0, width: thumbSize.width, height: thumbSize.height),
            contents: image
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragOrigin = nil
    }

    override func mouseUp(with event: NSEvent) {
        // If we didn't drag, treat as click-to-dismiss
        if dragOrigin != nil {
            dragOrigin = nil
            onDismiss()
        }
    }

    // NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDismiss()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(copyAction), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        if fileURL != nil {
            let annotateItem = NSMenuItem(title: "Annotate…", action: #selector(annotateAction), keyEquivalent: "")
            annotateItem.target = self
            menu.addItem(annotateItem)
        }
        menu.addItem(.separator())
        let dismissItem = NSMenuItem(title: "Dismiss", action: #selector(dismissAction), keyEquivalent: "")
        dismissItem.target = self
        menu.addItem(dismissItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyAction() { onCopy(fileURL) }
    @objc private func dismissAction() { onDismiss() }
    @objc private func annotateAction() {
        guard let fileURL else { return }
        onAnnotate(fileURL)
    }

    func attachFileURL(_ fileURL: URL) {
        self.fileURL = fileURL
        configureAnnotateButton()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func configureAnnotateButton() {
        guard fileURL != nil else {
            annotateButton?.removeFromSuperview()
            annotateButton = nil
            return
        }

        if annotateButton == nil {
            let button = NSButton()
            button.image = NSImage(
                systemSymbolName: "sparkles.rectangle.stack",
                accessibilityDescription: "Annotate"
            )
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
            button.contentTintColor = NSColor.white.withAlphaComponent(0.86)
            button.toolTip = "Annotate"
            button.target = self
            button.action = #selector(annotateAction)
            addSubview(button)
            annotateButton = button
        }

        needsLayout = true
    }

    override func resetCursorRects() {
        if fileURL != nil {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let padding: CGFloat = 8
        let cornerRadius: CGFloat = 8
        let stripHeight: CGFloat = 18
        let imageRect = NSRect(
            x: padding, y: padding,
            width: thumbSize.width, height: thumbSize.height
        )
        let stripRect = NSRect(
            x: padding, y: padding + thumbSize.height,
            width: thumbSize.width, height: stripHeight
        )

        // Outer background
        let bgRect = bounds
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        ctx.saveGState()
        NSColor(white: 0.06, alpha: 0.94).setFill()
        bgPath.fill()
        ctx.restoreGState()

        // Image
        let imageCornerRadius: CGFloat = 5
        let imageClip = NSBezierPath(roundedRect: imageRect, xRadius: imageCornerRadius, yRadius: imageCornerRadius)
        ctx.saveGState()
        imageClip.addClip()
        NSColor(white: 0.1, alpha: 1).setFill()
        imageRect.fill()
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
        ctx.restoreGState()

        // Image border
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let imgBorder = NSBezierPath(roundedRect: imageRect, xRadius: imageCornerRadius, yRadius: imageCornerRadius)
        imgBorder.lineWidth = 0.5
        imgBorder.stroke()

        // Data strip
        NSColor(white: 0.06, alpha: 1).setFill()
        stripRect.fill()

        let meta = "\(imageWidth)×\(imageHeight)"
        let font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.35),
        ]
        let metaSize = meta.size(withAttributes: attrs)
        meta.draw(
            at: NSPoint(x: padding + 4, y: stripRect.minY + (stripHeight - metaSize.height) / 2),
            withAttributes: attrs
        )

        // Drag hint on right side of strip
        if fileURL != nil {
            let hint = "drag"
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.2),
            ]
            let hintSize = hint.size(withAttributes: hintAttrs)
            hint.draw(
                at: NSPoint(
                    x: stripRect.maxX - hintSize.width - 4,
                    y: stripRect.minY + (stripHeight - hintSize.height) / 2
                ),
                withAttributes: hintAttrs
            )
        }

        // Outer border
        let outerBorder = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.25, dy: 0.25), xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.white.withAlphaComponent(0.1).setStroke()
        outerBorder.lineWidth = 0.5
        outerBorder.stroke()

        // Hover overlay
        if isHovered {
            ctx.saveGState()
            imageClip.addClip()
            NSColor(white: 0, alpha: 0.25).setFill()
            imageRect.fill()
            ctx.restoreGState()
        }
    }
}
