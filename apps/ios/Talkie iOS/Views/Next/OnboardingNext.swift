//
//  OnboardingNext.swift
//  Talkie iOS
//
//  Faithful port of OnboardingView (apps/ios/Talkie iOS/Views/
//  OnboardingView.swift, 1401 lines). Donor structure:
//
//  - 4 paged TabView slides — Welcome / Capture / Sync / GetStarted
//  - SKIP top-right, page dots + back/forward chevron at bottom
//  - Each page: hero + title + body + feature hints / status panel
//  - GetStartedPage has a System Status checklist (App / Storage /
//    Encryption / iCloud), a TAP TO TRY record button, an optional
//    "Enable iCloud for sync" deep-link, and a "GET STARTED" CTA
//
//  Decorations intentionally deferred (call out in code, not faked):
//  - GridPatternView background + CornerBrackets decoration
//  - ArchitectureWalkthrough modal sheet
//  - AnimatedStatusRow check animations on GetStarted
//
//  iCloud account status is via CKContainer.accountStatus (native
//  CloudKit, not Clerk). No auth-manager touch in this surface —
//  the rebuild is removing Clerk; see project memory.
//

import AVFoundation
import CloudKit
import Speech
import SwiftUI
import TalkieMobileKit

struct OnboardingNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage: Int = 0
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @State private var heroPulse = false
    @State private var selectedSyncNode: SyncNodeKind = .icloud
    @State private var microphonePermissionStatus: PermissionPromptStatus = .needsAction
    @State private var speechPermissionStatus: PermissionPromptStatus = .needsAction
    @State private var keyboardPermissionStatus: PermissionPromptStatus = .needsSettings

    private let totalPages = 4

    private enum SyncNodeKind: CaseIterable {
        case iphone
        case icloud
        case mac

        var icon: String {
            switch self {
            case .iphone: return "iphone"
            case .icloud: return "icloud.fill"
            case .mac: return "macbook"
            }
        }

        var label: String {
            switch self {
            case .iphone: return "iPhone"
            case .icloud: return "iCloud"
            case .mac: return "Mac"
            }
        }

        var detail: String {
            switch self {
            case .iphone: return "Recordings and dictation start locally on this iPhone."
            case .icloud: return "CloudKit keeps private memo data available across devices."
            case .mac: return "The Mac bridge runs heavier AI workflows when paired."
            }
        }
    }

    private enum PermissionPromptStatus {
        case ready
        case needsAction
        case denied
        case restricted
        case needsSettings

        var label: String {
            switch self {
            case .ready: return "READY"
            case .needsAction: return "ENABLE"
            case .denied: return "SETTINGS"
            case .restricted: return "RESTRICTED"
            case .needsSettings: return "SETTINGS"
            }
        }

        var isReady: Bool { self == .ready }
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                skipBar

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    capturePage.tag(1)
                    syncPage.tag(2)
                    getStartedPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                pageNav
            }
        }
        .onAppear {
            checkICloudStatus()
            refreshPermissionStatuses()
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                heroPulse = true
            }
        }
    }

    // MARK: - Top SKIP bar

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(action: complete) {
                Text("SKIP")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom nav (back chevron · dots · forward/checkmark)

    private var pageNav: some View {
        HStack(spacing: 18) {
            Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(currentPage > 0 ? 1 : 0)
            .disabled(currentPage == 0)

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<totalPages, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentPage ? theme.currentTheme.chrome.accent : theme.currentTheme.chrome.edgeFaint)
                        .frame(width: idx == currentPage ? 8 : 6, height: idx == currentPage ? 8 : 6)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            Spacer()

            Button(action: advanceOrComplete) {
                Image(systemName: currentPage < totalPages - 1 ? "chevron.right" : "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.currentTheme.chrome.accent))
                    .shadow(color: theme.currentTheme.chrome.accentGlow,
                            radius: theme.currentTheme.chrome.glowRadius)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func advanceOrComplete() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        } else {
            complete()
        }
    }

    private func complete() {
        // Write through the in-memory TalkieAppSettings.shared so
        // talkieApp.swift's .onAppear sees the fresh value on the
        // next home render. Setting just @AppStorage / UserDefaults
        // updates the persisted value but leaves the cached
        // appSettings.hasSeenOnboarding=false, which then re-routes
        // back to onboarding on every home appear. The settings
        // setter calls persistIfNeeded() → writes UserDefaults
        // "hasSeenOnboarding" so both sides stay in sync.
        TalkieAppSettings.shared.hasSeenOnboarding = true
        hasSeenOnboarding = true
        AppShellRouter.shared.openHome()
    }

    private func checkICloudStatus() {
        #if targetEnvironment(simulator)
        iCloudStatus = .couldNotDetermine
        #else
        CKContainer.default().accountStatus { status, _ in
            Task { @MainActor in
                iCloudStatus = status
            }
        }
        #endif
    }

    private func tryRecord() {
        complete()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            RecordingSheetController.shared.isPresented = true
        }
    }

    // MARK: - Welcome page

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()

            welcomeHero

            HStack(spacing: 8) {
                Text("VOICE")
                    .talkieType(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("+ AI")
                    .talkieType(.headline)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .shadow(color: theme.currentTheme.chrome.accentGlow,
                            radius: theme.currentTheme.chrome.glowRadius)
            }
            .padding(.top, 6)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    taglineWord("Record")
                    taglineSep
                    taglineWord("Dictate")
                    taglineSep
                    taglineWord("Transcribe")
                }

                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("On-device. Private. Yours.")
                        .talkieType(.channelLabel)
                }
                .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 4) {
                Text("usetalkie.com")
                    .talkieType(.timestamp)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .talkieType(.channelLabelTiny)
                    .opacity(0.7)
            }
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private func taglineWord(_ word: String) -> some View {
        Text(word)
            .talkieType(.channelLabelSmall)
            .foregroundStyle(theme.colors.textSecondary)
    }

    private var welcomeHero: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                    )
                    .frame(width: 140, height: 140)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(theme.currentTheme.chrome.accent.opacity(heroPulse ? 0.18 : 0.08))
                            .frame(width: 76, height: 76)
                            .scaleEffect(heroPulse ? 1.08 : 0.96)
                        Image(systemName: "waveform")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                    }

                    Text("TALKIE")
                        .talkieType(.wordmark)
                        .foregroundStyle(theme.colors.textPrimary.opacity(0.84))
                }
            }

            logoRibbon
                .offset(x: 22, y: -12)
                .rotationEffect(.degrees(12))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Talkie logo")
    }

    private var logoRibbon: some View {
        HStack(spacing: 5) {
            Text(";)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text("Talkie")
                .talkieType(.channelLabelSmall)
        }
        .foregroundStyle(theme.colors.cardBackground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(theme.currentTheme.chrome.accent)
                .shadow(color: theme.currentTheme.chrome.accentGlow, radius: 8)
        )
    }

    private var taglineSep: some View {
        Text("·")
            .talkieType(.fieldValue)
            .foregroundStyle(theme.colors.textTertiary)
    }

    // MARK: - Capture page

    private var capturePage: some View {
        VStack(spacing: 22) {
            Spacer()

            captureHero

            VStack(spacing: 8) {
                Text("Capture Your Voice")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Record memos, dictate into any app,\nor let the keyboard type as you speak.\nAll on-device. Always ready.")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureHint(icon: "mic.fill",   text: "Voice memos with instant transcription")
                featureHint(icon: "keyboard",   text: "Talkie keyboard — dictate anywhere you type")
                featureHint(icon: "waveform",   text: "On-device speech recognition, no servers")
            }
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var captureHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                )
                .frame(width: 136, height: 188)

            VStack(spacing: 14) {
                Capsule()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(width: 42, height: 4)

                ZStack {
                    Circle()
                        .fill(theme.currentTheme.chrome.accent.opacity(heroPulse ? 0.20 : 0.07))
                        .frame(width: 92, height: 92)
                        .scaleEffect(heroPulse ? 1.18 : 0.92)
                    Circle()
                        .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.55), lineWidth: 1)
                        .frame(width: 78, height: 78)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .shadow(color: theme.currentTheme.chrome.accentGlow,
                                radius: theme.currentTheme.chrome.glowRadius)
                }

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(theme.currentTheme.chrome.accent.opacity(index.isMultiple(of: 2) ? 0.9 : 0.48))
                            .frame(width: 4, height: heroPulse ? CGFloat(10 + (index % 4) * 6) : CGFloat(22 - (index % 4) * 4))
                            .animation(
                                .easeInOut(duration: 0.85)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.05),
                                value: heroPulse
                            )
                    }
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.92, green: 0.18, blue: 0.18))
                        .frame(width: 6, height: 6)
                        .opacity(heroPulse ? 1 : 0.35)
                    Text("REC")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated recording phone illustration")
    }

    // MARK: - Sync page

    private var syncPage: some View {
        VStack(spacing: 22) {
            Spacer()

            syncArchitectureDiagram
                .padding(.vertical, 18)
                .padding(.horizontal, 14)
                .overlay(alignment: .top) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                        Text("USER OWNED DATA")
                            .talkieType(.channelLabelTiny)
                    }
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(theme.colors.background)
                            .overlay(Capsule().strokeBorder(
                                theme.currentTheme.chrome.accent.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            ))
                    )
                    .offset(y: -10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    theme.currentTheme.chrome.accent.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                )
                        )
                )

            VStack(spacing: 8) {
                Text("The Magic of Sync")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Record anywhere on your iPhone.\nSync locally, via iCloud, or direct to Mac.\nMac processes with on-device AI.\nAll encrypted, all yours.")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Donor's "Works perfectly fine locally without iCloud" disclaimer
            HStack(spacing: 5) {
                Image(systemName: "info.circle").font(.system(size: 10))
                Text("Works perfectly fine locally without iCloud")
                    .talkieType(.timestamp)
            }
            .foregroundStyle(theme.colors.textTertiary)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var syncArchitectureDiagram: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                syncNode(.iphone)
                syncArrow(active: selectedSyncNode == .iphone || selectedSyncNode == .icloud)
                syncNode(.icloud)
                syncArrow(active: selectedSyncNode == .icloud || selectedSyncNode == .mac)
                syncNode(.mac)
            }

            Text(selectedSyncNode.detail)
                .talkieType(.timestamp)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 32)
                .padding(.horizontal, 6)
        }
    }

    private func syncNode(_ node: SyncNodeKind) -> some View {
        let isSelected = selectedSyncNode == node
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedSyncNode = node
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: node.icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(isSelected ? theme.currentTheme.chrome.accent : theme.colors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(isSelected ? theme.currentTheme.chrome.accent.opacity(0.12) : Color.clear)
                    )
                    .scaleEffect(isSelected && heroPulse ? 1.06 : 1)
                Text(node.label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(isSelected ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.label)
        .accessibilityHint(node.detail)
    }

    private func syncArrow(active: Bool) -> some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.currentTheme.chrome.accent.opacity(active ? 0.8 : 0.35))
            .offset(x: heroPulse && active ? 2 : 0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: heroPulse)
            .accessibilityHidden(true)
    }

    // MARK: - GetStarted page

    private var getStartedPage: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("· SYSTEM STATUS")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)

            // System status panel — donor uses AnimatedStatusRow with
            // staggered check animations. Static rows here.
            VStack(spacing: 10) {
                statusRow(label: "App",         value: "Ready",       active: true)
                statusRow(label: "Storage",     value: "Local",       active: true)
                statusRow(label: "Encryption",  value: "On-Device",   active: true)
                statusRow(label: "iCloud",
                          value: iCloudStatus == .available ? "Connected" : "Offline",
                          active: iCloudStatus == .available,
                          highlight: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 4)

            permissionPromptPanel

            // TAP TO TRY record affordance
            Button(action: tryRecord) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(theme.currentTheme.chrome.accent)
                            .frame(width: 52, height: 52)
                            .shadow(color: theme.currentTheme.chrome.accentGlow,
                                    radius: theme.currentTheme.chrome.glowRadius)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(theme.colors.cardBackground)
                    }
                    Text("TAP TO TRY")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()

            if iCloudStatus != .available {
                Button(action: openICloudSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.slash").font(.system(size: 10))
                        Text("Enable iCloud for sync")
                            .talkieType(.channelLabelSmall)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Button(action: complete) {
                HStack(spacing: 8) {
                    Text("GET STARTED")
                        .talkieType(.chipLabel)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(theme.colors.cardBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }

    private var permissionPromptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· PERMISSIONS")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)

            permissionPromptRow(
                icon: "mic.fill",
                title: "Microphone",
                detail: "Record memos",
                status: microphonePermissionStatus,
                action: requestMicrophonePermission
            )
            permissionPromptRow(
                icon: "waveform",
                title: "Speech",
                detail: "Transcribe live",
                status: speechPermissionStatus,
                action: requestSpeechPermission
            )
            permissionPromptRow(
                icon: "keyboard",
                title: "Dictation Extension",
                detail: "Enable in Settings",
                status: keyboardPermissionStatus,
                action: openICloudSettings
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
    }

    private func permissionPromptRow(
        icon: String,
        title: String,
        detail: String,
        status: PermissionPromptStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.isReady ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(detail)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(status.label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(status.isReady ? theme.currentTheme.chrome.accent : theme.colors.cardBackground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(status.isReady ? Color.clear : theme.currentTheme.chrome.accent)
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        status.isReady
                                            ? theme.currentTheme.chrome.accent.opacity(0.55)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(status == .ready || status == .restricted)
        }
    }

    private func statusRow(label: String, value: String, active: Bool, highlight: Bool = false) -> some View {
        HStack {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(active ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)

            Text(label)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text(value)
                .talkieType(.channelLabelSmall)
                .foregroundStyle(highlight && active
                    ? theme.currentTheme.chrome.accent
                    : theme.colors.textSecondary)
        }
    }

    private func openICloudSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refreshPermissionStatuses() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphonePermissionStatus = .ready
        case .denied:
            microphonePermissionStatus = .denied
        case .undetermined:
            microphonePermissionStatus = .needsAction
        @unknown default:
            microphonePermissionStatus = .needsAction
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionStatus = .ready
        case .denied:
            speechPermissionStatus = .denied
        case .restricted:
            speechPermissionStatus = .restricted
        case .notDetermined:
            speechPermissionStatus = .needsAction
        @unknown default:
            speechPermissionStatus = .needsAction
        }

        keyboardPermissionStatus = KeyboardBridge.shared.getKeyboardModeEnabled() ? .ready : .needsSettings
    }

    private func requestMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphonePermissionStatus = .ready
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    microphonePermissionStatus = granted ? .ready : .denied
                }
            }
        case .denied:
            openICloudSettings()
        @unknown default:
            openICloudSettings()
        }
    }

    private func requestSpeechPermission() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionStatus = .ready
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    switch status {
                    case .authorized:
                        speechPermissionStatus = .ready
                    case .restricted:
                        speechPermissionStatus = .restricted
                    default:
                        speechPermissionStatus = .denied
                    }
                }
            }
        case .denied, .restricted:
            openICloudSettings()
        @unknown default:
            openICloudSettings()
        }
    }

    private func featureHint(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 20)
            Text(text)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}
