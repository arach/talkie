//
//  AgentHomeShellView.swift
//  TalkieAgent
//
//  TalkieKit-native operational home for TalkieAgent.
//  Built on TalkieKit console primitives so the agent has its own shell without
//  borrowing another app's UX layer.
//

import AppKit
import ImageIO
import SwiftUI
import TalkieKit

struct AgentHomeShellView: View {
    private static let inspectorAutoCollapseWidth: CGFloat = 900

    let onDismiss: () -> Void

    @StateObject private var store = AgentHomeActivityStore()
    @StateObject private var libraryStore = AgentHomeLibraryStore(displayLimit: 120)
    @StateObject private var captureLibraryStore = AgentHomeLibraryStore(displayLimit: 120, filter: .captures)
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var homeController = AgentHomeController.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: AgentHomeShellSection = .home
    @State private var libraryFilter: AgentHomeLibraryFilter = .all
    @State private var overflowMenu = AgentRailOverflowMenu()
    @State private var sidebarTooltipState = SidebarTooltipState()
    @AppStorage("talkie.agentHome.sidebar.compact") private var railCompact = true
    @AppStorage("talkie.agentHome.sidebar.labelWidth") private var navigationSidebarLabelWidth = 120.0
    @AppStorage("talkie.agentHome.inspector.collapsed") private var inspectorCollapsed = true

    @State private var serverStatus: TalkieAgentServerStatus = .stopped
    @State private var traySnapshot = AgentLiveTrayAssetSnapshot.empty
    @State private var storageSize = "—"
    @State private var lastOperationalRefresh: Date?

    private var manifest: OpsManifest {
        // Runtime interaction uses the Agent signal. The brand mark keeps its
        // fixed Talkie amber callout.
        OpsManifest(
            name: "Talkie Agent",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            accent: AgentTheme.accent,
            accentSoft: AgentTheme.accentSoft,
            targetLabel: "Runtime"
        )
    }

    var body: some View {
        homeShell
    }

