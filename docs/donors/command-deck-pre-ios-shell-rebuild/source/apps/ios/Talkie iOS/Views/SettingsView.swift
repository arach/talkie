//
//  SettingsView.swift
//  Talkie iOS
//
//  Settings view with theme selection
//

import SwiftUI
import UIKit
import TalkieMobileKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var logStore = LogStore.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var showingAllLogs = false
    @State private var showingAIQRScanner = false
    @State private var aiCredentialRefreshID = UUID()
    @State private var isImportingMacAICredentials = false
    @State private var macAICredentialImportMessage: String?
    @State private var macAICredentialImportError: String?
    @State private var showLocationPrivacy = false
    @State private var showSignIn = false
    private var bridgeManager = BridgeManager.shared

    // App info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.talkie.ios"
    }

    private var deviceName: String {
        UIDevice.current.name
    }

    private var iosVersion: String {
        UIDevice.current.systemVersion
    }

    private var settingsRowDividerInset: CGFloat {
        Spacing.sm + 28 + 12
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    ScrollViewReader { proxy in
                    VStack(spacing: Spacing.lg) {
                        settingsQuickNav(proxy: proxy)
                            .id("__top__")
                            .padding(.top, 4)

                        // MARK: - Account
                        settingsSection("ACCOUNT") {
                            VStack(spacing: 0) {
                                if AuthManager.shared.isSignedIn {
                                    HStack(spacing: 12) {
                                        SettingsLeadingIcon(
                                            systemName: "person.crop.circle.fill",
                                            color: .active,
                                            fontSize: 24,
                                            weight: .light
                                        )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AuthManager.shared.user?.email ?? "Signed In")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor(.textPrimary)

                                            HStack(spacing: 6) {
                                                Text((AuthManager.shared.user?.plan.rawValue ?? "free").uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .tracking(1)
                                                    .foregroundColor(.active)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.active.opacity(0.1))
                                                    .cornerRadius(4)
                                            }
                                        }

                                        Spacer()

                                        Button {
                                            AuthManager.shared.signOut()
                                        } label: {
                                            Text("Sign Out")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.recording)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.recording.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    }
                                    .padding(Spacing.sm)
                                } else {
                                    Button {
                                        showSignIn = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            SettingsLeadingIcon(systemName: "person.crop.circle", color: .active)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Sign In or Create Account")
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundColor(.textPrimary)

                                                Text("Sync memos between devices")
                                                    .font(.system(size: 11, weight: .light))
                                                    .foregroundColor(.textTertiary)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .light))
                                                .foregroundColor(.textTertiary.opacity(0.5))
                                        }
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 10)
                                    }
                                }

                                Divider().background(Color.borderPrimary)

                                NavigationLink(destination: MacAvailabilityCoachView()) {
                                    settingsRow(
                                        icon: "macbook.and.iphone",
                                        iconColor: .active,
                                        title: "Macs",
                                        subtitle: "Direct pairing and terminal access",
                                        badge: { MacAvailabilityBadge() }
                                    )
                                }
                            }
                        }

                        // MARK: - Appearance (inline)
                        settingsSection("APPEARANCE") {
                            AppearanceSettingsRow(themeManager: themeManager)
                        }

                        // MARK: - Keyboard & Dictation Engine
                        settingsSection("KEYBOARD & DICTATION") {
                            VStack(spacing: 0) {
                                NavigationLink(destination: KeyboardSettingsView()) {
                                    settingsRow(
                                        icon: "keyboard",
                                        iconColor: .active,
                                        title: "Keyboard",
                                        subtitle: "Voice dictation in any app",
                                        badge: { KeyboardStatusBadge() }
                                    )
                                }

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                NavigationLink(destination: DictationEngineSettingsDetail()) {
                                    settingsRow(
                                        icon: "waveform",
                                        iconColor: .active,
                                        title: "Engine",
                                        subtitle: engineSummary
                                    )
                                }
                            }
                        }

                        settingsSection("COMPANION") {
                            HStack(spacing: Spacing.sm) {
                                SettingsLeadingIcon(systemName: "rectangle.grid.2x2", color: .active)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Open Command Deck")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.textPrimary)

                                    Text(companionSubtitle)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                Toggle("", isOn: $appSettings.followComputerShortcutMode)
                                    .labelsHidden()
                                    .tint(.active)
                            }
                            .padding(Spacing.sm)
                        }

                        settingsSection("AI & VOICE") {
                            VStack(spacing: 0) {
                                NavigationLink(destination: AISettingsDetail(refreshID: $aiCredentialRefreshID)) {
                                    settingsRow(
                                        icon: "sparkles",
                                        iconColor: .cyan,
                                        title: "AI",
                                        subtitle: aiCapabilitySummary,
                                        badge: { SettingsStatusBadge(isReady: aiCredentialProvider != nil) }
                                    )
                                }
                                .id(aiCredentialRefreshID)

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                NavigationLink(destination: AIVoiceSettingsDetail()) {
                                    settingsRow(
                                        icon: "speaker.wave.2.fill",
                                        iconColor: .orange,
                                        title: "AI Voice",
                                        subtitle: aiVoiceCapabilitySummary,
                                        badge: { SettingsStatusBadge(isReady: isAIVoiceReady) }
                                    )
                                }

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                HStack(spacing: Spacing.sm) {
                                    SettingsLeadingIcon(systemName: "quote.bubble", color: .active)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Speak Replies")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.textPrimary)

                                        Text(aiVoiceRouteSummary)
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { appSettings.aiVoiceOutputRoute != "silent" },
                                        set: { appSettings.aiVoiceOutputRoute = $0 ? "phone" : "silent" }
                                    ))
                                    .labelsHidden()
                                    .tint(.active)
                                }
                                .padding(Spacing.sm)

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                NavigationLink(destination: MacAvailabilityCoachView()) {
                                    settingsRow(
                                        icon: "macmini",
                                        iconColor: bridgeManager.isPaired ? .green : .textTertiary,
                                        title: "Mac mini",
                                        subtitle: macMiniSummary,
                                        badge: { BridgeStatusBadge() }
                                    )
                                }

                                if bridgeManager.isPaired {
                                    Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                    Button {
                                        importAICredentialsFromPairedMac()
                                    } label: {
                                        settingsRow(
                                            icon: "lock.rectangle.stack",
                                            iconColor: .cyan,
                                            title: isImportingMacAICredentials ? "Importing from Mac..." : "Import from Mac",
                                            subtitle: macAICredentialImportSubtitle,
                                            badge: {
                                                if isImportingMacAICredentials {
                                                    ProgressView()
                                                        .scaleEffect(0.75)
                                                        .tint(.cyan)
                                                } else if macAICredentialImportMessage != nil {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 16, weight: .medium))
                                                        .foregroundColor(.green)
                                                } else if macAICredentialImportError != nil {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.orange)
                                                } else {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(.cyan)
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isImportingMacAICredentials)

                                    if shouldShowMacAICredentialImportDiagnostics {
                                        Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                        macAICredentialImportDiagnosticsCard
                                    } else {
                                        Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                        Button {
                                            copyMacAICredentialImportDiagnostics()
                                        } label: {
                                            settingsRow(
                                                icon: "stethoscope",
                                                iconColor: .textSecondary,
                                                title: "Diagnostics",
                                                subtitle: "Copy AI and Mac connection status"
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if !bridgeManager.isPaired {
                                    Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                    Button {
                                        copyMacAICredentialImportDiagnostics()
                                    } label: {
                                        settingsRow(
                                            icon: "stethoscope",
                                            iconColor: .textSecondary,
                                            title: "Diagnostics",
                                            subtitle: "Copy AI and Mac connection status"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // MARK: - Recording
                        settingsSection("RECORDING") {
                            VStack(spacing: 0) {
                                HStack(spacing: Spacing.sm) {
                                    SettingsLeadingIcon(systemName: "location", color: .active)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: Spacing.xs) {
                                            Text("Tag Location")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor(.textPrimary)

                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showLocationPrivacy.toggle()
                                                }
                                            } label: {
                                                Image(systemName: "lock.shield")
                                                    .font(.system(size: 10, weight: .light))
                                                    .foregroundColor(.textTertiary)
                                            }
                                        }

                                        Text("Attach coordinates to voice memos")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(.textSecondary)
                                    }

                                    Spacer()

                                    Toggle("", isOn: $appSettings.tagLocationEnabled)
                                        .labelsHidden()
                                        .tint(.active)
                                        .onChange(of: appSettings.tagLocationEnabled) { _, enabled in
                                            if enabled {
                                                LocationService.shared.requestPermission()
                                            }
                                        }
                                }
                                .padding(Spacing.sm)

                                if showLocationPrivacy {
                                    Text("Location is stored on-device and in your private iCloud. It is never sent to Talkie or any third party.")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.textTertiary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.bottom, Spacing.sm)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }

                        #if DEBUG
                        if FeatureFlags.showConnectionCenter {
                            settingsSection("REMOTE ACCESS") {
                                VStack(spacing: 0) {
                                    NavigationLink(destination: SSHTerminalView()) {
                                        settingsRow(
                                            icon: "rectangle.and.terminal",
                                            iconColor: .active,
                                            title: "SSH Terminal",
                                            subtitle: sshTerminalSummary
                                        )
                                    }
                                    .accessibilityIdentifier("settings.sshTerminal")

                                    Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                    NavigationLink(destination: ConnectionCenterView()) {
                                        settingsRow(
                                            icon: "point.3.connected.trianglepath.dotted",
                                            iconColor: .active,
                                            title: "Connection Center",
                                            subtitle: "Bridge and device connections"
                                        )
                                    }
                                    .accessibilityIdentifier("settings.connectionCenter")
                                }
                            }
                        }
                        #endif

                        // MARK: - About
                        settingsSection("ABOUT") {
                            VStack(spacing: 0) {
                                DebugInfoRow(label: "Version", value: "\(appVersion) (\(buildNumber))")
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "Device", value: deviceName)
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "iOS", value: iosVersion)
                            }
                        }

                        // MARK: - Logs
                        settingsSection("LOGS") {
                            Button(action: { showingAllLogs = true }) {
                                settingsRow(
                                    icon: "list.bullet.rectangle.portrait",
                                    iconColor: .active,
                                    title: "Logs",
                                    subtitle: "System, sync, bridge, and terminal activity",
                                    badge: {
                                        if !logStore.importantEntries.isEmpty {
                                            LogCountBadge(count: logStore.importantEntries.count)
                                        }
                                    }
                                )
                            }
                        }

                        // MARK: - Dev Tools (DEBUG only)
                        #if DEBUG
                        settingsSection("DEV TOOLS") {
                            VStack(spacing: 0) {
                                Button(action: {
                                    appSettings.hasSeenOnboarding = false
                                    dismiss()
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(300))
                                        NotificationCenter.default.post(name: talkieApp.showOnboardingNotification, object: nil)
                                    }
                                }) {
                                    settingsRow(
                                        icon: "arrow.counterclockwise",
                                        iconColor: .textSecondary,
                                        title: "Show Onboarding",
                                        subtitle: nil
                                    )
                                }

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                Button(action: {
                                    appSettings.hasSeenResumeTooltip = false
                                }) {
                                    settingsRow(
                                        icon: "text.bubble",
                                        iconColor: .textSecondary,
                                        title: "Reset Resume Tooltip",
                                        subtitle: nil
                                    )
                                }

                                Divider().background(Color.borderPrimary).padding(.leading, settingsRowDividerInset)

                                Button(action: {
                                    AuthManager.shared.signOut()
                                }) {
                                    settingsRow(
                                        icon: "person.slash",
                                        iconColor: .recording,
                                        title: "Reset Auth State",
                                        subtitle: "Sign out and clear token"
                                    )
                                }
                            }
                        }
                        #endif

                        Spacer(minLength: 40)
                    }
                    .padding(.top, Spacing.xs)
                    } // ScrollViewReader
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.active)
                }
            }
        }
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingAllLogs) {
            LogViewerSheet()
        }
        .sheet(isPresented: $showingAIQRScanner, onDismiss: {
            aiCredentialRefreshID = UUID()
        }) {
            QRScannerView()
        }
    }

    // MARK: - Settings Helpers

    private var engineSummary: String {
        let pref = TranscriptionService.shared.keyboardEnginePreference
        switch pref {
        case .auto: return "Auto"
        case .appleSpeech: return "Apple Speech"
        case .parakeet: return "Parakeet"
        }
    }

    private var sshTerminalSummary: String {
        let savedHosts = SSHTerminalSavedHostStore().load()

        guard let mostRecentHost = savedHosts.first else {
            return "Direct shell access over SSH"
        }

        if savedHosts.count == 1 {
            return mostRecentHost.title
        }

        return "\(savedHosts.count) saved hosts"
    }

    private var aiCredentialProvider: ComposeBorrowedProvider? {
        _ = aiCredentialRefreshID
        return ComposeProviderCredentialStore.shared.load(
            providerId: appSettings.composeDirectProviderId,
            modelId: appSettings.composeDirectModelId
        )
    }

    private var aiCredentialSummary: String {
        guard let provider = aiCredentialProvider else {
            return "Not configured"
        }

        return "\(provider.providerName) • \(provider.modelId)"
    }

    private var aiCapabilitySummary: String {
        aiCredentialProvider == nil ? "Needs setup" : "Ready"
    }

    private var aiVoiceCapabilitySummary: String {
        let state = isAIVoiceReady ? "Ready" : "Needs setup"
        return "\(state) • \(aiVoiceRouteLabel)"
    }

    private var isAIVoiceReady: Bool {
        TTSService.canSynthesizeConfiguredAudio(settings: appSettings)
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

    private var aiVoiceRouteSummary: String {
        switch appSettings.aiVoiceOutputRoute {
        case "watch":
            return "Short AI replies are routed to the paired Watch when available."
        case "silent":
            return "AI replies stay visual. Speech generation remains available from memo and capture views."
        default:
            return "Short AI replies speak on this iPhone using the speech provider below."
        }
    }

    private var speechProviderSummary: String {
        switch appSettings.ttsProvider {
        case "openai":
            return "OpenAI speech can reuse the saved AI provider credential."
        case "elevenlabs":
            return "Third-party speech, direct key required for phone playback."
        default:
            return "Mac Bridge Kokoro speech, no phone API key required."
        }
    }

    private var speechRouteSummary: String {
        if appSettings.ttsMode == "direct" {
            if reusableSpeechCredential != nil {
                return "Direct on iPhone using the saved provider credential."
            }
            return "Direct on iPhone with a provider key saved on this device."
        }

        return "Via paired Mac when Bridge is connected."
    }

    private var reusableSpeechCredential: ComposeBorrowedProvider? {
        _ = aiCredentialRefreshID
        guard appSettings.ttsProvider == "openai" else { return nil }
        return ComposeProviderCredentialStore.shared.load(providerId: "openai")
    }

    private var shouldShowSpeechCredentialRow: Bool {
        appSettings.ttsMode == "direct"
    }

    private var speechCredentialSummary: String {
        if let reusableSpeechCredential {
            return "Using saved \(reusableSpeechCredential.providerName) key for speech and AI."
        }

        if appSettings.ttsProvider == "elevenlabs" {
            return "Paste an ElevenLabs API key for direct phone speech."
        }

        return "Paste an OpenAI key, or import it once from your paired Mac."
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
            return "Kokoro voice on the Mac"
        default:
            return "OpenAI voice name"
        }
    }

    private var macAICredentialImportSubtitle: String {
        if let message = macAICredentialImportMessage {
            return message
        }

        if let error = macAICredentialImportError {
            return error
        }

        if isImportingMacAICredentials {
            return "Decrypting and validating the paired Mac provider key"
        }

        if bridgeManager.status == .connected {
            return "Copy the Mac provider key over the encrypted bridge"
        }

        return "Reconnects to your Mac, then copies the encrypted provider key"
    }

    private var shouldShowMacAICredentialImportDiagnostics: Bool {
        isImportingMacAICredentials ||
        macAICredentialImportMessage != nil ||
        macAICredentialImportError != nil ||
        !bridgeManager.credentialImportEvents.isEmpty ||
        bridgeManager.awaitingPairingApproval
    }

    private var macAICredentialImportDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: macAICredentialImportError == nil ? "lock.shield" : "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(macAICredentialImportError == nil ? Color.cyan : Color.orange)

                Text("Credential Import")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                Button {
                    copyMacAICredentialImportDiagnostics()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy credential import diagnostics")
            }

            VStack(alignment: .leading, spacing: 7) {
                credentialDiagnosticLine(
                    icon: bridgeManager.status.icon,
                    color: bridgeManager.status.color,
                    text: "Bridge: \(bridgeManager.status.rawValue)"
                )

                if bridgeManager.awaitingPairingApproval {
                    credentialDiagnosticLine(
                        icon: "person.crop.circle.badge.checkmark",
                        color: .orange,
                        text: "Approval needed on Mac"
                    )
                }

                if let error = bridgeManager.errorMessage, !error.isEmpty {
                    credentialDiagnosticLine(
                        icon: "exclamationmark.circle",
                        color: .orange,
                        text: error
                    )
                }

                ForEach(bridgeManager.credentialImportEvents) { event in
                    credentialDiagnosticLine(
                        icon: credentialImportEventIcon(for: event.level),
                        color: credentialImportEventColor(for: event.level),
                        text: event.message
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 12)
    }

    private func credentialDiagnosticLine(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credentialImportEventIcon(
        for level: BridgeManager.CredentialImportEvent.Level
    ) -> String {
        switch level {
        case .info:
            return "circle"
        case .warning:
            return "exclamationmark.circle"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private func credentialImportEventColor(
        for level: BridgeManager.CredentialImportEvent.Level
    ) -> Color {
        switch level {
        case .info:
            return .textTertiary
        case .warning:
            return .orange
        case .success:
            return .green
        }
    }

    private var companionSubtitle: String {
        if bridgeManager.isPaired {
            let macName = bridgeManager.pairedMacName ?? bridgeManager.pairedHostname ?? "your Mac"
            return "Let \(macName) switch this phone into Command Deck automatically. The manual deck button still works."
        }

        return "Pair with a Mac first to allow automatic Command Deck handoff. The manual deck button still works."
    }

    private var macMiniSummary: String {
        guard bridgeManager.isPaired else {
            return "Pair a Mac to import keys and run local AI Voice"
        }

        let name = bridgeManager.pairedMacDisplayName ?? "Paired Mac"
        if bridgeManager.status == .connected {
            return "\(name) connected"
        }

        return "\(name) paired • \(bridgeManager.status.rawValue)"
    }

    private func importAICredentialsFromPairedMac() {
        guard !isImportingMacAICredentials else { return }

        isImportingMacAICredentials = true
        macAICredentialImportMessage = nil
        macAICredentialImportError = nil

        Task { @MainActor in
            do {
                let result = try await bridgeManager.importAIProviderCredentialsFromMac()
                appSettings.composeDirectProviderId = result.providerId
                appSettings.composeDirectModelId = result.modelId
                aiCredentialRefreshID = UUID()
                macAICredentialImportMessage = "Saved \(result.providerName) • \(result.modelId)"
            } catch BridgeError.httpError(401) {
                macAICredentialImportError = "The Mac rejected this iPhone's bridge signature. Approve the pending pairing on your Mac, then try again."
            } catch {
                macAICredentialImportError = error.localizedDescription
            }

            isImportingMacAICredentials = false
        }
    }

    private func copyMacAICredentialImportDiagnostics() {
        let portDescription = bridgeManager.pairedPort.map(String.init) ?? "-"
        var lines: [String] = [
            "AI credential import diagnostics",
            "Bridge status: \(bridgeManager.status.rawValue)",
            "Awaiting approval: \(bridgeManager.awaitingPairingApproval ? "yes" : "no")",
            "Paired Mac: \(bridgeManager.pairedMacDisplayName ?? "unknown")",
            "Host: \(bridgeManager.pairedHostname ?? "unknown"):\(portDescription)",
        ]

        if let error = bridgeManager.errorMessage, !error.isEmpty {
            lines.append("Bridge error: \(error)")
        }

        if let message = macAICredentialImportMessage {
            lines.append("Result: \(message)")
        }

        if let error = macAICredentialImportError {
            lines.append("Import error: \(error)")
        }

        lines.append(contentsOf: bridgeManager.credentialImportEvents.map { event in
            "[\(event.level)] \(event.message)"
        })

        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: title)
                .padding(.horizontal, Spacing.md)

            content()
                .background(themeManager.colors.cardBackground)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(themeManager.chrome.edgeFaint, lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
        }
        .id(title)
    }

    private static let quickNavItems: [(icon: String, label: String, section: String)] = [
        ("sparkles",             "AI",         "AI & VOICE"),
        ("ipad.and.iphone",      "Companion",  "COMPANION"),
        ("keyboard",             "Dictation",  "KEYBOARD & DICTATION"),
        ("waveform",             "Recording",  "RECORDING"),
        ("paintpalette",         "Appearance", "APPEARANCE"),
        ("person.crop.circle",   "Account",    "ACCOUNT"),
    ]

    private func settingsQuickNav(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickNavItems, id: \.section) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(item.section, anchor: .top)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(item.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.surfaceSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.textTertiary.opacity(0.18), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        settingsRow(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle) { EmptyView() }
    }

    private func settingsRow<Badge: View>(icon: String, iconColor: Color, title: String, subtitle: String?, @ViewBuilder badge: () -> Badge) -> some View {
        HStack(spacing: 12) {
            SettingsLeadingIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            badge()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 10)
    }
}

private struct SettingsLeadingIcon: View {
    let systemName: String
    let color: Color
    var fontSize: CGFloat = 14
    var weight: Font.Weight = .light

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: weight))
            .foregroundColor(color)
            .frame(width: 28, height: 28)
    }
}

