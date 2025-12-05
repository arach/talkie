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

// MARK: - Workflow Column Views

struct WorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?
    @StateObject private var workflowManager = WorkflowManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKFLOWS")
                        .font(SettingsManager.shared.fontSMBold)
                        .tracking(1.5)
                    Text("\(workflowManager.workflows.count) total")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: createNewWorkflow) {
                    Image(systemName: "plus")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 24)
                        .background(settings.surfaceSelected)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(settings.surface1)

            Divider()

            // Workflow List
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(workflowManager.workflows) { workflow in
                        WorkflowListItem(
                            workflow: workflow,
                            isSelected: selectedWorkflowID == workflow.id,
                            isSystem: false,
                            onSelect: { selectWorkflow(workflow) },
                            onEdit: { selectWorkflow(workflow) }
                        )
                    }
                }
                .padding(8)
            }
        }
    }

    private func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func selectWorkflow(_ workflow: WorkflowDefinition) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow
        }
    }
}

struct WorkflowDetailColumn: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var editingWorkflow: WorkflowDefinition?
    @Binding var selectedWorkflowID: UUID?
    @ObservedObject private var workflowManager = WorkflowManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showingMemoSelector = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    /// Memos that need transcription (for TRANSCRIBE workflows like HQ Transcribe)
    private var untranscribedMemos: [VoiceMemo] {
        allMemos.filter { ($0.transcription == nil || $0.transcription!.isEmpty) && !$0.isTranscribing }
    }

    // Get fresh workflow from manager (source of truth)
    private var currentWorkflow: WorkflowDefinition? {
        guard let id = editingWorkflow?.id else { return nil }
        return workflowManager.workflows.first { $0.id == id }
    }

    var body: some View {
        Group {
            if editingWorkflow != nil {
                WorkflowInlineEditor(
                    workflow: $editingWorkflow,
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(SettingsManager.shared.fontXS)
                            Text("NEW WORKFLOW")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(0.5)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.surfaceSelected)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.surfaceInput)
            }
        }
        .sheet(isPresented: $showingMemoSelector) {
            // Use currentWorkflow from manager for fresh data
            if let workflow = currentWorkflow ?? editingWorkflow {
                // Use untranscribed memos for TRANSCRIBE workflows, transcribed for others
                let memosToShow = workflow.startsWithTranscribe ? untranscribedMemos : transcribedMemos
                WorkflowMemoSelectorSheet(
                    workflow: workflow,
                    memos: memosToShow,
                    onSelect: { memo in
                        runWorkflow(workflow, on: memo)
                        showingMemoSelector = false
                    },
                    onCancel: {
                        showingMemoSelector = false
                    }
                )
            }
        }
    }

    private func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func saveWorkflow() {
        // Use currentWorkflow from manager if available, otherwise fall back to binding
        guard var workflow = currentWorkflow ?? editingWorkflow else { return }
        workflow.modifiedAt = Date()

        if workflowManager.workflows.contains(where: { $0.id == workflow.id }) {
            workflowManager.updateWorkflow(workflow)
        } else {
            workflowManager.addWorkflow(workflow)
        }
        // Sync binding from manager
        editingWorkflow = workflowManager.workflows.first { $0.id == workflow.id }
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = currentWorkflow ?? editingWorkflow else { return }
        workflowManager.deleteWorkflow(workflow)
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = currentWorkflow ?? editingWorkflow else { return }
        let duplicate = workflowManager.duplicateWorkflow(workflow)
        editingWorkflow = duplicate
        selectedWorkflowID = duplicate.id
    }

    private func runWorkflow(_ workflow: WorkflowDefinition, on memo: VoiceMemo) {
        Task {
            do {
                let _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow,
                    for: memo,
                    context: viewContext
                )
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }
        }
    }
}

// MARK: - Column Resizer

