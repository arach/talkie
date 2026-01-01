//
//  LiveSettingsView.swift
//  Talkie
//
//  Live settings view using Talkie's design system
//  With instrumented components from TalkieLive
//

import SwiftUI
import os
import QuartzCore  // For CATransaction render timing

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

enum LiveSettingsSection: String, Hashable {
    case general
    case shortcuts
    case sounds
    case audio
    case transcription
    case autoPaste
    case storage
    case permissions
}

struct LiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings
    @State private var selectedSection: LiveSettingsSection = .general

    // Live settings sidebar width - user-adjustable with smart defaults
    @AppStorage("liveSettings.sidebarWidth") private var sidebarWidth: Double = 220
    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 320

    // Theme-aware colors for light/dark mode
    private var sidebarBackground: Color { Theme.current.backgroundSecondary }
    private var contentBackground: Color { Theme.current.background }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header
                Text("LIVE SETTINGS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Menu Sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        // GENERAL
                        SettingsSidebarSection(title: "GENERAL", isActive: selectedSection == .general) {
                            SettingsSidebarItem(
                                icon: "waveform",
                                title: "OVERVIEW",
                                isSelected: selectedSection == .general
                            ) {
                                selectedSection = .general
                            }
                        }

                        // RECORDING
                        SettingsSidebarSection(title: "RECORDING", isActive: selectedSection == .shortcuts || selectedSection == .sounds || selectedSection == .audio) {
                            SettingsSidebarItem(
                                icon: "command",
                                title: "SHORTCUTS",
                                isSelected: selectedSection == .shortcuts
                            ) {
                                selectedSection = .shortcuts
                            }
                            SettingsSidebarItem(
                                icon: "speaker.wave.2",
                                title: "SOUNDS",
                                isSelected: selectedSection == .sounds
                            ) {
                                selectedSection = .sounds
                            }
                            SettingsSidebarItem(
                                icon: "mic",
                                title: "AUDIO",
                                isSelected: selectedSection == .audio
                            ) {
                                selectedSection = .audio
                            }
                        }

                        // PROCESSING
                        SettingsSidebarSection(title: "PROCESSING", isActive: selectedSection == .transcription || selectedSection == .autoPaste) {
                            SettingsSidebarItem(
                                icon: "text.bubble",
                                title: "TRANSCRIPTION",
                                isSelected: selectedSection == .transcription
                            ) {
                                selectedSection = .transcription
                            }
                            SettingsSidebarItem(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "AUTO-PASTE",
                                isSelected: selectedSection == .autoPaste
                            ) {
                                selectedSection = .autoPaste
                            }
                        }

                        // SYSTEM
                        SettingsSidebarSection(title: "SYSTEM", isActive: selectedSection == .storage || selectedSection == .permissions) {
                            SettingsSidebarItem(
                                icon: "clock",
                                title: "STORAGE",
                                isSelected: selectedSection == .storage
                            ) {
                                selectedSection = .storage
                            }
                            SettingsSidebarItem(
                                icon: "lock.shield",
                                title: "PERMISSIONS",
                                isSelected: selectedSection == .permissions
                            ) {
                                selectedSection = .permissions
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: sidebarWidth)
            .background(sidebarBackground)

            // Resizable divider
            LiveSettingsSidebarResizer(
                width: $sidebarWidth,
                minWidth: sidebarMinWidth,
                maxWidth: sidebarMaxWidth
            )

            // MARK: - Content Area
            VStack(spacing: 0) {
                Group {
                    switch selectedSection {
                    case .general:
                        GeneralLiveSettingsView()
                    case .shortcuts:
                        ShortcutsLiveSettingsView()
                    case .sounds:
                        SoundsLiveSettingsView()
                    case .audio:
                        AudioLiveSettingsView()
                    case .transcription:
                        TranscriptionLiveSettingsView()
                    case .autoPaste:
                        AutoPasteLiveSettingsView()
                    case .storage:
                        StorageLiveSettingsView()
                    case .permissions:
                        PermissionsLiveSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Use GeometryReader to detect actual layout completion
            GeometryReader { _ in
                Color.clear
                    .onAppear {
                        // This fires after the geometry is calculated
                        // Use CATransaction to wait for the render to complete
                        CATransaction.setCompletionBlock {
                            Task { @MainActor in
                                PerformanceMonitor.shared.markActionAsRendered(actionName: "LiveSettings")
                                PerformanceMonitor.shared.completeAction()
                                logger.info("🎨 LiveSettings fully rendered")
                            }
                        }
                        CATransaction.begin()
                        CATransaction.commit()
                    }
            }
        )
    }
}

// MARK: - Radio Button Row Component

struct RadioButtonRow<T: Equatable>: View {
    let title: String
    let description: String
    let value: T
    let selectedValue: T
    let onSelect: () -> Void
    var preview: AnyView? = nil

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: selectedValue == value ? "largecircle.fill.circle" : "circle")
                    .font(Theme.current.fontBody)
                    .foregroundColor(selectedValue == value ? .accentColor : Theme.current.foregroundSecondary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if let preview = preview {
                    preview
                        .frame(width: 80, height: 40)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - General Settings

struct GeneralLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        @Bindable var live = liveSettings

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "OVERVIEW",
                subtitle: "Configure Live recording behavior and visual feedback."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Live Recording Health Status
                LiveRecordingHealthCard()

                // Main layout: Screen LEFT, Settings RIGHT
                HStack(alignment: .top, spacing: Spacing.xl) {
                    // LEFT: Mock screen preview
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("PREVIEW")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text("Hover to simulate recording")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                        LivePreviewScreen(
                            overlayStyle: $live.overlayStyle,
                            hudPosition: $live.overlayPosition,
                            pillPosition: $live.pillPosition,
                            showOnAir: $live.showOnAir
                        )
                    }

                    // RIGHT: Settings (HUD top, ON AIR middle, Pill bottom)
                    VStack(alignment: .leading, spacing: 0) {
                        // HUD Section (top-aligned)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("HUD")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            StyledToggle(
                                label: "Show HUD overlay",
                                isOn: Binding(
                                    get: { live.overlayStyle.showsTopOverlay },
                                    set: { show in
                                        if show {
                                            live.overlayStyle = .particles
                                        } else {
                                            live.overlayStyle = .pillOnly
                                        }
                                    }
                                ),
                                help: "Animated feedback at top of screen"
                            )

                            if live.overlayStyle.showsTopOverlay {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    LiveStyleSelector(selection: $live.overlayStyle)

                                    // Speed toggle (applies to both particles and waveform)
                                    HStack(spacing: Spacing.sm) {
                                        Text("Speed")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary)

                                        Picker("", selection: Binding(
                                            get: {
                                                // particlesCalm = slow, particles = fast
                                                // waveform = slow, waveformSensitive = fast
                                                if live.overlayStyle == .particlesCalm || live.overlayStyle == .waveform {
                                                    return "slow"
                                                }
                                                return "fast"
                                            },
                                            set: { speed in
                                                if live.overlayStyle == .particles || live.overlayStyle == .particlesCalm {
                                                    live.overlayStyle = speed == "slow" ? .particlesCalm : .particles
                                                } else if live.overlayStyle == .waveform || live.overlayStyle == .waveformSensitive {
                                                    live.overlayStyle = speed == "slow" ? .waveform : .waveformSensitive
                                                }
                                            }
                                        )) {
                                            Text("Slow").tag("slow")
                                            Text("Fast").tag("fast")
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 100)
                                    }
                                }
                                .padding(.leading, Spacing.xxs)
                            }
                        }

                        Spacer().frame(height: Spacing.md)

                        // ON AIR (small middle section)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text("ON AIR")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(
                                        RoundedRectangle(cornerRadius: Spacing.xxs)
                                            .fill(live.showOnAir ? Color.red : Color.gray.opacity(Opacity.half))
                                    )

                                Toggle("", isOn: $live.showOnAir)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .controlSize(.mini)
                            }

                            Text("Neon sign in top-left during recording")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        // Pill Section (bottom-aligned)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PILL")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            StyledToggle(
                                label: "Expand during recording",
                                isOn: $live.pillExpandsDuringRecording,
                                help: "Show timer and audio level"
                            )

                            StyledToggle(
                                label: "Show on all screens",
                                isOn: $live.pillShowOnAllScreens,
                                help: "Display on every connected display"
                            )
                        }
                    }
                    .frame(width: 220)
                }

                // Settings summary
                LiveSettingsSummary()
            }
        }
        .onAppear {
            logger.debug("GeneralLiveSettingsView appeared")
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings
    @State private var isRecordingToggle = false
    @State private var isRecordingPTT = false

    var body: some View {
        @Bindable var live = liveSettings


        SettingsPageContainer {
            SettingsPageHeader(
                icon: "command",
                title: "SHORTCUTS",
                subtitle: "Configure keyboard shortcuts for Live recording."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Toggle Hotkey
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("TOGGLE RECORDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Press once to start recording, press again to stop.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    HotkeyRecorderButton(
                        hotkey: $live.hotkey,
                        isRecording: $isRecordingToggle
                    )
                }

                // Push-to-Talk Hotkey
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("PUSH-TO-TALK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Hold down to record, release to stop.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    StyledToggle(
                        label: "Enable Push-to-Talk",
                        isOn: $live.pttEnabled,
                        help: "Activate push-to-talk recording mode"
                    )

                    HotkeyRecorderButton(
                        hotkey: $live.pttHotkey,
                        isRecording: $isRecordingPTT
                    )
                    .opacity(live.pttEnabled ? 1.0 : 0.5)
                    .allowsHitTesting(live.pttEnabled)
                }
            }
        }
        .onAppear {
            logger.debug("ShortcutsLiveSettingsView appeared")
        }
    }
}

