//
//  AgentMenuPopoverView.swift
//  TalkieAgent
//

import AppKit
import ImageIO
import SwiftUI
import TalkieKit

struct AgentMenuModel: Sendable {
    var stateTitle: String
    var stateDetail: String
    var isReady: Bool
    var isRecording: Bool
    var permissionsGranted: Bool
    var recordingShortcut: String
    var inputDeviceName: String
    var inputDevicesReady: Bool
    var isSystemDefaultInput: Bool
    var inputDevices: [AgentMenuInputDevice]
    var failedQueueCount: Int
    var recentItems: [AgentMenuRecentItem]
    var isLoadingData: Bool
}

struct AgentMenuInputDevice: Identifiable, Hashable, Sendable {
    var id: UInt32
    var uid: String
    var name: String
    var isDefault: Bool
}

struct AgentMenuRecentItem: Identifiable, Sendable {
    var id: UUID
    var preview: String
    var timestamp: String
    var text: String
}

struct AgentMenuActions {
    var toggleRecording: () -> Void
    var openHome: () -> Void
    var openTalkie: () -> Void
    var openSettings: () -> Void
    var openHistory: () -> Void
    var openAllGrabs: () -> Void
    var openGrab: (AgentLiveTrayItem) -> Void
    var openAudioSettings: () -> Void
    var openLogs: () -> Void
    var openPermissions: () -> Void
    var openQueue: () -> Void
    var clearQueue: () -> Void
    var refreshAudioDevices: () -> Void
    var selectSystemDefaultInput: () -> Void
    var selectInputDevice: (AgentMenuInputDevice) -> Void
    var rebootAudio: () -> Void
    var copyRecent: (String) -> Void
    var restart: () -> Void
    var quit: () -> Void
}

// MARK: - Theme skin
//
// The tray is theme-aware: it reads the active `VisualTheme` and selects
// an existing ScopeDesign token set — it does NOT define a new palette.
// Three skins map onto the app's themes:
//
//   live / midnight / terminal → carbon  (ScopePanel — cool dark)
//   darkMatte                  → paper   (the theme's own warm previewColors)
//   light                      → frost   (ScopePalette + ScopeInk — light)
//
// Subviews read the skin from the environment and derive elevation
// overlays from `ink`, so they read correctly on both light and dark.

struct AgentTraySkin {
    let isDark: Bool
    let headerFill: AnyShapeStyle
    let background: Color
    let panelStroke: Color

    let ink: Color
    let inkDim: Color
    let inkMuted: Color
    let inkFaint: Color
    let inkSubtle: Color

    let accent: Color
    let accentGlow: Color
    let rec: Color

    let edgeStrong: Color
    let edge: Color
    let edgeFaint: Color

    let cardFill: Color
    let cardStroke: Color
    let hoverFill: Color
    let tileFill: Color
    let tileFillHover: Color
    let tileStroke: Color
    let iconWellFill: Color
    let iconWellStroke: Color
    let composerFill: Color

    let headerTileFill: Color
    let headerTileGlyph: Color

    // The hot-mic red has no canonical ScopeDesign token; shared by all skins.
    static let recRed = Color(red: 1.0, green: 0.325, blue: 0.275)

    /// Resolve the skin for the currently-selected app theme.
    @MainActor
    static func current() -> AgentTraySkin {
        switch LiveSettings.shared.visualTheme {
        case .light:
            return .frost
        case .darkMatte:
            return .paper
        case .live, .midnight, .terminal:
            return .carbon
        }
    }

