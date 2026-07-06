//
//  PasteBarPanel.swift
//  TalkieAgent
//
//  Floating panel for Quick Paste (Hyper+V).
//  Shows 1-5 most recent captures as thumbnails with format legend.
//  Modifier keys (Shift/Option/Control) change the paste format.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - State

@MainActor
@Observable
final class PasteBarState {
    var items: [AgentLiveTrayItem] = []
    var activeFormat: PasteFormat = .image
    var onAction: ((PasteBarResult?) -> Void)?
}

private enum PasteBarStyle {
    static let rowHeight: CGFloat = 48
    static let keySize: CGFloat = 18
}

private struct PasteBarPalette {
    let theme: VisualTheme
    let accent: Color
    let surfaceTint: Color
    let elevatedTint: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let edge: Color
    let subtleEdge: Color
    let hairline: Color
    let shadow: Color

    var panelRadius: CGFloat {
        switch theme {
        case .terminal: 7
        case .light: 12
        case .live, .midnight, .darkMatte: 13
        }
    }

    var cellRadius: CGFloat {
        switch theme {
        case .terminal: 4
        case .light: 6
        case .live, .midnight, .darkMatte: 7
        }
    }

    @MainActor
    static func resolved(settings: LiveSettings) -> PasteBarPalette {
        let accent = settings.effectiveAccentColor
        let preview = settings.visualTheme.previewColors

        switch settings.visualTheme {
        case .light:
            return PasteBarPalette(
                theme: .light,
                accent: accent,
                surfaceTint: preview.bg.opacity(0.97),
                elevatedTint: Color.white.opacity(0.38),
                textPrimary: preview.fg.opacity(0.92),
                textSecondary: preview.fg.opacity(0.66),
                textMuted: preview.fg.opacity(0.44),
                edge: preview.fg.opacity(0.14),
                subtleEdge: preview.fg.opacity(0.08),
                hairline: preview.fg.opacity(0.10),
                shadow: Color.black.opacity(0.18)
            )
        case .terminal:
            return PasteBarPalette(
                theme: .terminal,
                accent: accent,
                surfaceTint: Color.black.opacity(0.96),
                elevatedTint: Color.white.opacity(0.045),
                textPrimary: preview.fg.opacity(0.90),
                textSecondary: preview.fg.opacity(0.64),
                textMuted: preview.fg.opacity(0.42),
                edge: preview.fg.opacity(0.18),
                subtleEdge: preview.fg.opacity(0.10),
                hairline: preview.fg.opacity(0.12),
                shadow: Color.black.opacity(0.38)
            )
        case .darkMatte:
            return PasteBarPalette(
                theme: .darkMatte,
                accent: accent,
                surfaceTint: preview.bg.opacity(0.96),
                elevatedTint: Color(red: 0.20, green: 0.15, blue: 0.10).opacity(0.34),
                textPrimary: preview.fg.opacity(0.92),
                textSecondary: preview.fg.opacity(0.66),
                textMuted: preview.fg.opacity(0.42),
                edge: preview.fg.opacity(0.15),
                subtleEdge: preview.fg.opacity(0.08),
                hairline: preview.fg.opacity(0.10),
                shadow: Color.black.opacity(0.40)
            )
        case .live, .midnight:
            return PasteBarPalette(
                theme: settings.visualTheme,
                accent: accent,
                surfaceTint: preview.bg.opacity(0.96),
                elevatedTint: Color.white.opacity(0.06),
                textPrimary: preview.fg.opacity(0.92),
                textSecondary: preview.fg.opacity(0.64),
                textMuted: preview.fg.opacity(0.40),
                edge: preview.fg.opacity(0.15),
                subtleEdge: preview.fg.opacity(0.08),
                hairline: preview.fg.opacity(0.10),
                shadow: Color.black.opacity(0.38)
            )
        }
    }

    func tint(for format: PasteFormat) -> Color {
        switch format {
        case .image:
            accent
        case .filePath:
            theme == .terminal ? textSecondary : OpsTint.amber.color
        case .url:
            theme == .terminal ? textSecondary : OpsTint.cyan.color
        case .base64:
            theme == .terminal ? textSecondary : OpsTint.violet.color
        case .visionDescription:
            theme == .terminal ? textSecondary : OpsTint.green.color
        case .dragFile:
            theme == .terminal ? textSecondary : OpsTint.red.color
        }
    }
}