struct ColumnResizer: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.blue : (isHovering ? Color.secondary.opacity(0.3) : Color.clear))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newWidth = width + value.translation.width
                        width = min(maxWidth, max(minWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

// MARK: - Activity Run Row Model (for native Table)

struct ActivityRunRow: Identifiable {
    let id: NSManagedObjectID
    let runId: UUID?
    let timestamp: Date
    let workflowName: String
    let memoTitle: String
    let isSuccess: Bool
    let durationMs: Int?
    let run: WorkflowRun

    init(from run: WorkflowRun) {
        self.id = run.objectID
        self.runId = run.id
        self.timestamp = run.runDate ?? Date.distantPast
        self.workflowName = run.workflowName ?? "Workflow"
        self.memoTitle = run.memo?.title ?? "Unknown"
        self.isSuccess = run.output != nil && !(run.output?.isEmpty ?? true)
        self.run = run

        // Calculate duration from step outputs
        if let json = run.stepOutputsJSON,
           let data = json.data(using: .utf8),
           let steps = try? JSONDecoder().decode([WorkflowExecutor.StepExecution].self, from: data),
           !steps.isEmpty {
            let totalChars = steps.reduce(0) { $0 + $1.output.count }
            self.durationMs = max(100, totalChars * 2)
        } else {
            self.durationMs = nil
        }
    }
}

// MARK: - Activity Log Full View (with Native Table)

struct ActivityLogFullView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkflowRun.runDate, ascending: false)],
        animation: .default
    )
    private var allRuns: FetchedResults<WorkflowRun>

    // Selection & Inspector state
    @State private var selectedRunId: NSManagedObjectID?
    @State private var showInspector: Bool = false

    // Sorting state for Table
    @State private var sortOrder = [KeyPathComparator(\ActivityRunRow.timestamp, order: .reverse)]

    // Inspector panel width (resizable)
    @State private var inspectorWidth: CGFloat = 380

    // Convert FetchedResults to row models, deduplicated
    private var tableRows: [ActivityRunRow] {
        var seen = Set<UUID>()
        return allRuns.compactMap { run -> ActivityRunRow? in
            if let runId = run.id {
                if seen.contains(runId) { return nil }
                seen.insert(runId)
            }
            return ActivityRunRow(from: run)
        }.sorted(using: sortOrder)
    }

    private var selectedRun: WorkflowRun? {
        guard let selectedId = selectedRunId else { return nil }
        return allRuns.first { $0.objectID == selectedId }
    }

    var body: some View {
        HSplitView {
            // Left side: Table
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.primary)

                    Text("Actions")
                        .font(SettingsManager.shared.fontTitleMedium)
                        .foregroundColor(.primary)

                    Text("\(allRuns.count) events")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(settings.surface1)

                Divider()

                if allRuns.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wand.and.rays")
                            .font(SettingsManager.shared.fontDisplay)
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO ACTIVITY YET")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Run workflows on your memos")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Native SwiftUI Table with resizable columns
                    Table(tableRows, selection: $selectedRunId, sortOrder: $sortOrder) {
                        TableColumn("Timestamp", value: \.timestamp) { row in
                            Text(formatTimestamp(row.timestamp))
                                .font(SettingsManager.shared.fontSM)
                                .foregroundColor(.secondary)
                        }
                        .width(min: 100, ideal: 150, max: 200)

                        TableColumn("Workflow", value: \.workflowName) { row in
                            Text(row.workflowName)
                                .font(SettingsManager.shared.fontBodyBold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 140, max: 250)

                        TableColumn("Memo", value: \.memoTitle) { row in
                            Text(row.memoTitle)
                                .font(SettingsManager.shared.fontSM)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 180, max: 300)

                        TableColumn("Status") { row in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(row.isSuccess ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)

                                if let ms = row.durationMs {
                                    Text(formatDurationMs(ms))
                                        .font(.monoSmall)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("--")
                                        .font(.monoSmall)
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                            }
                        }
                        .width(min: 60, ideal: 90, max: 120)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .frame(minWidth: 400, idealWidth: 550)
            .background(settings.surfaceInput)

            // Right side: Inspector (always visible)
            VStack(spacing: 0) {
                if let run = selectedRun {
                    // Show inspector content
                    ActivityInspectorPanel(
                        run: run,
                        onClose: { selectedRunId = nil },
                        onDelete: {
                            deleteRun(run)
                            selectedRunId = nil
                        }
                    )
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("SELECT AN ACTION")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Click a row to see details")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settings.surface1)
                }
            }
            .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
        }
        .onKeyPress(.escape) {
            if selectedRunId != nil {
                selectedRunId = nil
                return .handled
            }
            return .ignored
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, hh:mm a"
        return formatter.string(from: date)
    }

    private func formatDurationMs(_ ms: Int) -> String {
        if ms >= 1000 {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.2fs", seconds)
        } else {
            return "\(ms)ms"
        }
    }

    private func deleteRun(_ run: WorkflowRun) {
        viewContext.perform {
            viewContext.delete(run)
            try? viewContext.save()
        }
    }
}

