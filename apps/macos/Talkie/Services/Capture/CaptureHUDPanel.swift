//
//  CaptureHUDPanel.swift
//  Talkie
//
//  Top-center floating chord menu for Hyper+S / Hyper+R. Built against
//  the SchemeTokens trio (PEARL · SLATE · AMBER) so the chrome adapts to
//  the wallpaper behind the panel — the previous one-tone slab was
//  always near-black, which sank into light desktops.
//
//  Anatomy (one rounded surface, hardware feel):
//    ┌─ TOP STRIP (stripTop gradient) ─────────────────────────────┐
//    │  ● Screenshot      ● Video                  ← → Mode          │
//    ├─ GRATICULE FIELD (3 primary cells) ─────────────────────────┤
//    │   [crop]        [display]      [window]                     │
//    │    A              S              D                          │
//    │  Region        Screen         Window                        │
//    ├─ BOTTOM STRIP (stripBottom gradient) ───────────────────────┤
//    │  Optional contextual actions: note, paste latest, tray       │
//    └─────────────────────────────────────────────────────────────┘
//

import AppKit
import SwiftUI

// MARK: - Panel

@MainActor
final class CaptureHUDPanel {

    static let panelWidth: CGFloat = 384
    static let panelHeight: CGFloat = 156

    private var panel: NSPanel?
    let state = CaptureBarState()
    private var palette: Palette = .amber

    var frame: NSRect? { panel?.frame }

    /// Where the HUD will land for a given cursor position + position
    /// preference. Pulled out so `WallpaperLuminanceSampler` can sample
    /// the same rect we're about to draw into, with no chance of drift.
    static func expectedFrame(
        for mouseLocation: NSPoint,
        position: CaptureHUDPosition
    ) -> NSRect {
        let cursorScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
        let screen: NSScreen? = {
            switch position {
            case .cursor: return cursorScreen ?? NSScreen.main ?? NSScreen.screens.first
            case .fixed:  return cursorScreen ?? NSScreen.main ?? NSScreen.screens.first
            }
        }()
        guard let screen else {
            return NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        }
        let margin: CGFloat = 8
        let visibleFrame = screen.visibleFrame

        switch position {
        case .fixed:
            // Top-center, fixed slot. The screenshot preview lives in
            // the same lane; they're allowed to overlap. Avoidance/
            // stacking was tried (offset, push-below) and dropped —
            // visual clutter wasn't worth the layout complexity.
            let x = clamp(
                visibleFrame.midX - panelWidth / 2,
                min: visibleFrame.minX + margin,
                max: visibleFrame.maxX - panelWidth - margin
            )
            let y = visibleFrame.maxY - panelHeight - 8
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        case .cursor:
            // Anchor centered on the cursor's X. Y: prefer below the cursor;
            // flip above if the cursor is near the bottom of the screen.
            // Clamp both axes inside visibleFrame.
            let gap: CGFloat = 24
            let x = clamp(
                mouseLocation.x - panelWidth / 2,
                min: visibleFrame.minX + margin,
                max: visibleFrame.maxX - panelWidth - margin
            )
            // In macOS coords (Y grows up), "below the cursor" means a smaller Y.
            let below = mouseLocation.y - gap - panelHeight
            let above = mouseLocation.y + gap
            let preferBelow = mouseLocation.y > visibleFrame.midY
            var y = preferBelow ? below : above
            if y < visibleFrame.minY + margin {
                y = above
            }
            if y + panelHeight > visibleFrame.maxY - margin {
                y = below
            }
            y = clamp(
                y,
                min: visibleFrame.minY + margin,
                max: visibleFrame.maxY - panelHeight - margin
            )
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        }
    }