// MARK: - Panel

@MainActor
final class PasteBarPanel {

    private var panel: NSPanel?
    let state = PasteBarState()

    var frame: NSRect? { panel?.frame }

    func show(items: [AgentLiveTrayItem]) {
        dismiss()

        state.items = items
        state.activeFormat = .image

        let hostingView = NSHostingView(rootView: PasteBarView(state: state))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

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
        p.hasShadow = false
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

    @ObservedObject private var settings = LiveSettings.shared
    @State private var appeared = false
    @State private var hoveredIndex: Int?

    private var palette: PasteBarPalette {
        PasteBarPalette.resolved(settings: settings)
    }

    private var activeTint: Color {
        palette.tint(for: state.activeFormat)
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

                separatorLine

                HStack {
                    formatLegend
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 10)
            }
        }
        .foregroundStyle(palette.textPrimary)
        .background(
            panelBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: palette.panelRadius, style: .continuous)
                .strokeBorder(palette.edge, lineWidth: 0.65)
        )
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredIndex)
        .animation(.easeInOut(duration: 0.16), value: state.activeFormat)
        .tint(palette.accent)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: palette.panelRadius, style: .continuous)
            .fill(palette.surfaceTint)
            .shadow(color: palette.shadow, radius: 14, y: 7)
    }

    private var separatorLine: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        palette.hairline,
                        activeTint.opacity(0.18),
                        palette.hairline,
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(activeTint.opacity(0.86))

            Text("No captures yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)

            Text("Hyper+S to start")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textMuted)
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

    private func thumbnailCell(item: AgentLiveTrayItem, index: Int) -> some View {
        let isHovered = hoveredIndex == index
        let number = index + 1
        let tint = activeTint

        return Button(action: { state.onAction?(PasteBarResult(item: item, format: state.activeFormat)) }) {
            VStack(spacing: 4) {
                ZStack {
                    palette.elevatedTint

                    if let nsImage = item.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else if let previewText = item.previewText {
                        Text(previewText)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(3)
                            .padding(3)
                    } else {
                        Image(systemName: item.isClip ? "video.fill" : "photo")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(palette.textMuted)
                    }
                }
                .frame(width: 72, height: PasteBarStyle.rowHeight)
                .clipShape(RoundedRectangle(cornerRadius: palette.cellRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cellRadius, style: .continuous)
                        .strokeBorder(
                            isHovered ? tint.opacity(0.72) : palette.subtleEdge,
                            lineWidth: isHovered ? 1 : 0.5
                        )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(isHovered ? tint.opacity(0.20) : palette.hairline)
                        .frame(height: 1)
                        .clipShape(RoundedRectangle(cornerRadius: palette.cellRadius, style: .continuous))
                }

                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHovered ? tint : palette.textPrimary)
                    .frame(width: PasteBarStyle.keySize, height: PasteBarStyle.keySize)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isHovered ? tint.opacity(0.16) : palette.elevatedTint)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(isHovered ? tint.opacity(0.36) : palette.subtleEdge, lineWidth: 0.5)
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

    private func formatPill(_ key: String, label: String, active: Bool) -> some View {
        let tint = active ? activeTint : palette.edge

        return HStack(spacing: 5) {
            keyBadge(key, active: active)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(active ? palette.textPrimary : palette.textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(active ? activeTint.opacity(0.12) : Color.clear)
        )
        .overlay(
            Capsule()
                .strokeBorder(active ? tint.opacity(0.32) : Color.clear, lineWidth: 0.5)
        )
    }

    private func keyBadge(_ key: String, active: Bool) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? activeTint : palette.textSecondary)
            .frame(minWidth: key.count > 1 ? 34 : 18, minHeight: 18)
            .padding(.horizontal, key.count > 1 ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(active ? activeTint.opacity(0.16) : palette.elevatedTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(active ? activeTint.opacity(0.36) : palette.subtleEdge, lineWidth: 0.5)
                    )
            )
    }
}