    // Carbon — cool dark, grounded on ScopePanel.*
    static let carbon = AgentTraySkin(
        isDark: true,
        headerFill: AnyShapeStyle(ScopePanel.stripTop),
        background: ScopePanel.bg,
        panelStroke: ScopePanel.Edge.strong,
        ink: ScopePanel.ink,
        inkDim: ScopePanel.inkDim,
        inkMuted: ScopePanel.inkMuted,
        inkFaint: ScopePanel.inkFaint,
        inkSubtle: ScopePanel.inkSubtle,
        accent: ScopePanel.trace,
        accentGlow: ScopePanel.traceGlow,
        rec: recRed,
        edgeStrong: ScopePanel.Edge.strong,
        edge: ScopePanel.Edge.normal,
        edgeFaint: ScopePanel.Edge.faint,
        cardFill: Color.white.opacity(0.03),
        cardStroke: ScopePanel.Edge.faint,
        hoverFill: Color.white.opacity(0.06),
        tileFill: Color.white.opacity(0.04),
        tileFillHover: Color.white.opacity(0.08),
        tileStroke: ScopePanel.Edge.faint,
        iconWellFill: Color.white.opacity(0.03),
        iconWellStroke: ScopePanel.Edge.subtle,
        composerFill: ScopePanel.trace.opacity(0.05),
        headerTileFill: Color.white.opacity(0.92),
        headerTileGlyph: Color.black.opacity(0.86)
    )

    // Frost — light, grounded on ScopePalette + ScopeInk + ScopeEdge.
    static let frost = AgentTraySkin(
        isDark: false,
        headerFill: AnyShapeStyle(ScopePalette.bgSunk),
        background: ScopePalette.bg,
        panelStroke: ScopeEdge.strong,
        ink: ScopeInk.primary,
        inkDim: ScopeInk.dim,
        inkMuted: ScopeInk.muted,
        inkFaint: ScopeInk.faint,
        inkSubtle: ScopeInk.subtle,
        accent: ScopeAmber.solid,
        accentGlow: ScopeAmber.glow,
        rec: recRed,
        edgeStrong: ScopeEdge.strong,
        edge: ScopeEdge.normal,
        edgeFaint: ScopeEdge.faint,
        cardFill: ScopePalette.bgRaised,
        cardStroke: ScopeEdge.faint,
        hoverFill: ScopeEdge.subtle,
        tileFill: ScopePalette.bgRaised,
        tileFillHover: ScopeCanvas.canvas,
        tileStroke: ScopeEdge.faint,
        iconWellFill: ScopeEdge.subtle,
        iconWellStroke: ScopeEdge.faint,
        composerFill: ScopeAmber.tint,
        headerTileFill: ScopeInk.primary,
        headerTileGlyph: ScopePalette.bgRaised
    )

    // Paper — warm, mapped from the darkMatte theme's own previewColors
    // (warm-dark, so it stays coherent over the dark warm app theme).
    static let paper: AgentTraySkin = {
        let pm = VisualTheme.darkMatte.previewColors // (bg, fg, accent)
        return AgentTraySkin(
            isDark: true,
            headerFill: AnyShapeStyle(pm.fg.opacity(0.05)),
            background: pm.bg,
            panelStroke: pm.fg.opacity(0.18),
            ink: pm.fg,
            inkDim: pm.fg.opacity(0.82),
            inkMuted: pm.fg.opacity(0.60),
            inkFaint: pm.fg.opacity(0.45),
            inkSubtle: pm.fg.opacity(0.32),
            accent: pm.accent,
            accentGlow: pm.accent.opacity(0.35),
            rec: recRed,
            edgeStrong: pm.fg.opacity(0.20),
            edge: pm.fg.opacity(0.12),
            edgeFaint: pm.fg.opacity(0.08),
            cardFill: pm.fg.opacity(0.04),
            cardStroke: pm.fg.opacity(0.08),
            hoverFill: pm.fg.opacity(0.07),
            tileFill: pm.fg.opacity(0.05),
            tileFillHover: pm.fg.opacity(0.10),
            tileStroke: pm.fg.opacity(0.09),
            iconWellFill: pm.fg.opacity(0.04),
            iconWellStroke: pm.fg.opacity(0.08),
            composerFill: pm.accent.opacity(0.06),
            headerTileFill: Color.white.opacity(0.92),
            headerTileGlyph: Color.black.opacity(0.86)
        )
    }()
}

