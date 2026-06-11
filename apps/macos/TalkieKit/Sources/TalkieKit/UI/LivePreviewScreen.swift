//
//  LivePreviewScreen.swift
//  TalkieKit
//
//  Shared overlay settings types and preview component
//  Used by both Talkie and TalkieAgent for visual feedback configuration
//

import SwiftUI

// MARK: - Overlay Types

/// Visual style for the recording overlay
public enum OverlayStyle: String, CaseIterable, Codable {
    case particles = "particles"
    case particlesCalm = "particlesCalm"
    case waveform = "waveform"
    case waveformSensitive = "waveformSensitive"
    case island = "island"
    case pillOnly = "pillOnly"

    public var displayName: String {
        switch self {
        case .particles: return "Particles"
        case .particlesCalm: return "Particles (Calm)"
        case .waveform: return "Waveform"
        case .waveformSensitive: return "Waveform (Sensitive)"
        case .island: return "Island"
        case .pillOnly: return "Pill Only"
        }
    }

    public var description: String {
        switch self {
        case .particles: return "Responsive particles that react to your voice"
        case .particlesCalm: return "Smooth, relaxed particle flow"
        case .waveform: return "Scrolling audio bars"
        case .waveformSensitive: return "Waveform with enhanced low-level response"
        case .island: return "Dark oval pill shapes that pulse with your voice"
        case .pillOnly: return "No top overlay, just the bottom pill"
        }
    }

    public var showsTopOverlay: Bool {
        switch self {
        case .particles, .particlesCalm, .waveform, .waveformSensitive, .island: return true
        case .pillOnly: return false
        }
    }
}

public struct IslandVisualizationSettings: Equatable, Sendable {
    public static let defaultValue = IslandVisualizationSettings()

    public var motion: Double
    public var reactivity: Double
    public var shape: Double

    public init(
        motion: Double = 0.38,
        reactivity: Double = 0.58,
        shape: Double = 0.50
    ) {
        self.motion = Self.clamp(motion)
        self.reactivity = Self.clamp(reactivity)
        self.shape = Self.clamp(shape)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
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

/// Preview surface for Live settings with fixed top and bottom anchor positions.
public struct LivePreviewScreen: View {
    @Binding public var overlayStyle: OverlayStyle
    @Binding public var hudPlacement: NormalizedPlacement
    @Binding public var pillEnabled: Bool
    @Binding public var pillPlacement: NormalizedPlacement
    public let islandSettings: IslandVisualizationSettings
    public let accentTint: Color

    private let screenWidth: CGFloat = 420
    private let screenHeight: CGFloat = 238
    private let topPositions: [IndicatorPosition] = [.topLeft, .topCenter, .topRight]
    private let bottomPositions: [PillPosition] = [.bottomLeft, .bottomCenter, .bottomRight]

    public init(
        overlayStyle: Binding<OverlayStyle>,
        hudPlacement: Binding<NormalizedPlacement>,
        pillEnabled: Binding<Bool>,
        pillPlacement: Binding<NormalizedPlacement>,
        islandSettings: IslandVisualizationSettings = .defaultValue,
        accentTint: Color = TalkieTheme.accent
    ) {
        self._overlayStyle = overlayStyle
        self._hudPlacement = hudPlacement
        self._pillEnabled = pillEnabled
        self._pillPlacement = pillPlacement
        self.islandSettings = islandSettings
        self.accentTint = accentTint
    }

    public var body: some View {
        ZStack {
            PreviewSurfaceFrame()

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ForEach(topPositions, id: \.rawValue) { position in
                        PreviewSlotMarker(
                            isSelected: overlaySelection == position,
                            tint: accentTint
                        )
                    }
                }
                .padding(.top, 16)

                Spacer()

                HStack(spacing: 14) {
                    ForEach(bottomPositions, id: \.rawValue) { position in
                        PreviewSlotMarker(
                            isSelected: pillSelection == position,
                            tint: TalkieTheme.textPrimary
                        )
                    }
                }
                .padding(.bottom, 16)
            }

            if overlayStyle.showsTopOverlay {
                PreviewTopBar(style: overlayStyle, islandSettings: islandSettings)
                    .frame(width: overlayPreviewWidth, height: overlayPreviewHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overlayAlignment)
                    .padding(.top, 34)
                    .padding(.horizontal, 24)
            }

            if pillEnabled {
                PreviewRecordingPill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pillAlignment)
                    .padding(.bottom, 34)
                    .padding(.horizontal, 24)
            }
        }
        .frame(width: screenWidth, height: screenHeight)
    }

    private var overlaySelection: IndicatorPosition {
        hudPlacement.nearestIndicatorPosition
    }

    private var overlayPreviewWidth: CGFloat {
        overlayStyle == .island ? 148 : 124
    }

    private var overlayPreviewHeight: CGFloat {
        overlayStyle == .island ? 30 : 26
    }

    private var pillSelection: PillPosition {
        let nearest = pillPlacement.nearestPillPosition
        return nearest == .topCenter ? .bottomCenter : nearest
    }

    private var overlayAlignment: Alignment {
        switch overlaySelection {
        case .topLeft:
            return .topLeading
        case .topCenter:
            return .top
        case .topRight:
            return .topTrailing
        }
    }

    private var pillAlignment: Alignment {
        switch pillSelection {
        case .bottomLeft:
            return .bottomLeading
        case .bottomCenter:
            return .bottom
        case .bottomRight:
            return .bottomTrailing
        case .topCenter:
            return .bottom
        }
    }
}

