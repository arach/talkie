//
//  LivePreviewScreen.swift
//  Talkie
//
//  Mock screen preview for Live settings - shows HUD and Pill positions in context
//  The screen IS the control: click position dots to select
//

import SwiftUI
import TalkieKit

// MARK: - Main Preview Screen

struct LivePreviewScreen: View {
    @Binding var overlayStyle: OverlayStyle
    @Binding var hudPosition: IndicatorPosition
    @Binding var pillPosition: PillPosition
    @Binding var showOnAir: Bool

    @State private var isHovered = false

    // Mock screen dimensions (16:10 aspect ratio, generous sizing)
    private let screenWidth: CGFloat = 420
    private let screenHeight: CGFloat = 262

    var body: some View {
        ZStack {
            // Screen background
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

            // Content
            VStack(spacing: 0) {
                // Top area: HUD position markers + style preview
                topArea

                Spacer()

                // Bottom area: Pill position markers + mini pill
                bottomArea
            }
            .padding(16)

            // ON AIR indicator (below top-left dot, respects position marker space)
            if showOnAir {
                VStack {
                    HStack {
                        OnAirBadge()
                            .padding(.top, 36)  // Below the position dot row
                            .padding(.leading, 20)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(width: screenWidth, height: screenHeight)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Top Area (HUD)

    private var topArea: some View {
        VStack(spacing: 6) {
            // HUD position dots + style preview in a row
            HStack(alignment: .top) {
                PositionDot(
                    isSelected: hudPosition == .topLeft,
                    action: { hudPosition = .topLeft }
                )

                Spacer()

                // Center: HUD preview or position dot
                VStack(spacing: 4) {
                    PositionDot(
                        isSelected: hudPosition == .topCenter,
                        action: { hudPosition = .topCenter }
                    )

                    // Style preview (only if showsTopOverlay)
                    if overlayStyle.showsTopOverlay {
                        HUDStylePreview(style: overlayStyle)
                            .frame(width: 120, height: 28)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Spacer()

                PositionDot(
                    isSelected: hudPosition == .topRight,
                    action: { hudPosition = .topRight }
                )
            }
            .padding(.horizontal, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: overlayStyle.showsTopOverlay)
    }

    // MARK: - Bottom Area (Pill)

    private var bottomArea: some View {
        VStack(spacing: 6) {
            // Pill preview at selected position
            HStack {
                if pillPosition == .bottomLeft {
                    AnimatedMiniPill(isRecording: isHovered)
                    Spacer()
                } else if pillPosition == .bottomCenter {
                    Spacer()
                    AnimatedMiniPill(isRecording: isHovered)
                    Spacer()
                } else if pillPosition == .bottomRight {
                    Spacer()
                    AnimatedMiniPill(isRecording: isHovered)
                } else {
                    Spacer()
                }
            }
            .frame(height: 24)
            .opacity(pillPosition != .topCenter ? 1 : 0)

            // Pill position dots (bottom row)
            HStack {
                PositionDot(
                    isSelected: pillPosition == .bottomLeft,
                    action: { pillPosition = .bottomLeft }
                )

                Spacer()

                PositionDot(
                    isSelected: pillPosition == .bottomCenter,
                    action: { pillPosition = .bottomCenter }
                )

                Spacer()

                PositionDot(
                    isSelected: pillPosition == .bottomRight,
                    action: { pillPosition = .bottomRight }
                )
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Position Dot

private struct PositionDot: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private let size: CGFloat = 12

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer circle (always visible)
                Circle()
                    .stroke(isSelected ? Color.cyan : Color.white.opacity(0.4), lineWidth: 1.5)
                    .frame(width: size, height: size)

                // Inner fill (selected state)
                if isSelected {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: size - 4, height: size - 4)
                }
            }
            .scaleEffect(isHovered ? 1.3 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(isSelected ? "Selected" : "Click to select")
    }
}

// MARK: - HUD Style Preview

private struct HUDStylePreview: View {
    let style: OverlayStyle

    var body: some View {
        Group {
            switch style {
            case .particles:
                WavyParticlesPreview(calm: false)
            case .particlesCalm:
                WavyParticlesPreview(calm: true)
            case .waveform:
                WaveformBarsPreview(sensitive: false)
            case .waveformSensitive:
                WaveformBarsPreview(sensitive: true)
            case .pillOnly:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Animated Mini Pill

private struct AnimatedMiniPill: View {
    let isRecording: Bool

    var body: some View {
        Group {
            if isRecording {
                // Expanded recording state
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .overlay(
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 10, height: 10)
                        )

                    Text("0:03")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                        )
                )
            } else {
                // Idle state: flat wide capsule
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 24, height: 6)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRecording)
    }
}

// MARK: - ON AIR Badge (Mini version of OnAirIndicator)

private struct OnAirBadge: View {
    @State private var glowPhase: CGFloat = 0

    var body: some View {
        Text("ON AIR")
            .font(.system(size: 6, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(.white)
            .shadow(color: .red.opacity(0.8), radius: 2)
            .shadow(color: .red.opacity(0.5), radius: 4)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                ZStack {
                    // Outer glow
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.3), Color.orange.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 4)
                        .opacity(0.6 + glowPhase * 0.4)

                    // Inner background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.15), Color.red.opacity(0.25)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Border glow
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .shadow(color: .red.opacity(0.5), radius: 2)
                }
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPhase = 1.0
                }
            }
    }
}

// MARK: - Style Selector (HUD styles only, no "Pill Only")

struct LiveStyleSelector: View {
    @Binding var selection: OverlayStyle

    // Only show the main HUD styles
    private let options: [(style: OverlayStyle, label: String, icon: String)] = [
        (.particles, "Particles", "sparkles"),
        (.waveform, "Waveform", "waveform")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.style) { option in
                StylePill(
                    label: option.label,
                    icon: option.icon,
                    isSelected: isSelected(option.style),
                    action: { selectStyle(option.style) }
                )
            }
        }
    }

    private func isSelected(_ style: OverlayStyle) -> Bool {
        switch style {
        case .particles:
            return selection == .particles || selection == .particlesCalm
        case .waveform:
            return selection == .waveform || selection == .waveformSensitive
        default:
            return selection == style
        }
    }

    private func selectStyle(_ style: OverlayStyle) {
        // Preserve "calm" or "sensitive" variant if already in that family
        switch style {
        case .particles:
            if selection != .particles && selection != .particlesCalm {
                selection = .particles
            }
        case .waveform:
            if selection != .waveform && selection != .waveformSensitive {
                selection = .waveform
            }
        default:
            selection = style
        }
    }
}

private struct StylePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.cyan.opacity(0.8) : (isHovered ? TalkieTheme.hover : Color.clear))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.cyan : TalkieTheme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview("LivePreviewScreen") {
    VStack(spacing: 20) {
        LivePreviewScreen(
            overlayStyle: .constant(.particles),
            hudPosition: .constant(.topCenter),
            pillPosition: .constant(.bottomCenter),
            showOnAir: .constant(true)
        )

        LiveStyleSelector(selection: .constant(.particles))
    }
    .padding(40)
    .background(Color(white: 0.1))
}
