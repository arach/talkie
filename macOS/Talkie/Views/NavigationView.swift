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
    case recent
    case processed
    case archived
    case aiResults
    case workflows
    case activityLog
    case models
    case smartFolder(String)
}

struct TalkieNavigationView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    @State private var selectedSection: NavigationSection? = .allMemos
    @State private var selectedMemo: VoiceMemo?
    @State private var searchText = ""

    var body: some View {
        Group {
            if isTwoColumnSection {
                // 2-column layout for Models, etc.
                NavigationSplitView {
                    sidebarView
                } detail: {
                    twoColumnDetailView
                }
            } else {
                // 3-column layout for Memos, Workflows, AI Results
                NavigationSplitView {
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
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TALKIE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Navigation sections
            List(selection: $selectedSection) {
                Section("TOOLS") {
                    NavigationLink(value: NavigationSection.aiResults) {
                        Label {
                            Text("AI Results")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                        }
                    }

                    NavigationLink(value: NavigationSection.workflows) {
                        Label {
                            Text("Workflows")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                        }
                    }

                    NavigationLink(value: NavigationSection.models) {
                        Label {
                            Text("Models")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                        }
                    }
                }
                .collapsible(false)

                Section("LIBRARY") {
                    NavigationLink(value: NavigationSection.allMemos) {
                        Label {
                            HStack {
                                Text("All Memos")
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text("\(allMemos.count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.stack")
                                .font(.system(size: 10))
                        }
                    }

                    NavigationLink(value: NavigationSection.recent) {
                        Label {
                            Text("Recent")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                        }
                    }

                    NavigationLink(value: NavigationSection.processed) {
                        Label {
                            HStack {
                                Text("Processed")
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text("\(processedCount)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                        }
                    }

                    NavigationLink(value: NavigationSection.archived) {
                        Label {
                            Text("Archived")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Image(systemName: "archivebox")
                                .font(.system(size: 10))
                        }
                    }
                }
                .collapsible(false)

                Section("SMART FOLDERS") {
                    NavigationLink(value: NavigationSection.smartFolder("Work")) {
                        Label {
                            Text("Work")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                    }

                    NavigationLink(value: NavigationSection.smartFolder("Ideas")) {
                        Label {
                            Text("Ideas")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                        }
                    }

                    NavigationLink(value: NavigationSection.smartFolder("Personal")) {
                        Label {
                            Text("Personal")
                                .font(.system(size: 11, design: .monospaced))
                        } icon: {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .collapsible(false)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // Footer - iCloud sync status
            Divider()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud")
                    .font(.system(size: 9))
                    .foregroundColor(.green)

                Text("Synced with iCloud")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200, idealWidth: 220)
    }

    // MARK: - 2-Column Detail View

    @ViewBuilder
    private var twoColumnDetailView: some View {
        switch selectedSection {
        case .models:
            ModelsContentView()
        default:
            EmptyView()
        }
    }

    // MARK: - Column Views

    /// Whether the current section uses a 2-column layout (sidebar + full content)
    /// vs 3-column layout (sidebar + list + detail)
    private var isTwoColumnSection: Bool {
        switch selectedSection {
        case .models:
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
            AIResultsListColumn(selectedRun: $selectedRun)
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
            AIResultsDetailColumn(selectedRun: $selectedRun)
        default:
            if let memo = selectedMemo {
                MemoDetailView(memo: memo)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("SELECT A MEMO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var selectedRun: WorkflowRun?

    // MARK: - Computed Properties

    private var sectionTitle: String {
        switch selectedSection {
        case .allMemos: return "ALL MEMOS"
        case .recent: return "RECENT"
        case .processed: return "PROCESSED"
        case .archived: return "ARCHIVED"
        case .aiResults: return "AI RESULTS"
        case .workflows: return "WORKFLOWS"
        case .activityLog: return "ACTIVITY LOG"
        case .models: return "MODELS"
        case .smartFolder(let name): return name.uppercased()
        case .none: return "MEMOS"
        }
    }

    private var sectionSubtitle: String? {
        switch selectedSection {
        case .allMemos: return "\(allMemos.count) total"
        case .recent: return "Last 7 days"
        case .processed: return "\(processedCount) memos"
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
        case .recent:
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            memos = memos.filter { ($0.createdAt ?? Date()) > sevenDaysAgo }
        case .processed:
            memos = memos.filter { $0.summary != nil || $0.tasks != nil || $0.reminders != nil }
        case .archived:
            // Future: filter archived memos
            memos = []
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

    private var processedCount: Int {
        allMemos.filter { $0.summary != nil || $0.tasks != nil || $0.reminders != nil }.count
    }

    private var isToolSection: Bool {
        switch selectedSection {
        case .aiResults, .workflows, .activityLog, .models:
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)

                    if let subtitle = sectionSubtitle {
                        Text(subtitle)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Memo list
            if filteredMemos.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("NO MEMOS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)

                    Text("Record on iPhone to sync")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        MemoRowView(memo: memo)
                            .tag(memo)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Workflow Column Views

struct WorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?
    @StateObject private var workflowManager = WorkflowManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKFLOWS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                    Text("\(workflowManager.workflows.count) total")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: createNewWorkflow) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

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
        selectedWorkflowID = workflow.id
        editingWorkflow = workflow
    }
}

struct WorkflowDetailColumn: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var editingWorkflow: WorkflowDefinition?
    @Binding var selectedWorkflowID: UUID?
    @StateObject private var workflowManager = WorkflowManager.shared
    @State private var showingMemoSelector = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
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
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("NEW WORKFLOW")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .sheet(isPresented: $showingMemoSelector) {
            if let workflow = editingWorkflow {
                WorkflowMemoSelectorSheet(
                    workflow: workflow,
                    memos: transcribedMemos,
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
                print("✅ Workflow '\(workflow.name)' completed successfully")
            } catch {
                print("❌ Workflow execution failed: \(error)")
            }
        }
    }
}

// MARK: - AI Results Column Views

struct AIResultsListColumn: View {
    @Binding var selectedRun: WorkflowRun?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkflowRun.runDate, ascending: false)],
        animation: .default
    )
    private var allRuns: FetchedResults<WorkflowRun>

    private var runsByMemo: [(memo: VoiceMemo, runs: [WorkflowRun])] {
        let grouped = Dictionary(grouping: allRuns) { $0.memo }
        return grouped.compactMap { (memo, runs) -> (VoiceMemo, [WorkflowRun])? in
            guard let memo = memo else { return nil }
            return (memo, runs.sorted { ($0.runDate ?? .distantPast) > ($1.runDate ?? .distantPast) })
        }.sorted { ($0.runs.first?.runDate ?? .distantPast) > ($1.runs.first?.runDate ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                    Text("AI RESULTS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(.primary)

                Text("\(allRuns.count) workflow runs")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if runsByMemo.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "wand.and.rays")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))

                    Text("NO RESULTS YET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Run workflows on your memos")
                        .font(.system(size: 9, design: .monospaced))
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
    }
}

struct AIResultsDetailColumn: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedRun: WorkflowRun?

    var body: some View {
        if let run = selectedRun {
            AIRunDetailView(run: run, onDelete: {
                deleteRun(run)
                selectedRun = nil
            })
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("SELECT A RUN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
                Text("Choose a workflow run to view details")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private func deleteRun(_ run: WorkflowRun) {
        viewContext.perform {
            viewContext.delete(run)
            try? viewContext.save()
        }
    }
}

// MARK: - Legacy Tool Content Views (keeping for reference)

struct WorkflowsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var workflowManager = WorkflowManager.shared
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

    var body: some View {
        HStack(spacing: 0) {
            // Left: Workflow List
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WORKFLOWS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                        Text("\(workflowManager.workflows.count) total")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: createNewWorkflow) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.1))
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
            .background(Color(NSColor.controlBackgroundColor))

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
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("NEW WORKFLOW")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingMemoSelector) {
            if let workflow = editingWorkflow {
                WorkflowMemoSelectorSheet(
                    workflow: workflow,
                    memos: transcribedMemos,
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
        selectedWorkflowID = workflow.id
        editingWorkflow = workflow
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
                print("✅ Workflow '\(workflow.name)' completed successfully")
            } catch {
                print("❌ Workflow execution failed: \(error)")
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(workflow.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            if memos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Transcribed Memos")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("Record and transcribe a voice memo first")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(memos) { memo in
                            Button(action: { onSelect(memo) }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(memo.title ?? "Untitled")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        if let date = memo.createdAt {
                                            Text(date, style: .relative)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 400, height: 450)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct WorkflowCard: View {
    @Environment(\.managedObjectContext) private var viewContext
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
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)

                    Text(description)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    if isExecuting {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("RUNNING...")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
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
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
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
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memo.title ?? "Untitled")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .lineLimit(1)

                                    if let date = memo.createdAt {
                                        Text(date, style: .relative)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - AI Results View

struct AIResultsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

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
                            .font(.system(size: 14))
                        Text("AI RESULTS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("All workflow runs across your memos")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if runsByMemo.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO RESULTS YET")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Run workflows on your memos")
                            .font(.system(size: 9, design: .monospaced))
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
            .background(Color(NSColor.textBackgroundColor))

            // Right: Detail view
            if let run = selectedRun {
                AIRunDetailView(run: run, onDelete: {
                    deleteRun(run)
                    selectedRun = nil
                })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("SELECT A RUN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)
                    Text("Choose a workflow run to view details")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
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

// MARK: - Memo Header in AI Results
struct AIMemoHeaderView: View {
    let memo: VoiceMemo
    let runCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(memo.title ?? "Untitled")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(runCount)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }
}

// MARK: - Run Row in AI Results List
struct AIRunRowView: View {
    let run: WorkflowRun
    let isSelected: Bool
    let onSelect: () -> Void

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
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? Color.blue : Color.primary.opacity(0.05))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflowName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let model = modelId {
                            Text(model)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                        }

                        Text(formatDate(runDate))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .padding(.horizontal, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Run Detail View in AI Results
struct AIRunDetailView: View {
    let run: WorkflowRun
    let onDelete: () -> Void

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
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflowName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))

                        HStack(spacing: 8) {
                            if let model = modelId {
                                Text(model)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(3)
                            }

                            Text(formatFullDate(runDate))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Memo reference
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                    Text("From: \(memoTitle)")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Step-by-step content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OUTPUT")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor))
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
        .background(Color(NSColor.textBackgroundColor))
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Step Card in AI Results
struct AIStepCard: View {
    let step: WorkflowExecutor.StepExecution
    let isLast: Bool

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(step.stepNumber)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OUTPUT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("→ {{\(step.outputKey)}}")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(step.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ActivityLogContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 16))
                        Text("ACTIVITY LOG")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("View workflow execution history and results.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Activity log with workflow execution history")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// ModelsContentView is now in its own file: ModelsContentView.swift