    private var homeShell: some View {
        // No custom titlebar — the window's native title bar is the only one.
        OpsShell {
            sidebar
        } trailing: {
            EmptyView()
        } content: {
            content
        } statusBar: {
            statusBar
        }
                .opsManifest(manifest)
        .overlay(alignment: .top) {
            AgentHomeTitlePill()
                .padding(.top, 4)
                .offset(x: navigationSidebarWidth / 2)
                .allowsHitTesting(false)
        }
        // Agent Home follows the user's appearance setting (NSApp.appearance,
        // driven by LiveSettings.applyAppearance): adaptive Ops tokens resolve
        // to their light or dark variant. No forced color scheme here.
        .onAppear {
            store.startRefreshing()
            libraryStore.start()
            captureLibraryStore.start()
            permissionManager.refreshAll()
            applyPendingRoute()
        }
        .onChange(of: homeController.pendingSection) { _, _ in
            applyPendingRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLogs)) { _ in
            selectedSection = .logs
            closeSettings()
        }
        .onDisappear {
            store.stopRefreshing()
            libraryStore.stop()
            captureLibraryStore.stop()
        }
        .task {
            await refreshOperationalSnapshotsLoop()
        }
    }

    private var sidebar: some View {
        ManagedResizableSidebar(
            isCompact: $railCompact,
            labelWidth: $navigationSidebarLabelWidth,
            selection: sidebarSelection,
            entries: AgentHomeShellSection.sidebarEntries,
            accent: AgentTheme.accent,
            allCaps: false,
            tooltipState: sidebarTooltipState,
            isScopeTheme: true,
            handleTint: ScopeInk.primary,
            railHeader: { brandMark },
            labelHeader: { brandWordmark },
            footer: { sidebarFooter }
        )
    }

    private var sidebarSelection: Binding<AgentHomeShellSection?> {
        Binding(
            get: { homeController.isShowingSettings ? nil : selectedSection },
            set: { next in
                guard let next else { return }
                if next == .more {
                    presentOverflowMenu()
                } else {
                    selectSection(next)
                }
            }
        )
    }

    private var navigationSidebarWidth: CGFloat {
        SidebarLayout.leadingInset
            + SidebarLayout.railWidth
            + (railCompact ? 0 : CGFloat(max(100, min(220, navigationSidebarLabelWidth))))
    }

    /// The JetBrains Mono "T" from the Talkie logo in its amber callout box.
    /// `ScopeType.mono` resolves the real bundled font (registered at launch)
    /// instead of SF Mono. Amber is the shared Talkie brand cue; interaction
    /// inside Agent Home uses the cooler Agent signal color.
    private var brandMark: some View {
        Text("t")
            .font(ScopeType.mono(size: OpsSize.base, weight: .bold))
            .foregroundStyle(OpsInk.bg)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                    .fill(AgentTheme.brandAccent)
            )
    }

    private var brandWordmark: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Talkie")
                .font(OpsType.ui(OpsSize.base, weight: .semibold))
                .foregroundStyle(OpsInk.ink)
                .lineLimit(1)

            Text("Agent Home")
                .font(OpsType.mono(OpsSize.micro, weight: .medium))
                .foregroundStyle(OpsInk.dim)
                .textCase(.uppercase)
                .tracking(0.9)
                .lineLimit(1)
        }
    }

    /// Rail-width gear — the canonical Sidebar footer is a rail-slot icon.
    /// Runtime/permission warnings already surface in the status bar.
    private var sidebarFooter: some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape")
                .font(OpsType.ui(OpsSize.base, weight: .medium))
                .foregroundStyle(homeController.isShowingSettings ? AgentTheme.accent : OpsInk.muted)
                .frame(width: SidebarLayout.railWidth, height: SidebarLayout.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open TalkieAgent settings")
    }

    @ViewBuilder
    private var content: some View {
        if homeController.isShowingSettings {
            // Secondary nav: settings section rail + pane, appended to the right of the
            // primary Agent Home rail (primary nav stays visible).
            SettingsView(onClose: closeSettings)
        } else {
            runtimeContent
        }
    }

    private func openSettings() {
        homeController.isShowingSettings = true
    }

    private func closeSettings() {
        homeController.isShowingSettings = false
    }

    private func selectSection(_ section: AgentHomeShellSection) {
        selectedSection = section
        if section == .library {
            libraryFilter = .all
        }
        closeSettings()   // primary nav stays live; selecting it exits settings
    }

    private func collapseInspectorIfNeeded(width: CGFloat) {
        guard width < Self.inspectorAutoCollapseWidth, !inspectorCollapsed else { return }
        inspectorCollapsed = true
    }

    /// Honor a deep-link requested by an external entry point (status-bar
    /// menu, XPC) — navigate to the routed tab, then clear the request.
    private func applyPendingRoute() {
        guard let route = homeController.pendingSection else { return }
        selectedSection = route.shellSection
        if let filter = route.libraryFilter {
            libraryFilter = filter
        }
        closeSettings()
        homeController.pendingSection = nil
    }

    /// Pop the "…" overflow flyout listing the demoted, soon-to-retire
    /// sections. Selecting one navigates to it (and exits settings).
    private func presentOverflowMenu() {
        overflowMenu.present(
            items: AgentHomeShellSection.overflowSections.map { section in
                AgentRailOverflowMenu.Item(title: section.title, systemImage: section.icon) {
                    selectSection(section)
                }
            }
        )
    }

    @ViewBuilder
    private var runtimeContent: some View {
        switch selectedSection {
        case .conversations:
            // The conversation surface stands on its own — no top status strip.
            AgentHomeView(
                onDismiss: onDismiss,
                onOpenSettings: openSettings
            )
        case .more:
            // Sentinel — never selected (the overflow pops a menu instead).
            Color.clear
        case .home:
            AgentHomeOverviewPage(
                store: store,
                settings: settings,
                permissionManager: permissionManager,
                serverStatus: serverStatus,
                traySnapshot: traySnapshot,
                dictationCount: libraryStore.summary.dictations,
                storageSize: storageSize,
                librarySummary: libraryStore.summary,
                libraryItems: libraryStore.items,
                onSelect: selectSection,
                onOpenSettings: openSettings
            )
        case .library:
            AgentHomeLibraryPage(
                store: libraryFilter == .captures ? captureLibraryStore : libraryStore,
                filter: libraryFilter,
                onOpenSettings: openSettings
            )
        case .capture:
            AgentHomeCapturePage(
                settings: settings,
                permissionManager: permissionManager,
                traySnapshot: traySnapshot,
                onOpenSettings: openSettings
            )
        case .tray:
            AgentHomeTrayPage(
                traySnapshot: traySnapshot,
                libraryCount: libraryStore.summary.total,
                storageSize: storageSize,
                onOpenSettings: openSettings
            )
        case .dictation:
            AgentHomeDictationPage(
                settings: settings,
                dictationCount: libraryStore.summary.dictations,
                storageSize: storageSize,
                onOpenSettings: openSettings
            )
        case .overlays:
            AgentHomeOverlaysPage(
                settings: settings,
                onOpenSettings: openSettings
            )
        case .server:
            AgentHomeServerPage(
                runtimePing: store.runtimePing,
                agents: store.agents,
                jobs: store.executorJobs,
                serverStatus: serverStatus,
                onOpenSettings: openSettings
            )
        case .permissions:
            AgentHomePermissionsPage(
                permissionManager: permissionManager,
                onOpenSettings: openSettings
            )
        case .logs:
            AgentHomeLogsConsolePage()
        case .assistant:
            AgentHomeAssistantPage(
                onDismiss: onDismiss,
                onOpenSettings: openSettings
            )
        }
    }

    private var inspector: some View {
        OpsInspector(isCollapsed: $inspectorCollapsed) {
            VStack(alignment: .leading, spacing: 2) {
                OpsSectionLabel("Inspector")
                Text(selectedSection.title)
                    .font(OpsType.ui(OpsSize.md, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)
                    .lineLimit(1)
            }
        } content: {
            AgentHomeInspectorContent(
                selectedSection: selectedSection,
                runtimePing: store.runtimePing,
                agents: store.agents,
                activeJobs: store.activeJobs,
                serverStatus: serverStatus,
                permissionManager: permissionManager,
                settings: settings,
                traySnapshot: traySnapshot,
                librarySummary: libraryStore.summary,
                lastOperationalRefresh: lastOperationalRefresh,
                onSelect: selectSection,
                onOpenSettings: openSettings
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Text("TALKIE AGENT ·")
                .font(OpsType.mono(9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AgentHomeCommandPalette.muted)

            Text(statusBarHealthLabel.uppercased())
                .font(OpsType.mono(9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(statusBarHealthTint)

            if shouldSurfaceServerStatus {
                OpsBadge(statusBarServerBadgeText, tint: serverTint)
            }

            if !permissionManager.allRequiredGranted {
                OpsBadge("Permissions", tint: OpsInk.statusWarn)
            }

            Spacer(minLength: 0)

            // Build stamp — the running binary's link time. A fresh build moves
            // this; if it's stale, you're looking at an old binary.
            Text("BUILD \(Self.buildStamp)")
                .font(OpsType.mono(8, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(AgentHomeCommandPalette.faint)
                .lineLimit(1)
                .help("Link time of the running TalkieAgent binary")

        }
        .padding(.horizontal, 14)
        .frame(height: OpsLayout.statusBarHeight)
        .background(AgentHomeCommandPalette.paper)
    }

    /// The running binary's link/modification time — proves which build is live.
    private static let buildStamp: String = {
        let date = (try? Bundle.main.executableURL?
            .resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d HH:mm:ss"
        return date.map(fmt.string(from:)) ?? "unknown"
    }()

    private var statusBarHealthLabel: String {
        guard store.runtimePing != nil else { return "Runtime offline" }
        guard permissionManager.allRequiredGranted else { return "Needs permissions" }
        guard serverStatus.processState == .running, serverStatus.lastHealthCheckOk else { return "Check server" }
        return "Ready"
    }

    private var statusBarHealthTint: Color {
        switch statusBarHealthLabel {
        case "Ready":
            return OpsInk.muted
        case "Needs permissions", "Check server":
            return OpsInk.statusWarn
        default:
            return OpsInk.statusError
        }
    }

    private var shouldSurfaceServerStatus: Bool {
        serverStatus.processState != .running || !serverStatus.lastHealthCheckOk
    }

    private var statusBarServerBadgeText: String {
        if serverStatus.processState == .running {
            return "Server health"
        }
        return "Server \(serverStatus.processState.rawValue)"
    }

    private var serverTint: Color {
        switch serverStatus.processState {
        case .running:
            return serverStatus.lastHealthCheckOk ? OpsInk.statusOk : OpsInk.statusWarn
        case .starting:
            return OpsInk.statusInfo
        case .degraded:
            return OpsInk.statusWarn
        case .error:
            return OpsInk.statusError
        case .stopped:
            return OpsInk.dim
        }
    }

    @MainActor
    private func refreshOperationalSnapshotsLoop() async {
        while !Task.isCancelled {
            await refreshOperationalSnapshots()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    @MainActor
    private func refreshOperationalSnapshots() async {
        serverStatus = TalkieAgentServerSupervisor.shared.currentStatus
        traySnapshot = .empty
        storageSize = await AudioStorage.formattedStorageSizeAsync()
        lastOperationalRefresh = Date()
    }
}

// MARK: - Navigation

private enum AgentHomeShellSection: String, CaseIterable, Hashable {
    // Primary rail
    case home          // dashboard: status + recent history + quick actions
    case library       // presented as "History"
    case conversations
    case permissions
    case logs
    // Overflow trigger — pops the "…" flyout; never renders a page.
    case more
    // Demoted / stop-gap sections (reachable only through the overflow).
    case capture
    case tray
    case dictation
    case overlays
    case server
    case assistant

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "History"
        case .conversations: return "Conversations"
        case .permissions: return "Permissions"
        case .more: return "More"
        case .capture: return "Capture"
        case .tray: return "Tray"
        case .dictation: return "Dictation"
        case .overlays: return "Overlays"
        case .server: return "Server"
        case .logs: return "Logs"
        case .assistant: return "Assistant"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Status & recent history"
        case .library: return "History + media"
        case .conversations: return "Talk to the agent"
        case .permissions: return "macOS access"
        case .more: return "Capture · Dictation · Server..."
        case .capture: return "Context + screen"
        case .tray: return "Live asset ownership"
        case .dictation: return "Mic, model, routing"
        case .overlays: return "Pill + indicator"
        case .server: return "Bridge + agents"
        case .logs: return "Recent activity"
        case .assistant: return "Conversation"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "clock.arrow.circlepath"
        case .conversations: return "bubble.left.and.bubble.right"
        case .permissions: return "lock.shield"
        case .more: return "ellipsis"
        case .capture: return "viewfinder"
        case .tray: return "tray.full"
        case .dictation: return "waveform"
        case .overlays: return "rectangle.inset.topright.filled"
        case .server: return "server.rack"
        case .logs: return "doc.text.magnifyingglass"
        case .assistant: return "bubble.left.and.bubble.right"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "clock.arrow.circlepath"
        case .conversations: return "bubble.left.and.bubble.right.fill"
        case .permissions: return "lock.shield.fill"
        case .more: return "ellipsis"
        case .capture: return "viewfinder.circle.fill"
        case .tray: return "tray.full.fill"
        case .dictation: return "waveform.circle.fill"
        case .overlays: return "rectangle.inset.topright.filled"
        case .server: return "server.rack"
        case .logs: return "doc.text.magnifyingglass"
        case .assistant: return "bubble.left.and.bubble.right.fill"
        }
    }

    /// Sections that hang off the "…" overflow. Kept reachable as a stop-gap;
    /// these pages were never carefully designed and are slated to retire.
    static var overflowSections: [AgentHomeShellSection] {
        [.capture, .dictation, .overlays, .server]
    }

    /// The simplified primary rail: Home · History · Conversations ·
    /// Permissions · Logs, then a single "…" overflow. No group headers;
    /// Settings lives in the footer.
    static var sidebarEntries: [SidebarEntry<AgentHomeShellSection>] {
        func entry(_ id: AgentHomeShellSection) -> SidebarEntry<AgentHomeShellSection> {
            .item(.init(id: id, title: id.title, icon: id.icon, selectedIcon: id.selectedIcon, tooltipLabel: id.subtitle))
        }
        return [
            entry(.home),
            entry(.library),
            entry(.conversations),
            entry(.permissions),
            entry(.logs),
            entry(.more),
        ]
    }
}

// MARK: - Command-center chrome

/// Agent-local materials built on Talkie's Scope chassis. The page substrate
/// and ink hierarchy are shared with Talkie; steel chrome and signal-blue state
/// make the runtime surface identifiable as Agent Home. The live conversation
/// borrows the main app's PEARL instrument treatment so the primary interaction
/// feels fabricated and lifted instead of reading as a flat blue slab.
private enum AgentHomeCommandPalette {
    static let paper = AgentTheme.background
    static let card = AgentTheme.surface
    static let ink = AgentTheme.textPrimary
    static let muted = AgentTheme.textSecondary
    static let faint = AgentTheme.textTertiary
    static let hairline = AgentTheme.border

    static let signal = AgentTheme.accent
    static let signalSoft = AgentTheme.accentSoft

    // Preserve the user's cool structural-rail calibration. The denser icon
    // rail and signal treatment carry the Agent identity.
    static let rail = AgentTheme.backgroundSecondary
    static let railIcon = AgentTheme.textSecondary
    static let railSelected = AgentTheme.accentSoft
    static let wire = AgentInstrumentStyle.surface
    static let wireChrome = AgentInstrumentStyle.commandChrome
    static let wireSignal = AgentInstrumentStyle.action
    static let wireSignalSoft = AgentInstrumentStyle.actionSoft
    static let wireEdge = AgentInstrumentStyle.actionBorder
    static let wireCard = AgentInstrumentStyle.card
    static let wireMuted = AgentInstrumentStyle.mutedText
    static let wireText = AgentInstrumentStyle.text
}

private struct AgentHomeTitlePill: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AgentTheme.brandAccent)
                .frame(width: 5, height: 5)

            Text("TALKIE AGENT")
                .font(OpsType.mono(9, weight: .semibold))
                .tracking(1.9)
                .foregroundStyle(ScopeCanvas.canvas)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Capsule().fill(ScopeInk.primary))
        .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Talkie Agent")
    }
}

private struct AgentHomeCommandRail: View {
    let selection: AgentHomeShellSection
    let settingsSelected: Bool
    let onSelect: (AgentHomeShellSection) -> Void
    let onOpenSettings: () -> Void

    private let sections: [AgentHomeShellSection] = [
        .home,
        .library,
        .conversations,
        .permissions,
        .logs,
        .more,
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "waveform.path.ecg")
                .font(OpsType.ui(OpsSize.base, weight: .medium))
                .foregroundStyle(AgentTheme.brandAccent)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AgentHomeCommandPalette.card.opacity(0.72))
                )
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle()
                .fill(AgentHomeCommandPalette.hairline.opacity(0.72))
                .frame(width: 26, height: 1)
                .padding(.bottom, 8)

            ForEach(sections, id: \.self) { section in
                railButton(section)
            }

            Spacer(minLength: 16)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(OpsType.ui(OpsSize.base, weight: .medium))
                    .foregroundStyle(settingsSelected ? AgentHomeCommandPalette.signal : AgentHomeCommandPalette.railIcon.opacity(0.72))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(settingsSelected ? AgentHomeCommandPalette.railSelected : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .padding(.bottom, 12)
        }
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .background(AgentHomeCommandPalette.rail)
    }

    private func railButton(_ section: AgentHomeShellSection) -> some View {
        let isSelected = !settingsSelected && selection == section
        return Button { onSelect(section) } label: {
            Image(systemName: isSelected ? section.selectedIcon : section.icon)
                .font(OpsType.ui(OpsSize.base, weight: .medium))
                .foregroundStyle(isSelected ? AgentHomeCommandPalette.signal : AgentHomeCommandPalette.railIcon.opacity(0.76))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? AgentHomeCommandPalette.railSelected : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

private extension AgentHomeRoute {
    /// Map an external deep-link target onto the shell's private section enum.
    var shellSection: AgentHomeShellSection {
        switch self {
        case .home: return .home
        case .history, .libraryCaptures: return .library
        case .conversations: return .conversations
        case .permissions: return .permissions
        case .logs: return .logs
        }
    }

    var libraryFilter: AgentHomeLibraryFilter? {
        switch self {
        case .history: return .all
        case .libraryCaptures: return .captures
        case .home, .conversations, .permissions, .logs: return nil
        }
    }
}

// MARK: - Pages

private struct AgentHomeOverviewPage: View {
    @ObservedObject var store: AgentHomeActivityStore
    @ObservedObject var settings: LiveSettings
    @ObservedObject var permissionManager: PermissionManager
    let serverStatus: TalkieAgentServerStatus
    let traySnapshot: AgentLiveTrayAssetSnapshot
    let dictationCount: Int
    let storageSize: String
    let librarySummary: AgentHomeLibraryStore.Summary
    let libraryItems: [TalkieObject]
    let onSelect: (AgentHomeShellSection) -> Void
    let onOpenSettings: () -> Void

    @State private var previewItemID: UUID?
    @State private var showingLibraryPreview = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AgentHomeCommandDashboard(
                    store: store,
                    permissionManager: permissionManager,
                    libraryItems: libraryItems,
                    onSelect: onSelect,
                    onPreview: previewLibraryItem,
                    onOpenSettings: onOpenSettings
                )

                if showingLibraryPreview, let previewItem {
                    AgentHomeLibrarySlideSheet(
                        availableSize: proxy.size,
                        onDismiss: closeLibraryPreview
                    ) {
                        AgentHomeLibraryDetailPane(item: previewItem) { item in
                            AgentHomeTalkieLibraryOpener.open(item)
                        }
                    }
                    .transition(.move(edge: proxy.size.width < 620 ? .bottom : .trailing).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(OpsAnimation.chromeResize, value: showingLibraryPreview)
            .onChange(of: libraryItems) { _, _ in
                reconcileLibraryPreview()
            }
        }
    }

    private var hero: some View {
        OpsCard {
            HStack(alignment: .top, spacing: OpsSpacing.xxxl) {
                VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                    HStack(spacing: OpsSpacing.md) {
                        OpsBadge("TalkieKit", tint: OpsInk.muted)
                        OpsBadge("Agent-owned", tint: OpsInk.muted)
                    }

                    Text("One home for capture, dictation, tray assets, overlays, server health, permissions, and agent work.")
                        .font(OpsType.ui(OpsSize.xl, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)
                        .lineSpacing(3)

                    Text("Agent Home uses TalkieKit console primitives while runtime services stay owned by TalkieAgent.")
                        .font(OpsType.ui(OpsSize.base))
                        .foregroundStyle(OpsInk.muted)
                        .lineSpacing(4)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: OpsSpacing.md) {
                    AgentHomeStatusPill(
                        title: readinessTitle,
                        tint: readinessTint
                    )
                }
            }
        }
    }

    // The Agent Bay — the Home page's runtime "instrument" moment (replaces
    // the old flat stat tiles). Three cells in the agent's own tally:
    // dictations + captures it owns, plus a real day-streak so it reads
    // "live". History deliberately omits the bay.
    private var bay: some View {
        AgentHomeBay(
            runtime: "\(runtimeStateWord) · TALKIE.AGENT",
            runtimeRight: "Local only · No telemetry",
            footer: "· Live · Signal Path · Local",
            stats: [
                .init(value: ScopeType.statCount(librarySummary.dictations), label: "Dictations"),
                .init(value: ScopeType.statCount(librarySummary.captures), label: "Captures"),
                .init(value: ScopeType.statCount(dayStreak), label: "Day Streak"),
            ]
        )
    }

    private var runtimeStateWord: String {
        store.runtimePing != nil ? "Running" : "Offline"
    }

    private var dayStreak: Int {
        AgentHomeStreak.current(from: libraryItems)
    }

    private var ownership: some View {
        OpsCard {
            VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                AgentHomeSectionHeader(
                    icon: "arrow.left.arrow.right",
                    title: "Ownership boundary",
                    subtitle: "The new split is explicit and visible."
                )

                AgentHomeKeyValueStack {
                    OpsKVRow("Live tray/capture", value: "TalkieAgent owns")
                    OpsKVRow("Durable media", value: "Talkie view/edit/save")
                    OpsKVRow("Agent → Talkie fetch", value: "Removed", valueColor: OpsInk.statusOk)
                    OpsKVRow("Shared settings", value: "Allowlist only")
                }
            }
        }
    }

    private var libraryPreview: some View {
        let visualCaptures = recentVisualCaptureItems

        return OpsCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: OpsSpacing.xl) {
                    AgentHomeSectionHeader(
                        icon: "clock.arrow.circlepath",
                        title: "Library",
                        subtitle: "Latest useful work across dictations, captures, memos, notes, and selections."
                    )

                    Spacer(minLength: 0)

                    OpsButton("Open Library", icon: "arrow.right", style: .ghost) {
                        onSelect(.library)
                    }
                }
                .padding(OpsSpacing.xxl)

                OpsDivider(color: OpsHairline.subtle)

                if recentLibraryItems.isEmpty {
                    AgentHomeEmptyInset(
                        title: "No library items yet",
                        detail: "New dictations, screenshots, clips, memos, notes, and selections will appear here."
                    )
                    .padding(OpsSpacing.xxl)
                } else {
                    if !visualCaptures.isEmpty {
                        AgentHomeCapturePreviewStrip(
                            items: visualCaptures,
                            selectedID: showingLibraryPreview ? previewItemID : nil,
                            onSelect: previewLibraryItem
                        )

                        OpsDivider(color: OpsHairline.subtle)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recentLibraryItems) { item in
                            HStack(alignment: .center, spacing: 0) {
                                ScopeLibraryRow(
                                    recording: item,
                                    isSelected: showingLibraryPreview && previewItemID == item.id,
                                    onSelect: { previewLibraryItem(item) }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)

                                OpsButton("Open in Talkie", icon: "arrow.up.forward.app", style: .ghost) {
                                    AgentHomeTalkieLibraryOpener.open(item)
                                }
                                .padding(.trailing, OpsSpacing.xl)
                            }
                            .overlay(alignment: .top) {
                                if item.id != recentLibraryItems.first?.id {
                                    ScopeRule(.row)
                                }
                            }
                        }
                    }
                    .background(ScopeCanvas.canvas)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shortcuts: some View {
        OpsCard {
            VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                AgentHomeSectionHeader(
                    icon: "square.grid.2x2",
                    title: "Quick routes",
                    subtitle: "Jump to the runtime pane you need."
                )

                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.md) {
                    AgentHomeRouteButton(section: .conversations, onSelect: onSelect)
                    AgentHomeRouteButton(section: .library, onSelect: onSelect)
                    AgentHomeRouteButton(section: .permissions, onSelect: onSelect)
                    AgentHomeRouteButton(section: .logs, onSelect: onSelect)
                }

                HStack(spacing: OpsSpacing.md) {
                    // Launch the sibling Talkie app — amber ties it to the brand
                    // mark so it reads as "leave to the main app", distinct from
                    // the in-app shared-settings route beside it.
                    OpsButton("Open Talkie", icon: "arrow.up.forward.app", style: .primary(.amber)) {
                        TalkieAppOpener.openApp()
                    }
                    OpsButton("Open shared settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var availableAgentCount: Int {
        store.agents.filter(\.isAvailable).count
    }

    private var libraryDetail: String {
        "\(librarySummary.memos) memos / \(librarySummary.dictations) dictations / \(librarySummary.captures) captures"
    }

    private var previewItem: TalkieObject? {
        guard let previewItemID else { return nil }
        return libraryItems.first { $0.id == previewItemID }
    }

    private var recentLibraryItems: [TalkieObject] {
        Array(libraryItems.prefix(6))
    }

    private var recentVisualCaptureItems: [TalkieObject] {
        Array(
            libraryItems
                .lazy
                .filter(\.agentHomeHasVisualPreview)
                .prefix(5)
        )
    }

    private func previewLibraryItem(_ item: TalkieObject) {
        previewItemID = item.id
        showingLibraryPreview = true
    }

    private func closeLibraryPreview() {
        showingLibraryPreview = false
    }

    private func reconcileLibraryPreview() {
        guard previewItemID != nil, previewItem == nil else { return }
        previewItemID = nil
        showingLibraryPreview = false
    }

    private var serverTint: Color {
        switch serverStatus.processState {
        case .running:
            return serverStatus.lastHealthCheckOk ? OpsInk.statusOk : OpsInk.statusWarn
        case .starting:
            return OpsInk.statusInfo
        case .degraded:
            return OpsInk.statusWarn
        case .error:
            return OpsInk.statusError
        case .stopped:
            return OpsInk.dim
        }
    }

    private var readinessTitle: String {
        guard store.runtimePing != nil else { return "Runtime offline" }
        guard permissionManager.allRequiredGranted else { return "Needs permissions" }
        guard serverStatus.processState == .running, serverStatus.lastHealthCheckOk else { return "Check server" }
        return "Ready"
    }

    private var readinessTint: Color {
        switch readinessTitle {
        case "Ready":
            return OpsInk.muted
        case "Needs permissions", "Check server":
            return OpsInk.statusWarn
        default:
            return OpsInk.statusError
        }
    }
}

// MARK: - Home command center

private struct AgentHomeCommandDashboard: View {
    @ObservedObject var store: AgentHomeActivityStore
    @ObservedObject var permissionManager: PermissionManager
    let libraryItems: [TalkieObject]
    let onSelect: (AgentHomeShellSection) -> Void
    let onPreview: (TalkieObject) -> Void
    let onOpenSettings: () -> Void

    @StateObject private var voiceCapture = AgentHomeVoiceCapture()
    @State private var prompt = ""

    private var wireJobs: [AgentHomeExecutorJob] {
        Array(store.executorJobs.sorted { $0.updatedDate < $1.updatedDate }.suffix(4))
    }

    private var failedJobs: [AgentHomeExecutorJob] {
        Array(store.executorJobs.filter { $0.status == .failed }.prefix(2))
    }

    private var completedJobs: [AgentHomeExecutorJob] {
        Array(
            store.executorJobs
                .filter { job in
                    job.status == .done
                        && (job.spokenSummary?.agentHomeTrimmed.isEmpty == false
                            || job.output?.agentHomeTrimmed.isEmpty == false)
                }
                .prefix(3)
        )
    }

    private var missingPermissions: [PermissionType] {
        PermissionType.allCases.filter { permissionManager.status(for: $0) != .granted }
    }

    private var recentCaptures: [TalkieObject] {
        Array(libraryItems.lazy.filter(\.agentHomeHasVisualPreview).prefix(3))
    }

    private var recentDictations: [TalkieObject] {
        Array(libraryItems.lazy.filter(\.isDictation).prefix(5))
    }

    private var needsCount: Int {
        missingPermissions.count + failedJobs.count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    AgentHomeCommandSectionHeader(
                        title: "Agent Chat",
                        detail: wireSectionDetail,
                        trailingLabel: "Conversations",
                        tint: AgentHomeCommandPalette.wireSignal,
                        onTrailing: { onSelect(.conversations) }
                    )

                    wire
                }
                recentCapturesSection
                recentDictationsSection
                footerActions
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 26)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AgentHomeCommandPalette.paper)
        .onDisappear {
            voiceCapture.cancel()
        }
    }

    private var wire: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PhosphorDot(
                    color: store.runtimePing == nil
                        ? AgentHomeCommandPalette.wireMuted
                        : AgentHomeCommandPalette.wireSignal,
                    size: 5
                )

                Text(wireRailLabel)
                    .font(OpsType.mono(9, weight: .semibold))
                    .tracking(1.35)
                    .foregroundStyle(AgentHomeCommandPalette.wireMuted)

                Spacer(minLength: 0)

                Text("NO TELEMETRY")
                    .font(OpsType.mono(9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(AgentHomeCommandPalette.wireMuted)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(AgentHomeCommandPalette.wireChrome)

            Rectangle()
                .fill(AgentHomeCommandPalette.wireEdge)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if wireJobs.isEmpty {
                        AgentHomeWireEmptyState(runtimeOnline: store.runtimePing != nil)
                    } else {
                        ForEach(wireJobs) { job in
                            AgentHomeWireJobRow(job: job)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .frame(minHeight: 210, maxHeight: 330)

            Rectangle()
                .fill(AgentHomeCommandPalette.wireEdge)
                .frame(height: 1)

            composer
                .padding(12)
                .background(AgentHomeCommandPalette.wireChrome)
        }
        .background {
            ZStack {
                AgentHomeCommandPalette.wire

                RadialGradient(
                    colors: [
                        AgentHomeCommandPalette.wireSignal.opacity(0.095),
                        AgentHomeCommandPalette.wireSignal.opacity(0.035),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 520
                )

                GraticuleBackground(
                    pitch: 32,
                    color: AgentHomeCommandPalette.wireSignal.opacity(0.075),
                    opacity: 0.26
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AgentHomeCommandPalette.wireEdge, lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 7)
    }

    private var wireSectionDetail: String {
        if wireJobs.isEmpty {
            return store.runtimePing == nil ? "offline" : "standing by"
        }
        return "\(wireJobs.count) recent"
    }

    private var wireRailLabel: String {
        store.runtimePing == nil
            ? "TALKIE.AGENT · CHANNEL OFFLINE"
            : "TALKIE.AGENT · LOCAL LIVE WIRE"
    }

    private var composer: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .leading) {
                if prompt.isEmpty {
                    Text("Message your agent…")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AgentHomeCommandPalette.wireMuted.opacity(0.68))
                        .allowsHitTesting(false)
                }

                TextField("", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AgentHomeCommandPalette.wireText)
                    .submitLabel(.send)
                    .onSubmit { submit() }
                    .disabled(store.isInvokingAgent || voiceCapture.phase != .idle)
            }

            if voiceCapture.phase == .recording {
                Text(voiceCapture.formattedElapsed)
                    .font(OpsType.mono(9, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.wireSignal)
            } else if voiceCapture.phase == .processing {
                Text("TRANSCRIBING")
                    .font(OpsType.mono(9, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AgentHomeCommandPalette.wireSignal)
            }

            Button(action: toggleVoiceCapture) {
                Image(systemName: voiceCapture.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(OpsType.ui(12, weight: .semibold))
                    .foregroundStyle(voiceCapture.phase == .recording ? Color.white : AgentHomeCommandPalette.wireSignal)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(
                            voiceCapture.phase == .recording
                                ? AgentHomeCommandPalette.wireSignal
                                : AgentHomeCommandPalette.wireSignalSoft
                        )
                    )
                    .overlay(Circle().stroke(AgentHomeCommandPalette.wireSignal.opacity(0.36), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: .option)
            .disabled(store.isInvokingAgent || voiceCapture.phase == .processing)
            .help(voiceCapture.phase == .recording ? "Stop and send" : "Talk to the agent")

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(OpsType.ui(12, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : AgentHomeCommandPalette.railIcon.opacity(0.55))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(
                            canSend
                                ? AgentHomeCommandPalette.wireSignal
                                : AgentHomeCommandPalette.paper.opacity(0.75)
                        )
                    )
                    .overlay(
                        Circle().stroke(
                            canSend
                                ? AgentHomeCommandPalette.wireSignal
                                : AgentHomeCommandPalette.hairline.opacity(0.82),
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send message")
        }
        .padding(.leading, 13)
        .padding(.trailing, 5)
        .frame(height: 40)
        .background(AgentHomeCommandPalette.wireCard.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AgentHomeCommandPalette.wireEdge.opacity(0.82), lineWidth: 1)
        )
    }

    private var needsYou: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHomeCommandSectionHeader(
                title: "Needs You",
                detail: needsCount == 0 ? "clear" : "\(needsCount) waiting"
            )

            if needsCount == 0 {
                AgentHomeCommandEmptyBand(
                    icon: "checkmark.circle",
                    title: "Nothing needs your attention",
                    detail: "The agent can keep working without an approval or permission change."
                )
            } else {
                VStack(spacing: 9) {
                    ForEach(missingPermissions) { permission in
                        AgentHomeNeedsPermissionRow(
                            permission: permission,
                            status: permissionManager.status(for: permission),
                            onOpen: { permissionManager.handleRequest(for: permission) }
                        )
                    }

                    ForEach(failedJobs) { job in
                        AgentHomeNeedsJobRow(job: job) {
                            onSelect(.conversations)
                        }
                    }
                }
            }
        }
    }

    private var readyForYou: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHomeCommandSectionHeader(
                title: "Ready for You",
                detail: completedJobs.isEmpty ? nil : "\(completedJobs.count) finished",
                trailingLabel: "Everything the agent made",
                onTrailing: { onSelect(.conversations) }
            )

            if completedJobs.isEmpty {
                AgentHomeCommandEmptyBand(
                    icon: "sparkles",
                    title: "No finished agent work yet",
                    detail: "Completed requests will collect here for a quick review."
                )
            } else {
                LazyVGrid(columns: AgentHomeCommandGrid.three, spacing: 14) {
                    ForEach(completedJobs) { job in
                        AgentHomeReadyCard(job: job) {
                            onSelect(.conversations)
                        }
                    }
                }
            }
        }
    }

    private var recentCapturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHomeCommandSectionHeader(
                title: "Recent Captures",
                trailingLabel: "Open Library",
                onTrailing: { onSelect(.library) }
            )

            if recentCaptures.isEmpty {
                AgentHomeCommandEmptyBand(
                    icon: "viewfinder",
                    title: "No recent captures",
                    detail: "Screenshots and clips will appear here as soon as Talkie records them."
                )
            } else {
                LazyVGrid(columns: AgentHomeCommandGrid.three, spacing: 14) {
                    ForEach(recentCaptures) { item in
                        AgentHomeCommandCaptureCard(item: item) {
                            onPreview(item)
                        }
                    }
                }
            }
        }
    }

    private var recentDictationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHomeCommandSectionHeader(
                title: "Dictations",
                detail: recentDictations.isEmpty ? nil : "\(recentDictations.count) recent",
                trailingLabel: "Open History",
                onTrailing: { onSelect(.library) }
            )

            if recentDictations.isEmpty {
                AgentHomeCommandEmptyBand(
                    icon: "waveform",
                    title: "No recent dictations",
                    detail: "New Talkie Agent dictations will appear here for quick review."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recentDictations) { item in
                        AgentHomeCommandDictationRow(item: item) {
                            onPreview(item)
                        }

                        if item.id != recentDictations.last?.id {
                            Rectangle()
                                .fill(AgentHomeCommandPalette.hairline.opacity(0.60))
                                .frame(height: 1)
                                .padding(.leading, 58)
                        }
                    }
                }
                .background(AgentHomeCommandPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AgentHomeCommandPalette.hairline.opacity(0.68), lineWidth: 1)
                )
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 9) {
            AgentHomeCommandFooterButton("Conversations", icon: "bubble.left.and.bubble.right") {
                onSelect(.conversations)
            }
            AgentHomeCommandFooterButton("History", icon: "clock.arrow.circlepath") {
                onSelect(.library)
            }
            AgentHomeCommandFooterButton("Permissions", icon: "lock.shield") {
                onSelect(.permissions)
            }
            AgentHomeCommandFooterButton("Logs", icon: "doc.text") {
                onSelect(.logs)
            }

            Spacer(minLength: 12)

            AgentHomeCommandFooterButton("Open Talkie", icon: "arrow.up.forward.app", prominent: true) {
                TalkieAppOpener.openApp()
            }
            AgentHomeCommandFooterButton("Settings", icon: "gearshape", iconOnly: true, action: onOpenSettings)
        }
    }

    private var canSend: Bool {
        !store.isInvokingAgent && voiceCapture.phase == .idle
    }

    private func submit() {
        submit(prompt)
    }

    private func submit(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isInvokingAgent else { return }
        prompt = ""

        Task {
            await store.invokeAgent(text: text)
        }
    }

    private func toggleVoiceCapture() {
        switch voiceCapture.phase {
        case .idle:
            voiceCapture.start()
        case .recording:
            voiceCapture.stopAndTranscribe(
                onTranscript: submit,
                onFinish: {}
            )
        case .processing:
            break
        }
    }
}