// MARK: - Audio Settings

struct AudioLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic",
                title: "AUDIO",
                subtitle: "Configure microphone input for Live recording."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Microphone Selection
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("INPUT DEVICE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Select which microphone to use for recording. The level meter shows real-time input volume.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    AudioDeviceSelector()
                }
            }
        }
        .onAppear {
            logger.debug("AudioLiveSettingsView appeared")
        }
    }
}

// MARK: - Sounds Settings

struct SoundsLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings
    @State private var selectedEvent: SoundEvent = .start

    var body: some View {
        @Bindable var live = liveSettings


        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "SOUNDS",
                subtitle: "Configure audio feedback for recording events."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Event Selector
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SELECT EVENT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.sm) {
                        ForEach(SoundEvent.allCases, id: \.rawValue) { event in
                            SoundEventCard(
                                event: event,
                                sound: {
                                    switch event {
                                    case .start: return live.startSound
                                    case .finish: return live.finishSound
                                    case .paste: return live.pastedSound
                                    }
                                }(),
                                isSelected: selectedEvent == event
                            ) {
                                selectedEvent = event
                                logger.debug("Selected sound event: \(event.rawValue)")
                            }
                        }
                    }

                    // Play sequence button
                    HStack {
                        Spacer()
                        PlaySequenceButton(sounds: [
                            live.startSound,
                            live.finishSound,
                            live.pastedSound
                        ])
                    }
                }

                // Sound Grid for selected event
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SOUND FOR \(selectedEvent.rawValue.uppercased())")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(selectedEvent.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    SoundGrid(selection: {
                        switch selectedEvent {
                        case .start: return $live.startSound
                        case .finish: return $live.finishSound
                        case .paste: return $live.pastedSound
                        }
                    }())
                }
            }
        }
        .onAppear {
            logger.debug("SoundsLiveSettingsView appeared")
        }
        .onChange(of: live.startSound) { _, newValue in
            logger.info("Start sound changed to: \(newValue.displayName)")
        }
        .onChange(of: live.finishSound) { _, newValue in
            logger.info("Finish sound changed to: \(newValue.displayName)")
        }
        .onChange(of: live.pastedSound) { _, newValue in
            logger.info("Pasted sound changed to: \(newValue.displayName)")
        }
    }
}