private struct AgentTraySkinKey: EnvironmentKey {
    static let defaultValue: AgentTraySkin = .carbon
}

extension EnvironmentValues {
    var agentTraySkin: AgentTraySkin {
        get { self[AgentTraySkinKey.self] }
        set { self[AgentTraySkinKey.self] = newValue }
    }
}

struct AgentMenuPopoverView: View {
    static func preferredContentSize(for model: AgentMenuModel) -> NSSize {
        NSSize(width: popoverWidth, height: preferredHeight(for: model))
    }

    private static let popoverWidth: CGFloat = 320
    private static let headerHeight: CGFloat = 50
    private static let contentBottomPadding: CGFloat = 8
    private static let sectionSpacing: CGFloat = 8
    private static let sectionTitleHeight: CGFloat = 12
    private static let sectionTitleSpacing: CGFloat = 4
    private static let captureRowHeight: CGFloat = 44
    private static let commandRowHeight: CGFloat = 40
    private static let recentGrabsHeight: CGFloat = 78
    private static let recentRowHeight: CGFloat = 26
    private static let emptyRowHeight: CGFloat = 32
    private static let toolGridHeight: CGFloat = 90
    private static let bareSectionTitleSpacing: CGFloat = 5
    private static let recoveryRowHeight: CGFloat = 30
    private static let maxPopoverHeight: CGFloat = 535

    let model: AgentMenuModel
    let actions: AgentMenuActions

    // Resolved once when the popover is built (on open / refresh), so it
    // tracks the user's selected theme without per-frame main-actor reads.
    private let skin: AgentTraySkin

    @MainActor
    init(model: AgentMenuModel, actions: AgentMenuActions) {
        self.model = model
        self.actions = actions
        self.skin = AgentTraySkin.current()
    }