private struct SettingsStatusBadge: View {
    let isReady: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isReady ? Color.success : Color.orange)
                .frame(width: 6, height: 6)
            Text(isReady ? "Ready" : "Needs setup")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - AI Settings Detail

private struct AISettingsDetail: View {
    @State private var appSettings = TalkieAppSettings.shared
    @Binding var refreshID: UUID
    @State private var showingAIQRScanner = false
    @State private var isTestingAI = false
    @State private var testMessage: String?

    private var provider: ComposeBorrowedProvider? {
        _ = refreshID
        return ComposeProviderCredentialStore.shared.load(
            providerId: appSettings.composeDirectProviderId,
            modelId: appSettings.composeDirectModelId
        )
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SettingsDetailSection("AI Provider") {
                        detailRow(
                            icon: "sparkles",
                            iconColor: .cyan,
                            title: "Provider",
                            subtitle: provider?.providerName ?? "Needs setup"
                        )

                        Divider().background(Color.borderPrimary)

                        detailRow(
                            icon: "cpu",
                            iconColor: .active,
                            title: "Model",
                            subtitle: provider?.modelId ?? appSettings.composeDirectModelId
                        )

                        Divider().background(Color.borderPrimary)

                        detailRow(
                            icon: "iphone",
                            iconColor: .green,
                            title: "Runs on",
                            subtitle: provider == nil ? "Set up credentials to run AI on this iPhone" : "This iPhone"
                        )

                        Divider().background(Color.borderPrimary)

                        detailRow(
                            icon: provider == nil ? "key.fill" : "checkmark.seal.fill",
                            iconColor: provider == nil ? .yellow : .green,
                            title: "Credentials",
                            subtitle: provider == nil ? "Import from Mac or scan setup QR" : "Saved on this iPhone"
                        )
                    }

                    SettingsDetailSection("Setup") {
                        Button {
                            showingAIQRScanner = true
                        } label: {
                            detailRow(
                                icon: "qrcode.viewfinder",
                                iconColor: .active,
                                title: "Scan Setup QR",
                                subtitle: "Run npx @talkie/ai qr on your Mac"
                            )
                        }
                        .buttonStyle(.plain)

                        if provider != nil {
                            Divider().background(Color.borderPrimary)

                            Button(role: .destructive) {
                                ComposeProviderCredentialStore.shared.deleteAll()
                                appSettings.composeDirectProviderId = "openai"
                                appSettings.composeDirectModelId = ""
                                refreshID = UUID()
                                testMessage = nil
                            } label: {
                                detailRow(
                                    icon: "trash",
                                    iconColor: .red,
                                    title: "Clear Credentials",
                                    subtitle: "Remove phone-stored provider keys"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SettingsDetailSection("Test") {
                        Button {
                            testAI()
                        } label: {
                            HStack(spacing: 12) {
                                SettingsLeadingIcon(systemName: "checkmark.circle", color: .cyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isTestingAI ? "Testing AI..." : "Test AI")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.textPrimary)

                                    Text(testMessage ?? "Send a short check with the saved provider")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                if isTestingAI {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .tint(.cyan)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(provider == nil || isTestingAI)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAIQRScanner, onDismiss: {
            refreshID = UUID()
        }) {
            QRScannerView()
        }
    }

    private func testAI() {
        guard let provider, !isTestingAI else { return }

        isTestingAI = true
        testMessage = nil

        Task { @MainActor in
            do {
                _ = try await CaptureAICommandService.shared.run(
                    context: "Talkie settings connection test.",
                    instruction: "Reply with exactly: Ready.",
                    title: "Settings AI Test",
                    sourceDescription: "Settings",
                    provider: provider
                )
                testMessage = "Ready"
            } catch {
                testMessage = error.localizedDescription
            }

            isTestingAI = false
        }
    }

    private func detailRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            SettingsLeadingIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(title == "Clear Credentials" ? .red : .textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 10)
    }
}

// MARK: - AI Voice Settings Detail

private struct AIVoiceSettingsDetail: View {
    @State private var appSettings = TalkieAppSettings.shared
    @State private var isTestingVoice = false
    @State private var testMessage: String?

    private var reusableSpeechCredential: ComposeBorrowedProvider? {
        guard appSettings.ttsProvider == "openai" else { return nil }
        return TalkieAIProviderResolver.shared.provider(providerId: "openai")
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SettingsDetailSection("AI Voice") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailHeader(icon: "waveform", color: .purple, title: "Provider")

                            Text(aiVoiceProviderSummary)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 40)

                            Picker("", selection: $appSettings.ttsProvider) {
                                Text("Mac").tag("local")
                                Text("OpenAI").tag("openai")
                                Text("ElevenLabs").tag("elevenlabs")
                            }
                            .pickerStyle(.segmented)
                            .padding(.leading, 40)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 10)

                        Divider().background(Color.borderPrimary)

                        HStack {
                            SettingsLeadingIcon(systemName: "person.wave.2", color: .purple)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voice")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textPrimary)

                                Text(aiVoiceNameSummary)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.textSecondary)
                            }

                            Spacer()

                            TextField(aiVoicePlaceholder, text: $appSettings.ttsVoice)
                                .font(.system(size: 14))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 140)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 10)

                        Divider().background(Color.borderPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            detailHeader(icon: "arrow.triangle.2.circlepath", color: .blue, title: "Runs on")

                            Text(aiVoiceRunsOnSummary)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 40)

                            if appSettings.ttsProvider != "local" {
                                Picker("", selection: $appSettings.ttsMode) {
                                    Text("Via Mac").tag("bridge")
                                    Text("Direct").tag("direct")
                                }
                                .pickerStyle(.segmented)
                                .padding(.leading, 40)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 10)

                        if shouldShowCredentialRow {
                            Divider().background(Color.borderPrimary)

                            VStack(alignment: .leading, spacing: 8) {
                                detailHeader(
                                    icon: reusableSpeechCredential == nil ? "key.fill" : "checkmark.seal.fill",
                                    color: reusableSpeechCredential == nil ? .yellow : .green,
                                    title: "Credentials"
                                )

                                Text(aiVoiceCredentialSummary)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 40)

                                if reusableSpeechCredential == nil {
                                    SecureField("Paste key", text: $appSettings.ttsApiKey)
                                        .font(.system(size: 14, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .padding(.leading, 40)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 10)
                        }
                    }

                    SettingsDetailSection("Replies") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: Spacing.sm) {
                                SettingsLeadingIcon(systemName: "quote.bubble", color: .active)

                                Text("Speak Replies")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textPrimary)

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { appSettings.aiVoiceOutputRoute != "silent" },
                                    set: { appSettings.aiVoiceOutputRoute = $0 ? "phone" : "silent" }
                                ))
                                .labelsHidden()
                                .tint(.active)
                            }

                            Picker("", selection: $appSettings.aiVoiceOutputRoute) {
                                Text("iPhone").tag("phone")
                                Text("Watch").tag("watch")
                                Text("Silent").tag("silent")
                            }
                            .pickerStyle(.segmented)
                            .padding(.leading, 40)

                            Text(aiVoiceRouteSummary)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 40)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 10)
                    }

                    SettingsDetailSection("Test") {
                        Button {
                            testVoice()
                        } label: {
                            HStack(spacing: 12) {
                                SettingsLeadingIcon(systemName: "play.circle", color: .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isTestingVoice ? "Testing AI Voice..." : "Test AI Voice")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.textPrimary)

                                    Text(testMessage ?? "Generate a short spoken reply")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                if isTestingVoice {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .tint(.orange)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!TTSService.canSynthesizeConfiguredAudio(settings: appSettings) || isTestingVoice)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("AI Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var aiVoiceProviderSummary: String {
        switch appSettings.ttsProvider {
        case "openai":
            return "OpenAI speech can reuse the saved AI credential."
        case "elevenlabs":
            return "Third-party speech, direct key required for phone playback."
        default:
            return "Mac Bridge Kokoro speech, no phone API key required."
        }
    }

    private var aiVoiceRunsOnSummary: String {
        if appSettings.ttsProvider == "local" {
            return "Paired Mac through Bridge."
        }

        if appSettings.ttsMode == "direct" {
            if reusableSpeechCredential != nil {
                return "This iPhone using the saved AI credential."
            }
            return "This iPhone with a provider key saved here."
        }

        return "Paired Mac when Bridge is connected."
    }

    private var shouldShowCredentialRow: Bool {
        appSettings.ttsMode == "direct"
    }

    private var aiVoiceCredentialSummary: String {
        if let reusableSpeechCredential {
            return "Use AI key: saved \(reusableSpeechCredential.providerName) credential."
        }

        if appSettings.ttsProvider == "elevenlabs" {
            return "Paste an ElevenLabs API key for direct AI Voice playback."
        }

        return "Paste an OpenAI key, or import it once from your paired Mac."
    }

    private var aiVoicePlaceholder: String {
        switch appSettings.ttsProvider {
        case "elevenlabs":
            return "Voice ID"
        case "local":
            return "af_heart"
        default:
            return "echo"
        }
    }

    private var aiVoiceNameSummary: String {
        switch appSettings.ttsProvider {
        case "elevenlabs":
            return "ElevenLabs voice ID"
        case "local":
            return "Kokoro voice on the Mac"
        default:
            return "OpenAI voice name"
        }
    }

    private var aiVoiceRouteSummary: String {
        switch appSettings.aiVoiceOutputRoute {
        case "watch":
            return "Short AI replies are routed to the paired Watch when available."
        case "silent":
            return "AI replies stay visual."
        default:
            return "Short AI replies speak on this iPhone."
        }
    }

    private func testVoice() {
        guard !isTestingVoice else { return }

        isTestingVoice = true
        testMessage = nil

        Task { @MainActor in
            do {
                let audioData = try await TTSService.synthesizeConfigured(
                    text: "AI Voice is ready.",
                    settings: appSettings
                )
                await WalkieFX.shared.playVoiceAudio(
                    data: audioData,
                    playbackRate: Float(appSettings.ttsPlaybackRate)
                )
                testMessage = "Ready"
            } catch {
                testMessage = error.localizedDescription
            }

            isTestingVoice = false
        }
    }

    private func detailHeader(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: Spacing.sm) {
            SettingsLeadingIcon(systemName: icon, color: color)

            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.textPrimary)

            Spacer()
        }
    }
}