// MARK: - Transcription Settings

struct TranscriptionLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings
    @Environment(EngineClient.self) private var engineClient

    var body: some View {
        @Bindable var live = liveSettings


        SettingsPageContainer {
            SettingsPageHeader(
                icon: "text.bubble",
                title: "TRANSCRIPTION",
                subtitle: "Configure the speech-to-text engine."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Engine Health Status
                EngineHealthCard()

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("TRANSCRIPTION MODELS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Select a model to use for Live transcription. Models are downloaded and managed by the engine.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    // Model grid
                    if engineClient.availableModels.isEmpty {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading available models...")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .padding(.vertical, 20)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Spacing.sm),
                                GridItem(.flexible(), spacing: Spacing.sm)
                            ],
                            spacing: Spacing.sm
                        ) {
                            ForEach(engineClient.availableModels) { model in
                                STTModelCard(
                                    modelInfo: model,
                                    downloadProgress: engineClient.downloadProgress,
                                    isSelected: live.selectedModelId == model.id,
                                    onSelect: {
                                        selectModel(model, live: live)
                                    },
                                    onDownload: {
                                        downloadModel(model)
                                    },
                                    onDelete: {
                                        deleteModel(model)
                                    },
                                    onCancel: {
                                        cancelDownload()
                                    }
                                )
                            }
                        }
                        .padding(.top, Spacing.sm)
                    }
                }
            }
        }
        .onAppear {
            logger.debug("TranscriptionLiveSettingsView appeared")
            // Fetch available models when view appears
            Task {
                await engineClient.fetchAvailableModels()
            }
        }
    }

    private func selectModel(_ model: ModelInfo, live: LiveSettings) {
        guard model.isDownloaded else { return }

        logger.info("Selecting transcription model: \(model.id)")
        live.selectedModelId = model.id

        // Preload the model for fast transcription
        Task {
            do {
                try await engineClient.preloadModel(model.id)
                logger.info("✓ Model preloaded: \(model.id)")
            } catch {
                logger.error("Failed to preload model: \(error.localizedDescription)")
            }
        }
    }

    private func downloadModel(_ model: ModelInfo) {
        logger.info("Downloading transcription model: \(model.id)")

        Task {
            do {
                try await engineClient.downloadModel(model.id)
                logger.info("✓ Model downloaded: \(model.id)")

                // Start monitoring progress
                startMonitoringDownload()
            } catch {
                logger.error("Download failed: \(error.localizedDescription)")
            }
        }
    }

    private func deleteModel(_ model: ModelInfo) {
        logger.warning("Delete model not yet implemented: \(model.id)")
        // TODO: Add delete functionality to engine
    }

    private func cancelDownload() {
        logger.info("Canceling model download")

        Task {
            await engineClient.cancelDownload()
        }
    }

    private func startMonitoringDownload() {
        // Monitor download progress every second
        Task {
            while engineClient.isDownloading {
                try? await Task.sleep(for: .seconds(1)) // 1 second
                engineClient.refreshDownloadProgress()
            }
        }
    }
}