    private static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(v, hi))
    }

    func show(
        mode: CaptureBarMode,
        showCameraOption: Bool,
        showTrayOption: Bool,
        showSelectionOption: Bool,
        trayCount: Int,
        palette: Palette
    ) {
        dismiss()

        state.mode = mode
        state.showCameraOption = showCameraOption
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.trayCount = trayCount
        self.palette = palette

        let hostingView = NSHostingView(rootView: CaptureHUDView(state: state, palette: palette))
        hostingView.layer?.isOpaque = false

        let origin = Self.expectedFrame(
            for: NSEvent.mouseLocation,
            position: SettingsManager.shared.captureHUDPosition
        )

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: origin.size),
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
        p.sharingType = .none
        p.hidesOnDeactivate = false
        p.canHide = false

        p.setFrameOrigin(origin.origin)

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
        state.onStart = nil
        state.onCancel = nil

        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.contentView = nil
        })
    }

    func updatePalette(_ palette: Palette) {
        guard let p = panel, palette != self.palette else { return }
        self.palette = palette

        let hostingView = NSHostingView(rootView: CaptureHUDView(state: state, palette: palette))
        hostingView.layer?.isOpaque = false
        p.contentView = hostingView
    }

    func toggleMode() {
        state.mode = (state.mode == .screenshot) ? .video : .screenshot
    }

}

// MARK: - HUD SwiftUI View

private struct CaptureHUDView: View {
    @Bindable var state: CaptureBarState
    let palette: Palette

    @State private var appeared = false
    @State private var hoveredKey: String?
    @State private var pulseOn = false

    private var tokens: SchemeTokens { palette.tokens }
    private var isVideo: Bool { state.mode == .video }

