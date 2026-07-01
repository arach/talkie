//
//  CaptureIslandController.swift
//  TalkieAgent
//
//  Agent-owned "island" at the top of the active display: when a capture
//  (screenshot or clip) lands in the live tray, it surfaces a draggable
//  preview you can drag straight into any app. Works on external displays
//  (no physical notch required) since it positions itself at top-center.
//
//  This is the minimal recreation that replaces the legacy Talkie notch
//  island. Capture review uses Agent's lightweight in-place markup surface.
//

import AppKit
import TalkieKit

@MainActor
final class CaptureIslandController {
    static let shared = CaptureIslandController()

    private var panel: NSPanel?
    private var assetsObserver: NSObjectProtocol?
    private var dismissTimer: Timer?
    private var shownItemID: UUID?

    private let panelWidth: CGFloat = 188
    private let panelHeight: CGFloat = 132

    /// User toggle (agent-local). Defaults on.
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: CaptureIslandDefaults.enabled) as? Bool ?? true
    }

    private var dismissSeconds: Double {
        let stored = UserDefaults.standard.object(forKey: CaptureIslandDefaults.dismissSeconds) as? Double
        return max(2, stored ?? 6)
    }

    private var placement: CaptureIslandPlacement {
        TalkieSharedSettings.string(forKey: CaptureIslandDefaults.placement)
            .flatMap(CaptureIslandPlacement.init(rawValue:))
            ?? .contextual
    }

    func initialize() {
        guard assetsObserver == nil else { return }
        // The store posts assetsDidChange (distributed) on every tray mutation,
        // including the agent's own writes — so we receive our own captures here.
        assetsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(LiveTrayNotifications.assetsDidChange),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAssetsChanged()
            }
        }
    }

    private func handleAssetsChanged() {
        guard isEnabled else { return }
        Task { @MainActor in
            let items = await AgentLiveTrayAssetStore.shared.recentItems(limit: 1)
            guard let latest = items.first else { return }
            // Only react to a genuinely fresh capture, not unrelated tray edits
            // (pin toggles, deletions). assetsDidChange carries no payload, so
            // gate on recency + de-dupe by id.
            guard latest.id != shownItemID else { return }
            guard isFreshForPresentation(latest) else { return }
            present(latest, near: nil)
        }
    }

    private func isFreshForPresentation(_ item: AgentLiveTrayItem) -> Bool {
        let now = Date()
        if now.timeIntervalSince(item.capturedAt) < 5 {
            return true
        }

        guard item.isClip else { return false }
        let values = try? item.fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
        ])
        guard let savedAt = values?.contentModificationDate ?? values?.creationDate else {
            return false
        }

        return now.timeIntervalSince(savedAt) < max(8, dismissSeconds + 2)
    }

    func presentImmediate(_ item: AgentLiveTrayItem, near anchor: NSPoint?) {
        guard isEnabled else { return }
        guard isFreshForPresentation(item) else { return }
        present(item, near: placement == .contextual ? anchor : nil)
    }

    private func present(_ item: AgentLiveTrayItem, near anchor: NSPoint?) {
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else { return }
        shownItemID = item.id
        dismiss(animated: false)

        let view = CaptureIslandView(
            item: item,
            onDragEnded: { [weak self] in self?.dismiss() },
            onDelete: { [weak self] item in self?.delete(item) },
            onOpen: { [weak self] item in self?.open(item) },
            onActivate: { [weak self] item in self?.open(item) },
            onDismiss: { [weak self] in self?.dismiss() },
            onHoverChanged: { [weak self] hovering in
                if hovering { self?.cancelDismissTimer() } else { self?.scheduleDismiss() }
            }
        )
        view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = view
        p.isFloatingPanel = true
        p.level = .screenSaver + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.sharingType = .none

        position(p, near: anchor)

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            p.animator().alphaValue = 1
        }
        panel = p
        scheduleDismiss()
    }

    private func position(_ p: NSPanel, near anchor: NSPoint?) {
        if let anchor {
            position(p, around: anchor)
            return
        }

        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panelWidth / 2
        let y = visible.maxY - panelHeight - 6  // tucked just under the menu bar
        p.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func position(_ p: NSPanel, around anchor: NSPoint) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) })
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let gap: CGFloat = 14
        var x = anchor.x + gap
        var y = anchor.y - panelHeight - gap

        if x + panelWidth > visible.maxX {
            x = anchor.x - panelWidth - gap
        }
        if y < visible.minY {
            y = anchor.y + gap
        }

        x = min(max(x, visible.minX + gap), visible.maxX - panelWidth - gap)
        y = min(max(y, visible.minY + gap), visible.maxY - panelHeight - gap)
        p.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func scheduleDismiss() {
        cancelDismissTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    func dismiss(animated: Bool = true) {
        cancelDismissTimer()
        guard let p = panel else { return }
        panel = nil
        guard animated else {
            p.orderOut(nil)
            p.contentView = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.contentView = nil
        })
    }

    private func delete(_ item: AgentLiveTrayItem) {
        cancelDismissTimer()
        Task { [weak self] in
            guard let self else { return }
            let deleted = await AgentLiveTrayAssetStore.shared.deleteItem(item)
            if deleted {
                self.dismiss()
            } else {
                self.scheduleDismiss()
            }
        }
    }

    private func open(_ item: AgentLiveTrayItem) {
        if item.isClip {
            cancelDismissTimer()
            AgentCaptureClipPreviewController.shared.open(item: item)
            dismiss()
            return
        }

        guard supportsCaptureMarkup(item) else {
            scheduleDismiss()
            return
        }
        cancelDismissTimer()

        AgentCaptureMarkupController.shared.open(item: item)
        dismiss()
    }
}