// MARK: - Auto-Paste Settings

struct AutoPasteLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        @Bindable var live = liveSettings


        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "AUTO-PASTE",
                subtitle: "Control how transcribed text is delivered."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("ROUTING MODE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .padding(.top, 1)
                        Text("Controls where transcribed text is sent after recording completes.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    RadioButtonRow(
                        title: RoutingMode.paste.displayName,
                        description: RoutingMode.paste.description,
                        value: RoutingMode.paste,
                        selectedValue: live.routingMode
                    ) {
                        live.routingMode = .paste
                    }

                    RadioButtonRow(
                        title: RoutingMode.clipboardOnly.displayName,
                        description: RoutingMode.clipboardOnly.description,
                        value: RoutingMode.clipboardOnly,
                        selectedValue: live.routingMode
                    ) {
                        live.routingMode = .clipboardOnly
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .padding(.top, 1)
                        Text("Contextual options for how Live interacts with your workflow.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    StyledToggle(
                        label: "Return to origin app after pasting",
                        isOn: $live.returnToOriginAfterPaste,
                        help: "Automatically switches back to the app you were using when the recording started"
                    )
                }

                // Primary Context Source
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("CONTEXT PREFERENCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .padding(.top, 1)
                        Text("Which app context should be considered primary for recordings.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    RadioButtonRow(
                        title: PrimaryContextSource.startApp.displayName,
                        description: PrimaryContextSource.startApp.description,
                        value: .startApp,
                        selectedValue: live.primaryContextSource
                    ) {
                        live.primaryContextSource = .startApp
                    }

                    RadioButtonRow(
                        title: PrimaryContextSource.endApp.displayName,
                        description: PrimaryContextSource.endApp.description,
                        value: .endApp,
                        selectedValue: live.primaryContextSource
                    ) {
                        live.primaryContextSource = .endApp
                    }
                }
            }
        }
    }
}

// MARK: - Storage Settings

