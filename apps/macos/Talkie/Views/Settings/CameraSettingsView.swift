//
//  CameraSettingsView.swift
//  Talkie
//
//  Settings page for camera bubble and clip capture configuration.
//

import SwiftUI
import AVFoundation
import TalkieKit

// MARK: - Bubble Size

enum CameraBubbleSize: String, CaseIterable, Codable {
    case small    // 80pt
    case standard // 100pt
    case large    // 130pt

    var points: CGFloat {
        switch self {
        case .small: return 80
        case .standard: return 100
        case .large: return 130
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        }
    }
}

// MARK: - Video Codec

enum CameraVideoCodec: String, CaseIterable, Codable {
    case h264
    case hevc

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }

    var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }

    var detail: String {
        switch self {
        case .h264: return "Maximum compatibility"
        case .hevc: return "Smaller files, same quality"
        }
    }
}

// MARK: - Capture Section Tabs

enum CaptureSection: String, CaseIterable {
    case screenshots = "SCREENSHOTS"
    case camera = "CAMERA"

    var icon: String {
        switch self {
        case .screenshots: return "camera.shutter.button"
        case .camera: return "video.circle"
        }
    }

    var color: Color {
        switch self {
        case .screenshots: return .orange
        case .camera: return .cyan
        }
    }
}

// MARK: - Camera Settings View

