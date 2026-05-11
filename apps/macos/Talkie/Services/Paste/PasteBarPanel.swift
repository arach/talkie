//
//  PasteBarPanel.swift
//  Talkie
//
//  Floating panel for Quick Paste (Hyper+V).
//  Shows 1-5 most recent tray items as thumbnails with format legend.
//  Modifier keys (Shift/Option/Control) change the paste format.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - State

@MainActor
@Observable
final class PasteBarState {
    var items: [TrayItem] = []
    var activeFormat: PasteFormat = .image
    var onAction: ((PasteBarResult?) -> Void)?
}

// MARK: - Panel

@MainActor
final class PasteBarPanel {

    private var panel: NSPanel?
    let state = PasteBarState()

    var frame: NSRect? { panel?.frame }

    func show(items: [TrayItem]) {
        dismiss()

        state.items = items
        state.activeFormat = .image

        let hostingView = NSHostingView(rootView: PasteBarView(state: state))
        hostingView.layer?.isOpaque = false

        let isEmpty = items.isEmpty
        let width: CGFloat = isEmpty ? 260 : CGFloat(min(items.count, 5)) * 100 + 40
        let height: CGFloat = isEmpty ? 80 : 140

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .screenSaver + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.sharingType = .readOnly
        p.hidesOnDeactivate = false
        p.canHide = false

        // Position near cursor, clamped to screen
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else { return }

        let offset: CGFloat = 20
        var x = mouseLocation.x - width / 2
        var y = mouseLocation.y - height / 2 - offset

        let margin: CGFloat = 8
        x = max(screen.frame.minX + margin, min(x, screen.frame.maxX - width - margin))
        y = max(screen.frame.minY + margin, min(y, screen.frame.maxY - height - margin))

        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        self.panel = p
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }
}

// MARK: - SwiftUI View

private struct PasteBarView: View {
    @Bindable var state: PasteBarState

    @State private var appeared = false
    @State private var hoveredIndex: Int?

    private var chromeBaseColor: Color { Theme.current.surface2 }

    var body: some View {
        VStack(spacing: 0) {
            if state.items.isEmpty {
                emptyState
            } else {
                thumbnailRow
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                HStack {
                    formatLegend

                    Spacer()

                    Text("W browse")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.textTertiary)
                }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(chromeBaseColor.opacity(0.96))

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.current.surface3.opacity(0.6),
                                chromeBaseColor.opacity(0.25),
                                Theme.current.background.opacity(0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        RadialGradient(
                            colors: [Theme.current.surface3.opacity(0.28), Color.clear],
                            center: .top,
                            startRadius: 8,
                            endRadius: 120
                        )
                    )
            }
            .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.current.divider.opacity(0.95),
                            Theme.current.divider.opacity(0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredIndex)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No captures yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.current.textSecondary)
            Text("Hyper+S to start")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: - Thumbnail Row

    private var thumbnailRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                thumbnailCell(item: item, index: index)
            }
        }
    }

    private func thumbnailCell(item: TrayItem, index: Int) -> some View {
        let isHovered = hoveredIndex == index
        let number = index + 1

        return Button(action: { state.onAction?(PasteBarResult(item: item, format: state.activeFormat)) }) {
            VStack(spacing: 4) {
                // Thumbnail
                ZStack {
                    Theme.current.surface1

                    if let nsImage = item.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else if let previewText = item.previewText {
                        Text(previewText)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.textSecondary)
                            .lineLimit(3)
                            .padding(3)
                    } else {
                        Image(systemName: item.isClip ? "video.fill" : "photo")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Theme.current.textMuted)
                    }
                }
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isHovered ? Color.accentColor.opacity(0.6) : Theme.current.divider,
                            lineWidth: isHovered ? 1.2 : 0.5
                        )
                )

                // Number key
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.textPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovered ? Color.accentColor.opacity(0.3) : Theme.current.surfaceHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Theme.current.divider, lineWidth: 0.5)
                            )
                    )
            }
            .scaleEffect(isHovered ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredIndex = inside ? index : (hoveredIndex == index ? nil : hoveredIndex)
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Format Legend

    private var formatLegend: some View {
        HStack(spacing: 8) {
            formatPill("[1-5]", label: "image", active: state.activeFormat == .image, color: Theme.current.textPrimary)
            formatPill("⇧", label: "path", active: state.activeFormat == .filePath, color: .orange)
            formatPill("⌥", label: "url", active: state.activeFormat == .url, color: .cyan)
            formatPill("⌃", label: "base64", active: state.activeFormat == .base64, color: .purple)
            formatPill("⌘", label: "drag", active: state.activeFormat == .dragFile, color: .green)
        }
    }

    private func formatPill(_ key: String, label: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(active ? color : color.opacity(0.5))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(active ? color.opacity(0.8) : color.opacity(0.35))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(active ? color.opacity(0.12) : Color.clear)
        )
    }
}
