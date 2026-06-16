//
//  OverlaySettingsSection.swift
//  TalkieAgent
//
//  Overlay settings: top bar and recording pill
//

import SwiftUI
import AppKit
import TalkieKit

struct OverlaySettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @AppStorage(CaptureIslandDefaults.enabled) private var capturePreviewEnabled = true
    @AppStorage(CaptureIslandDefaults.dismissSeconds) private var capturePreviewDismissSeconds = 6.0
    @State private var lastTopOverlayStyle: OverlayStyle = .particles
    @State private var notchInfo = NotchInfo.detect()

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.inset.topright.filled",
                title: "OVERLAY",
                subtitle: "Live visual feedback and capture surfaces."
            )
        } content: {
            SettingsCard(title: "SURFACE READOUT") {
                SurfaceReadout(
                    liveSurface: liveSurfaceReadout,
                    capturePreview: capturePreviewReadout,
                    macBookNotch: macBookNotchReadout
                )
            }

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

            SettingsCard(title: "MACBOOK NOTCH") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    SettingsToggleRow(
                        icon: "macbook",
                        title: "Use MacBook notch format",
                        description: notchToggleDescription,
                        isOn: $settings.notchOverlayEnabled
                    )
                    .help("Use the built-in MacBook notch surface when one is available")
                    .disabled(!notchInfo.hasNotch)
                    .opacity(notchInfo.hasNotch ? 1.0 : 0.45)
                }
            }
        }
        .onAppear {
            notchInfo = NotchInfo.detect()
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            notchInfo = NotchInfo.detect()
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

    private var liveSurfaceReadout: SurfaceReadout.Item {
        if settings.effectiveOverlayStyle == .island {
            return SurfaceReadout.Item(
                title: "Live surface",
                value: "Island",
                detail: "\(Int(settings.islandOverlayWidth)) x \(Int(settings.islandOverlayHeight)) pt",
                icon: "capsule",
                tint: OpsTint.amber.color
            )
        }

        guard settings.effectiveOverlayStyle.showsTopOverlay else {
            return SurfaceReadout.Item(
                title: "Live surface",
                value: "Off",
                detail: "Recording pill only",
                icon: "rectangle.inset.topright.filled",
                tint: OpsInk.dim
            )
        }

        return SurfaceReadout.Item(
            title: "Live surface",
            value: settings.effectiveOverlayStyle.displayName,
            detail: settings.overlayPlacement.nearestIndicatorPosition.displayName,
            icon: "rectangle.inset.topright.filled",
            tint: OpsInk.statusInfo
        )
    }

    private var capturePreviewReadout: SurfaceReadout.Item {
        SurfaceReadout.Item(
            title: "Capture preview",
            value: capturePreviewEnabled ? "On" : "Off",
            detail: capturePreviewEnabled ? "\(Int(capturePreviewDismissSeconds))s auto-dismiss" : "Hidden after capture",
            icon: "rectangle.topthird.inset.filled",
            tint: capturePreviewEnabled ? OpsInk.statusOk : OpsInk.dim
        )
    }

    private var macBookNotchReadout: SurfaceReadout.Item {
        guard notchInfo.hasNotch else {
            return SurfaceReadout.Item(
                title: "MacBook notch",
                value: "Not detected",
                detail: "Island remains available",
                icon: "macbook",
                tint: OpsInk.dim
            )
        }

        return SurfaceReadout.Item(
            title: "MacBook notch",
            value: settings.notchOverlayEnabled ? "Available" : "Disabled",
            detail: settings.notchOverlayEnabled ? "Uses hardware notch format" : "Falls back to top overlay",
            icon: "macbook",
            tint: settings.notchOverlayEnabled ? OpsInk.statusOk : OpsInk.statusWarn
        )
    }

    private var notchToggleDescription: String {
        if notchInfo.hasNotch {
            return "Keep the physical MacBook notch surface available for live recording."
        }
        return "No built-in notch was detected on the current display set."
    }
}

private struct SurfaceReadout: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let detail: String
        let icon: String
        let tint: Color
    }

    let liveSurface: Item
    let capturePreview: Item
    let macBookNotch: Item

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: OpsSpacing.md) {
            SurfaceReadoutCell(item: liveSurface)
            SurfaceReadoutCell(item: capturePreview)
            SurfaceReadoutCell(item: macBookNotch)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 176), spacing: OpsSpacing.md)]
    }
}

private struct SurfaceReadoutCell: View {
    let item: SurfaceReadout.Item

    var body: some View {
        HStack(alignment: .top, spacing: OpsSpacing.md) {
            Image(systemName: item.icon)
                .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: OpsRadius.tight)
                        .fill(OpsSurface.tintFill(item.tint))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.uppercased())
                    .font(OpsType.mono(OpsSize.micro, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(OpsInk.dim)

                Text(item.value)
                    .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(item.detail)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OpsSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard)
                .fill(OpsSurface.control)
                .overlay(
                    RoundedRectangle(cornerRadius: OpsRadius.standard)
                        .stroke(OpsHairline.standard, lineWidth: OpsStroke.thin)
                )
        )
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