private struct SettingsDetailSection<Content: View>: View {
    let title: String
    let content: Content

    @ObservedObject private var theme = ThemeManager.shared

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: title)
                .padding(.horizontal, Spacing.md)

            content
                .background(theme.colors.cardBackground)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(theme.chrome.edgeFaint, lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
        }
    }
}

private struct AppearanceSettingsRow: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsLeadingIcon(systemName: "circle.lefthalf.filled", color: .active)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textPrimary)

                        Text("\(themeManager.appearanceMode.displayName) • \(themeManager.currentTheme.displayName)")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        ForEach(AppearanceMode.allCases) { mode in
                            appearanceModeSummaryPill(mode)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.textTertiary.opacity(0.7))
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.borderPrimary)

                VStack(spacing: 0) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            AppearanceModeButton(
                                mode: mode,
                                isSelected: themeManager.appearanceMode == mode,
                                onSelect: { themeManager.appearanceMode = mode }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, 6)

                    Divider().background(Color.borderPrimary)

                    ForEach(AppTheme.allCases) { theme in
                        if theme != AppTheme.allCases.first {
                            Divider().background(Color.borderPrimary)
                        }
                        ThemeRow(
                            theme: theme,
                            isSelected: themeManager.currentTheme == theme,
                            onSelect: {
                                themeManager.currentTheme = theme
                            }
                        )
                    }

                    Divider().background(Color.borderPrimary)

                    ThemePreview(theme: themeManager.currentTheme)
                        .padding(Spacing.sm)
                }
            }
        }
    }

    @ViewBuilder
    private func appearanceModeSummaryPill(_ mode: AppearanceMode) -> some View {
        Image(systemName: mode.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(themeManager.appearanceMode == mode ? .active : .textTertiary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(themeManager.appearanceMode == mode ? Color.active.opacity(0.12) : Color.surfacePrimary.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(themeManager.appearanceMode == mode ? Color.active.opacity(0.35) : Color.borderPrimary, lineWidth: 0.5)
            )
    }
}

private struct LogCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(min(count, 99))")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.recording)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.recording.opacity(0.12))
            .cornerRadius(6)
    }
}

