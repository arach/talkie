//
//  LivePreviewScreen.swift
//  TalkieKit
//
//  Shared overlay settings types and preview component
//  Used by both Talkie and TalkieLive for visual feedback configuration
//

import SwiftUI

// MARK: - Overlay Types

/// Visual style for the recording overlay
public enum OverlayStyle: String, CaseIterable, Codable {
    case particles = "particles"
    case particlesCalm = "particlesCalm"
    case waveform = "waveform"
    case waveformSensitive = "waveformSensitive"
    case pillOnly = "pillOnly"

    public var displayName: String {
        switch self {
        case .particles: return "Particles"
        case .particlesCalm: return "Particles (Calm)"
        case .waveform: return "Waveform"
        case .waveformSensitive: return "Waveform (Sensitive)"
        case .pillOnly: return "Pill Only"
        }
    }

    public var description: String {
        switch self {
        case .particles: return "Responsive particles that react to your voice"
        case .particlesCalm: return "Smooth, relaxed particle flow"
        case .waveform: return "Scrolling audio bars"
        case .waveformSensitive: return "Waveform with enhanced low-level response"
        case .pillOnly: return "No top overlay, just the bottom pill"
        }
    }

    public var showsTopOverlay: Bool {
        switch self {
        case .particles, .particlesCalm, .waveform, .waveformSensitive: return true
        case .pillOnly: return false
        }
    }
}

/// Position for the recording indicator (particles/waveform overlay)
public enum IndicatorPosition: String, CaseIterable, Codable {
    case topCenter = "topCenter"
    case topLeft = "topLeft"
    case topRight = "topRight"

    public var displayName: String {
        switch self {
        case .topCenter: return "Top Center"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }

    public var description: String {
        switch self {
        case .topCenter: return "Centered at top of screen"
        case .topLeft: return "Upper left corner"
        case .topRight: return "Upper right corner"
        }
    }
}

/// Position for the floating pill widget
public enum PillPosition: String, CaseIterable, Codable {
    case bottomCenter = "bottomCenter"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case topCenter = "topCenter"

    public var displayName: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topCenter: return "Top Center"
        }
    }

    public var description: String {
        switch self {
        case .bottomCenter: return "Centered at bottom edge"
        case .bottomLeft: return "Lower left corner"
        case .bottomRight: return "Lower right corner"
        case .topCenter: return "Centered at top edge"
        }
    }
}

// MARK: - Live Preview Screen

/// Mock screen preview for Live settings - shows HUD and Pill positions in context
/// The screen IS the control: click position dots to select
public struct LivePreviewScreen: View {
    @Binding public var overlayStyle: OverlayStyle
    @Binding public var hudPosition: IndicatorPosition
    @Binding public var pillPosition: PillPosition
    @Binding public var showOnAir: Bool

    @State private var isHovered = false

    // Mock screen dimensions (16:10 aspect ratio)
    private let screenWidth: CGFloat = 420
    private let screenHeight: CGFloat = 262

    public init(
        overlayStyle: Binding<OverlayStyle>,
        hudPosition: Binding<IndicatorPosition>,
        pillPosition: Binding<PillPosition>,
        showOnAir: Binding<Bool>
    ) {
        self._overlayStyle = overlayStyle
        self._hudPosition = hudPosition
        self._pillPosition = pillPosition
        self._showOnAir = showOnAir
    }

