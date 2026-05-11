//
//  NotchSettingsView.swift
//  Talkie
//
//  ARCHIVED / DEPRECATED — This view is not wired into any navigation.
//  All active notch + tray settings live in SurfaceSettingsView.
//  Kept as reference for the geometry lab, live preview, and tuning
//  sliders that were built here. Safe to delete once those patterns
//  are no longer needed.
//

import SwiftUI
import AppKit

struct NotchSettingsView: View {
    @Bindable private var tuning = NotchTuning.shared
    @Bindable private var notchSettings = NotchSettings.shared
    @Bindable private var traySettings = TraySettings.shared

    @State private var showGuides = true
    @State private var showOutline = true
    @State private var compareModes = true
    @State private var revealUnderNotch = true
    @State private var showFloatingIsland = true
    @State private var showTrayDotPreview = true
    @State private var previewTrayDotCount: Double = 3
    @State private var previewState: PreviewState = .hover
    @State private var notchInfo = NotchInfo.effective()
    @State private var showAdvancedGeometryControls = false
    @State private var showAdvancedTrayBadgeControls = false

    private enum PreviewState: String, CaseIterable, Identifiable {
        case rest
        case hover
        case active

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private var previewPokeOut: CGFloat {
        switch previewState {
        case .rest:
            return 0
        case .hover:
            return CGFloat(max(0, tuning.hoverPokeOut))
        case .active:
            return CGFloat(max(0, tuning.activePokeOut))
        }
    }

    private var previewNotchWidth: CGFloat {
        max(notchInfo.notchWidth, 180)
    }

    private var previewNotchHeight: CGFloat {
        max(notchInfo.notchHeight, 34)
    }

    private var previewWidth: CGFloat {
        previewNotchWidth + (previewPokeOut * 2)
    }

    private var previewHeight: CGFloat {
        max(36, previewNotchHeight)
    }

    private var leftTopOuterRadius: CGFloat { CGFloat(tuning.leftTopOuterRadius) }
    private var rightTopOuterRadius: CGFloat { CGFloat(tuning.rightTopOuterRadius) }
    private var topInnerRadius: CGFloat { CGFloat(max(0, tuning.topInnerRadius)) }
    private var bottomRadius: CGFloat { CGFloat(max(0, tuning.bottomRadius)) }
    private var notchOverlap: CGFloat { CGFloat(max(0, tuning.notchOverlap)) }
    private var previewMinimumNotchOverlap: CGFloat {
        let fromNotchHeight = ceil(previewNotchHeight * 0.22)
        let fromWingBottomRadius = ceil((bottomRadius * 2) + 1)
        let fromOuterTopArc = ceil(max(leftTopOuterRadius, rightTopOuterRadius) * 0.25)
        let required = max(6, fromNotchHeight, fromWingBottomRadius, fromOuterTopArc)
        let upperBound = max(fromWingBottomRadius, min(42, floor(previewNotchWidth * 0.22)))
        return min(required, upperBound)
    }
    private var trayDotCount: Int { Int(previewTrayDotCount.rounded()) }
    private var trayBadgeDefaultWidth: Double { Double(max(notchInfo.notchWidth - 4, 172)) }
    private var selectedShellStyle: NotchVirtualDisplayStyle {
        NotchVirtualDisplayStyle(rawValue: notchSettings.shellStyleRaw) ?? .auto
    }

    private var resolvedDisplayProfile: NotchVirtualDisplayStyle {
        notchSettings.resolvedShellStyle(for: notchInfo)
    }

    private var resolvedDisplayProfileText: String {
        if !notchInfo.isVirtual {
            return "This display has a camera notch, so the shell always resolves to Notch here."
        }

        switch selectedShellStyle {
        case .auto:
            return "Auto resolved to \(resolvedDisplayProfile.title) on this external display."
        case .island:
            return "Forced to Island for this external display."
        case .notch:
            return "Forced to Notch emulation for this external display."
        }
    }

    private var hasTrayContent: Bool {
        ScreenshotTray.shared.isNotEmpty || ClipTray.shared.isNotEmpty
    }