    /// Accent color: scheme-warm for screenshot, scheme-red for video.
    private var accent: Color {
        isVideo ? Color(hex: tokens.recHex) : Color(hex: tokens.accentHex)
    }
    private var accentGlow: Color {
        (isVideo ? tokens.recGlow : tokens.accentGlow).color
    }

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            primaryCells
            bottomStrip
        }
        .frame(width: CaptureHUDPanel.panelWidth, height: CaptureHUDPanel.panelHeight)
        .background(Color(hex: tokens.bgHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tokens.edgeStrong.color, lineWidth: 0.5)
        )
        .overlay(
            // Inner bezel: highlight at top, shadow at bottom — reads as a
            // milled hardware part rather than a flat sticker.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .inset(by: 0.5)
                .strokeBorder(
                    LinearGradient(
                        colors: [tokens.bezelHighlight.color, .clear, tokens.bezelShadow.color],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
                .opacity(0.75)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: state.mode)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hoveredKey)
        .onAppear {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) { appeared = true }
            pulseOn = true
        }
    }

    // MARK: - Top strip

    /// Top strip now hosts BOTH mode tabs (Screenshot · Video) side by
    /// side. Each is clickable and toggles `state.mode`. The active tab
    /// carries the accent dot + lit text + tinted background; the
    /// inactive tab is a hollow dot + faint text. Replaces the older
    /// single-mode badge so the user can see — and switch — what mode
    /// the HUD is in at a glance.
    private var topStrip: some View {
        HStack(spacing: 4) {
            modeTab(kind: .screenshot)
            modeTab(kind: .video)

            Spacer(minLength: 8)

            modeSwitchHint
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(gradient(from: tokens.stripTop))
        .overlay(
            Rectangle()
                .fill(tokens.edge.color)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }

    private func modeTab(kind: CaptureBarMode) -> some View {
        let isActive = state.mode == kind
        let isVideoTab = kind == .video
        let tabAccent: Color = isVideoTab
            ? Color(hex: tokens.recHex)
            : Color(hex: tokens.accentHex)
        let tabAccentGlow: Color = isVideoTab
            ? tokens.recGlow.color
            : tokens.accentGlow.color
        let label = isVideoTab ? "Video" : "Screenshot"

        return Button {
            // Set mode directly rather than toggling — clicking a tab
            // should land you on it, not flip away if you double-tap.
            state.mode = kind
            state.onAction?(nil)
        } label: {
            HStack(spacing: 5) {
                if isActive {
                    Circle()
                        .fill(tabAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: tabAccentGlow, radius: 3)
                        .opacity(isVideoTab && pulseOn ? 0.35 : 1)
                        .animation(
                            isVideoTab
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: pulseOn
                        )
                } else {
                    Circle()
                        .stroke(Color(hex: tokens.inkFaintHex), lineWidth: 0.5)
                        .frame(width: 6, height: 6)
                }

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(isActive ? tabAccent : Color(hex: tokens.inkFaintHex))
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? tabAccent.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isActive ? tabAccent.opacity(0.45) : .clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isVideoTab ? "Video mode (Right Arrow)" : "Screenshot mode (Left Arrow)")
    }

    private var modeSwitchHint: some View {
        HStack(spacing: 4) {
            smallKeyCap("←")
            smallKeyCap("→")
            Text("Mode")
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1.3)
                .foregroundColor(Color(hex: tokens.inkFaintHex))
                .textCase(.uppercase)
        }
        .help("Left and Right Arrow switch between Screenshot and Video")
    }

    // MARK: - Primary cells

    private var primaryCells: some View {
        HStack(spacing: 8) {
            primaryCell(key: "A", icon: .crop,    label: "Region")
            primaryCell(key: "S", icon: .display, label: "Screen")
            primaryCell(key: "D", icon: .window,  label: "Window")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(graticule)
    }

    /// 12-pt graticule wash behind the primary cells. Instrument-bay
    /// vocabulary — reads as a precision field, not a flat plate.
    private var graticule: some View {
        Canvas { context, size in
            let step: CGFloat = 12
            let color = GraphicsContext.Shading.color(tokens.graticule.color)
            var x: CGFloat = 0
            while x <= size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: color, lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: color, lineWidth: 0.5)
                y += step
            }
        }
    }

    private func primaryCell(key: String, icon: HUDIcon, label: String) -> some View {
        let isHovered = hoveredKey == key
        let isActive = captureMode(forKey: key) == state.selectedCaptureMode
        // Active beats hover for icon color; hover still adds the
        // glass-lift treatment so the user feels "I can switch here too".
        let iconColor: Color = (isActive || isHovered) ? accent : Color(hex: tokens.inkHex)

        return Button(action: { tapAction(key: key) }) {
            VStack(spacing: 6) {
                icon.view(color: iconColor, size: 18)
                keyChip(key, isActive: isActive)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(isActive ? accent : Color(hex: tokens.inkFaintHex))
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? accent.opacity(0.14)
                            : (isHovered ? tokens.detailsBg.color : Color(hex: tokens.bgHex).opacity(0.5))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? accent.opacity(0.55)
                            : (isHovered ? tokens.edgeStrong.color : tokens.edge.color),
                        lineWidth: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .inset(by: 0.5)
                    .strokeBorder(tokens.bezelHighlight.color, lineWidth: 0.5)
                    .blendMode(.plusLighter)
                    .opacity(isHovered ? 0.9 : (isActive ? 0.6 : 0))
            )
            .shadow(
                color: isActive ? accentGlow.opacity(0.6) : .clear,
                radius: isActive ? 6 : 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredKey = inside ? key : (hoveredKey == key ? nil : hoveredKey)
            inside ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
        }
    }

    /// Maps the cell key letter back to its `CaptureMode` so the
    /// primaryCell rendering can compare against `state.selectedCaptureMode`.
    private func captureMode(forKey key: String) -> CaptureMode? {
        switch key {
        case "A": return .region
        case "S": return .fullscreen
        case "D": return .window
        default:  return nil
        }
    }

    private func keyChip(_ key: String, isActive: Bool = false) -> some View {
        Text(key)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundColor(isActive ? accent : Color(hex: tokens.inkHex))
            .frame(minWidth: 18, minHeight: 16)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? accent.opacity(0.22) : tokens.detailsBg.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isActive ? accent.opacity(0.7) : tokens.edgeStrong.color,
                        lineWidth: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .inset(by: 0.5)
                    .strokeBorder(tokens.bezelHighlight.color, lineWidth: 0.5)
                    .blendMode(.plusLighter)
                    .opacity(0.6)
            )
    }

    // MARK: - Bottom strip (extras)

    private var bottomStrip: some View {
        HStack(spacing: 4) {
            if state.showCameraOption {
                extraCell(key: "C", label: "Camera", systemImage: "video.fill", tone: .accent) {
                    state.onAction?(.toggleCamera)
                }
            }
            if state.showSelectionOption {
                extraCell(key: "N", label: "Selection Note", systemImage: "note.text", tone: .ink) {
                    state.onAction?(.saveSelection)
                }
            }
            if state.showTrayOption {
                extraCell(key: "V", label: "Paste Last", systemImage: "clipboard", tone: .ink) {
                    state.onAction?(.pasteLastTray)
                }
                extraCell(
                    key: "T",
                    label: "Tray",
                    systemImage: "tray.full",
                    badge: trayBadge,
                    tone: .ink
                ) {
                    state.onAction?(.viewTray)
                }
            }
            if !hasSecondaryActions {
                keyboardLegend
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(gradient(from: tokens.stripBottom))
        .overlay(
            Rectangle()
                .fill(tokens.edge.color)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    private enum ExtraTone { case ink, accent }

    private var hasSecondaryActions: Bool {
        state.showCameraOption || state.showSelectionOption || state.showTrayOption
    }

    private var trayBadge: String {
        state.trayCount > 99 ? "99+" : "\(state.trayCount)"
    }

    private var keyboardLegend: some View {
        HStack(spacing: 8) {
            Button(action: cancelChord) {
                HStack(spacing: 4) {
                    smallKeyCap("Esc")
                    Text("Cancel")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel capture")
            .accessibilityLabel("Cancel capture")
            .onHover { inside in
                hoveredKey = inside ? "legend-cancel" : (hoveredKey == "legend-cancel" ? nil : hoveredKey)
                inside ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }

            Spacer(minLength: 12)

            Button(action: commitStart) {
                HStack(spacing: 4) {
                    smallKeyCap("↵", color: accent)
                    Text("Start")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isVideo ? "Start screen recording" : "Capture selected mode")
            .accessibilityLabel(isVideo ? "Start screen recording" : "Capture selected mode")
            .onHover { inside in
                hoveredKey = inside ? "legend-start" : (hoveredKey == "legend-start" ? nil : hoveredKey)
                inside ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
        }
        .font(.system(size: 9, weight: .medium))
        .tracking(0.9)
        .foregroundColor(Color(hex: tokens.inkFaintHex))
        .textCase(.uppercase)
        .frame(maxWidth: .infinity)
    }

    private func extraCell(
        key: String,
        label: String,
        systemImage: String,
        badge: String? = nil,
        tone: ExtraTone,
        action: @escaping () -> Void
    ) -> some View {
        let id = "extra_\(key)"
        let isHovered = hoveredKey == id
        let keyColor: Color = tone == .accent ? accent : Color(hex: tokens.inkHex)

        return Button(action: action) {
            HStack(spacing: 4) {
                smallKeyCap(key, color: keyColor)

                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(keyColor.opacity(0.9))

                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(0.7)
                    .foregroundColor(Color(hex: tokens.inkFaintHex))
                    .textCase(.uppercase)
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: tokens.inkFaintHex))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tokens.detailsBg.color)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(tokens.edge.color, lineWidth: 0.5)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? tokens.detailsBg.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredKey = inside ? id : (hoveredKey == id ? nil : hoveredKey)
            inside ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
        }
    }

    private func smallKeyCap(_ key: String, color: Color? = nil) -> some View {
        Text(key)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(color ?? Color(hex: tokens.inkHex))
            .frame(minWidth: key.count > 1 ? 24 : 14, minHeight: 14)
            .padding(.horizontal, key.count > 1 ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tokens.detailsBg.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(tokens.edgeStrong.color, lineWidth: 0.5)
            )
    }

    // MARK: - Helpers

    private func gradient(from stops: [GradientStop]) -> LinearGradient {
        LinearGradient(
            stops: stops.map { Gradient.Stop(color: Color(hex: $0.hex), location: $0.location) },
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tapAction(key: String) {
        let mode: CaptureMode
        switch key {
        case "A": mode = .region
        case "S": mode = .fullscreen
        case "D": mode = .window
        default: return
        }
        if isVideo {
            state.onAction?(.screenRecord(mode))
        } else {
            state.onAction?(.screenshot(mode))
        }
    }

    private func commitStart() {
        state.onStart?()
    }

    private func cancelChord() {
        state.onCancel?()
    }
}

// MARK: - Icons

private enum HUDIcon {
    case crop, display, window

    @ViewBuilder
    func view(color: Color, size: CGFloat) -> some View {
        switch self {
        case .crop:    CropIcon(color: color).frame(width: size, height: size)
        case .display: DisplayIcon(color: color).frame(width: size, height: size)
        case .window:  WindowIcon(color: color).frame(width: size, height: size)
        }
    }
}

private struct CropIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            // Outer L (top-left → bottom-right)
            let s = size.width
            let stroke = GraphicsContext.Shading.color(color)
            let strokeFaint = GraphicsContext.Shading.color(color.opacity(0.5))

            var p1 = Path()
            p1.move(to: CGPoint(x: s * 0.28, y: 0.08 * s))
            p1.addLine(to: CGPoint(x: s * 0.28, y: s * 0.72))
            p1.addLine(to: CGPoint(x: s * 0.92, y: s * 0.72))
            ctx.stroke(p1, with: stroke, lineWidth: 1.2)

            var p2 = Path()
            p2.move(to: CGPoint(x: s * 0.08, y: s * 0.28))
            p2.addLine(to: CGPoint(x: s * 0.72, y: s * 0.28))
            p2.addLine(to: CGPoint(x: s * 0.72, y: s * 0.92))
            ctx.stroke(p2, with: strokeFaint, lineWidth: 1.2)
        }
    }
}

private struct DisplayIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let stroke = GraphicsContext.Shading.color(color)
            let rect = CGRect(x: 0.08 * s, y: 0.16 * s, width: 0.84 * s, height: 0.56 * s)
            let body = Path(roundedRect: rect, cornerRadius: 1.4)
            ctx.stroke(body, with: stroke, lineWidth: 1.2)

            var stand = Path()
            stand.move(to: CGPoint(x: 0.5 * s, y: 0.72 * s))
            stand.addLine(to: CGPoint(x: 0.5 * s, y: 0.88 * s))
            stand.move(to: CGPoint(x: 0.33 * s, y: 0.88 * s))
            stand.addLine(to: CGPoint(x: 0.67 * s, y: 0.88 * s))
            ctx.stroke(stand, with: stroke, lineWidth: 1.2)
        }
    }
}

private struct WindowIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let stroke = GraphicsContext.Shading.color(color)
            let rect = CGRect(x: 0.10 * s, y: 0.16 * s, width: 0.80 * s, height: 0.68 * s)
            let body = Path(roundedRect: rect, cornerRadius: 1.6)
            ctx.stroke(body, with: stroke, lineWidth: 1.2)

            var titlebar = Path()
            titlebar.move(to: CGPoint(x: 0.10 * s, y: 0.34 * s))
            titlebar.addLine(to: CGPoint(x: 0.90 * s, y: 0.34 * s))
            ctx.stroke(titlebar, with: stroke, lineWidth: 1.2)

            let dotR: CGFloat = 0.04 * s
            for (i, opacity) in [(0, 1.0), (1, 0.55), (2, 0.35)] {
                let cx = 0.18 * s + CGFloat(i) * 0.10 * s
                let dot = Path(ellipseIn: CGRect(
                    x: cx - dotR, y: 0.25 * s - dotR,
                    width: dotR * 2, height: dotR * 2
                ))
                ctx.fill(dot, with: GraphicsContext.Shading.color(color.opacity(opacity)))
            }
        }
    }
}
