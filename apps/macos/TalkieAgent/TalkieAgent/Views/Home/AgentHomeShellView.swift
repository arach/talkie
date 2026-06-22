//
//  AgentHomeShellView.swift
//  TalkieAgent
//
//  TalkieKit-native operational home for TalkieAgent.
//  Built on TalkieKit console primitives so the agent has its own shell without
//  borrowing another app's UX layer.
//

import AppKit
import SwiftUI
import TalkieKit

struct AgentHomeShellView: View {
    private static let inspectorAutoCollapseWidth: CGFloat = 900

    let onDismiss: () -> Void

    @StateObject private var store = AgentHomeActivityStore()
    @StateObject private var libraryStore = AgentHomeLibraryStore(displayLimit: 120)
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var homeController = AgentHomeController.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: AgentHomeShellSection = .home
    @State private var overflowMenu = AgentRailOverflowMenu()
    @AppStorage("talkie.agentHome.sidebar.compact") private var railCompact = true
    @AppStorage("talkie.agentHome.sidebar.labelWidth") private var navigationSidebarLabelWidth = 120.0
    @AppStorage("talkie.agentHome.inspector.collapsed") private var inspectorCollapsed = true

    @State private var serverStatus: TalkieAgentServerStatus = .stopped
    @State private var traySnapshot = AgentLiveTrayAssetSnapshot.empty
    @State private var storageSize = "—"
    @State private var lastOperationalRefresh: Date?

