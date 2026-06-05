//
//  SurfaceSettingsView.swift
//  Talkie
//
//  Two-column surface settings: left column for toggles/pickers,
//  right column for detailed tuning of the active selection.
//

import SwiftUI

struct SurfaceSettingsView: View {

    private enum SurfaceTab: String, CaseIterable, Identifiable {
        case overlay = "Overlay"
        case hoverZone = "Hover Zone"

        var id: String { rawValue }
    }
    @Bindable private var notchSettings = NotchSettings.shared
    @Bindable private var tuning = NotchTuning.shared

    @State private var notchInfo = NotchInfo.effective()
    @State private var selectedTab: SurfaceTab = .overlay
    @State private var isRecordingSelectionQuickHotkey = false
    @State private var previewState: SurfaceState = .hover

    private var overlayActive: Bool {
        notchSettings.enabled && NotchComposer.shared.isActive
    }

    private var displayProfile: NotchVirtualDisplayStyle {
        NotchVirtualDisplayStyle(rawValue: notchSettings.shellStyleRaw) ?? .auto
    }

    private var resolvedDisplayProfile: NotchVirtualDisplayStyle {
        notchSettings.resolvedShellStyle(for: notchInfo)
    }

    private var overlayBaseWidth: CGFloat {
        max(notchInfo.notchWidth - 4, 172)
    }

    private var previewUsesIslandShape: Bool {
        previewMode == .external && resolvedDisplayProfile == .island
    }

    private var virtualWidthBonus: CGFloat {
        guard previewMode == .external else { return 0 }
        return previewUsesIslandShape ? 28 : 40
    }