    private var trayStripPlacementDescription: String {
        switch notchSettings.trayStripPlacement {
        case "inside": return "Dots inside the notch body. Hover the notch to reveal tray."
        case "outside": return "Strip below the notch. Hover the strip to reveal tray."
        case "both": return "Dots inside + strip below. Hover either to reveal tray."
        default: return ""
        }
    }

    private var externalBadgeSuppressedByNotch: Bool {
        notchSettings.overlayOwnsTrayDiscovery(isOverlayActive: NotchComposer.shared.isActive)
    }

    private var externalBadgeStatusText: String {
        if !traySettings.externalBadgeEnabled {
            return "Disabled"
        }
        if externalBadgeSuppressedByNotch {
            return "Suppressed (Overlay Owns Tray)"
        }
        return hasTrayContent ? "Running" : "Idle (No Tray Items)"
    }

    private var externalBadgeStatusColor: Color {
        if !traySettings.externalBadgeEnabled {
            return .secondary
        }
        if externalBadgeSuppressedByNotch {
            return .orange
        }
        return hasTrayContent ? .green : .secondary
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.topthird.inset.filled",
                title: "NOTCH",
                subtitle: "Legacy shell geometry lab. Primary runtime controls live in Notch."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                behaviorSection
                animationInspectorSection
                previewSection
                geometrySection
                presetSection
                trayBadgeSection
            }
        }
        .onAppear {
            notchInfo = NotchInfo.effective()
            pushLiveValues()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            notchInfo = NotchInfo.effective()
        }
        .onChange(of: notchSettings.enabled) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
            TrayBadge.shared.refreshVisibility()
        }
        .onChange(of: notchSettings.externalEnabled) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
        }
        .onChange(of: notchSettings.shellStyleRaw) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
        }
        .onChange(of: notchSettings.trayStripEnabled) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
            TrayBadge.shared.refreshVisibility()
        }
        .onChange(of: traySettings.externalBadgeEnabled) { _, _ in
            TrayBadge.shared.refreshVisibility()
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("PREVIEW", uppercase: true)

            Picker("Preview State", selection: $previewState) {
                ForEach(PreviewState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: Spacing.md) {
                Toggle("Guides", isOn: $showGuides)
                Toggle("Outline", isOn: $showOutline)
                Toggle("Compare Modes", isOn: $compareModes)
                Toggle("Reveal Under Notch", isOn: $revealUnderNotch)
                Toggle("Floating Island", isOn: $showFloatingIsland)
            }
            .toggleStyle(.switch)

            HStack(spacing: Spacing.md) {
                Toggle("Tray Dots", isOn: $showTrayDotPreview)
                    .toggleStyle(.switch)

                HStack(spacing: Spacing.xs) {
                    Text("Dot Count")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Slider(value: $previewTrayDotCount, in: 1...5, step: 1)
                        .frame(width: 140)
                    Text("\(trayDotCount)")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 18, alignment: .trailing)
                }

                NotchTrayDotBar(count: trayDotCount)
                    .opacity(showTrayDotPreview ? 1 : 0.35)
            }

            if showFloatingIsland {
                floatingIslandPreview
                Text("Floating island study: detached from the top edge and physical notch mask so curve tuning is easier to judge.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            } else {
                anchoredNotchPreview
                Text("Cyan dashed shape = physical notch cutout. Wings are independent left/right surfaces around that fixed gap.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Text("Notch Overlap lets wings intrude under the notch cutout to remove the inner seam. Notch Join Radius controls the top inner curve near the notch.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            topJoinInspector

            if compareModes {
                HStack(spacing: Spacing.sm) {
                    ForEach(NotchInnerCurveMode.allCases, id: \.self) { mode in
                        modeComparisonTile(mode: mode)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var floatingIslandPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.96))

            ZStack {
                previewWingPairShape()
                .fill(Color(white: 0.08))

                previewWingPairShape()
                .stroke(Color.white.opacity(showOutline ? 0.9 : 0.25), lineWidth: 1)

                if showGuides {
                    NotchSettingsGuideOverlay(
                        pokeOut: previewPokeOut,
                        notchGap: previewNotchWidth,
                        leftTopOuterRadius: leftTopOuterRadius,
                        rightTopOuterRadius: rightTopOuterRadius,
                        topInnerRadius: topInnerRadius,
                        notchOverlap: notchOverlap,
                        minimumNotchOverlap: previewMinimumNotchOverlap,
                        mode: tuning.innerCurveMode
                    )
                }

                trayDotOverlay
            }
            .frame(width: previewWidth, height: previewHeight)
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var anchoredNotchPreview: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.96))

            Rectangle()
                .fill(Color.yellow.opacity(0.7))
                .frame(height: 1)

            ZStack {
                previewWingPairShape()
                .fill(Color(white: 0.08))

                previewWingPairShape()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)

                if showOutline {
                    previewWingPairShape()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                }

                if showGuides {
                    NotchSettingsGuideOverlay(
                        pokeOut: previewPokeOut,
                        notchGap: previewNotchWidth,
                        leftTopOuterRadius: leftTopOuterRadius,
                        rightTopOuterRadius: rightTopOuterRadius,
                        topInnerRadius: topInnerRadius,
                        notchOverlap: notchOverlap,
                        minimumNotchOverlap: previewMinimumNotchOverlap,
                        mode: tuning.innerCurveMode
                    )
                }

                if !revealUnderNotch {
                    NotchSettingsPhysicalNotchShape(
                        bottomRadius: min(bottomRadius, previewNotchHeight / 2)
                    )
                    .fill(Color.black)
                    .frame(width: previewNotchWidth, height: previewNotchHeight)
                    .frame(width: previewWidth, height: previewHeight, alignment: .top)
                }

                NotchSettingsPhysicalNotchShape(
                    bottomRadius: min(bottomRadius, previewNotchHeight / 2)
                )
                .stroke(Color.cyan.opacity(0.95), style: .init(lineWidth: 1, dash: [5, 4]))
                .frame(width: previewNotchWidth, height: previewNotchHeight)
                .frame(width: previewWidth, height: previewHeight, alignment: .top)

                trayDotOverlay
            }
            .frame(width: previewWidth, height: previewHeight)
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trayDotOverlay: some View {
        HStack(spacing: 0) {
            ZStack {
                if showTrayDotPreview && previewPokeOut > 0 {
                    NotchTrayDotBar(count: trayDotCount)
                }
            }
            .frame(width: previewPokeOut, height: previewHeight)

            Color.clear
                .frame(width: previewNotchWidth, height: previewHeight)

            Color.clear
                .frame(width: previewPokeOut, height: previewHeight)
        }
        .frame(width: previewWidth, height: previewHeight)
        .allowsHitTesting(false)
    }

    private func modeComparisonTile(mode: NotchInnerCurveMode) -> some View {
        VStack(spacing: 6) {
            Text(modeLabel(mode))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(mode == tuning.innerCurveMode ? Theme.current.foreground : Theme.current.foregroundSecondary)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.96))

                Rectangle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(height: 1)

                ZStack {
                    previewWingPairShape(innerCurveMode: mode)
                    .fill(Color(white: 0.08))

                    previewWingPairShape(innerCurveMode: mode)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)

                    NotchSettingsGuideOverlay(
                        pokeOut: previewPokeOut,
                        notchGap: previewNotchWidth,
                        leftTopOuterRadius: leftTopOuterRadius,
                        rightTopOuterRadius: rightTopOuterRadius,
                        topInnerRadius: topInnerRadius,
                        notchOverlap: notchOverlap,
                        minimumNotchOverlap: previewMinimumNotchOverlap,
                        mode: mode
                    )

                    if !revealUnderNotch {
                        NotchSettingsPhysicalNotchShape(
                            bottomRadius: min(bottomRadius, previewNotchHeight / 2)
                        )
                        .fill(Color.black)
                        .frame(width: previewNotchWidth * 0.62, height: previewNotchHeight * 0.9)
                        .frame(width: previewWidth * 0.62, height: previewHeight * 0.9, alignment: .top)
                    }

                    NotchSettingsPhysicalNotchShape(
                        bottomRadius: min(bottomRadius, previewNotchHeight / 2)
                    )
                    .stroke(Color.cyan.opacity(0.95), style: .init(lineWidth: 1, dash: [4, 3]))
                    .frame(width: previewNotchWidth * 0.62, height: previewNotchHeight * 0.9)
                    .frame(width: previewWidth * 0.62, height: previewHeight * 0.9, alignment: .top)
                }
                .frame(width: previewWidth * 0.62, height: previewHeight * 0.9)
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var topJoinInspector: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DetailSectionHeader("TOP JOIN INSPECTOR", uppercase: true)
            Text("Magnified left inner join. This is the exact curve controlled by Notch Join Radius + Inner Curve Mode.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: Spacing.sm) {
                ForEach(NotchInnerCurveMode.allCases, id: \.self) { mode in
                    NotchJoinInspectorTile(
                        mode: mode,
                        notchJoinRadius: topInnerRadius,
                        outerTopRadius: leftTopOuterRadius,
                        notchOverlap: notchOverlap,
                        isSelected: mode == tuning.innerCurveMode
                    )
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("BEHAVIOR", uppercase: true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Profile")
                    .font(Theme.current.fontSM.weight(.semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("Shell Style", selection: $notchSettings.shellStyleRaw) {
                    ForEach(NotchVirtualDisplayStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedShellStyle.subtitle)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Text(resolvedDisplayProfileText)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted.opacity(0.9))

                Text("Rounded island styling is now owned by Profile above. The old standalone island toggle was removed because it no longer drove rendering.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted.opacity(0.75))
            }

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Visibility")
                    .font(Theme.current.fontSM.weight(.semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Toggle("Notch Overlay", isOn: $notchSettings.enabled)
                    .toggleStyle(.switch)
                Text("The notch/island overlay itself. When off, no notch UI appears.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Toggle("Tray Dot Strip", isOn: $notchSettings.trayStripEnabled)
                    .toggleStyle(.switch)

                if notchSettings.trayStripEnabled {
                    Picker("Placement", selection: $notchSettings.trayStripPlacement) {
                        Text("Inside notch").tag("inside")
                        Text("Below notch").tag("outside")
                        Text("Both").tag("both")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    Text(trayStripPlacementDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Toggle("Standalone Badge", isOn: $traySettings.externalBadgeEnabled)
                    .toggleStyle(.switch)
                Text("Floating tray badge when the notch overlay is inactive or disabled.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                HStack(spacing: 6) {
                    Circle()
                        .fill(externalBadgeStatusColor)
                        .frame(width: 6, height: 6)
                    Text("Badge: \(externalBadgeStatusText)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Divider().padding(.vertical, 2)

            DisclosureGroup("Diagnostics") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Toggle("Aggressive Geometry Logging", isOn: $notchSettings.aggressiveDebugLogging)
                        .toggleStyle(.switch)

                    Text("Logs per-frame notch geometry and transition values to UI logs.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(.top, Spacing.xs)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DetailSectionHeader("GEOMETRY", uppercase: true)

            Picker(
                "Inner Curve Mode",
                selection: Binding(
                    get: { tuning.innerCurveMode },
                    set: { mode in
                        tuning.innerCurveModeRawValue = mode.rawValue
                        pushLiveValues()
                    }
                )
            ) {
                ForEach(NotchInnerCurveMode.allCases, id: \.self) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            notchSlider("Hover Wing Width", value: hoverPokeOutBinding, range: 0...90)
            notchSlider("Active Wing Width", value: activePokeOutBinding, range: 0...90)
            notchSlider("Notch Overlap", value: notchOverlapBinding, range: 0...24)

            DisclosureGroup("Advanced Geometry", isExpanded: $showAdvancedGeometryControls) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    notchSlider("Outer Anchor X (Left)", value: leftTopOuterRadiusBinding, range: -24...24)
                    notchSlider("Outer Anchor X (Right)", value: rightTopOuterRadiusBinding, range: -24...24)
                    notchSlider("Notch Join Radius", value: topInnerRadiusBinding, range: 0...28)
                    notchSlider("Bottom Radius", value: bottomRadiusBinding, range: 0...28)
                    notchSlider("Height Inset", value: heightInsetBinding, range: 0...6)
                }
                .padding(.top, Spacing.xs)
            }

            Text("Outer anchor is signed on X only: positive = external shoulder, negative = internal corner. Bottom radius affects only outer corners; inner bottoms stay square.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var animationInspectorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("ANIMATION INSPECTOR", uppercase: true)

            Toggle("Enable Floating Inspector", isOn: $notchSettings.inspectorEnabled)
                .toggleStyle(.switch)

            Toggle("Scrub Sequence With Slider", isOn: $notchSettings.inspectorScrubEnabled)
                .toggleStyle(.switch)

            HStack(spacing: Spacing.sm) {
                Button("Open Animator") {
                    NotchAnimationInspectorController.shared.show()
                }
                .buttonStyle(.borderedProminent)

                Button("Shot Overlay") {
                    NotchComposer.shared.captureOverlaySnapshot()
                }
                .buttonStyle(.bordered)
            }

            Text("Use the floating Notch Animator for frame scrubbing and quick tuning. Essential controls stay visible; advanced timing, width, and indicator styling are grouped to reduce slider overload.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("PRESETS", uppercase: true)

            HStack(spacing: Spacing.sm) {
                Button("Canonical") {
                    applyPreset(mode: .canonicalDownward)
                }
                .buttonStyle(.bordered)

                Button("Hard") {
                    applyPreset(mode: .hardCorner)
                }
                .buttonStyle(.bordered)

                Button("Mirrored") {
                    applyPreset(mode: .mirroredUpward)
                }
                .buttonStyle(.bordered)
            }

            Text("Presets only adjust notch geometry and curve mode.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var trayBadgeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DetailSectionHeader("TRAY BADGE", uppercase: true)

            Toggle("Follow Notch Width", isOn: $traySettings.badgeFollowNotchWidth)
                .toggleStyle(.switch)

            trayBadgeSlider(
                "Y Offset",
                value: badgeYOffsetBinding,
                range: 0...24
            )

            trayBadgeSlider(
                "Hover Target Height",
                value: badgeHoverTargetHeightBinding,
                range: 0...24
            )

            DisclosureGroup("Advanced Tray Badge", isExpanded: $showAdvancedTrayBadgeControls) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    trayBadgeSlider(
                        "Badge Width",
                        value: badgeWidthBinding,
                        range: 120...420,
                        disabled: traySettings.badgeFollowNotchWidth
                    )

                    trayBadgeSlider(
                        "Badge Thickness",
                        value: badgeHeightBinding,
                        range: 2...12
                    )

                    trayBadgeSlider(
                        "Dot Size",
                        value: badgeDotSizeBinding,
                        range: 1...8
                    )

                    trayBadgeSlider(
                        "Max Dots",
                        value: badgeMaxDotsBinding,
                        range: 1...12
                    )
                }
                .padding(.top, Spacing.xs)
            }

            TrayBadgeStripPreview(
                width: traySettings.badgeFollowNotchWidth ? trayBadgeDefaultWidth : traySettings.badgeWidth,
                height: traySettings.badgeHeight,
                dotSize: traySettings.badgeDotSize,
                maxDots: traySettings.badgeMaxDots,
                count: max(1, trayDotCount)
            )

            Text("Always-on tray indicator. Default follows notch width and uses a very thin strip.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var hoverPokeOutBinding: Binding<Double> {
        Binding(
            get: { tuning.hoverPokeOut },
            set: { value in
                tuning.hoverPokeOut = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var activePokeOutBinding: Binding<Double> {
        Binding(
            get: { tuning.activePokeOut },
            set: { value in
                tuning.activePokeOut = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var leftTopOuterRadiusBinding: Binding<Double> {
        Binding(
            get: { tuning.leftTopOuterRadius },
            set: { value in
                tuning.leftTopOuterRadius = value
                pushLiveValues()
            }
        )
    }

    private var rightTopOuterRadiusBinding: Binding<Double> {
        Binding(
            get: { tuning.rightTopOuterRadius },
            set: { value in
                tuning.rightTopOuterRadius = value
                pushLiveValues()
            }
        )
    }

    private var topInnerRadiusBinding: Binding<Double> {
        Binding(
            get: { tuning.topInnerRadius },
            set: { value in
                tuning.topInnerRadius = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var bottomRadiusBinding: Binding<Double> {
        Binding(
            get: { tuning.bottomRadius },
            set: { value in
                tuning.bottomRadius = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var notchOverlapBinding: Binding<Double> {
        Binding(
            get: { tuning.notchOverlap },
            set: { value in
                tuning.notchOverlap = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var heightInsetBinding: Binding<Double> {
        Binding(
            get: { tuning.heightInset },
            set: { value in
                tuning.heightInset = max(0, value)
                pushLiveValues()
            }
        )
    }

    private var badgeWidthBinding: Binding<Double> {
        Binding(
            get: { traySettings.badgeFollowNotchWidth ? trayBadgeDefaultWidth : traySettings.badgeWidth },
            set: { value in
                traySettings.badgeWidth = max(120, min(value, 420))
            }
        )
    }

    private var badgeHeightBinding: Binding<Double> {
        Binding(
            get: { traySettings.badgeHeight },
            set: { value in
                traySettings.badgeHeight = max(2, min(value, 12))
            }
        )
    }

    private var badgeDotSizeBinding: Binding<Double> {
        Binding(
            get: { traySettings.badgeDotSize },
            set: { value in
                traySettings.badgeDotSize = max(1, min(value, 8))
            }
        )
    }

    private var badgeMaxDotsBinding: Binding<Double> {
        Binding(
            get: { Double(traySettings.badgeMaxDots) },
            set: { value in
                traySettings.badgeMaxDots = Int(max(1, min(12, value.rounded())))
            }
        )
    }

    private var badgeYOffsetBinding: Binding<Double> {
        Binding(
            get: { traySettings.badgeYOffset },
            set: { value in
                traySettings.badgeYOffset = max(0, min(value, 24))
            }
        )
    }

    private var badgeHoverTargetHeightBinding: Binding<Double> {
        Binding(
            get: { traySettings.badgeHoverTargetHeight },
            set: { value in
                traySettings.badgeHoverTargetHeight = max(0, min(value, 24))
            }
        )
    }

    private func notchSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Slider(value: value, in: range, step: 1)
        }
    }

    private func trayBadgeSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.current.fontSM)
                    .foregroundColor(disabled ? Theme.current.foregroundMuted : Theme.current.foreground)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(disabled ? Theme.current.foregroundMuted : Theme.current.foregroundSecondary)
            }

            Slider(value: value, in: range, step: 1)
                .disabled(disabled)
        }
    }

    private func modeLabel(_ mode: NotchInnerCurveMode) -> String {
        switch mode {
        case .canonicalDownward: return "Canonical"
        case .hardCorner: return "Hard"
        case .mirroredUpward: return "Mirrored"
        }
    }

    private func previewWingPairShape(
        innerCurveMode: NotchInnerCurveMode? = nil
    ) -> NotchWingPairSurfaceShape {
        NotchWingPairSurfaceShape(
            pokeOut: previewPokeOut,
            notchGap: previewNotchWidth,
            leftTopOuterRadius: leftTopOuterRadius,
            rightTopOuterRadius: rightTopOuterRadius,
            topInnerRadius: topInnerRadius,
            bottomRadius: bottomRadius,
            notchOverlap: notchOverlap,
            minimumNotchOverlap: previewMinimumNotchOverlap,
            innerCurveMode: innerCurveMode ?? tuning.innerCurveMode,
            debugLoggingEnabled: false,
            debugContext: "legacy-preview"
        )
    }

    private func applyPreset(mode: NotchInnerCurveMode) {
        // Canonical baseline from the currently approved notch screenshot.
        tuning.hoverPokeOut = 90
        tuning.activePokeOut = 61
        tuning.topOuterRadius = 15
        tuning.leftTopOuterRadius = 15
        tuning.rightTopOuterRadius = 15
        tuning.topInnerRadius = 0
        tuning.bottomRadius = 14
        tuning.notchOverlap = 5
        tuning.heightInset = 2
        tuning.innerCurveModeRawValue = mode.rawValue
        pushLiveValues()
    }

    private func pushLiveValues() {
        tuning.syncMirrors()
    }
}

private struct TrayBadgeStripPreview: View {
    let width: Double
    let height: Double
    let dotSize: Double
    let maxDots: Int
    let count: Int

    var body: some View {
        let stripWidth = CGFloat(max(120, min(width, 420)))
        let stripHeight = CGFloat(max(2, min(height, 12)))
        let configuredDotSize = CGFloat(max(1, min(dotSize, 8)))
        let dotCount = min(max(count, 1), max(1, min(maxDots, 12)))
        let horizontalPadding = max(3, stripHeight * 0.45)
        let innerWidth = max(1, stripWidth - (horizontalPadding * 2))
        let maxFitDot = (innerWidth - CGFloat(max(0, dotCount - 1))) / CGFloat(max(dotCount, 1))
        let fitDotSize = max(1, min(configuredDotSize, maxFitDot))
        let spacing: CGFloat = dotCount > 1
            ? max(1, (innerWidth - (CGFloat(dotCount) * fitDotSize)) / CGFloat(dotCount - 1))
            : 0

        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: fitDotSize, height: fitDotSize)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: stripWidth, height: stripHeight)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NotchJoinInspectorTile: View {
    let mode: NotchInnerCurveMode
    let notchJoinRadius: CGFloat
    let outerTopRadius: CGFloat
    let notchOverlap: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.9))

                Canvas { context, size in
                    let m: CGFloat = 10
                    let topY = m
                    let leftX = m
                    let width = size.width - (m * 2)
                    let height = size.height - (m * 2)

                    let wing = min(max(48 + notchOverlap, 20), width - 2)
                    let tr = min(abs(outerTopRadius), min(wing, height) / 2)
                    let ir = max(0, min(notchJoinRadius, max(0, wing - tr), height / 2))

                    var base = Path()
                    base.move(to: CGPoint(x: leftX, y: topY))
                    base.addLine(to: CGPoint(x: leftX + width, y: topY))
                    context.stroke(base, with: .color(.yellow.opacity(0.75)), lineWidth: 1)

                    var boundary = Path()
                    boundary.move(to: CGPoint(x: leftX + wing, y: topY))
                    boundary.addLine(to: CGPoint(x: leftX + wing, y: topY + height))
                    context.stroke(boundary, with: .color(.mint.opacity(0.7)), lineWidth: 1)

                    var join = Path()
                    join.move(to: CGPoint(x: leftX + wing - ir, y: topY))

                    if ir > 0, mode != .hardCorner {
                        let control: CGPoint = {
                            switch mode {
                            case .canonicalDownward:
                                return CGPoint(x: leftX + wing, y: topY)
                            case .mirroredUpward:
                                return CGPoint(x: leftX + wing - ir, y: topY + ir)
                            case .hardCorner:
                                return CGPoint(x: leftX + wing, y: topY)
                            }
                        }()
                        join.addQuadCurve(
                            to: CGPoint(x: leftX + wing, y: topY + ir),
                            control: control
                        )
                    } else {
                        join.addLine(to: CGPoint(x: leftX + wing, y: topY))
                    }

                    context.stroke(join, with: .color(.white.opacity(0.95)), lineWidth: 2)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? (SettingsManager.shared.accentColor.color ?? .accentColor).opacity(0.6) : Theme.current.divider.opacity(0.5), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var label: String {
        switch mode {
        case .canonicalDownward: return "Canonical"
        case .hardCorner: return "Hard"
        case .mirroredUpward: return "Mirrored"
        }
    }
}

private struct NotchSettingsPhysicalNotchShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let br = min(bottomRadius, min(w, h) / 2)

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - br))
        p.addQuadCurve(to: CGPoint(x: w - br, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: br, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - br), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

private struct NotchSettingsGuideOverlay: View {
    let pokeOut: CGFloat
    let notchGap: CGFloat
    let leftTopOuterRadius: CGFloat
    let rightTopOuterRadius: CGFloat
    let topInnerRadius: CGFloat
    let notchOverlap: CGFloat
    let minimumNotchOverlap: CGFloat
    let mode: NotchInnerCurveMode

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let baseWing = max(0, min(pokeOut, w / 2))
                let baseGap = max(0, min(notchGap, w - (baseWing * 2)))
                let desiredOverlap = max(minimumNotchOverlap, notchOverlap)
                let overlap = max(0, min(desiredOverlap, baseGap / 2))

                let wing = baseWing + overlap
                let gap = max(0, baseGap - (overlap * 2))
                let maxTor = min(wing, h) / 2
                let leftTor = max(-maxTor, min(leftTopOuterRadius, maxTor))
                let rightTor = max(-maxTor, min(rightTopOuterRadius, maxTor))
                let leftIr = max(0, min(topInnerRadius, max(0, wing - abs(leftTor)), h / 2))
                let rightIr = max(0, min(topInnerRadius, max(0, wing - abs(rightTor)), h / 2))

                let innerLeft = wing
                let innerRight = wing + gap

                var boundaries = Path()
                boundaries.move(to: CGPoint(x: innerLeft, y: 0))
                boundaries.addLine(to: CGPoint(x: innerLeft, y: h))
                boundaries.move(to: CGPoint(x: innerRight, y: 0))
                boundaries.addLine(to: CGPoint(x: innerRight, y: h))
                context.stroke(boundaries, with: .color(.mint.opacity(0.65)), lineWidth: 1)

                guard mode != .hardCorner else { return }

                guard leftIr > 0 || rightIr > 0 else { return }

                let leftStart = CGPoint(x: innerLeft - leftIr, y: 0)
                let leftEnd = CGPoint(x: innerLeft, y: leftIr)
                let rightStart = CGPoint(x: innerRight, y: rightIr)
                let rightEnd = CGPoint(x: innerRight + rightIr, y: 0)

                let leftControl: CGPoint
                let rightControl: CGPoint
                switch mode {
                case .canonicalDownward:
                    leftControl = CGPoint(x: innerLeft, y: 0)
                    rightControl = CGPoint(x: innerRight, y: 0)
                case .mirroredUpward:
                    leftControl = CGPoint(x: innerLeft - leftIr, y: leftIr)
                    rightControl = CGPoint(x: innerRight + rightIr, y: rightIr)
                case .hardCorner:
                    return
                }

                if leftIr > 0 {
                    drawHandle(context: context, start: leftStart, control: leftControl, end: leftEnd)
                }
                if rightIr > 0 {
                    drawHandle(context: context, start: rightStart, control: rightControl, end: rightEnd)
                }
            }
        }
    }

    private func drawHandle(context: GraphicsContext, start: CGPoint, control: CGPoint, end: CGPoint) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: control)
        line.addLine(to: end)
        context.stroke(line, with: .color(.orange.opacity(0.7)), style: .init(lineWidth: 1, dash: [4, 3]))

        let dotSize: CGFloat = 5
        context.fill(Circle().path(in: CGRect(x: start.x - dotSize / 2, y: start.y - dotSize / 2, width: dotSize, height: dotSize)), with: .color(.white.opacity(0.9)))
        context.fill(Circle().path(in: CGRect(x: control.x - dotSize / 2, y: control.y - dotSize / 2, width: dotSize, height: dotSize)), with: .color(.orange))
        context.fill(Circle().path(in: CGRect(x: end.x - dotSize / 2, y: end.y - dotSize / 2, width: dotSize, height: dotSize)), with: .color(.white.opacity(0.9)))
    }
}
