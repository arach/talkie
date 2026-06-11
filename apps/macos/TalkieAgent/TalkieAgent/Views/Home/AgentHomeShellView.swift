//
//  AgentHomeShellView.swift
//  TalkieAgent
//
//  TalkieKit-native operational home for TalkieAgent.
//  Built on TalkieKit console primitives so the agent has its own shell without
//  borrowing another app's UX layer.
//

import SwiftUI
import TalkieKit

struct AgentHomeShellView: View {
    let onDismiss: () -> Void

    @StateObject private var store = AgentHomeActivityStore()
    @StateObject private var libraryStore = AgentHomeLibraryStore(displayLimit: 120)
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var homeController = AgentHomeController.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: AgentHomeShellSection = .overview
    @AppStorage("talkie.agentHome.sidebar.compact") private var railCompact = true
    @AppStorage("talkie.agentHome.sidebar.labelWidth") private var navigationSidebarLabelWidth = 120.0
    @AppStorage("talkie.agentHome.inspector.collapsed") private var inspectorCollapsed = false

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
        // Agent Home follows the user's appearance setting (NSApp.appearance,
        // driven by LiveSettings.applyAppearance): adaptive Ops tokens resolve
        // to their light or dark variant. No forced color scheme here.
        .onAppear {
            store.startRefreshing()
            libraryStore.start()
            permissionManager.refreshAll()
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
                    if let next {
                        selectedSection = next
                        closeSettings()   // primary nav stays live; selecting it exits settings
                    }
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

    @ViewBuilder
    private var runtimeContent: some View {
        switch selectedSection {
        case .overview:
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
            AgentHomeLogsPage(
                store: store,
                serverStatus: serverStatus,
                lastOperationalRefresh: lastOperationalRefresh,
                onOpenSettings: openSettings
            )
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
    case overview
    case library
    case capture
    case tray
    case dictation
    case overlays
    case server
    case permissions
    case logs
    case assistant

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .library: return "Library"
        case .capture: return "Capture"
        case .tray: return "Tray"
        case .dictation: return "Dictation"
        case .overlays: return "Overlays"
        case .server: return "Server"
        case .permissions: return "Permissions"
        case .logs: return "Logs"
        case .assistant: return "Assistant"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Runtime posture"
        case .library: return "History + media"
        case .capture: return "Context + screen"
        case .tray: return "Live asset ownership"
        case .dictation: return "Mic, model, routing"
        case .overlays: return "Pill + indicator"
        case .server: return "Bridge + agents"
        case .permissions: return "macOS access"
        case .logs: return "Diagnostics"
        case .assistant: return "Conversation"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "rectangle.3.group"
        case .library: return "clock.arrow.circlepath"
        case .capture: return "viewfinder"
        case .tray: return "tray.full"
        case .dictation: return "waveform"
        case .overlays: return "rectangle.inset.topright.filled"
        case .server: return "server.rack"
        case .permissions: return "lock.shield"
        case .logs: return "doc.text.magnifyingglass"
        case .assistant: return "bubble.left.and.bubble.right"
        }
    }

    var selectedIcon: String {
        switch self {
        case .overview: return "rectangle.3.group.fill"
        case .library: return "clock.arrow.circlepath"
        case .capture: return "viewfinder.circle.fill"
        case .tray: return "tray.full.fill"
        case .dictation: return "waveform.circle.fill"
        case .overlays: return "rectangle.inset.topright.filled"
        case .server: return "server.rack"
        case .permissions: return "lock.shield.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .assistant: return "bubble.left.and.bubble.right.fill"
        }
    }

    static var sidebarEntries: [SidebarEntry<AgentHomeShellSection>] {
        [
            .section(id: "home", title: "Home"),
            .item(.init(id: .overview, title: AgentHomeShellSection.overview.title, icon: AgentHomeShellSection.overview.icon, selectedIcon: AgentHomeShellSection.overview.selectedIcon, tooltipLabel: AgentHomeShellSection.overview.subtitle)),
            .item(.init(id: .library, title: AgentHomeShellSection.library.title, icon: AgentHomeShellSection.library.icon, selectedIcon: AgentHomeShellSection.library.selectedIcon, tooltipLabel: AgentHomeShellSection.library.subtitle)),
            .section(id: "runtime", title: "Runtime"),
            .item(.init(id: .capture, title: AgentHomeShellSection.capture.title, icon: AgentHomeShellSection.capture.icon, selectedIcon: AgentHomeShellSection.capture.selectedIcon, tooltipLabel: AgentHomeShellSection.capture.subtitle)),
            .item(.init(id: .tray, title: AgentHomeShellSection.tray.title, icon: AgentHomeShellSection.tray.icon, selectedIcon: AgentHomeShellSection.tray.selectedIcon, tooltipLabel: AgentHomeShellSection.tray.subtitle)),
            .item(.init(id: .dictation, title: AgentHomeShellSection.dictation.title, icon: AgentHomeShellSection.dictation.icon, selectedIcon: AgentHomeShellSection.dictation.selectedIcon, tooltipLabel: AgentHomeShellSection.dictation.subtitle)),
            .item(.init(id: .overlays, title: AgentHomeShellSection.overlays.title, icon: AgentHomeShellSection.overlays.icon, selectedIcon: AgentHomeShellSection.overlays.selectedIcon, tooltipLabel: AgentHomeShellSection.overlays.subtitle)),
            .section(id: "ops", title: "Operations"),
            .item(.init(id: .server, title: AgentHomeShellSection.server.title, icon: AgentHomeShellSection.server.icon, selectedIcon: AgentHomeShellSection.server.selectedIcon, tooltipLabel: AgentHomeShellSection.server.subtitle)),
            .item(.init(id: .permissions, title: AgentHomeShellSection.permissions.title, icon: AgentHomeShellSection.permissions.icon, selectedIcon: AgentHomeShellSection.permissions.selectedIcon, tooltipLabel: AgentHomeShellSection.permissions.subtitle)),
            .item(.init(id: .logs, title: AgentHomeShellSection.logs.title, icon: AgentHomeShellSection.logs.icon, selectedIcon: AgentHomeShellSection.logs.selectedIcon, tooltipLabel: AgentHomeShellSection.logs.subtitle)),
            .section(id: "work", title: "Work"),
            .item(.init(id: .assistant, title: AgentHomeShellSection.assistant.title, icon: AgentHomeShellSection.assistant.icon, selectedIcon: AgentHomeShellSection.assistant.selectedIcon, tooltipLabel: AgentHomeShellSection.assistant.subtitle)),
        ]
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

    var body: some View {
        AgentHomePageScaffold(title: "Agent Home", subtitle: "TalkieKit console for the live TalkieAgent runtime.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                metrics
                libraryPreview
                shortcuts
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

    private var metrics: some View {
        LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
            AgentHomeMetricCard(
                title: "Agents",
                value: "\(store.agents.count)",
                detail: "\(availableAgentCount) available",
                icon: "person.2.fill",
                tint: OpsInk.muted
            )
            AgentHomeMetricCard(
                title: "Active work",
                value: "\(store.activeJobs.count)",
                detail: "\(store.completedJobs.count) recent complete",
                icon: "arrow.triangle.2.circlepath",
                tint: store.activeJobs.isEmpty ? OpsInk.muted : OpsInk.statusWarn
            )
            AgentHomeMetricCard(
                title: "Live tray",
                value: "\(traySnapshot.totalCount)",
                detail: "\(traySnapshot.pinnedCount) pinned · \(traySnapshot.latestLabel)",
                icon: "tray.full.fill",
                tint: OpsInk.muted
            )
            AgentHomeMetricCard(
                title: "Library",
                value: "\(librarySummary.total)",
                detail: libraryDetail,
                icon: "clock.arrow.circlepath",
                tint: OpsInk.muted
            )
            AgentHomeMetricCard(
                title: "Dictations",
                value: "\(dictationCount)",
                detail: "\(storageSize) local audio",
                icon: "waveform",
                tint: OpsInk.muted
            )
        }
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
                        title: "Recent library",
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
                            ScopeLibraryRow(
                                recording: item,
                                isSelected: false,
                                onSelect: { onSelect(.library) }
                            )
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
                    AgentHomeRouteButton(section: .library, onSelect: onSelect)
                    AgentHomeRouteButton(section: .capture, onSelect: onSelect)
                    AgentHomeRouteButton(section: .tray, onSelect: onSelect)
                    AgentHomeRouteButton(section: .dictation, onSelect: onSelect)
                    AgentHomeRouteButton(section: .server, onSelect: onSelect)
                }

                OpsButton("Open shared settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
            }
        }
    }

    private var availableAgentCount: Int {
        store.agents.filter(\.isAvailable).count
    }

    private var libraryDetail: String {
        "\(librarySummary.memos) memos / \(librarySummary.dictations) dictations / \(librarySummary.captures) captures"
    }

    private var recentLibraryItems: [TalkieObject] {
        Array(libraryItems.prefix(6))
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
                    AgentHomeMetricCard(title: "Notch", value: notchValue, detail: notchDetail, icon: "macbook", tint: notchTint)
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
    @ObservedObject var store: AgentHomeLibraryStore
    let onOpenSettings: () -> Void

    @State private var selectedID: UUID?

    var body: some View {
        AgentHomePageScaffold(
            title: "Library",
            subtitle: "Read-only history from Talkie's shared recordings table.",
            scrolls: false
        ) {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "All items", value: "\(store.summary.total)", detail: visibleDetail, icon: "clock.arrow.circlepath", tint: OpsInk.muted)
                    AgentHomeMetricCard(title: "Memos", value: "\(store.summary.memos)", detail: "Cloud-synced voice memos", icon: TalkieObjectType.memo.icon, tint: OpsTint.amber.color)
                    AgentHomeMetricCard(title: "Dictations", value: "\(store.summary.dictations)", detail: "Live local transcript history", icon: TalkieObjectType.dictation.icon, tint: OpsTint.cyan.color)
                    AgentHomeMetricCard(title: "Media", value: "\(store.summary.captures + store.summary.selections)", detail: "\(store.summary.captures) captures / \(store.summary.selections) selections", icon: TalkieObjectType.capture.icon, tint: OpsTint.green.color)
                }

                OpsCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: OpsSpacing.xl) {
                            AgentHomeSectionHeader(
                                icon: "clock.arrow.circlepath",
                                title: "Recent library history",
                                subtitle: "Memos, dictations, notes, captures, and selections from Talkie."
                            )

                            Spacer(minLength: 0)

                            OpsButton("Storage", icon: "internaldrive", style: .ghost, action: onOpenSettings)
                        }
                        .padding(OpsSpacing.xxl)

                        OpsDivider(color: OpsHairline.subtle)

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                onSelect: { item in selectedID = item.id }
            )
        }
    }

    private var visibleDetail: String {
        if store.summary.total > store.items.count {
            return "\(store.items.count) recent shown"
        }
        return "All visible"
    }
}