    private static func preferredHeight(for model: AgentMenuModel) -> CGFloat {
        let sectionHeader = sectionTitleHeight + sectionTitleSpacing

        let captureHeight = captureRowHeight + (model.permissionsGranted ? 0 : sectionSpacing + commandRowHeight)
        let recentGrabsSectionHeight = sectionHeader + recentGrabsHeight
        let recentRows = model.isLoadingData || model.recentItems.isEmpty
            ? emptyRowHeight
            : CGFloat(model.recentItems.count) * recentRowHeight
        let recentSectionHeight = sectionHeader + recentRows
        let toolsHeight = sectionTitleHeight + bareSectionTitleSpacing + toolGridHeight

        var sectionHeights = [
            captureHeight,
            recentGrabsSectionHeight,
            recentSectionHeight,
            toolsHeight,
        ]

        if model.failedQueueCount > 0 {
            sectionHeights.append(sectionHeader + recoveryRowHeight)
        }

        let sectionSpacingHeight = CGFloat(max(0, sectionHeights.count - 1)) * sectionSpacing
        let height = headerHeight
            + sectionHeights.reduce(0, +)
            + sectionSpacingHeight
            + contentBottomPadding

        return min(height, maxPopoverHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    captureSection
                    recentGrabsSection
                    recentSection
                    toolsSection

                    recoverySection
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: Self.popoverWidth, height: Self.preferredHeight(for: model))
        .background {
            skin.background
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(skin.panelStroke, lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 14))
        .environment(\.agentTraySkin, skin)
        .preferredColorScheme(skin.isDark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(skin.headerTileFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(skin.edge, lineWidth: 0.5)
                    }
                    .shadow(color: Color.black.opacity(skin.isDark ? 0.45 : 0.18), radius: 4, x: 0, y: 2)

                Image(nsImage: Self.menuBarIconImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(skin.headerTileGlyph)
                    .frame(width: 18, height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isRecording {
                    Circle()
                        .fill(skin.rec)
                        .frame(width: 5, height: 5)
                        .offset(x: 7, y: -7)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("Talkie Agent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(skin.ink)
                    .lineLimit(1)

                Text(model.stateDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(skin.inkSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            AgentMenuStatusPill(
                title: statusTitle,
                tint: statusTint,
                filled: model.isRecording || !model.permissionsGranted
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { Rectangle().fill(skin.headerFill) }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(skin.edge)
                .frame(height: 0.5)
        }
    }

    // Capture composer — consolidates the old NOW (record) + INPUT (mic)
    // sections into one unit, split 50/50: record on the left, mic picker
    // on the right. No shortcut keycaps; the chord lives in the header.
    private var captureSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                AgentMenuRecordHalf(
                    title: model.isRecording ? "Stop" : "Record",
                    isRecording: model.isRecording,
                    isEnabled: model.isReady,
                    action: actions.toggleRecording
                )

                Rectangle()
                    .fill(skin.edgeStrong)
                    .frame(width: 0.5)

                AgentMenuInputHalf(
                    selectedName: model.inputDeviceName,
                    devicesReady: model.inputDevicesReady,
                    isSystemDefault: model.isSystemDefaultInput,
                    devices: model.inputDevices,
                    isRecording: model.isRecording,
                    selectSystemDefault: actions.selectSystemDefaultInput,
                    selectDevice: actions.selectInputDevice,
                    refreshDevices: actions.refreshAudioDevices,
                    openAudioSettings: actions.openAudioSettings,
                    rebootAudio: actions.rebootAudio
                )
            }
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(skin.composerFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(skin.edgeStrong, lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 9))

            if !model.permissionsGranted {
                AgentMenuCommandRow(
                    title: "Permissions",
                    subtitle: "Microphone or accessibility",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: skin.accent,
                    action: actions.openPermissions
                )
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(skin.cardFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(skin.cardStroke, lineWidth: 0.5)
                }
            }
        }
    }

    private var recentSection: some View {
        AgentMenuSection(
            title: "Recent",
            trailingTitle: "All",
            trailingAction: actions.openHistory,
            trailingHelp: "Show all history"
        ) {
            if model.isLoadingData {
                AgentMenuEmptyRow(title: "Loading recent...")
            } else if model.recentItems.isEmpty {
                AgentMenuEmptyRow(title: "No recent dictations")
            } else {
                ForEach(model.recentItems) { item in
                    AgentMenuRecentRow(
                        preview: item.preview,
                        timestamp: recentTimestampLabel(item.timestamp),
                        action: { actions.copyRecent(item.text) }
                    )
                }
            }
        }
    }

    private var recentGrabsSection: some View {
        AgentMenuRecentGrabsSection(
            onOpenAll: actions.openAllGrabs,
            onOpenGrab: actions.openGrab
        )
    }

    private var toolsSection: some View {
        AgentMenuBareSection(title: "Tools") {
            // "Open Talkie" intentionally lives on the agent home page, not here —
            // it's a "leave to the main app" shortcut, not an agent tool.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                AgentMenuToolTile(title: "Home", systemImage: "rectangle.grid.2x2.fill", tint: skin.inkDim, action: actions.openHome)
                AgentMenuToolTile(title: "Settings", systemImage: "gearshape.fill", tint: skin.inkDim, action: actions.openSettings)
                AgentMenuToolTile(
                    title: "Logs",
                    systemImage: "doc.text.magnifyingglass",
                    tint: skin.inkMuted,
                    badgeTitle: errorBadgeTitle,
                    badgeTint: skin.accent,
                    action: actions.openLogs
                )
                AgentMenuToolTile(
                    title: "Permissions",
                    systemImage: "lock.shield.fill",
                    tint: model.permissionsGranted ? skin.inkMuted : skin.accent,
                    badgeTitle: model.permissionsGranted ? nil : "!",
                    badgeTint: skin.accent,
                    action: actions.openPermissions
                )
                AgentMenuToolTile(title: "Restart", systemImage: "arrow.clockwise", tint: skin.inkMuted, action: actions.restart)
                AgentMenuToolTile(title: "Quit", systemImage: "power", tint: skin.inkSubtle, action: actions.quit)
            }
        }
    }

    private var recoverySection: some View {
        Group {
            if model.failedQueueCount > 0 {
                AgentMenuSection(title: "Recovery") {
                    AgentMenuCompactSplitRow(
                        title: "Queue",
                        value: failedQueueSubtitle,
                        systemImage: "tray.full.fill",
                        tint: skin.accent,
                        primaryAction: actions.openQueue,
                        secondaryTitle: "Clear",
                        secondaryAction: actions.clearQueue
                    )
                }
            }
        }
    }

    private func recentTimestampLabel(_ timestamp: String) -> String {
        timestamp == "now" ? "now" : "\(timestamp) ago"
    }

    private var failedQueueSubtitle: String {
        "\(model.failedQueueCount) \(model.failedQueueCount == 1 ? "item" : "items") waiting"
    }

    private var errorBadgeTitle: String? {
        guard model.failedQueueCount > 0 else { return nil }
        return model.failedQueueCount > 99 ? "99+" : "\(model.failedQueueCount)"
    }

    private var statusTitle: String {
        if model.isRecording { return "REC" }
        if !model.permissionsGranted { return "PERM" }
        if !model.isReady { return "START" }
        return "READY"
    }

    private var statusTint: Color {
        if model.isRecording { return skin.rec }
        if !model.permissionsGranted { return skin.accent }
        if !model.isReady { return skin.inkMuted }
        return skin.inkMuted
    }

    private static var menuBarIconImage: NSImage {
        if let asset = NSImage(named: "MenuBarIcon")?.copy() as? NSImage {
            asset.size = NSSize(width: 24, height: 24)
            asset.isTemplate = true
            return asset
        }

        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
            NSString(string: "t").draw(in: rect.insetBy(dx: 0, dy: -1), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct AgentMenuSection<Content: View>: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil
    var trailingHelp: String = "Show all"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(skin.accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: skin.accentGlow, radius: 3)

                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(skin.inkFaint)

                Spacer(minLength: 8)

                if let trailingTitle, let trailingAction {
                    Button(action: trailingAction) {
                        HStack(spacing: 2) {
                            Text(trailingTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(skin.accent)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(trailingHelp)
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(skin.cardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(skin.cardStroke, lineWidth: 0.5)
            }
        }
    }
}

private struct AgentMenuBareSection<Content: View>: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(skin.accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: skin.accentGlow, radius: 3)

                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(skin.inkFaint)
            }
            .padding(.horizontal, 6)

            content
        }
    }
}

private struct AgentMenuCommandRow: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var shortcut: String?
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            AgentMenuIconWell(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? skin.ink : skin.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(skin.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if let shortcut, !shortcut.isEmpty {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.inkMuted)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skin.iconWellFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(skin.iconWellStroke, lineWidth: 0.75)
                    }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered && isEnabled ? skin.hoverFill : Color.clear)
        }
        .contentShape(.rect)
        .opacity(isEnabled ? 1 : 0.6)
        .focusable(false)
    }
}