// MARK: - Appearance Settings Detail

struct AppearanceSettingsDetail: View {
    @ObservedObject var themeManager = ThemeManager.shared

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Appearance mode
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TalkieEyebrow(text: "Mode")

                        HStack(spacing: Spacing.sm) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                AppearanceModeButton(
                                    mode: mode,
                                    isSelected: themeManager.appearanceMode == mode,
                                    onSelect: { themeManager.appearanceMode = mode }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                    // Theme list
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TalkieEyebrow(text: "Theme")
                            .padding(.horizontal, Spacing.md)

                        VStack(spacing: 0) {
                            ForEach(AppTheme.allCases) { theme in
                                if theme != AppTheme.allCases.first {
                                    Divider().background(Color.borderPrimary)
                                }
                                ThemeRow(
                                    theme: theme,
                                    isSelected: themeManager.currentTheme == theme,
                                    onSelect: { themeManager.currentTheme = theme }
                                )
                            }
                        }
                        .background(themeManager.colors.cardBackground)
                        .cornerRadius(CornerRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(themeManager.chrome.edgeFaint, lineWidth: 0.5)
                        )
                        .padding(.horizontal, Spacing.md)
                    }

                    // Theme preview
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TalkieEyebrow(text: "Preview", tint: .ink, showLeader: false)
                            .padding(.horizontal, Spacing.md)

