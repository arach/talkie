//
//  TrayShelf.swift
//  Talkie
//
//  Full-width horizontal strip across the top of the screen for browsing tray assets.
//  Triggered by hotkey toggle. Coordinates with SurfaceCoordinator for state management.
//

import AppKit
import Observation
import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Shelf Controller

@MainActor
final class TrayShelf {
    static let shared = TrayShelf()

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    private init() {}

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard !SurfaceCoordinator.shared.isRecording else { return }

        if TrayViewer.shared.isVisible {
            TrayViewer.shared.dismiss()
        }

        let items = TrayItem.allItems()
        guard !items.isEmpty else {
            log.info("TrayShelf.show: no items, skipping")
            return
        }

        if let existing = panel, existing.isVisible {
            return
        }

        let screen = targetScreen()
        let visibleFrame = screen.visibleFrame
        let shelfHeight = TraySettings.shared.shelfHeight
        let width = visibleFrame.width
        let finalY = visibleFrame.maxY - shelfHeight
        let startY = visibleFrame.maxY

        let hostingView = NSHostingView(rootView: TrayShelfView(
            dismiss: { [weak self] in self?.dismiss() }
        ))

        let p = NSPanel(
            contentRect: NSRect(x: visibleFrame.origin.x, y: 0, width: width, height: shelfHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.sharingType = .none
        p.isReleasedWhenClosed = false

        p.setFrameOrigin(NSPoint(x: visibleFrame.origin.x, y: startY))
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrameOrigin(NSPoint(x: visibleFrame.origin.x, y: finalY))
            p.animator().alphaValue = 1
        }

        self.panel = p
        installEventMonitors()
        SurfaceCoordinator.shared.openShelf()
        log.info("TrayShelf.show: displayed (\(Int(width))×\(Int(shelfHeight)))")
    }

    func dismiss() {
        guard let p = panel else { return }

        removeEventMonitors()

        let slideUpY = p.frame.origin.y + p.frame.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrameOrigin(NSPoint(x: p.frame.origin.x, y: slideUpY))
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                p.orderOut(nil)
                self?.panel = nil
                TraySelection.shared.reset()
                SurfaceCoordinator.shared.dismiss()
            }
        })
    }

    // MARK: - Event Monitors

    private func installEventMonitors() {
        // Global click — dismiss when clicking outside (other apps)
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }

        // Local click — dismiss when clicking other Talkie windows, pass through if clicking shelf itself
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }
            self.dismiss()
            return event
        }

        // Local escape
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.dismiss()
                return nil
            }
            if self.handleKeyDown(event) { return nil }
            return event
        }

        // Global escape
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
            }
        }
    }

    private func removeEventMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localEscapeMonitor { NSEvent.removeMonitor(m) }
        if let m = globalEscapeMonitor { NSEvent.removeMonitor(m) }
        globalClickMonitor = nil
        localClickMonitor = nil
        localEscapeMonitor = nil
        globalEscapeMonitor = nil
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }

        let selection = TraySelection.shared
        let items = TrayItem.allItems()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 51, 117: // Delete / Forward delete
            let ids = selection.selectedIDs
            guard !ids.isEmpty else { return false }
            _ = TrayActionService.shared.deleteSelected(ids: ids, in: items)
            if TrayItem.allItems().isEmpty { dismiss() }
            return true

        case 8: // C
            if modifiers.contains(.command) {
                return TrayActionService.shared.copySelected(ids: selection.selectedIDs, in: items)
            }

        case 0: // A
            if modifiers.contains(.command) {
                selection.selectAll(items)
                return true
            }

        case 123: // Left
            selection.moveFocus(direction: .left, in: items)
            return true

        case 124: // Right
            selection.moveFocus(direction: .right, in: items)
            return true

        case 49: // Space
            if let focusedID = selection.focusedID {
                selection.toggle(focusedID)
                return true
            }

        default:
            break
        }

        return false
    }

    // MARK: - Screen

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - Shelf SwiftUI View

private struct TrayShelfView: View {
    let dismiss: () -> Void

    @State private var selection = TraySelection.shared

    private var shelfHeight: Double { TraySettings.shared.shelfHeight }

    var body: some View {
        let allItems = TrayItem.allItems()
        let cardHeight = shelfHeight - 24
        let panelShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 0) {
            // Left info section
            VStack(alignment: .leading, spacing: 4) {
                Text("\(allItems.count) items")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if selection.count > 0 {
                    HStack(spacing: 6) {
                        Button(action: {
                            _ = TrayActionService.shared.deleteSelected(ids: selection.selectedIDs, in: allItems)
                            if TrayItem.allItems().isEmpty { dismiss() }
                        }) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 10, weight: .medium))
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button(action: {
                            _ = TrayActionService.shared.togglePinSelected(ids: selection.selectedIDs, in: allItems)
                        }) {
                            Label("Pin", systemImage: "pin")
                                .font(.system(size: 10, weight: .medium))
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .frame(width: 80)
            .padding(.leading, 12)

            Divider()
                .padding(.vertical, 8)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allItems) { item in
                        shelfCard(item: item, cardHeight: cardHeight, allItems: allItems)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Close button
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel("Close shelf")
        }
        .frame(height: shelfHeight)
        .background {
            panelShape
                .fill(.ultraThinMaterial)
                .overlay(
                    panelShape
                        .fill(Theme.current.surface2.opacity(0.88))
                )
                .overlay(
                    panelShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.current.surface3.opacity(0.45),
                                    Theme.current.background.opacity(0.28)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .overlay {
            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.current.divider.opacity(0.95),
                            Theme.current.divider.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.34), radius: 24, y: 10)
        .onAppear {
            selection.pruneStaleIDs()
        }
    }

    @ViewBuilder
    private func shelfCard(item: TrayItem, cardHeight: CGFloat, allItems: [TrayItem]) -> some View {
        let cardWidth = cardHeight * item.aspectRatio
        let isSelected = selection.isSelected(item.id)
        let isFocused = selection.isFocused(item.id)
        let cardShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        Button {
            handleItemClick(item, allItems: allItems)
        } label: {
            ZStack {
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Theme.current.surface1)
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay {
                            Image(systemName: item.isClip ? "video" : "photo")
                                .foregroundStyle(.quaternary)
                        }
                }
            }
            .clipShape(cardShape)
            .overlay {
                if isSelected {
                    cardShape
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                } else if isFocused {
                    cardShape
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, height: cardHeight)
        .trayDrag(item: item)
        .accessibilityLabel(item.isClip ? "Video clip" : "Screenshot")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Copy") {
                _ = TrayActionService.shared.copySelected(ids: [item.id], in: allItems)
            }
            Button(item.pinned ? "Unpin" : "Pin") {
                _ = TrayActionService.shared.togglePinSelected(ids: [item.id], in: allItems)
            }
            Divider()
            Button("Delete", role: .destructive) {
                _ = TrayActionService.shared.deleteSelected(ids: [item.id], in: allItems)
            }
        }
    }

    private func handleItemClick(_ item: TrayItem, allItems: [TrayItem]) {
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []

        if modifiers.contains(.shift) {
            selection.rangeSelect(to: item.id, in: allItems)
        } else if modifiers.contains(.command) {
            selection.toggle(item.id)
        } else {
            selection.select(item.id)
        }
    }

}