private struct PreviewSurfaceFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(
                LinearGradient(
                    colors: [
                        TalkieTheme.surfaceElevated,
                        TalkieTheme.backgroundSecondary
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(TalkieTheme.divider.opacity(0.9), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TalkieTheme.divider.opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.top, 38)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TalkieTheme.divider.opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 38)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
    }
}

private struct PreviewSlotMarker: View {
    let isSelected: Bool
    let tint: Color

    var body: some View {
        Capsule()
            .fill(isSelected ? tint.opacity(0.9) : TalkieTheme.hover.opacity(0.7))
            .frame(width: isSelected ? 26 : 18, height: 5)
            .overlay(
                Capsule()
                    .stroke(isSelected ? tint.opacity(0.95) : TalkieTheme.divider, lineWidth: 0.5)
            )
            .shadow(color: isSelected ? tint.opacity(0.18) : .clear, radius: 4)
    }
}

private struct PreviewTopBar: View {
    let style: OverlayStyle
    let islandSettings: IslandVisualizationSettings

    var body: some View {
        ZStack {
            previewContent
                .padding(previewPadding)

            if style == .island {
                HStack {
                    PreviewIslandIcon(systemImage: "xmark")
                    Spacer(minLength: 0)
                    PreviewIslandStopIcon()
                }
                .padding(.horizontal, 11)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(style == .island ? Color.black.opacity(0.92) : TalkieTheme.surfaceElevated.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(style == .island ? Color.white.opacity(0.12) : TalkieTheme.divider, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var previewContent: some View {
        switch style {
        case .particles:
            WavyParticlesPreview(calm: false)
        case .particlesCalm:
            WavyParticlesPreview(calm: true)
        case .waveform:
            WaveformBarsPreview(sensitive: false)
        case .waveformSensitive:
            WaveformBarsPreview(sensitive: true)
        case .island:
            IslandPillShapesPreview(settings: islandSettings)
        case .pillOnly:
            EmptyView()
        }
    }

    private var previewPadding: EdgeInsets {
        style == .island
            ? EdgeInsets(top: 6, leading: 31, bottom: 6, trailing: 31)
            : EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
    }

    private var cornerRadius: CGFloat {
        style == .island ? 15 : 9
    }
}

private struct PreviewIslandIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.56))
            .frame(width: 12, height: 12)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
    }
}

private struct PreviewIslandStopIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.58))
            .frame(width: 7, height: 7)
            .frame(width: 12, height: 12)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
    }
}