struct StorageLiveSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        @Bindable var live = liveSettings


        SettingsPageContainer {
            SettingsPageHeader(
                icon: "clock",
                title: "STORAGE",
                subtitle: "Configure how long Live recordings are kept."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("RETENTION PERIOD")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Recordings older than this will be automatically deleted.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    HStack {
                        Stepper(
                            value: $live.utteranceTTLHours,
                            in: 1...720,
                            step: 24
                        ) {
                            Text("\(live.utteranceTTLHours) hours (\(live.utteranceTTLHours / 24) days)")
                                .font(Theme.current.fontSM)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Permissions Settings

struct PermissionsLiveSettingsView: View {
    private let permissionsManager = PermissionsManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "lock.shield",
                title: "PERMISSIONS",
                subtitle: "System permissions required for Live features."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Microphone
                PermissionLiveRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Required for recording audio",
                    status: permissionsManager.microphoneStatus,
                    onRequest: {
                        if permissionsManager.microphoneStatus == .notDetermined {
                            permissionsManager.requestMicrophonePermission()
                        } else {
                            permissionsManager.openMicrophoneSettings()
                        }
                    }
                )

                Divider()

                // Accessibility
                PermissionLiveRow(
                    icon: "hand.point.up.left.fill",
                    name: "Accessibility",
                    description: "Required to auto-paste transcriptions (simulates Cmd+V)",
                    status: permissionsManager.accessibilityStatus,
                    onRequest: {
                        permissionsManager.requestAccessibilityPermission()
                    }
                )
            }

            Divider()
                .padding(.vertical, Spacing.sm)

            // Context Capture Privacy Controls
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("CONTEXT CAPTURE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Controls what information is captured about active apps during recording.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                }

                // Session kill-switch
                StyledToggle(
                    label: "Enable context capture for this session",
                    isOn: Binding(
                        get: { LiveSettings.shared.contextCaptureSessionAllowed },
                        set: { LiveSettings.shared.contextCaptureSessionAllowed = $0 }
                    ),
                    help: "Temporarily disable all context capture (resets on app restart)"
                )

                // Detail level (only shown if session allowed)
                if LiveSettings.shared.contextCaptureSessionAllowed {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Detail Level")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        ForEach([ContextCaptureDetail.off, .metadataOnly, .rich], id: \.rawValue) { detail in
                            RadioButtonRow(
                                title: detail.displayName,
                                description: detail.description,
                                value: detail,
                                selectedValue: LiveSettings.shared.contextCaptureDetail
                            ) {
                                LiveSettings.shared.contextCaptureDetail = detail
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, Spacing.sm)

            // Refresh button
            HStack {
                Button(action: {
                    permissionsManager.refreshAllPermissions()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(Theme.current.fontXS)
                        Text("REFRESH STATUS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.secondary.opacity(Opacity.light))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    permissionsManager.openPrivacySettings()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gear")
                            .font(Theme.current.fontXS)
                        Text("OPEN PRIVACY SETTINGS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.secondary.opacity(Opacity.light))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }

            // Info note
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("TalkieLive runs as a background helper app. These permissions apply to the TalkieLive helper, not Talkie. Grant when prompted, or check System Settings → Privacy & Security.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Show bundle ID for dev/staging builds
                if let bundleID = Bundle.main.bundleIdentifier,
                   bundleID.hasSuffix(".dev") || bundleID.hasSuffix(".staging") {
                    Divider()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "app.badge")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Look for TalkieLive helper in System Settings:")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text("jdi.talkie.live" + (bundleID.hasSuffix(".dev") ? ".dev" : bundleID.hasSuffix(".staging") ? ".staging" : ""))
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Color.secondary.opacity(Opacity.subtle))
            .cornerRadius(CornerRadius.sm)
        }
        .onAppear {
            permissionsManager.refreshAllPermissions()
        }
    }
}

// MARK: - Permission Row for Live Settings

private struct PermissionLiveRow: View {
    let icon: String
    let name: String
    let description: String
    let status: PermissionStatus
    let onRequest: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(Theme.current.fontTitle)
                .foregroundColor(status.color)
                .frame(width: 32, height: 32)
                .background(status.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.sm)

            // Name and description
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: Spacing.xxs) {
                Image(systemName: status.icon)
                    .font(Theme.current.fontXS)
                Text(status.displayName)
                    .font(Theme.current.fontXSMedium)
            }
            .foregroundColor(status.color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(status.color.opacity(Opacity.light))
            .cornerRadius(CornerRadius.xs)

            // Action button
            Button(action: onRequest) {
                Text(status == .granted ? "SETTINGS" : "ENABLE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(status == .granted ? Theme.current.foregroundSecondary : .white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(status == .granted ? Color.secondary.opacity(Opacity.medium) : Color.accentColor)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Live Settings Sidebar Resizer Component

/// Native-style resizer divider (mimics NSSplitView behavior)
private struct LiveSettingsSidebarResizer: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        // Native macOS split view style: 1px divider with expanded hit area
        ZStack {
            // Background to prevent window color bleeding through
            Rectangle()
                .fill(Theme.current.background)
                .frame(width: 8)

            // Visible 1px divider line - use theme color for consistency
            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    let newWidth = width + value.translation.width
                    width = min(maxWidth, max(minWidth, newWidth))
                }
                .onEnded { _ in
                    isDragging = false
                    if !isHovering {
                        NSCursor.pop()
                    }
                }
        )
    }
}

#Preview {
    LiveSettingsView()
        .frame(width: 800, height: 600)
}