private struct AgentMenuIconWell: View {
    @Environment(\.agentTraySkin) private var skin
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(skin.iconWellFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(skin.iconWellStroke, lineWidth: 0.5)
                }

            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .imageScale(.medium)
        }
        .frame(width: 24, height: 24)
    }
}

private struct AgentMenuRecentRow: View {
    @Environment(\.agentTraySkin) private var skin
    let preview: String
    let timestamp: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(skin.accent.opacity(0.7))
                    .frame(width: 3, height: 3)

                Text(preview)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(skin.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(timestamp)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(skin.inkSubtle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? skin.hoverFill : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct AgentMenuRecentGrabsSection: View {
    let onOpenAll: () -> Void
    let onOpenGrab: (AgentLiveTrayItem) -> Void

    @State private var previews: [AgentMenuGrabPreview] = []
    @State private var isLoading = true
    @State private var loadGeneration = 0

    var body: some View {
        AgentMenuSection(
            title: "Recent Grabs",
            trailingTitle: "All",
            trailingAction: onOpenAll,
            trailingHelp: "Show all screenshots and clips"
        ) {
            if previews.isEmpty && isLoading {
                AgentMenuGrabSkeletonStrip()
            } else if previews.isEmpty {
                AgentMenuEmptyRow(title: "No recent grabs", systemImage: "photo.on.rectangle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(previews) { preview in
                            AgentMenuGrabTile(
                                preview: preview,
                                action: { onOpenGrab(preview.item) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(height: 78)
            }
        }
        .task {
            await loadPreviews()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(LiveTrayNotifications.assetsDidChange)
        )) { _ in
            Task { await loadPreviews() }
        }
        .animation(.easeInOut(duration: 0.16), value: previews.map(\.id))
    }

    @MainActor
    private func loadPreviews() async {
        loadGeneration += 1
        let generation = loadGeneration

        if previews.isEmpty {
            isLoading = true
        }

        let loadedPreviews = await AgentMenuGrabPreviewLoader.previews(limit: 8)
        guard generation == loadGeneration, !Task.isCancelled else { return }
        previews = loadedPreviews
        isLoading = false
    }
}

private struct AgentMenuGrabPreview: Identifiable {
    let item: AgentLiveTrayItem
    let thumbnail: NSImage?

    var id: UUID { item.id }
}

private struct AgentMenuGrabSkeletonStrip: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    AgentMenuGrabSkeletonTile()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(height: 78)
    }
}

private struct AgentMenuGrabSkeletonTile: View {
    @Environment(\.agentTraySkin) private var skin
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(skin.tileFill)
            .frame(width: 58, height: 54)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(skin.isDark ? 0.14 : 0.34),
                        Color.white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 22, height: 70)
                .rotationEffect(.degrees(12))
                .offset(x: shimmer ? 70 : -70)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(skin.tileStroke, lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 6))
            .onAppear {
                shimmer = true
            }
            .animation(
                .easeInOut(duration: 1.05)
                    .repeatForever(autoreverses: false),
                value: shimmer
            )
    }
}

