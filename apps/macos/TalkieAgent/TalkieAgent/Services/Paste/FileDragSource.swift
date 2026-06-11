//
//  FileDragSource.swift
//  TalkieAgent
//
//  Floating drag handle for Quick Paste file drag (Hyper+V → ⌘+N).
//  Shows a DossierCard-style thumbnail at the cursor. User clicks and drags
//  to drop the file into any accepting app. Dismisses on drop or Escape.
//

import AppKit
import TalkieKit

// MARK: - Drag Source

final class FileDragSourceDelegate: NSObject, NSDraggingSource {
    var onEnd: (() -> Void)?

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onEnd?()
    }
}

// MARK: - Drag Handle Panel

@MainActor
final class FileDragPanel {
    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var dragSource = FileDragSourceDelegate()

    func show(item: AgentLiveTrayItem) {
        dismiss()

        let fileURL = item.tempURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Log(.system).warning("Drag panel: file not found")
            return
        }

        let dragImage: NSImage
        if let thumb = item.image {
            dragImage = thumb
        } else {
            dragImage = NSWorkspace.shared.icon(forFile: fileURL.path)
        }

        let panelWidth: CGFloat = 96
        let panelHeight: CGFloat = 80

        // Use a pure NSView-based approach — no SwiftUI hosting view interference
        let dragView = DragInitiatorView(
            fileURL: fileURL,
            dragImage: dragImage,
            item: item,
            dragSource: dragSource
        )
        dragView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = dragView
        p.isFloatingPanel = true
        p.level = .screenSaver + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.canHide = false
        // Accept mouse events even when app is not active
        p.acceptsMouseMovedEvents = true

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main else { return }

        let x = max(screen.frame.minX + 4, min(mouseLocation.x - panelWidth / 2, screen.frame.maxX - panelWidth - 4))
        let y = max(screen.frame.minY + 4, min(mouseLocation.y - panelHeight / 2, screen.frame.maxY - panelHeight - 4))
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1
        }

        self.panel = p

        // Escape to dismiss (both local and global)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
        }

        dragSource.onEnd = { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
        if let m = globalEscapeMonitor { NSEvent.removeMonitor(m); globalEscapeMonitor = nil }
        dragSource.onEnd = nil
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.contentView = nil
        })
    }
}

// MARK: - Drag Initiator View

/// Pure AppKit view that renders the thumbnail with dossier-style chrome
/// and initiates a drag session on mouseDown.
private class DragInitiatorView: NSView {
    let fileURL: URL
    let dragImage: NSImage
    let item: AgentLiveTrayItem
    let dragSource: FileDragSourceDelegate

    private let cornerRadius: CGFloat = 6
    private let borderColor = NSColor.white.withAlphaComponent(0.12)
    private let stripBg = NSColor(white: 0.08, alpha: 1)
    private let stripFont = NSFont.monospacedSystemFont(ofSize: 7, weight: .medium)
    private let stripColor = NSColor.white.withAlphaComponent(0.35)

    init(fileURL: URL, dragImage: NSImage, item: AgentLiveTrayItem, dragSource: FileDragSourceDelegate) {
        self.fileURL = fileURL
        self.dragImage = dragImage
        self.item = item
        self.dragSource = dragSource
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let stripHeight: CGFloat = 16
        let stripRect = NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
        let imageRect = NSRect(x: 0, y: stripHeight, width: bounds.width, height: bounds.height - stripHeight)

        // Clip to rounded rect
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()

        // Image region
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: imageRect).fill()
        dragImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // Data strip
        stripBg.setFill()
        NSBezierPath(rect: stripRect).fill()

        let meta = "\(item.width)×\(item.height)"
        let attrs: [NSAttributedString.Key: Any] = [.font: stripFont, .foregroundColor: stripColor]
        let metaSize = (meta as NSString).size(withAttributes: attrs)
        let textPoint = NSPoint(x: 6, y: stripRect.minY + (stripHeight - metaSize.height) / 2)
        (meta as NSString).draw(at: textPoint, withAttributes: attrs)

        // Border
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: cornerRadius, yRadius: cornerRadius)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let imageSize = NSSize(width: bounds.width, height: bounds.height)
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(
            NSRect(origin: .zero, size: imageSize),
            contents: dragImage
        )
        beginDraggingSession(with: [draggingItem], event: event, source: dragSource)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