                        ThemePreview(theme: themeManager.currentTheme)
                            .padding(.horizontal, Spacing.md)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Engine Settings Detail

struct DictationEngineSettingsDetail: View {
    @StateObject private var parakeetManager = ParakeetModelManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var selectedModel: ParakeetModel = TalkieAppSettings.shared.preferredParakeetModel
    @ObservedObject private var theme = ThemeManager.shared

    private var keyboardEngine: TranscriptionEnginePreference {
        get { appSettings.transcriptionKeyboardEngine }
        nonmutating set { appSettings.transcriptionKeyboardEngine = newValue }
    }

    private var memoEngine: TranscriptionEnginePreference {
        get { appSettings.transcriptionMemoEngine }
        nonmutating set { appSettings.transcriptionMemoEngine = newValue }
    }

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Engine choice
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TalkieEyebrow(text: "Engine")
                            .padding(.horizontal, Spacing.md)

                        VStack(spacing: 0) {
                            // Keyboard
                            HStack {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.active)
                                    .frame(width: 24)

                                Text("Keyboard")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textPrimary)

                                Spacer()

                                Picker("", selection: Binding(
                                    get: { keyboardEngine },
                                    set: { keyboardEngine = $0 }
                                )) {
                                    Text("Auto").tag(TranscriptionEnginePreference.auto)
                                    Text("Apple").tag(TranscriptionEnginePreference.appleSpeech)
                                    Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            .padding(Spacing.sm)

                            Divider().background(Color.borderPrimary)

                            // Memos
                            HStack {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.active)
                                    .frame(width: 24)

                                Text("Memos")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textPrimary)