private struct AgentMenuGrabTile: View {
    @Environment(\.agentTraySkin) private var skin
    let preview: AgentMenuGrabPreview
    let action: () -> Void

    @State private var isHovered = false

    private var item: AgentLiveTrayItem { preview.item }

    var body: some View {
        Button(action: action) {
            tileContent
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(.rect)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            let provider = NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
            provider.suggestedName = item.filename
            return TalkieInternalDrag.mark(provider)
        }
        .help(helpTitle)
    }

    private var tileContent: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail = preview.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 54)
                    .clipped()
            } else {
                placeholder
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(item.isClip ? 0.56 : 0.36),
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            Image(systemName: item.isClip ? "play.fill" : "camera.viewfinder")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(4)
        }
        .frame(width: 58, height: 54)
        .background(skin.iconWellFill)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? skin.accent.opacity(0.75) : skin.tileStroke, lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(skin.isDark ? 0.30 : 0.10), radius: isHovered ? 5 : 2, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.03 : 1)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(skin.tileFill)

            Image(systemName: item.isClip ? "film.fill" : "photo.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(skin.inkSubtle)
        }
    }

    private var helpTitle: String {
        let title = item.displayName ?? item.windowTitle ?? item.appName ?? (item.isClip ? "Screen recording" : "Screenshot")
        return "\(title) • \(item.capturedAt.timeAgoShort)"
    }
}

private enum AgentMenuGrabPreviewLoader {
    static func previews(limit: Int) async -> [AgentMenuGrabPreview] {
        let items = await AgentLiveTrayAssetStore.shared.recentItems(limit: limit)
        var previews: [AgentMenuGrabPreview] = []
        previews.reserveCapacity(items.count)

        for item in items {
            guard !Task.isCancelled else { return previews }
            let thumbnail = await AgentMenuGrabThumbnailLoader.thumbnail(for: item)
            previews.append(AgentMenuGrabPreview(item: item, thumbnail: thumbnail))
        }

        return previews
    }
}