// MARK: - Activity Inspector Panel

struct ActivityInspectorPanel: View {
    let run: WorkflowRun
    let onClose: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var modelId: String? { run.modelId }
    private var runDate: Date { run.runDate ?? Date() }
    private var memoTitle: String { run.memo?.title ?? "Unknown Memo" }

    private var stepExecutions: [WorkflowExecutor.StepExecution] {
        guard let json = run.stepOutputsJSON,
              let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([WorkflowExecutor.StepExecution].self, from: data)
        else { return [] }
        return steps
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inspector Header
            HStack(spacing: 10) {
                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                    .background(settings.surfaceInfo)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(workflowName)
                        .font(SettingsManager.shared.fontBodyMedium)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formatFullDate(runDate))
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)

                        if let runId = run.id {
                            Text(runId.uuidString.prefix(8).uppercased())
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                }

                Spacer()

                CloseButton(action: onClose)
                    .help("Close inspector")
            }
            .padding(12)
            .background(settings.surface1)

            Divider()

            // Memo reference
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(SettingsManager.shared.fontXS)
                Text("From: \(memoTitle)")
                    .font(SettingsManager.shared.fontXS)
                    .lineLimit(1)

                Spacer()

                if let model = modelId {
                    Text(model)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(settings.surfaceAlternate)
                        .cornerRadius(3)
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(settings.surface2)

            Divider()

            // Step-by-step content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("OUTPUT")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(2)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(settings.surface1)
                                    .cornerRadius(6)
                            }
                        }
                    } else {
                        ForEach(Array(stepExecutions.enumerated()), id: \.offset) { index, step in
                            InspectorStepCard(step: step, isLast: index == stepExecutions.count - 1)
                        }
                    }
                }
                .padding(12)
            }

            Divider()

            // Delete button at bottom, far from close
            HStack {
                Spacer()
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(SettingsManager.shared.fontXS)
                        Text("Delete Run")
                            .font(SettingsManager.shared.fontXSMedium)
                    }
                    .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this run")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(settings.surface2)
        }
        .background(settings.surfaceInput)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Inspector Step Card (Compact)

struct InspectorStepCard: View {
    let step: WorkflowExecutor.StepExecution
    let isLast: Bool
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(step.stepNumber)")
                    .font(SettingsManager.shared.fontXSBold)
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.blue)
                    .cornerRadius(3)

                Image(systemName: step.stepIcon)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(SettingsManager.shared.fontXSBold)
                    .tracking(0.5)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Image(systemName: showInput ? "chevron.up" : "chevron.down")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showInput {
                VStack(alignment: .leading, spacing: 3) {
                    Text("INPUT")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                        .lineSpacing(1)
                        .lineLimit(6)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(settings.surfaceAlternate)
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("OUTPUT")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("→ {{\(step.outputKey)}}")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(step.output)
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(settings.surface1)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .background(settings.surface2)
        .cornerRadius(6)
    }
}

// MARK: - Inspector Resize Handle

struct InspectorResizeHandle: View {
    @Binding var width: CGFloat
    @ObservedObject private var settings = SettingsManager.shared

    @State private var isHovering = false
    @State private var isDragging = false

    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 600

