//
//  NavigationView.swift
//  Talkie macOS
//
//  EchoFlow-style navigation with Tools, Library, and Smart Folders
//

import SwiftUI
import CoreData

enum NavigationSection: Hashable {
    case home           // Main Talkie home/dashboard
    case allMemos  // All Memos view (GRDB-based with pagination and filters)
    case liveDashboard  // Live home/insights view
    case liveRecent     // Live utterance list
    case liveSettings   // Live settings (now visible in sidebar)
    case aiResults
    case workflows
    case activityLog
    case systemConsole
    case pendingActions
    case talkieService  // Accessible via engine icon click, not in sidebar
    case talkieLiveMonitor  // Accessible via live icon click, not in sidebar
    case models
    case allowedCommands
    case settings
    case smartFolder(String)
}

struct TalkieNavigationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    // Use let for singletons - we subscribe to remote data, we don't own it
    private let settings = SettingsManager.shared
    private let liveDataStore = DictationStore.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ]
    )
    private var allMemos: FetchedResults<VoiceMemo>

    @State private var selectedSection: NavigationSection? = .home
    @State private var previousSection: NavigationSection? = .home
    @State private var selectedMemo: VoiceMemo?
    @State private var searchText = ""
    @State private var isSectionLoading = false
    // Use let for @Observable singletons (not @State which breaks observation)
    private let eventManager = SystemEventManager.shared
    private let pendingActionsManager = PendingActionsManager.shared

    // Cached console event counts (updated via publisher, not computed on every render)
    @State private var cachedErrorCount: Int = 0
    @State private var cachedWorkflowCount: Int = 0

    // Collapsible sidebar state (matches TalkieLive)
    @State private var isSidebarCollapsed: Bool = false
    @State private var isChevronHovered: Bool = false

    // Sidebar width constants - use fixed values to avoid NavigationSplitView recalculations
    private let sidebarExpandedWidth: CGFloat = 180
    private let sidebarCollapsedWidth: CGFloat = 56

    private var currentSidebarWidth: CGFloat {
        isSidebarCollapsed ? sidebarCollapsedWidth : sidebarExpandedWidth
    }

    // Responsive layout state - hide StatusBar on short windows
    @State private var windowHeight: CGFloat = 0
    private var shouldShowStatusBar: Bool {
        windowHeight >= 550  // Hide StatusBar below 550px height
    }

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar - full height
                sidebarView
                    .frame(width: currentSidebarWidth)
                    .clipped()

                // Divider between sidebar and content
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(width: 1)

                // Content area + StatusBar
                VStack(spacing: 0) {
                    // Main content area
                    ZStack {
                        if isTwoColumnSection {
                            twoColumnDetailView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // 3-column: content list + detail
                            HStack(spacing: 0) {
                                contentColumnView
                                    .frame(width: 300)

                                Rectangle()
                                    .fill(Theme.current.divider)
                                    .frame(width: 1)

                                detailColumnView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }

                        // Loading indicator during section transitions
                        if isSectionLoading {
                            Rectangle()
                                .fill(Theme.current.background.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Theme.current.surface1)
                                                .shadow(radius: 4)
                                        )
                                )
                                .transition(.opacity)
                        }
                    }

                    // StatusBar only on content area (not under sidebar) - hide on short windows
                    if shouldShowStatusBar {
                        StatusBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.snappy(duration: 0.2), value: isSidebarCollapsed)
            .onAppear {
                windowHeight = geometry.size.height
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                windowHeight = newHeight
            }
        }
        .padding(.top, 8)  // Breathing room for traffic lights
        .padding(.horizontal, 1)  // Subtle edge spacing
        .focusedValue(\.sidebarToggle, SidebarToggleAction(toggle: toggleSidebar))
        .focusedValue(\.settingsNavigation, SettingsNavigationAction(showSettings: { selectedSection = .settings }))
        .focusedValue(\.liveNavigation, LiveNavigationAction(showLive: { selectedSection = .liveDashboard }))
        .onChange(of: allMemos.count) { _, _ in
            // Mark any new memos as received when they appear in the list
            PersistenceController.markMemosAsReceivedByMac(context: viewContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browseWorkflows)) { _ in
            // Navigate to Workflows section when "MORE" button is clicked
            selectedSection = .workflows
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLive)) { _ in
            // Navigate to Live Dashboard when opened from TalkieLive
            selectedSection = .liveDashboard
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
            // Navigate to Settings section when opened from URL scheme or deep link
            selectedSection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLiveSettings)) { _ in
            // Navigate to Live Settings subsection
            selectedSection = .liveSettings
        }
        .onChange(of: eventManager.events.count) { _, _ in
            updateEventCounts()
        }
        .onAppear {
            updateEventCounts()
            // Start Live data monitoring
            liveDataStore.startMonitoring()
        }
        .onDisappear {
            liveDataStore.stopMonitoring()
        }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            DebugToolbarOverlay {
                MainDebugContent()
            } debugInfo: {
                [
                    "Memos": "\(allMemos.count)",
                    "Section": String(describing: selectedSection),
                    "AutoRun": SettingsManager.shared.autoRunWorkflowsEnabled ? "ON" : "OFF"
                ]
            }
        }
        #endif
    }

    // MARK: - Status Bar View

    private let syncManager = SyncStatusManager.shared

    // Console event counts - use cached values updated via publisher
    private var consoleErrorCount: Int { cachedErrorCount }
    private var consoleWorkflowCount: Int { cachedWorkflowCount }

    private func updateEventCounts() {
        let recent = eventManager.events.prefix(100)
        cachedErrorCount = recent.filter { $0.type == .error }.count
        cachedWorkflowCount = recent.filter { $0.type == .workflow }.count
    }

    // Old statusBarView removed - now using unified StatusBar component

    // MARK: - Sidebar View (matches TalkieLive structure)


    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header with collapse toggle (matches TalkieLive)
            sidebarHeader

            // Navigation content
            if isSidebarCollapsed {
                // Collapsed: simple VStack, no scroll, natural sizing
                VStack(spacing: 0) {
                    sidebarButton(section: .home, icon: "house.fill", title: "Home")
                    sidebarButton(section: .allMemos, icon: "square.stack", title: "All Memos", badge: allMemos.count > 0 ? "\(allMemos.count)" : nil, badgeColor: .secondary)
                    sidebarButton(section: .liveDashboard, icon: "chart.xyaxis.line", title: "Live", badge: liveDataStore.needsActionCount > 0 ? "\(liveDataStore.needsActionCount)" : nil, badgeColor: .cyan)
                    sidebarButton(section: .aiResults, icon: "chart.line.uptrend.xyaxis", title: "Actions")
                    sidebarButton(section: .pendingActions, icon: "clock.arrow.circlepath", title: "Pending", badge: pendingActionsManager.hasActiveActions ? "\(pendingActionsManager.activeCount)" : nil, badgeColor: .accentColor, showSpinner: pendingActionsManager.hasActiveActions)
                    sidebarButton(section: .workflows, icon: "wand.and.stars", title: "Workflows")
                    sidebarButton(section: .models, icon: "brain", title: "Models")
                    sidebarButton(section: .systemConsole, icon: "terminal", title: "Logs", badge: cachedErrorCount > 0 ? "\(cachedErrorCount)" : nil, badgeColor: .orange)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Expanded: ScrollView with sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Home
                        sidebarButton(
                            section: .home,
                            icon: "house.fill",
                            title: "Home"
                        )

                        // Memos section
                        sidebarSectionHeader("Memos")
                            .padding(.top, 12)
                        sidebarButton(
                            section: .allMemos,
                            icon: "square.stack",
                            title: "All Memos",
                            badge: allMemos.count > 0 ? "\(allMemos.count)" : nil,
                            badgeColor: .secondary
                        )

                        // Live section
                        sidebarSectionHeader("Live")
                            .padding(.top, 12)
                        sidebarButton(
                            section: .liveDashboard,
                            icon: "chart.xyaxis.line",
                            title: "Dashboard"
                        )
                        sidebarButton(
                            section: .liveRecent,
                            icon: "waveform.badge.mic",
                            title: "Recent",
                            badge: liveDataStore.needsActionCount > 0 ? "\(liveDataStore.needsActionCount)" : nil,
                            badgeColor: .cyan
                        )
                        sidebarButton(
                            section: .liveSettings,
                            icon: "gearshape",
                            title: "Settings"
                        )

                        // Activity section
                        sidebarSectionHeader("Activity")
                            .padding(.top, 12)
                        sidebarButton(
                            section: .aiResults,
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Actions"
                        )
                        sidebarButton(
                            section: .pendingActions,
                            icon: "clock.arrow.circlepath",
                            title: "Pending",
                            badge: pendingActionsManager.hasActiveActions ? "\(pendingActionsManager.activeCount)" : nil,
                            badgeColor: .accentColor,
                            showSpinner: pendingActionsManager.hasActiveActions
                        )

                        // Tools section
                        sidebarSectionHeader("Tools")
                            .padding(.top, 12)
                        sidebarButton(
                            section: .workflows,
                            icon: "wand.and.stars",
                            title: "Workflows"
                        )
                        sidebarButton(
                            section: .models,
                            icon: "brain",
                            title: "Models"
                        )
                        sidebarButton(
                            section: .systemConsole,
                            icon: "terminal",
                            title: "Logs",
                            badge: cachedErrorCount > 0 ? "\(cachedErrorCount)" : nil,
                            badgeColor: .orange
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)

            // Settings pinned to bottom
            VStack(spacing: 0) {
                Divider()
                    .opacity(isSidebarCollapsed ? 0 : 0.5)
                sidebarButton(
                    section: .settings,
                    icon: "gear",
                    title: "Settings"
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .background(Theme.current.backgroundSecondary)
    }

    /// Section header for custom sidebar
    @ViewBuilder
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.current.foregroundMuted)
            .opacity(isSidebarCollapsed ? 0 : 1)
            .frame(height: isSidebarCollapsed ? 0 : 16)  // Collapse to 0 height when sidebar collapsed
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    /// Custom sidebar button with controlled selection styling and instrumentation
    @ViewBuilder
    private func sidebarButton(
        section: NavigationSection,
        icon: String,
        title: String,
        badge: String? = nil,
        badgeColor: SwiftUI.Color = .secondary,
        showSpinner: Bool = false,
        showStatusDot: Bool = false,
        statusDotColor: SwiftUI.Color = .gray
    ) -> some View {
        SidebarButtonContent(
            section: section,
            icon: icon,
            title: title,
            badge: badge,
            badgeColor: badgeColor,
            showSpinner: showSpinner,
            showStatusDot: showStatusDot,
            statusDotColor: statusDotColor,
            isSelected: selectedSection == section,
            isSidebarCollapsed: isSidebarCollapsed,
            onTap: {
                // Sound feedback (subtle click)
                NSSound(named: "Tink")?.play()

                // Haptic feedback (subtle click)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

                // Track section change
                if previousSection != section {
                    previousSection = selectedSection
                }

                // **START TIMER HERE** - Track full navigation time
                PerformanceMonitor.shared.startAction(
                    type: "Navigate",
                    name: sectionName(section),
                    context: "Sidebar"
                )

                // Show loading state briefly for visual feedback
                isSectionLoading = true

                // Navigate (async to allow loading indicator to show)
                Task { @MainActor in
                    selectedSection = section

                    // Hide loading after brief delay (100ms) or when view appears
                    try? await Task.sleep(for: .milliseconds(100))
                    isSectionLoading = false
                }
            },
            sectionName: sectionName(section)
        )
    }

    /// Helper to get clean section name for instrumentation
    private func sectionName(_ section: NavigationSection) -> String {
        switch section {
        case .home: return "Home"
        case .allMemos: return "AllMemos"
        case .liveDashboard: return "LiveDashboard"
        case .liveRecent: return "LiveRecent"
        case .liveSettings: return "LiveSettings"
        case .aiResults: return "AIResults"
        case .workflows: return "Workflows"
        case .activityLog: return "ActivityLog"
        case .systemConsole: return "Logs"
        case .pendingActions: return "PendingActions"
        case .talkieService: return "EngineMonitor"
        case .talkieLiveMonitor: return "LiveMonitor"
        case .models: return "Models"
        case .allowedCommands: return "AllowedCommands"
        case .settings: return "Settings"
        case .smartFolder(let name): return "SmartFolder.\(name)"
        }
    }

    /// Sidebar header with app branding and collapse toggle (matches TalkieLive)
    private var sidebarHeader: some View {
        HStack {
            if isSidebarCollapsed {
                // Collapsed: show expand chevron centered
                chevronButton(icon: "chevron.right", help: "Expand Sidebar")
            } else {
                // Expanded: show app name and collapse button
                Text("TALKIE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                chevronButton(icon: "chevron.left", help: "Collapse Sidebar")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.horizontal, isSidebarCollapsed ? 0 : 12)
        .padding(.top, 8) // Clear traffic light buttons
    }

    /// Interactive chevron button with hover and press feedback (matches TalkieLive)
    private func chevronButton(icon: String, help: String) -> some View {
        Button(action: {
            // Immediate toggle - no delay, let parent animation handle it
            toggleSidebarCollapse()
        }) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isChevronHovered ? Theme.current.foreground : Theme.current.foregroundMuted)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isChevronHovered ? Theme.current.backgroundTertiary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isChevronHovered = hovering
        }
        .help(help)
    }

    private func toggleSidebarCollapse() {
        // No withAnimation here - parent .animation(.snappy) handles it
        isSidebarCollapsed.toggle()
    }

    // MARK: - 2-Column Detail View

    @ViewBuilder
    private var twoColumnDetailView: some View {
        switch selectedSection {
        case .home:
            TalkieHomeView()
        case .models:
            TalkieSection("Models") {
                ModelsContentView()
            }
        case .allowedCommands:
            TalkieSection("AllowedCommands") {
                AllowedCommandsView()
            }
        case .aiResults:
            TalkieSection("AIResults") {
                ActivityLogFullView()
            }
        case .allMemos:
            // AllMemos already wraps itself in TalkieSection
            AllMemos()
        case .liveDashboard:
            // Live home view with insights, activity, and stats
            TalkieSection("LiveDashboard") {
                HomeView(
                    onSelectUtterance: { utterance in
                        // Navigate to Recent and select this utterance
                        selectedSection = .liveRecent
                        // TODO: Pass selected utterance to Recent view
                    },
                    onSelectApp: { appName, _ in
                        // Navigate to Recent filtered by app
                        selectedSection = .liveRecent
                        // TODO: Pass app filter to Recent view
                    }
                )
            }
        case .liveRecent:
            // Simple utterance list without sidebar navigation
            TalkieSection("LiveRecent") {
                DictationListView()
            }
        case .liveSettings:
            // Live settings view using Talkie design system
            LiveSettingsView()
        case .systemConsole:
            TalkieSection("SystemLogs") {
                SystemLogsView(onClose: {
                    // Return to previous section, or home if none
                    selectedSection = previousSection ?? .home
                })
            }
        case .pendingActions:
            TalkieSection("PendingActions") {
                PendingActionsView()
            }
        case .settings:
            TalkieSection("Settings") {
                SettingsView()
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Column Views

    /// Toggle sidebar visibility (now just toggles collapse state)
    private func toggleSidebar() {
        toggleSidebarCollapse()
    }

    /// Whether the current section uses a 2-column layout (sidebar + full content)
    /// vs 3-column layout (sidebar + list + detail)
    private var isTwoColumnSection: Bool {
        switch selectedSection {
        case .home, .models, .allowedCommands, .aiResults, .allMemos, .liveDashboard, .liveRecent, .liveSettings, .systemConsole, .pendingActions, .settings:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var contentColumnView: some View {
        switch selectedSection {
        case .workflows:
            WorkflowListColumn(
                selectedWorkflowID: $selectedWorkflowID,
                editingWorkflow: $editingWorkflow
            )
        case .aiResults:
            ActivityLogFullView()
        default:
            memoListView
        }
    }

    @ViewBuilder
    private var detailColumnView: some View {
        switch selectedSection {
        case .workflows:
            TalkieSection("Workflows") {
                WorkflowDetailColumn(
                    editingWorkflow: $editingWorkflow,
                    selectedWorkflowID: $selectedWorkflowID
                )
            }
        case .aiResults:
            // ActivityLogFullView has its own built-in inspector via HSplitView
            EmptyView()
        default:
            if let memo = selectedMemo {
                MemoDetailView(memo: memo)
                    .id(memo.id)  // Stable identity for SwiftUI diffing
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "text.below.photo")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("SELECT A MEMO")
                        .font(Theme.current.fontBodyBold)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surface1)
            }
        }
    }

    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?

    // MARK: - Computed Properties

    private var sectionTitle: String {
        switch selectedSection {
        case .home: return "HOME"
        case .allMemos: return "ALL MEMOS"
        case .liveDashboard: return "LIVE DASHBOARD"
        case .liveRecent: return "LIVE RECENT"
        case .liveSettings: return "LIVE SETTINGS"
        case .aiResults: return "ACTIVITY LOG"
        case .workflows: return "WORKFLOWS"
        case .activityLog: return "ACTIVITY LOG"
        case .systemConsole: return "LOGS"
        case .pendingActions: return "PENDING ACTIONS"
        case .talkieService: return "ENGINE MONITOR"
        case .talkieLiveMonitor: return "LIVE MONITOR"
        case .models: return "MODELS"
        case .allowedCommands: return "ALLOWED COMMANDS"
        case .settings: return "SETTINGS"
        case .smartFolder(let name): return name.uppercased()
        case .none: return "MEMOS"
        }
    }

    private var sectionSubtitle: String? {
        switch selectedSection {
        case .allMemos: return "\(allMemos.count) total"
        default: return nil
        }
    }

    private var filteredMemos: [VoiceMemo] {
        var memos = Array(allMemos)

        // Filter by search
        if !searchText.isEmpty {
            memos = memos.filter { memo in
                (memo.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (memo.transcription?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Filter by section
        switch selectedSection {
        case .smartFolder(let name):
            // Future: filter by tags or smart criteria
            memos = memos.filter { memo in
                memo.transcription?.localizedCaseInsensitiveContains(name.lowercased()) ?? false
            }
        default:
            break
        }

        return memos
    }

    private var isToolSection: Bool {
        switch selectedSection {
        case .aiResults, .workflows, .activityLog, .models, .allowedCommands:
            return true
        default:
            return false
        }
    }

    // MARK: - Tool Content Views

    @ViewBuilder
    private var toolContentView: some View {
        switch selectedSection {
        case .aiResults:
            AIResultsContentView()
        case .workflows:
            WorkflowsContentView()
        case .activityLog:
            ActivityLogContentView()
        case .models:
            ModelsContentView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var memoListView: some View {
        VStack(spacing: 0) {
            // Search field (moved from sidebar to content column)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.current.backgroundSecondary)

            // Memo list
            if filteredMemos.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("NO MEMOS")
                        .font(.techLabel)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Record on iPhone to sync")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsManager.shared.tacticalBackground)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        MemoRowView(memo: memo)
                            .tag(memo)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(SettingsManager.shared.tacticalBackground)
            }
        }
        .background(SettingsManager.shared.tacticalBackground)
    }
}

// MARK: - Sidebar Button Content (with hover state)

private struct SidebarButtonContent: View {
    let section: NavigationSection
    let icon: String
    let title: String
    let badge: String?
    let badgeColor: SwiftUI.Color
    let showSpinner: Bool
    let showStatusDot: Bool
    let statusDotColor: SwiftUI.Color
    let isSelected: Bool
    let isSidebarCollapsed: Bool
    let onTap: () -> Void
    let sectionName: String

    @State private var isHovering = false

    var body: some View {
        TalkieButtonSync("Navigate.\(sectionName)", section: "Sidebar", action: onTap) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: isSidebarCollapsed ? 14 : 12))
                        .foregroundColor(isSelected ? .white : Theme.current.foreground)
                        .frame(width: isSidebarCollapsed ? 20 : 16)

                    // Status dot indicator
                    if showStatusDot {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.accentColor : Theme.current.background, lineWidth: 1.5)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                // Text and badge - always present, opacity animated
                HStack {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : Theme.current.foreground)
                    Spacer()
                    if showSpinner {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                    }
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : badgeColor)
                    }
                }
                .opacity(isSidebarCollapsed ? 0 : 1)
                .frame(width: isSidebarCollapsed ? 0 : nil)
                .clipped()
            }
            .padding(.horizontal, isSidebarCollapsed ? 0 : 8)
            .padding(.vertical, isSidebarCollapsed ? 4 : 8)
            .frame(width: isSidebarCollapsed ? 36 : nil, height: isSidebarCollapsed ? 36 : nil)
            .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .offset(x: isSidebarCollapsed ? 3 : 0)
            .background(
                ZStack {
                    // Selected state
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    }
                    // Hover state (only show when not selected)
                    if isHovering && !isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.current.backgroundTertiary.opacity(0.5))
                    }
                }
            )
            .scaleEffect(isSelected ? 1.0 : 0.98)  // Subtle scale feedback
            .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(isSidebarCollapsed ? title : "")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