private enum AgentMenuGrabThumbnailLoader {
    static func thumbnail(for item: AgentLiveTrayItem) async -> NSImage? {
        switch item.kind {
        case .screenshot:
            return await AgentMenuImageThumbnailer.thumbnailAsync(for: item.fileURL, maxPixelSize: 180)
        case .clip:
            return await VideoFrameThumbnailer.thumbnailAsync(for: item.fileURL, maxSize: 180)
                ?? NSWorkspace.shared.icon(forFile: item.fileURL.path)
        }
    }
}

private enum AgentMenuImageThumbnailer {
    static func thumbnailAsync(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let box = await Task.detached(priority: .utility) {
            SendableCGImageBox(decodeThumbnail(for: url, maxPixelSize: maxPixelSize))
        }.value
        guard let cgImage = box.image else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func decodeThumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    private final class SendableCGImageBox: @unchecked Sendable {
        let image: CGImage?

        init(_ image: CGImage?) {
            self.image = image
        }
    }
}

private struct AgentMenuRecordHalf: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AgentMenuRecordDisc(isRecording: isRecording)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isRecording ? skin.rec : skin.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(isHovered && isEnabled ? skin.hoverFill : Color.clear)
            }
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focusable(false)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isRecording ? "Stop recording" : "Start talking")
    }
}

private struct AgentMenuRecordDisc: View {
    @Environment(\.agentTraySkin) private var skin
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? skin.rec.opacity(0.18) : skin.accent.opacity(0.10))

            Circle()
                .stroke(isRecording ? skin.rec : skin.accent.opacity(0.45), lineWidth: 1)

            if isRecording {
                RoundedRectangle(cornerRadius: 2)
                    .fill(skin.rec)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(skin.rec)
                    .frame(width: 11, height: 11)
                    .shadow(color: skin.rec.opacity(0.55), radius: 4)
            }
        }
        .frame(width: 32, height: 32)
        .shadow(color: isRecording ? skin.rec.opacity(0.4) : Color.clear, radius: 8)
    }
}

/// Decorative level meter shown while recording — animates to read as
/// "live". Not driven by real audio levels (none are exposed here).
private struct AgentMenuLiveMeter: View {
    let tint: Color

    @State private var animate = false
    private let bars: [CGFloat] = [0.4, 0.85, 0.55, 0.95, 0.5, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 2, height: animate ? 14 * bars[i] : 3)
                    .animation(
                        .easeInOut(duration: 0.45 + Double(i) * 0.06)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animate = true }
    }
}

private struct AgentMenuInputHalf: View {
    @Environment(\.agentTraySkin) private var skin
    let selectedName: String
    let devicesReady: Bool
    let isSystemDefault: Bool
    let devices: [AgentMenuInputDevice]
    let isRecording: Bool
    let selectSystemDefault: () -> Void
    let selectDevice: (AgentMenuInputDevice) -> Void
    let refreshDevices: () -> Void
    let openAudioSettings: () -> Void
    let rebootAudio: () -> Void

    @State private var isHovered = false