                                Spacer()

                                Picker("", selection: Binding(
                                    get: { memoEngine },
                                    set: { memoEngine = $0 }
                                )) {
                                    Text("Auto").tag(TranscriptionEnginePreference.auto)
                                    Text("Apple").tag(TranscriptionEnginePreference.appleSpeech)
                                    Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            .padding(Spacing.sm)
                        }
                        .background(theme.colors.cardBackground)
                        .cornerRadius(CornerRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(theme.chrome.edgeFaint, lineWidth: 0.5)
                        )
                        .padding(.horizontal, Spacing.md)
                    }

                    // Model
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TalkieEyebrow(text: "Model")
                            .padding(.horizontal, Spacing.md)

                        VStack(spacing: 0) {
                            // Version
                            HStack {
                                Image(systemName: "brain")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.active)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Version")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.textPrimary)
                                    Text(selectedModel.shortDescription)
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                Picker("", selection: $selectedModel) {
                                    Text("V2").tag(ParakeetModel.v2)
                                    Text("V3").tag(ParakeetModel.v3)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                                .onChange(of: selectedModel) { _, newValue in
                                    Task { @MainActor in
                                        parakeetManager.preferredModel = newValue
                                        appSettings.preferredParakeetModel = newValue
                                        if parakeetManager.state == .ready && parakeetManager.currentModel != newValue {
                                            if parakeetManager.isModelDownloaded(newValue) {
                                                try? await parakeetManager.loadModel(newValue)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(Spacing.sm)

                            Divider().background(Color.borderPrimary)

                            // Status
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(parakeetStatusColor)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Status")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.textPrimary)
                                    Text(parakeetStatusText)
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                parakeetActionButton
                            }
                            .padding(Spacing.sm)
                        }
                        .background(theme.colors.cardBackground)
                        .cornerRadius(CornerRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(theme.chrome.edgeFaint, lineWidth: 0.5)
                        )
                        .padding(.horizontal, Spacing.md)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Engine Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Parakeet Status Helpers

    private var parakeetStatusColor: Color {
        switch parakeetManager.state {
        case .ready: return .success
        case .downloaded: return .success
        case .downloading, .loading: return .active
        case .error: return .recording
        default: return .textTertiary
        }
    }

    private var parakeetStatusText: String {
        switch parakeetManager.state {
        case .notDownloaded:
            return "Not downloaded \u{2022} \(selectedModel.sizeDescription)"
        case .downloading(let progress):
            if progress > 0 {
                return "Downloading \(selectedModel.rawValue.uppercased())... \(Int(progress * 100))%"
            }
            return "Preparing \(selectedModel.rawValue.uppercased())..."
        case .downloaded:
            let models = parakeetManager.downloadedModels.map { $0.rawValue.uppercased() }.joined(separator: ", ")
            return "\(models) on device \u{2022} On standby"
        case .loading:
            return "Warming up \(selectedModel.rawValue.uppercased())..."
        case .ready:
            if let model = parakeetManager.currentModel {
                let warmupStatus = parakeetManager.isWarmedUp ? "Ready" : "Warming up..."
                return "\(model.displayName) \u{2022} \(warmupStatus)"
            }
            return "Ready"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    @ViewBuilder
    private var parakeetActionButton: some View {
        switch parakeetManager.state {
        case .notDownloaded:
            Button {
                Task { try? await parakeetManager.downloadAndLoad(selectedModel) }
            } label: {
                Text("Download")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.chrome.panelInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.active)
                    .cornerRadius(6)
            }
        case .downloading, .loading:
            BrailleSpinner(size: 14, color: .active)
        case .downloaded:
            Button {
                Task { try? await parakeetManager.loadModel(selectedModel) }
            } label: {
                Text("Warm Up")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.active)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.surfacePrimary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.active.opacity(0.3), lineWidth: 0.5)
                    )
            }
        case .ready:
            HStack(spacing: 6) {
                if parakeetManager.isWarmedUp {
                    Button {
                        parakeetManager.unloadModel()
                    } label: {
                        Text("Unload")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.surfacePrimary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.chrome.edgeFaint, lineWidth: 0.5)
                            )
                    }
                } else {
                    BrailleSpinner(size: 14, color: .active)
                }
            }
        case .error:
            Button {
                Task { try? await parakeetManager.downloadAndLoad(selectedModel) }
            } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.chrome.panelInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.active)
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Log Viewer Sheet

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var logStore = LogStore.shared
    @State private var filterLevel: LogEntry.LogLevel? = nil

    var filteredLogs: [LogEntry] {
        if let level = filterLevel {
            return logStore.entries.filter { $0.level == level }
        }
        return logStore.entries
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                if logStore.entries.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text("No logs yet")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Filter buttons
                        HStack(spacing: Spacing.xs) {
                            FilterButton(title: "All", isSelected: filterLevel == nil) {
                                filterLevel = nil
                            }
                            FilterButton(title: "Errors", isSelected: filterLevel == .error) {
                                filterLevel = .error
                            }
                            FilterButton(title: "Warnings", isSelected: filterLevel == .warning) {
                                filterLevel = .warning
                            }
                            Spacer()
                            Button(action: { logStore.clear() }) {
                                Text("Clear")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)

                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredLogs) { entry in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.formattedTime)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.textTertiary)

                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(entry.level == .info ? .textPrimary : entry.level.color.opacity(0.85))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 5)
                                    .background(Color.surfaceSecondary)
                                    .contextMenu {
                                        Button(action: {
                                            UIPasteboard.general.string = "[\(entry.formattedTime)] \(entry.message)"
                                        }) {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TalkieEyebrow(text: "Logs", tint: .ink, showLeader: false)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.active)
                }
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? theme.chrome.panelInk : .textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(isSelected ? Color.active : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Appearance Mode Button

struct AppearanceModeButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .active : .textSecondary)

