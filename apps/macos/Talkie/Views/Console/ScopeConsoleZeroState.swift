//
//  ScopeConsoleZeroState.swift
//  Talkie macOS
//
//  Cream-phosphor lobby for the Console when no tab is active. Echoes
//  the homepage capture-mode card row, scoped to console launch
//  actions. Includes a small signal-table of existing channels.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  ConsoleScreen branches on theme and renders ConsoleEmptyState() for
//  every other theme.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - Scope display fonts

// Cormorant Garamond — matches the homepage's `--font-display-modern`.
// Mirrors the same helper from ScopeHomeView / ScopeDraftsScreen.
private enum ScopeFont {
    private static let regularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let mediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]

    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumCandidates : regularCandidates) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }
}

// MARK: - ScopeConsoleZeroState

struct ScopeConsoleZeroState: View {
    let onNewTab: () -> Void
    let onSelectTab: (String) -> Void

    @State private var registry = TabDefinitionRegistry.shared
    @State private var pool = ConsoleSessionPool.shared

    private var tabsExist: Bool { !registry.tabs.isEmpty }

    private var liveSessionCount: Int {
        registry.tabs.reduce(0) { acc, tab in
            acc + ((pool.session(for: tab.id)?.isRunning ?? false) ? 1 : 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                cardGrid

                if tabsExist {
                    signalTable
                }

                ownershipStrip
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 840, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the root-level scope canvas / graticule show through.
    }

    // MARK: - Header strip
    //
    // The Console rail owns top-left identity, so this empty-state page
    // doesn't render a universal top bar. The thin strip below states
    // what the page is + session counts; the card grid carries the
    // actual "pick a channel" call-to-action.

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Eyebrow("Console", color: ScopeAmber.solid)
            Spacer(minLength: 8)
            Text(chromeRight)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
                .lineLimit(1)
        }
    }

    private var chromeRight: String {
        if !tabsExist {
            return "READY · 00 SESSIONS LIVE"
        }
        let count = String(format: "%02d", registry.tabs.count)
        let live = String(format: "%02d", liveSessionCount)
        return "\(count) ON FILE · \(live) LIVE"
    }

    // MARK: - Card grid (three presets)