struct CameraSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    private let captureService = CameraCaptureService.shared
    private let controller = CameraBubbleController.shared

    @State private var availableDevices: [AVCaptureDevice] = []
    @State private var recordingAction: HotkeyAction? = nil
    @State private var selectedTab: CaptureSection = .screenshots
    @AppStorage(AgentSettingsKey.captureIslandPlacement, store: TalkieSharedSettings)
    private var capturePreviewPlacementRaw = CaptureIslandPlacement.contextual.rawValue

    private let flags = FeatureFlags.shared
    private let screenCapturePermissions = ScreenCapturePermissionManager.shared

    private var capturePreviewPlacement: CaptureIslandPlacement {
        CaptureIslandPlacement(rawValue: capturePreviewPlacementRaw) ?? .contextual
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "camera.aperture",
                title: "CAPTURE",
                subtitle: "Screenshots, camera bubble, clip recording, and tray attachments."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                featureToggleSection
                    .padding(.bottom, Spacing.lg)

                if flags.enableCapture {
                    hotkeysSection
                        .padding(.bottom, Spacing.lg)

                    overlayControlsSection
                        .padding(.bottom, Spacing.lg)

                    if flags.enableCameraBubble {
                        // Both enabled — show tab bar
                        tabBar
                        Rectangle()
                            .fill(Theme.current.divider)
                            .frame(height: 1)

                        Group {
                            switch selectedTab {
                            case .screenshots:
                                screenshotsTabContent
                            case .camera:
                                cameraTabContent
                            }
                        }
                        .padding(.top, Spacing.lg)
                    } else {
                        // Only screenshots — no tabs needed
                        screenshotsTabContent
                    }
                }
            }
        }
        .onAppear {
            loadDevices()
            normalizeCapturePreviewPlacement()
            Task { await screenCapturePermissions.refresh() }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CaptureSection.allCases, id: \.rawValue) { section in
                tabItem(section)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
    }

    @ViewBuilder
    private func tabItem(_ section: CaptureSection) -> some View {
        let isSelected = selectedTab == section

        Button(action: { selectedTab = section }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: section.icon)
                        .font(.system(size: 11))

                    Text(section.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? section.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? section.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    private var screenshotsTabContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            screenshotStoragePresetSection
            screenRecordingStorageSection
            screenshotLauncherSection
        }
    }

    private var cameraTabContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            cameraDeviceSection
            bubbleSizeSection
            recordingQualitySection
            videoFormatSection
            maxDurationSection
        }
    }

    // MARK: - Feature Toggle

    private var featureToggleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green)
                    .frame(width: 3, height: 14)
                Text("FEATURES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            #if DEBUG
            debugFeatureOverrideControls
            #else
            productionFeatureStatus
            #endif
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var productionFeatureStatus: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            readOnlyFeatureRow(title: "Capture", key: "enableCapture", value: flags.enableCapture)

            if flags.enableCapture {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(screenCapturePermissions.isReadyForCapture ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(screenCapturePermissions.isReadyForCapture ? "Screen capture access ready" : "Screen capture access needed for screenshots and screen recording.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Spacer()

                    if !screenCapturePermissions.isReadyForCapture {
                        Button(screenCapturePermissions.isRequesting ? "Requesting..." : "Grant Access") {
                            Task { @MainActor in
                                _ = await screenCapturePermissions.requestForCaptureEnablement()
                            }
                        }
                        .font(Theme.current.fontXS)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                readOnlyFeatureRow(title: "Screenshots", key: "enableScreenshots", value: flags.enableScreenshots)
                    .padding(.leading, Spacing.sm)
                readOnlyFeatureRow(title: "Camera Bubble", key: "enableCameraBubble", value: flags.enableCameraBubble)
                    .padding(.leading, Spacing.sm)
            }
        }
    }

    private var debugFeatureOverrideControls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Binding(
                get: { flags.enableCapture },
                set: { enabled in
                    FeatureFlags.shared.setLocalOverride("enableCapture", value: enabled)
                    guard enabled else { return }
                    Task { @MainActor in
                        _ = await screenCapturePermissions.requestForCaptureEnablement()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Capture")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Capture tray, tray-to-memo attachments, and global shortcuts.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)

            if flags.enableCapture {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(screenCapturePermissions.isReadyForCapture ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(screenCapturePermissions.isReadyForCapture ? "Screen capture access ready" : "Screen capture access needed for screenshots and screen recording.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Spacer()

                    if !screenCapturePermissions.isReadyForCapture {
                        Button(screenCapturePermissions.isRequesting ? "Requesting..." : "Grant Access") {
                            Task { @MainActor in
                                _ = await screenCapturePermissions.requestForCaptureEnablement()
                            }
                        }
                        .font(Theme.current.fontXS)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                Toggle(isOn: Binding(
                    get: { flags.enableScreenshots },
                    set: { enabled in
                        FeatureFlags.shared.setLocalOverride("enableScreenshots", value: enabled)
                    }
                )) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.current.divider)
                            .frame(width: 2, height: 14)
                        Text("Screenshots")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)
                    }
                    .padding(.leading, Spacing.sm)
                }
                .toggleStyle(.switch)
                .tint(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: Binding(
                    get: { flags.enableCameraBubble },
                    set: { enabled in
                        FeatureFlags.shared.setLocalOverride("enableCameraBubble", value: enabled)
                    }
                )) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.current.divider)
                            .frame(width: 2, height: 14)
                        Text("Camera Bubble")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)
                    }
                    .padding(.leading, Spacing.sm)
                }
                .toggleStyle(.switch)
                .tint(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Enables capture tray, tray-to-memo attachments, and global shortcuts. Screen Recording is only requested when you turn this on. Restart required for shortcut changes.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
        }
    }

    private func readOnlyFeatureRow(title: String, key: String, value: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.current.divider)
                .frame(width: 2, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            Text(FeatureFlags.shared.flagSource(key).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(Theme.current.foregroundMuted.opacity(0.14))
                .cornerRadius(CornerRadius.xs)

            Text(value ? "ON" : "OFF")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(value ? .green : Theme.current.foregroundMuted)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Camera Device

    private var cameraDeviceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan)
                    .frame(width: 3, height: 14)
                Text("CAMERA")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            if availableDevices.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("No cameras detected")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(availableDevices, id: \.uniqueID) { device in
                        deviceRow(device)
                    }
                }
            }

            // Only show permission prompt when access is missing
            if !captureService.isAuthorized {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Camera access required")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Button("Request") {
                        Task { await captureService.requestPermission() }
                    }
                    .font(Theme.current.fontXS)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.top, Spacing.xxs)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func deviceRow(_ device: AVCaptureDevice) -> some View {
        let isSelected = captureService.selectedDeviceID == device.uniqueID

        return Button(action: {
            captureService.selectedDeviceID = device.uniqueID
        }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: device.position == .front ? "person.crop.circle" : "camera")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.localizedName)
                        .font(Theme.current.fontSM)
                        .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bubble Size

    private var bubbleSizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan)
                    .frame(width: 3, height: 14)
                Text("BUBBLE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                ForEach(CameraBubbleSize.allCases, id: \.self) { size in
                    bubbleSizeOption(size)
                }
            }

            Text("Size of the floating camera preview bubble.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func bubbleSizeOption(_ size: CameraBubbleSize) -> some View {
        let isSelected = captureService.bubbleSize == size

        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                captureService.bubbleSize = size
            }
        }) {
            VStack(spacing: Spacing.xs) {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Theme.current.foregroundMuted.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    .frame(width: size.points * 0.4, height: size.points * 0.4)

                Text(size.label)
                    .font(Theme.current.fontXS)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text("\(Int(size.points))pt")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording Quality

    private var recordingQualitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 3, height: 14)
                Text("RECORDING QUALITY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                ForEach(CameraQuality.allCases, id: \.self) { quality in
                    qualityOption(quality)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func qualityOption(_ quality: CameraQuality) -> some View {
        let isSelected = captureService.quality == quality

        return Button(action: {
            captureService.quality = quality
        }) {
            VStack(spacing: Spacing.xs) {
                Text(quality.label)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text("\(quality.bitrate / 1_000_000) Mbps")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Format

    private var videoFormatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 3, height: 14)
                Text("VIDEO FORMAT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                ForEach(CameraVideoCodec.allCases, id: \.self) { codec in
                    codecOption(codec)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func codecOption(_ codec: CameraVideoCodec) -> some View {
        let isSelected = captureService.videoCodec == codec

        return Button(action: {
            captureService.videoCodec = codec
        }) {
            VStack(spacing: Spacing.xs) {
                Text(codec.label)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text(codec.detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Max Clip Duration

    private var maxDurationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple)
                    .frame(width: 3, height: 14)
                Text("MAX CLIP DURATION")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            HStack(spacing: Spacing.md) {
                Slider(
                    value: Binding(
                        get: { captureService.maxClipDurationSeconds },
                        set: { captureService.maxClipDurationSeconds = $0 }
                    ),
                    in: 15...120,
                    step: 5
                )

                Text("\(Int(captureService.maxClipDurationSeconds))s")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)
                    .frame(width: 40, alignment: .trailing)
            }

            Text("Clips auto-stop after this duration.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Screenshot Shortcuts

    // MARK: - Screenshot Launcher

    private var screenshotLauncherSection: some View {
        let editToolLaunchers: [ScreenshotLauncher] = [.builtin, .cleanshotX, .screenshotX]

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)
                Text("EDIT TOOL")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            Text("Preferred app for editing tray screenshots — annotate, markup, and share.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            VStack(spacing: 4) {
                ForEach(editToolLaunchers, id: \.self) { launcher in
                    launcherRow(launcher)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func launcherRow(_ launcher: ScreenshotLauncher) -> some View {
        let isSelected = settingsManager.preferredScreenshotLauncher == launcher
        let available = launcher.isInstalled

        return Button {
            guard available else { return }
            settingsManager.preferredScreenshotLauncher = launcher
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: launcher.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : (available ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(launcher.label)
                        .font(Theme.current.fontSM.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(available ? Theme.current.foreground : Theme.current.foregroundMuted)
                    if let detail = launcher.detail {
                        Text(detail)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                Spacer()

                if !available {
                    Text("Not installed")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private var screenshotStoragePresetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)
                Text("SCREENSHOT STORAGE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            Text("Defaults start small for AI workflows. Raise this only when you need sharper saved captures.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: Spacing.sm) {
                ForEach(ScreenshotCapturePreset.allCases, id: \.self) { preset in
                    screenshotPresetOption(preset)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func screenshotPresetOption(_ preset: ScreenshotCapturePreset) -> some View {
        let isSelected = settingsManager.screenshotCapturePreset == preset

        return Button {
            settingsManager.screenshotCapturePreset = preset
        } label: {
            VStack(spacing: Spacing.xs) {
                Text(preset.label)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text(preset.sizeSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)

                Text(preset.detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var screenRecordingStorageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)
                Text("SCREEN CLIP STORAGE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            Text("Screen clips also start low by default. Higher tiers trade storage for smoother motion and cleaner playback.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: Spacing.sm) {
                ForEach(ScreenRecordingQualityPreset.allCases, id: \.self) { preset in
                    screenRecordingPresetOption(preset)
                }
            }

            Text("Reusable target countdown")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: Spacing.sm) {
                ForEach([0, 1, 3, 5], id: \.self) { seconds in
                    screenRecordingCountdownOption(seconds)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func screenRecordingPresetOption(_ preset: ScreenRecordingQualityPreset) -> some View {
        let isSelected = settingsManager.screenRecordingQualityPreset == preset

        return Button {
            settingsManager.screenRecordingQualityPreset = preset
        } label: {
            VStack(spacing: Spacing.xs) {
                Text(preset.label)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text("\(preset.bitrateSummary) • \(preset.fpsSummary)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)

                Text(preset.detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func screenRecordingCountdownOption(_ seconds: Int) -> some View {
        let isSelected = settingsManager.screenRecordingCountdownSeconds == seconds
        let title = seconds == 0 ? "Off" : "\(seconds)s"

        return Button {
            settingsManager.screenRecordingCountdownSeconds = seconds
        } label: {
            Text(title)
                .font(Theme.current.fontSMBold)
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // Screenshot shortcuts section removed — all shortcuts are now in the unified HOTKEYS section above.

    // MARK: - Hotkeys (Unified via HotkeyRegistry)

    private var hotkeysSection: some View {
        let registry = HotkeyRegistry.shared
        let captureActions: [HotkeyAction] = [
            .captureChord, .screenRecordChord,
            .captureFullscreen, .captureRegion, .captureWindow, .openTrayViewer, .openTrayShelf,
            .pasteLastScreenshot
        ]

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)
                Text("HOTKEYS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(captureActions) { action in
                    hotkeyRow(action: action, registry: registry)
                }
            }

            Text("Click a shortcut to customize it.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func hotkeyRow(action: HotkeyAction, registry: HotkeyRegistry) -> some View {
        HStack {
            Text(action.label)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 140, alignment: .leading)
            HotkeyRecorderButton(
                hotkey: Binding(
                    get: { registry.config(for: action) },
                    set: { registry.setConfig(action, $0) }
                ),
                isRecording: Binding(
                    get: { recordingAction == action },
                    set: { $0 ? (recordingAction = action) : (recordingAction = nil) }
                ),
                showReset: !registry.isDefault(action),
                resetValue: action.defaultConfig
            )
        }
    }

    // MARK: - Overlay Controls

    private var overlayControlsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple)
                    .frame(width: 3, height: 14)
                Text("OVERLAY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                ForEach(CaptureHUDPosition.allCases, id: \.self) { position in
                    hudPositionOption(position)
                }
            }

            Rectangle()
                .fill(Theme.current.divider)
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview Placement")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text(capturePreviewPlacement.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Picker("", selection: $capturePreviewPlacementRaw) {
                    ForEach(CaptureIslandPlacement.allCases) { placement in
                        Text(placement.displayName).tag(placement.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func hudPositionOption(_ position: CaptureHUDPosition) -> some View {
        let isSelected = settingsManager.captureHUDPosition == position

        return Button(action: {
            settingsManager.captureHUDPosition = position
        }) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: position.icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Text(position.label)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Theme.current.divider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func loadDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableDevices = discovery.devices

        // Set default selection if none set
        if captureService.selectedDeviceID.isEmpty, let first = availableDevices.first {
            captureService.selectedDeviceID = first.uniqueID
        }
    }

    private func normalizeCapturePreviewPlacement() {
        guard CaptureIslandPlacement(rawValue: capturePreviewPlacementRaw) == nil else { return }
        capturePreviewPlacementRaw = CaptureIslandPlacement.contextual.rawValue
    }
}