private enum AgentHomeCommandGrid {
    static let three = [
        GridItem(.flexible(minimum: 180), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 180), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 180), spacing: 14, alignment: .top),
    ]
}

private struct AgentHomeWireEmptyState: View {
    let runtimeOnline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runtimeOnline ? "STANDING BY" : "RUNTIME OFFLINE")
                .font(OpsType.mono(10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(AgentHomeCommandPalette.wireSignal)

            Text(runtimeOnline
                 ? "Send a message or hold the mic to start a new turn."
                 : "Start the local runtime to send work through the Wire.")
                .font(OpsType.ui(13))
                .foregroundStyle(AgentHomeCommandPalette.wireText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AgentHomeCommandPalette.wireCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.wireEdge.opacity(0.62), lineWidth: 1)
        )
    }
}

private struct AgentHomeWireJobRow: View {
    let job: AgentHomeExecutorJob

    private var response: String? {
        if let summary = job.spokenSummary?.agentHomeTrimmed, !summary.isEmpty {
            return summary
        }
        if let output = job.output?.agentHomeTrimmed, !output.isEmpty {
            return output
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text(job.updatedDate, format: .dateTime.hour().minute())
                    .font(OpsType.mono(9, weight: .medium))
                    .foregroundStyle(AgentHomeCommandPalette.wireMuted)

                Text(job.source == "agent-home" ? "HOME" : "VOICE")
                    .font(OpsType.mono(8, weight: .semibold))
                    .tracking(0.95)
                    .foregroundStyle(AgentHomeCommandPalette.wireMuted.opacity(0.82))

                Spacer(minLength: 8)

                Circle()
                    .fill(statusTint)
                    .frame(width: 5, height: 5)

                Text(job.status.title.uppercased())
                    .font(OpsType.mono(8, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(statusTint)
            }

            AgentHomeWireSpeechGroup(
                label: "You",
                text: job.title,
                emphasized: false
            )

            if let response {
                AgentHomeWireSpeechGroup(
                    label: "Talkie",
                    text: response,
                    emphasized: true
                )
            } else if job.status.isActive {
                HStack(spacing: 9) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(AgentHomeCommandPalette.wireSignal)
                        .frame(maxWidth: 150)

                    Text(job.status == .waiting ? "WAKING" : "WORKING")
                        .font(OpsType.mono(8, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(AgentHomeCommandPalette.wireMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AgentHomeCommandPalette.wireSignalSoft)
                )
            } else if let error = job.error?.agentHomeTrimmed, !error.isEmpty {
                Text(error)
                    .font(OpsType.ui(12))
                    .foregroundStyle(Color.red.opacity(0.78))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.055))
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AgentHomeCommandPalette.wireCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.wireEdge.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 2, y: 1)
    }

    private var statusTint: Color {
        switch job.status {
        case .waiting, .running: return AgentHomeCommandPalette.wireSignal
        case .done: return Color.green.opacity(0.78)
        case .failed: return Color.red.opacity(0.78)
        }
    }
}

private struct AgentHomeWireSpeechGroup: View {
    let label: String
    let text: String
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if emphasized {
                    Circle()
                        .fill(AgentHomeCommandPalette.wireSignal)
                        .frame(width: 4, height: 4)
                }

