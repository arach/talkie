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

import SwiftUI

struct SettingsNext: View {
    @ObservedObject private var theme = ThemeManager.shared
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
            field("Engine", "Parakeet 0.4", hint: "On-device · 392 MB")
            field("Input device", "Built-in mic")
            field("Sample rate", "48 kHz")
            field("Channels", "Mono")
            field("Gain", "+3 dB", hint: "Auto-leveled when low")
            field("Pre-roll", "200 ms")
            field("Noise gate", "Soft")
            metricStrip(
                title: "ENGINE TELEMETRY",
                metrics: [("LATENCY", "180ms"), ("WER", "3.2%"), ("LOADED", "12s")]
            )
        }
    }

    private var lookPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Theme", theme.currentTheme.rawValue.capitalized)
            field("Density", "Standard")
            field("Accent intensity", "0.85")
            field("Wordmark style", "Mono")
            field("Reduce motion", "System")

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
    }

    private var connectPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("iCloud sync", "On", hint: "Last sync 2 min ago")
            field("Mac Bridge", "Paired · Mini", hint: "art@mini.local · 192.168.1.42")
            field("Account", "art@…", hint: "Sign in with Apple")
            metricStrip(
                title: "LINK HEALTH",
                metrics: [("RTT", "12ms"), ("SENT", "4.2k"), ("QUEUED", "0")]
            )
            actionRow("Re-pair Mac", tone: .neutral)
            actionRow("Sign out", tone: .warn)
        }
    }

    private var keysPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Dictation engine", "On-device")
            field("Auto-format", "Smart", hint: "Sentences + lists")
            field("Punctuation", "Inferred")
            field("Auto-capitalize", "On")
            field("Trailing space", "Smart")
            field("Voice activation", "Long-press")
            field("Haptic feedback", "Soft")
        }
    }

    private var labPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Debug-only. These won't ship in release builds.")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.bottom, 10)

            actionRow("Reset onboarding", tone: .neutral)
            actionRow("Reset auth state", tone: .neutral)
            actionRow("Reset resume tooltip", tone: .neutral)
            actionRow("Open log viewer", tone: .accent)
            actionRow("Dump shared store", tone: .neutral)
            actionRow("Force iCloud refresh", tone: .neutral)
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("Version", Bundle.main.shortVersion)
            field("Build", Bundle.main.buildNumber)
            field("Channel", "Debug")
            field("Engine bundle", "parakeet-0.4-en")
            field("Mac bridge protocol", "v2.1")
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

    private func actionRow(_ label: String, tone: ActionTone) -> some View {
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