    public var body: some View {
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

            // ON AIR indicator
            if showOnAir {
                VStack {
                    HStack {
                        OnAirBadge()
                            .padding(.top, 36)
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
            Text("HUD POSITION")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .tracking(0.5)

            HStack(alignment: .top) {
                PositionDot(
                    isSelected: hudPosition == .topLeft,
                    action: { hudPosition = .topLeft }
                )

                Spacer()

                VStack(spacing: 4) {
                    PositionDot(
                        isSelected: hudPosition == .topCenter,
                        action: { hudPosition = .topCenter }
                    )

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

            Text("PILL POSITION")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .tracking(0.5)
        }
    }
}

// MARK: - Position Dot

private struct PositionDot: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var pulsePhase: CGFloat = 0

    private let size: CGFloat = 16
    private let hitSize: CGFloat = 28

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: hitSize, height: hitSize)

                if isHovered && !isSelected {
                    Circle()
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                        .frame(width: size + 6, height: size + 6)
                        .scaleEffect(1.0 + pulsePhase * 0.2)
                        .opacity(1.0 - pulsePhase * 0.5)
                }

                Circle()
                    .stroke(
                        isSelected ? Color.cyan : (isHovered ? Color.cyan.opacity(0.8) : Color.white.opacity(0.4)),
                        lineWidth: isHovered ? 2 : 1.5
                    )
                    .frame(width: size, height: size)

                Circle()
                    .fill(isSelected ? Color.cyan : (isHovered ? Color.cyan.opacity(0.3) : Color.clear))
                    .frame(width: size - 4, height: size - 4)

                if isHovered && !isSelected {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .scaleEffect(isHovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1
                }
            } else {
                pulsePhase = 0
            }
        }
        .help(isSelected ? "Current position" : "Click to move here")
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

// MARK: - ON AIR Badge

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

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.15), Color.red.opacity(0.25)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

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

// MARK: - Wavy Particles Preview

public struct WavyParticlesPreview: View {
    public let calm: Bool

    private let particleCount = 16

    public init(calm: Bool) {
        self.calm = calm
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(TalkieTheme.textTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(TalkieTheme.divider, lineWidth: 1)
                )

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let centerY = size.height / 2

                    let baseSpeed: CGFloat = calm ? 0.05 : 0.2
                    let waveSpeed: CGFloat = calm ? 1.0 : 3.5
                    let amplitude: CGFloat = calm ? 5 : 15

                    for i in 0..<particleCount {
                        let seed = Double(i) * 1.618

                        let speed = baseSpeed + CGFloat(seed.truncatingRemainder(dividingBy: 0.3))
                        let xProgress = (time * Double(speed) + seed).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(xProgress) * size.width

                        let wave = sin(time * Double(waveSpeed) + seed * 4) * Double(amplitude)
                        let y = centerY + CGFloat(wave)

                        let particleSize: CGFloat = calm ? 3.0 : 2.5
                        let opacity = 0.5 + sin(seed * 3) * 0.3

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )

                        context.fill(
                            Circle().path(in: rect),
                            with: .color(Color.white.opacity(opacity))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Waveform Bars Preview

public struct WaveformBarsPreview: View {
    public let sensitive: Bool

    private let barCount = 12

    public init(sensitive: Bool) {
        self.sensitive = sensitive
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(TalkieTheme.textTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(TalkieTheme.divider, lineWidth: 1)
                )

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let barWidth: CGFloat = (size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
                    let centerY = size.height / 2
                    let maxHeight = size.height * 0.7

                    let amplitude: CGFloat = sensitive ? 1.0 : 0.4
                    let speed: CGFloat = sensitive ? 3.5 : 1.8

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barWidth + 2)

                        let wave = sin(time * Double(speed) + Double(i) * 0.6) * Double(amplitude)
                        let barHeight = max(4, (wave * 0.5 + 0.5) * Double(maxHeight))

                        let rect = CGRect(
                            x: x,
                            y: centerY - CGFloat(barHeight) / 2,
                            width: barWidth,
                            height: CGFloat(barHeight)
                        )

                        let opacity = 0.6 + wave * 0.3
                        context.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(Color.gray.opacity(opacity))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Live Style Selector

/// Selector for HUD overlay styles (particles or waveform)
public struct LiveStyleSelector: View {
    @Binding public var selection: OverlayStyle

    private let options: [(style: OverlayStyle, label: String, icon: String)] = [
        (.particles, "Particles", "sparkles"),
        (.waveform, "Waveform", "waveform")
    ]

    public init(selection: Binding<OverlayStyle>) {
        self._selection = selection
    }

    public var body: some View {
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
