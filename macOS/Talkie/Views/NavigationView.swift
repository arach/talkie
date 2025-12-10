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
    case models
    case allowedCommands
    case smartFolder(String)
}

struct TalkieNavigationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared

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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var eventManager = SystemEventManager.shared
    @StateObject private var pendingActionsManager = PendingActionsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ZStack(alignment: .topLeading) {
                Group {
                    if isTwoColumnSection {
                        // 2-column layout for Models, etc.
                        NavigationSplitView(columnVisibility: $columnVisibility) {
                            sidebarView
                        } detail: {
                            twoColumnDetailView
                        }
                    } else {
                        // 3-column layout for Memos, Workflows, AI Results
                        NavigationSplitView(columnVisibility: $columnVisibility) {
                            sidebarView
                        } content: {
                            contentColumnView
                                .frame(minWidth: 280, idealWidth: 320)
                        } detail: {
                            detailColumnView
                        }
                        .navigationSplitViewStyle(.prominentDetail)
                    }
                }

                // Floating sidebar toggle button (shows when sidebar is collapsed)
                if columnVisibility == .detailOnly {
                    Button(action: { toggleSidebar() }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Show Sidebar")
                    .padding(.top, 8)
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            // Full-width status bar (like VS Code/Cursor)
            statusBarView
        }
        .animation(.easeInOut(duration: 0.2), value: columnVisibility)
        .focusedValue(\.sidebarToggle, SidebarToggleAction(toggle: toggleSidebar))
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

    @StateObject private var syncManager = SyncStatusManager.shared

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
                .background(Color.white.opacity(0.05))
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
                .font(SettingsManager.shared.fontXSBold)
                .tracking(1)
                .foregroundColor(.orange.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(settings.surfaceWarning)
                .cornerRadius(3)
            #endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SettingsManager.shared.tacticalBackgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(SettingsManager.shared.tacticalDivider),
            alignment: .top
        )
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

    // MARK: - Sidebar View

    @State private var showingSettings = false

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TALKIE")
                    .font(SettingsManager.shared.fontSMBold)
                    .tracking(2)
                    .foregroundColor(SettingsManager.shared.tacticalForeground)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(SettingsManager.shared.tacticalDivider)
                .frame(height: 0.5)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(SettingsManager.shared.tacticalForeground)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SettingsManager.shared.tacticalBackgroundTertiary)
            .cornerRadius(4)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Navigation sections
            List(selection: $selectedSection) {
                Section(header: Text("Memos")
                    .font(SettingsManager.shared.fontXSMedium)
                    .textCase(SettingsManager.shared.uiTextCase)
                    .foregroundColor(.secondary.opacity(0.6))
                ) {
                    NavigationLink(value: NavigationSection.allMemos) {
                        Label {
                            HStack {
                                Text("All Memos")
                                    .font(SettingsManager.shared.fontSM)
                                    .textCase(SettingsManager.shared.uiTextCase)
                                Spacer()
                                Text("\(allMemos.count)")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.stack")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }
                }
                .collapsible(false)

                // Activity section - Actions + Pending Actions
                Section(header: Text("Activity")
                    .font(SettingsManager.shared.fontXSMedium)
                    .textCase(SettingsManager.shared.uiTextCase)
                    .foregroundColor(.secondary.opacity(0.6))
                ) {
                    NavigationLink(value: NavigationSection.aiResults) {
                        Label {
                            Text("Actions")
                                .font(SettingsManager.shared.fontSM)
                                .textCase(SettingsManager.shared.uiTextCase)
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }

                    NavigationLink(value: NavigationSection.pendingActions) {
                        Label {
                            HStack {
                                Text("Pending Actions")
                                    .font(SettingsManager.shared.fontSM)
                                    .textCase(SettingsManager.shared.uiTextCase)
                                Spacer()
                                // Show count badge if there are active actions
                                if pendingActionsManager.hasActiveActions {
                                    HStack(spacing: 3) {
                                        ProgressView()
                                            .scaleEffect(0.4)
                                            .frame(width: 10, height: 10)
                                        Text("\(pendingActionsManager.activeCount)")
                                            .font(SettingsManager.shared.fontXS)
                                    }
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(8)
                                }
                            }
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }
                }
                .collapsible(false)

                // Tools section - Workflows, Models, Console
                Section(header: Text("Tools")
                    .font(SettingsManager.shared.fontXSMedium)
                    .textCase(SettingsManager.shared.uiTextCase)
                    .foregroundColor(.secondary.opacity(0.6))
                ) {
                    NavigationLink(value: NavigationSection.workflows) {
                        Label {
                            Text("Workflows")
                                .font(SettingsManager.shared.fontSM)
                                .textCase(SettingsManager.shared.uiTextCase)
                        } icon: {
                            Image(systemName: "wand.and.stars")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }

                    NavigationLink(value: NavigationSection.models) {
                        Label {
                            Text("Models")
                                .font(SettingsManager.shared.fontSM)
                                .textCase(SettingsManager.shared.uiTextCase)
                        } icon: {
                            Image(systemName: "brain")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }

                    NavigationLink(value: NavigationSection.systemConsole) {
                        Label {
                            HStack {
                                Text("Console")
                                    .font(SettingsManager.shared.fontSM)
                                    .textCase(SettingsManager.shared.uiTextCase)
                                Spacer()
                                // Show indicator if there are recent errors
                                if consoleErrorCount > 0 {
                                    Text("\(consoleErrorCount)")
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                }
                            }
                        } icon: {
                            Image(systemName: "terminal")
                                .font(SettingsManager.shared.fontXS)
                        }
                    }
                }
                .collapsible(false)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // Footer - Settings button at bottom of sidebar
            Divider()

            Button(action: { showingSettings = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(SettingsManager.shared.fontXS)
                    Text("Settings")
                        .font(SettingsManager.shared.fontSM)
                        .textCase(SettingsManager.shared.uiTextCase)
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 180, idealWidth: 200)
        .background(SettingsManager.shared.tacticalBackground)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 900, height: 750, alignment: .topLeading)
        }
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
        default:
            EmptyView()
        }
    }

    // MARK: - Column Views

    /// Toggle sidebar visibility
    private func toggleSidebar() {
        withAnimation {
            switch columnVisibility {
            case .all:
                columnVisibility = .detailOnly
            case .detailOnly:
                columnVisibility = .all
            default:
                columnVisibility = .all
            }
        }
    }

    /// Whether the current section uses a 2-column layout (sidebar + full content)
    /// vs 3-column layout (sidebar + list + detail)
    private var isTwoColumnSection: Bool {
        switch selectedSection {
        case .models, .allowedCommands, .aiResults, .allMemos, .systemConsole, .pendingActions:
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
                        .font(SettingsManager.shared.fontBodyBold)
                        .tracking(2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.surfaceInput)
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
        case .models: return "MODELS"
        case .allowedCommands: return "ALLOWED COMMANDS"
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
            // Section header
            HStack(spacing: 6) {
                Text(sectionTitle)
                    .font(SettingsManager.shared.fontSMMedium)
                    .foregroundColor(SettingsManager.shared.tacticalForeground)

                if let subtitle = sectionSubtitle {
                    Text(subtitle)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SettingsManager.shared.tacticalBackgroundSecondary)

            Divider()

            // Memo list
            if filteredMemos.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)

                    Text("NO MEMOS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)

                    Text("Record on iPhone to sync")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
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