    var body: some View {
        Rectangle()
            .fill(isDragging ? settings.surfaceInfo : (isHovering ? settings.surfaceHover : settings.divider))
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // Dragging left increases width, dragging right decreases
                        let newWidth = width - value.translation.width
                        width = min(maxWidth, max(minWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

// MARK: - Legacy Tool Content Views (keeping for reference)

struct WorkflowsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var workflowManager = WorkflowManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var showingMemoSelector = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    /// Memos that need transcription (for TRANSCRIBE workflows like HQ Transcribe)
    private var untranscribedMemos: [VoiceMemo] {
        allMemos.filter { ($0.transcription == nil || $0.transcription!.isEmpty) && !$0.isTranscribing }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Workflow List
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WORKFLOWS")
                            .font(SettingsManager.shared.fontSMBold)
                            .tracking(1.5)
                        Text("\(workflowManager.workflows.count) total")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: createNewWorkflow) {
                        Image(systemName: "plus")
                            .font(SettingsManager.shared.fontBody)
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                            .background(settings.surfaceSelected)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)

                Divider()
                    .opacity(0.5)

                // Workflow List - unified, no sections
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(workflowManager.workflows) { workflow in
                            WorkflowListItem(
                                workflow: workflow,
                                isSelected: selectedWorkflowID == workflow.id,
                                isSystem: false,
                                onSelect: { selectWorkflow(workflow) },
                                onEdit: { selectWorkflow(workflow) }
                            )
                        }
                    }
                    .padding(8)
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            .background(settings.surface1)

            Divider()
                .opacity(0.5)

            // Right: Inline Editor - expands to fill
            if editingWorkflow != nil {
                WorkflowInlineEditor(
                    workflow: $editingWorkflow,
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(SettingsManager.shared.fontXS)
                            Text("NEW WORKFLOW")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(0.5)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.surfaceSelected)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.surfaceInput)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingMemoSelector) {
            if let workflow = editingWorkflow {
                // Use untranscribed memos for TRANSCRIBE workflows, transcribed for others
                let memosToShow = workflow.startsWithTranscribe ? untranscribedMemos : transcribedMemos
                WorkflowMemoSelectorSheet(
                    workflow: workflow,
                    memos: memosToShow,
                    onSelect: { memo in
                        runWorkflow(workflow, on: memo)
                        showingMemoSelector = false
                    },
                    onCancel: {
                        showingMemoSelector = false
                    }
                )
            }
        }
    }

    private func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func selectWorkflow(_ workflow: WorkflowDefinition) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow
        }
    }

    private func saveWorkflow() {
        guard var workflow = editingWorkflow else { return }
        workflow.modifiedAt = Date()

        if workflowManager.workflows.contains(where: { $0.id == workflow.id }) {
            workflowManager.updateWorkflow(workflow)
        } else {
            workflowManager.addWorkflow(workflow)
        }
        editingWorkflow = workflow
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = editingWorkflow else { return }
        workflowManager.deleteWorkflow(workflow)
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = editingWorkflow else { return }
        let duplicate = workflowManager.duplicateWorkflow(workflow)
        editingWorkflow = duplicate
        selectedWorkflowID = duplicate.id
    }

    private func runWorkflow(_ workflow: WorkflowDefinition, on memo: VoiceMemo) {
        Task {
            do {
                let _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow,
                    for: memo,
                    context: viewContext
                )
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }
        }
    }
}

// MARK: - Workflow Memo Selector Sheet

struct WorkflowMemoSelectorSheet: View {
    let workflow: WorkflowDefinition
    let memos: [VoiceMemo]
    let onSelect: (VoiceMemo) -> Void
    let onCancel: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    @State private var selectedMemo: VoiceMemo?
    @State private var searchText = ""

