//
//  AgentCaptureClipPreviewController.swift
//  TalkieAgent
//
//  Lightweight review surface for Agent-owned screen clips.
//

import AppKit
import AVKit
import TalkieKit

@MainActor
final class AgentCaptureClipPreviewController: NSObject, NSWindowDelegate {
    static let shared = AgentCaptureClipPreviewController()

    private var panel: AgentClipPreviewPanel?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?

    func open(item: AgentLiveTrayItem) {
        guard item.isClip,
              FileManager.default.fileExists(atPath: item.fileURL.path) else {
            return
        }

        dismiss()

        let player = AVPlayer(url: item.fileURL)
        let playerView = AVPlayerView(frame: .zero)
        playerView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.player = player

        let frame = Self.previewFrame(for: item)
        let panel = AgentClipPreviewPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = item.displayName ?? item.filename
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = AgentClipPreviewFrameView(item: item, playerView: playerView) { [weak self] in
            self?.dismiss()
        }
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 420, height: 300)
        panel.setFrame(frame, display: false)
        panel.center()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        self.panel = panel
        self.player = player
        panel.orderFrontRegardless()
        panel.makeKey()
        player.play()
    }

    func dismiss() {
        player?.pause()
        player = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        panel?.delegate = nil
        panel?.onDismiss = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }

    private static func previewFrame(for item: AgentLiveTrayItem) -> NSRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700))
            .insetBy(dx: 24, dy: 24)
        let ratio = max(0.2, CGFloat(item.width) / max(1, CGFloat(item.height)))
        let maxWidth = min(820, visible.width)
        let maxHeight = min(600, visible.height)
        let chromeWidth = AgentClipPreviewFrameView.contentInset * 2
        let chromeHeight = AgentClipPreviewFrameView.titlebarHeight
            + AgentClipPreviewFrameView.footerHeight
            + AgentClipPreviewFrameView.contentInset * 2
        let maxPlayerWidth = max(320, maxWidth - chromeWidth)
        let maxPlayerHeight = max(200, maxHeight - chromeHeight)

        var playerWidth = min(maxPlayerWidth, max(460, visible.width * 0.58))
        var playerHeight = playerWidth / ratio
        if playerHeight > maxPlayerHeight {
            playerHeight = maxPlayerHeight
            playerWidth = playerHeight * ratio
        }
        playerWidth = min(max(360, playerWidth), maxPlayerWidth)
        playerHeight = min(max(220, playerHeight), maxPlayerHeight)

        let width = playerWidth + chromeWidth
        let height = playerHeight + chromeHeight
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private final class AgentClipPreviewPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

private final class AgentClipPreviewFrameView: NSView {
    static let titlebarHeight: CGFloat = 36
    static let footerHeight: CGFloat = 40
    static let contentInset: CGFloat = 12

    private let item: AgentLiveTrayItem
    private let playerView: AVPlayerView
    private let playerContainer = NSView()
    private let closeButton = NSButton()
    private let dragHandle: AgentClipPreviewDragHandleView
    private let onClose: () -> Void

    private var titlebarRect: NSRect {
        NSRect(
            x: 0,
            y: bounds.maxY - Self.titlebarHeight,
            width: bounds.width,
            height: Self.titlebarHeight
        )
    }

