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
//    ├─ RECORDING OPTIONS (video mode only) ───────────────────────┤
//    │  Audio on/off   Mic on/off     Bubble on/off                │
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
    static let screenshotPanelHeight: CGFloat = 156
    static let videoPanelHeight: CGFloat = 194

    private var panel: NSPanel?
    let state = CaptureBarState()
    private var palette: Palette = .amber

    var frame: NSRect? { panel?.frame }

    /// Where the HUD will land for a given cursor position + position
    /// preference. Pulled out so `WallpaperLuminanceSampler` can sample
    /// the same rect we're about to draw into, with no chance of drift.
    static func expectedFrame(
        for mouseLocation: NSPoint,
        position: CaptureHUDPosition,
        mode: CaptureBarMode = .video
    ) -> NSRect {
        let panelHeight = Self.panelHeight(for: mode)
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

    static func panelHeight(for mode: CaptureBarMode) -> CGFloat {
        mode == .video ? videoPanelHeight : screenshotPanelHeight
    }

    private static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(v, hi))
    }

    func show(
        mode: CaptureBarMode,
        showCameraOption: Bool,
        showTrayOption: Bool,
        showSelectionOption: Bool,
        showMarkupOption: Bool,
        trayCount: Int,
        palette: Palette
    ) {
        dismiss()

        state.mode = mode
        state.showCameraOption = showCameraOption
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.showMarkupOption = showMarkupOption
        if showMarkupOption {
            state.reloadMarkupDestination()
        }
        state.trayCount = trayCount
        state.onModeChanged = nil
        self.palette = palette

        let hostingView = NSHostingView(rootView: CaptureHUDView(state: state, palette: palette))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let origin = Self.expectedFrame(
            for: NSEvent.mouseLocation,
            position: Self.captureHUDPosition,
            mode: mode
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
        p.hasShadow = false
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
        state.onModeChanged = { [weak self] mode in
            self?.resize(for: mode)
        }
    }

    func dismiss() {
        state.onAction = nil
        state.onStart = nil
        state.onCancel = nil
        state.onModeChanged = nil

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
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = hostingView
    }

    func toggleMode() {
        state.mode = (state.mode == .screenshot) ? .video : .screenshot
    }

    private func resize(for mode: CaptureBarMode) {
        guard let panel else { return }
        let height = Self.panelHeight(for: mode)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height

        if let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, panel.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first {
            let margin: CGFloat = 8
            let visible = screen.visibleFrame
            if frame.minY < visible.minY + margin {
                frame.origin.y = visible.minY + margin
            }
            if frame.maxY > visible.maxY - margin {
                frame.origin.y = visible.maxY - margin - height
            }
        }

        panel.setFrame(frame, display: true, animate: true)
    }

    private static var captureHUDPosition: CaptureHUDPosition {
        guard let raw = UserDefaults.standard.string(forKey: "captureHUDPosition"),
              let position = CaptureHUDPosition(rawValue: raw) else {
            return .fixed
        }
        return position
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
        isVideo ? Color.captureHex(tokens.recHex) : Color.captureHex(tokens.accentHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            primaryCells
            if isVideo {
                recordingOptionsStrip
            }
            bottomStrip
        }
        .frame(width: CaptureHUDPanel.panelWidth, height: CaptureHUDPanel.panelHeight(for: state.mode))
        .background(Color.captureHex(tokens.bgHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tokens.edgeStrong.color, lineWidth: 0.5)
        )
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
            ? Color.captureHex(tokens.recHex)
            : Color.captureHex(tokens.accentHex)
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
                        .stroke(Color.captureHex(tokens.inkFaintHex), lineWidth: 0.5)
                        .frame(width: 6, height: 6)
                }

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(isActive ? tabAccent : Color.captureHex(tokens.inkFaintHex))
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
                .foregroundColor(Color.captureHex(tokens.inkFaintHex))
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
        .background(Color.captureHex(tokens.bgHex).opacity(0.58))
    }

    private func primaryCell(key: String, icon: HUDIcon, label: String) -> some View {
        let isHovered = hoveredKey == key
        let isActive = captureMode(forKey: key) == state.selectedCaptureMode
        // Active beats hover for icon color; hover still adds the
        // glass-lift treatment so the user feels "I can switch here too".
        let iconColor: Color = (isActive || isHovered) ? accent : Color.captureHex(tokens.inkHex)

        return Button(action: { tapAction(key: key) }) {
            VStack(spacing: 6) {
                icon.view(color: iconColor, size: 18)
                keyChip(key, isActive: isActive)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(isActive ? accent : Color.captureHex(tokens.inkFaintHex))
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? accent.opacity(0.14)
                            : (isHovered ? tokens.detailsBg.color : Color.captureHex(tokens.bgHex).opacity(0.5))
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
            .foregroundColor(isActive ? accent : Color.captureHex(tokens.inkHex))
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
    }

    // MARK: - Recording options

    private var recordingOptionsStrip: some View {
        HStack(spacing: 6) {
            recordingOptionToggle(
                title: "Audio",
                systemImage: "speaker.wave.2",
                isOn: $state.screenRecordingIncludesSystemAudio
            )
            recordingOptionToggle(
                title: "Mic",
                systemImage: "mic",
                isOn: $state.screenRecordingIncludesMicrophone
            )
            recordingOptionToggle(
                title: "Bubble",
                systemImage: "video.circle",
                isOn: $state.screenRecordingShowsCameraBubble
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(tokens.detailsBg.color.opacity(0.46))
    }

    private func recordingOptionToggle(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        let id = "recording_\(title)"
        let isHovered = hoveredKey == id
        let enabled = isOn.wrappedValue

        return Button {
            isOn.wrappedValue.toggle()
            state.onAction?(nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(enabled ? accent : Color.captureHex(tokens.inkFaintHex))
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(Color.captureHex(tokens.inkHex))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(enabled ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(enabled ? accent : Color.captureHex(tokens.inkFaintHex))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(enabled ? accent.opacity(0.16) : tokens.detailsBg.color)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                enabled ? accent.opacity(0.55) : tokens.edgeStrong.color,
                                lineWidth: 0.5
                            )
                    )
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        enabled
                            ? accent.opacity(0.10)
                            : (isHovered ? tokens.detailsBg.color : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        enabled
                            ? accent.opacity(0.45)
                            : (isHovered ? tokens.edgeStrong.color : tokens.edge.color),
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) \(enabled ? "on" : "off") for screen recording")
        .onHover { inside in
            hoveredKey = inside ? id : (hoveredKey == id ? nil : hoveredKey)
            inside ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
        }
    }

    // MARK: - Bottom strip (extras)

    private var bottomStrip: some View {
        HStack(spacing: 4) {
            if state.showMarkupOption && !isVideo {
                extraCell(
                    key: "M",
                    label: "Markup",
                    systemImage: "pencil.tip.crop.circle",
                    tone: .accent,
                    isActive: state.markupDestinationEnabled
                ) {
                    state.markupDestinationEnabled.toggle()
                    state.onAction?(nil)
                }
                .help("Open the capture directly in Agent quick markup after A, S, D, or Return")
            }
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
            if !hasContextualActions {
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

    private var hasContextualActions: Bool {
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
        .foregroundColor(Color.captureHex(tokens.inkFaintHex))
        .textCase(.uppercase)
        .frame(maxWidth: .infinity)
    }

    private func extraCell(
        key: String,
        label: String,
        systemImage: String,
        badge: String? = nil,
        tone: ExtraTone,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let id = "extra_\(key)"
        let isHovered = hoveredKey == id
        let keyColor: Color = tone == .accent ? accent : Color.captureHex(tokens.inkHex)
        let foregroundColor: Color = isActive ? accent : Color.captureHex(tokens.inkFaintHex)
        let fillColor: Color = isActive
            ? accent.opacity(0.14)
            : (isHovered ? tokens.detailsBg.color : Color.clear)
        let strokeColor: Color = isActive
            ? accent.opacity(0.52)
            : (isHovered ? tokens.edgeStrong.color : Color.clear)

        return Button(action: action) {
            HStack(spacing: 4) {
                smallKeyCap(key, color: keyColor)

                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(keyColor.opacity(0.9))

                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(0.7)
                    .foregroundColor(foregroundColor)
                    .textCase(.uppercase)
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.captureHex(tokens.inkFaintHex))
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
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.5)
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
            .foregroundColor(color ?? Color.captureHex(tokens.inkHex))
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
            stops: stops.map { Gradient.Stop(color: Color.captureHex($0.hex), location: $0.location) },
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
            state.onAction?(state.markupDestinationEnabled ? .screenshotMarkup(mode) : .screenshot(mode))
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