private struct PreviewRecordingPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .fill(Color.red.opacity(0.22))
                        .frame(width: 12, height: 12)
                )

            Text("REC")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(TalkieTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(TalkieTheme.surfaceElevated.opacity(0.98))
                .overlay(
                    Capsule()
                        .stroke(TalkieTheme.divider, lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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

// MARK: - Island Preview

public struct IslandPillShapesPreview: View {
    public let settings: IslandVisualizationSettings

    public init(settings: IslandVisualizationSettings = .defaultValue) {
        self.settings = settings
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let speed = CGFloat(settings.motion)
                let reactivity = CGFloat(settings.reactivity)
                let density = CGFloat(settings.shape)
                let speedAmount = max(0.12, speed)
                let voiceWave = CGFloat((sin(time * (1.9 + Double(reactivity) * 1.55)) + 1) / 2)
                let animatedLevel = 0.14 + voiceWave * 0.20 * (0.45 + reactivity)
                let particleCount = Int(16 + density * 18)
                let flowSpeed = 0.18 + Double(speedAmount) * 0.52
                let waveSpeed = 1.25 + Double(speedAmount) * 1.15
                let waveAmplitude = (0.08 + Double(animatedLevel) * (0.42 + Double(reactivity) * 0.22)) * Double(size.height) * 0.5
                let baseSize = 1.2 + density * 0.9
                let levelBonus = animatedLevel * (1.0 + reactivity * 1.35)

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749
                    let speedVariation = seed.truncatingRemainder(dividingBy: 1.0) * 0.06
                    let xProgress = (time * (flowSpeed + speedVariation) + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(xProgress) * size.width
                    let laneOffset = (Double(i % 9) / 8.0 - 0.5) * 0.38
                    let primaryWave = sin(time * waveSpeed + seed * 4.0)
                    let secondaryWave = sin(time * (waveSpeed * 0.48) + seed * 6.0) * 0.28
                    let y = centerY + CGFloat((primaryWave + secondaryWave + laneOffset) * waveAmplitude)
                    let sizeScale = CGFloat(0.68 + sin(seed * 5.0) * 0.32)
                    let particleSize = max(1.0, baseSize + levelBonus * sizeScale)
                    let edgeFade = min(xProgress * 3.0, 1.0) * min((1.0 - xProgress) * 2.0, 1.0)
                    let shimmer = 0.72 + sin(time * 2.2 + seed * 3.0) * 0.18
                    let opacityScale = 0.58 + sin(seed * 3.0) * 0.34
                    let opacity = max(
                        0.10,
                        (0.18 + Double(animatedLevel) * (0.32 + Double(reactivity) * 0.18)) * edgeFade * shimmer * opacityScale
                    )

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(opacity)))
                }

                if settings.motion > 0.05 {
                    let glintWidth = max(16, size.width * (0.10 + animatedLevel * 0.08))
                    let glintXProgress = CGFloat((time * (0.18 + Double(speedAmount) * 0.34)).truncatingRemainder(dividingBy: 1))
                    let glintX = glintXProgress * (size.width + glintWidth) - glintWidth
                    let glintRect = CGRect(x: glintX, y: 1.6, width: glintWidth, height: 0.8)
                    context.fill(
                        RoundedRectangle(cornerRadius: 0.5).path(in: glintRect),
                        with: .color(Color.white.opacity(0.035 + animatedLevel * 0.065))
                    )
                }
            }
        }
    }
}

// MARK: - Live Style Selector

/// Selector for HUD overlay styles.
public struct LiveStyleSelector: View {
    @Binding public var selection: OverlayStyle
    public let accentTint: Color

    private let options: [(style: OverlayStyle, label: String, icon: String)] = [
        (.particles, "Particles", "sparkles"),
        (.waveform, "Waveform", "waveform"),
        (.island, "Island", "capsule")
    ]

    public init(selection: Binding<OverlayStyle>, accentTint: Color = TalkieTheme.accent) {
        self._selection = selection
        self.accentTint = accentTint
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.style) { option in
                StylePill(
                    label: option.label,
                    icon: option.icon,
                    isSelected: isSelected(option.style),
                    accentTint: accentTint,
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
        case .island:
            return selection == .island
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
        case .island:
            selection = .island
        default:
            selection = style
        }
    }
}

private struct StylePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let accentTint: Color
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
            .foregroundStyle(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? accentTint.opacity(0.16) : (isHovered ? TalkieTheme.hover : Color.clear))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? accentTint.opacity(0.72) : TalkieTheme.border, lineWidth: 0.5)
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
            hudPlacement: .constant(.hudDefault),
            pillEnabled: .constant(true),
            pillPlacement: .constant(.pillDefault)
        )

        LiveStyleSelector(selection: .constant(.particles))
    }
    .padding(40)
    .background(Color(white: 0.1))
}
