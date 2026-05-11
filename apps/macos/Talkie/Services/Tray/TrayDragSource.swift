//
//  TrayDragSource.swift
//  Talkie
//
//  AppKit drag source for multi-item dragging from tray surfaces.
//  SwiftUI's .onDrag only supports single NSItemProvider — this drops to AppKit's
//  beginDraggingSession(with:) for multi-item file URL drags.
//
//  Works in non-activating panels (notch) via acceptsFirstMouse + overlay placement.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Internal Drag Marker

enum TalkieInternalDrag {
    static let typeIdentifier = "com.jdi.talkie.internal-drag"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    static func isInternal(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            provider.registeredTypeIdentifiers.contains(typeIdentifier)
                || provider.hasItemConformingToTypeIdentifier(typeIdentifier)
        }
    }

    @discardableResult
    static func mark(_ provider: NSItemProvider) -> NSItemProvider {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(Data("talkie-internal-drag".utf8), nil)
            return nil
        }
        return provider
    }

    static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier))
        item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(UTType.url.identifier))
        item.setString("1", forType: pasteboardType)
        return item
    }
}

// MARK: - Multi-Drag View Modifier

extension View {
    /// Attach multi-drag support to a tray card. If the item is part of a multi-selection,
    /// drags all selected items as file URLs. Otherwise drags just this item.
    func trayDrag(item: TrayItem) -> some View {
        overlay(TrayDragSourceRepresentable(itemID: item.id))
    }
}

// MARK: - NSViewRepresentable

private struct TrayDragSourceRepresentable: NSViewRepresentable {
    let itemID: UUID

    func makeNSView(context: Context) -> TrayDragSourceView {
        let view = TrayDragSourceView()
        view.itemID = itemID
        return view
    }

    func updateNSView(_ nsView: TrayDragSourceView, context: Context) {
        nsView.itemID = itemID
    }
}

// MARK: - AppKit Drag Source

@MainActor
final class TrayDragSourceView: NSView, NSDraggingSource {
    var itemID: UUID?

    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4
    private var isDragging = false

    // Accept clicks even in non-activating panels (notch)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
        // Don't call super — we handle the full mouse lifecycle
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = dragStartLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance >= dragThreshold else { return }

        isDragging = true
        dragStartLocation = nil
        startMultiDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        dragStartLocation = nil
        isDragging = false

        if !wasDragging {
            // Wasn't a drag — forward as a click to the SwiftUI layer beneath
            super.mouseUp(with: event)
            // Also synthesize a click by forwarding mouseDown then mouseUp to next responder
            if let next = nextResponder {
                next.mouseDown(with: event)
                next.mouseUp(with: event)
            }
        }
    }

    // Make the view fill its parent but stay transparent
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only claim hits inside our bounds
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    private func startMultiDrag(with event: NSEvent) {
        guard let itemID else { return }

        let selection = TraySelection.shared
        let allItems = TrayItem.allItems()

        // Determine which URLs to drag
        let urls: [URL]
        if selection.isSelected(itemID), selection.count > 1 {
            // Multi-drag: all selected items
            let selectedItems = allItems.filter { selection.isSelected($0.id) }
            urls = selectedItems.map(\.tempURL)
        } else {
            // Single drag: just this item
            if let item = allItems.first(where: { $0.id == itemID }) {
                urls = [item.tempURL]
            } else {
                return
            }
        }

        guard !urls.isEmpty else { return }

        // Use the item's thumbnail as drag image if available
        let primaryItem = allItems.first(where: { $0.id == itemID })
        let dragItems = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: url))
            let offset = CGFloat(index) * 4
            let imageSize = NSSize(width: 64, height: 64)
            let dragFrame = NSRect(
                x: bounds.midX - imageSize.width / 2 + offset,
                y: bounds.midY - imageSize.height / 2 - offset,
                width: imageSize.width,
                height: imageSize.height
            )
            let dragImage: NSImage
            if index == 0, let thumb = primaryItem?.image {
                dragImage = makeThumbnailDragImage(thumb, count: urls.count)
            } else {
                dragImage = makeIconDragImage(for: url, count: urls.count, index: index)
            }
            item.setDraggingFrame(dragFrame, contents: dragImage)
            return item
        }

        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - Drag Images

    /// Thumbnail-based drag image — shows the actual screenshot/clip preview
    private func makeThumbnailDragImage(_ thumbnail: NSImage, count: Int) -> NSImage {
        let maxDim: CGFloat = 64
        let aspect = thumbnail.size.width / max(thumbnail.size.height, 1)
        let size: NSSize
        if aspect >= 1 {
            size = NSSize(width: maxDim, height: maxDim / aspect)
        } else {
            size = NSSize(width: maxDim * aspect, height: maxDim)
        }

        let image = NSImage(size: size)
        image.lockFocus()

        // Draw rounded thumbnail
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.addClip()
        thumbnail.draw(in: rect)

        // Badge with count
        if count > 1 {
            drawCountBadge(count, in: size)
        }

        image.unlockFocus()
        return image
    }

    /// Fallback icon-based drag image
    private func makeIconDragImage(for url: URL, count: Int, index: Int) -> NSImage {
        let size = NSSize(width: 48, height: 48)
        let image = NSImage(size: size)
        image.lockFocus()

        let iconImage = NSWorkspace.shared.icon(forFile: url.path)
        iconImage.draw(in: NSRect(origin: .zero, size: size))

        if index == 0, count > 1 {
            drawCountBadge(count, in: size)
        }

        image.unlockFocus()
        return image
    }

    private func drawCountBadge(_ count: Int, in size: NSSize) {
        let badgeSize: CGFloat = 18
        let badgeRect = NSRect(x: size.width - badgeSize - 2, y: size.height - badgeSize - 2, width: badgeSize, height: badgeSize)
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = "\(count)" as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        ), withAttributes: attrs)
    }
}
