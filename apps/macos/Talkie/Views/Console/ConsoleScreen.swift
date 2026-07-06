//
//  ConsoleScreen.swift
//  Talkie
//
//  Sidebar console surface for managed agent sessions.
//

import AppKit
import Observation
import SwiftUI
import TalkieKit

struct ConsoleScreen: View {
    var tooltipState: SidebarTooltipState = .shared

    @State private var registry = TabDefinitionRegistry.shared
    @State private var pool = ConsoleSessionPool.shared
    @State private var showSettings = false
    @State private var showTabEditor = false
    @State private var editingTab: TabDefinition?
    @State private var didBootstrap = false
    /// When true, the starter picker is shown regardless of the active
    /// tab. Toggled by the `+` button in the tab strip — lets the user
    /// pick a fresh harness for the next tab. Resets after the pick.
    @State private var isPickingNewTab = false
    /// Tab whose chip is currently hovered — drives a small floating
    /// preview chip above the number with the tab's icon + label, so
    /// users can identify tabs without relying on numbers alone.
    @State private var hoveredTabID: String? = nil
    #if DEBUG
    @State private var debugShowLoader = false
    @State private var debugLoaderReplayToken = UUID()
    #endif

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    var body: some View {
        Group {
            if isScope {
                // Scope: tab chips live INSIDE the bezel, so we just let
                // tabContent render itself — the bezel + tab strip get
                // composed downstream in each state (starter / ready /
                // running / failure).
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ConsoleTabRail(
                        tabs: registry.tabs,
                        errors: registry.errors,
                        activeTabId: Binding(
                            get: { registry.activeTabId },
                            set: { registry.activeTabId = $0 }
                        ),
                        sessionPool: pool,
                        tooltipState: tooltipState,
                        onNewTab: { showTabEditor = true; editingTab = nil },
                        onEdit: { tab in editingTab = tab; showTabEditor = true },
                        onDuplicate: { tab in
                            if let copy = registry.duplicate(tab.id) {
                                registry.activeTabId = copy.id
                            }
                        },
                        onReveal: { tab in
                            if let url = tab.sourceURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else {
                                let url = registry.tabsDirectoryURL.appending(path: "\(tab.id).talkierc")
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        },
                        onDelete: { tab in
                            pool.close(tabId: tab.id)
                            registry.delete(tab.id)
                        }
                    )

                    Rectangle()
                        .fill(Theme.current.border.opacity(0.5))
                        .frame(width: 1)

                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(isScope ? ScopeCanvas.canvas : Theme.current.surfaceBase)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            registry.bootstrap()
        }
        .onChange(of: registry.tabs) { _, newTabs in
            pool.checkForStaleDefinitions(registry: registry)
        }
        .sheet(isPresented: $showSettings) {
            if let tab = registry.activeTab {
                ConsoleTabSettingsSheet(
                    tab: tab,
                    hasRunningSession: pool.session(for: tab.id)?.isRunning ?? false,
                    hasSession: pool.hasSession(tab.id),
                    relaunch: {
                        showSettings = false
                        pool.restart(tab: tab, registry: registry)
                    },
                    quitSession: {
                        pool.close(tabId: tab.id)
                        showSettings = false
                    },
                    onEdit: {
                        showSettings = false
                        editingTab = tab
                        showTabEditor = true
                    }
                )
                .frame(minWidth: 580, minHeight: 480)
            }
        }
        .sheet(isPresented: $showTabEditor) {
            ConsoleTabEditor(
                mode: editingTab.map { .edit($0) } ?? .create,
                onSave: { definition in
                    if editingTab != nil {
                        registry.update(definition.id, definition)
                    } else {
                        registry.create(definition)
                        registry.activeTabId = definition.id
                    }
                    showTabEditor = false
                    editingTab = nil
                },
                onCancel: {
                    showTabEditor = false
                    editingTab = nil
                }
            )
        }
        .keyboardShortcut(for: .tabNav)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isScope && shouldShowScopeStarter {
            // Starter shows whenever no session is currently running —
            // covers empty registry, the `+` picker flag, and the
            // "tab exists but not launched" case (which would otherwise
            // fall into the un-themed ConsoleTabReadyView hero).
            ScopeConsoleStarter(
                registry: registry,
                onLaunch: { template in
                    createTabFromTemplate(template)
                    isPickingNewTab = false
                },
                bezelChrome: .newSession(),
                onNewTab: { isPickingNewTab = true },
                inlineTabs: AnyView(scopeInlineTabs)
            )
        } else if let tab = registry.activeTab {
            let state = pool.state(for: tab.id)

            GeometryReader { geo in
                Group {
                    if let session = state.session {
                        ZStack {
                            #if DEBUG
                            ConsoleTerminalSurface(
                                session: session,
                                openSettings: { showSettings = true },
                                quitSession: { pool.close(tabId: tab.id) },
                                debugShowLoader: debugShowLoader,
                                debugLoaderReplayToken: debugLoaderReplayToken,
                                newTab: isScope ? { isPickingNewTab = true } : nil,
                                inlineTabs: isScope ? AnyView(scopeInlineTabs) : nil
                            )
                            #else
                            ConsoleTerminalSurface(
                                session: session,
                                openSettings: { showSettings = true },
                                quitSession: { pool.close(tabId: tab.id) },
                                debugShowLoader: false,
                                debugLoaderReplayToken: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                                newTab: isScope ? { isPickingNewTab = true } : nil,
                                inlineTabs: isScope ? AnyView(scopeInlineTabs) : nil
                            )
                            #endif

                            if pool.isStale(tab.id) {
                                VStack {
                                    Spacer()
                                    ConsoleRestartPill {
                                        pool.restart(tab: tab, registry: registry)
                                    }
                                    .padding(.bottom, 16)
                                }
                            }
                        }
                    } else if let error = state.launchError {
                        ConsoleTabLaunchFailureView(
                            tab: tab,
                            message: error,
                            openSettings: { showSettings = true },
                            retry: { pool.launch(tab: tab, registry: registry) }
                        )
                    } else {
                        ConsoleTabReadyView(
                            tab: tab,
                            openSettings: { showSettings = true },
                            launch: { launchIfNeeded(tab) }
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .id(tab.id)
        } else {
            ConsoleEmptyState()
        }
    }

    /// Build a fresh tab from a harness template and launch it. Called
    /// from the starter cards — replaces the old seeded-tab approach.
    private func createTabFromTemplate(_ template: TabDefinition) {
        // UUID prefix instead of a second-resolution timestamp — two
        // quick clicks on the same card within one second were
        // colliding under the old `Int(timeIntervalSince1970)` scheme,
        // which silently overwrote the `.talkierc` file and tore down
        // the first tab's session on the second `pool.launch`.
        let newId = "\(template.harness.rawValue)-\(UUID().uuidString.prefix(8).lowercased())"
        let label = nextContextualTabLabel(for: template)
        let newTab = TabDefinition(
            id: newId,
            label: label,
            icon: template.icon,
            order: (registry.tabs.map(\.order).max() ?? 0) + 10,
            harness: template.harness,
            model: template.model,
            provider: template.provider,
            systemPrompt: template.systemPrompt,
            cwd: template.cwd,
            launchArgs: template.launchArgs,
            readOnly: template.readOnly,
            useTmux: template.useTmux,
            tmuxSessionName: template.tmuxSessionName,
            env: template.env,
            shell: template.shell,
            sourceURL: nil
        )
        registry.create(newTab)
        registry.activeTabId = newId
        pool.launch(tab: newTab, registry: registry)
    }

    /// `+` action: clone the active tab's style (same harness/template)
    /// with the next contextual label. Lets the user spin up "3x Claude"
    /// fast without losing track of which chip is which.
    private func cloneActiveTabStyle() {
        guard let active = registry.activeTab else { return }
        createTabFromTemplate(active)
    }

    private func launchIfNeeded(_ tab: TabDefinition) {
        pool.launch(tab: tab, registry: registry)
    }

    private func selectScopeTab(_ tab: TabDefinition) {
        registry.activeTabId = tab.id
        isPickingNewTab = false
        if pool.session(for: tab.id) == nil {
            pool.launch(tab: tab, registry: registry)
        }
    }

    private func closeScopeTab(_ tab: TabDefinition) {
        let wasActive = tab.id == registry.activeTabId
        let fallbackTabId = wasActive ? neighboringTabId(afterClosing: tab.id) : nil

        hoveredTabID = nil
        pool.close(tabId: tab.id)
        registry.delete(tab.id)

        if wasActive {
            registry.activeTabId = fallbackTabId ?? registry.activeTabId
            isPickingNewTab = registry.tabs.isEmpty
        }
    }

    private func neighboringTabId(afterClosing tabId: String) -> String? {
        let tabs = registry.tabs
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            return tabs.first?.id
        }
        if index < tabs.count - 1 {
            return tabs[index + 1].id
        }
        if index > 0 {
            return tabs[index - 1].id
        }
        return nil
    }

    private func nextContextualTabLabel(for template: TabDefinition) -> String {
        let base = tabBaseLabel(for: template)
        let matchingCount = registry.tabs.filter { existing in
            tabBaseLabel(for: existing) == base && existingMatchesTemplate(existing, template)
        }.count
        return matchingCount == 0 ? base : "\(base) \(matchingCount + 1)"
    }

    private func existingMatchesTemplate(_ existing: TabDefinition, _ template: TabDefinition) -> Bool {
        existing.harness == template.harness &&
        existing.icon == template.icon &&
        existing.shell?.program == template.shell?.program &&
        existing.shell?.initScript == template.shell?.initScript
    }

    private func tabDisplayLabel(_ tab: TabDefinition, number: Int) -> String {
        let trimmed = tab.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(tabBaseLabel(for: tab)) \(number)" }
        if Int(trimmed) != nil {
            return "\(tabBaseLabel(for: tab)) \(number)"
        }
        return trimmed
    }

    private func tabBaseLabel(for tab: TabDefinition) -> String {
        let trimmed = tab.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, Int(trimmed) == nil {
            let pieces = trimmed.split(separator: " ")
            if pieces.count > 1, let last = pieces.last, Int(last) != nil {
                return pieces.dropLast().joined(separator: " ")
            }
            return trimmed
        }

        if tab.shell?.initScript == TabPresets.bridgeLogsInitScriptPath {
            return "Bridge Logs"
        }
        if tab.shell?.initScript?.contains("talkie-shell") == true {
            return "Talkie Shell"
        }

        switch tab.harness {
        case .claudeCode:
            return "Claude"
        case .pi:
            return "Pi"
        case .shell:
            return "Shell"
        case .opencode:
            return "OpenCode"
        }
    }

    private func tabDetailLabel(_ tab: TabDefinition) -> String {
        var parts: [String] = [tab.harness.displayName]
        if let model = tab.model, !model.isEmpty {
            parts.append(model)
        }
        if !tab.cwd.isEmpty {
            parts.append(tab.cwd)
        }
        return parts.joined(separator: " · ")
    }

    /// In Scope mode, the starter (cards + tab strip + `+` in title bar)
    /// is the canonical "no session running" surface. It replaces the
    /// older un-themed ConsoleTabReadyView hero for tabs that exist but
    /// haven't been launched yet.
    ///
    /// Crucially, this does NOT swallow launch failures: when the
    /// active tab's state carries a `launchError`, fall through to
    /// `ConsoleTabLaunchFailureView` (and the Pi-install onboarding it
    /// routes to) instead of bouncing the user back to the picker
    /// with no indication of what went wrong.
    private var shouldShowScopeStarter: Bool {
        guard isScope else { return false }
        if isPickingNewTab { return true }
        if registry.tabs.isEmpty { return true }
        if let tab = registry.activeTab {
            let state = pool.state(for: tab.id)
            if state.session == nil && state.launchError == nil {
                return true
            }
        }
        return false
    }

    // MARK: - Horizontal tab strip (Scope)

    /// Inline tab chips rendered INSIDE the bezel title bar. The
    /// title bar replaces the "CONSOLE / Title" path with this chip
    /// row when tabs exist; an active tab's chip is highlighted, so
    /// the chrome itself becomes the tab switcher (no separate row
    /// of chips below the bar).
    @ViewBuilder
    private var scopeInlineTabs: some View {
        if !registry.tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Text("/")
                        .font(.geistMono(size: 11, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundMuted)
                    ForEach(Array(registry.tabs.enumerated()), id: \.element.id) { idx, tab in
                        scopeInlineTabChip(tab, number: idx + 1)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .layoutPriority(1)
        }
    }

    private func scopeInlineTabChip(_ tab: TabDefinition, number: Int) -> some View {
        let isActive = tab.id == registry.activeTabId
        let isHovered = hoveredTabID == tab.id
        let showsClose = !tab.readOnly && (isHovered || isActive)
        let label = tabDisplayLabel(tab, number: number)

        return HStack(spacing: 1) {
            Button(action: { selectScopeTab(tab) }) {
                HStack(spacing: 5) {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isActive ? ScopeAmber.solid : ScopeInk.faint)
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? ScopeInk.primary : ScopeInk.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: isActive ? 126 : 104, minHeight: 18, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if !tab.readOnly {
                Button(action: { closeScopeTab(tab) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(isActive ? ScopeInk.primary : ScopeInk.muted)
                        .frame(width: 14, height: 18)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .opacity(showsClose ? 1 : 0)
                .allowsHitTesting(showsClose)
                .help("Close \(label)")
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isActive ? ScopeAmber.tint : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isActive ? ScopeAmber.solid.opacity(0.55) : ScopeEdge.faint, lineWidth: 0.5)
        )
        .contextMenu {
            if !tab.readOnly {
                Button("Close Tab") { closeScopeTab(tab) }
            }
            Button("Restart Session") { pool.restart(tab: tab, registry: registry) }
            Divider()
            Button("Edit Tab") {
                editingTab = tab
                showTabEditor = true
            }
        }
        .help("\(label) · \(tabDetailLabel(tab))")
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private func scopeTabChip(_ tab: TabDefinition, number: Int) -> some View {
        let isActive = tab.id == registry.activeTabId
        return Button(action: {
            registry.activeTabId = tab.id
            isPickingNewTab = false
            // Tap-to-launch: a chip whose session isn't running launches
            // on tap so the user goes straight to the terminal instead
            // of bouncing through a "ready" intermediate.
            if pool.session(for: tab.id) == nil {
                pool.launch(tab: tab, registry: registry)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? ScopeAmber.solid : ScopeInk.faint)
                Text("\(number)")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(isActive ? ScopeInk.primary : ScopeInk.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? ScopeAmber.tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isActive ? ScopeAmber.solid.opacity(0.55) : ScopeEdge.faint, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }
}

private struct ConsoleRestartPill: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("Restart session")
                    .font(.geist(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.orange.opacity(isHovered ? 0.95 : 0.85))
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ConsoleEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.current.foregroundMuted)

            Text("No tabs configured")
                .font(Theme.current.fontBody)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Text("Add a tab with the + button to get started.")
                .font(.geist(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.foregroundMuted)
        }
        .stageCentered()
        .background(Theme.current.surfaceBase)
    }
}

// MARK: - Scope starter

/// Hero-style cards (Claude / Pi / Shell / Logs) shown when the user
/// enters the Console without a running session. Each card calls
/// `onLaunch` with the matching seeded preset; the parent switches the
/// active tab and launches it.
private struct ScopeConsoleStarter: View {
    let registry: TabDefinitionRegistry
    let onLaunch: (TabDefinition) -> Void

    private var presets: [(TabDefinition, String, String)] {
        // Tuple: (template, blurb, channel pin). Pulls from
        // TabPresets.templates rather than the registry — the registry
        // no longer pre-seeds these, they live as static templates the
        // picker clones on demand.
        [
            (TabPresets.claude,       "Persistent Claude Code runtime with shared workspace + tools.", "CH-01"),
            (TabPresets.pi,           "Persistent Pi session with mounted workspace and prompt context.", "CH-02"),
            (TabPresets.talkieShell,  "Interactive zsh session in this Console workspace.", "CH-03"),
            (TabPresets.bridgeLogs,   "Live bridge, Talkie, and TalkieAgent logs in one terminal.", "CH-04"),
        ]
    }

    let bezelChrome: ConsoleBezelChrome
    var onNewTab: (() -> Void)? = nil
    var inlineTabs: AnyView? = nil

    var body: some View {
        ConsoleTerminalBezel(
            chrome: bezelChrome,
            statusText: "Idle",
            statusColor: ScopeInk.faint,
            footer: ConsoleBezelFooter(
                statusLabel: "Idle",
                statusColor: ScopeInk.faint,
                primary: nil,
                secondary: nil,
                trailing: nil
            ),
            openSettings: {},
            quitSession: nil,
            newTab: onNewTab,
            inlineTabs: inlineTabs
        ) {
            VStack(spacing: 0) {
                VStack(spacing: 22) {
                    Spacer(minLength: 12)

                    VStack(spacing: 4) {
                        Eyebrow("New Session", color: ScopeAmber.solid)
                        Text("Pick a starting point")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(ScopeInk.primary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 14)],
                        alignment: .center,
                        spacing: 14
                    ) {
                        ForEach(presets, id: \.0.id) { tab, blurb, channel in
                            ScopeStarterCard(
                                tab: tab,
                                blurb: blurb,
                                channel: channel,
                                onLaunch: { onLaunch(tab) }
                            )
                        }
                    }
                    .frame(maxWidth: 920)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(ScopeCanvas.canvas)
    }
}

private struct ScopeStarterCard: View {
    let tab: TabDefinition
    let blurb: String
    let channel: String
    let onLaunch: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ChannelLabel(channel)
                Spacer()
                Image(systemName: tab.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ScopeAmber.solid)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ScopeAmber.tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ScopeAmber.solid.opacity(0.45), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.label)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
                Text(tab.harness.displayName.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            Text(blurb)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: onLaunch) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("LAUNCH")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                    }
                    .foregroundStyle(ScopePanel.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ScopeAmber.solid)
                    )
                    .shadow(color: isHovered ? ScopeAmber.glow : .clear, radius: 4)
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScopeEdge.faint, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 12 : 6, y: 4)
        .animation(ScopeMotion.snap, value: isHovered)
    }
}

// MARK: - Tab-aware ready state (replaces ConsoleInactiveView for tabs)

private struct ConsoleTabReadyView: View {
    let tab: TabDefinition
    let openSettings: () -> Void
    let launch: () -> Void

    var body: some View {
        ConsoleTerminalBezel(
            chrome: .from(tab: tab),
            statusText: "Idle",
            statusColor: Theme.current.foregroundMuted,
            footer: ConsoleBezelFooter(
                statusLabel: "Idle",
                statusColor: Theme.current.foregroundMuted,
                primary: tab.harness.displayName,
                secondary: tab.cwd.isEmpty ? nil : tab.cwd,
                trailing: tab.model
            ),
            openSettings: openSettings,
            quitSession: nil
        ) {
            ConsoleStateStage(accent: Theme.current.accent) {
                ConsoleTabReadyCard(
                    tab: tab,
                    launch: launch,
                    openSettings: openSettings
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleTabReadyCard: View {
    let tab: TabDefinition
    let launch: () -> Void
    let openSettings: () -> Void
    @State private var isLaunchHovered = false
    @State private var isDetailsHovered = false

    var body: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.current.surface1)
                .frame(width: 76, height: 76)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.current.border.opacity(0.7), lineWidth: 1)
                }
                .overlay {
                    TabIconView(tab: tab, size: 28, weight: .medium)
                        .foregroundStyle(Theme.current.accent)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)

            VStack(spacing: 10) {
                Text(tab.label)
                    .font(.geist(size: 28, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)

                subtitleRow

                if let blurb = readyBlurb {
                    Text(blurb)
                        .font(.geist(size: 13, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 360)
                }
            }

            HStack(spacing: 10) {
                Button(action: launch) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("LAUNCH CONSOLE")
                            .font(.geistMono(size: 11, weight: .semibold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.current.accent.opacity(isLaunchHovered ? 1.0 : 0.9))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isLaunchHovered = $0 }

                Button(action: openSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                        Text("DETAILS")
                            .font(.geistMono(size: 11, weight: .semibold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isDetailsHovered ? Theme.current.surfaceHover : Theme.current.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.current.border.opacity(0.85), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isDetailsHovered = $0 }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 480)
    }

    @ViewBuilder
    private var subtitleRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "at")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.current.foregroundMuted)
                Text(tab.harness.displayName.uppercased())
                    .font(.geistMono(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                if let model = tab.model, !model.isEmpty {
                    Text("/")
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundMuted)
                    Text(model)
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
            }

            if !tab.cwd.isEmpty {
                Circle()
                    .fill(Theme.current.foregroundMuted.opacity(0.6))
                    .frame(width: 3, height: 3)

                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.current.foregroundMuted)
                    Text(tab.cwd)
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var readyBlurb: String? {
        switch tab.harness {
        case .claudeCode:
            return "Initialize a persistent runtime for Claude Code with shared workspace context and mounted tools."
        case .pi:
            return "Initialize a persistent Pi session with the mounted workspace and prompt context loaded."
        case .opencode:
            return "Initialize a persistent OpenCode session with mounted workspace context."
        case .shell:
            return "Open an interactive zsh session in this Console workspace."
        }
    }
}

// MARK: - Tab-aware failure view

private struct ConsoleTabLaunchFailureView: View {
    let tab: TabDefinition
    let message: String
    let openSettings: () -> Void
    let retry: () -> Void

    private var isPiNotInstalled: Bool {
        tab.harness == .pi && message.contains("pi is not installed")
    }

    var body: some View {
        if isPiNotInstalled {
            PiInstallGuide(tab: tab, retry: retry, openSettings: openSettings)
        } else {
            GenericLaunchFailureView(tab: tab, message: message, openSettings: openSettings, retry: retry)
        }
    }
}

private struct GenericLaunchFailureView: View {
    let tab: TabDefinition
    let message: String
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    TabIconView(tab: tab, size: 32, weight: .light)
                        .foregroundStyle(.orange.opacity(0.5))

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                        .offset(x: 14, y: 14)
                }

                VStack(spacing: 6) {
                    Text("\(tab.label) Failed to Launch")
                        .font(.geist(size: 20, weight: .medium))
                        .foregroundStyle(Theme.current.foreground)

                    Text(tab.harness.displayName)
                        .font(.geistMono(size: 12, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }

                Text(message)
                    .font(.geistMono(size: 11, weight: .regular))
                    .foregroundStyle(Theme.current.foreground.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .fill(Theme.current.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                    .strokeBorder(.orange.opacity(0.2), lineWidth: 0.5)
                            )
                    )

                HStack(spacing: 12) {
                    Button(action: retry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Retry")
                                .font(.geist(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.current.accent.opacity(0.85))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: openSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Settings")
                                .font(.geist(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.current.surface1)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Theme.current.border, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)

            Spacer()
        }
        .stageCentered()
        .background(Theme.current.surfaceBase)
    }
}

// MARK: - Toolchain probe

private struct ToolchainProbe {
    let hasNpm: Bool
    let hasBrew: Bool

    static func detect() -> ToolchainProbe {
        return ToolchainProbe(
            hasNpm: ExecutableResolver.resolve("npm") != nil,
            hasBrew: ExecutableResolver.resolve("brew") != nil
        )
    }
}

// MARK: - Pi install guide

private let piNpmCommand = "npm install -g @mariozechner/pi-coding-agent"
private let piBrewCommand = "brew install pi"
private let piLookupHints = [
    "Your login shell PATH",
    "~/.local/bin/pi",
    "~/.bun/bin/pi",
    "~/.local/state/fnm_multishells/*/bin/pi",
    "~/.nvm/versions/node/*/bin/pi",
    "/opt/homebrew/bin/pi",
    "/usr/local/bin/pi",
]

private struct PiInstallGuide: View {
    let tab: TabDefinition
    let retry: () -> Void
    let openSettings: () -> Void

    @State private var toolchain: ToolchainProbe = ToolchainProbe(hasNpm: false, hasBrew: false)
    @State private var inlineShell = PiInstallShellRunner()
    @State private var npmCopied = false
    @State private var brewCopied = false
    @State private var isChecking = false
    @State private var piFound = false
    @State private var checkHovered = false

    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.1)

    private var shellRunner: PiInstallShellRunner {
        _inlineShell.wrappedValue
    }

    var body: some View {
        VStack(spacing: 0) {
            warningBanner
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    VStack(spacing: 24) {
                        installSection
                        if shellRunner.isVisible {
                            shellSection
                        }
                        pathsSection
                        actionSection
                    }
                    .frame(maxWidth: 520)
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
        }
        .background(Theme.current.surfaceBase)
        .task {
            let detected = await Task.detached(priority: .userInitiated) {
                ToolchainProbe.detect()
            }.value
            toolchain = detected
        }
        .onDisappear {
            shellRunner.terminate()
        }
    }

    private var warningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.amber)

            Text("Pi wasn't found on this Mac — install it once and this tab will launch automatically.")
                .font(.geist(size: 13, weight: .regular))
                .foregroundStyle(Self.amber.opacity(0.9))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Self.amber.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Self.amber.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSTALL")
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .tracking(0.5)

            VStack(spacing: 8) {
                npmMethod
                if toolchain.hasBrew {
                    brewMethod
                }
            }
        }
    }

    private var npmMethod: some View {
        installMethodCard(
            isHighlighted: true,
            badgeText: "PREFERRED",
            prereqNote: toolchain.hasNpm ? nil : "Requires Node.js — install from nodejs.org first",
            icon: "terminal",
            title: "npm",
            subtitle: "Preferred install method from the Pi project",
            command: piNpmCommand,
            copied: npmCopied,
            runningInShell: shellRunner.isRunning && shellRunner.command == piNpmCommand,
            canRunInShell: true
        ) {
            launchInstallInlineShell(piNpmCommand)
        } onCopy: {
            copyToClipboard(piNpmCommand, flag: $npmCopied)
        }
    }

    private var brewMethod: some View {
        installMethodCard(
            isHighlighted: false,
            badgeText: "FALLBACK",
            prereqNote: nil,
            icon: "shippingbox",
            title: "Homebrew",
            subtitle: "Fallback option via Homebrew package manager",
            command: piBrewCommand,
            copied: brewCopied,
            runningInShell: shellRunner.isRunning && shellRunner.command == piBrewCommand,
            canRunInShell: true
        ) {
            launchInstallInlineShell(piBrewCommand)
        } onCopy: {
            copyToClipboard(piBrewCommand, flag: $brewCopied)
        }
    }

    private func installMethodCard(
        isHighlighted: Bool,
        badgeText: String?,
        prereqNote: String?,
        icon: String,
        title: String,
        subtitle: String,
        command: String,
        copied: Bool,
        runningInShell: Bool,
        canRunInShell: Bool,
        onRunInShell: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .frame(width: 18)

                Text(title)
                    .font(.geist(size: 13, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)

                if let badgeText {
                    Text(badgeText)
                        .font(.geistMono(size: 9, weight: .regular))
                        .foregroundStyle(Self.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Self.amber.opacity(0.4), lineWidth: 1)
                        )
                }

                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.geist(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.foregroundMuted)

            if let note = prereqNote {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .medium))
                    Text(note)
                        .font(.geist(size: 11, weight: .regular))
                }
                .foregroundStyle(Theme.current.foregroundMuted)
            }

            HStack(spacing: 0) {
                Text(command)
                    .font(.geistMono(size: 11, weight: .regular))
                    .foregroundStyle(Theme.current.foreground.opacity(0.9))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 32)

                Button(action: onRunInShell) {
                    HStack(spacing: 5) {
                        Image(systemName: runningInShell ? "ellipsis.circle" : "play.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text(runningInShell ? "Running" : "Run in Shell")
                            .font(.geistMono(size: 11, weight: .regular))
                    }
                    .foregroundStyle(
                        canRunInShell
                        ? (runningInShell ? Self.amber : Theme.current.accent)
                        : Theme.current.foregroundMuted
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .disabled(!canRunInShell)

                Divider().frame(height: 32)

                Button(action: onCopy) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.geistMono(size: 11, weight: .regular))
                    }
                    .foregroundStyle(copied ? Self.amber : Theme.current.foregroundSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .strokeBorder(Theme.current.border.opacity(0.7), lineWidth: 0.5)
                    )
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Self.amber.opacity(0.25) : Theme.current.border.opacity(0.6),
                            lineWidth: isHighlighted ? 1 : 0.5
                        )
                )
        )
    }

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("INLINE SHELL")
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .tracking(0.5)

                Spacer(minLength: 0)

                Text(shellRunner.statusLabel.uppercased())
                    .font(.geistMono(size: 9, weight: .regular))
                    .foregroundStyle(shellRunner.statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(shellRunner.statusColor.opacity(0.35), lineWidth: 1)
                    )

                if shellRunner.isRunning {
                    Button("Stop") {
                        shellRunner.terminate()
                    }
                    .buttonStyle(.plain)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Self.amber)
                } else {
                    Button("Hide") {
                        shellRunner.hide()
                    }
                    .buttonStyle(.plain)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                }
            }

            Text(shellRunner.command)
                .font(.geistMono(size: 11, weight: .regular))
                .foregroundStyle(Theme.current.foreground.opacity(0.9))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Theme.current.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
                        )
                )

            Text("cwd: \(shellRunner.workingDirectory)")
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundMuted)
                .textSelection(.enabled)