    private var manifest: OpsManifest {
        // Nav selection follows the user's accent (OpsInk.accent == Color.accentColor).
        // The brand "T" keeps its fixed amber callout (see railHeader).
        OpsManifest(
            name: "Talkie Agent",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
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
            inspector
        } content: {
            content
        } statusBar: {
            statusBar
        }
                .opsManifest(manifest)
                // Compact-rail hover tooltip — the same TalkieKit overlay the
                // Talkie app mounts, reading the shared SidebarTooltipState that
                // the Sidebar writes on hover. Spans the shell so the label
                // isn't clipped by the 40pt rail.
                .overlay(alignment: .topLeading) {
                    SidebarTooltipOverlay(surface: OpsInk.surface, foreground: OpsInk.ink)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                collapseInspectorIfNeeded(width: proxy.size.width)
                            }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                collapseInspectorIfNeeded(width: newWidth)
                            }
                    }
                }
        // Agent Home follows the user's appearance setting (NSApp.appearance,
        // driven by LiveSettings.applyAppearance): adaptive Ops tokens resolve
        // to their light or dark variant. No forced color scheme here.
        .onAppear {
            store.startRefreshing()
            libraryStore.start()
            permissionManager.refreshAll()
            applyPendingRoute()
        }
        .onChange(of: homeController.pendingSection) { _, _ in
            applyPendingRoute()
        }
        .onDisappear {
            store.stopRefreshing()
            libraryStore.stop()
        }
        .task {
            await refreshOperationalSnapshotsLoop()
        }
    }

    private var sidebar: some View {
        // The canonical Talkie nav, now with the same drag-to-resize / collapse
        // behavior as the main app — `ManagedResizableSidebar` (TalkieKit) owns
        // the whole resize state machine; we just hand it our two persisted
        // bindings. Header-tap still toggles compact; the trailing edge handle
        // adds drag-to-resize, drag-left-to-collapse, drag-right-to-expand.
        // It self-sizes to its intrinsic width, so no manual frame pin.
        ManagedResizableSidebar(
            isCompact: $railCompact,
            labelWidth: $navigationSidebarLabelWidth,
            selection: Binding<AgentHomeShellSection?>(
                get: { selectedSection },
                set: { next in
                    guard let next else { return }
                    if next == .more {
                        // The "…" overflow doesn't navigate — it pops a native
                        // flyout of the demoted (stop-gap) sections.
                        presentOverflowMenu()
                        return
                    }
                    selectedSection = next
                    closeSettings()   // primary nav stays live; selecting it exits settings
                }
            ),
            entries: AgentHomeShellSection.sidebarEntries,
            accent: .accentColor,
            handleTint: OpsInk.ink,
            railHeader: { brandMark },
            labelHeader: { brandWordmark },
            footer: { sidebarFooter }
        )
    }

    /// The JetBrains Mono "T" from the Talkie logo in its amber callout box.
    /// `ScopeType.mono` resolves the real bundled font (registered at launch)
    /// instead of SF Mono. Amber stays fixed even as nav selection follows the
    /// user's accent.
    private var brandMark: some View {
        Text("t")
            .font(ScopeType.mono(size: OpsSize.base, weight: .bold))
            .foregroundStyle(OpsInk.bg)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                    .fill(OpsTint.amber.color)
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
                .foregroundStyle(homeController.isShowingSettings ? Color.accentColor : OpsInk.muted)
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

    private func collapseInspectorIfNeeded(width: CGFloat) {
        guard width < Self.inspectorAutoCollapseWidth, !inspectorCollapsed else { return }
        inspectorCollapsed = true
    }

    /// Honor a deep-link requested by an external entry point (status-bar
    /// menu, XPC) — navigate to the routed tab, then clear the request.
    private func applyPendingRoute() {
        guard let route = homeController.pendingSection else { return }
        selectedSection = route.shellSection
        closeSettings()
        homeController.pendingSection = nil
    }

    /// Pop the "…" overflow flyout listing the demoted, soon-to-retire
    /// sections. Selecting one navigates to it (and exits settings).
    private func presentOverflowMenu() {
        overflowMenu.present(
            items: AgentHomeShellSection.overflowSections.map { section in
                AgentRailOverflowMenu.Item(title: section.title, systemImage: section.icon) {
                    selectedSection = section
                    closeSettings()
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
                onSelect: { selectedSection = $0 },
                onOpenSettings: openSettings
            )
        case .library:
            AgentHomeLibraryPage(
                store: libraryStore,
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
                onSelect: { selectedSection = $0 },
                onOpenSettings: openSettings
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: OpsSpacing.lg) {
            Text("Talkie Agent")
                .font(OpsType.mono(OpsSize.xs, weight: .semibold))
                .foregroundStyle(OpsInk.ink)
                .lineLimit(1)

            Text(statusBarHealthLabel)
                .font(OpsType.mono(OpsSize.xs))
                .foregroundStyle(statusBarHealthTint)
                .lineLimit(1)

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
                .font(OpsType.mono(OpsSize.micro, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(OpsInk.dim)
                .lineLimit(1)
                .help("Link time of the running TalkieAgent binary")

            OpsInspectorToggle(isCollapsed: $inspectorCollapsed)
        }
        .padding(.horizontal, OpsSpacing.xl)
        .frame(height: OpsLayout.statusBarHeight)
        .background(OpsInk.chrome)
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
        traySnapshot = await AgentLiveTrayAssetStore.shared.snapshot()
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
        case .more: return "Capture · Tray · Server…"
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
        [.capture, .tray, .dictation, .overlays, .server]
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

private extension AgentHomeRoute {
    /// Map an external deep-link target onto the shell's private section enum.
    var shellSection: AgentHomeShellSection {
        switch self {
        case .home: return .home
        case .history: return .library
        case .conversations: return .conversations
        case .permissions: return .permissions
        case .logs: return .logs
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
                AgentHomePageScaffold(title: "Home", subtitle: "Runtime status, recent history, and quick actions.", showsHeader: false) {
                    VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                        VStack(alignment: .leading, spacing: OpsSpacing.md) {
                            OpsSectionLabel("· Agent")
                            bay
                        }
                        VStack(alignment: .leading, spacing: OpsSpacing.md) {
                            OpsSectionLabel("· Recent")
                            libraryPreview
                        }
                        shortcuts
                    }
                }

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
                .init(value: "\(librarySummary.dictations)", label: "Dictations"),
                .init(value: "\(librarySummary.captures)", label: "Captures"),
                .init(value: "\(dayStreak)", label: "Day Streak"),
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
        OpsCard(padding: 0) {
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
                        tint: traySnapshot.totalCount > 0 ? OpsTint.amber.color : OpsInk.muted
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
                            OpsKVRow("Return to origin", value: settings.returnToOriginAfterPaste ? "Yes" : "No")
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
        TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled)
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
                    AgentHomeMetricCard(title: "Clips", value: "\(traySnapshot.clipCount)", detail: "\(traySnapshot.pinnedClipCount) pinned", icon: "film.stack", tint: OpsTint.amber.color)
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
                    AgentHomeMetricCard(title: "Model", value: settings.selectedModelId, detail: "Talkie transcription stack", icon: "waveform.badge.magnifyingglass", tint: OpsTint.amber.color)
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
                    AgentHomeMetricCard(title: "Top overlay", value: settings.effectiveOverlayStyle.displayName, detail: settings.overlayPosition.displayName, icon: "rectangle.inset.topright.filled", tint: OpsTint.amber.color)
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
                    AgentHomeMetricCard(title: "Jobs", value: "\(jobs.count)", detail: "\(jobs.filter { $0.status == .running || $0.status == .waiting }.count) active", icon: "list.bullet.rectangle", tint: OpsTint.amber.color)
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

    @ObservedObject var store: AgentHomeLibraryStore
    let onOpenSettings: () -> Void

    @State private var selectedID: UUID?
    @State private var isCompactLayout = false
    @State private var showingDetailSheet = false

    var body: some View {
        AgentHomePageScaffold(
            title: "History",
            subtitle: "Read-only history from Talkie's shared recordings table.",
            showsHeader: false,
            scrolls: false,
            maxContentWidth: 1_260
        ) {
            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                OpsSectionLabel("· History")

                OpsCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: OpsSpacing.xl) {
                            AgentHomeSectionHeader(
                                icon: "clock.arrow.circlepath",
                                title: "Library",
                                subtitle: "Memos, dictations, notes, captures, and selections from Talkie."
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
                emptyTitle: "NO LIBRARY ITEMS YET",
                emptyDetail: "New memos, dictations, captures, notes, and selections will appear here after Talkie writes them.",
                onSelect: { item in selectItem(item) }
            )
        }
    }

    private var libraryBody: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < Self.compactDetailThreshold

            ZStack {
                if compact {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        // List hugs its row width (the ScopeLibraryList rows cap
                        // out around here), so the detail pane fills the rest
                        // instead of leaving dead space between the two.
                        content
                            .frame(width: min(460, max(360, proxy.size.width * 0.40)))
                            .frame(maxHeight: .infinity)

                        OpsDivider(color: OpsHairline.subtle)

                        AgentHomeLibraryDetailPane(item: selectedItem) { item in
                            AgentHomeTalkieLibraryOpener.open(item)
                        }
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
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
                OpsStatusDot(color: OpsTint.amber.color, size: OpsDot.tiny)
                Text(eyebrow.uppercased())
                    .font(OpsType.mono(OpsSize.micro, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(OpsTint.amber.color)
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
                .font(OpsType.mono(8.5, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(AgentBayPalette.inkFaint)
                .lineLimit(1)

            Spacer(minLength: OpsSpacing.md)

            Text(trailing.uppercased())
                .font(OpsType.mono(8.5, weight: .semibold))
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
                .font(OpsType.mono(8.5, weight: .bold))
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
    static let accent = opsAdaptive(light: c(154, 106, 34),  dark: c(201, 150, 74)) // brass
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
                .foregroundStyle(OpsTint.amber.color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: OpsRadius.standard, style: .continuous)
                        .fill(OpsSurface.tintFill(OpsTint.amber.color))
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
                    .foregroundStyle(OpsTint.amber.color)
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
        availableSize.width < 620
    }

    private var panelWidth: CGFloat {
        let maxAvailable = max(320, availableSize.width - 32)
        return min(560, min(maxAvailable, max(360, availableSize.width * 0.84)))
    }

    private var panelHeight: CGFloat {
        let maxAvailable = max(320, availableSize.height - 24)
        return min(maxAvailable, max(360, availableSize.height * 0.84))
    }

    var body: some View {
        ZStack {
            Button(action: onDismiss) {
                Color.black.opacity(0.16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close library preview")

            if usesBottomSheet {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                        .frame(height: panelHeight)
                }
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                        .frame(width: panelWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onDismiss)
    }

    private var panel: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpsInk.bg)
            .clipShape(RoundedRectangle(cornerRadius: usesBottomSheet ? OpsRadius.card : 0, style: .continuous))
            .overlay(edgeRule, alignment: usesBottomSheet ? .top : .leading)
            .overlay(closeButton, alignment: .topTrailing)
            .shadow(
                color: Color.black.opacity(usesBottomSheet ? 0.22 : 0.18),
                radius: usesBottomSheet ? 18 : 24,
                x: usesBottomSheet ? 0 : -8,
                y: usesBottomSheet ? -8 : 0
            )
    }

    @ViewBuilder
    private var edgeRule: some View {
        if usesBottomSheet {
            Rectangle()
                .fill(OpsHairline.standard)
                .frame(height: 1)
        } else {
            Rectangle()
                .fill(OpsHairline.standard)
                .frame(width: 1)
        }
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
        .padding(OpsSpacing.xl)
    }
}

private struct AgentHomeLibraryDetailPane: View {
    let item: TalkieObject?
    let onOpenInTalkie: (TalkieObject) -> Void

    @State private var copiedItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: OpsSpacing.xxl) {
                        header(for: item)
                        facts(for: item)
                        media(for: item)
                        textPreview(for: item)
                    }
                    .padding(OpsSpacing.xxl)
                }
                .background(OpsInk.bg)
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

    private func header(for item: TalkieObject) -> some View {
        VStack(alignment: .leading, spacing: OpsSpacing.lg) {
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
            }

            Text(item.agentHomeDisplayTitle)
                .font(OpsType.ui(OpsSize.xl, weight: .semibold))
                .foregroundStyle(OpsInk.ink)
                .lineLimit(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: OpsSpacing.md) {
                    actions(for: item)
                }

                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    actions(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for item: TalkieObject) -> some View {
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

    private func facts(for item: TalkieObject) -> some View {
        AgentHomeKeyValueStack {
            OpsKVRow("Source", value: item.source.displayName)
            OpsKVRow("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            OpsKVRow("Duration", value: item.duration > 0 ? Self.formatDuration(item.duration) : "-")
            OpsKVRow("Words", value: item.wordCount > 0 ? "\(item.wordCount)" : "-")
            OpsKVRow("Status", value: item.transcriptionStatus.displayName)
        }
    }

    @ViewBuilder
    private func media(for item: TalkieObject) -> some View {
        if item.hasAudio || !item.screenshots.isEmpty || !item.clips.isEmpty || !item.attachments.isEmpty {
            AgentHomeKeyValueStack {
                OpsKVRow("Audio", value: item.hasAudio ? "Available" : "-")
                OpsKVRow("Screenshots", value: "\(item.screenshots.count)")
                OpsKVRow("Clips", value: "\(item.clips.count)")
                OpsKVRow("Attachments", value: "\(item.attachments.count)")
            }
        }
    }

    @ViewBuilder
    private func textPreview(for item: TalkieObject) -> some View {
        if let preview = item.agentHomeTextPreview {
            VStack(alignment: .leading, spacing: OpsSpacing.md) {
                OpsSectionLabel("Preview")
                Text(preview)
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.muted)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        } else {
            AgentHomeEmptyInset(
                title: "No text preview",
                detail: "Open the item in Talkie for the full detail surface, media, and editing actions."
            )
        }
    }

    private func tint(for type: TalkieObjectType) -> Color {
        switch type {
        case .memo:
            return OpsTint.amber.color
        case .dictation:
            return OpsTint.cyan.color
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
            URLQueryItem(name: "recordingId", value: item.id.uuidString)
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