private struct AgentHomeLogsPage: View {
    @ObservedObject var store: AgentHomeActivityStore
    let serverStatus: TalkieAgentServerStatus
    let lastOperationalRefresh: Date?
    let onOpenSettings: () -> Void

    var body: some View {
        AgentHomePageScaffold(title: "Logs", subtitle: "Operational diagnostics and recent activity posture.") {
            VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                LazyVGrid(columns: AgentHomeGrid.columns, alignment: .leading, spacing: OpsSpacing.xl) {
                    AgentHomeMetricCard(title: "Runtime refresh", value: store.lastRefreshed.map { AgentHomeRelative.shortLabel(for: $0) } ?? "—", detail: "Agent runtime client", icon: "arrow.clockwise", tint: OpsInk.statusInfo)
                    AgentHomeMetricCard(title: "Ops snapshot", value: lastOperationalRefresh.map { AgentHomeRelative.shortLabel(for: $0) } ?? "—", detail: "Server/tray/local stats", icon: "gauge.with.needle", tint: OpsTint.amber.color)
                    AgentHomeMetricCard(title: "Failures", value: "\(serverStatus.consecutiveFailures)", detail: "Bridge health", icon: "exclamationmark.triangle", tint: serverStatus.consecutiveFailures == 0 ? OpsInk.statusOk : OpsInk.statusWarn)
                    AgentHomeMetricCard(title: "Restarts", value: "\(serverStatus.restartCount)", detail: serverStatus.lastError ?? "No current error", icon: "arrow.triangle.2.circlepath", tint: OpsInk.muted)
                }

                OpsCard {
                    VStack(alignment: .leading, spacing: OpsSpacing.xl) {
                        AgentHomeSectionHeader(
                            icon: "doc.text.magnifyingglass",
                            title: "Diagnostic posture",
                            subtitle: "Agent Home stays lightweight and points to durable logs instead of embedding a firehose."
                        )

                        AgentHomeKeyValueStack {
                            OpsKVRow("Runtime activities", value: "\(store.executorJobs.count)")
                            OpsKVRow("Completed jobs", value: "\(store.completedJobs.count)")
                            OpsKVRow("Bridge state", value: serverStatus.processState.rawValue)
                            OpsKVRow("Last error", value: serverStatus.lastError ?? "—", valueColor: serverStatus.lastError == nil ? OpsInk.muted : OpsInk.statusError, valueLineLimit: 3)
                        }

                        Text("New diagnostics should continue using TalkieLogger categories. This page is the operational summary; verbose traces stay in the existing log viewers and Console.app.")
                            .font(OpsType.ui(OpsSize.base))
                            .foregroundStyle(OpsInk.muted)
                            .lineSpacing(4)

                        OpsButton("Open diagnostics settings", icon: "gearshape", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
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
                    OpsButton("Library", icon: "clock.arrow.circlepath", style: .ghost) {
                        onSelect(.library)
                    }
                    OpsButton("Assistant", icon: "bubble.left.and.bubble.right", style: .ghost) {
                        onSelect(.assistant)
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
        case .overview:
            return "Top-level runtime posture and ownership map."
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
            return "Small operational summary; durable logs stay in the logging stack."
        case .assistant:
            return "Existing conversation surface retained inside the new shell."
        }
    }
}

// MARK: - Components

private struct AgentHomePageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let scrolls: Bool
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.content = content
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    pageContent
                        .padding(OpsSpacing.huge)
                        .frame(maxWidth: 980, alignment: .leading)
                }
            } else {
                pageContent
                    .padding(OpsSpacing.huge)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpsInk.bg)
    }

    @ViewBuilder
    private var pageContent: some View {
        let stack = VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
            VStack(alignment: .leading, spacing: OpsSpacing.sm) {
                Text(title)
                    .font(OpsType.ui(OpsSize.xxl, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)

                Text(subtitle)
                    .font(OpsType.ui(OpsSize.base))
                    .foregroundStyle(OpsInk.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
        }

        if scrolls {
            stack.frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct AgentHomeMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

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

#Preview {
    AgentHomeShellView(onDismiss: {})
        .frame(width: 1180, height: 760)
}