    private var cardGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Channels")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ],
                spacing: 14
            ) {
                LaunchCard(
                    channel: "CH-01",
                    eyebrow: "Scout",
                    title: "Local CLI agent.",
                    copy: "scout ask — broker chat against your fleet.",
                    icon: "antenna.radiowaves.left.and.right",
                    existing: existingTabForPreset(.scout),
                    onTap: handlePresetTap(.scout)
                )

                LaunchCard(
                    channel: "CH-02",
                    eyebrow: "Hudson",
                    title: "Design-mind agent.",
                    copy: "hudson chat — reviews UI and design choices.",
                    icon: "pencil.and.ruler",
                    existing: existingTabForPreset(.hudson),
                    onTap: handlePresetTap(.hudson)
                )

                LaunchCard(
                    channel: "CH-XX",
                    eyebrow: "Custom",
                    title: "Bring your own.",
                    copy: "Wire a .talkierc and aim it at any shell or binary.",
                    icon: "terminal",
                    existing: nil,
                    onTap: onNewTab
                )
            }
        }
    }

    // MARK: - Presets

    private enum Preset {
        case scout
        case hudson

        /// Loose substrings that suggest the tab is one of our blessed
        /// presets. Tabs ship with user-edited labels so we only do a
        /// best-effort match; misses just open the new-tab editor.
        var matchSubstrings: [String] {
            switch self {
            case .scout:  return ["scout"]
            case .hudson: return ["hudson"]
            }
        }
    }

    private func existingTabForPreset(_ preset: Preset) -> TabDefinition? {
        let needles = preset.matchSubstrings
        return registry.tabs.first { tab in
            let hay = (tab.label + " " + tab.id).lowercased()
            return needles.contains(where: { hay.contains($0) })
        }
    }

    private func handlePresetTap(_ preset: Preset) -> () -> Void {
        return {
            if let existing = existingTabForPreset(preset) {
                onSelectTab(existing.id)
            } else {
                onNewTab()
            }
        }
    }

    // MARK: - Signal table

    private var signalTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("On file")
                Spacer()
                Button(action: onNewTab) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("NEW TAB")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                    }
                    .foregroundStyle(ScopeAmber.solid)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(registry.tabs.prefix(6).enumerated()), id: \.element.id) { idx, tab in
                    SessionRow(
                        tab: tab,
                        channel: ScopeConsoleRail.channelPin(idx),
                        sessionRunning: pool.session(for: tab.id)?.isRunning ?? false,
                        isStale: pool.isStale(tab.id),
                        onTap: { onSelectTab(tab.id) }
                    )
                    .overlay(alignment: .top) {
                        Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.faint, lineWidth: 1)
            )
        }
    }

    // MARK: - Ownership strip

    private var ownershipStrip: some View {
        HStack(spacing: 14) {
            ownershipNode(pin: "P1", label: "Your shell",    detail: "local · this device")
            SignalPath(color: ScopeAmber.solid, width: 24)
            ownershipNode(pin: "P2", label: "Your model",    detail: "you pick the harness")
            SignalPath(color: ScopeAmber.solid, width: 24)
            ownershipNode(pin: "P3", label: "Your terminal", detail: "talkierc · env · cwd")
        }
        .padding(.top, 6)
    }

    private func ownershipNode(pin: String, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            ChannelLabel(pin)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                Text(detail.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Launch card

private struct LaunchCard: View {
    let channel: String
    let eyebrow: String
    let title: String
    let copy: String
    let icon: String
    let existing: TabDefinition?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? ScopeEdge.strong : ScopeEdge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 22, color: ScopeTrace.faint, opacity: 0.40)
                    .mask(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        HStack(spacing: 9) {
                            iconBadge
                            Text(eyebrow.uppercased())
                                .font(ScopeType.channel)
                                .tracking(ScopeType.Tracking.wide)
                                .foregroundStyle(ScopeInk.faint)
                        }
                        Spacer()
                        Text(channel)
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }

                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)

                    Text(title)
                        .font(ScopeFont.display(size: 18))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .tracking(-0.3)

                    Text(copy)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ScopeInk.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text(ctaLabel)
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeAmber.solid)
                            .phosphorGlow(radius: 2, opacity: 0.28)
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeAmber.solid)
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 196, alignment: .topLeading)
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    private var ctaLabel: String {
        if existing != nil { return "OPEN" }
        return "WIRE UP"
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ScopeAmber.tintSubtle)
            .frame(width: 26, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.32)
            )
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let tab: TabDefinition
    let channel: String
    let sessionRunning: Bool
    let isStale: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ChannelLabel(channel,
                             color: sessionRunning ? ScopeAmber.solid : ScopeInk.muted,
                             strokeColor: ScopeEdge.normal)
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusBlock
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? ScopeCanvas.canvasAlt : Color.clear)
            .overlay(alignment: .leading) {
                if isHovered {
                    Rectangle().fill(ScopeAmber.solid).frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        var parts: [String] = [tab.harness.displayName.uppercased()]
        if let model = tab.model, !model.isEmpty {
            parts.append(model.uppercased())
        }
        if !tab.cwd.isEmpty {
            parts.append(tab.cwd)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusBlock: some View {
        if isStale {
            statusPill(text: "RESTART", color: Color(red: 0.72, green: 0.32, blue: 0.18))
        } else if sessionRunning {
            HStack(spacing: 6) {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                Text("LIVE")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 2, opacity: 0.28)
            }
        } else {
            statusPill(text: "IDLE", color: ScopeInk.subtle)
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(ScopeType.channel)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.4), lineWidth: 0.5)
            )
    }
}
