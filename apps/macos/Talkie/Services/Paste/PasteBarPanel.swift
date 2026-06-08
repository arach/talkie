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
        let width: CGFloat = isEmpty ? 260 : max(390, CGFloat(min(items.count, 5)) * 100 + 40)
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
        state.onAction = nil

        guard let p = panel else {
            state.items = []
            return
        }
        panel = nil
        let state = self.state
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                p.orderOut(nil)
                p.contentView = nil
                state.items = []
            }
        })
    }
}

// MARK: - SwiftUI View

private struct PasteBarView: View {
    @Bindable var state: PasteBarState

    @State private var appeared = false
    @State private var hoveredIndex: Int?

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.32), Color.white.opacity(0.09)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

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
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                HStack {
                    formatLegend

                    Spacer()

                    browseHint
                }
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 10)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.78))

                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .opacity(0.62)

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: .black.opacity(0.34), radius: 18, y: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderGradient, lineWidth: 0.5)
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
                .foregroundColor(.white.opacity(0.76))
            Text("Hyper+S to start")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
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
                    Color.black.opacity(0.28)

                    if let nsImage = item.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else if let previewText = item.previewText {
                        Text(previewText)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(3)
                            .padding(3)
                    } else {
                        Image(systemName: item.isClip ? "video.fill" : "photo")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isHovered ? Color.white.opacity(0.48) : Color.white.opacity(0.16),
                            lineWidth: isHovered ? 1 : 0.5
                        )
                )

                // Number key
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(isHovered ? 0.98 : 0.82))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.white.opacity(isHovered ? 0.28 : 0.13), lineWidth: 0.5)
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
        HStack(spacing: 6) {
            formatPill("[1-5]", label: "image", active: state.activeFormat == .image)
            formatPill("⇧", label: "path", active: state.activeFormat == .filePath)
            formatPill("⌥", label: "url", active: state.activeFormat == .url)
            formatPill("⌃", label: "base64", active: state.activeFormat == .base64)
            formatPill("⇧⌥", label: "describe", active: state.activeFormat == .visionDescription)
            formatPill("⌘", label: "drag", active: state.activeFormat == .dragFile)
        }
    }

    private var browseHint: some View {
        HStack(spacing: 4) {
            keyBadge("W", active: false)
            Text("browse")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
    }

    private func formatPill(_ key: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            keyBadge(key, active: active)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(active ? .white.opacity(0.84) : .white.opacity(0.42))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(active ? Color.white.opacity(0.10) : Color.clear)
        )
        .overlay(
            Capsule()
                .strokeBorder(active ? Color.white.opacity(0.16) : Color.clear, lineWidth: 0.5)
        )
    }

    private func keyBadge(_ key: String, active: Bool) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(active ? .white.opacity(0.95) : .white.opacity(0.56))
            .frame(minWidth: key.count > 1 ? 34 : 18, minHeight: 18)
            .padding(.horizontal, key.count > 1 ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(active ? 0.13 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(active ? 0.22 : 0.10), lineWidth: 0.5)
                    )
            )
    }
}