                Text(label.uppercased())
                    .font(OpsType.mono(8, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(
                        emphasized
                            ? AgentHomeCommandPalette.wireSignal
                            : AgentHomeCommandPalette.wireMuted
                    )
            }

            Text(text)
                .font(.system(size: 13, weight: emphasized ? .regular : .medium))
                .foregroundStyle(AgentHomeCommandPalette.wireText.opacity(emphasized ? 0.84 : 1))
                .lineSpacing(3)
                .lineLimit(emphasized ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, emphasized ? 12 : 0)
        .padding(.vertical, emphasized ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if emphasized {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AgentHomeCommandPalette.wireSignalSoft)
            }
        }
    }
}

private struct AgentHomeCommandSectionHeader: View {
    let title: String
    var detail: String? = nil
    var trailingLabel: String? = nil
    var tint: Color = AgentHomeCommandPalette.signal
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(tint)
                .frame(width: 5, height: 5)

            Text(title.uppercased())
                .font(OpsType.mono(10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(AgentHomeCommandPalette.ink)

            if let detail {
                Text(detail.uppercased())
                    .font(OpsType.mono(9, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(AgentHomeCommandPalette.faint)
            }

            Rectangle()
                .fill(AgentHomeCommandPalette.hairline.opacity(0.72))
                .frame(height: 1)

            if let trailingLabel, let onTrailing {
                Button(action: onTrailing) {
                    HStack(spacing: 5) {
                        Text(trailingLabel.uppercased())
                        Image(systemName: "arrow.right")
                    }
                    .font(OpsType.mono(8, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 18)
    }
}

private struct AgentHomeCommandEmptyBand: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(OpsType.ui(14, weight: .medium))
                .foregroundStyle(AgentHomeCommandPalette.signal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OpsType.ui(13, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.ink)
                Text(detail)
                    .font(OpsType.ui(11))
                    .foregroundStyle(AgentHomeCommandPalette.muted)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(AgentHomeCommandPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.hairline.opacity(0.64), lineWidth: 1)
        )
    }
}

private struct AgentHomeNeedsPermissionRow: View {
    let permission: PermissionType
    let status: PermissionStatus
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: permission.icon)
                .font(OpsType.ui(14, weight: .medium))
                .foregroundStyle(AgentHomeCommandPalette.signal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(permission.title) needs access")
                    .font(OpsType.ui(13, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.ink)

                Text("\(status.label.uppercased()) · \(permission.shortDescription.uppercased())")
                    .font(OpsType.mono(8, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(AgentHomeCommandPalette.faint)
            }

            Spacer(minLength: 12)

            AgentHomeCommandActionButton("Open permissions", action: onOpen)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(AgentHomeCommandPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.hairline.opacity(0.64), lineWidth: 1)
        )
    }
}

private struct AgentHomeNeedsJobRow: View {
    let job: AgentHomeExecutorJob
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "exclamationmark.triangle")
                .font(OpsType.ui(14, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.72))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(OpsType.ui(13, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.ink)
                    .lineLimit(1)
                Text((job.error ?? "The agent could not finish this request.").uppercased())
                    .font(OpsType.mono(8, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(AgentHomeCommandPalette.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
            AgentHomeCommandActionButton("Review", action: onOpen)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(AgentHomeCommandPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.hairline.opacity(0.64), lineWidth: 1)
        )
    }
}

private struct AgentHomeReadyCard: View {
    let job: AgentHomeExecutorJob
    let onOpen: () -> Void

    private var preview: String {
        if let summary = job.spokenSummary?.agentHomeTrimmed, !summary.isEmpty {
            return summary
        }
        if let output = job.output?.agentHomeTrimmed, !output.isEmpty {
            return output
        }
        return "Finished."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentHomeReadyCardGraphic(seed: job.id.hashValue)
                .frame(height: 78)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            Rectangle()
                .fill(AgentHomeCommandPalette.hairline.opacity(0.55))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(OpsType.ui(13, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.ink)
                    .lineLimit(1)

                Text(preview)
                    .font(OpsType.ui(11))
                    .foregroundStyle(AgentHomeCommandPalette.muted)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text("DONE")
                    Text("·")
                    Text(AgentHomeRelative.shortLabel(for: job.updatedDate).uppercased())
                    Spacer(minLength: 0)
                    Button("OPEN", action: onOpen)
                        .buttonStyle(.plain)
                        .foregroundStyle(AgentHomeCommandPalette.ink)
                }
                .font(OpsType.mono(8, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(AgentHomeCommandPalette.faint)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(AgentHomeCommandPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentHomeCommandPalette.hairline.opacity(0.68), lineWidth: 1)
        )
    }
}

private struct AgentHomeReadyCardGraphic: View {
    let seed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 8) {
                    if seed.isMultiple(of: 2) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(index < 2 ? AgentHomeCommandPalette.signal : AgentHomeCommandPalette.hairline)
                            .frame(width: 9, height: 9)
                    }
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == 2 ? AgentHomeCommandPalette.signalSoft : AgentHomeCommandPalette.hairline.opacity(0.64))
                        .frame(width: graphicWidth(for: index), height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func graphicWidth(for index: Int) -> CGFloat {
        switch abs(seed + index) % 4 {
        case 0: return 112
        case 1: return 152
        case 2: return 92
        default: return 132
        }
    }
}

private struct AgentHomeCommandDictationRow: View {
    let item: TalkieObject
    let onPreview: () -> Void

    private var sourceLabel: String {
        let appName = item.appContext?.name?.agentHomeTrimmed ?? ""
        return appName.isEmpty ? item.source.displayName : appName
    }

    var body: some View {
        Button(action: onPreview) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(OpsType.ui(13, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.signal)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AgentHomeCommandPalette.signal.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.agentHomeDisplayTitle)
                        .font(OpsType.ui(13, weight: .regular))
                        .foregroundStyle(AgentHomeCommandPalette.ink)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(sourceLabel.uppercased())
                        Text("·")
                        Text(AgentHomeRelative.shortLabel(for: item.createdAt).uppercased())
                        if item.duration > 0 {
                            Text("·")
                            Text(Self.formatDuration(item.duration))
                        }
                    }
                    .font(OpsType.mono(8, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(AgentHomeCommandPalette.faint)
                }

                Spacer(minLength: 12)

                Text("PREVIEW")
                    .font(OpsType.mono(8, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(AgentHomeCommandPalette.signal)

                Image(systemName: "chevron.right")
                    .font(OpsType.ui(9, weight: .semibold))
                    .foregroundStyle(AgentHomeCommandPalette.faint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remainingSeconds = total % 60
        let paddedSeconds = remainingSeconds < 10 ? "0\(remainingSeconds)" : "\(remainingSeconds)"
        return "\(minutes):\(paddedSeconds)"
    }
}

private struct AgentHomeCommandCaptureCard: View {
    let item: TalkieObject
    let onOpen: () -> Void

    private var media: CaptureMediaAsset? {
        if let clip = item.clips.first,
           let url = CaptureMediaFileResolver.clipURL(filename: clip.filename) {
            return .video(url)
        }
        if let context = item.visualContexts.first,
           let url = CaptureMediaFileResolver.visualContextSourceURL(for: context) {
            return .video(url)
        }
        return CaptureMediaFileResolver.primaryMedia(for: item)
    }

    private var sourceLabel: String {
        let appName = item.appContext?.name?.agentHomeTrimmed ?? ""
        return appName.isEmpty ? item.source.displayName : appName
    }

    private var captureDurationLabel: String? {
        guard media?.isVideo == true else { return nil }

        if let durationMs = item.clips.first?.durationMs, durationMs > 0 {
            return Self.formatCaptureDuration(Double(durationMs) / 1_000)
        }
        if let durationMs = item.visualContexts.first?.durationMs, durationMs > 0 {
            return Self.formatCaptureDuration(Double(durationMs) / 1_000)
        }
        if item.duration > 0 {
            return Self.formatCaptureDuration(item.duration)
        }
        return nil
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                AgentHomeMediaPreview(
                    media: media,
                    maxPixelSize: 520,
                    style: .captureCard(durationLabel: captureDurationLabel)
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 118)
                    .clipShape(.rect(topLeadingRadius: 10, topTrailingRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.agentHomeDisplayTitle)
                        .font(ScopeType.display(size: 17, weight: .regular))
                        .foregroundStyle(AgentHomeCommandPalette.ink)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(sourceLabel.uppercased())
                        Text("·")
                        Text(AgentHomeRelative.shortLabel(for: item.createdAt).uppercased())
                    }
                    .font(OpsType.mono(8, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(AgentHomeCommandPalette.faint)
                }
                .padding(14)
            }
            .background(AgentHomeCommandPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AgentHomeCommandPalette.hairline.opacity(0.68), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func formatCaptureDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 {
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours)h\(paddedMinutes)m"
        }
        if total >= 60 {
            return "\(total / 60)m"
        }

        let paddedSeconds = total < 10 ? "0\(total)" : "\(total)"
        return "0:\(paddedSeconds)"
    }
}

private struct AgentHomeCommandActionButton: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(OpsType.ui(11, weight: .semibold))
            .foregroundStyle(AgentHomeCommandPalette.ink)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AgentHomeCommandPalette.hairline.opacity(0.82), lineWidth: 1)
            )
    }
}

private struct AgentHomeCommandFooterButton: View {
    let label: String
    let icon: String
    let prominent: Bool
    let iconOnly: Bool
    let action: () -> Void

    init(
        _ label: String,
        icon: String,
        prominent: Bool = false,
        iconOnly: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.prominent = prominent
        self.iconOnly = iconOnly
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(OpsType.ui(11, weight: .medium))
                if !iconOnly {
                    Text(label)
                        .font(OpsType.ui(11, weight: .medium))
                }
            }
            .foregroundStyle(prominent ? Color.white : AgentHomeCommandPalette.ink)
            .padding(.horizontal, iconOnly ? 9 : 12)
            .frame(height: 34)
            .background(prominent ? AgentHomeCommandPalette.ink : AgentHomeCommandPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(prominent ? .clear : AgentHomeCommandPalette.hairline.opacity(0.75), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(iconOnly ? label : "")
    }
}

private struct AgentHomeCapturePage: View {
    @ObservedObject var settings: LiveSettings
    @ObservedObject var permissionManager: PermissionManager
    let traySnapshot: AgentLiveTrayAssetSnapshot
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Capture", subtitle: "Context capture, screen permissions, and live tray intake.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(
                        title: "Capture feature",
                        value: captureEnabled ? "On" : "Off",
                        detail: "Shared feature flag",
                        icon: "viewfinder",
                        tint: captureEnabled ? OpsInk.statusOk : OpsInk.dim
                    )
                    AgentHomeMetricCard(
                        title: "Context detail",
                        value: settings.contextCaptureDetail.displayName,
                        detail: settings.primaryContextSource.displayName,
                        icon: "text.viewfinder",
                        tint: OpsInk.statusInfo
                    )
                    AgentHomeMetricCard(
                        title: "Screen access",
                        value: permissionManager.screenRecordingStatus.label,
                        detail: "Optional for screenshots",
                        icon: "rectangle.dashed.badge.record",
                        tint: permissionManager.screenRecordingStatus.hudTint
                    )
                    AgentHomeMetricCard(
                        title: "Live assets",
                        value: "\(traySnapshot.totalCount)",
                        detail: "Agent drains eligible assets",
                        icon: "tray.full",
                        tint: traySnapshot.totalCount > 0 ? AgentTheme.accent : OpsInk.muted
                    )
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "camera.metering.matrix",
                            title: "Capture contract",
                            subtitle: "Capture settings can live here because Agent owns live capture execution."
                        )

                        AgentHomeKeyValueStack {
                            OpsKVRow("Context capture", value: settings.contextCaptureDetail.displayName)
                            OpsKVRow("Primary app", value: settings.primaryContextSource.displayName)
                            OpsKVRow("Session allowed", value: settings.contextCaptureSessionAllowed ? "Yes" : "No", valueColor: settings.contextCaptureSessionAllowed ? OpsInk.statusOk : OpsInk.statusWarn)
                            OpsKVRow("Return to origin", value: "Paused", valueColor: OpsInk.statusWarn)
                        }

                        Text("Talkie remains the durable review/edit/save surface; Agent owns the live window, live files, and promotion/drain timing.")
                            .font(OpsType.ui(OpsSize.base))
                            .foregroundStyle(OpsInk.muted)
                            .lineSpacing(4)

                        OpsButton("Open capture settings", icon: "slider.horizontal.3", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }

    private var captureEnabled: Bool {
        if TalkieEnvironment.current == .production {
            return true
        }
        return TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled)
    }
}

private struct AgentHomeTrayPage: View {
    let traySnapshot: AgentLiveTrayAssetSnapshot
    let libraryCount: Int
    let storageSize: String
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Tray", subtitle: "Agent-owned live screenshots and clips, promoted into Talkie durable media.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "Screenshots", value: "\(traySnapshot.screenshotCount)", detail: "\(traySnapshot.pinnedScreenshotCount) pinned", icon: "photo.on.rectangle", tint: OpsInk.statusInfo)
                    AgentHomeMetricCard(title: "Clips", value: "\(traySnapshot.clipCount)", detail: "\(traySnapshot.pinnedClipCount) pinned", icon: "film.stack", tint: AgentTheme.accent)
                    AgentHomeMetricCard(title: "Latest live asset", value: traySnapshot.latestLabel, detail: "Manifest snapshot", icon: "clock.arrow.circlepath", tint: OpsInk.muted)
                    AgentHomeMetricCard(title: "Durable library", value: "\(libraryCount)", detail: "\(storageSize) local audio", icon: "books.vertical", tint: OpsInk.statusOk)
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "externaldrive.badge.timemachine",
                            title: "Live → durable flow",
                            subtitle: "The migration boundary from TLK-027 is now surfaced."
                        )

                        AgentHomeKeyValueStack {
                            OpsKVRow("Live manifest reads", value: "TalkieAgent")
                            OpsKVRow("Promotion", value: "TalkieAgent")
                            OpsKVRow("Drain", value: "TalkieAgent")
                            OpsKVRow("Durable review", value: "Talkie")
                        }

                        Text("Pinned live tray items stay in the live tray. Eligible unpinned assets that overlap a dictation window are promoted and drained by Agent after the durable recording merge.")
                            .font(OpsType.ui(OpsSize.base))
                            .foregroundStyle(OpsInk.muted)
                            .lineSpacing(4)

                        OpsButton("Open settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }
}

private struct AgentHomeDictationPage: View {
    @ObservedObject var settings: LiveSettings
    let dictationCount: Int
    let storageSize: String
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Dictation", subtitle: "TalkieAgent speech stack, model choice, and delivery routing.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "Microphone", value: microphoneLabel, detail: microphoneModeLabel, icon: "mic.fill", tint: OpsInk.statusInfo)
                    AgentHomeMetricCard(title: "Model", value: settings.selectedModelId, detail: "Talkie transcription stack", icon: "waveform.badge.magnifyingglass", tint: AgentTheme.accent)
                    AgentHomeMetricCard(title: "Routing", value: settings.routingMode.displayName, detail: settings.pressEnterAfterPaste ? "Press Enter after paste" : "No auto-submit", icon: "arrow.right.doc.on.clipboard", tint: OpsInk.statusOk)
                    AgentHomeMetricCard(title: "History", value: "\(dictationCount)", detail: "\(storageSize) local audio", icon: "clock.arrow.circlepath", tint: OpsInk.muted)
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "waveform",
                            title: "Shared runtime settings",
                            subtitle: "Agent Home exposes only the shared allowlist."
                        )