    private var footerRect: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.footerHeight)
    }

    init(item: AgentLiveTrayItem, playerView: AVPlayerView, onClose: @escaping () -> Void) {
        self.item = item
        self.playerView = playerView
        self.onClose = onClose
        self.dragHandle = AgentClipPreviewDragHandleView(item: item)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false

        playerContainer.wantsLayer = true
        playerContainer.layer?.cornerRadius = 8
        playerContainer.layer?.masksToBounds = true
        playerContainer.layer?.backgroundColor = NSColor.black.cgColor
        playerContainer.addSubview(playerView)
        addSubview(playerContainer)

        closeButton.title = "x"
        closeButton.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 5
        closeButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.88).cgColor
        closeButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
        closeButton.layer?.borderWidth = 1
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.84)
        closeButton.attributedTitle = NSAttributedString(
            string: "x",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.84),
            ]
        )
        closeButton.toolTip = "Close"
        closeButton.target = self
        closeButton.action = #selector(closePreview(_:))
        addSubview(closeButton)
        addSubview(dragHandle)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        closeButton.frame = NSRect(
            x: 9,
            y: bounds.maxY - Self.titlebarHeight + (Self.titlebarHeight - 20) / 2,
            width: 20,
            height: 20
        )

        let dragWidth: CGFloat = min(108, max(88, bounds.width * 0.22))
        dragHandle.frame = NSRect(
            x: bounds.maxX - dragWidth - 12,
            y: (Self.footerHeight - 24) / 2,
            width: dragWidth,
            height: 24
        )

        let playerFrame = NSRect(
            x: Self.contentInset,
            y: Self.footerHeight + Self.contentInset,
            width: max(1, bounds.width - Self.contentInset * 2),
            height: max(1, bounds.height - Self.titlebarHeight - Self.footerHeight - Self.contentInset * 2)
        )
        playerContainer.frame = playerFrame
        playerView.frame = playerContainer.bounds
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if titlebarRect.contains(point) || footerRect.contains(point) {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let shell = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.052, alpha: 0.98).setFill()
        shell.fill()

        NSGraphicsContext.saveGraphicsState()
        shell.addClip()
        NSColor(calibratedWhite: 0.074, alpha: 0.98).setFill()
        titlebarRect.fill()
        NSColor(calibratedWhite: 0.064, alpha: 0.98).setFill()
        footerRect.fill()
        drawChromeRelief(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        drawSeparators()
        drawTitle()
        drawFooterMetadata()

        let playerBorder = NSBezierPath(
            roundedRect: playerContainer.frame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 8,
            yRadius: 8
        )
        NSColor.white.withAlphaComponent(0.14).setStroke()
        playerBorder.lineWidth = 1
        playerBorder.stroke()

        let shellBorder = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 12,
            yRadius: 12
        )
        NSColor.white.withAlphaComponent(0.13).setStroke()
        shellBorder.lineWidth = 1
        shellBorder.stroke()
    }

    private func drawTitle() {
        let markRect = NSRect(x: closeButton.frame.maxX + 10, y: titlebarRect.midY - 8, width: 16, height: 16)
        let mark = NSBezierPath(roundedRect: markRect, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.09, alpha: 0.88).setFill()
        mark.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        mark.lineWidth = 1
        mark.stroke()

        let markAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
        ]
        drawCentered("T", in: markRect, attributes: markAttrs)

        let textX = markRect.maxX + 10
        let textRect = NSRect(
            x: textX,
            y: titlebarRect.minY + 5,
            width: max(40, bounds.width - textX - 14),
            height: titlebarRect.height - 8
        )
        drawTruncated(
            item.previewTitle,
            in: NSRect(x: textRect.minX, y: textRect.minY + 13, width: textRect.width, height: 14),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.86)
        )
        drawTruncated(
            item.previewSubtitle,
            in: NSRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: 12),
            font: .monospacedSystemFont(ofSize: 9, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.48)
        )
    }

    private func drawFooterMetadata() {
        let textRect = NSRect(
            x: 14,
            y: footerRect.minY + 10,
            width: max(20, dragHandle.frame.minX - 24),
            height: 16
        )
        drawTruncated(
            item.previewMetadataLine,
            in: textRect,
            font: .monospacedSystemFont(ofSize: 9, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.56)
        )
    }

    private func drawSeparators() {
        NSColor.white.withAlphaComponent(0.13).setFill()
        NSRect(x: 1, y: bounds.maxY - 1, width: bounds.width - 2, height: 1).fill()
        NSColor.black.withAlphaComponent(0.34).setFill()
        NSRect(x: 1, y: 0, width: bounds.width - 2, height: 1).fill()
        NSColor.black.withAlphaComponent(0.30).setFill()
        NSRect(x: 0, y: titlebarRect.minY - 1, width: bounds.width, height: 1).fill()
        NSColor.white.withAlphaComponent(0.05).setFill()
        NSRect(x: 0, y: titlebarRect.minY - 2, width: bounds.width, height: 1).fill()
        NSColor.black.withAlphaComponent(0.18).setFill()
        NSRect(x: 0, y: footerRect.maxY + 1, width: bounds.width, height: 1).fill()
        NSColor.white.withAlphaComponent(0.04).setFill()
        NSRect(x: 0, y: footerRect.maxY, width: bounds.width, height: 1).fill()
    }

    private func drawChromeRelief(in rect: NSRect) {
        guard rect.width > 2, rect.height > 2 else { return }
        var y = rect.minY + 2
        while y < rect.maxY - 1 {
            NSColor.white.withAlphaComponent(0.018).setFill()
            NSRect(x: rect.minX + 1, y: y.rounded(.down), width: rect.width - 2, height: 1).fill()
            NSColor.black.withAlphaComponent(0.048).setFill()
            NSRect(x: rect.minX + 1, y: (y + 1).rounded(.down), width: rect.width - 2, height: 1).fill()
            y += 6
        }
    }

    private func drawCentered(_ string: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let size = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawTruncated(_ string: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }

    @objc private func closePreview(_ sender: Any) {
        onClose()
    }
}

private final class AgentClipPreviewDragHandleView: NSView, NSDraggingSource {
    private let item: AgentLiveTrayItem

    init(item: AgentLiveTrayItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "Drag a copy"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let chip = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.05, alpha: 0.88).setFill()
        chip.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        chip.lineWidth = 1
        chip.stroke()

        NSColor.white.withAlphaComponent(0.20).setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                NSBezierPath(ovalIn: NSRect(
                    x: 8 + CGFloat(column) * 4,
                    y: bounds.midY - 5 + CGFloat(row) * 4,
                    width: 1.4,
                    height: 1.4
                )).fill()
            }
        }

        let title = "DRAG COPY"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.66),
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            at: NSPoint(x: bounds.maxX - size.width - 9, y: bounds.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        let icon = NSWorkspace.shared.icon(forFile: item.fileURL.path)
        icon.size = NSSize(width: 34, height: 34)

        let draggingItem = NSDraggingItem(pasteboardWriter: item.fileURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

private extension AgentLiveTrayItem {
    var previewTitle: String {
        displayName ?? windowTitle ?? appName ?? "Screen recording"
    }

    var previewSubtitle: String {
        "\(durationLabel)  |  \(width)x\(height)  |  \(captureModeLabel)"
    }

    var previewMetadataLine: String {
        let source = appName ?? windowTitle ?? filename
        return "Captured \(capturedAt.timeAgoShort)  |  \(source)  |  \(fileSizeLabel)"
    }

    private var captureModeLabel: String {
        captureMode.isEmpty ? "clip" : captureMode.replacing("_", with: " ")
    }

    private var durationLabel: String {
        guard let durationMs else { return "clip" }
        let tenths = max(0, (durationMs + 50) / 100)
        let minutes = tenths / 600
        let seconds = (tenths / 10) % 60
        let fraction = tenths % 10
        if minutes > 0 {
            return "\(minutes):\(seconds.twoDigit).\(fraction)"
        }
        return "\(seconds).\(fraction)s"
    }

    private var fileSizeLabel: String {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        guard size > 0 else { return filename }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

private extension Int {
    var twoDigit: String {
        self < 10 ? "0\(self)" : "\(self)"
    }
}