    var body: some View {
        if isRecording {
            // Device is locked while recording — show a live level read instead.
            HStack(spacing: 8) {
                AgentMenuLiveMeter(tint: skin.rec)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Menu {
                Button(action: selectSystemDefault) {
                    Label("System Default", systemImage: isSystemDefault ? "checkmark" : "")
                }

                if !devices.isEmpty {
                    Divider()
                }

                ForEach(devices) { device in
                    Button(action: { selectDevice(device) }) {
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(default)")
                            }
                        }
                    }
                }

                Divider()

                Button(action: refreshDevices) {
                    Label("Refresh Inputs", systemImage: "arrow.clockwise")
                }

                Button(action: openAudioSettings) {
                    Label("Audio Settings", systemImage: "slider.horizontal.3")
                }

                Button(action: rebootAudio) {
                    Label("Reboot Audio", systemImage: "powerplug")
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(skin.accent)
                        .frame(width: 15)

                    // Same size as the "Record" label; just show the first
                    // few letters — no need to fit the whole device name.
                    Text(devicesReady ? selectedName : "Loading inputs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(devicesReady ? skin.inkDim : skin.inkSubtle)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(skin.inkSubtle)
                        .frame(width: 10)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .background {
                    Rectangle()
                        .fill(isHovered ? skin.hoverFill : Color.clear)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .contentShape(.rect)
            .focusable(false)
            .help(devicesReady ? "Audio input: \(selectedName)" : "Loading audio inputs")
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

private struct AgentMenuToolTile: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    let systemImage: String
    let tint: Color
    var badgeTitle: String? = nil
    var badgeTint: Color = Color.gray
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(height: 16)

                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(skin.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)

                if let badgeTitle {
                    AgentMenuToolBadge(title: badgeTitle, tint: badgeTint)
                        .padding(.top, 5)
                        .padding(.trailing, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? skin.tileFillHover : skin.tileFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(skin.tileStroke, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(skin.isDark ? 0.32 : 0.10), radius: 3, x: 0, y: 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct AgentMenuToolBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, title.count > 1 ? 4 : 0)
            .frame(minWidth: 13, minHeight: 13)
            .background {
                Capsule()
                    .fill(tint)
            }
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.22), lineWidth: 0.5)
            }
    }
}

private struct AgentMenuCompactSplitRow: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                HStack(spacing: 7) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 16)

                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(skin.ink)

                    Text(value)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(skin.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button(secondaryTitle, action: secondaryAction)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .buttonStyle(.plain)
                .focusable(false)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
    }
}

private struct AgentMenuStatusPill: View {
    let title: String
    let tint: Color
    let filled: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(filled ? Color.black.opacity(0.82) : tint)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background {
                Capsule()
                    .fill(filled ? tint : tint.opacity(0.12))
            }
            .overlay {
                Capsule()
                    .stroke(tint.opacity(filled ? 0 : 0.34), lineWidth: 0.5)
            }
    }
}

private struct AgentMenuEmptyRow: View {
    @Environment(\.agentTraySkin) private var skin
    let title: String
    var systemImage = "text.bubble"

    var body: some View {
        HStack(spacing: 8) {
            AgentMenuIconWell(systemImage: systemImage, tint: skin.inkSubtle)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(skin.inkMuted)
            Spacer()
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
    }
}

#Preview {
    AgentMenuPopoverView(
        model: AgentMenuModel(
            stateTitle: "Recording",
            stateDetail: "Listening for dictation",
            isReady: true,
            isRecording: true,
            permissionsGranted: true,
            recordingShortcut: "⌥⌘L",
            inputDeviceName: "System Default",
            inputDevicesReady: true,
            isSystemDefaultInput: true,
            inputDevices: [
                AgentMenuInputDevice(id: 1, uid: "default", name: "MacBook Pro Microphone", isDefault: true)
            ],
            failedQueueCount: 2,
            recentItems: [
                AgentMenuRecentItem(
                    id: UUID(),
                    preview: "Turn this recording into a tighter product note for the menu treatment.",
                    timestamp: "3m",
                    text: "Turn this recording into a tighter product note for the menu treatment."
                )
            ],
            isLoadingData: false
        ),
        actions: AgentMenuActions(
            toggleRecording: {},
            openHome: {},
            openTalkie: {},
            openSettings: {},
            openHistory: {},
            openAllGrabs: {},
            openGrab: { _ in },
            openAudioSettings: {},
            openLogs: {},
            openPermissions: {},
            openQueue: {},
            clearQueue: {},
            refreshAudioDevices: {},
            selectSystemDefaultInput: {},
            selectInputDevice: { _ in },
            rebootAudio: {},
            copyRecent: { _ in },
            restart: {},
            quit: {}
        )
    )
}