    /// Surface lifecycle states — each shows a different expansion level in the preview.
    private enum SurfaceState: String, CaseIterable, Identifiable {
        case rest       // Wings retracted, rest indicator visible
        case hover      // Wings at hoverPokeOut
        case active     // Wings at activePokeOut (recording)
        case minimized  // Collapsed to nub

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rest: return "Rest"
            case .hover: return "Hover"
            case .active: return "Active"
            case .minimized: return "Minimized"
            }
        }

        var icon: String {
            switch self {
            case .rest: return "minus"
            case .hover: return "hand.point.up"
            case .active: return "record.circle"
            case .minimized: return "arrow.down.to.line"
            }
        }
    }

    var body: some View {
            SettingsPageContainer {
                SettingsPageHeader(
                    icon: "rectangle.topthird.inset.filled",
                    title: "NOTCH",
                    subtitle: "Surface settings for built-in notch Macs and external displays."
                )
            } content: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                surfacePreviewPanel

                SettingsTabSection(selection: $selectedTab, tabs: SurfaceTab.allCases) { tab in
                    Text(tab.rawValue)
                } content: {
                    switch selectedTab {
                    case .overlay:
                        overlayTabContent
                    case .hoverZone:
                        hoverZoneTabContent
                    }
                }
            }
        }
        .onAppear {
            notchInfo = NotchInfo.effective()
            moveNotchToSettingsScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            notchInfo = NotchInfo.effective()
        }
        .onChange(of: notchSettings.enabled) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
        }
        .onChange(of: notchSettings.externalEnabled) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
        }
        .onChange(of: notchSettings.shellStyleRaw) { _, _ in
            NotchComposer.shared.refreshVisibilityFromSettings()
        }
    }

    private var surfacePreviewPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("NOTCH PREVIEW")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Preview the surface at each lifecycle state. Adjust geometry below.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer(minLength: Spacing.md)

                Picker("", selection: $previewMode) {
                    ForEach(PreviewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            // State lifecycle selector
            HStack(spacing: Spacing.sm) {
                ForEach(SurfaceState.allCases) { state in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { previewState = state }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.icon)
                                .font(.system(size: 9))
                            Text(state.label)
                                .font(Theme.current.fontXS.weight(previewState == state ? .semibold : .regular))
                        }
                        .foregroundColor(previewState == state ? Theme.current.foreground : Theme.current.foregroundMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(previewState == state ? Color.white.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            surfacePreviewArea
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Tab Content

    private var overlayTabContent: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                overlaySection
                shortcutsSection
            }
            .frame(minWidth: 240, maxWidth: 280)

            VStack(alignment: .leading, spacing: Spacing.lg) {
                if notchSettings.enabled {
                    overlayTuningSection
                }
            }
            .frame(minWidth: 240, maxWidth: .infinity)
        }
    }

    // MARK: - Per-Monitor Hover Zone State

    @State private var selectedMonitorID: CGDirectDisplayID = 0

    /// Available external monitors (excludes built-in).
    private var externalMonitors: [(id: CGDirectDisplayID, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let did = CGDirectDisplayID(num.uint32Value)
            guard CGDisplayIsBuiltin(did) == 0 else { return nil }
            let name = screen.localizedName
            return (id: did, name: name)
        }
    }

    /// Config binding for the currently selected monitor.
    private var selectedMonitorConfig: HoverZoneConfig {
        get { notchSettings.hoverZoneConfig(for: selectedMonitorID) }
    }

    private func updateSelectedMonitorConfig(_ update: (inout HoverZoneConfig) -> Void) {
        var config = notchSettings.hoverZoneConfig(for: selectedMonitorID)
        update(&config)
        notchSettings.setHoverZoneConfig(config, for: selectedMonitorID)
    }

    private var hoverZoneTabContent: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hoverZoneSection
            }
            .frame(minWidth: 240, maxWidth: 280)

            VStack(alignment: .leading, spacing: Spacing.lg) {
                hoverZoneTuningSection
            }
            .frame(minWidth: 240, maxWidth: .infinity)
        }
        .onAppear { initSelectedMonitor() }
    }

    private func initSelectedMonitor() {
        let current = NotchComposer.shared.currentDisplayID
        if current != 0, CGDisplayIsBuiltin(current) == 0 {
            selectedMonitorID = current
        } else if let first = externalMonitors.first {
            selectedMonitorID = first.id
        }
    }

    // MARK: - Hover Zone Settings

    private var hoverZoneSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("HOVER ZONE", uppercase: true)

            Text("The invisible area at the top of the screen that triggers the notch to expand when your mouse enters it.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            if !externalMonitors.isEmpty {
                Divider().padding(.vertical, 2)

                Text("Each external monitor has its own hover zone. Laptop always uses the full notch width.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                monitorPicker
            }

            Divider().padding(.vertical, 2)

            Text("Switch to the **Rest** state in the preview above to see the hover zone outline.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            Button("Preview Hover Zone") {
                withAnimation(.easeInOut(duration: 0.2)) { previewState = .rest }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider().padding(.vertical, 2)

            HStack(spacing: Spacing.sm) {
                Button("Reset Zone") {
                    notchSettings.removeHoverZoneConfig(for: selectedMonitorID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reset this monitor's hover zone to global defaults")

                Button("Reset All") {
                    resetAllToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    @ViewBuilder
    private var monitorPicker: some View {
        let monitors = externalMonitors
        if monitors.count == 1, let only = monitors.first {
            HStack(spacing: 6) {
                Image(systemName: "display")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                Text(only.name)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
            }
            .onAppear { selectedMonitorID = only.id }
        } else if monitors.count > 1 {
            Picker("Monitor", selection: $selectedMonitorID) {
                ForEach(monitors, id: \.id) { monitor in
                    Text(monitor.name).tag(monitor.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var hoverZoneTuningSection: some View {
        let config = selectedMonitorConfig
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("ZONE SIZE", uppercase: true)

            if previewMode == .external {
                surfaceStepper("Width", value: Binding(
                    get: { config.width },
                    set: { v in updateSelectedMonitorConfig { $0.width = v } }
                ), range: 30...400)
            } else {
                surfaceStepper("Width (Laptop)", value: Binding(
                    get: { notchSettings.hoverZoneWidthNotch },
                    set: { notchSettings.hoverZoneWidthNotch = $0 }
                ), range: 60...400)
            }

            surfaceStepper("Height", value: Binding(
                get: { config.height },
                set: { v in updateSelectedMonitorConfig { $0.height = v } }
            ), range: 8...60)

            Divider().padding(.vertical, 2)

            DetailSectionHeader("PADDING", uppercase: true)

            Text("Extra invisible margin around the zone.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            surfaceStepper("Horizontal", value: Binding(
                get: { config.paddingX },
                set: { v in updateSelectedMonitorConfig { $0.paddingX = v } }
            ), range: 0...40)

            surfaceStepper("Vertical", value: Binding(
                get: { config.paddingY },
                set: { v in updateSelectedMonitorConfig { $0.paddingY = v } }
            ), range: 0...40)

            if previewMode == .external, selectedMonitorID != 0 {
                Divider().padding(.vertical, 2)
                Text("Editing: display \(selectedMonitorID)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted.opacity(0.5))
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Overlay Settings

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("OVERLAY", uppercase: true)

            Toggle("Enable Notch Overlay", isOn: $notchSettings.enabled)
                .toggleStyle(.switch)

            HStack(spacing: 6) {
                Circle()
                    .fill(overlayActive ? Color.green : .secondary)
                    .frame(width: 6, height: 6)
                Text(overlayStatusText)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            if notchSettings.enabled {
                Divider().padding(.vertical, 2)

                Toggle("Always Visible", isOn: $notchSettings.alwaysVisible)
                    .toggleStyle(.switch)

                Text("Keep overlay visible without hovering.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Divider().padding(.vertical, 2)

                Text("Shape (external displays)")
                    .font(Theme.current.fontSM.weight(.semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("Profile", selection: $notchSettings.shellStyleRaw) {
                    Text("Auto").tag(NotchVirtualDisplayStyle.auto.rawValue)
                    Text("Island").tag(NotchVirtualDisplayStyle.island.rawValue)
                    Text("Notch").tag(NotchVirtualDisplayStyle.notch.rawValue)
                }
                .pickerStyle(.segmented)

                Text(profileDescription)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Text("Current display resolves to \(resolvedDisplayProfile.title).")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted.opacity(0.75))

                if notchInfo.isVirtual {
                    Text("External displays and auto-hidden menu bars use a virtual surface on purpose. This is a supported mode, not a fallback error.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted.opacity(0.75))
                } else {
                    Text("This display has a camera notch — shape is always notch here.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted.opacity(0.7))
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var overlayStatusText: String {
        if !notchSettings.enabled { return "Disabled" }
        if !NotchComposer.shared.isActive { return "Waiting for display" }
        return notchInfo.isVirtual ? "Active (virtual surface)" : "Active (physical notch)"
    }

    private var profileDescription: String {
        switch displayProfile {
        case .auto:
            return "Auto keeps the hardware notch on built-in displays and uses the same surface model on external displays."
        case .island:
            return "Detached rounded rectangle floating below the top edge."
        case .notch:
            return "Attached to the top edge with inward curves — no gap in the center."
        }
    }

    // MARK: - Left Column: Shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("SHORTCUTS", uppercase: true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quick Selection")
                            .font(Theme.current.fontSM.weight(.semibold))
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text("Run the default read or summarize action on the current text selection.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Spacing.sm)

                    HotkeyRecorderButton(
                        hotkey: Binding(
                            get: { AgentSettings.shared.selectionQuickHotkey },
                            set: { newValue in
                                AgentSettings.shared.selectionQuickHotkey = newValue
                                DistributedNotificationCenter.default().postNotificationName(
                                    NSNotification.Name("to.talkie.app.agentHotkeysDidChange"),
                                    object: nil,
                                    userInfo: nil,
                                    deliverImmediately: true
                                )
                            }
                        ),
                        isRecording: $isRecordingSelectionQuickHotkey,
                        showReset: AgentSettings.shared.selectionQuickHotkey != .defaultSelectionQuick,
                        resetValue: .defaultSelectionQuick
                    )
                }

                Rectangle()
                    .fill(Theme.current.divider.opacity(0.7))
                    .frame(height: 1)

                shortcutRow(HotkeyRegistry.shared.config(for: .captureChord).displayString, description: "Capture chord")
                shortcutRow(HotkeyRegistry.shared.config(for: .openTrayViewer).displayString, description: "Open Hyper Paste")
                shortcutRow(HotkeyRegistry.shared.config(for: .pasteLastScreenshot).displayString, description: "Paste last screenshot")
            }

            Text("Selection action updates in TalkieAgent immediately. Hyper Paste uses the recent screenshot candidates shown from the top surface.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - 1:1 Surface Preview

    private enum PreviewMode: String, CaseIterable {
        case external = "External Monitor"
        case laptop = "Laptop Notch"
    }

    @State private var previewMode: PreviewMode = .external

    /// Real-dimension preview at 1:1 pixel scale showing the overlay shape.
    /// Toggle between external monitor and laptop views.
    /// Responds to the selected lifecycle state.
    private var surfacePreviewArea: some View {
        let overlayHeight = notchInfo.notchHeight - CGFloat(tuning.heightInset)
        let pokeOut: CGFloat = {
            switch previewState {
            case .rest, .minimized: return 0
            case .hover: return CGFloat(tuning.hoverPokeOut) + virtualWidthBonus
            case .active: return CGFloat(tuning.activePokeOut) + 48 + virtualWidthBonus
            }
        }()
        let leftTor = CGFloat(tuning.leftTopOuterRadius)
        let rightTor = CGFloat(tuning.rightTopOuterRadius)
        let br = CGFloat(tuning.bottomRadius)
        let ir = CGFloat(tuning.topInnerRadius)
        let overlap = CGFloat(tuning.notchOverlap)
        let innerCurveMode = NotchInnerCurveMode(rawValue: tuning.innerCurveModeRawValue) ?? .canonicalDownward
        let isIsland = resolvedDisplayProfile == .island
        let shellFill = Color(white: 0.08).opacity(max(0.18, notchSettings.overlayOpacity))

        let realNotchWidth = max(notchInfo.notchWidth - 4, 172)
        let leftShoulder = pokeOut > 0 ? max(0, leftTor) : 0
        let rightShoulder = pokeOut > 0 ? max(0, rightTor) : 0
        let previewMinimumNotchOverlap: CGFloat = {
            let fromNotchHeight = ceil(overlayHeight * 0.22)
            let fromWingBottomRadius = ceil((br * 2) + 1)
            let fromOuterTopArc = ceil(max(leftTor, rightTor) * 0.25)
            let required = max(6, fromNotchHeight, fromWingBottomRadius, fromOuterTopArc)
            let upperBound = max(fromWingBottomRadius, min(42, floor(realNotchWidth * 0.22)))
            return min(required, upperBound)
        }()

        let shellStroke = Color.white.opacity(0.24)
        let shellGlow = Color.white.opacity(0.06)
        let cutoutRadius = min(br, overlayHeight / 2)
        let previewShellWidth = previewMode == .laptop
            ? realNotchWidth + (pokeOut * 2) + leftShoulder + rightShoulder
            : (pokeOut * 2) + leftShoulder + rightShoulder

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.96))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)

            Rectangle()
                .fill(Color.yellow.opacity(0.7))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    switch previewState {
                    case .minimized:
                        // Minimized nub — small pill at top center
                        previewMinimizedNub()
                            .padding(.top, previewUsesIslandShape ? 4 : 0)

                    case .rest:
                        // Rest: wings retracted, rest indicator + hover zone outline
                        VStack(spacing: 4) {
                            if previewMode == .external {
                                // Rest indicator bar
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 36, height: 4)
                                    .padding(.top, 6)
                            }
                        }

                        // Hover zone outline (dotted) — per-monitor config for external, global for laptop
                        let hzConfig = previewMode == .external
                            ? notchSettings.hoverZoneConfig(for: selectedMonitorID)
                            : HoverZoneConfig(width: notchSettings.hoverZoneWidthNotch, height: notchSettings.hoverZoneHeight, paddingX: notchSettings.hoverZonePaddingX, paddingY: notchSettings.hoverZonePaddingY)
                        let hzWidth = CGFloat(hzConfig.width)
                        let hzHeight = CGFloat(hzConfig.height)
                        let hzPadX = CGFloat(hzConfig.paddingX)
                        let hzPadY = CGFloat(hzConfig.paddingY)
                        // Inner zone (visible trigger area)
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.cyan.opacity(0.5))
                            .frame(width: hzWidth, height: hzHeight)
                        // Outer zone (with padding — actual hit area)
                        if hzPadX > 0 || hzPadY > 0 {
                            Rectangle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.cyan.opacity(0.2))
                                .frame(width: hzWidth + hzPadX * 2, height: hzHeight + hzPadY * 2)
                        }

                    case .hover, .active:
                        // Expanded shell
                        if previewMode == .external {
                            previewExternalShell(
                                isIsland: isIsland,
                                pokeOut: pokeOut,
                                leftShoulder: leftShoulder,
                                rightShoulder: rightShoulder,
                                overlayHeight: overlayHeight,
                                leftTor: leftTor,
                                rightTor: rightTor,
                                topInnerRadius: ir,
                                bottomRadius: br,
                                notchOverlap: overlap,
                                minimumNotchOverlap: previewMinimumNotchOverlap,
                                innerCurveMode: innerCurveMode,
                                shellFill: shellFill,
                                shellStroke: shellStroke,
                                shellGlow: shellGlow
                            )
                        } else {
                            previewLaptopShell(
                                pokeOut: pokeOut,
                                leftShoulder: leftShoulder,
                                rightShoulder: rightShoulder,
                                overlayHeight: overlayHeight,
                                notchWidth: realNotchWidth,
                                leftTor: leftTor,
                                rightTor: rightTor,
                                topInnerRadius: ir,
                                bottomRadius: br,
                                notchOverlap: overlap,
                                minimumNotchOverlap: previewMinimumNotchOverlap,
                                innerCurveMode: innerCurveMode,
                                shellFill: shellFill,
                                shellStroke: shellStroke,
                                shellGlow: shellGlow,
                                cutoutRadius: cutoutRadius
                            )
                        }

                    }
                }
                .frame(width: max(previewShellWidth, 80), height: overlayHeight, alignment: .top)
                .animation(.easeInOut(duration: 0.25), value: previewState)
            }
            .padding(.top, 1)

            VStack {
                Spacer()

                HStack {
                    Text("\(previewState.label) · \(previewMode == .external ? "External" : "Laptop")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.26))

                    Spacer()

                    if previewState == .rest {
                        let cfg = previewMode == .external
                            ? notchSettings.hoverZoneConfig(for: selectedMonitorID)
                            : HoverZoneConfig(width: notchSettings.hoverZoneWidthNotch, height: notchSettings.hoverZoneHeight, paddingX: notchSettings.hoverZonePaddingX, paddingY: notchSettings.hoverZonePaddingY)
                        Text("zone: \(Int(cfg.width))×\(Int(cfg.height))pt + \(Int(cfg.paddingX))×\(Int(cfg.paddingY)) pad")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.4))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: previewMode == .external ? 160 : 176)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Preview of the minimized nub — matches NotchComposerView.notchMinimizedNub
    private func previewMinimizedNub() -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.4))
                .frame(width: 28, height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }

    @ViewBuilder
    private func previewExternalShell(
        isIsland: Bool,
        pokeOut: CGFloat,
        leftShoulder: CGFloat,
        rightShoulder: CGFloat,
        overlayHeight: CGFloat,
        leftTor: CGFloat,
        rightTor: CGFloat,
        topInnerRadius: CGFloat,
        bottomRadius: CGFloat,
        notchOverlap: CGFloat,
        minimumNotchOverlap: CGFloat,
        innerCurveMode: NotchInnerCurveMode,
        shellFill: Color,
        shellStroke: Color,
        shellGlow: Color
    ) -> some View {
        if isIsland {
            let totalWidth = (pokeOut * 2) + leftShoulder + rightShoulder
            RoundedRectangle(cornerRadius: max(10, min(18, bottomRadius + 2)), style: .continuous)
                .fill(shellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: max(10, min(18, bottomRadius + 2)), style: .continuous)
                        .strokeBorder(shellStroke, lineWidth: 1)
                )
                .shadow(color: shellGlow, radius: 10, y: 2)
                .frame(width: totalWidth, height: overlayHeight)
                .padding(.top, 2)
        } else {
            let coreWidth = pokeOut * 2
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: leftShoulder, height: overlayHeight)

                previewWingPairShape(
                    pokeOut: pokeOut,
                    notchGap: 0,
                    leftTopOuterRadius: leftTor,
                    rightTopOuterRadius: rightTor,
                    topInnerRadius: topInnerRadius,
                    bottomRadius: bottomRadius,
                    notchOverlap: notchOverlap,
                    minimumNotchOverlap: minimumNotchOverlap,
                    innerCurveMode: innerCurveMode,
                    debugContext: "surface-preview-ext"
                )
                .fill(shellFill)
                .overlay(
                    previewWingPairShape(
                        pokeOut: pokeOut,
                        notchGap: 0,
                        leftTopOuterRadius: leftTor,
                        rightTopOuterRadius: rightTor,
                        topInnerRadius: topInnerRadius,
                        bottomRadius: bottomRadius,
                        notchOverlap: notchOverlap,
                        minimumNotchOverlap: minimumNotchOverlap,
                        innerCurveMode: innerCurveMode,
                        debugContext: "surface-preview-ext-stroke"
                    )
                    .stroke(shellStroke, lineWidth: 1)
                )
                .shadow(color: shellGlow, radius: 10, y: 2)
                .frame(width: coreWidth, height: overlayHeight)

                Color.clear
                    .frame(width: rightShoulder, height: overlayHeight)
            }
            .frame(width: coreWidth + leftShoulder + rightShoulder, height: overlayHeight)
        }
    }

    private func previewLaptopShell(
        pokeOut: CGFloat,
        leftShoulder: CGFloat,
        rightShoulder: CGFloat,
        overlayHeight: CGFloat,
        notchWidth: CGFloat,
        leftTor: CGFloat,
        rightTor: CGFloat,
        topInnerRadius: CGFloat,
        bottomRadius: CGFloat,
        notchOverlap: CGFloat,
        minimumNotchOverlap: CGFloat,
        innerCurveMode: NotchInnerCurveMode,
        shellFill: Color,
        shellStroke: Color,
        shellGlow: Color,
        cutoutRadius: CGFloat
    ) -> some View {
        let coreWidth = notchWidth + (pokeOut * 2)

        return ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: leftShoulder, height: overlayHeight)

                previewWingPairShape(
                    pokeOut: pokeOut,
                    notchGap: notchWidth,
                    leftTopOuterRadius: leftTor,
                    rightTopOuterRadius: rightTor,
                    topInnerRadius: topInnerRadius,
                    bottomRadius: bottomRadius,
                    notchOverlap: notchOverlap,
                    minimumNotchOverlap: minimumNotchOverlap,
                    innerCurveMode: innerCurveMode,
                    debugContext: "surface-preview-notch"
                )
                .fill(shellFill)
                .overlay(
                    previewWingPairShape(
                        pokeOut: pokeOut,
                        notchGap: notchWidth,
                        leftTopOuterRadius: leftTor,
                        rightTopOuterRadius: rightTor,
                        topInnerRadius: topInnerRadius,
                        bottomRadius: bottomRadius,
                        notchOverlap: notchOverlap,
                        minimumNotchOverlap: minimumNotchOverlap,
                        innerCurveMode: innerCurveMode,
                        debugContext: "surface-preview-notch-stroke"
                    )
                    .stroke(shellStroke, lineWidth: 1)
                )
                .shadow(color: shellGlow, radius: 10, y: 2)
                .frame(width: coreWidth, height: overlayHeight)

                Color.clear
                    .frame(width: rightShoulder, height: overlayHeight)
            }
            .frame(width: coreWidth + leftShoulder + rightShoulder, height: overlayHeight)

            previewLaptopCutout(
                width: notchWidth,
                height: overlayHeight,
                bottomRadius: cutoutRadius
            )
            .frame(width: coreWidth + leftShoulder + rightShoulder, height: overlayHeight, alignment: .top)
        }
    }

    private func previewWingPairShape(
        pokeOut: CGFloat,
        notchGap: CGFloat,
        leftTopOuterRadius: CGFloat,
        rightTopOuterRadius: CGFloat,
        topInnerRadius: CGFloat,
        bottomRadius: CGFloat,
        notchOverlap: CGFloat,
        minimumNotchOverlap: CGFloat,
        innerCurveMode: NotchInnerCurveMode,
        debugContext: String
    ) -> NotchWingPairSurfaceShape {
        NotchWingPairSurfaceShape(
            pokeOut: pokeOut,
            notchGap: notchGap,
            leftTopOuterRadius: leftTopOuterRadius,
            rightTopOuterRadius: rightTopOuterRadius,
            topInnerRadius: topInnerRadius,
            bottomRadius: bottomRadius,
            notchOverlap: notchOverlap,
            minimumNotchOverlap: minimumNotchOverlap,
            innerCurveMode: innerCurveMode,
            debugLoggingEnabled: false,
            debugContext: debugContext
        )
    }

    private func previewLaptopCutout(width: CGFloat, height: CGFloat, bottomRadius: CGFloat) -> some View {
        ZStack {
            SurfacePreviewPhysicalNotchShape(bottomRadius: bottomRadius)
                .fill(Color.black)
                .frame(width: width, height: height)

            SurfacePreviewPhysicalNotchShape(bottomRadius: bottomRadius)
                .stroke(Color.cyan.opacity(0.9), style: .init(lineWidth: 1, dash: [5, 4]))
                .frame(width: width, height: height)

            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Right Column: Overlay Tuning

    private var overlayTuningSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            DetailSectionHeader("TUNING", uppercase: true)

            surfaceStepper("Opacity", value: $notchSettings.overlayOpacity, range: 0...1, step: 0.05)
            surfaceStepper("Corner Radius", value: $tuning.bottomRadius, range: 0...100)

            Divider().padding(.vertical, 2)

            surfaceStepper("Hover Expansion", value: $tuning.hoverPokeOut, range: 0...500)
                .onChange(of: tuning.hoverPokeOut) { _, _ in
                    if previewState == .hover { /* preview updates automatically */ }
                    else { withAnimation(.easeInOut(duration: 0.2)) { previewState = .hover } }
                }
            surfaceStepper("Active Expansion", value: $tuning.activePokeOut, range: 0...500)
                .onChange(of: tuning.activePokeOut) { _, _ in
                    if previewState == .active { /* preview updates automatically */ }
                    else { withAnimation(.easeInOut(duration: 0.2)) { previewState = .active } }
                }

            // Display-specific controls — driven by the preview mode toggle
            if previewMode == .external {
                Divider().padding(.vertical, 2)
                surfaceStepper("Outer Radius L", value: $tuning.leftTopOuterRadius, range: -100...100)
                surfaceStepper("Outer Radius R", value: $tuning.rightTopOuterRadius, range: -100...100)
            } else {
                Divider().padding(.vertical, 2)
                surfaceStepper("Inner Radius", value: $tuning.topInnerRadius, range: -100...100)
                surfaceStepper("Notch Overlap", value: $tuning.notchOverlap, range: 0...100)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Reset

    /// Move the notch overlay to the screen where the Talkie settings window is,
    /// so the debug hover zone outline is visible next to the settings controls.
    private func moveNotchToSettingsScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let screen = window.screen else { return }
        NotchComposer.shared.moveToScreen(screen)
        // Also update the preview's notchInfo to match this screen
        notchInfo = NotchInfo.effective(for: screen)
    }

    private func resetAllToDefaults() {
        // Overlay tuning
        tuning.hoverPokeOut = 38
        tuning.activePokeOut = 58
        tuning.heightInset = 2
        tuning.leftTopOuterRadius = 15
        tuning.rightTopOuterRadius = 15
        tuning.topOuterRadius = 15
        tuning.topInnerRadius = 0
        tuning.bottomRadius = 14
        tuning.notchOverlap = 7
        tuning.innerCurveModeRawValue = NotchInnerCurveMode.canonicalDownward.rawValue

        // Overlay settings
        notchSettings.overlayOpacity = 1.0
        notchSettings.shellStyleRaw = NotchVirtualDisplayStyle.auto.rawValue
        notchSettings.alwaysVisible = false
        // Hover Zone (global defaults + clear per-monitor overrides)
        notchSettings.hoverZoneWidthExternal = 80
        notchSettings.hoverZoneWidthNotch = 180
        notchSettings.hoverZoneHeight = 24
        notchSettings.hoverZonePaddingX = 10
        notchSettings.hoverZonePaddingY = 8
        // Clear all per-monitor overrides
        for monitor in externalMonitors {
            notchSettings.removeHoverZoneConfig(for: monitor.id)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func shortcutRow(_ shortcut: String, description: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
                .frame(width: 70, alignment: .trailing)
            Text(description)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private var widthStatesSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Width States")
                .font(Theme.current.fontSM.weight(.semibold))
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(widthStatesDescription)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            ForEach([SurfaceState.rest, .hover, .active], id: \.self) { state in
                widthStateRow(state.label, width: overlayWidth(for: state))
            }
        }
        .padding(.bottom, 4)
    }

    private var widthStatesDescription: String {
        if previewMode == .external {
            return "External preview uses the virtual shell. Hover and active widths add the external-display bonus automatically."
        }
        return "Laptop preview starts from the detected camera cutout width. Hover and active add left and right expansion on top."
    }

    private func overlayWidth(for state: SurfaceState) -> CGFloat {
        let pokeOut: CGFloat
        switch state {
        case .rest, .minimized:
            pokeOut = 0
        case .hover:
            pokeOut = CGFloat(max(0, tuning.hoverPokeOut)) + virtualWidthBonus
        case .active:
            let activeBase = CGFloat(max(0, tuning.activePokeOut))
            pokeOut = previewMode == .external
                ? activeBase + 48 + virtualWidthBonus
                : activeBase
        }

        let leftShoulder = pokeOut > 0 ? max(0, CGFloat(tuning.leftTopOuterRadius)) : 0
        let rightShoulder = pokeOut > 0 ? max(0, CGFloat(tuning.rightTopOuterRadius)) : 0
        let baseWidth = previewMode == .laptop ? overlayBaseWidth : 0

        return baseWidth + (pokeOut * 2) + leftShoulder + rightShoulder
    }

    private func widthStateRow(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
            Spacer()
            Text("\(Int(width.rounded())) pt")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func surfaceSlider(
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

    private func surfaceStepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)

                TextField("", value: value, format: .number)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 44, height: 22)
                    .textFieldStyle(.plain)
                    .background(Color.white.opacity(0.05))

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1)))
        }
    }

}

private struct SurfacePreviewPhysicalNotchShape: Shape {
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
