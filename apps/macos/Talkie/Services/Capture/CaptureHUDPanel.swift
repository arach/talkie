//
//  CaptureHUDPanel.swift
//  Talkie
//
//  Grid-style HUD bar for the capture chord (Hyper+S / Hyper+R).
//  Alternative to the radial pie menu — a compact 3-row grid near the cursor.
//
//  Row 1: Dimension presets + settings
//  Row 2: A (Area), S (Screen), D (Window) — primary actions
//  Row 3: Mode toggle, Camera (C), Save Selection (N), Tray (W)
//

import AppKit
import SwiftUI

// MARK: - Panel

@MainActor
final class CaptureHUDPanel {

    private var panel: NSPanel?
    let state = CaptureBarState()

    var frame: NSRect? { panel?.frame }

    func show(mode: CaptureBarMode, showTrayOption: Bool, showSelectionOption: Bool, trayCount: Int) {
        dismiss()

        state.mode = mode
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.trayCount = trayCount

        let hostingView = NSHostingView(rootView: CaptureHUDView(state: state))
        hostingView.layer?.isOpaque = false

        let width: CGFloat = 280
        let height: CGFloat = 160

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
        p.sharingType = .none
        p.hidesOnDeactivate = false
        p.canHide = false

        // Position near cursor, clamped to screen bounds
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

    func toggleMode() {
        state.mode = (state.mode == .screenshot) ? .video : .screenshot
    }
}

// MARK: - HUD SwiftUI View

private struct CaptureHUDView: View {
    @Bindable var state: CaptureBarState

    @State private var appeared = false
    @State private var hoveredKey: String?

    private var isVideo: Bool { state.mode == .video }

    private var borderGradient: LinearGradient {
        if isVideo {
            return LinearGradient(
                colors: [Color.red.opacity(0.4), Color.red.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var chromeBaseColor: Color {
        isVideo
            ? Color(red: 0.11, green: 0.045, blue: 0.055)
            : Color(red: 0.055, green: 0.06, blue: 0.075)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Mode indicator + dimensions
            row1DimensionsBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // Row 2: Primary capture actions (A/S/D)
            row2CaptureActions
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // Row 3: Mode toggle + extras
            row3Extras
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(chromeBaseColor.opacity(0.96))

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.09),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isVideo ? 0.04 : 0.05),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 8,
                            endRadius: 120
                        )
                    )

                if isVideo {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.06))
                }
            }
            .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderGradient, lineWidth: 0.75)
        )
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.mode)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredKey)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Row 1: Dimensions & Mode

    private var row1DimensionsBar: some View {
        HStack(spacing: 6) {
            // Mode indicator
            HStack(spacing: 4) {
                if isVideo {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .modifier(HUDPulseModifier())
                    Text("Video")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Screenshot")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Row 2: Primary Capture Actions

    private var row2CaptureActions: some View {
        HStack(spacing: 8) {
            captureCell("A", label: "Region", icon: "crop")
            captureCell("S", label: "Screen", icon: "display")
            captureCell("D", label: "Window", icon: "macwindow")
        }
    }

    private func captureCell(_ key: String, label: String, icon: String) -> some View {
        let isHovered = hoveredKey == key

        return Button(action: { tapAction(key: key) }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 0.95 : 0.7))

                HStack(spacing: 3) {
                    Text(key)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isVideo && isHovered
                            ? Color.red.opacity(0.3)
                            : Color.white.opacity(isHovered ? 0.15 : 0),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { inside in
            hoveredKey = inside ? key : (hoveredKey == key ? nil : hoveredKey)
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Row 3: Mode + Extras

    private var row3Extras: some View {
        HStack(spacing: 8) {
            // Tab / Mode toggle
            extraCell("⇥", label: "Mode", color: .white) {
                state.mode = state.mode == .screenshot ? .video : .screenshot
                state.onAction?(nil)
            }

            // Camera toggle
            extraCell("C", label: "Camera", color: .orange) {
                state.onAction?(.toggleCamera)
            }

            if state.showSelectionOption {
                extraCell("N", label: "Save Selection", color: .mint) {
                    state.onAction?(.saveSelection)
                }
            }

            if state.showTrayOption {
                // Paste last
                extraCell("F", label: "Paste", color: .green) {
                    state.onAction?(.pasteLastTray)
                }

                // Tray viewer
                extraCell("W", label: "Tray (\(state.trayCount))", color: .cyan) {
                    state.onAction?(.viewTray)
                }
            }
        }
    }

    private func extraCell(_ key: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredKey == "extra_\(key)"

        return Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                    )
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? color.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { inside in
            hoveredKey = inside ? "extra_\(key)" : (hoveredKey == "extra_\(key)" ? nil : hoveredKey)
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Actions

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
}

// MARK: - Pulse Animation

private struct HUDPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