                        AgentHomeKeyValueStack {
                            OpsKVRow("Toggle hotkey", value: settings.hotkey.displayString)
                            OpsKVRow("Push-to-talk", value: settings.pttEnabled ? settings.pttHotkey.displayString : "Disabled")
                            OpsKVRow("Segments", value: segmentDurationLabel)
                        }

                        Text("Dictation remains on TalkieAgent's existing speech path. This page exposes shared settings without taking over the audio stack.")
                            .font(OpsType.ui(OpsSize.base))
                            .foregroundStyle(OpsInk.muted)
                            .lineSpacing(4)

                        OpsButton("Open dictation settings", icon: "slider.horizontal.3", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }

    private var microphoneLabel: String {
        switch settings.selectedMicrophoneMode {
        case .systemDefault:
            return "System default"
        case .fixedUID:
            return settings.selectedMicrophoneName ?? "Fixed device"
        }
    }

    private var microphoneModeLabel: String {
        switch settings.selectedMicrophoneMode {
        case .systemDefault: return "Follows macOS"
        case .fixedUID: return "Pinned input"
        }
    }

    private var segmentDurationLabel: String {
        guard settings.segmentDuration > 0 else { return "Disabled" }
        let seconds = Int(settings.segmentDuration)
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}

private struct AgentHomeOverlaysPage: View {
    @ObservedObject var settings: LiveSettings
    let onOpenSettings: () -> Void

    private var hasNotch: Bool { NotchInfo.detect().hasNotch }

    private var notchValue: String {
        guard hasNotch else { return "No notch" }
        return settings.notchOverlayEnabled ? "Enabled" : "Disabled"
    }

    private var notchDetail: String {
        hasNotch ? "MacBook notch overlay" : "No notch on this display"
    }

    private var notchTint: Color {
        guard hasNotch else { return OpsInk.dim }
        return settings.notchOverlayEnabled ? OpsInk.statusOk : OpsInk.dim
    }

    var body: some View {
        AgentHomePageScaffold(title: "Overlays", subtitle: "Live visual feedback owned by Agent at runtime.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "Top overlay", value: settings.effectiveOverlayStyle.displayName, detail: settings.overlayPosition.displayName, icon: "rectangle.inset.topright.filled", tint: AgentTheme.accent)
                    AgentHomeMetricCard(title: "Pill", value: settings.pillEnabled ? "Enabled" : "Disabled", detail: settings.pillPosition.displayName, icon: "capsule.portrait", tint: settings.pillEnabled ? OpsInk.statusOk : OpsInk.dim)
                    AgentHomeMetricCard(title: "All screens", value: settings.pillShowOnAllScreens ? "Yes" : "No", detail: "Floating pill", icon: "display.2", tint: OpsInk.statusInfo)
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "sparkles",
                            title: "Overlay runtime",
                            subtitle: "These settings belong close to Agent because Agent renders the live surfaces."
                        )

                        AgentHomeKeyValueStack {
                            OpsKVRow("Overlay style", value: settings.overlayStyle.displayName)
                            OpsKVRow("Effective style", value: settings.effectiveOverlayStyle.displayName)
                            OpsKVRow("Pill expands", value: settings.pillExpandsDuringRecording ? "During recording" : "Manual")
                            OpsKVRow("MacBook notch", value: "\(notchValue) - \(notchDetail)", valueColor: notchTint)
                            OpsKVRow("Theme", value: settings.visualTheme.displayName)
                        }

                        OpsButton("Open overlay settings", icon: "slider.horizontal.3", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }
}

private struct AgentHomeServerPage: View {
    let runtimePing: AgentRuntimePing?
    let agents: [AgentRuntimeAgentSnapshot]
    let jobs: [AgentHomeExecutorJob]
    let serverStatus: TalkieAgentServerStatus
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Server", subtitle: "Node/Bun bridge, runtime ping, and agent adapters.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "Bridge", value: serverStatus.processState.rawValue, detail: serverStatus.lastHealthCheckOk ? "Healthy" : "Health pending", icon: "server.rack", tint: serverTint)
                    AgentHomeMetricCard(title: "PID", value: serverStatus.pid.map(String.init) ?? "—", detail: uptimeLabel, icon: "number", tint: OpsInk.muted)
                    AgentHomeMetricCard(title: "Runtime", value: runtimePing?.runtimeName ?? "Offline", detail: runtimePing?.runtimeId ?? "No ping", icon: "cpu", tint: runtimePing == nil ? OpsInk.statusError : OpsInk.statusOk)
                    AgentHomeMetricCard(title: "Jobs", value: "\(jobs.count)", detail: "\(jobs.filter { $0.status == .running || $0.status == .waiting }.count) active", icon: "list.bullet.rectangle", tint: AgentTheme.accent)
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "person.2.wave.2",
                            title: "Agent adapters",
                            subtitle: "\(agents.filter(\.isAvailable).count) available of \(agents.count) configured."
                        )

                        if agents.isEmpty {
                            AgentHomeEmptyInset(title: "No agents reported", detail: "The runtime ping has not returned adapter snapshots yet.")
                        } else {
                            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                                ForEach(agents.prefix(6)) { agent in
                                    AgentHomeAgentRow(agent: agent)
                                }
                            }
                        }

                        OpsButton("Open connection settings", icon: "network", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }

    private var serverTint: Color {
        switch serverStatus.processState {
        case .running:
            return serverStatus.lastHealthCheckOk ? OpsInk.statusOk : OpsInk.statusWarn
        case .starting:
            return OpsInk.statusInfo
        case .degraded:
            return OpsInk.statusWarn
        case .error:
            return OpsInk.statusError
        case .stopped:
            return OpsInk.dim
        }
    }

    private var uptimeLabel: String {
        guard let uptime = serverStatus.uptime else { return "Not running" }
        let total = max(0, Int(uptime))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct AgentHomePermissionsPage: View {
    @ObservedObject var permissionManager: PermissionManager
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Permissions", subtitle: "macOS capabilities required by the live Agent runtime.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    ForEach(PermissionType.allCases) { permission in
                        let status = permissionManager.status(for: permission)
                        AgentHomeMetricCard(
                            title: permission.title,
                            value: status.label,
                            detail: permission.isRequired ? "Required" : "Optional",
                            icon: permission.icon,
                            tint: status.hudTint
                        )
                    }
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "lock.shield",
                            title: permissionManager.allRequiredGranted ? "All required permissions granted" : "Permission action needed",
                            subtitle: "Agent can request or route users to the right macOS pane."
                        )

                        VStack(alignment: .leading, spacing: OpsSpacing.md) {
                            ForEach(PermissionType.allCases) { permission in
                                AgentHomePermissionRow(permission: permission, status: permissionManager.status(for: permission)) {
                                    permissionManager.handleRequest(for: permission)
                                }
                            }
                        }

                        OpsButton("Open permissions settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
    }
}

private struct AgentHomeLibraryPage: View {
    private static let compactDetailThreshold: CGFloat = 860
    private static func listWidth(for availableWidth: CGFloat) -> CGFloat {
        min(380, max(340, availableWidth * 0.30))
    }

    @ObservedObject var store: AgentHomeLibraryStore
    let filter: AgentHomeLibraryFilter
    let onOpenSettings: () -> Void

    @State private var selectedID: UUID?
    @State private var isCompactLayout = false
    @State private var showingDetailSheet = false

    var body: some View {
        AgentHomePageScaffold(
            title: filter.title,
            subtitle: filter.subtitle,
            showsHeader: false,
            scrolls: false,
            maxContentWidth: 1_260
        ) {
            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                OpsSectionLabel(filter.eyebrow)

                OpsCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: OpsSpacing.xl) {
                            AgentHomeSectionHeader(
                                icon: "clock.arrow.circlepath",
                                title: filter.title,
                                subtitle: filter.sectionSubtitle
                            )

                            Spacer(minLength: 0)

                            if let selectedItem {
                                OpsButton("Open in Talkie", icon: "arrow.up.forward.app", style: .secondary) {
                                    AgentHomeTalkieLibraryOpener.open(selectedItem)
                                }
                            }

                            OpsButton("Storage", icon: "internaldrive", style: .ghost, action: onOpenSettings)
                        }
                        .padding(OpsSpacing.xxl)

                        OpsDivider(color: OpsHairline.subtle)

                        libraryBody
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { reconcileSelection() }
        .onChange(of: store.items) { _, _ in
            reconcileSelection()
        }
        .scopeLibraryKeyboardNavigation(
            isEnabled: !store.items.isEmpty && store.errorMessage == nil,
            onMoveUp: { moveSelection(by: -1) },
            onMoveDown: { moveSelection(by: 1) }
        )
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.items.isEmpty {
            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading shared Talkie library")
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.errorMessage {
            AgentHomeEmptyInset(title: "Library unavailable", detail: errorMessage)
                .padding(OpsSpacing.xxl)
        } else {
            // Talkie's own library presentation (TalkieKit ScopeLibraryList):
            // date-bucketed, channel-tagged rows on the Scope paper canvas.
            // Same shared-recordings data as before, now visually one with
            // Talkie proper instead of a bespoke Ops table.
            ScopeLibraryList(
                objects: store.items,
                selectedID: selectedID,
                emptyTitle: filter.emptyTitle,
                emptyDetail: filter.emptyDetail,
                onSelect: { item in selectItem(item) }
            )
        }
    }

    private var libraryBody: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < Self.compactDetailThreshold
            let listWidth = Self.listWidth(for: proxy.size.width)
            let dividerWidth: CGFloat = 1
            let detailWidth = max(0, proxy.size.width - listWidth - dividerWidth)

            ZStack(alignment: .topLeading) {
                if compact {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        // The Scope list has a natural scanning width; keep
                        // it compact so the selected item can use the rest.
                        content
                            .frame(width: listWidth)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .clipped()

                        OpsDivider(color: OpsHairline.subtle, axis: .vertical)
                            .frame(width: dividerWidth)

                        AgentHomeLibraryDetailPane(item: selectedItem) { item in
                            AgentHomeTalkieLibraryOpener.open(item)
                        }
                        .frame(width: detailWidth)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }

                if compact, showingDetailSheet, let selectedItem {
                    AgentHomeLibrarySlideSheet(
                        availableSize: proxy.size,
                        onDismiss: closeDetailSheet
                    ) {
                        AgentHomeLibraryDetailPane(item: selectedItem) { item in
                            AgentHomeTalkieLibraryOpener.open(item)
                        }
                    }
                    .transition(.move(edge: proxy.size.width < 620 ? .bottom : .trailing).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(OpsAnimation.chromeResize, value: showingDetailSheet)
            .onAppear {
                updateCompactLayout(compact)
            }
            .onChange(of: compact) { _, newValue in
                updateCompactLayout(newValue)
            }
        }
    }

    private var selectedItem: TalkieObject? {
        guard let selectedID else { return nil }
        return store.items.first { $0.id == selectedID }
    }

    private func reconcileSelection() {
        guard !store.items.isEmpty else {
            selectedID = nil
            closeDetailSheet()
            return
        }

        if let selectedID, store.items.contains(where: { $0.id == selectedID }) {
            return
        }

        selectedID = store.items.first?.id
    }

    private func updateCompactLayout(_ compact: Bool) {
        isCompactLayout = compact
        if !compact {
            closeDetailSheet()
        }
    }

    private func selectItem(_ item: TalkieObject, revealDetail: Bool = true) {
        selectedID = item.id
        guard revealDetail, isCompactLayout else { return }
        showingDetailSheet = true
    }

    private func moveSelection(by offset: Int) {
        guard !store.items.isEmpty else { return }

        let currentIndex = selectedID.flatMap { id in
            store.items.firstIndex { $0.id == id }
        }

        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(
                max(currentIndex + offset, store.items.startIndex),
                store.items.index(before: store.items.endIndex)
            )
        } else {
            targetIndex = offset < 0
                ? store.items.index(before: store.items.endIndex)
                : store.items.startIndex
        }

        selectItem(store.items[targetIndex], revealDetail: false)
    }

    private func closeDetailSheet() {
        guard showingDetailSheet else { return }
        showingDetailSheet = false
    }
}

/// First-class Logs surface: the live agent log feed rendered through the
/// shared TalkieKit `ConsoleView` (level filters, category picker, search,
/// tail autoscroll), backed by `AppLogger.shared.entries`. Replaces the old
/// status-bar afterthought + summary-card stop-gap.
private struct AgentHomeLogsConsolePage: View {
    @ObservedObject private var logger = AppLogger.shared

