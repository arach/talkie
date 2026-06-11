//
//  OverlaySettingsSection.swift
//  TalkieAgent
//
//  Overlay settings: top bar and recording pill
//

import SwiftUI
import TalkieKit

struct OverlaySettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @AppStorage(CaptureIslandDefaults.enabled) private var capturePreviewEnabled = true
    @AppStorage(CaptureIslandDefaults.dismissSeconds) private var capturePreviewDismissSeconds = 6.0
    @State private var lastTopOverlayStyle: OverlayStyle = .particles

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.inset.topright.filled",
                title: "OVERLAY",
                subtitle: "Live visual feedback and capture surfaces."
            )
        } content: {
            SettingsCard(title: "LIVE PREVIEW") {
                LivePreviewScreen(
                    overlayStyle: $settings.overlayStyle,
                    hudPlacement: $settings.overlayPlacement,
                    pillEnabled: $settings.pillEnabled,
                    pillPlacement: $settings.pillPlacement,
                    islandSettings: settings.islandVisualizationSettings,
                    accentTint: OpsTint.amber.color
                )
                .frame(maxWidth: .infinity)
            }

            SettingsCard(title: "STYLE") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    SettingsToggleRow(
                        icon: "capsule",
                        title: "Show top bar",
                        isOn: topBarEnabled
                    )
                    .help("Voice feedback at the top edge")

                    OpsDivider()

                    VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                        OverlayControlGroup(title: "Style") {
                            LiveStyleSelector(selection: $settings.overlayStyle, accentTint: OpsTint.amber.color)
                        }

                        OverlayControlGroup(title: "Position") {
                            OverlayPositionPicker(kind: .topBar, placement: $settings.overlayPlacement)
                        }
                    }
                    .opacity(settings.overlayStyle.showsTopOverlay ? 1.0 : 0.45)
                    .disabled(!settings.overlayStyle.showsTopOverlay)
                }
            }

            if settings.overlayStyle == .island {
                SettingsCard(title: "ISLAND") {
                    IslandOverlayControls(settings: settings)
                }
            }

            SettingsCard(title: "RECORDING PILL") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    SettingsToggleRow(
                        icon: "capsule",
                        title: "Show recording pill",
                        isOn: $settings.pillEnabled
                    )
                    .help("Persistent recording indicator")

                    OpsDivider()

                    OverlayControlGroup(title: "Position") {
                        OverlayPositionPicker(kind: .recordingPill, placement: $settings.pillPlacement)
                    }
                    .opacity(settings.pillEnabled ? 1.0 : 0.45)
                    .disabled(!settings.pillEnabled)
                }
            }

            SettingsCard(title: "CAPTURE PREVIEW") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    SettingsToggleRow(
                        icon: "rectangle.topthird.inset.filled",
                        title: "Show capture preview",
                        isOn: $capturePreviewEnabled
                    )
                    .help("Surface recent screenshots and clips at the top edge")

                    OpsDivider()

                    OverlayAutoDismissRow(seconds: $capturePreviewDismissSeconds)
                    .opacity(capturePreviewEnabled ? 1.0 : 0.45)
                    .disabled(!capturePreviewEnabled)
                }
            }
        }
        .onAppear {
            OverlaySettingsPreviewController.shared.activate()
            rememberCurrentTopOverlayStyle()
            if settings.pillPosition == .topCenter {
                settings.pillPosition = .bottomCenter
            }
        }
        .onDisappear {
            OverlaySettingsPreviewController.shared.deactivate()
        }
        .onChange(of: settings.overlayStyle) { _, _ in
            rememberCurrentTopOverlayStyle()
        }
    }

    private var topBarEnabled: Binding<Bool> {
        Binding(
            get: { settings.overlayStyle.showsTopOverlay },
            set: { show in
                if show {
                    settings.overlayStyle = lastTopOverlayStyle.showsTopOverlay ? lastTopOverlayStyle : .particles
                } else {
                    rememberCurrentTopOverlayStyle()
                    settings.overlayStyle = .pillOnly
                }
            }
        )
    }

    private func rememberCurrentTopOverlayStyle() {
        if settings.overlayStyle.showsTopOverlay {
            lastTopOverlayStyle = settings.overlayStyle
        }
    }
}

private struct OverlayControlGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.sm) {
            Text(title.uppercased())
                .font(OpsType.mono(OpsSize.micro, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(OpsInk.dim)

            content
        }
    }
}

