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
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Left sidebar - Navigation
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
                        NavigationLink(value: NavigationSection.workflows) {
                            Label {
                                Text("Workflows")
                                    .font(.system(size: 11, design: .monospaced))
                            } icon: {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 10))
                            }
                        }

                        NavigationLink(value: NavigationSection.activityLog) {
                            Label {
                                Text("Activity Log")
                                    .font(.system(size: 11, design: .monospaced))
                            } icon: {
                                Image(systemName: "list.bullet.clipboard")
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
        } content: {
            // Middle column - Content based on selection
            Group {
                if isToolSection {
                    // Tool sections take full content area
                    toolContentView
                } else {
                    // Library sections show memo list
                    memoListView
                }
            }
        } detail: {
            // Right column - Detail view (only for memo sections)
            if !isToolSection {
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
    }

    // MARK: - Computed Properties

    private var sectionTitle: String {
        switch selectedSection {
        case .allMemos: return "ALL MEMOS"
        case .recent: return "RECENT"
        case .processed: return "PROCESSED"
        case .archived: return "ARCHIVED"
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
        case .workflows, .activityLog, .models:
            return true
        default:
            return false
        }
    }

    // MARK: - Tool Content Views

    @ViewBuilder
    private var toolContentView: some View {
        switch selectedSection {
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
        .frame(minWidth: 300, idealWidth: 350)
    }
}

// MARK: - Tool Content Views

struct WorkflowsContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                        Text("WORKFLOWS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Create and manage automated workflows for your voice memos.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // System Workflows
                VStack(alignment: .leading, spacing: 12) {
                    Text("SYSTEM WORKFLOWS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    WorkflowCard(
                        icon: "list.bullet.clipboard",
                        title: "Summarize",
                        description: "Create a concise executive summary",
                        model: "Gemini 2.5 Flash"
                    )

                    WorkflowCard(
                        icon: "checkmark.square",
                        title: "Extract Tasks",
                        description: "Identify and list action items",
                        model: "Gemini 2.5 Flash"
                    )

                    WorkflowCard(
                        icon: "lightbulb",
                        title: "Key Insights",
                        description: "Extract 3-5 key takeaways",
                        model: "Gemini 2.5 Flash"
                    )

                    WorkflowCard(
                        icon: "bell",
                        title: "Reminders",
                        description: "Extract time-sensitive items and deadlines",
                        model: "Gemini 2.5 Flash"
                    )
                }

                Divider()

                // Custom Workflows (future)
                VStack(alignment: .leading, spacing: 12) {
                    Text("CUSTOM WORKFLOWS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Coming soon: Create custom workflows with your own prompts")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .italic()
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct WorkflowCard: View {
    let icon: String
    let title: String
    let description: String
    let model: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("Model: \(model)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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

struct ModelsContentView: View {
    @ObservedObject var settingsManager = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .font(.system(size: 16))
                        Text("MODELS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Configure AI models and API settings.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // API Settings
                APISettingsView(settingsManager: settingsManager)

                Divider()

                // Model Library
                ModelLibraryView()

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