    private var filteredMemos: [VoiceMemo] {
        if searchText.isEmpty {
            return memos
        }
        let query = searchText.lowercased()
        return memos.filter {
            ($0.title?.lowercased().contains(query) ?? false) ||
            ($0.transcription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(SettingsManager.shared.fontTitleBold)
                    HStack(spacing: 6) {
                        Image(systemName: workflow.icon)
                            .foregroundColor(workflow.color.color)
                        Text(workflow.name)
                            .font(SettingsManager.shared.fontBody)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(settings.surface1)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if memos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Transcribed Memos")
                        .font(SettingsManager.shared.fontBodyMedium)
                        .foregroundColor(.secondary)

                    Text("Record and transcribe a voice memo first")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMemos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No matching memos")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        MemoRowView(memo: memo)
                            .tag(memo)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(memo)
                            }
                            .onTapGesture(count: 1) {
                                selectedMemo = memo
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer with action button
            HStack {
                Text("\(filteredMemos.count) memo\(filteredMemos.count == 1 ? "" : "s")")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    if let memo = selectedMemo {
                        onSelect(memo)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMemo == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(16)
        }
        .frame(width: 500, height: 500)
        .background(settings.surfaceInput)
    }
}

struct WorkflowCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared
    let icon: String
    let title: String
    let description: String
    let actionType: WorkflowActionType
    let provider: String
    let model: String

    @State private var showingMemoSelector = false
    @State private var isExecuting = false
    @State private var errorMessage: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    var body: some View {
        Button(action: {
            if !transcribedMemos.isEmpty {
                showingMemoSelector = true
            } else {
                errorMessage = "No transcribed memos available"
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(settings.surfaceHover)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(SettingsManager.shared.fontSMBold)
                        .tracking(0.5)

                    Text(description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)

                    if isExecuting {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("RUNNING...")
                                .font(SettingsManager.shared.fontXSMedium)
                                .tracking(0.5)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(12)
            .background(settings.surface1)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .sheet(isPresented: $showingMemoSelector) {
            MemoSelectorSheet(
                memos: transcribedMemos,
                actionType: actionType,
                provider: provider,
                model: model,
                onExecute: { memo in
                    executeWorkflow(for: memo)
                }
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func executeWorkflow(for memo: VoiceMemo) {
        isExecuting = true
        showingMemoSelector = false

        Task {
            do {
                try await WorkflowExecutor.shared.execute(
                    action: actionType,
                    for: memo,
                    providerName: provider,
                    modelId: model,
                    context: viewContext
                )
                await MainActor.run {
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExecuting = false
                }
            }
        }
    }
}

struct MemoSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    let memos: [VoiceMemo]
    let actionType: WorkflowActionType
    let provider: String
    let model: String
    let onExecute: (VoiceMemo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Memo")
                    .font(SettingsManager.shared.fontTitleBold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Memo list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(memos) { memo in
                        Button(action: {
                            onExecute(memo)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(SettingsManager.shared.fontTitle)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memo.title ?? "Untitled")
                                        .font(SettingsManager.shared.fontBodyMedium)
                                        .lineLimit(1)

                                    if let date = memo.createdAt {
                                        Text(date, style: .relative)
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(settings.surface1)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 400, height: 500)
        .background(settings.surfaceInput)
    }
}

// MARK: - Activity Log View

struct AIResultsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkflowRun.runDate, ascending: false)],
        animation: .default
    )
    private var allRuns: FetchedResults<WorkflowRun>

    @State private var selectedRun: WorkflowRun?
    @State private var selectedMemoId: NSManagedObjectID?

    // Group runs by memo
    private var runsByMemo: [(memo: VoiceMemo, runs: [WorkflowRun])] {
        let grouped = Dictionary(grouping: allRuns) { $0.memo }
        return grouped.compactMap { (memo, runs) -> (VoiceMemo, [WorkflowRun])? in
            guard let memo = memo else { return nil }
            return (memo, runs.sorted { ($0.runDate ?? .distantPast) > ($1.runDate ?? .distantPast) })
        }.sorted { ($0.runs.first?.runDate ?? .distantPast) > ($1.runs.first?.runDate ?? .distantPast) }
    }

    var body: some View {
        HSplitView {
            // Left: List of memos with runs
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(SettingsManager.shared.fontTitle)
                        Text("ACTIVITY LOG")
                            .font(SettingsManager.shared.fontBodyBold)
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("All workflow runs across your memos")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(settings.surface1)

                Divider()

                if runsByMemo.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wand.and.rays")
                            .font(SettingsManager.shared.fontDisplay)
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO RESULTS YET")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Run workflows on your memos")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                            ForEach(runsByMemo, id: \.memo.id) { item in
                                Section {
                                    ForEach(item.runs, id: \.id) { run in
                                        AIRunRowView(
                                            run: run,
                                            isSelected: selectedRun?.id == run.id,
                                            onSelect: { selectedRun = run }
                                        )
                                    }
                                } header: {
                                    AIMemoHeaderView(memo: item.memo, runCount: item.runs.count)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 350)
            .background(settings.surfaceInput)

            // Right: Detail view
            if let run = selectedRun {
                AIRunDetailView(run: run, onDelete: {
                    deleteRun(run)
                    selectedRun = nil
                })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("SELECT A RUN")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)
                    Text("Choose a workflow run to view details")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.surfaceInput)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteRun(_ run: WorkflowRun) {
        viewContext.perform {
            viewContext.delete(run)
            try? viewContext.save()
        }
    }
}

// MARK: - Memo Header in Activity Log
struct AIMemoHeaderView: View {
    let memo: VoiceMemo
    let runCount: Int
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(SettingsManager.shared.fontSM)
                .foregroundColor(.secondary)

            Text(memo.title ?? "Untitled")
                .font(SettingsManager.shared.fontSMBold)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(runCount)")
                .font(SettingsManager.shared.fontXSBold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(settings.surfaceAlternate)
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(settings.surface2)
    }
}

// MARK: - Run Row in Activity Log List
struct AIRunRowView: View {
    let run: WorkflowRun
    let isSelected: Bool
    let onSelect: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    @State private var isHovering = false

    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var modelId: String? { run.modelId }
    private var runDate: Date { run.runDate ?? Date() }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Workflow icon
                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? Color.blue : Color.primary.opacity(0.05))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflowName)
                        .font(SettingsManager.shared.fontSMMedium)
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let model = modelId {
                            Text(model)
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                        }

                        Text(formatDate(runDate))
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 44)
            .background(isSelected ? Color.blue : (isHovering ? settings.surfaceHover : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Run Detail View in Activity Log
struct AIRunDetailView: View {
    let run: WorkflowRun
    let onDelete: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var providerName: String? { run.providerName }
    private var modelId: String? { run.modelId }
    private var runDate: Date { run.runDate ?? Date() }
    private var memoTitle: String { run.memo?.title ?? "Unknown Memo" }

    private var stepExecutions: [WorkflowExecutor.StepExecution] {
        guard let json = run.stepOutputsJSON,
              let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([WorkflowExecutor.StepExecution].self, from: data)
        else { return [] }
        return steps
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                // Workflow info
                HStack(spacing: 10) {
                    Image(systemName: workflowIcon)
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(settings.surfaceInfo)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflowName)
                            .font(SettingsManager.shared.fontTitleMedium)

                        HStack(spacing: 8) {
                            if let model = modelId {
                                Text(model)
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(settings.surfaceAlternate)
                                    .cornerRadius(3)
                            }

                            Text(formatFullDate(runDate))
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary.opacity(0.6))

                            if let runId = run.id {
                                Text(runId.uuidString.prefix(8).uppercased())
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                    }

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(SettingsManager.shared.fontBody)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Memo reference
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(SettingsManager.shared.fontXS)
                    Text("From: \(memoTitle)")
                        .font(SettingsManager.shared.fontXS)
                }
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(16)
            .background(settings.surface1)

            Divider()

            // Step-by-step content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OUTPUT")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(SettingsManager.shared.fontBody)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(settings.surface1)
                                    .cornerRadius(6)
                            }
                        }
                    } else {
                        ForEach(Array(stepExecutions.enumerated()), id: \.offset) { index, step in
                            AIStepCard(step: step, isLast: index == stepExecutions.count - 1)

                            if index < stepExecutions.count - 1 {
                                HStack {
                                    Spacer().frame(width: 14)
                                    VStack(spacing: 2) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            Circle()
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 3, height: 3)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(settings.surfaceInput)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Step Card in Activity Log
struct AIStepCard: View {
    let step: WorkflowExecutor.StepExecution
    let isLast: Bool
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(step.stepNumber)")
                    .font(SettingsManager.shared.fontXSBold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(SettingsManager.shared.fontXSBold)
                    .tracking(0.5)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(SettingsManager.shared.fontXSMedium)
                        .tracking(0.3)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            if showInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INPUT")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(settings.surfaceAlternate)
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OUTPUT")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("→ {{\(step.outputKey)}}")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(step.output)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(settings.surface1)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(settings.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ActivityLogContentView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(SettingsManager.shared.fontHeadline)
                        Text("ACTIVITY LOG")
                            .font(SettingsManager.shared.fontTitleBold)
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("View workflow execution history and results.")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Activity log with workflow execution history")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.surfaceInput)
    }
}

// ModelsContentView is now in its own file: ModelsContentView.swift

// MARK: - Memo Table Sort Field

enum MemoSortField: String, CaseIterable {
    case timestamp = "TIMESTAMP"
    case title = "TITLE"
    case duration = "DURATION"
    case workflows = "WORKFLOWS"
}

// MARK: - Memo Table Full View (with Inspector Panel)

struct MemoTableFullView: View {
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

    // Selection & Inspector state
    @State private var selectedMemo: VoiceMemo?
    @State private var showInspector: Bool = false

    // Sorting state
    @State private var sortField: MemoSortField = .timestamp
    @State private var sortAscending: Bool = false

    // Column widths (resizable)
    @State private var timestampWidth: CGFloat = 150
    @State private var titleWidth: CGFloat = 280
    @State private var durationWidth: CGFloat = 80
    @State private var workflowsWidth: CGFloat = 100

    // Inspector panel width (resizable)
    @State private var inspectorWidth: CGFloat = 420

    // Sorted memos based on current sort state
    private var sortedMemos: [VoiceMemo] {
        let memos = Array(allMemos)
        return memos.sorted { a, b in
            let result: Bool
            switch sortField {
            case .timestamp:
                result = (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            case .title:
                result = (a.title ?? "") < (b.title ?? "")
            case .duration:
                result = a.duration > b.duration
            case .workflows:
                result = (a.workflowRuns?.count ?? 0) > (b.workflowRuns?.count ?? 0)
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main table content (full width, always visible)
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 4) {
                    Text("All Memos")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(SettingsManager.shared.tacticalForeground)
                        .textCase(SettingsManager.shared.uiTextCase)

                    Text("\(allMemos.count)")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)

                    Spacer()

                    // Inspector toggle button
                    if selectedMemo != nil {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInspector.toggle() } }) {
                            Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(showInspector ? .blue : SettingsManager.shared.tacticalForegroundSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(showInspector ? "Hide Details" : "Show Details")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SettingsManager.shared.tacticalBackgroundSecondary)

                Divider()

                if allMemos.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "waveform.slash")
                            .font(SettingsManager.shared.fontDisplay)
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO MEMOS YET")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Record your first voice memo on iOS")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Table header with sortable columns
                    MemoTableHeader(
                        sortField: $sortField,
                        sortAscending: $sortAscending,
                        timestampWidth: $timestampWidth,
                        titleWidth: $titleWidth,
                        durationWidth: $durationWidth,
                        workflowsWidth: $workflowsWidth
                    )

                    Divider()

                    // Table rows
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedMemos, id: \.id) { memo in
                                MemoTableRow(
                                    memo: memo,
                                    isSelected: selectedMemo?.id == memo.id,
                                    onSelect: {
                                        selectedMemo = memo
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showInspector = true
                                        }
                                    },
                                    timestampWidth: timestampWidth,
                                    titleWidth: titleWidth,
                                    durationWidth: durationWidth,
                                    workflowsWidth: workflowsWidth
                                )

                                Rectangle()
                                    .fill(SettingsManager.shared.tacticalDivider.opacity(0.25))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .background(SettingsManager.shared.tacticalBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsManager.shared.tacticalBackground)

            // Inspector Panel (overlays from right, anchored to right edge)
            if showInspector, let memo = selectedMemo {
                HStack(spacing: 0) {
                    // Resizable divider (on left side of inspector)
                    InspectorResizeHandle(width: $inspectorWidth)

                    MemoInspectorPanel(
                        memo: memo,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showInspector = false
                            }
                        }
                    )
                    .frame(width: inspectorWidth)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: -1, y: 0)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onKeyPress(.escape) {
            if showInspector {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector = false
                }
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Memo Table Header

struct MemoTableHeader: View {
    @Binding var sortField: MemoSortField
    @Binding var sortAscending: Bool
    @Binding var timestampWidth: CGFloat
    @Binding var titleWidth: CGFloat
    @Binding var durationWidth: CGFloat
    @Binding var workflowsWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            MemoSortableColumnHeader(
                title: "TIMESTAMP",
                field: .timestamp,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: timestampWidth
            )
            ColumnResizer(width: $timestampWidth, minWidth: 100, maxWidth: 200)

            MemoSortableColumnHeader(
                title: "TITLE",
                field: .title,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: titleWidth
            )
            ColumnResizer(width: $titleWidth, minWidth: 120, maxWidth: 400)

            MemoSortableColumnHeader(
                title: "DURATION",
                field: .duration,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: durationWidth,
                alignment: .trailing
            )
            ColumnResizer(width: $durationWidth, minWidth: 60, maxWidth: 120)

            MemoSortableColumnHeader(
                title: "WORKFLOWS",
                field: .workflows,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: workflowsWidth,
                alignment: .trailing
            )

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 26)
        .background(SettingsManager.shared.tacticalBackgroundSecondary)
    }
}

// MARK: - Memo Sortable Column Header

struct MemoSortableColumnHeader: View {
    let title: String
    let field: MemoSortField
    @Binding var currentSort: MemoSortField
    @Binding var ascending: Bool
    let width: CGFloat
    var alignment: Alignment = .leading

    @ObservedObject private var settings = SettingsManager.shared
    @State private var isHovering = false

    private var isSorted: Bool { currentSort == field }

    var body: some View {
        Button(action: {
            if currentSort == field {
                ascending.toggle()
            } else {
                currentSort = field
                ascending = false
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer() }

                Text(title)
                    .font(SettingsManager.shared.fontSMMedium)
                    .foregroundColor(isSorted ? .primary : .secondary)

                if isSorted {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.blue)
                }

                if alignment == .leading { Spacer() }
            }
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 2)
            .background(isHovering ? settings.surfaceHover : Color.clear)
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Memo Table Row

struct MemoTableRow: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject private var settings = SettingsManager.shared
    let isSelected: Bool
    let onSelect: () -> Void
    let timestampWidth: CGFloat
    let titleWidth: CGFloat
    let durationWidth: CGFloat
    let workflowsWidth: CGFloat

    @State private var isHovering = false

    private var workflowCount: Int {
        memo.workflowRuns?.count ?? 0
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Timestamp
                Text(formatTimestamp(memo.createdAt ?? Date()))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                    .frame(width: timestampWidth, alignment: .leading)

                // Title
                Text(memo.title ?? "Untitled")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForeground)
                    .lineLimit(1)
                    .frame(width: titleWidth, alignment: .leading)

                // Duration
                Text(formatDuration(memo.duration))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                    .frame(width: durationWidth, alignment: .trailing)

                // Workflow count
                HStack(spacing: 3) {
                    if workflowCount > 0 {
                        Image(systemName: "wand.and.stars")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.blue.opacity(0.8))
                        Text("\(workflowCount)")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.blue)
                    } else {
                        Text("—")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(SettingsManager.shared.tacticalForegroundMuted.opacity(0.5))
                    }
                }
                .frame(width: workflowsWidth, alignment: .trailing)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.blue.opacity(0.15) :
                    (isHovering ? SettingsManager.shared.tacticalBackgroundTertiary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"  // 24hr for tactical look
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Memo Inspector Panel

struct MemoInspectorPanel: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject private var settings = SettingsManager.shared
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Minimal inspector toolbar
            HStack {
                Text("DETAILS")
                    .font(SettingsManager.shared.fontXSBold)
                    .tracking(1)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)

                Spacer()

                CloseButton(action: onClose)
                    .help("Close inspector (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SettingsManager.shared.tacticalBackgroundSecondary)

            Rectangle()
                .fill(SettingsManager.shared.tacticalDivider)
                .frame(height: 0.5)

            // Embed MemoDetailView without redundant header
            MemoDetailView(memo: memo, showHeader: false)
        }
        .background(SettingsManager.shared.tacticalBackground)
    }
}

// MARK: - Close Button

/// Reusable close button with extended hit target and hover highlight
struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Extended hit area to the left (invisible)
                Color.clear
                    .frame(width: 16)

                // Visual button area with highlight
                Image(systemName: "xmark")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(isHovering
                        ? SettingsManager.shared.tacticalForeground
                        : SettingsManager.shared.tacticalForegroundSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovering
                                ? SettingsManager.shared.tacticalForegroundMuted.opacity(0.15)
                                : Color.clear)
                    )
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}