private struct IslandOverlayControls: View {
    @ObservedObject var settings: LiveSettings

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.lg) {
            OverlayControlSlider(
                label: "Width",
                value: $settings.islandOverlayWidth,
                range: 112...260,
                step: 2,
                suffix: "pt"
            )

            OverlayControlSlider(
                label: "Height",
                value: $settings.islandOverlayHeight,
                range: 24...48,
                step: 1,
                suffix: "pt"
            )

            OverlayControlSlider(
                label: "Speed",
                value: $settings.islandOverlayMotion,
                leftLabel: "Slow",
                rightLabel: "Fast"
            )

            OverlayControlSlider(
                label: "Response",
                value: $settings.islandOverlayReactivity,
                leftLabel: "Soft",
                rightLabel: "Expressive"
            )

            OverlayControlSlider(
                label: "Density",
                value: $settings.islandOverlayShape,
                leftLabel: "Sparse",
                rightLabel: "Dense"
            )

            HStack {
                Spacer()

                Button {
                    let defaults = IslandVisualizationSettings.defaultValue
                    settings.islandOverlayMotion = defaults.motion
                    settings.islandOverlayReactivity = defaults.reactivity
                    settings.islandOverlayShape = defaults.shape
                    settings.islandOverlayWidth = LiveSettings.defaultIslandOverlayWidth
                    settings.islandOverlayHeight = LiveSettings.defaultIslandOverlayHeight
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(OpsType.ui(OpsSize.xs, weight: .medium))
                        .foregroundStyle(OpsInk.muted)
                        .padding(.horizontal, OpsSpacing.md)
                        .padding(.vertical, OpsSpacing.sm)
                        .background(
                            Capsule()
                                .fill(OpsSurface.control)
                                .overlay(
                                    Capsule()
                                        .stroke(OpsHairline.standard, lineWidth: OpsStroke.thin)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Restore Island defaults")
            }
        }
    }
}

private struct OverlayControlSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let suffix: String?
    let leftLabel: String?
    let rightLabel: String?

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        suffix: String? = nil,
        leftLabel: String? = nil,
        rightLabel: String? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.suffix = suffix
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
    }

    var body: some View {
        HStack(spacing: OpsSpacing.md) {
            Text(label)
                .font(OpsType.ui(OpsSize.xs, weight: .medium))
                .foregroundStyle(OpsInk.ink)
                .frame(width: 72, alignment: .leading)

            if let leftLabel {
                Text(leftLabel)
                    .font(OpsType.mono(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
                    .frame(width: 58, alignment: .trailing)
            }

            Slider(value: steppedValue, in: range)
                .controlSize(.small)
                .tint(OpsTint.amber.color)

            if let suffix {
                Text("\(Int(value.rounded()))\(suffix)")
                    .font(OpsType.mono(OpsSize.micro, weight: .medium))
                    .foregroundStyle(OpsInk.dim)
                    .frame(width: 54, alignment: .trailing)
            } else if let rightLabel {
                Text(rightLabel)
                    .font(OpsType.mono(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
                    .frame(width: 72, alignment: .leading)
            }
        }
    }

    private var steppedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                guard let step else {
                    value = min(range.upperBound, max(range.lowerBound, newValue))
                    return
                }
                let stepped = (newValue / step).rounded() * step
                value = min(range.upperBound, max(range.lowerBound, stepped))
            }
        )
    }
}

private enum OverlayPositionPickerKind {
    case topBar
    case recordingPill
}

private struct OverlayPositionPicker: View {
    let kind: OverlayPositionPickerKind
    @Binding var placement: NormalizedPlacement

    var body: some View {
        HStack(spacing: OpsSpacing.sm) {
            switch kind {
            case .topBar:
                AgentPositionButton(
                    title: "Left",
                    isSelected: placement.nearestIndicatorPosition == .topLeft
                ) {
                    placement = .init(indicatorPosition: .topLeft)
                }

                AgentPositionButton(
                    title: "Center",
                    isSelected: placement.nearestIndicatorPosition == .topCenter
                ) {
                    placement = .init(indicatorPosition: .topCenter)
                }

                AgentPositionButton(
                    title: "Right",
                    isSelected: placement.nearestIndicatorPosition == .topRight
                ) {
                    placement = .init(indicatorPosition: .topRight)
                }
            case .recordingPill:
                AgentPositionButton(
                    title: "Left",
                    isSelected: selectedPillPosition == .bottomLeft
                ) {
                    placement = .init(pillPosition: .bottomLeft)
                }

                AgentPositionButton(
                    title: "Center",
                    isSelected: selectedPillPosition == .bottomCenter
                ) {
                    placement = .init(pillPosition: .bottomCenter)
                }

                AgentPositionButton(
                    title: "Right",
                    isSelected: selectedPillPosition == .bottomRight
                ) {
                    placement = .init(pillPosition: .bottomRight)
                }
            }
        }
    }

    private var selectedPosition: PillPosition {
        let nearest = placement.nearestPillPosition
        return nearest == .topCenter ? .bottomCenter : nearest
    }

    private var selectedPillPosition: PillPosition {
        selectedPosition
    }
}

private struct AgentPositionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OpsType.ui(OpsSize.xs, weight: .medium))
                .foregroundStyle(isSelected ? OpsInk.bg : (isHovered ? OpsInk.ink : OpsInk.muted))
                .frame(minWidth: 54)
                .padding(.horizontal, OpsSpacing.md)
                .padding(.vertical, OpsSpacing.sm)
                .background(
                    Capsule()
                        .fill(isSelected ? OpsTint.amber.color : (isHovered ? OpsSurface.hover : OpsSurface.control))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? OpsTint.amber.color.opacity(0.85) : OpsHairline.standard, lineWidth: OpsStroke.thin)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct OverlayAutoDismissRow: View {
    @Binding var seconds: Double

    var body: some View {
        HStack(spacing: OpsSpacing.md) {
            Image(systemName: "timer")
                .font(OpsType.ui(OpsSize.sm, weight: .medium))
                .foregroundStyle(OpsInk.dim)
                .frame(width: 20)

            Text("Auto-dismiss")
                .font(OpsType.ui(OpsSize.xs, weight: .medium))
                .foregroundStyle(OpsInk.ink)

            Spacer()

            OverlayDurationPicker(selection: $seconds)
        }
        .help("How long capture previews remain visible")
    }
}

private struct OverlayDurationPicker: View {
    @Binding var selection: Double
    private let options: [Double] = [4, 6, 10]

    var body: some View {
        HStack(spacing: OpsSpacing.xs) {
            ForEach(options, id: \.self) { option in
                AgentPositionButton(
                    title: "\(Int(option))s",
                    isSelected: abs(selection - option) < 0.5
                ) {
                    withAnimation(TalkieAnimation.fast) {
                        selection = option
                    }
                }
            }
        }
    }
}