            ScrollView {
                Text(shellRunner.output.isEmpty ? "Waiting for shell output…" : shellRunner.output)
                    .font(.geistMono(size: 11, weight: .regular))
                    .foregroundStyle(Theme.current.foreground.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                            .strokeBorder(Theme.current.border.opacity(0.7), lineWidth: 0.5)
                    )
            )
        }
    }

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TALKIE NOW CHECKS")
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .tracking(0.5)

            Text("Your login shell comes first, then a few common install locations.")
                .font(.geist(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.foregroundMuted)

            VStack(spacing: 0) {
                ForEach(Array(piLookupHints.enumerated()), id: \.offset) { idx, path in
                    HStack(spacing: 10) {
                        Image(systemName: idx == 0 ? "terminal" : "folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.current.foregroundMuted)
                            .frame(width: 14)

                        Text(path)
                            .font(.geistMono(size: 11, weight: .regular))
                            .foregroundStyle(Theme.current.foreground.opacity(0.8))
                            .textSelection(.enabled)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if idx < piLookupHints.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
                    )
            )
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button(action: checkAndRetry) {
                HStack(spacing: 7) {
                    if isChecking {
                        ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
                    } else if piFound {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(piFound ? "Pi found — launching…" : (isChecking ? "Checking…" : "I've installed Pi"))
                        .font(.geist(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(piFound ? Color.green.opacity(0.85) : Theme.current.accent.opacity(checkHovered ? 0.95 : 0.85))
                )
            }
            .buttonStyle(.plain)
            .onHover { checkHovered = $0 }
            .disabled(isChecking || piFound)

            Button(action: openSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Settings")
                        .font(.geist(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.current.foregroundSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.current.surface1)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.current.border, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func checkAndRetry() {
        isChecking = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                ExecutableResolver.resolve("pi") != nil
            }.value

            isChecking = false
            if found {
                piFound = true
                try? await Task.sleep(for: .milliseconds(600))
                retry()
            }
        }
    }

    private func launchInstallInlineShell(_ command: String) {
        piFound = false
        shellRunner.run(command: command, cwd: tab.resolvedCwd) { exitCode in
            guard exitCode == 0 else { return }

            Task { @MainActor in
                let found = await Task.detached(priority: .userInitiated) {
                    ExecutableResolver.resolve("pi") != nil
                }.value

                guard found else { return }
                piFound = true
                try? await Task.sleep(for: .milliseconds(500))
                shellRunner.hide()
                retry()
            }
        }
    }

    private func copyToClipboard(_ text: String, flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        flag.wrappedValue = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            flag.wrappedValue = false
        }
    }
}

@MainActor
@Observable
private final class PiInstallShellRunner {
    enum Phase: Equatable {
        case idle
        case running
        case finished(Int32)
    }

    var command: String = ""
    var workingDirectory: String = ""
    var output: String = ""
    var isVisible = false
    var phase: Phase = .idle

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdoutPipe: Pipe?
    @ObservationIgnored private var stderrPipe: Pipe?

    var isRunning: Bool {
        if case .running = phase {
            true
        } else {
            false
        }
    }

    var statusLabel: String {
        switch phase {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .finished(let code):
            code == 0 ? "Done" : "Exit \(code)"
        }
    }

    var statusColor: Color {
        switch phase {
        case .idle:
            Theme.current.foregroundSecondary
        case .running:
            Color.orange
        case .finished(let code):
            code == 0 ? .green : .orange
        }
    }

    func run(
        command: String,
        cwd: URL,
        onExit: (@MainActor (Int32) -> Void)? = nil
    ) {
        terminate()

        self.command = command
        self.workingDirectory = cwd.path
        self.output = ""
        self.isVisible = true
        self.phase = .running

        guard let shellPath = ExecutableResolver.preferredShellPath() ?? Optional("/bin/zsh") else {
            output = "[Talkie] No shell was available to run this command.\n"
            phase = .finished(127)
            return
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        var environment = ExecutableResolver.enrichedEnvironment()
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Talkie"

        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-ilc", command]
        process.currentDirectoryURL = cwd
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.append(chunk)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.append(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self.phase = .finished(process.terminationStatus)
                self.process = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                onExit?(process.terminationStatus)
            }
        }

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        append("[Talkie] Launching \(command)\n\n")

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            append("[Talkie] Failed to start shell command: \(error.localizedDescription)\n")
            self.process = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.phase = .finished(127)
        }
    }

    func hide() {
        guard !isRunning else { return }
        isVisible = false
    }

    func terminate() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil

        if case .running = phase {
            phase = .finished(SIGTERM)
        }
    }

    private func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        output += chunk

        let maxLength = 32_000
        if output.count > maxLength {
            output.removeFirst(output.count - maxLength)
        }
    }
}

// MARK: - Tab settings sheet (env, cwd, command — full launch transparency)

private struct ConsoleTabSettingsSheet: View {
    let tab: TabDefinition
    let hasRunningSession: Bool
    let hasSession: Bool
    let relaunch: () -> Void
    let quitSession: () -> Void
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var commandLine: String {
        switch tab.harness {
        case .claudeCode:
            var parts = ["claude"]
            parts.append(contentsOf: tab.launchArgs)
            return parts.joined(separator: " ")
        case .pi:
            var parts = ["pi"]
            parts.append(contentsOf: tab.launchArgs)
            return parts.joined(separator: " ")
        case .shell:
            let program = tab.shell?.program ?? "/bin/zsh"
            if let initScript = tab.shell?.initScript {
                return "\(program) -lc \"source '\(initScript)'\""
            }
            return "\(program) -i"
        case .opencode:
            var parts = ["opencode"]
            if let model = tab.model, !model.isEmpty {
                parts.append(contentsOf: ["-m", model])
            }
            parts.append(contentsOf: tab.launchArgs)
            return parts.joined(separator: " ")
        }
    }

    private var envLines: String {
        guard !tab.env.isEmpty else { return "None" }
        return tab.env
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.current.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.label)
                            .font(.geist(size: 15, weight: .medium))
                            .foregroundStyle(Theme.current.foreground)

                        Text(tab.harness.displayName)
                            .font(.geistMono(size: 11, weight: .regular))
                            .foregroundStyle(Theme.current.foregroundSecondary)
                    }
                }

                Spacer(minLength: 0)

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.current.border.opacity(0.6))
                    .frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    terminalAppearanceSection

                    settingsRow(label: "COMMAND", value: commandLine, mono: true)

                    settingsRow(label: "WORKING DIRECTORY", value: tab.cwd, mono: true)

                    if let model = tab.model, !model.isEmpty {
                        settingsRow(label: "MODEL", value: model, mono: true)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("ENVIRONMENT")
                            .font(.geistMono(size: 10, weight: .regular))
                            .foregroundStyle(Theme.current.foregroundSecondary)
                            .tracking(0.35)

                        Text(envLines)
                            .font(.geistMono(size: 12, weight: .regular))
                            .foregroundStyle(Theme.current.foreground.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                    .fill(Theme.current.surface1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                            .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
                                    )
                            )
                    }

                    if let initScript = tab.shell?.initScript, !initScript.isEmpty {
                        settingsRow(label: "INIT SCRIPT", value: initScript, mono: true)
                    }

                    if tab.useTmux {
                        let sessionName = TabLaunchSpec.tmuxSessionName(for: tab)
                        settingsRow(
                            label: "TMUX SESSION",
                            value: AgentHarnessProfile.consoleTmuxAvailable
                                ? sessionName
                                : "\(sessionName) (tmux not found)",
                            mono: true
                        )
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Theme.current.surfaceBase)

            HStack(alignment: .center, spacing: Spacing.sm) {
                Button("Relaunch", systemImage: "arrow.clockwise") {
                    relaunch()
                }
                .buttonStyle(.borderedProminent)

                if hasSession {
                    Button("Quit Session", systemImage: hasRunningSession ? "stop.fill" : "xmark.circle.fill") {
                        quitSession()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Button("Edit Tab", systemImage: "pencil") {
                    onEdit()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.current.border.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .background(Theme.current.surfaceBase)
    }

    private var terminalAppearanceSection: some View {
        ConsoleTerminalAppearanceControls(
            title: "TERMINAL APPEARANCE",
            subtitle: "Applies to all Talkie console tabs and updates the live surface immediately."
        )
    }

    private func settingsRow(label: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .tracking(0.35)

            Text(value)
                .font(mono ? .geistMono(size: 12, weight: .regular) : .geist(size: 13, weight: .regular))
                .foregroundStyle(Theme.current.foreground.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Theme.current.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
                        )
                )
        }
    }

}

