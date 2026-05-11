//
//  CaptureRadialPanel.swift
//  Talkie
//
//  Compact radial pie menu for the capture chord (Hyper+S / Hyper+R).
//  Replaces the linear 480px CaptureBarPanel with a ~160px radial near the cursor.
//
//  Center: App icon on glass circle
//  Ring: A (Area), S (Screen), D (Window) at 10, 12, 2 o'clock
//  Below: C (camera), N (save selection), F (paste), W (tray) as small dots
//  Mode indicator below center
//

import AppKit
import SwiftUI

// MARK: - Panel

@MainActor
final class CaptureRadialPanel {

    private var panel: NSPanel?
    let state = CaptureBarState()  // Reuse existing state type

    var frame: NSRect? { panel?.frame }

    func show(mode: CaptureBarMode, showTrayOption: Bool, showSelectionOption: Bool, trayCount: Int) {
        dismiss()

        state.mode = mode
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.trayCount = trayCount

        let hostingView = NSHostingView(rootView: CaptureRadialView(state: state))
        hostingView.layer?.isOpaque = false

        let size: CGFloat = 180

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
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

        // Position near cursor, clamped to screen bounds
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let offset: CGFloat = 20  // Offset from cursor
        var x = mouseLocation.x - size / 2
        var y = mouseLocation.y - size / 2 - offset

        // Clamp to screen with margin
        let margin: CGFloat = 8
        x = max(screen.frame.minX + margin, min(x, screen.frame.maxX - size - margin))
        y = max(screen.frame.minY + margin, min(y, screen.frame.maxY - size - margin))

        p.setFrameOrigin(NSPoint(x: x, y: y))

        // Appear with scale animation
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

    func toggleMode() {
        state.mode = (state.mode == .screenshot) ? .video : .screenshot
    }
}

// MARK: - Radial SwiftUI View

private struct CaptureRadialView: View {
    @Bindable var state: CaptureBarState

    @State private var appeared = false
    @State private var hoveredKey: String?

    private var isVideo: Bool { state.mode == .video }

    private let ringRadius: CGFloat = 56
    private let centerSize: CGFloat = 48
    private let segmentSize: CGFloat = 34
    private let dotSize: CGFloat = 24

    // Segment positions: 10 o'clock, 12 o'clock, 2 o'clock
    // Angles from top (0°), clockwise: -60°, 0°, +60°
    private let segments: [(key: String, label: String, angleDeg: Double)] = [
        ("A", "Area", -55),
        ("S", "Screen", 0),
        ("D", "Window", 55),
    ]

    var body: some View {
        ZStack {
            // Main glass backdrop circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                center: .top,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isVideo
                                ? LinearGradient(
                                    colors: [Color.red.opacity(0.4), Color.red.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            // Video mode ambient glow
            if isVideo {
                Circle()
                    .fill(Color.red.opacity(0.04))
                    .frame(width: 160, height: 160)
            }

            // Center: App icon (click to toggle mode)
            centerIcon
                .contentShape(Circle())
                .onTapGesture {
                    state.mode = state.mode == .screenshot ? .video : .screenshot
                    state.onAction?(nil)  // signal interaction to reset timeout
                }
                .onHover { inside in
                    hoveredKey = inside ? "center" : (hoveredKey == "center" ? nil : hoveredKey)
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .scaleEffect(hoveredKey == "center" ? 1.12 : 1.0)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

            // A / S / D segments around the ring
            // Uses .position() instead of .offset() so hit testing follows the visual position
            ForEach(Array(segments.enumerated()), id: \.offset) { index, seg in
                let angle = Angle.degrees(seg.angleDeg - 90)
                let xPos = 90 + ringRadius * cos(angle.radians)
                let yPos = 90 + ringRadius * sin(angle.radians)

                segmentBubble(key: seg.key, label: seg.label)
                    .contentShape(Circle())
                    .onTapGesture { tapSegment(key: seg.key) }
                    .onHover { inside in
                        hoveredKey = inside ? seg.key : (hoveredKey == seg.key ? nil : hoveredKey)
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .scaleEffect(hoveredKey == seg.key ? 1.12 : 1.0)
                    .position(x: xPos, y: yPos)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.7)
                            .delay(Double(index) * 0.04 + 0.06),
                        value: appeared
                    )
            }

            // Secondary dots: C (camera) and W (tray) below
            secondaryDots
                .position(x: 90, y: 90 + 56)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.7).delay(0.2),
                    value: appeared
                )

            // Mode indicator
            modeIndicator
                .offset(y: 16)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(0.15), value: appeared)
        }
        .frame(width: 180, height: 180)
        .animation(.easeInOut(duration: 0.25), value: state.mode)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredKey)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    // MARK: - Center Icon

    private var centerIcon: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: centerSize, height: centerSize)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )

            // App icon
            AppIconView(bundleIdentifier: Bundle.main.bundleIdentifier ?? "", size: 28)
        }
    }

    // MARK: - Segment Bubble (A/S/D)

    private func segmentBubble(key: String, label: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: segmentSize, height: segmentSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                Text(key)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Secondary Dots

    private var secondaryDots: some View {
        HStack(spacing: 12) {
            // Camera toggle
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
                    )

                Image(systemName: "video.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
            }
            .contentShape(Circle())
            .onTapGesture { state.onAction?(.toggleCamera) }
            .onHover { inside in
                hoveredKey = inside ? "C" : (hoveredKey == "C" ? nil : hoveredKey)
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
                .scaleEffect(hoveredKey == "C" ? 1.12 : 1.0)
                .help("Toggle camera")

            if state.showSelectionOption {
                ZStack {
                    Circle()
                        .fill(Color.mint.opacity(0.15))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.mint.opacity(0.4), lineWidth: 0.5)
                        )

                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mint)
                }
                .contentShape(Circle())
                .onTapGesture { state.onAction?(.saveSelection) }
                .onHover { inside in
                    hoveredKey = inside ? "N" : (hoveredKey == "N" ? nil : hoveredKey)
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .scaleEffect(hoveredKey == "N" ? 1.12 : 1.0)
                .help("Save staged selection to a note")
            }

            // Paste last
            if state.showTrayOption {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.green.opacity(0.4), lineWidth: 0.5)
                        )

                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
                .contentShape(Circle())
                .onTapGesture { state.onAction?(.pasteLastTray) }
                .onHover { inside in
                    hoveredKey = inside ? "F" : (hoveredKey == "F" ? nil : hoveredKey)
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .scaleEffect(hoveredKey == "F" ? 1.12 : 1.0)
                .help("Paste last screenshot")
            }

            // Tray
            if state.showTrayOption {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.5)
                        )

                    Image(systemName: "tray.full")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyan)
                }
                .overlay(alignment: .topTrailing) {
                    if state.trayCount > 0 {
                        Text("\(state.trayCount)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.cyan.opacity(0.7)))
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Circle())
                .onTapGesture { state.onAction?(.viewTray) }
                .onHover { inside in
                    hoveredKey = inside ? "W" : (hoveredKey == "W" ? nil : hoveredKey)
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .scaleEffect(hoveredKey == "W" ? 1.12 : 1.0)
                .help("View tray")
            }
        }
    }

    // MARK: - Tap Helpers

    private func tapSegment(key: String) {
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

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        HStack(spacing: 4) {
            if isVideo {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                    .modifier(RadialPulseModifier())
                Text("Video")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.red.opacity(0.8))
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.4))
                Text("Screenshot")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Pulse Animation

private struct RadialPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