enum CaptureIslandDefaults {
    static let enabled = "agent.captureIsland.enabled"
    static let dismissSeconds = "agent.captureIsland.dismissSeconds"
    static let placement = AgentSettingsKey.captureIslandPlacement
}

// MARK: - Island View (pure AppKit for reliable drag-out)

private final class CaptureIslandView: NSView {
    private let item: AgentLiveTrayItem
    private let onDragEnded: () -> Void
    private let onDelete: (AgentLiveTrayItem) -> Void
    private let onOpen: (AgentLiveTrayItem) -> Void
    private let onActivate: (AgentLiveTrayItem) -> Void
    private let onDismiss: () -> Void
    private let onHoverChanged: (Bool) -> Void
    private let dragSource = FileDragSourceDelegate()
    private let thumbnail: NSImage
    /// Press origin in view coords; a click that never drifts past the slop is a
    /// tap (opens the capture) rather than the start of a drag-out.
    private var pressOrigin: NSPoint?
    private var didBeginDrag = false
    private var swipeAccumulator = CGSize.zero

    private let cornerRadius: CGFloat = 12
    private let inset: CGFloat = 8
    private let stripHeight: CGFloat = 22
    private let actionButtonSize: CGFloat = 18
    private let openButton: NSButton
    private let deleteButton: NSButton