struct ConsoleTerminalAppearanceControls: View {
    let title: String
    let subtitle: String
    @Environment(SettingsManager.self) private var settingsManager

    private var displayedFont: ConsoleTerminalFontOption {
        settingsManager.effectiveConsoleTerminalFont
    }

    private var fontAvailabilityNote: String? {
        guard settingsManager.consoleTerminalFont != displayedFont else { return nil }
        return "\(settingsManager.consoleTerminalFont.displayName) isn't installed on this Mac. Using \(displayedFont.displayName) instead."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .tracking(0.35)

                Text(subtitle)
                    .font(.geist(size: 12, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(ConsoleTerminalThemeOption.allCases, id: \.rawValue) { theme in
                        themeCard(theme)
                    }
                }
            }

            HStack(alignment: .top, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("FONT")
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .tracking(0.35)

                    Menu {
                        ForEach(ConsoleTerminalFontOption.availableOptions, id: \.rawValue) { font in
                            Button {
                                settingsManager.consoleTerminalFont = font
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(font.displayName)
                                        Text(font.description)
                                    }
                                    if displayedFont == font {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat.alt")
                                .font(.system(size: 11, weight: .medium))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayedFont.displayName)
                                    .font(.geist(size: 12, weight: .medium))
                                Text(displayedFont.description)
                                    .font(.geist(size: 11, weight: .regular))
                                    .foregroundStyle(Theme.current.foregroundMuted)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.current.foregroundMuted)
                        }
                        .foregroundStyle(Theme.current.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 220, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .fill(Theme.current.surface1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                        .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if let fontAvailabilityNote {
                        Text(fontAvailabilityNote)
                            .font(.geist(size: 11, weight: .regular))
                            .foregroundStyle(Theme.current.foregroundMuted)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SIZE")
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .tracking(0.35)

                    HStack(spacing: 2) {
                        ForEach(ConsoleTerminalFontSizeOption.allCases, id: \.rawValue) { size in
                            Button {
                                settingsManager.consoleTerminalFontSize = size
                            } label: {
                                VStack(spacing: 2) {
                                    Text(size.displayName)
                                        .font(.geist(size: 11, weight: .medium))
                                    Text(size.description)
                                        .font(.geistMono(size: 9, weight: .regular))
                                }
                                .foregroundStyle(
                                    settingsManager.consoleTerminalFontSize == size
                                        ? Color.white
                                        : Theme.current.foregroundSecondary
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    settingsManager.consoleTerminalFontSize == size
                                        ? settingsManager.resolvedAccentColor
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.current.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func themeCard(_ theme: ConsoleTerminalThemeOption) -> some View {
        let isSelected = settingsManager.consoleTerminalTheme == theme
        let preview = theme.previewColors

        return Button {
            settingsManager.consoleTerminalTheme = theme
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(preview.bg)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(preview.fg)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(preview.accent)
                        .frame(width: 12, height: 12)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settingsManager.resolvedAccentColor)
                    }
                }

                Text(theme.displayName)
                    .font(.geist(size: 12, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)

                Text(theme.description)
                    .font(.geist(size: 11, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(2)
            }
            .frame(width: 154, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? settingsManager.resolvedAccentColor.opacity(0.7)
                                    : Theme.current.border.opacity(0.6),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func keyboardShortcut(for _: ConsoleKeyboardShortcuts) -> some View {
        self
            .background {
                Group {
                    ForEach(1...9, id: \.self) { index in
                        Button("") {
                            let registry = TabDefinitionRegistry.shared
                            if index <= registry.tabs.count {
                                registry.activeTabId = registry.tabs[index - 1].id
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                    }

                    Button("") {
                        let registry = TabDefinitionRegistry.shared
                        let tabs = registry.tabs
                        guard let idx = tabs.firstIndex(where: { $0.id == registry.activeTabId }) else { return }
                        let prev = idx > 0 ? idx - 1 : tabs.count - 1
                        registry.activeTabId = tabs[prev].id
                    }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                    Button("") {
                        let registry = TabDefinitionRegistry.shared
                        let tabs = registry.tabs
                        guard let idx = tabs.firstIndex(where: { $0.id == registry.activeTabId }) else { return }
                        let next = idx < tabs.count - 1 ? idx + 1 : 0
                        registry.activeTabId = tabs[next].id
                    }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
            }
    }
}

private enum ConsoleKeyboardShortcuts {
    case tabNav
}

private struct ConsoleLoadingView: View {
    let initialProfile: ManagedAgentConsoleProfile
    let openSettings: () -> Void

    var body: some View {
        ConsoleTerminalBezel(
            chrome: .from(profile: initialProfile),
            statusText: "Launching",
            statusColor: .orange,
            footer: ConsoleBezelFooter(
                statusLabel: "Launching",
                statusColor: .orange,
                primary: initialProfile.title,
                secondary: nil,
                trailing: nil
            ),
            openSettings: openSettings,
            quitSession: nil
        ) {
            ConsoleTerminalLoadingPane(
                profile: initialProfile
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleLaunchFailureView: View {
    let profile: ManagedAgentConsoleProfile
    let message: String
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        ConsoleTerminalBezel(
            chrome: .from(profile: profile),
            statusText: "Failed",
            statusColor: .red,
            footer: ConsoleBezelFooter(
                statusLabel: "Failed",
                statusColor: .red,
                primary: profile.title,
                secondary: nil,
                trailing: "Launch failed"
            ),
            openSettings: openSettings,
            quitSession: nil
        ) {
            ConsoleStateStage(accent: .orange) {
                ConsoleStatePanel(
                    profile: profile,
                    eyebrow: "Launch Failed",
                    title: profile.consoleFailureTitle,
                    subtitle: profile.consoleFailureSubtitle,
                    symbolName: "exclamationmark.triangle",
                    accent: .orange,
                    badges: [
                        ConsoleStateBadgeData(icon: profile.symbolName, title: profile.title),
                        ConsoleStateBadgeData(icon: "bolt.horizontal.circle", title: "Failed")
                    ],
                    detailTitle: "Runtime Output",
                    detailText: message,
                    secondaryAction: .init(
                        title: "Settings",
                        subtitle: "Inspect context and fallback",
                        icon: "slider.horizontal.3",
                        style: .secondary,
                        action: openSettings
                    ),
                    primaryAction: .init(
                        title: "Retry Launch",
                        subtitle: "Attempt the same session again",
                        icon: "arrow.clockwise",
                        style: .primary,
                        action: retry
                    )
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleInactiveView: View {
    let profile: ManagedAgentConsoleProfile
    let openSettings: () -> Void
    let relaunch: () -> Void

    var body: some View {
        ConsoleTerminalBezel(
            chrome: .from(profile: profile),
            statusText: "Inactive",
            statusColor: .orange,
            footer: ConsoleBezelFooter(
                statusLabel: "Inactive",
                statusColor: .orange,
                primary: profile.title,
                secondary: nil,
                trailing: "Session released"
            ),
            openSettings: openSettings,
            quitSession: nil
        ) {
            ConsoleStateStage(accent: Theme.current.accent) {
                ConsoleStatePanel(
                    profile: profile,
                    eyebrow: profile.consoleInactiveEyebrow,
                    title: profile.consoleInactiveTitle,
                    subtitle: profile.consoleInactiveSubtitle,
                    symbolName: profile.symbolName,
                    accent: Theme.current.accent,
                    badges: profile.consoleInactiveBadges,
                    detailTitle: profile.consoleInactiveDetailTitle,
                    detailText: profile.consoleInactiveDetailText,
                    secondaryAction: .init(
                        title: "Settings",
                        subtitle: "Adjust context or fallback",
                        icon: "slider.horizontal.3",
                        style: .secondary,
                        action: openSettings
                    ),
                    primaryAction: .init(
                        title: profile.consoleInactivePrimaryActionTitle,
                        subtitle: profile.consoleInactivePrimaryActionSubtitle,
                        icon: profile.symbolName,
                        style: .primary,
                        action: relaunch
                    )
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleTerminalSurface: View {
    let session: ManagedAgentConsoleSession
    let openSettings: () -> Void
    let quitSession: () -> Void
    let debugShowLoader: Bool
    let debugLoaderReplayToken: UUID
    var newTab: (() -> Void)? = nil
    var inlineTabs: AnyView? = nil
    @Environment(SettingsManager.self) private var settingsManager
    @State private var terminalReady = false
    @State private var popoutManager = ConsolePopoutManager.shared
    @State private var captureController = ConsoleTerminalCaptureController()

    private var isPoppedOut: Bool {
        popoutManager.isPoppedOut(session.id)
    }

    var body: some View {
        ConsoleTerminalBezel(
            chrome: .from(profile: session.profile),
            statusText: session.statusLabel,
            statusColor: statusColor,
            footer: ConsoleBezelFooter(
                statusLabel: session.statusLabel,
                statusColor: statusColor,
                primary: session.profile.harness.displayName,
                secondary: session.workspace.rootURL.path,
                trailing: session.profile.preferredModel
            ),
            openSettings: openSettings,
            quitSession: quitSession,
            popout: { [session, settingsManager] in
                ConsolePopoutManager.shared.openOrFocus(
                    session: session,
                    settingsManager: settingsManager
                )
            },
            newTab: newTab,
            inlineTabs: inlineTabs
        ) {
            if isPoppedOut {
                ConsolePopoutPlaceholder(
                    profile: session.profile,
                    focusWindow: { [session, settingsManager] in
                        ConsolePopoutManager.shared.openOrFocus(
                            session: session,
                            settingsManager: settingsManager
                        )
                    }
                )
            } else {
                ZStack(alignment: .topTrailing) {
                    ManagedAgentTerminalView(
                        session: session,
                        isReady: $terminalReady,
                        holdLoader: debugShowLoader,
                        loaderReplayToken: debugLoaderReplayToken,
                        appearance: settingsManager.consoleTerminalAppearance,
                        backgroundColor: settingsManager.consoleTerminalTheme.backgroundColor,
                        foregroundColor: settingsManager.consoleTerminalTheme.foregroundColor
                    )
                    .id(session.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ConsoleTerminalCaptureControls(
                        controller: captureController,
                        session: session
                    )
                    .padding(.top, 10)
                    .padding(.trailing, 10)

                    ConsoleTerminalDictationDock(
                        controller: captureController,
                        session: session
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.surfaceBase)
    }

    private var statusColor: Color {
        switch session.status {
        case .launching:
            .orange
        case .running:
            .green
        case .exited(let code):
            code == 0 ? .green : .orange
        case .failed:
            .red
        }
    }

}

private struct ConsolePopoutPlaceholder: View {
    let profile: ManagedAgentConsoleProfile
    let focusWindow: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.current.accent)

            Text("\(profile.title) is open in its own window.")
                .font(Theme.current.fontBody)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Button(action: focusWindow) {
                HStack(spacing: 7) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Focus window")
                        .font(.geist(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.current.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.current.surfaceHover)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.current.border.opacity(0.85), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.surfaceBase)
    }
}

// MARK: - Bezel chrome (shared between active session, idle, ready, and failure states)

private enum ConsoleBezelIcon {
    case symbol(String)
    case tab(TabDefinition)
}

private struct ConsoleBezelChrome {
    let title: String
    let icon: ConsoleBezelIcon
    let showsSparkles: Bool
    let guideText: String?
    let guideBadges: [ConsoleStateBadgeData]

    static func from(profile: ManagedAgentConsoleProfile) -> ConsoleBezelChrome {
        ConsoleBezelChrome(
            title: profile.title,
            icon: .symbol(profile.symbolName),
            showsSparkles: profile.id == ManagedAgentConsoleProfile.talkieAgent.id,
            guideText: profile.consoleGuideText,
            guideBadges: profile.consoleGuideBadges
        )
    }

    static func from(tab: TabDefinition) -> ConsoleBezelChrome {
        ConsoleBezelChrome(
            title: tab.label,
            icon: .tab(tab),
            showsSparkles: false,
            guideText: nil,
            guideBadges: []
        )
    }

    /// Generic chrome for the "no tab yet" / starter state — used when
    /// the registry has zero tabs and the picker is on screen.
    static func newSession() -> ConsoleBezelChrome {
        ConsoleBezelChrome(
            title: "New Session",
            icon: .symbol("terminal"),
            showsSparkles: false,
            guideText: nil,
            guideBadges: []
        )
    }
}

private struct ConsoleBezelFooter {
    var statusLabel: String
    var statusColor: Color
    var primary: String?
    var secondary: String?
    var trailing: String?
}

private struct ConsoleTerminalBezel<Content: View>: View {
    let chrome: ConsoleBezelChrome
    let statusText: String
    let statusColor: Color
    let footer: ConsoleBezelFooter
    let openSettings: () -> Void
    let quitSession: (() -> Void)?
    var popout: (() -> Void)? = nil
    var newTab: (() -> Void)? = nil
    var inlineTabs: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ConsoleTerminalTitleBar(
                chrome: chrome,
                statusText: statusText,
                statusColor: statusColor,
                openSettings: openSettings,
                quitSession: quitSession,
                popout: popout,
                newTab: newTab,
                inlineTabs: inlineTabs
            )

            Rectangle()
                .fill(Theme.current.border.opacity(0.65))
                .frame(height: 1)

            if let guideText = chrome.guideText {
                ConsoleAgentSpotlightBar(
                    message: guideText,
                    highlights: chrome.guideBadges
                )

                Rectangle()
                    .fill(Theme.current.border.opacity(0.65))
                    .frame(height: 1)
            }

            GeometryReader { _ in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.current.surfaceBase)

            Rectangle()
                .fill(Theme.current.border.opacity(0.65))
                .frame(height: 1)

            ConsoleTerminalFooter(footer: footer)
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Theme.current.surface1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .strokeBorder(Theme.current.border.opacity(0.95), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md - 1, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.0),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
    }
}

private struct ConsoleTerminalLoadingPane: View {
    let profile: ManagedAgentConsoleProfile

    var body: some View {
        ConsoleTerminalWarmupView(
            profile: profile,
            title: profile.consoleLoadingTitle,
            subtitle: profile.consoleLoadingSubtitle
        )
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleTerminalBootOverlay: View {
    let profile: ManagedAgentConsoleProfile
    @State private var shimmerX: CGFloat = -0.7
    @State private var cursorVisible = true

    var body: some View {
        ConsoleTerminalWarmupView(
            profile: profile,
            title: profile.consoleBootTitle,
            subtitle: profile.consoleBootSubtitle,
            shimmerX: shimmerX,
            cursorVisible: cursorVisible
        )
        .allowsHitTesting(false)
        .onAppear {
            shimmerX = -0.7
            cursorVisible = true

            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                shimmerX = 1.15
            }

            withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

private struct ConsoleTerminalWarmupView: View {
    let profile: ManagedAgentConsoleProfile
    let title: String
    let subtitle: String
    var shimmerX: CGFloat = -0.7
    var cursorVisible: Bool = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.current.surfaceBase
                .opacity(0.988)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONSOLE")
                        .font(.geistMono(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary.opacity(0.84))
                        .tracking(0.95)

                    Text(title)
                        .font(Theme.current.fontTitleMedium)
                        .foregroundStyle(Theme.current.foreground.opacity(0.94))

                    Text(subtitle)
                        .font(Theme.current.fontBody)
                        .foregroundStyle(Theme.current.foregroundMuted)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ConsoleBootLine(
                        command: "mount",
                        text: "Creating session workspace"
                    )

                    ConsoleBootLine(
                        command: profile.isTalkieAgentProfile ? "config" : "context",
                        text: profile.isTalkieAgentProfile
                            ? "Loading Talkie settings and workflow guides"
                            : "Loading prompts and examples"
                    )

                    ConsoleBootLine(
                        command: profile.harness.displayName.lowercased(),
                        text: profile.isTalkieAgentProfile
                            ? "Connecting Talkie Agent workspace"
                            : "Attaching terminal surface",
                        cursorVisible: cursorVisible
                    )
                }

            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 24)
            .padding(.leading, 24)
            .padding(.trailing, 18)

            shimmerSweep
        }
    }

    private var shimmerSweep: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    .clear,
                    Theme.current.foreground.opacity(0.018),
                    Theme.current.foreground.opacity(0.065),
                    Theme.current.foreground.opacity(0.018),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: proxy.size.width * 0.32)
            .rotationEffect(.degrees(8))
            .offset(x: proxy.size.width * shimmerX)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

private struct ConsoleBootLine: View {
    let command: String
    let text: String
    var cursorVisible = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(">")
                .font(.geistMono(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.accent.opacity(0.82))

            Text(command)
                .font(.geistMono(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.foreground.opacity(0.9))

            Text(text)
                .font(.geistMono(size: 12, weight: .light))
                .foregroundStyle(Theme.current.foregroundSecondary.opacity(0.86))

            if cursorVisible {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.current.foreground.opacity(0.8))
                    .frame(width: 7, height: 12)
                    .opacity(cursorVisible ? 1 : 0.15)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ConsoleLaunchStep: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.techLabelSmall)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                Text(detail)
                    .font(.geist(size: 12, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundMuted)
            }
        }
    }
}

private struct ConsoleTerminalTitleBar: View {
    let chrome: ConsoleBezelChrome
    let statusText: String
    let statusColor: Color
    let openSettings: () -> Void
    let quitSession: (() -> Void)?
    var popout: (() -> Void)? = nil
    /// Optional `+` action surfaced in the title bar chrome. Used by
    /// Scope to expose a stable new-tab affordance — the tab strip
    /// hides when empty, so the title-bar `+` is always reachable.
    var newTab: (() -> Void)? = nil
    /// Optional inline tab chips rendered after the CONSOLE label.
    /// When provided, the chip strip *replaces* the "/Title" path so
    /// the active tab is visible via its highlighted chip — the chrome
    /// becomes the tab switcher.
    var inlineTabs: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                pathIcon

                Text("CONSOLE")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.current.foreground)
                    .tracking(0.6)

                if let inlineTabs {
                    inlineTabs
                } else {
                    HStack(spacing: 5) {
                        Text("/")
                            .font(.geistMono(size: 11, weight: .regular))
                            .foregroundStyle(Theme.current.foregroundMuted)
                        Text(chrome.title)
                            .font(.geistMono(size: 11, weight: .regular))
                            .foregroundStyle(Theme.current.foregroundSecondary)
                    }
                }

                // Stable `+` anchor — sits right after the chips so the
                // new-tab affordance reads as part of the tab row.
                if let newTab {
                    ConsoleChromeButton(
                        icon: "plus",
                        label: "New tab",
                        iconOnly: true,
                        action: newTab
                    )
                }

                if chrome.showsSparkles {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.current.accent.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ConsoleStatusChip(
                    label: statusText,
                    tint: statusColor
                )

                if let popout {
                    ConsoleChromeButton(
                        icon: "arrow.up.right.square",
                        label: "Open in new window",
                        iconOnly: true,
                        action: popout
                    )
                }

                ConsoleChromeButton(
                    icon: "gearshape",
                    label: "Settings",
                    iconOnly: true,
                    action: openSettings
                )

                if let quitSession {
                    ConsoleChromeButton(
                        icon: "xmark",
                        label: "Release session",
                        iconOnly: true,
                        action: quitSession
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.current.surface1)
    }

    @ViewBuilder
    private var pathIcon: some View {
        switch chrome.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.current.accent)
        case .tab(let tab):
            TabIconView(tab: tab, size: 13, weight: .semibold)
                .foregroundStyle(Theme.current.accent)
        }
    }
}

private extension ManagedAgentConsoleProfile {
    var isTalkieAgentProfile: Bool {
        id == Self.talkieAgent.id
    }

    var consoleGuideText: String? {
        guard isTalkieAgentProfile else { return nil }
        return "Configure Talkie, inspect mounted settings, and create or run workflows from this workspace."
    }

    var consoleGuideBadges: [ConsoleStateBadgeData] {
        guard isTalkieAgentProfile else { return [] }
        return [
            ConsoleStateBadgeData(icon: "slider.horizontal.3", title: "Configure Talkie"),
            ConsoleStateBadgeData(icon: "wand.and.stars", title: "Run Workflows")
        ]
    }

    var consoleLoadingTitle: String {
        isTalkieAgentProfile ? "Preparing Talkie Agent" : "Preparing AI"
    }

    var consoleLoadingSubtitle: String {
        if isTalkieAgentProfile {
            return "Loading Talkie config, workflow guides, and the mounted workspace before the terminal attaches."
        }
        return "Mounting the workspace, writing the context files, and attaching the terminal surface."
    }

    var consoleBootTitle: String {
        isTalkieAgentProfile ? "Attaching Talkie Agent" : "Attaching \(harness.displayName)"
    }

    var consoleBootSubtitle: String {
        if isTalkieAgentProfile {
            return "Settling the Talkie Agent workspace so config and workflow tasks are ready when the session opens."
        }
        return "Settling the embedded terminal before the live session takes over."
    }

    var consoleFailureTitle: String {
        isTalkieAgentProfile ? "Talkie Agent Launch Failed" : "Console Launch Failed"
    }

    var consoleFailureSubtitle: String {
        if isTalkieAgentProfile {
            return "Talkie could not restore the Talkie Agent workspace. Review the loaded context or retry with the same profile."
        }
        return "Talkie could not restore the terminal session. Review the launch context or retry with the same profile."
    }

    var consoleInactiveEyebrow: String {
        isTalkieAgentProfile ? "Talkie Agent" : "Idle Console"
    }

    var consoleInactiveTitle: String {
        isTalkieAgentProfile ? "Configure Talkie or Run Workflows" : "No Active Session"
    }

    var consoleInactiveSubtitle: String {
        if isTalkieAgentProfile {
            return "Launch Talkie Agent when you want help with app setup, mounted config, or workflow work from the same workspace."
        }
        return "The console is parked. Launch a fresh session when you want the terminal surface back."
    }

    var consoleInactiveBadges: [ConsoleStateBadgeData] {
        if isTalkieAgentProfile {
            return [
                ConsoleStateBadgeData(icon: symbolName, title: title),
                ConsoleStateBadgeData(icon: "slider.horizontal.3", title: "Configure Talkie"),
                ConsoleStateBadgeData(icon: "wand.and.stars", title: "Run Workflows"),
                ConsoleStateBadgeData(icon: "pause.circle", title: "Idle")
            ]
        }

        return [
            ConsoleStateBadgeData(icon: symbolName, title: title),
            ConsoleStateBadgeData(icon: "square.stack.3d.forward.dottedline", title: contextLabel),
            ConsoleStateBadgeData(icon: "pause.circle", title: "Idle")
        ]
    }

    var consoleInactiveDetailTitle: String {
        isTalkieAgentProfile ? "Suggested Tasks" : "Profile"
    }

    var consoleInactiveDetailText: String {
        if isTalkieAgentProfile {
            return """
Configure Talkie
Inspect mounted settings, explain what matters, and update file-backed config safely.

Run workflows
Create, revise, or troubleshoot workflows in Live Config/workflow-user and explain what changed.
"""
        }
        return summary
    }

    var consoleInactivePrimaryActionTitle: String {
        isTalkieAgentProfile ? "Launch Talkie Agent" : "Launch Session"
    }

    var consoleInactivePrimaryActionSubtitle: String {
        if isTalkieAgentProfile {
            return "Open config and workflow context"
        }
        return "Return to \(title)"
    }
}

@MainActor
private struct ConsoleStateStage<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Theme.current.surfaceBase

            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -24)
                .allowsHitTesting(false)

            VStack {
                Spacer()
                content
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConsoleStateBadgeData: Hashable {
    let icon: String
    let title: String
}

private struct ConsoleStateAction {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let subtitle: String
    let icon: String
    let style: Style
    let action: () -> Void
}

@MainActor
private struct ConsoleStatePanel: View {
    let profile: ManagedAgentConsoleProfile
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let badges: [ConsoleStateBadgeData]
    let detailTitle: String
    let detailText: String
    let secondaryAction: ConsoleStateAction
    let primaryAction: ConsoleStateAction

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .fill(TechnicalStyle.isActive ? TechnicalStyle.surface1 : Theme.current.surface1)
                    .frame(width: 64, height: 64)
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                            .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.techLabelSmall)
                        .foregroundStyle(accent.opacity(0.92))

                    Text(title)
                        .font(.geist(size: 24, weight: .medium))
                        .foregroundStyle(Theme.current.foreground)

                    Text(subtitle)
                        .font(.geist(size: 13, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    badgeRow
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        badgeRow
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(detailTitle.uppercased())
                    .font(.techLabelSmall)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                Text(detailText)
                    .font(.geistMono(size: 12, weight: .regular))
                    .foregroundStyle(Theme.current.foreground.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .fill(TechnicalStyle.isActive ? TechnicalStyle.surface1 : Theme.current.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                    .strokeBorder(Theme.current.border.opacity(0.7), lineWidth: 1)
                            )
                    )
            }

            ViewThatFits {
                HStack(spacing: 12) {
                    ConsoleStateActionButton(action: secondaryAction, accent: accent)
                    ConsoleStateActionButton(action: primaryAction, accent: accent)
                }

                VStack(spacing: 12) {
                    ConsoleStateActionButton(action: secondaryAction, accent: accent)
                    ConsoleStateActionButton(action: primaryAction, accent: accent)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 580, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(TechnicalStyle.isActive ? TechnicalStyle.surface0 : Theme.current.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(Theme.current.border.opacity(0.8), lineWidth: 1)
        )
        .matteFinish(surfaceLevel: 1, cornerRadius: CornerRadius.card)
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
    }

    @ViewBuilder
    private var badgeRow: some View {
        ForEach(badges, id: \.self) { badge in
            ConsoleStateBadge(badge: badge, accent: accent)
        }
    }
}

@MainActor
private struct ConsoleStateBadge: View {
    let badge: ConsoleStateBadgeData
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent.opacity(0.95))

            Text(badge.title)
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(TechnicalStyle.isActive ? TechnicalStyle.surface1 : Theme.current.surface1)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.current.border.opacity(0.75), lineWidth: 1)
                )
        )
    }
}

@MainActor
private struct ConsoleAgentSpotlightBar: View {
    let message: String
    let highlights: [ConsoleStateBadgeData]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.current.accent)

                Text("Talkie Agent")
                    .font(.geist(size: 13, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)

                Text(message)
                    .font(.geist(size: 12, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    badgeRow
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        badgeRow
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.current.surfaceBase)
    }

    @ViewBuilder
    private var badgeRow: some View {
        ForEach(highlights, id: \.self) { highlight in
            ConsoleStateBadge(
                badge: highlight,
                accent: Theme.current.accent
            )
        }
    }
}

@MainActor
private struct ConsoleStateActionButton: View {
    let action: ConsoleStateAction
    let accent: Color
    @State private var isHovered = false

    var body: some View {
        Button(action: action.action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(iconFill)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconForeground)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(Theme.current.fontSMMedium)
                        .foregroundStyle(titleForeground)

                    Text(action.subtitle)
                        .font(.geist(size: 11, weight: .regular))
                        .foregroundStyle(subtitleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.cardSmall, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.cardSmall, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var isPrimary: Bool {
        action.style == .primary
    }

    private var backgroundFill: Color {
        if isPrimary {
            return isHovered ? accent.opacity(0.92) : accent.opacity(0.82)
        }
        return isHovered
            ? (TechnicalStyle.isActive ? TechnicalStyle.surfaceHover(level: 2) : Theme.current.surface1)
            : (TechnicalStyle.isActive ? TechnicalStyle.surface1 : Theme.current.surface1)
    }

    private var borderColor: Color {
        if isPrimary {
            return accent.opacity(0.95)
        }
        return isHovered ? Theme.current.foreground.opacity(0.12) : Theme.current.border.opacity(0.85)
    }

    private var titleForeground: Color {
        isPrimary ? .white : Theme.current.foreground
    }

    private var subtitleForeground: Color {
        isPrimary ? Color.white.opacity(0.76) : Theme.current.foregroundSecondary
    }

    private var iconFill: Color {
        isPrimary ? Color.white.opacity(0.14) : accent.opacity(isHovered ? 0.18 : 0.12)
    }

    private var iconForeground: Color {
        isPrimary ? .white : accent
    }
}

@MainActor
private struct ConsoleTitleChip: View {
    let label: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .semibold))

            Text(label)
                .font(.geistMono(size: 10, weight: .regular))
        }
        .foregroundStyle(Theme.current.foregroundSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(TechnicalStyle.isActive ? TechnicalStyle.surface2 : Theme.current.surface1)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.current.border.opacity(0.75), lineWidth: 1)
                )
        )
    }
}

@MainActor
private struct ConsoleStatusChip: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(label.uppercased())
                .font(.geistMono(size: 10, weight: .regular))
        }
        .foregroundStyle(Theme.current.foregroundSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(TechnicalStyle.isActive ? TechnicalStyle.surface1 : Theme.current.surface1)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

@MainActor
private struct ConsoleChromeButton: View {
    let icon: String
    let label: String
    var tint: Color? = nil
    var iconOnly: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(isHovered ? Theme.current.foreground : effectiveTint)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.current.border.opacity(0.78), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
    }

    @ViewBuilder
    private var content: some View {
        if iconOnly {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))

                Text(label)
                    .font(.geistMono(size: 10, weight: .regular))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
    }

    private var effectiveTint: Color {
        tint ?? Theme.current.foregroundSecondary
    }
}

private struct ConsoleTerminalFooter: View {
    let footer: ConsoleBezelFooter

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(footer.statusColor)
                    .frame(width: 6, height: 6)

                Text(footer.statusLabel.uppercased())
                    .font(.geistMono(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .tracking(0.6)
            }

            if let primary = footer.primary, !primary.isEmpty {
                divider
                Text(primary)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundMuted.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if let secondary = footer.secondary, !secondary.isEmpty {
                divider
                Text(secondary)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundMuted.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let trailing = footer.trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.geistMono(size: 10, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .tracking(0.15)
                    .lineLimit(1)
            }
        }
        // Match the title bar's horizontal inset (16) so the top and bottom
        // rails align — they were off by 2px (footer was 14).
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.current.surface1)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.current.border.opacity(0.7))
            .frame(width: 1, height: 10)
    }
}

private struct ConsoleInlineMetric<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label.uppercased())
                .font(.techLabelSmall)
                .foregroundStyle(Theme.current.foregroundSecondary)

            content
        }
    }
}

#if DEBUG
private struct ConsoleDebugContent: View {
    @Binding var showLoader: Bool
    let replayLoader: () -> Void
    let relaunch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            DebugSection(title: "CONSOLE") {
                Toggle(isOn: $showLoader) {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                            .frame(width: 14)

                        Text("Show Loader")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Text("Hold the boot overlay on screen while the terminal is already ready.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                DebugActionButton(icon: "play.rectangle", label: "Replay Loader") {
                    replayLoader()
                }

                DebugActionButton(icon: "arrow.clockwise", label: "Relaunch Session") {
                    relaunch()
                }
            }
        }
        .frame(width: 220)
    }
}
#endif

private struct ConsoleContextSettingsSheet: View {
    let profile: ManagedAgentConsoleProfile
    let fallbackProfile: ManagedAgentConsoleProfile
    @Binding var systemPrompt: String
    @Binding var prompt: String
    @Binding var notes: String
    @Binding var examples: String
    let relaunchContext: () -> Void
    let launchFallback: () -> Void
    let quitSession: () -> Void
    let hasRunningSession: Bool
    let hasSession: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONSOLE CONTEXT")
                        .font(.techLabelSmall)
                        .foregroundStyle(Theme.current.foregroundSecondary)

                    Text("Context")
                        .font(.geist(size: 16, weight: .medium))
                        .foregroundStyle(Theme.current.foreground)

                    Text(profile.summary)
                        .font(.geist(size: 12, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }

                Spacer(minLength: 0)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.current.border.opacity(0.6))
                    .frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ConsoleSettingsField(
                        title: "System Prompt",
                        text: $systemPrompt,
                        minHeight: 140
                    )

                    ConsoleSettingsField(
                        title: "User Prompt",
                        text: $prompt,
                        minHeight: 130
                    )

                    ConsoleSettingsField(
                        title: "Context",
                        text: $notes,
                        minHeight: 120
                    )

                    ConsoleSettingsField(
                        title: "Examples",
                        text: $examples,
                        minHeight: 150
                    )
                }
                .padding(Spacing.lg)
            }
            .background(Theme.current.surfaceBase)

            HStack(alignment: .center, spacing: Spacing.sm) {
                Button("Relaunch Context", systemImage: profile.symbolName) {
                    relaunchContext()
                }
                .buttonStyle(.borderedProminent)

                if profile.id != fallbackProfile.id {
                    Button(fallbackProfile.title, systemImage: fallbackProfile.symbolName) {
                        launchFallback()
                    }
                    .buttonStyle(.bordered)
                }

                if hasSession {
                    Button("Quit Session", systemImage: hasRunningSession ? "stop.fill" : "xmark.circle.fill") {
                        quitSession()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Text("Changes apply when you relaunch.")
                    .font(.geist(size: 12, weight: .regular))
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.current.border.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .background(Theme.current.surfaceBase)
    }
}

private struct ConsoleSettingsField: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.geistMono(size: 10, weight: .regular))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .tracking(0.35)

            TextEditor(text: $text)
                .font(.geistMono(size: 12, weight: .regular))
                .frame(minHeight: minHeight)
                .padding(Spacing.xs)
                .background(Theme.current.backgroundSecondary)
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
        }
    }
}
