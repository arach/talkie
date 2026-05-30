//
//  SettingsNext.swift
//  Talkie iOS
//
//  Fresh design — not a port. Replaces the legacy SettingsView with
//  an Inspector pattern: a left rail of rotated-type chips (the
//  "radio band" language established in Console Side-label) +
//  the active section's panel on the right.
//
//  Six inspector sections — VOICE / LOOK / CONNECT / KEYS / LAB /
//  ABOUT. Each panel shows fields, optional metric strips, and
//  action rows.
//
//  Paint-only pass. All values are placeholders. Codex wires real
//  bindings against:
//    - VOICE → TalkieAppSettings (engine, sample rate), input device
//    - LOOK → ThemeManager (theme), TalkieAppSettings (density,
//      accent, motion)
//    - CONNECT → iCloudStatusManager, BridgeManager, account state
//    - KEYS → TalkieAppSettings keyboard config
//    - LAB → reset helpers (DEBUG)
//    - ABOUT → Bundle info, logs, bridge protocol
//
//  Studio source: design/studio/components/studies/Settings.tsx,
//  variant "inspector" with the rail-on-left layout.
//

import Security
import SwiftUI

struct SettingsNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var aiCredentials = AICredentialStore.shared
    @ObservedObject private var iCloudStatus = iCloudStatusManager.shared
    @ObservedObject private var cloudKitSyncHealth = CloudKitSyncHealth.shared
    @ObservedObject private var parakeetManager = ParakeetModelManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var active: InspectorTab
    @State private var showingLogViewer = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case voice = "VOICE"
        case look = "LOOK"
        case connect = "CONNECT"
        case keys = "KEYS"
        case lab = "LAB"
        case about = "ABOUT"

        var id: String { rawValue }

        /// Match `--inspectorTab=<value>` launch arg (case-insensitive
        /// short form, e.g. "voice", "look").
        static func from(launchArg value: String) -> InspectorTab? {
            allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
        }
    }

    private struct SettingsChoice: Identifiable, Equatable {
        let id: String
        let title: String
    }

    /// Transcription engine choices for the Voice panel's keyboard
    /// (dictation) preference. Mirrors `TranscriptionEnginePreference`
    /// — the model layer's source of truth.
    private static let transcriptionEngineChoices: [SettingsChoice] = [
        SettingsChoice(id: "auto", title: "Auto"),
        SettingsChoice(id: "parakeet", title: "Parakeet"),
        SettingsChoice(id: "apple", title: "Apple Speech")
    ]

    private static let recordingInputChoices: [SettingsChoice] = [
        SettingsChoice(id: "system", title: "System default"),
        SettingsChoice(id: "builtIn", title: "Built-in mic"),
        SettingsChoice(id: "bluetooth", title: "Bluetooth")
    ]

    private static let recordingSampleRateChoices: [SettingsChoice] = [
        SettingsChoice(id: "system", title: "System"),
        SettingsChoice(id: "44100", title: "44.1 kHz"),
        SettingsChoice(id: "48000", title: "48 kHz")
    ]

    private static let appearanceDensityChoices: [SettingsChoice] = [
        SettingsChoice(id: "standard", title: "Standard"),
        SettingsChoice(id: "compact", title: "Compact"),
        SettingsChoice(id: "comfortable", title: "Comfort")
    ]

    private static let appearanceAccentIntensityChoices: [SettingsChoice] = [
        SettingsChoice(id: "theme", title: "Theme"),
        SettingsChoice(id: "subtle", title: "Subtle"),
        SettingsChoice(id: "vivid", title: "Vivid")
    ]

    private static let appearanceWordmarkChoices: [SettingsChoice] = [
        SettingsChoice(id: "mono", title: "Mono"),
        SettingsChoice(id: "ribbon", title: "Ribbon"),
        SettingsChoice(id: "compact", title: "Compact")
    ]

    private static let ttsProviderChoices: [SettingsChoice] = [
        SettingsChoice(id: "local", title: "Local"),
        SettingsChoice(id: "openai", title: "OpenAI"),
        SettingsChoice(id: "elevenlabs", title: "ElevenLabs")
    ]

    private static let ttsRouteChoices: [SettingsChoice] = [
        SettingsChoice(id: "bridge", title: "Via Mac"),
        SettingsChoice(id: "direct", title: "Direct")
    ]

    private static let aiVoiceOutputChoices: [SettingsChoice] = [
        SettingsChoice(id: "phone", title: "iPhone"),
        SettingsChoice(id: "watch", title: "Watch")
    ]

    init() {
        // Honor `--inspectorTab=<voice|look|connect|keys|lab|about>`
        // so per-panel screenshot loops can boot directly into each
        // panel without UI automation taps.
        let args = ProcessInfo.processInfo.arguments
        let initialTab: InspectorTab
        if let flagIdx = args.firstIndex(where: { $0.hasPrefix("--inspectorTab=") }) {
            let value = args[flagIdx].dropFirst("--inspectorTab=".count)
            initialTab = InspectorTab.from(launchArg: String(value)) ?? .voice
        } else if let flagIdx = args.firstIndex(of: "--inspectorTab"),
                  flagIdx + 1 < args.count,
                  let tab = InspectorTab.from(launchArg: args[flagIdx + 1]) {
            initialTab = tab
        } else {
            initialTab = .voice
        }
        _active = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                    .background(theme.currentTheme.chrome.edgeFaint)
                HStack(spacing: 0) {
                    rail
                    panel
                }
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            DebugLogsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · SETTINGS")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openHome() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Rail (left, rotated chips)

    private var rail: some View {
        VStack(spacing: 0) {
            ForEach(InspectorTab.allCases) { tab in
                railChip(tab)
                if tab != InspectorTab.allCases.last {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeFaint)
                        .frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 28)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(width: 1)
        }
    }

    private func railChip(_ tab: InspectorTab) -> some View {
        let isActive = tab == active
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { active = tab }
        } label: {
            // EXACT 28×88 chip cell. `.frame(width:height:)` is non-
            // negotiable, so the rotated text's natural width (which
            // is the unrotated word length: 25pt for LAB, 56pt for
            // CONNECT) can't expand the cell. Rotation is visual-only,
            // and the rendered rotated text fits well within 28pt
            // regardless of word length.
            ZStack {
                Text(tab.rawValue)
                    .font(.system(size: 9,
                                  weight: isActive ? .semibold : .medium,
                                  design: .monospaced))
                    .tracking(3.2)
                    .foregroundStyle(
                        isActive
                            ? theme.colors.textPrimary
                            : theme.colors.textTertiary
                    )
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 88)
            .background(
                isActive
                    ? theme.currentTheme.chrome.accent.opacity(0.12)
                    : Color.clear
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isActive ? theme.currentTheme.chrome.accent : Color.clear)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active panel (right)

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INSPECTOR · \(active.rawValue)")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch active {
                    case .voice: voicePanel
                    case .look: lookPanel
                    case .connect: connectPanel
                    case .keys: keysPanel
                    case .lab: labPanel
                    case .about: aboutPanel
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Parakeet install row
    //
    // Explicit install / uninstall affordance for the on-device
    // Parakeet model. Downloads run through ParakeetModelManager which
    // persists the model on disk — one download per device until the
    // user taps Uninstall. Subsequent app launches see the cached
    // model and skip straight to .ready/.loading.
    private var parakeetInstallRow: some View {
        let state = parakeetManager.state
        let model = appSettings.preferredParakeetModel

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet \(model.shortDescription)")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(parakeetSubtitle(for: state, model: model))
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer()
            parakeetTrailingControl(state: state, model: model)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 1)
        }
    }

    private func parakeetSubtitle(for state: ParakeetModelManager.ModelState,
                                  model: ParakeetModel) -> String {
        switch state {
        case .notDownloaded:
            return "Tap install to download once · stays local until uninstall"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))% · don't close the app"
        case .downloaded, .loading:
            return "Preparing model…"
        case .ready:
            return "Installed · ready for dictation, agentic, terminal"
        case .error(let detail):
            return "Error: \(detail)"
        }
    }

    @ViewBuilder
    private func parakeetTrailingControl(state: ParakeetModelManager.ModelState,
                                         model: ParakeetModel) -> some View {
        switch state {
        case .notDownloaded:
            Button {
                installParakeet(model)
            } label: {
                Text("INSTALL")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            .buttonStyle(.plain)

        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 70)
                    .tint(theme.currentTheme.chrome.accent)
                Text("\(Int(progress * 100))%")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }

        case .downloaded, .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("LOADING")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textTertiary)
            }

        case .ready:
            Button {
                uninstallParakeet(model)
            } label: {
                Text("UNINSTALL")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Remove the cached Parakeet model")

        case .error:
            Button {
                installParakeet(model)
            } label: {
                Text("RETRY")
                    .talkieType(.chipLabel)
                    .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
            }
            .buttonStyle(.plain)
        }
    }

    private func installParakeet(_ model: ParakeetModel) {
        Task {
            do {
                try await ParakeetModelManager.shared.downloadAndLoad(model)
            } catch {
                AppLogger.transcription.error("Parakeet install failed: \(error.localizedDescription)")
            }
        }
    }

    private func uninstallParakeet(_ model: ParakeetModel) {
        do {
            try ParakeetModelManager.shared.deleteModel(model)
        } catch {
            AppLogger.transcription.error("Parakeet uninstall failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Panels

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("TRANSCRIPTION")
            // Dictation (keyboard) engine — the one Compose + the
            // in-app keyboard actually use. Memo engine has its own
            // row further down so the two don't get conflated.
            cycleRow(
                "Dictation engine",
                selection: Binding(
                    get: { appSettings.transcriptionKeyboardEngine.rawValue },
                    set: { raw in
                        if let pref = TranscriptionEnginePreference(rawValue: raw) {
                            appSettings.transcriptionKeyboardEngine = pref
                            TranscriptionService.shared.keyboardEnginePreference = pref
                        }
                    }
                ),
                choices: Self.transcriptionEngineChoices,
                hint: "Used by Compose mic + Talkie keyboard"
            )
            cycleRow(
                "Memo engine",
                selection: Binding(
                    get: { appSettings.transcriptionMemoEngine.rawValue },
                    set: { raw in
                        if let pref = TranscriptionEnginePreference(rawValue: raw) {
                            appSettings.transcriptionMemoEngine = pref
                            TranscriptionService.shared.memoEnginePreference = pref
                        }
                    }
                ),
                choices: Self.transcriptionEngineChoices,
                hint: "Used by background voice memo transcription"
            )
            metricStrip(
                title: "ENGINE STATE",
                metrics: [("LATENCY", "—"), ("WER", "—"), ("LOADED", parakeetManager.statusDescription.uppercased())]
            )

            parakeetInstallRow

            sectionHeader("RECORDING")
            toggleRow(
                "Tag Location",
                isOn: Binding(
                    get: { appSettings.tagLocationEnabled },
                    set: { enabled in
                        appSettings.tagLocationEnabled = enabled
                        if enabled {
                            LocationService.shared.requestPermission()
                        }
                    }
                ),
                valueOn: "On",
                valueOff: "Off",
                hint: "Attach coordinates to voice memos"
            )
            cycleRow(
                "Input device",
                selection: Binding(
                    get: { appSettings.recordingInputDevice },
                    set: { appSettings.recordingInputDevice = $0 }
                ),
                choices: Self.recordingInputChoices,
                hint: "Preferred microphone"
            )
            cycleRow(
                "Sample rate",
                selection: Binding(
                    get: { appSettings.recordingSampleRate },
                    set: { appSettings.recordingSampleRate = $0 }
                ),
                choices: Self.recordingSampleRateChoices,
                hint: "Recorder preference"
            )
            toggleRow(
                "Echo cancellation",
                isOn: Binding(
                    get: { appSettings.recordingEchoCancellationEnabled },
                    set: { appSettings.recordingEchoCancellationEnabled = $0 }
                ),
                valueOn: "On",
                valueOff: "Off",
                hint: "Voice isolation"
            )
            sectionHeader("TEXT-TO-SPEECH")
            cycleRow(
                "Provider",
                selection: Binding(
                    get: { appSettings.ttsProvider },
                    set: { provider in
                        appSettings.ttsProvider = provider
                        normalizeSpeechSettings(for: provider)
                    }
                ),
                choices: Self.ttsProviderChoices,
                hint: speechProviderHint
            )
            if appSettings.ttsProvider == "local" {
                field("Route", "Via Mac", hint: "Kokoro over Bridge")
            } else {
                cycleRow(
                    "Route",
                    selection: Binding(
                        get: { appSettings.ttsMode },
                        set: { appSettings.ttsMode = $0 }
                    ),
                    choices: Self.ttsRouteChoices,
                    hint: speechRouteHint
                )
            }
            textEntryRow(
                "Voice",
                text: Binding(
                    get: { appSettings.ttsVoice },
                    set: { appSettings.ttsVoice = $0 }
                ),
                placeholder: speechVoicePlaceholder,
                hint: speechVoiceSummary
            )
            if shouldShowSpeechCredentialRow {
                if let reusableSpeechCredential {
                    field(
                        "API Key",
                        "AI keys",
                        hint: "Using saved \(reusableSpeechCredential.providerName) credential"
                    )
                } else {
                    textEntryRow(
                        "API Key",
                        text: Binding(
                            get: { appSettings.ttsApiKey },
                            set: { appSettings.ttsApiKey = $0 }
                        ),
                        placeholder: "Paste key",
                        hint: speechCredentialSummary,
                        secure: true
                    )
                }
            }
            toggleRow(
                "Speak replies",
                isOn: Binding(
                    get: { appSettings.aiVoiceOutputRoute != "silent" },
                    set: { appSettings.aiVoiceOutputRoute = $0 ? "phone" : "silent" }
                ),
                valueOn: aiVoiceRouteLabel,
                valueOff: "Silent",
                hint: "AI command responses"
            )
            if appSettings.aiVoiceOutputRoute != "silent" {
                cycleRow(
                    "Output",
                    selection: Binding(
                        get: { appSettings.aiVoiceOutputRoute },
                        set: { appSettings.aiVoiceOutputRoute = $0 }
                    ),
                    choices: Self.aiVoiceOutputChoices,
                    hint: "Where short replies speak"
                )
            }
            navRow("Manage AI keys") { AppShellRouter.shared.openAICredentials() }
        }
    }

    private var lookPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Theme", theme.currentTheme.displayName)
            cycleRow(
                "Density",
                selection: Binding(
                    get: { appSettings.appearanceDensity },
                    set: { appSettings.appearanceDensity = $0 }
                ),
                choices: Self.appearanceDensityChoices,
                hint: "Inspector spacing"
            )
            cycleRow(
                "Accent intensity",
                selection: Binding(
                    get: { appSettings.appearanceAccentIntensity },
                    set: { appSettings.appearanceAccentIntensity = $0 }
                ),
                choices: Self.appearanceAccentIntensityChoices,
                hint: "Chrome glow strength"
            )
            cycleRow(
                "Wordmark style",
                selection: Binding(
                    get: { appSettings.appearanceWordmarkStyle },
                    set: { appSettings.appearanceWordmarkStyle = $0 }
                ),
                choices: Self.appearanceWordmarkChoices,
                hint: "Header treatment"
            )
            toggleRow(
                "Reduce motion",
                isOn: Binding(
                    get: { appSettings.reduceMotionEnabled },
                    set: { appSettings.reduceMotionEnabled = $0 }
                ),
                valueOn: "Reduced",
                valueOff: "Standard",
                hint: theme.appearanceMode.displayName
            )

            // Theme picker — labeled chip swatches under a THEMES eyebrow.
            // Two themes share the indigo accent (Ghost / Lift), so the
            // name label is what distinguishes them, not the color.
            VStack(alignment: .leading, spacing: 10) {
                Text("THEMES")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(height: 1)
                    }

                // ≤4 themes → single row. 5+ → 3-column grid so labels
                // like TACTICAL / GRAPHITE never compete for ~56pt of
                // width on a mini-class phone.
                if AppTheme.allCases.count > 4 {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 14
                    ) {
                        ForEach(AppTheme.allCases, id: \.self) { t in
                            themeSwatch(t)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(AppTheme.allCases, id: \.self) { t in
                            themeSwatch(t)
                        }
                    }
                }
            }
            .padding(.top, 18)
        }
    }

    private func themeSwatch(_ t: AppTheme) -> some View {
        let isActive = t == theme.currentTheme
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(t.chrome.accent)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isActive
                                ? theme.colors.textPrimary
                                : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: isActive ? 2 : 1
                        )
                )
            Text(t.rawValue.uppercased())
                .talkieType(.channelLabelTiny)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    isActive
                        ? theme.colors.textPrimary
                        : theme.colors.textTertiary
                )
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            theme.apply(theme: t)
        }
    }

    private var connectPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field(
                "iCloud sync",
                appSettings.iCloudSyncEnabled ? "On" : "Off",
                hint: iCloudHint,
                inlineAction: iCloudInlineAction
            )
            field("Last iCloud sync", iCloudLastSyncValue, hint: iCloudLastSyncHint)
            field(
                "Mac Bridge",
                bridgeStatusValue,
                hint: bridgeStatusHint,
                inlineAction: bridgeInlineAction
            )
            toggleRow(
                "Auto-open Command Deck",
                isOn: Binding(
                    get: { appSettings.followComputerShortcutMode },
                    set: { appSettings.followComputerShortcutMode = $0 }
                ),
                valueOn: "On",
                valueOff: "Off",
                hint: companionShortcutHint
            )
            field("Account", nativeAccountValue, hint: "Sign in with Apple")
            metricStrip(
                title: "LINK HEALTH",
                metrics: [("RTT", "—"), ("SENT", "—"), ("QUEUED", "—")]
            )
            #if DEBUG
            navRow("SSH Terminal") { AppShellRouter.shared.openTerminal() }
            #endif
            navRow("Command Deck remote") { AppShellRouter.shared.openDeck() }
            navRow("View connections detail") { AppShellRouter.shared.openConnectionCenter() }
            navRow("Workspaces") { AppShellRouter.shared.openWorkspaces() }
            navRow("Resolve sync conflicts") { AppShellRouter.shared.openSyncConflicts() }
            if isNativelySignedIn {
                actionRow("Sign out", tone: .warn) { resetAuthState() }
            } else {
                actionRow("Sign in with Apple", tone: .accent) { AppShellRouter.shared.openSignIn() }
            }
        }
    }

    // MARK: - Inline actions / hints (connect panel)

    /// Surface a "RECONNECT" chip inline on the Mac Bridge field when
    /// we have a saved pair but aren't currently connected. Tap calls
    /// the same `bridgeManager.connect()` the bottom Re-pair row used
    /// to, but reads as a recovery action — not a destructive re-pair.
    private var bridgeInlineAction: InlineFieldAction? {
        guard bridgeManager.isPaired else { return nil }
        switch bridgeManager.status {
        case .disconnected, .error:
            return InlineFieldAction(label: "RECONNECT") {
                Task { await bridgeManager.connect() }
            }
        case .connecting, .connected:
            return nil
        }
    }

    /// Suppress the noisy "iCloud Status Unknown" hint when the
    /// account check is still pending — sim builds and pre-auth states
    /// frequently land there and the user can't act on it. Only
    /// surface a hint when something is actually wrong, with a
    /// "CHECK" chip the user can tap to re-run the status query.
    private var iCloudHint: String? {
        switch iCloudStatus.status {
        case .available, .checking, .couldNotDetermine: return nil
        default: return iCloudStatus.status.title
        }
    }

    private var iCloudInlineAction: InlineFieldAction? {
        switch iCloudStatus.status {
        case .error, .temporarilyUnavailable, .noAccount, .restricted:
            return InlineFieldAction(label: "CHECK") {
                iCloudStatus.checkStatus()
            }
        case .available, .checking, .couldNotDetermine:
            return nil
        }
    }

    private var latestCloudKitSyncAt: Date? {
        [cloudKitSyncHealth.lastSuccessfulExport, cloudKitSyncHealth.lastSuccessfulImport]
            .compactMap { $0 }
            .max()
    }

    private var iCloudLastSyncValue: String {
        guard appSettings.iCloudSyncEnabled else { return "Off" }
        guard let latestCloudKitSyncAt else { return "Pending" }
        return latestCloudKitSyncAt.formatted(.relative(presentation: .named))
    }

    private var iCloudLastSyncHint: String? {
        guard appSettings.iCloudSyncEnabled else { return "Disabled in preferences" }
        guard latestCloudKitSyncAt != nil else {
            return "Waiting for CloudKit event · \(cloudKitSyncHealth.status.rawValue)"
        }

        if let export = cloudKitSyncHealth.lastSuccessfulExport,
           let importDate = cloudKitSyncHealth.lastSuccessfulImport {
            return "\(export >= importDate ? "Last export" : "Last import") · \(cloudKitSyncHealth.status.rawValue)"
        }

        if cloudKitSyncHealth.lastSuccessfulExport != nil {
            return "Last export · \(cloudKitSyncHealth.status.rawValue)"
        }

        return "Last import · \(cloudKitSyncHealth.status.rawValue)"
    }

    private var keysPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Dictation engine", appSettings.transcriptionKeyboardEngine.displayName)
            field("Auto-format", appSettings.keyboardModeEnabled ? "Keyboard mode" : "Default", hint: appSettings.keyboardActiveLayout)
            field("Punctuation", "Inferred") // TODO: no TalkieAppSettings key exists yet.
            field("Auto-capitalize", appSettings.keyboardAutoCapitalizeEnabled ? "On" : "Off")
            field("Trailing space", "Smart") // TODO: no TalkieAppSettings key exists yet.
            field("Voice activation", appSettings.keyboardLEDIndicatorsEnabled ? "Indicators on" : "Indicators off")
            field("Haptic feedback", appSettings.keyboardHapticFeedbackEnabled ? "On" : "Off")
        }
    }

    private var labPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Debug-only. These won't ship in release builds.")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.bottom, 10)

            actionRow("Reset onboarding", tone: .neutral) { appSettings.hasSeenOnboarding = false }
            actionRow("Reset auth state", tone: .neutral) { resetAuthState() }
            actionRow("Reset resume tooltip", tone: .neutral) { appSettings.hasSeenResumeTooltip = false }
            actionRow("Dump shared store", tone: .neutral) { dumpSharedStore() }
            actionRow("Force iCloud refresh", tone: .neutral) { iCloudStatus.checkStatus() }
            navRow("Inspect theme contrast") { AppShellRouter.shared.openThemeContrast() }
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Version", Bundle.main.shortVersion)
            field("Build", Bundle.main.buildNumber)
            field("Channel", iosChannel)
            field("Engine", appSettings.preferredParakeetModel.displayName)
            field("Mac bridge protocol", "talkie-bridge-v1")
            navRow("Manage AI keys") { AppShellRouter.shared.openAICredentials() }
            navRow("Workflows hub") { AppShellRouter.shared.openWorkflows() }
            navRow("View logs") { showingLogViewer = true }
            navRow("Send feedback") { AppShellRouter.shared.openFeedback() }
        }
    }

    // MARK: - Panel primitives

    private enum InspectorRowMetrics {
        static let height: CGFloat = 44
        static let trailingValueMinWidth: CGFloat = 52
        static let trailingControlSpacing: CGFloat = 8
        static let trailingControlWidth: CGFloat = 14
    }

    @ViewBuilder
    private func rowLabelColumn(label: String, hint: String?) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)

            if let hint {
                Text("· \(hint)")
                    .talkieType(.hint)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .layoutPriority(2)
    }

    private func inspectorRowDivider() -> some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: 1)
    }

    /// Optional tappable chip placed at the trailing edge of a field
    /// row — used when the field's state implies a recovery action
    /// (e.g. RECONNECT on a disconnected bridge). Keeps the action
    /// physically adjacent to the state it acts on.
    struct InlineFieldAction {
        let label: String
        let action: () -> Void
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .frame(height: 32)
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 1)
        }
    }

    private func field(
        _ label: String,
        _ value: String,
        hint: String? = nil,
        inlineAction: InlineFieldAction? = nil
    ) -> some View {
        // Fixed-height row. Hint, when present, sits INLINE with the
        // label (truncated if it crowds the value) so the row never
        // grows beyond 44pt — gives every panel the same rhythm
        // regardless of hint presence.
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .layoutPriority(2)

            if let hint {
                Text("· \(hint)")
                    .talkieType(.hint)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }

            Spacer(minLength: 8)

            HStack(spacing: InspectorRowMetrics.trailingControlSpacing) {
                Text(value)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(
                        minWidth: InspectorRowMetrics.trailingValueMinWidth,
                        alignment: .trailing
                    )

                if let inlineAction {
                    Button(action: inlineAction.action) {
                        Text(inlineAction.label)
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        theme.currentTheme.chrome.accent.opacity(0.55),
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(inlineAction.label) \(label)")
                } else {
                    Color.clear
                        .frame(
                            width: InspectorRowMetrics.trailingControlWidth,
                            height: InspectorRowMetrics.trailingControlWidth
                        )
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: InspectorRowMetrics.height)
        .overlay(alignment: .bottom) {
            inspectorRowDivider()
        }
    }

    private func cycleRow(
        _ label: String,
        selection: Binding<String>,
        choices: [SettingsChoice],
        hint: String? = nil,
        onChange: ((String) -> Void)? = nil
    ) -> some View {
        let current = choices.first { $0.id == selection.wrappedValue }
            ?? choices.first
            ?? SettingsChoice(id: selection.wrappedValue, title: selection.wrappedValue)

        return Button {
            guard !choices.isEmpty else { return }
            let currentIndex = choices.firstIndex { $0.id == selection.wrappedValue }
            let nextIndex = currentIndex.map { choices.index(after: $0) % choices.count } ?? choices.startIndex
            let nextValue = choices[nextIndex].id
            selection.wrappedValue = nextValue
            onChange?(nextValue)
        } label: {
            HStack(alignment: .center, spacing: 6) {
                rowLabelColumn(label: label, hint: hint)
                    .layoutPriority(0)

                Spacer(minLength: 8)

                HStack(spacing: InspectorRowMetrics.trailingControlSpacing) {
                    Text(current.title)
                        .talkieType(.fieldValue)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(
                            minWidth: InspectorRowMetrics.trailingValueMinWidth,
                            alignment: .trailing
                        )

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: InspectorRowMetrics.height)
            .overlay(alignment: .bottom) {
                inspectorRowDivider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(current.title)")
        .accessibilityHint("Cycles to the next option")
    }

    private func textEntryRow(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        hint: String? = nil,
        secure: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            rowLabelColumn(label: label, hint: hint)
                .layoutPriority(0)

            Spacer(minLength: 8)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .talkieType(.fieldValue)
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .tint(theme.currentTheme.chrome.accent)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .lineLimit(1)
            .frame(maxWidth: 150)
        }
        .frame(height: InspectorRowMetrics.height)
        .overlay(alignment: .bottom) {
            inspectorRowDivider()
        }
    }

    private func toggleRow(
        _ label: String,
        isOn: Binding<Bool>,
        valueOn: String,
        valueOff: String,
        hint: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            rowLabelColumn(label: label, hint: hint)
                .layoutPriority(0)

            Spacer(minLength: 8)

            HStack(spacing: InspectorRowMetrics.trailingControlSpacing) {
                Text(isOn.wrappedValue ? valueOn : valueOff)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .lineLimit(1)
                    .frame(
                        minWidth: InspectorRowMetrics.trailingValueMinWidth,
                        alignment: .trailing
                    )

                Toggle(label, isOn: isOn)
                    .labelsHidden()
                    .tint(theme.currentTheme.chrome.accent)
                    .controlSize(.mini)
                    .fixedSize()
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: InspectorRowMetrics.height)
        .overlay(alignment: .bottom) {
            inspectorRowDivider()
        }
    }

    private enum ActionTone { case neutral, accent, warn }

    /// Navigation row — same 44pt chrome as actionRow but trails a
    /// chevron instead of "RUN". Use for rows that push to another
    /// surface (e.g. ConnectionCenter), not rows that fire an action.
    private func navRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center) {
                Text(label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            .frame(height: InspectorRowMetrics.height)
            .overlay(alignment: .bottom) {
                inspectorRowDivider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Opens \(label.lowercased())")
    }

    private func actionRow(_ label: String, tone: ActionTone, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .center) {
                Text(label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("RUN")
                    .talkieType(.chipLabel)
                    .foregroundStyle(actionColor(tone))
            }
            .frame(height: InspectorRowMetrics.height)
            .overlay(alignment: .bottom) {
                inspectorRowDivider()
            }
        }
        .buttonStyle(.plain)
    }

    private func actionColor(_ tone: ActionTone) -> Color {
        switch tone {
        case .neutral: return theme.colors.textTertiary
        case .accent: return theme.currentTheme.chrome.accent
        case .warn: return Color(red: 0.85, green: 0.46, blue: 0.34) // donor "recording" red-orange
        }
    }

    private func metricStrip(title: String, metrics: [(String, String)]) -> some View {
        // Metric strip conforms to the row chrome — full-width hairlines
        // top/bottom, channel-label section header with a full-width
        // hairline below it, cells separated by vertical 1pt rules
        // instead of bordered tiles. Visually it reads as a wider row
        // with multiple columns, not a foreign card.
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                ForEach(metrics.indices, id: \.self) { idx in
                    VStack(spacing: 4) {
                        Text(metrics[idx].0)
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                        Text(metrics[idx].1)
                            .talkieType(.instrumentReadoutSmall)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                    if idx < metrics.count - 1 {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(width: 1)
                            .padding(.vertical, 10)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Live data helpers

    private var bridgeStatusValue: String {
        guard bridgeManager.isPaired else { return "Not paired" }
        if let name = bridgeManager.pairedMacDisplayName {
            return "\(bridgeManager.status.rawValue) · \(name)"
        }
        return bridgeManager.status.rawValue
    }

    private var bridgeStatusHint: String {
        var parts: [String] = []
        if let hostname = bridgeManager.pairedHostname { parts.append(hostname) }
        if let port = bridgeManager.pairedPort { parts.append(String(port)) }
        if let last = bridgeManager.lastSuccessfulContactAt {
            parts.append(last.formatted(.relative(presentation: .named)))
        }
        return parts.isEmpty ? bridgeManager.errorMessage ?? bridgeManager.activeRouteDescription : parts.joined(separator: " · ")
    }

    private var isNativelySignedIn: Bool {
        UserDefaults.standard.bool(forKey: SignInStore.signedInDefaultsKey)
    }

    private var nativeAccountValue: String {
        isNativelySignedIn ? "Signed in" : "Not signed in"
    }

    private var companionShortcutHint: String {
        if bridgeManager.isPaired {
            let macName = bridgeManager.pairedMacDisplayName ?? bridgeManager.pairedHostname ?? "your Mac"
            return "Let \(macName) switch this phone into Deck mode"
        }

        return "Pair a Mac first; manual Deck still works"
    }

    private var speechProviderHint: String {
        switch appSettings.ttsProvider {
        case "openai":
            return "Can reuse AI keys"
        case "elevenlabs":
            return "Direct key for phone speech"
        default:
            return "Mac Bridge Kokoro"
        }
    }

    private var speechRouteHint: String {
        if appSettings.ttsMode == "direct" {
            return reusableSpeechCredential == nil
                ? "Uses key saved here"
                : "Uses saved AI credential"
        }

        return "Paired Mac fallback"
    }

    private var shouldShowSpeechCredentialRow: Bool {
        appSettings.ttsProvider != "local" && appSettings.ttsMode == "direct"
    }

    private var reusableSpeechCredential: ComposeBorrowedProvider? {
        _ = aiCredentials.setProviderIDs
        guard appSettings.ttsProvider == "openai" else { return nil }
        if let cachedProvider = ComposeProviderCredentialStore.shared.load(providerId: "openai") {
            return cachedProvider
        }
        guard let apiKey = AICredentialStore.shared.key(for: "openai") else { return nil }
        return ComposeBorrowedProvider(
            providerId: "openai",
            providerName: TalkieAIProviderCredentialPayload.displayName(for: "openai"),
            modelId: TalkieAIProviderCredentialPayload.defaultModel(for: "openai"),
            apiKey: apiKey,
            assistantPrompt: TalkieAIProviderCredentialPayload.defaultAssistantPrompt,
            fallbackReason: "Using the API key saved in AI Keys on this iPhone."
        )
    }

    private var speechCredentialSummary: String {
        if appSettings.ttsProvider == "elevenlabs" {
            return "Direct ElevenLabs speech"
        }

        return "Or save OpenAI in AI keys"
    }

    private var speechVoicePlaceholder: String {
        switch appSettings.ttsProvider {
        case "elevenlabs":
            return "Voice ID"
        case "local":
            return "af_heart"
        default:
            return "echo"
        }
    }

    private var speechVoiceSummary: String {
        switch appSettings.ttsProvider {
        case "elevenlabs":
            return "ElevenLabs voice ID"
        case "local":
            return "Kokoro voice on Mac"
        default:
            return "OpenAI voice name"
        }
    }

    private var aiVoiceRouteLabel: String {
        switch appSettings.aiVoiceOutputRoute {
        case "watch":
            return "Watch"
        case "silent":
            return "Silent"
        default:
            return "iPhone"
        }
    }

    private func normalizeSpeechSettings(for provider: String) {
        switch provider {
        case "local":
            appSettings.ttsMode = "bridge"
            if appSettings.ttsVoice.isEmpty || appSettings.ttsVoice == "echo" {
                appSettings.ttsVoice = "af_heart"
            }
        case "openai":
            if appSettings.ttsVoice.isEmpty || appSettings.ttsVoice == "af_heart" {
                appSettings.ttsVoice = "echo"
            }
        case "elevenlabs":
            if appSettings.ttsVoice == "echo" || appSettings.ttsVoice == "af_heart" {
                appSettings.ttsVoice = ""
            }
        default:
            break
        }
    }

    private var iosChannel: String {
        (Bundle.main.object(forInfoDictionaryKey: "TALKIE_IOS_CHANNEL") as? String) ?? "—"
    }

    private func resetAuthState() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "to.talkie.native-apple-auth"
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: SignInStore.signedInDefaultsKey)
        AppLogger.app.info("[Auth] Native Apple sign-in state reset from SettingsNext")
    }

    private func dumpSharedStore() {
        let configuration = TalkieAppConfigurationStore.shared.configuration
        if let data = try? JSONEncoder().encode(configuration),
           let dump = String(data: data, encoding: .utf8) {
            AppLogger.app.info("SettingsNext shared store dump", detail: dump)
        } else {
            AppLogger.app.warning("SettingsNext shared store dump failed")
        }
    }

}

// MARK: - Bundle convenience for ABOUT panel

private extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    var buildNumber: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
}
