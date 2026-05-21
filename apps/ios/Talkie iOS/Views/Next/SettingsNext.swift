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
//    - LAB → reset helpers, log viewer presentation (DEBUG)
//    - ABOUT → Bundle info, engine bundle id, bridge protocol
//
//  Studio source: design/studio/components/studies/Settings.tsx,
//  variant "inspector" with the rail-on-left layout.
//

import Security
import SwiftUI

struct SettingsNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var iCloudStatus = iCloudStatusManager.shared
    @ObservedObject private var parakeetManager = ParakeetModelManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var active: InspectorTab

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

    // MARK: - Panels

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Engine", appSettings.transcriptionMemoEngine.displayName, hint: appSettings.preferredParakeetModel.shortDescription)
            field("Input device", "System default")
            field("Sample rate", "System") // TODO: no TalkieAppSettings key exists yet.
            field("Channels", "System") // TODO: no TalkieAppSettings key exists yet.
            field("Gain", "Auto") // TODO: no TalkieAppSettings key exists yet.
            field("Pre-roll", "System") // TODO: no TalkieAppSettings key exists yet.
            field("Noise gate", "System") // TODO: no TalkieAppSettings key exists yet.
            metricStrip(
                title: "ENGINE TELEMETRY",
                metrics: [("LATENCY", "—"), ("WER", "—"), ("LOADED", parakeetManager.statusDescription.uppercased())]
            )
        }
    }

    private var lookPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Theme", theme.currentTheme.displayName)
            field("Density", "Standard") // TODO: no TalkieAppSettings key exists yet.
            field("Accent intensity", "Theme") // TODO: no TalkieAppSettings key exists yet.
            field("Wordmark style", "Mono")
            field("Reduce motion", theme.appearanceMode.displayName) // TODO: no dedicated motion key exists yet.

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

                HStack(spacing: 0) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        themeSwatch(t)
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
            field("iCloud sync", appSettings.iCloudSyncEnabled ? "On" : "Off", hint: iCloudStatus.status.title)
            field("Mac Bridge", bridgeStatusValue, hint: bridgeStatusHint)
            field("Account", nativeAccountValue, hint: "Sign in with Apple")
            metricStrip(
                title: "LINK HEALTH",
                metrics: [("RTT", "—"), ("SENT", "—"), ("QUEUED", "—")]
            )
            navRow("View connections detail") { AppShellRouter.shared.openConnectionCenter() }
            navRow("Workspaces") { AppShellRouter.shared.openWorkspaces() }
            navRow("Resolve sync conflicts") { AppShellRouter.shared.openSyncConflicts() }
            actionRow("Re-pair Mac", tone: .neutral) { Task { await bridgeManager.connect() } }
            if isNativelySignedIn {
                actionRow("Sign out", tone: .warn) { resetAuthState() }
            } else {
                actionRow("Sign in with Apple", tone: .accent) { AppShellRouter.shared.openSignIn() }
            }
        }
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
            actionRow("Open log viewer", tone: .accent) { AppLogger.app.info("SettingsNext log viewer requested; no LogViewerSheet is available in this target") }
            actionRow("Dump shared store", tone: .neutral) { dumpSharedStore() }
            actionRow("Force iCloud refresh", tone: .neutral) { iCloudStatus.checkStatus() }
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Version", Bundle.main.shortVersion)
            field("Build", Bundle.main.buildNumber)
            field("Channel", iosChannel)
            field("Engine bundle", appSettings.preferredParakeetModel.huggingFaceRepo)
            field("Mac bridge protocol", "talkie-bridge-v1")
            navRow("Manage AI keys") { AppShellRouter.shared.openAICredentials() }
            navRow("Workflows hub") { AppShellRouter.shared.openWorkflows() }
            navRow("Send feedback") { AppShellRouter.shared.openFeedback() }
        }
    }

    // MARK: - Panel primitives

    private func field(_ label: String, _ value: String, hint: String? = nil) -> some View {
        // Fixed-height row. Hint, when present, sits INLINE with the
        // label (truncated if it crowds the value) so the row never
        // grows beyond 44pt — gives every panel the same rhythm
        // regardless of hint presence.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
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

            Text(value)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 1)
        }
    }

    private enum ActionTone { case neutral, accent, warn }

    /// Navigation row — same 44pt chrome as actionRow but trails a
    /// chevron instead of "RUN". Use for rows that push to another
    /// surface (e.g. ConnectionCenter), not rows that fire an action.
    private func navRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 1)
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
            HStack {
                Text(label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("RUN")
                    .talkieType(.chipLabel)
                    .foregroundStyle(actionColor(tone))
            }
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 1)
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
