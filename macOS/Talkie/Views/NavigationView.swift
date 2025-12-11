//
//  NavigationView.swift
//  Talkie macOS
//
//  EchoFlow-style navigation with Tools, Library, and Smart Folders
//

import SwiftUI
import CoreData

enum NavigationSection: Hashable {
    case allMemos
    case aiResults
    case workflows
    case activityLog
    case systemConsole
    case pendingActions
    case talkieService
    case models
    case allowedCommands
    case settings
    case smartFolder(String)
}

struct TalkieNavigationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    // Use let for singletons - @ObservedObject causes full rerender on every settings change
    private let settings = SettingsManager.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    @State private var selectedSection: NavigationSection? = .allMemos
    @State private var previousSection: NavigationSection? = .allMemos
    @State private var selectedMemo: VoiceMemo?
    @State private var searchText = ""
    @State private var showConsolePopover = false
    // Use let for singletons to avoid unnecessary view updates
    private let eventManager = SystemEventManager.shared
    private let pendingActionsManager = PendingActionsManager.shared
    // TalkieServiceMonitor needs ObservedObject to show live status dot updates
    @ObservedObject private var talkieServiceMonitor = TalkieServiceMonitor.shared

    // Collapsible sidebar state (matches TalkieLive)
    @State private var isSidebarCollapsed: Bool = false
    @State private var isChevronHovered: Bool = false

    // Sidebar width constants - use fixed values to avoid NavigationSplitView recalculations
    private let sidebarExpandedWidth: CGFloat = 180
    private let sidebarCollapsedWidth: CGFloat = 56

    private var currentSidebarWidth: CGFloat {
        isSidebarCollapsed ? sidebarCollapsedWidth : sidebarExpandedWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area - HStack for manual sidebar control (avoids NavigationSplitView layout issues)
            HStack(spacing: 0) {
                // Sidebar with animated width
                sidebarView
                    .frame(width: currentSidebarWidth)
                    .clipped()

                // Divider between sidebar and content
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(width: 1)

                // Main content area
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
            }

            // Full-width status bar (like VS Code/Cursor)
            statusBarView
        }
        .animation(.snappy(duration: 0.2), value: isSidebarCollapsed)
        .focusedValue(\.sidebarToggle, SidebarToggleAction(toggle: toggleSidebar))
        .focusedValue(\.settingsNavigation, SettingsNavigationAction(showSettings: { selectedSection = .settings }))
        .onChange(of: allMemos.count) { _, _ in
            // Mark any new memos as received when they appear in the list
            PersistenceController.markMemosAsReceivedByMac(context: viewContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browseWorkflows)) { _ in
            // Navigate to Workflows section when "MORE" button is clicked
            selectedSection = .workflows
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

    // Console event counts (for status bar indicators)
    private var consoleErrorCount: Int {
        eventManager.events.prefix(100).filter { $0.type == .error }.count
    }

    private var consoleWorkflowCount: Int {
        eventManager.events.prefix(100).filter { $0.type == .workflow }.count
    }

    private var statusBarView: some View {
        HStack(spacing: 12) {
            // Left side - iCloud sync status (clickable to sync)
            Button(action: {
                CloudKitSyncManager.shared.recordActivity() // Boost to active interval
                CloudKitSyncManager.shared.syncNow()
            }) {
                HStack(spacing: 6) {
                    syncStatusIcon
                    syncStatusText
                }
            }
            .buttonStyle(.plain)
            .help("Click to sync now")

            // Manual sync button
            Button(action: {
                CloudKitSyncManager.shared.recordActivity()
                CloudKitSyncManager.shared.syncNow()
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Sync now")
            .disabled(syncManager.state == .syncing)

            Divider()
                .frame(height: 12)

            // Memo count
            HStack(spacing: 4) {
                Image(systemName: "square.stack")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
                Text("\(allMemos.count) memos")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Console button - opens log popover with error/warning counts
            Button(action: { showConsolePopover.toggle() }) {
                HStack(spacing: 6) {
                    // Error count (red)
                    if consoleErrorCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                            Text("\(consoleErrorCount)")
                                .font(SettingsManager.shared.fontXS)
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }

                    // Workflow count (amber)
                    if consoleWorkflowCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("\(consoleWorkflowCount)")
                                .font(SettingsManager.shared.fontXS)
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.3))
                    }

                    // Terminal icon
                    Image(systemName: "terminal")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.current.backgroundTertiary.opacity(0.5))
                .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConsolePopover, arrowEdge: .bottom) {
                SystemConsoleView(onPopOut: {
                    showConsolePopover = false
                    previousSection = selectedSection  // Remember where we were
                    selectedSection = .systemConsole
                })
                .frame(width: 600, height: 350)
            }

            // Right side - DEV indicator (only in debug builds)
            #if DEBUG
            Text("DEV")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.orange.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(settings.surfaceWarning)
                .cornerRadius(3)
            #endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.current.backgroundSecondary)
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncManager.state {
        case .synced:
            Image(systemName: "checkmark.icloud")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.green)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.blue)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.orange)
        case .idle:
            Image(systemName: "icloud")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var syncStatusText: some View {
        switch syncManager.state {
        case .synced:
            Text("Synced \(syncManager.lastSyncAgo)")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        case .syncing:
            Text("Syncing...")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.blue)
        case .error(let message):
            Text(message)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.orange)
        case .idle:
            Text("iCloud")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sidebar View (matches TalkieLive structure)


    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header with collapse toggle (matches TalkieLive)
            sidebarHeader

            // Navigation content
            if isSidebarCollapsed {
                // Collapsed: simple VStack, no scroll, natural sizing
                VStack(spacing: 0) {
                    sidebarButton(section: .allMemos, icon: "square.stack", title: "All Memos", badge: allMemos.count > 0 ? "\(allMemos.count)" : nil, badgeColor: .secondary)
                    sidebarButton(section: .aiResults, icon: "chart.line.uptrend.xyaxis", title: "Actions")
                    sidebarButton(section: .pendingActions, icon: "clock.arrow.circlepath", title: "Pending", badge: pendingActionsManager.hasActiveActions ? "\(pendingActionsManager.activeCount)" : nil, badgeColor: .accentColor, showSpinner: pendingActionsManager.hasActiveActions)
                    sidebarButton(section: .workflows, icon: "wand.and.stars", title: "Workflows")
                    sidebarButton(section: .models, icon: "brain", title: "Models")
                    sidebarButton(section: .talkieService, icon: "gearshape.2", title: "Service", badge: nil, badgeColor: talkieServiceMonitor.state == .running ? .green : .red, showStatusDot: true, statusDotColor: talkieServiceMonitor.state == .running ? .green : .red)
                    sidebarButton(section: .systemConsole, icon: "terminal", title: "Console", badge: consoleErrorCount > 0 ? "\(consoleErrorCount)" : nil, badgeColor: .orange)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Expanded: ScrollView with sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Memos section
                        sidebarSectionHeader("Memos")
                        sidebarButton(
                            section: .allMemos,
                            icon: "square.stack",
                            title: "All Memos",
                            badge: allMemos.count > 0 ? "\(allMemos.count)" : nil,
                            badgeColor: .secondary
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
                            section: .talkieService,
                            icon: "gearshape.2",
                            title: "Talkie Service",
                            showStatusDot: true,
                            statusDotColor: talkieServiceMonitor.state == .running ? .green : .red
                        )
                        sidebarButton(
                            section: .systemConsole,
                            icon: "terminal",
                            title: "Console",
                            badge: consoleErrorCount > 0 ? "\(consoleErrorCount)" : nil,
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

    /// Custom sidebar button with controlled selection styling
    @ViewBuilder
    private func sidebarButton(
        section: NavigationSection,
        icon: String,
        title: String,
        badge: String? = nil,
        badgeColor: Color = .secondary,
        showSpinner: Bool = false,
        showStatusDot: Bool = false,
        statusDotColor: Color = .gray
    ) -> some View {
        let isSelected = selectedSection == section

        Button(action: { selectedSection = section }) {
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
                                    .stroke(isSelected ? Color.accentColor : settings.tacticalBackground, lineWidth: 1.5)
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(isSidebarCollapsed ? title : "")
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
        case .models:
            ModelsContentView()
        case .allowedCommands:
            AllowedCommandsView()
        case .aiResults:
            ActivityLogFullView()
        case .allMemos:
            MemoTableFullView()
        case .systemConsole:
            SystemConsoleView(onClose: {
                // Return to previous section, or allMemos if none
                selectedSection = previousSection ?? .allMemos
            })
        case .pendingActions:
            PendingActionsView()
        case .talkieService:
            TalkieServiceMonitorView()
        case .settings:
            SettingsView()
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
        case .models, .allowedCommands, .aiResults, .allMemos, .systemConsole, .pendingActions, .talkieService, .settings:
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
            WorkflowDetailColumn(
                editingWorkflow: $editingWorkflow,
                selectedWorkflowID: $selectedWorkflowID
            )
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
        case .allMemos: return "ALL MEMOS"
        case .aiResults: return "ACTIVITY LOG"
        case .workflows: return "WORKFLOWS"
        case .activityLog: return "ACTIVITY LOG"
        case .systemConsole: return "CONSOLE"
        case .pendingActions: return "PENDING ACTIONS"
        case .talkieService: return "TALKIE SERVICE"
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