    private var consoleEntries: [ConsoleEntry] {
        logger.entries.map { entry in
            ConsoleEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                level: entry.level.consoleLevel,
                category: entry.category.uppercased(),
                message: entry.message,
                detail: entry.detail
            )
        }
    }

    var body: some View {
        // Explicit module qualifier: the agent's Debug/DebugKit.swift defines a
        // local `ConsoleView`, so unqualified would resolve to that one.
        TalkieKit.ConsoleView(
            entries: .constant(consoleEntries),
            theme: .ops,
            title: "Logs",
            showLiveIndicator: false,
            onClear: { logger.clear() },
            onOpenLogs: openLogsFolder
        )
    }

    private func openLogsFolder() {
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("TalkieAgent/logs", isDirectory: true)
        NSWorkspace.shared.open(dir)
    }
}

private struct AgentHomeAssistantPage: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomeView(
            onDismiss: onDismiss,
            onOpenSettings: onOpenSettings
        )
        .overlay(alignment: .topLeading) {
            OpsBadge("Assistant surface", tint: OpsInk.muted)
                .padding(OpsSpacing.xl)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Inspector

private struct AgentHomeInspectorContent: View {
    let selectedSection: AgentHomeShellSection
    let runtimePing: AgentRuntimePing?
    let agents: [AgentRuntimeAgentSnapshot]
    let activeJobs: [AgentHomeExecutorJob]
    let serverStatus: TalkieAgentServerStatus
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var settings: LiveSettings
    let traySnapshot: AgentLiveTrayAssetSnapshot
    let librarySummary: AgentHomeLibraryStore.Summary
    let lastOperationalRefresh: Date?
    let onSelect: (AgentHomeShellSection) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.xxl) {
            OpsCard(padding: OpsSpacing.xl) {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    AgentHomeSectionHeader(
                        icon: selectedSection.icon,
                        title: selectedSection.title,
                        subtitle: selectedSection.subtitle
                    )

                    Text(sectionBlurb)
                        .font(OpsType.ui(OpsSize.sm))
                        .foregroundStyle(OpsInk.muted)
                        .lineSpacing(3)
                }
            }

            OpsCard(padding: OpsSpacing.xl) {
                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    OpsSectionLabel("Runtime")
                    AgentHomeKeyValueStack {
                        OpsKVRow("Name", value: runtimePing?.runtimeName ?? "Offline")
                        OpsKVRow("Agents", value: "\(agents.filter(\.isAvailable).count)/\(agents.count)")
                        OpsKVRow("Active jobs", value: "\(activeJobs.count)")
                        OpsKVRow("Server", value: serverStatus.processState.rawValue)
                    }
                }
            }

            OpsCard(padding: OpsSpacing.xl) {
                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    OpsSectionLabel("Settings boundary")
                    AgentHomeKeyValueStack {
                        OpsKVRow("Hotkey", value: settings.hotkey.displayString)
                        OpsKVRow("Routing", value: settings.routingMode.displayName)
                        OpsKVRow("Overlay", value: settings.effectiveOverlayStyle.displayName)
                        OpsKVRow("Live tray", value: "\(traySnapshot.totalCount) assets")
                        OpsKVRow("Library", value: "\(librarySummary.total) items")
                    }
                }
            }

            OpsCard(padding: OpsSpacing.xl) {
                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    OpsSectionLabel("Quick actions")
                    OpsButton("Settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
                    OpsButton(permissionManager.allRequiredGranted ? "Permissions ready" : "Fix permissions", icon: "lock.shield", style: .secondary) {
                        onSelect(.permissions)
                    }
                    OpsButton("History", icon: "clock.arrow.circlepath", style: .ghost) {
                        onSelect(.library)
                    }
                    OpsButton("Conversations", icon: "bubble.left.and.bubble.right", style: .ghost) {
                        onSelect(.conversations)
                    }
                }
            }

            if let lastOperationalRefresh {
                Text("Snapshot refreshed \(lastOperationalRefresh, style: .relative)")
                    .font(OpsType.mono(OpsSize.xs))
                    .foregroundStyle(OpsInk.dim)
            }
        }
    }

    private var sectionBlurb: String {
        switch selectedSection {
        case .conversations:
            return "Talk to the agent — the live conversation surface."
        case .more:
            return "Demoted runtime panes, reachable from the overflow."
        case .home:
            return "At a glance: runtime status, recent history, and quick actions."
        case .library:
            return "Read-only view of Talkie's shared library history."
        case .capture:
            return "Live context and capture options that Agent can own end-to-end."
        case .tray:
            return "Live screenshot/clip manifests and the Agent-owned promotion boundary."
        case .dictation:
            return "Shared mic, model, routing, and retention settings."
        case .overlays:
            return "Agent-rendered recording feedback surfaces."
        case .server:
            return "TalkieServer supervision and agent adapter health."
        case .permissions:
            return "macOS access required for recording, paste, and screen context."
        case .logs:
            return "Live log feed — filter by level or subsystem, copy lines or the whole log."
        case .assistant:
            return "Existing conversation surface retained inside the new shell."
        }
    }
}

// MARK: - Components