    init(
        item: AgentLiveTrayItem,
        onDragEnded: @escaping () -> Void,
        onDelete: @escaping (AgentLiveTrayItem) -> Void,
        onOpen: @escaping (AgentLiveTrayItem) -> Void,
        onActivate: @escaping (AgentLiveTrayItem) -> Void,
        onDismiss: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.item = item
        self.onDragEnded = onDragEnded
        self.onDelete = onDelete
        self.onOpen = onOpen
        self.onActivate = onActivate
        self.onDismiss = onDismiss
        self.onHoverChanged = onHoverChanged
        self.thumbnail = item.image ?? NSWorkspace.shared.icon(forFile: item.fileURL.path)
        openButton = Self.makeActionButton(
            symbol: item.isClip ? "play.rectangle" : "pencil.tip.crop.circle",
            toolTip: item.isClip ? "Preview" : "Markup",
            action: #selector(openCapture(_:)),
            tint: NSColor.white.withAlphaComponent(0.82)
        )
        deleteButton = Self.makeActionButton(
            symbol: "trash",
            toolTip: "Delete",
            action: #selector(deleteCapture(_:)),
            tint: NSColor.systemRed.withAlphaComponent(0.78)
        )
        super.init(frame: .zero)
        wantsLayer = true
        openButton.target = self
        deleteButton.target = self
        openButton.isEnabled = item.isClip || supportsCaptureMarkup(item)
        addSubview(openButton)
        addSubview(deleteButton)
        dragSource.onEnd = { [weak self] in self?.onDragEnded() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let size = actionButtonSize
        let originY = inset + (stripHeight - size) / 2
        let edgeInset: CGFloat = 2
        deleteButton.frame = NSRect(
            x: inset + edgeInset,
            y: originY,
            width: size,
            height: size
        )
        openButton.frame = NSRect(
            x: bounds.width - inset - edgeInset - size,
            y: originY,
            width: size,
            height: size
        )
    }

    private static func makeActionButton(symbol: String, toolTip: String, action: Selector, tint: NSColor) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.contentTintColor = tint
        button.toolTip = toolTip
        button.action = action
        return button
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    override func resetCursorRects() {
        addCursorRect(thumbRect, cursor: .openHand)
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss()
    }

    private var thumbRect: NSRect {
        NSRect(
            x: inset,
            y: inset + stripHeight,
            width: bounds.width - inset * 2,
            height: bounds.height - inset * 2 - stripHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.07, alpha: 0.96).setFill()
        bg.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        border.lineWidth = 1
        border.stroke()

        // Thumbnail - soft halo so a fresh capture reads on dark UI behind it
        let tRect = thumbRect
        let thumbCornerRadius: CGFloat = 7
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setShadow(
                offset: .zero,
                blur: 5,
                color: NSColor.white.withAlphaComponent(0.20).cgColor
            )
            let halo = NSBezierPath(
                roundedRect: tRect.insetBy(dx: -0.5, dy: -0.5),
                xRadius: thumbCornerRadius + 0.5,
                yRadius: thumbCornerRadius + 0.5
            )
            NSColor.white.withAlphaComponent(0.06).setFill()
            halo.fill()
            ctx.restoreGState()
        }

        let clip = NSBezierPath(roundedRect: tRect, xRadius: thumbCornerRadius, yRadius: thumbCornerRadius)
        NSGraphicsContext.current?.saveGraphicsState()
        clip.addClip()
        NSColor(white: 0.13, alpha: 1).setFill()
        NSBezierPath(rect: tRect).fill()
        drawAspectFit(thumbnail, in: tRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        let thumbBorder = NSBezierPath(roundedRect: tRect, xRadius: thumbCornerRadius, yRadius: thumbCornerRadius)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        thumbBorder.lineWidth = 0.75
        thumbBorder.stroke()

        // Bottom bezel
        NSGraphicsContext.current?.saveGraphicsState()
        let stripRect = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: stripHeight)
        NSBezierPath(rect: stripRect).setClip()
        NSColor(white: 0.06, alpha: 1).setFill()
        stripRect.fill()

        let label = "\(item.isClip ? "CLIP" : "SHOT")  \(item.width)×\(item.height)"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let actionReserve = actionButtonSize + 8
        let availableLabelWidth = stripRect.width - actionReserve * 2
        if labelSize.width <= availableLabelWidth {
            (label as NSString).draw(
                at: NSPoint(
                    x: stripRect.midX - labelSize.width / 2,
                    y: stripRect.minY + (stripHeight - labelSize.height) / 2
                ),
                withAttributes: labelAttrs
            )
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawAspectFit(_ image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = NSPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
        image.draw(in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onDismiss()
            return
        }

        // The whole card is interactive. Don't commit to a drag yet —
        // wait to see whether the pointer drifts (drag-out) or stays put (tap).
        let point = convert(event.locationInWindow, from: nil)
        pressOrigin = bounds.contains(point) ? point : nil
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin, !didBeginDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        guard hypot(delta.width, delta.height) >= 4 else { return }

        if !thumbRect.contains(origin) {
            if abs(delta.width) >= 44, abs(delta.width) > abs(delta.height) * 1.35 {
                pressOrigin = nil
                onDismiss()
            }
            return
        }

        didBeginDrag = true
        let draggingItem = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: item.fileURL))
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: thumbRect.size), contents: thumbnail)
        beginDraggingSession(with: [draggingItem], event: event, source: dragSource)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressOrigin = nil; didBeginDrag = false }
        guard !didBeginDrag, pressOrigin != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard thumbRect.contains(point) else { return }
        // A tap (no drag): open the capture in its lightweight review surface.
        onActivate(item)
    }

    override func scrollWheel(with event: NSEvent) {
        swipeAccumulator.width += event.scrollingDeltaX
        swipeAccumulator.height += event.scrollingDeltaY
        let horizontal = abs(swipeAccumulator.width)
        let vertical = abs(swipeAccumulator.height)
        if horizontal >= 22, horizontal > vertical * 1.4 {
            swipeAccumulator = .zero
            onDismiss()
            return
        }
        if vertical > horizontal * 1.8 || horizontal > 80 {
            swipeAccumulator = .zero
        }
    }

    @objc private func openCapture(_ sender: Any) {
        onOpen(item)
    }

    @objc private func deleteCapture(_ sender: Any) {
        onDelete(item)
    }
}

private func supportsCaptureMarkup(_ item: AgentLiveTrayItem) -> Bool {
    guard !item.isClip else { return false }
    if item.isScreenshot { return true }
    return ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif"]
        .contains(item.fileURL.pathExtension.lowercased())
}