                Text(mode.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.active.opacity(0.1) : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isSelected ? Color.active : Color.borderPrimary, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Debug Info Row

struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Theme Row

struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Color swatch
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(theme.colors.tableHeaderBackground)
                        .frame(width: 12, height: 24)
                    Rectangle()
                        .fill(theme.colors.tableCellBackground)
                        .frame(width: 12, height: 24)
                    Rectangle()
                        .fill(theme.colors.tableDivider)
                        .frame(width: 4, height: 24)
                }
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textPrimary)

                    Text(theme.description)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.active)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NAME")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                Spacer()
                Text("DURATION")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
            }
            .foregroundColor(theme.colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.colors.tableHeaderBackground)

            // Sample rows
            ForEach(0..<3) { index in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.colors.tableDivider)
                        .frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(["Meeting notes", "Quick idea", "Voice memo"][index])
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.colors.textPrimary)
                            Text("10:30 AM | 1.2 MB | M4A")
                                .font(.system(size: 10))
                                .foregroundColor(theme.colors.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(["2:34", "0:45", "5:12"][index])
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(theme.colors.textSecondary)
                            HStack(spacing: 4) {
                                Text("TXT")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.colors.success)
                                Image(systemName: "checkmark.icloud.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.colors.success)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.colors.tableCellBackground)
                }
            }
        }
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(theme.colors.tableBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Sync Section

struct SyncSection: View {
    @State private var appSettings = TalkieAppSettings.shared
    @ObservedObject var cloudStatusManager = iCloudStatusManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var showingEnableConfirmation = false
    @State private var localMemoCount: Int = 0

    /// Whether iCloud is actually available (signed in and accessible)
    private var isActuallyAvailable: Bool {
        cloudStatusManager.status.isAvailable
    }

    /// Effective toggle state: only ON if preference enabled AND actually available
    private var effectivelyEnabled: Bool {
        appSettings.iCloudSyncEnabled && isActuallyAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Sync")
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                // iCloud Sync Row
                HStack {
                    Image(systemName: cloudStatusManager.status.icon)
                        .foregroundColor(effectivelyEnabled ? .active : .textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    statusBadge

                    // Only show toggle if iCloud is actually available
                    if isActuallyAvailable {
                        Toggle("", isOn: Binding(
                            get: { appSettings.iCloudSyncEnabled },
                            set: { newValue in
                                if newValue && !appSettings.iCloudSyncEnabled {
                                    // Enabling - show confirmation
                                    countLocalMemos()
                                    showingEnableConfirmation = true
                                } else if !newValue && appSettings.iCloudSyncEnabled {
                                    // Disabling - no confirmation needed, just pause
                                    appSettings.iCloudSyncEnabled = false
                                    handleToggleChange(false)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .padding(Spacing.sm)
                .alert("Enable iCloud Sync?", isPresented: $showingEnableConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Enable") {
                        appSettings.iCloudSyncEnabled = true
                        handleToggleChange(true)
                    }
                } message: {
                    Text(localMemoCount > 0
                         ? "\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s") will be uploaded to iCloud. This may take a few moments."
                         : "Your memos will sync across all your Apple devices via iCloud.")
                }

            }
            .background(theme.colors.cardBackground)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(theme.chrome.edgeFaint, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private var statusBadge: some View {
        Group {
            if cloudStatusManager.status == .checking {
                BrailleSpinner(size: 12)
            } else if !effectivelyEnabled {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var statusMessage: String {
        switch cloudStatusManager.status {
        case .checking:
            return "Checking..."
        case .available:
            return appSettings.iCloudSyncEnabled ? "Connected" : "Disabled"
        case .noAccount:
            return "Not signed in"
        case .restricted:
            return "Restricted"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        case .couldNotDetermine:
            return "Status unknown"
        case .error:
            return "Error"
        }
    }

    private func countLocalMemos() {
        // Count memos in local Core Data store
        Task {
            let context = PersistenceController.shared.container.viewContext
            do {
                let count = try await context.perform {
                    let fetchRequest = VoiceMemo.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "deletedAt == nil")
                    return try context.count(for: fetchRequest)
                }
                await MainActor.run {
                    localMemoCount = count
                }
            } catch {
                AppLogger.app.error("Failed to count local memos: \(error)")
                await MainActor.run {
                    localMemoCount = 0
                }
            }
        }
    }

    private func handleToggleChange(_ enabled: Bool) {
        AppLogger.app.info("iCloud sync \(enabled ? "enabled" : "disabled")")

        if enabled {
            // Resume sync - Core Data + CloudKit automatically sync
            AppLogger.app.info("iCloud sync resumed - Core Data will push changes")
        } else {
            // Pause sync - preference tracked, automatic sync paused
            AppLogger.app.info("iCloud sync paused")
        }

        Task {
            await ConnectionManager.shared.checkAllConnections()
        }
    }
}

#if DEBUG
// MARK: - Connections Section (gated by FeatureFlags.showConnectionCenter)

struct ConnectionsSection: View {
    @ObservedObject var cloudStatusManager = iCloudStatusManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    private var bridgeManager = BridgeManager.shared

    private var connectionSummary: String {
        var connected: [String] = ["Local"]

        // Check iCloud
        if cloudStatusManager.status.isAvailable {
            if appSettings.iCloudSyncEnabled {
                connected.append("iCloud")
            }
        }

        // Check Bridge
        if bridgeManager.isPaired && bridgeManager.status == .connected {
            connected.append("Bridge")
        }

        if connected.count == 1 {
            return "Local only"
        } else {
            return connected.joined(separator: " + ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Connections")
                .padding(.horizontal, Spacing.md)

            NavigationLink(destination: ConnectionCenterView()) {
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(.active)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection Center")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text(connectionSummary)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(Spacing.sm)
                .background(theme.colors.cardBackground)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(theme.chrome.edgeFaint, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}
#endif

// MARK: - Bridge Status Badge

struct BridgeStatusBadge: View {
    private var bridgeManager = BridgeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(bridgeManager.status.color)
                .frame(width: 6, height: 6)
            Text(bridgeManager.status.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Keyboard Status Badge

struct KeyboardStatusBadge: View {
    @ObservedObject private var headlessService = HeadlessDictationService.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(headlessService.isActive ? Color.success : Color.textTertiary)
                .frame(width: 6, height: 6)
            Text(headlessService.isActive ? "Active" : "Inactive")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Mac Availability Badge

struct MacAvailabilityBadge: View {
    @State private var registry = DirectMacRegistry.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .task {
            registry.refresh()
        }
    }

    private var statusColor: Color {
        guard !registry.macs.isEmpty else {
            return .textTertiary
        }
        if registry.macs.contains(where: { $0.bridgeConnected }) {
            return .success
        }
        return .active
    }

    private var statusText: String {
        let count = registry.macs.count
        guard count > 0 else {
            return "No Mac"
        }
        if count > 1 {
            return "\(count) Macs"
        }
        guard let mac = registry.macs.first else {
            return "Mac"
        }
        if mac.bridgeConnected {
            return "Connected"
        }
        if mac.bridgePaired {
            return "Paired"
        }
        return "1 Mac"
    }
}

// MARK: - Transcription Engine Section

struct TranscriptionEngineSection: View {
    @StateObject private var parakeetManager = ParakeetModelManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var keyboardEngine: TranscriptionEnginePreference = TranscriptionService.shared.keyboardEnginePreference
    @State private var memoEngine: TranscriptionEnginePreference = TranscriptionService.shared.memoEnginePreference
    @State private var selectedModel: ParakeetModel = ParakeetModelManager.shared.preferredModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Transcription")
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                // Keyboard dictation engine
                keyboardEngineRow

                Divider().background(Color.borderPrimary)

                // Memo transcription engine
                memoEngineRow

                Divider().background(Color.borderPrimary)

                // Parakeet model selection
                parakeetModelPickerRow

                Divider().background(Color.borderPrimary)

                // Parakeet model status
                parakeetStatusRow
            }
            .background(theme.colors.cardBackground)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(theme.chrome.edgeFaint, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Keyboard Engine Row

    private var keyboardEngineRow: some View {
        HStack {
            Image(systemName: "keyboard")
                .foregroundColor(.active)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard Dictation")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text("Keyboard voice input")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Picker("", selection: $keyboardEngine) {
                Text("Auto").tag(TranscriptionEnginePreference.auto)
                Text("Apple").tag(TranscriptionEnginePreference.appleSpeech)
                Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: keyboardEngine) { _, newValue in
                TranscriptionService.shared.keyboardEnginePreference = newValue
            }
        }
        .padding(Spacing.sm)
    }

    // MARK: - Memo Engine Row

    private var memoEngineRow: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.active)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Memo Transcription")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text("Voice memo processing")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Picker("", selection: $memoEngine) {
                Text("Auto").tag(TranscriptionEnginePreference.auto)
                Text("Apple").tag(TranscriptionEnginePreference.appleSpeech)
                Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: memoEngine) { _, newValue in
                TranscriptionService.shared.memoEnginePreference = newValue
            }
        }
        .padding(Spacing.sm)
    }

    // MARK: - Model Picker Row

    private var parakeetModelPickerRow: some View {
        HStack {
            Image(systemName: "brain")
                .foregroundColor(.active)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(selectedModel.shortDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Picker("", selection: $selectedModel) {
                Text("V2").tag(ParakeetModel.v2)
                Text("V3").tag(ParakeetModel.v3)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .onChange(of: selectedModel) { _, newValue in
                Task { @MainActor in
                    parakeetManager.preferredModel = newValue
                    // If model is loaded and different, reload with new model
                    if parakeetManager.state == .ready && parakeetManager.currentModel != newValue {
                        if parakeetManager.isModelDownloaded(newValue) {
                            try? await parakeetManager.loadModel(newValue)
                        }
                    }
                }
            }
        }
        .padding(Spacing.sm)
    }

    // MARK: - Parakeet Status Row

    private var parakeetStatusRow: some View {
        HStack {
            Image(systemName: "cpu")
                .foregroundColor(parakeetStatusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(parakeetStatusText)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Action button based on state
            parakeetActionButton
        }
        .padding(Spacing.sm)
    }

    private var parakeetStatusColor: Color {
        switch parakeetManager.state {
        case .ready:
            return .success
        case .downloaded:
            return .success
        case .downloading, .loading:
            return .active
        case .error:
            return .recording
        default:
            return .textTertiary
        }
    }

    private var parakeetStatusText: String {
        switch parakeetManager.state {
        case .notDownloaded:
            return "Not downloaded • \(selectedModel.sizeDescription)"
        case .downloading(let progress):
            if progress > 0 {
                return "Downloading \(selectedModel.rawValue.uppercased())... \(Int(progress * 100))%"
            }
            return "Preparing \(selectedModel.rawValue.uppercased())..."
        case .downloaded:
            let models = parakeetManager.downloadedModels.map { $0.rawValue.uppercased() }.joined(separator: ", ")
            return "\(models) on device • On standby"
        case .loading:
            return "Warming up \(selectedModel.rawValue.uppercased())..."
        case .ready:
            if let model = parakeetManager.currentModel {
                let warmupStatus = parakeetManager.isWarmedUp ? "Ready" : "Warming up..."
                return "\(model.displayName) • \(warmupStatus)"
            }
            return "Ready"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    @ViewBuilder
    private var parakeetActionButton: some View {
        switch parakeetManager.state {
        case .notDownloaded:
            Button {
                Task {
                    try? await parakeetManager.downloadAndLoad(selectedModel)
                }
            } label: {
                Text("Download")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.chrome.panelInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.active)
                    .cornerRadius(6)
            }

        case .downloading, .loading:
            BrailleSpinner(size: 14, color: .active)

        case .downloaded:
            Button {
                Task {
                    try? await parakeetManager.loadModel(selectedModel)
                }
            } label: {
                Text("Warm Up")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.active)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.surfacePrimary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.active.opacity(0.3), lineWidth: 0.5)
                    )
            }

        case .ready:
            HStack(spacing: 6) {
                if parakeetManager.isWarmedUp {
                    Button {
                        parakeetManager.unloadModel()
                    } label: {
                        Text("Unload")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.surfacePrimary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.chrome.edgeFaint, lineWidth: 0.5)
                            )
                    }
                } else {
                    BrailleSpinner(size: 14, color: .active)
                }
            }

        case .error:
            Button {
                Task {
                    try? await parakeetManager.downloadAndLoad(selectedModel)
                }
            } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.chrome.panelInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.active)
                    .cornerRadius(6)
            }
        }
    }
}

#Preview {
    SettingsView()
}