private struct AgentHomePageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    /// Optional uppercase mono eyebrow rendered above the title. When set,
    /// the page header switches to the editorial treatment borrowed from
    /// Talkie's homepage — eyebrow + serif display headline — instead of
    /// the plain semibold title. `nil` keeps the original look for every
    /// page that doesn't opt in.
    let eyebrow: String?
    /// When false, the page drops its title/subtitle header entirely and
    /// lands straight in `content` — used by Home (leads with the Agent Bay)
    /// and History (leads with the recordings list), which label their own
    /// sections with `OpsSectionLabel` instead.
    let showsHeader: Bool
    let scrolls: Bool
    let maxContentWidth: CGFloat
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        eyebrow: String? = nil,
        showsHeader: Bool = true,
        scrolls: Bool = true,
        maxContentWidth: CGFloat = 980,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.showsHeader = showsHeader
        self.scrolls = scrolls
        self.maxContentWidth = maxContentWidth
        self.content = content
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    pageContent
                        .padding(.horizontal, OpsSpacing.huge)
                        .padding(.top, OpsSpacing.xxl)
                        .padding(.bottom, OpsSpacing.huge)
                        .frame(maxWidth: maxContentWidth, alignment: .leading)
                }
            } else {
                pageContent
                    .padding(.horizontal, OpsSpacing.huge)
                    .padding(.top, OpsSpacing.xxl)
                    .padding(.bottom, OpsSpacing.huge)
                    .frame(maxWidth: maxContentWidth, maxHeight: .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpsInk.bg)
    }

    @ViewBuilder
    private var pageContent: some View {
        let stack = VStack(alignment: .leading, spacing: OpsSpacing.xxl) {
            if showsHeader {
                if let eyebrow {
                    AgentHomeEditorialHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: OpsSpacing.sm) {
                        Text(title)
                            .font(OpsType.ui(OpsSize.xxl, weight: .semibold))
                            .foregroundStyle(OpsInk.ink)

                        Text(subtitle)
                            .font(OpsType.ui(OpsSize.base))
                            .foregroundStyle(OpsInk.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            content()
        }

        if scrolls {
            stack.frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Editorial page header copied from Talkie's homepage vocabulary
/// (`ScopeHomeView` / `ScopePageHero`): a small uppercase mono eyebrow
/// over a Cormorant Garamond display headline, with a refined subtitle
/// and a tapering hairline beneath. Uses `ScopeType.display` — the
/// homepage's actual Cormorant face, now bundled + registered for the
/// Agent via `TalkieKitFonts.registerBundledFonts()` — so the headline
/// matches the homepage exactly, set over TalkieAgent's dark Ops palette.
private struct AgentHomeEditorialHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.sm) {
            HStack(spacing: OpsSpacing.sm) {
                OpsStatusDot(color: AgentTheme.accent, size: OpsDot.tiny)
                Text(eyebrow.uppercased())
                    .font(OpsType.mono(OpsSize.micro, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(AgentTheme.accent)
            }

            Text(title)
                .font(ScopeType.display(size: OpsSize.xxxl, weight: .regular))
                .foregroundStyle(OpsInk.ink)
                .tracking(-0.3)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(subtitle)
                .font(OpsType.ui(OpsSize.base))
                .foregroundStyle(OpsInk.muted)
                .lineSpacing(2)

            // Tapering hairline — the donor's `ScopeDivider` flourish,
            // drawn Ops-native so the band reads as one editorial unit.
            LinearGradient(
                colors: [OpsHairline.standard, OpsHairline.standard.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.top, OpsSpacing.xs)
        }
    }
}

private struct AgentHomeMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    /// Optional channel tag (e.g. `CH-01`) rendered top-right, mirroring
    /// the donor's instrument-bay `ChannelLabel`. `nil` keeps the plain
    /// card used elsewhere.
    var channel: String? = nil

    var body: some View {
        OpsCard(padding: OpsSpacing.xl) {
            VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                HStack(alignment: .center, spacing: OpsSpacing.md) {
                    Image(systemName: icon)
                        .font(OpsType.ui(OpsSize.md, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                                .fill(OpsSurface.tintFill(tint))
                    )

                    Spacer(minLength: 0)

                    if let channel {
                        Text(channel.uppercased())
                            .font(OpsType.mono(OpsSize.micro, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(OpsSurface.tintStrong(tint))
                            .padding(.horizontal, OpsSpacing.sm)
                            .padding(.vertical, OpsSpacing.xxs)
                            .overlay(
                                RoundedRectangle(cornerRadius: OpsRadius.tight)
                                    .stroke(OpsSurface.tintBorder(tint), lineWidth: OpsStroke.thin)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: OpsSpacing.xs) {
                    Text(value)
                        .font(OpsType.mono(OpsSize.xl, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(title.uppercased())
                        .font(OpsType.mono(OpsSize.micro, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(OpsInk.dim)
                        .lineLimit(1)

                    Text(detail)
                        .font(OpsType.ui(OpsSize.xs))
                        .foregroundStyle(OpsInk.muted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Left-edge accent stripe — the donor's "armed channel"
            // affordance (InsetStripe), leaning into the per-card tint.
            // Only on channel-tagged (instrument-bay) cards so the plain
            // metric cards used by other pages stay unchanged.
            .overlay(alignment: .leading) {
                if channel != nil {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(OpsSurface.tintMuted(tint))
                        .frame(width: 2)
                        .padding(.vertical, OpsSpacing.xxs)
                        .offset(x: -OpsSpacing.xl)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Warm-paper instrument panel that leads the **Home** page — the agent's
/// runtime "instrument" moment, ported from the design studio's Agent Bay
/// (donor: design/studio/components/studies/Bay.tsx + MacAgentHomeShell.tsx).
/// A top runtime rail, divided stat cells (serif value · mono label · brass
/// sparkline), and a signal-path footer rail. Carries its own warm palette
/// (`AgentBayPalette`) so it lifts off the cool Ops case with an artifact
/// shadow. Home only — History stays a plain recordings list, no bay.
private struct AgentHomeBay: View {
    struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    let runtime: String
    let runtimeRight: String
    let footer: String
    let stats: [Stat]

    var body: some View {
        VStack(spacing: 0) {
            rail(leading: runtime, trailing: runtimeRight, leadingDot: true)
                .overlay(alignment: .bottom) { hairline }
            cells
            rail(leading: footer, trailing: timeLabel, leadingDot: false)
                .overlay(alignment: .top) { hairline }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentBayPalette.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AgentBayPalette.edge, lineWidth: 1)
        )
        // The home study's `shadow-artifact` lift (0 6px 14px /.18) so the
        // bay reads as a raised instrument panel on the cool case.
        .shadow(color: Color.black.opacity(0.18), radius: 7, x: 0, y: 4)
    }

    private var hairline: some View {
        Rectangle().fill(AgentBayPalette.edge).frame(height: 1)
    }

    private func rail(leading: String, trailing: String, leadingDot: Bool) -> some View {
        HStack(spacing: OpsSpacing.md) {
            if leadingDot {
                Circle()
                    .fill(AgentBayPalette.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: AgentBayPalette.accent.opacity(0.4), radius: 2)
            }
            Text(leading.uppercased())
                .font(OpsType.mono(8, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(AgentBayPalette.inkFaint)
                .lineLimit(1)

            Spacer(minLength: OpsSpacing.md)

            Text(trailing.uppercased())
                .font(OpsType.mono(8, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(AgentBayPalette.inkSubtle)
                .lineLimit(1)
        }
        .padding(.horizontal, OpsSpacing.xxl)
        .padding(.vertical, 7)
        .background(AgentBayPalette.strip)
    }

    private var cells: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                cell(stat, seed: index)
                    .overlay(alignment: .trailing) {
                        if index < stats.count - 1 {
                            Rectangle().fill(AgentBayPalette.edge).frame(width: 1)
                        }
                    }
            }
        }
        .padding(.horizontal, OpsSpacing.xs)
    }

    private func cell(_ stat: Stat, seed: Int) -> some View {
        VStack(alignment: .leading, spacing: OpsSpacing.xs) {
            Text(stat.value)
                .font(ScopeType.display(size: OpsSize.xxxl, weight: .regular))
                .foregroundStyle(AgentBayPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(stat.label.uppercased())
                .font(OpsType.mono(8, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(AgentBayPalette.inkFaint)
                .lineLimit(1)

            AgentBaySparkline(seed: seed)
                .stroke(AgentBayPalette.accent.opacity(0.65), lineWidth: 1)
                .frame(height: 11)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OpsSpacing.lg)
        .padding(.vertical, OpsSpacing.xxl)
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

/// Warm "CHIFFON-family" paper palette for the Agent Bay — adaptive so it
/// stays warm-on-light and a deeper warm on dark, lifting off the neutral
/// Ops surface either way. Mirrors `BAY` in the studio's MacAgentHomeShell.
private enum AgentBayPalette {
    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }
    static let bg     = opsAdaptive(light: c(243, 239, 226), dark: c(31, 29, 24))
    static let strip  = opsAdaptive(light: c(237, 232, 214), dark: c(38, 35, 28))
    static let edge   = opsAdaptive(light: c(226, 218, 198), dark: c(58, 53, 42))
    static let accent = opsAdaptive(light: c(154, 106, 34), dark: c(201, 150, 74)) // brass
    static let ink      = OpsInk.ink
    static let inkFaint = OpsInk.muted
    static let inkSubtle = OpsInk.dim
}

/// Deterministic decorative sparkline for a bay cell — ported verbatim from
/// the studio's `sparklineSamples`/`sparklinePath` so each cell gets a
/// distinct, stable trace (no animation, no live data — pure instrument trim).
private struct AgentBaySparkline: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let samples = Self.samples(seed: seed)
        var path = Path()
        let step = rect.width / CGFloat(samples.count - 1)
        for (i, v) in samples.enumerated() {
            let x = rect.minX + CGFloat(i) * step
            let y = rect.maxY - CGFloat(v) * rect.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private static func samples(seed: Int) -> [Double] {
        var out: [Double] = []
        for i in 0..<7 {
            let phase = Double(seed) * 0.9
            let sine = sin(Double(i) * 0.85 + phase) * 0.3 + 0.55
            let jitter = Double((seed * 31 + i * 17) & 0xff) / 255.0 * 0.18
            out.append(min(0.95, max(0.08, sine + jitter - 0.09)))
        }
        return out
    }
}

/// Current day-streak from real library activity: consecutive calendar days
/// (ending at the most recent item's day) that have at least one item. Honest
/// — derived from `createdAt`, not a fabricated figure.
private enum AgentHomeStreak {
    static func current(from items: [TalkieObject], now: Date = Date()) -> Int {
        guard !items.isEmpty else { return 0 }
        let calendar = Calendar.current
        let days = Set(items.map { calendar.startOfDay(for: $0.createdAt) })
        guard var cursor = days.max() else { return 0 }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

/// Compact KPI tile in Talkie's Stats vocabulary (`StatsScreen.StatCard`):
/// a centered icon, a serif (Cormorant) value, and an uppercase mono
/// label — no detail line. Drives the lean "stats land" first row on the
/// Home and History pages so the Agent reads as the same family as Talkie,
/// set on the dark Ops surface that keeps the two apps distinct.
private struct AgentHomeStatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        OpsCard(padding: OpsSpacing.xl) {
            VStack(spacing: OpsSpacing.sm) {
                Image(systemName: icon)
                    .font(OpsType.ui(OpsSize.base, weight: .medium))
                    .foregroundStyle(OpsInk.muted)

                Text(value)
                    .font(ScopeType.display(size: OpsSize.xxxl, weight: .regular))
                    .foregroundStyle(OpsInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(label.uppercased())
                    .font(OpsType.mono(OpsSize.micro, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(OpsInk.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AgentHomeSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: OpsSpacing.md) {
            Image(systemName: icon)
                .font(OpsType.ui(OpsSize.base, weight: .semibold))
                .foregroundStyle(AgentTheme.accent)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                        .fill(OpsSurface.tintFill(AgentTheme.accent))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OpsType.ui(OpsSize.lg, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)
                Text(subtitle)
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.muted)
                    .lineSpacing(3)
            }
        }
    }
}

private struct AgentHomeKeyValueStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        OpsInset(padding: OpsSpacing.xl) {
            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AgentHomeStatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: OpsSpacing.sm) {
            Text(title)
                .font(OpsType.mono(OpsSize.xs, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, OpsSpacing.md)
        .padding(.vertical, OpsSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                .fill(OpsSurface.tintFill(tint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                .stroke(OpsSurface.tintBorder(tint), lineWidth: OpsStroke.standard)
        )
    }
}

private struct AgentHomeRouteButton: View {
    let section: AgentHomeShellSection
    let onSelect: (AgentHomeShellSection) -> Void

    var body: some View {
        Button {
            onSelect(section)
        } label: {
            HStack(spacing: OpsSpacing.md) {
                Image(systemName: section.icon)
                    .font(OpsType.ui(OpsSize.base, weight: .semibold))
                    .foregroundStyle(AgentTheme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)
                    Text(section.subtitle)
                        .font(OpsType.ui(OpsSize.xs))
                        .foregroundStyle(OpsInk.muted)
                }

                Spacer(minLength: 0)
            }
            .padding(OpsSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.card, style: .continuous)
                    .fill(OpsSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpsRadius.card, style: .continuous)
                    .stroke(OpsHairline.subtle, lineWidth: OpsStroke.standard)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AgentHomeAgentRow: View {
    let agent: AgentRuntimeAgentSnapshot

    var body: some View {
        OpsInset(padding: OpsSpacing.md) {
            HStack(alignment: .center, spacing: OpsSpacing.md) {
                OpsStatusDot(color: agent.isAvailable ? OpsInk.statusOk : OpsInk.dim, size: 7, pulses: false)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                        .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)
                        .lineLimit(1)

                    Text(agent.detail ?? agent.adapterType)
                        .font(OpsType.ui(OpsSize.xs))
                        .foregroundStyle(OpsInk.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                OpsBadge(agent.status, tint: agent.isAvailable ? OpsInk.statusOk : OpsInk.dim)
            }
        }
    }
}

private struct AgentHomePermissionRow: View {
    let permission: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void

    var body: some View {
        OpsInset(padding: OpsSpacing.md) {
            HStack(alignment: .center, spacing: OpsSpacing.md) {
                Image(systemName: permission.icon)
                    .font(OpsType.ui(OpsSize.base, weight: .semibold))
                    .foregroundStyle(status.hudTint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(permission.title)
                        .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)

                    Text(permission.shortDescription)
                        .font(OpsType.ui(OpsSize.xs))
                        .foregroundStyle(OpsInk.muted)
                }

                Spacer(minLength: 0)

                OpsBadge(status.label, tint: status.hudTint, dot: status == .granted)

                OpsButton(status == .granted ? "Open" : "Fix", icon: status == .granted ? "arrow.up.forward.app" : "wrench.and.screwdriver", style: .ghost, action: onRequest)
            }
        }
    }
}

private struct AgentHomeLibrarySlideSheet<Content: View>: View {
    let availableSize: CGSize
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    private var usesBottomSheet: Bool {
        availableSize.width < 560
    }

    private var panelWidth: CGFloat {
        let inset: CGFloat = usesBottomSheet ? 12 : 36
        return max(0, min(1_040, availableSize.width - inset))
    }

    private var panelHeight: CGFloat {
        let inset: CGFloat = usesBottomSheet ? 10 : 32
        return max(0, min(820, availableSize.height - inset))
    }

    var body: some View {
        ZStack {
            Button(action: onDismiss) {
                Color.black.opacity(0.24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close library preview")

            if usesBottomSheet {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                        .frame(width: panelWidth, height: panelHeight)
                }
            } else {
                panel
                    .frame(width: panelWidth, height: panelHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onDismiss)
    }

    private var panel: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpsInk.bg.opacity(0.94))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OpsHairline.standard, lineWidth: OpsStroke.thin)
            )
            .overlay(closeButton, alignment: .topTrailing)
            .shadow(
                color: Color.black.opacity(0.24),
                radius: 26,
                x: 0,
                y: 10
            )
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(OpsType.ui(OpsSize.xs, weight: .semibold))
                .foregroundStyle(OpsInk.muted)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                        .fill(OpsInk.surface.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                        .stroke(OpsHairline.subtle, lineWidth: OpsStroke.thin)
                )
        }
        .buttonStyle(.plain)
        .help("Close preview")
        .padding(OpsSpacing.lg)
    }
}

private struct AgentHomeLibraryDetailPane: View {
    let item: TalkieObject?
    let onOpenInTalkie: (TalkieObject) -> Void

    @State private var copiedItemID: UUID?

    private static let metadataRailThreshold: CGFloat = 660

    var body: some View {
        GeometryReader { proxy in
            if let item {
                let usesMetadataRail = proxy.size.width >= Self.metadataRailThreshold

                if usesMetadataRail {
                    let railWidth = metadataRailWidth(for: proxy.size.width)

                    HStack(spacing: 0) {
                        previewStage(for: item)
                            .frame(
                                width: max(0, proxy.size.width - railWidth - 1),
                                height: proxy.size.height
                            )

                        Rectangle()
                            .fill(OpsHairline.standard)
                            .frame(width: 1)

                        ScrollView {
                            metadataRail(for: item)
                                .padding(OpsSpacing.xxxl)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(width: railWidth)
                        .frame(maxHeight: .infinity)
                        .background(OpsInk.surface.opacity(0.74))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            previewStage(for: item)
                                .frame(
                                    width: proxy.size.width,
                                    height: stackedPreviewHeight(for: item, in: proxy.size)
                                )

                            Rectangle()
                                .fill(OpsHairline.standard)
                                .frame(height: 1)

                            metadataRail(for: item)
                                .padding(OpsSpacing.xxxl)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(OpsInk.surface.opacity(0.74))
                        }
                        .frame(width: proxy.size.width, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                }
            } else {
                AgentHomeEmptyInset(
                    title: "Select a library item",
                    detail: "Recordings and captures show a compact read-only summary here."
                )
                .padding(OpsSpacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(OpsInk.bg)
    }

    private func metadataRailWidth(for availableWidth: CGFloat) -> CGFloat {
        min(286, max(228, availableWidth * 0.32))
    }

    private func stackedPreviewHeight(for item: TalkieObject, in size: CGSize) -> CGFloat {
        if previewMedia(for: item) != nil {
            return min(430, max(250, size.width * 0.62))
        }
        return min(380, max(270, size.height * 0.46))
    }

    @ViewBuilder
    private func previewStage(for item: TalkieObject) -> some View {
        if let media = previewMedia(for: item) {
            AgentHomeMediaPreview(
                media: media,
                maxPixelSize: 1_100,
                style: .libraryStage
            )
        } else {
            textStage(for: item)
        }
    }

    private func textStage(for item: TalkieObject) -> some View {
        ZStack(alignment: .topLeading) {
            OpsInk.surface

            VStack(alignment: .leading, spacing: OpsSpacing.xxl) {
                HStack(spacing: OpsSpacing.md) {
                    Image(systemName: item.type == .dictation ? "waveform" : item.type.icon)
                        .font(OpsType.ui(OpsSize.md, weight: .semibold))
                        .foregroundStyle(tint(for: item.type))

                    Text(item.type == .dictation ? "DICTATION PREVIEW" : "CONTENT PREVIEW")
                        .font(OpsType.mono(OpsSize.micro, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(OpsInk.dim)
                }

                Rectangle()
                    .fill(OpsHairline.standard)
                    .frame(height: 1)

                ScrollView {
                    Text(item.agentHomeTextPreview ?? item.agentHomeDisplayTitle)
                        .font(OpsType.ui(OpsSize.lg))
                        .foregroundStyle(OpsInk.ink)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(OpsSpacing.huge)
        }
        .overlay {
            Rectangle()
                .stroke(OpsHairline.subtle, lineWidth: OpsStroke.thin)
        }
    }

    private func metadataRail(for item: TalkieObject) -> some View {
        VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
            HStack(alignment: .center, spacing: OpsSpacing.md) {
                Image(systemName: item.type.icon)
                    .font(OpsType.ui(OpsSize.lg, weight: .semibold))
                    .foregroundStyle(tint(for: item.type))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                            .fill(OpsSurface.tintFill(tint(for: item.type)))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.type.displayName.uppercased())
                        .font(OpsType.mono(OpsSize.micro, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(OpsInk.dim)

                    Text(item.createdAt, style: .relative)
                        .font(OpsType.ui(OpsSize.xs))
                        .foregroundStyle(OpsInk.muted)
                }

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: 26, height: 1)
            }

            Text(item.agentHomeDisplayTitle)
                .font(OpsType.ui(OpsSize.xl, weight: .semibold))
                .foregroundStyle(OpsInk.ink)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                OpsButton("Open in Talkie", icon: "arrow.up.forward.app", style: .secondary) {
                    onOpenInTalkie(item)
                }

                if item.agentHomeCopyableText != nil {
                    OpsButton(
                        copiedItemID == item.id ? "Copied" : "Copy Text",
                        icon: copiedItemID == item.id ? "checkmark" : "doc.on.doc",
                        style: .ghost
                    ) {
                        copyText(for: item)
                    }
                }
            }

            metadata(for: item)

            if previewMedia(for: item) != nil,
               let preview = item.agentHomeTextPreview {
                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    OpsSectionLabel("Preview")
                    Text(preview)
                        .font(OpsType.ui(OpsSize.sm))
                        .foregroundStyle(OpsInk.muted)
                        .lineSpacing(4)
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func copyText(for item: TalkieObject) {
        guard let text = item.agentHomeCopyableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedItemID = item.id

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
    }

    private func previewMedia(for item: TalkieObject) -> CaptureMediaAsset? {
        if let clip = item.clips.first,
           let url = CaptureMediaFileResolver.clipURL(filename: clip.filename) {
            return .video(url)
        }
        if let context = item.visualContexts.first,
           let url = CaptureMediaFileResolver.visualContextSourceURL(for: context) {
            return .video(url)
        }
        return CaptureMediaFileResolver.primaryMedia(for: item)
    }

    private func metadata(for item: TalkieObject) -> some View {
        let appName = item.appContext?.name?.agentHomeTrimmed ?? ""
        let source = appName.isEmpty ? item.source.displayName : appName

        return AgentHomeKeyValueStack {
            OpsKVRow("Source", value: source)
            OpsKVRow("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            OpsKVRow("Duration", value: item.duration > 0 ? Self.formatDuration(item.duration) : "-")
            OpsKVRow("Words", value: item.wordCount > 0 ? "\(item.wordCount)" : "-")
            OpsKVRow("Status", value: item.transcriptionStatus.displayName)

            if item.hasAudio || !item.screenshots.isEmpty || !item.clips.isEmpty || !item.attachments.isEmpty {
                OpsKVRow("Audio", value: item.hasAudio ? "Available" : "-")
                OpsKVRow("Screenshots", value: "\(item.screenshots.count)")
                OpsKVRow("Clips", value: "\(item.clips.count)")
                OpsKVRow("Attachments", value: "\(item.attachments.count)")
            }
        }
    }

    private func tint(for type: TalkieObjectType) -> Color {
        switch type {
        case .memo:
            return AgentTheme.accent
        case .dictation:
            return AgentTheme.brandAccent
        case .note:
            return OpsInk.statusInfo
        case .capture, .selection:
            return OpsTint.green.color
        case .segment:
            return OpsInk.dim
        }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"

        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }

        return "\(minutes):\(paddedSeconds)"
    }
}

private struct AgentHomeCapturePreviewStrip: View {
    let items: [TalkieObject]
    let selectedID: UUID?
    let onSelect: (TalkieObject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.md) {
            OpsSectionLabel("· Captures")
                .padding(.horizontal, OpsSpacing.xxl)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: OpsSpacing.lg) {
                    ForEach(items) { item in
                        AgentHomeCapturePreviewTile(
                            item: item,
                            isSelected: selectedID == item.id,
                            onSelect: { onSelect(item) }
                        )
                    }
                }
                .padding(.horizontal, OpsSpacing.xxl)
                .padding(.bottom, 2)
            }
        }
        .padding(.top, OpsSpacing.xl)
        .padding(.bottom, OpsSpacing.xxl)
    }
}

private struct AgentHomeCapturePreviewTile: View {
    private enum Metrics {
        static let width: CGFloat = 176
        static let imageHeight: CGFloat = 102
        static let captionGap: CGFloat = 9
        static let labelHeight: CGFloat = 36
        static let padding: CGFloat = 4
    }

    let item: TalkieObject
    let isSelected: Bool
    let onSelect: () -> Void

    private var media: CaptureMediaAsset? {
        CaptureMediaFileResolver.primaryMedia(for: item)
    }

    private var sourceLabel: String {
        let appName = item.appContext?.name?.agentHomeTrimmed ?? ""
        return appName.isEmpty ? item.source.displayName : appName
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Metrics.captionGap) {
                AgentHomeMediaPreview(media: media, maxPixelSize: 360)
                    .frame(width: Metrics.width, height: Metrics.imageHeight)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.agentHomeDisplayTitle)
                        .font(OpsType.ui(OpsSize.xs, weight: .semibold))
                        .foregroundStyle(OpsInk.ink)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(sourceLabel.uppercased())
                        Text("·")
                        Text(AgentHomeRelative.shortLabel(for: item.createdAt).uppercased())
                    }
                    .font(OpsType.mono(OpsSize.micro, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(OpsInk.dim)
                    .lineLimit(1)
                }
                .frame(width: Metrics.width, height: Metrics.labelHeight, alignment: .topLeading)
            }
            .frame(
                width: Metrics.width,
                height: Metrics.imageHeight + Metrics.captionGap + Metrics.labelHeight,
                alignment: .topLeading
            )
            .padding(Metrics.padding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                        .fill(OpsSurface.tintFill(AgentTheme.accent))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                    .stroke(
                        isSelected ? OpsSurface.tintBorder(AgentTheme.accent) : Color.clear,
                        lineWidth: OpsStroke.thin
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum AgentHomeMediaPreviewStyle: Equatable {
    case standard
    case captureCard(durationLabel: String?)
    case libraryStage

    var fillsFrame: Bool {
        if case .captureCard = self { return true }
        return false
    }

    var durationLabel: String? {
        if case .captureCard(let durationLabel) = self { return durationLabel }
        return nil
    }

    var usesBackdrop: Bool {
        self == .libraryStage
    }
}

private struct AgentHomeMediaPreview: View {
    let media: CaptureMediaAsset?
    var maxPixelSize: CGFloat = 420
    var style: AgentHomeMediaPreviewStyle = .standard

    @State private var image: NSImage?

    private var usesCinematicVideoTreatment: Bool {
        style.fillsFrame && media?.isVideo == true
    }

    private var showsCenteredPlayButton: Bool {
        media?.isVideo == true && (usesCinematicVideoTreatment || style.usesBackdrop)
    }

    private var cacheKey: String {
        guard let media else { return "none" }
        return "\(Int(maxPixelSize)):\(media.url.path)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                .fill(OpsSurface.inset)

            if let image {
                if style.usesBackdrop {
                    GeometryReader { proxy in
                        ZStack {
                            Image(nsImage: image)
                                .interpolation(.medium)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                                .blur(radius: 24)
                                .scaleEffect(1.16)
                                .opacity(0.34)

                            OpsInk.bg.opacity(0.42)

                            Image(nsImage: image)
                                .interpolation(.high)
                                .resizable()
                                .scaledToFit()
                                .padding(OpsSpacing.huge)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
                        }
                    }
                } else if style.fillsFrame {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .interpolation(.medium)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .blur(radius: usesCinematicVideoTreatment ? 7 : 0)
                            .scaleEffect(usesCinematicVideoTreatment ? 1.08 : 1)
                    }
                } else {
                    Image(nsImage: image)
                        .interpolation(.medium)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                AgentHomeMediaPlaceholder(isVideo: media?.isVideo == true)
            }

            if style.usesBackdrop {
                LinearGradient(
                    colors: [OpsInk.bg.opacity(0.08), .clear, OpsInk.ink.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            } else {
                LinearGradient(
                    colors: [
                        .white.opacity(0.18),
                        .clear,
                        OpsInk.ink.opacity(0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            if showsCenteredPlayButton {
                if usesCinematicVideoTreatment {
                    Color.black.opacity(0.14)
                        .allowsHitTesting(false)
                }

                Image(systemName: "play.fill")
                    .font(OpsType.ui(style.usesBackdrop ? 16 : 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(
                        width: style.usesBackdrop ? 46 : 38,
                        height: style.usesBackdrop ? 46 : 38
                    )
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().stroke(Color.white.opacity(0.34), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.24), radius: 6, y: 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                .stroke(OpsHairline.standard, lineWidth: OpsStroke.thin)
        }
        .overlay(alignment: .topTrailing) {
            if media?.isVideo == true {
                if style == .standard {
                    Image(systemName: "play.fill")
                        .font(OpsType.ui(OpsSize.micro, weight: .bold))
                        .foregroundStyle(OpsInk.ink)
                        .padding(5)
                        .background(Circle().fill(OpsInk.surface.opacity(0.82)))
                        .padding(5)
                } else if let durationLabel = style.durationLabel {
                    Text(durationLabel)
                        .font(OpsType.mono(8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.black.opacity(0.58)))
                        .padding(7)
                }
            }
        }
        .task(id: cacheKey) {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        guard let media else {
            await MainActor.run { image = nil }
            return
        }

        if let cached = await MainActor.run(body: { AgentHomeMediaPreviewCache.image(for: cacheKey) }) {
            await MainActor.run { image = cached }
            return
        }

        await MainActor.run { image = nil }
        let loaded = await AgentHomeMediaPreviewLoader.thumbnail(
            for: media,
            maxPixelSize: Int(maxPixelSize)
        )
        guard !Task.isCancelled else { return }

        if let loaded {
            await MainActor.run {
                AgentHomeMediaPreviewCache.set(loaded, for: cacheKey)
            }
        }
        await MainActor.run { image = loaded }
    }
}

private struct AgentHomeMediaPlaceholder: View {
    let isVideo: Bool

    var body: some View {
        VStack(spacing: OpsSpacing.xs) {
            Image(systemName: isVideo ? "play.rectangle" : "photo")
                .font(OpsType.ui(OpsSize.lg, weight: .semibold))
                .foregroundStyle(OpsInk.dim)

            Rectangle()
                .fill(OpsHairline.standard)
                .frame(width: 34, height: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private enum AgentHomeMediaPreviewCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    static func image(for key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    static func set(_ image: NSImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

private enum AgentHomeMediaPreviewLoader {
    static func thumbnail(for media: CaptureMediaAsset, maxPixelSize: Int) async -> NSImage? {
        switch media {
        case .image(let url):
            return await imageThumbnail(for: url, maxPixelSize: maxPixelSize)
        case .video(let url):
            return await VideoFrameThumbnailer.thumbnailAsync(
                for: url,
                maxSize: CGFloat(maxPixelSize)
            )
        }
    }

    private static func imageThumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let box = await Task.detached(priority: .utility) {
            SendableCGImageBox(decodeImage(for: url, maxPixelSize: maxPixelSize))
        }.value

        guard let cgImage = box.image else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func decodeImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
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

private struct AgentHomeEmptyInset: View {
    let title: String
    let detail: String

    var body: some View {
        OpsInset {
            VStack(alignment: .leading, spacing: OpsSpacing.sm) {
                Text(title)
                    .font(OpsType.ui(OpsSize.base, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)

                Text(detail)
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.muted)
            }
        }
    }
}

private enum AgentHomeGrid {
    static let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: OpsSpacing.xl, alignment: .top)
    ]
}

@MainActor
private enum AgentHomeTalkieLibraryOpener {
    static func open(_ item: TalkieObject) {
        var components = URLComponents()
        components.scheme = TalkieEnvironment.current.talkieURLScheme
        components.host = "library"
        components.queryItems = [
            URLQueryItem(name: "id", value: item.id.uuidString),
            URLQueryItem(name: "recordingId", value: item.id.uuidString),
            URLQueryItem(name: "newWindow", value: "1")
        ]

        guard let url = components.url else { return }
        TalkieAppOpener.open(url)
    }
}

// MARK: - Formatting extensions

private extension AgentLiveTrayAssetSnapshot {
    var latestLabel: String {
        guard let latestAssetAt else { return "empty" }
        return AgentHomeRelative.shortLabel(for: latestAssetAt)
    }
}

private extension String {
    var agentHomeTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension TalkieObject {
    var agentHomeHasVisualPreview: Bool {
        type == .capture
            || !screenshots.isEmpty
            || !clips.isEmpty
            || !visualContexts.isEmpty
            || attachments.contains { attachment in
                switch attachment.kind {
                case .image, .video:
                    return true
                case .audio, .document, .pdf, .other:
                    return false
                }
            }
    }

    var agentHomeDisplayTitle: String {
        if let title = title?.agentHomeTrimmed, !title.isEmpty {
            return title
        }

        if type == .capture {
            if let appName = appContext?.name?.agentHomeTrimmed, !appName.isEmpty {
                return "\(appName) capture"
            }
            if let screenshot = screenshots.first {
                return "\(screenshot.captureMode.capitalized) capture"
            }
        }

        if let text = text?.agentHomeTrimmed, !text.isEmpty {
            return Self.agentHomeSentence(from: text, limit: 90)
        }

        return "\(type.displayName) from \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var agentHomeTextPreview: String? {
        guard let text = text?.agentHomeTrimmed, !text.isEmpty else { return nil }

        let collapsed = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .agentHomeTrimmed

        if collapsed.count <= 360 {
            return collapsed
        }

        let prefix = String(collapsed.prefix(360))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    var agentHomeCopyableText: String? {
        guard let text = text?.agentHomeTrimmed, !text.isEmpty else { return nil }
        return text
    }

    private static func agentHomeSentence(from text: String, limit: Int) -> String {
        let collapsed = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .agentHomeTrimmed

        let enders: Set<Character> = [".", "!", "?"]
        for index in collapsed.indices {
            guard enders.contains(collapsed[index]) else { continue }
            let next = collapsed.index(after: index)
            guard next == collapsed.endIndex || collapsed[next].isWhitespace else { continue }
            let sentence = String(collapsed[...index]).agentHomeTrimmed
            if !sentence.isEmpty && sentence.count <= limit {
                return sentence
            }
            break
        }

        if collapsed.count <= limit {
            return collapsed
        }

        let prefix = String(collapsed.prefix(limit))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }
}

private enum AgentHomeRelative {
    static func shortLabel(for date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 {
            return "now"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600))h"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "yesterday"
        }
        return "\(Int(elapsed / 86_400))d"
    }
}

private extension PermissionStatus {
    var hudTint: Color {
        switch self {
        case .granted:
            return OpsInk.statusOk
        case .denied:
            return OpsInk.statusError
        case .notDetermined:
            return OpsInk.statusWarn
        case .restricted:
            return OpsInk.dim
        }
    }
}

// MARK: - Rail overflow flyout

/// Native NSMenu flyout for the "…" rail overflow. Holds the demoted
/// (stop-gap) sections; each item runs its closure when chosen. Kept small
/// and AppKit-side because the shared TalkieKit sidebar carries no popover
/// affordance of its own.
@MainActor
private final class AgentRailOverflowMenu: NSObject {
    struct Item {
        let title: String
        let systemImage: String
        let action: () -> Void
    }

    private final class ActionBox {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    func present(items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: #selector(fire(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = ActionBox(item.action)
            if let image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: item.title) {
                image.isTemplate = true
                menuItem.image = image
            }
            menu.addItem(menuItem)
        }

        // popUp runs a nested event loop and fires the chosen item's action
        // synchronously, so capturing view state in the closures is safe.
        let screenPoint = NSEvent.mouseLocation
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, let contentView = window.contentView {
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let viewPoint = contentView.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: viewPoint, in: contentView)
        } else {
            menu.popUp(positioning: nil, at: .zero, in: nil)
        }
    }

    @objc private func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.run()
    }
}

#Preview {
    AgentHomeShellView(onDismiss: {})
        .frame(width: 1180, height: 760)
}
