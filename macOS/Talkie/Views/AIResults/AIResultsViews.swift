//
//  AIResultsViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Activity Log View

struct AIResultsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    private let settings = SettingsManager.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkflowRun.runDate, ascending: false)]
    )
    private var allRuns: FetchedResults<WorkflowRun>

    @State private var selectedRun: WorkflowRun?
    @State private var selectedMemoId: NSManagedObjectID?

    // Group runs by memo (deduplicated by ID to handle CloudKit sync duplicates)
    private var runsByMemo: [(memo: VoiceMemo, runs: [WorkflowRun])] {
        // Deduplicate runs by ID, keeping the most recent one
        var uniqueRuns: [UUID: WorkflowRun] = [:]
        for run in allRuns {
            guard let id = run.id else { continue }
            if let existing = uniqueRuns[id] {
                // Keep the one with the more recent runDate
                if (run.runDate ?? .distantPast) > (existing.runDate ?? .distantPast) {
                    uniqueRuns[id] = run
                }
            } else {
                uniqueRuns[id] = run
            }
        }

        let grouped = Dictionary(grouping: uniqueRuns.values) { $0.memo }
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
                            .font(Theme.current.fontTitle)
                        Text("ACTIVITY LOG")
                            .font(Theme.current.fontBodyBold)
                    }
                    .foregroundColor(Theme.current.foreground)

                    Text("All workflow runs across your memos")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.current.surface1)

                Divider()

                if runsByMemo.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO RESULTS YET")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text("Run workflows on your memos")
                            .font(Theme.current.fontXS)
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
            .background(Theme.current.surfaceInput)

            // Right: Detail view
            if let run = selectedRun {
                AIRunDetailView(run: run, onDelete: {
                    deleteRun(run)
                    selectedRun = nil
                })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("SELECT A RUN")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Text("Choose a workflow run to view details")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surfaceInput)
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
    private let settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(memo.title ?? "Untitled")
                .font(Theme.current.fontSMBold)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            Text("\(runCount)")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.current.surfaceAlternate)
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.current.surface2)
    }
}

// MARK: - Run Row in Activity Log List
struct AIRunRowView: View {
    let run: WorkflowRun
    let isSelected: Bool
    let onSelect: () -> Void
    private let settings = SettingsManager.shared

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
                    .font(Theme.current.fontSM)
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? settings.resolvedAccentColor : Color.primary.opacity(0.05))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflowName)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let model = modelId {
                            Text(model)
                                .font(Theme.current.fontXS)
                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                        }

                        Text(formatDate(runDate))
                            .font(Theme.current.fontXS)
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.current.fontXS)
                    .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 44)
            .background(isSelected ? settings.resolvedAccentColor : (isHovering ? Theme.current.surfaceHover : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    // Static cached formatter
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Run Detail View in Activity Log
struct AIRunDetailView: View {
    let run: WorkflowRun
    let onDelete: () -> Void
    private let settings = SettingsManager.shared

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
                        .font(Theme.current.fontTitle)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Theme.current.surfaceInfo)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflowName)
                            .font(Theme.current.fontTitleMedium)

                        HStack(spacing: 8) {
                            if let model = modelId {
                                Text(model)
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.current.surfaceAlternate)
                                    .cornerRadius(3)
                            }

                            Text(formatFullDate(runDate))
                                .font(Theme.current.fontXS)
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
                            .font(Theme.current.fontBody)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // Memo reference
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(Theme.current.fontXS)
                    Text("From: \(memoTitle)")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(16)
            .background(Theme.current.surface1)

            Divider()

            // Step-by-step content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OUTPUT")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Text(output)
                                    .font(Theme.current.fontBody)
                                    .foregroundColor(Theme.current.foreground)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.current.surface1)
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
        .background(Theme.current.surfaceInput)
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
    private let settings = SettingsManager.shared

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(step.stepNumber)")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(settings.resolvedAccentColor)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text(step.stepType.uppercased())
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)
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
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.surfaceAlternate)
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OUTPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("→ {{\(step.outputKey)}}")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(step.output)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foreground)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Theme.current.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ActivityLogContentView: View {
    private let settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(Theme.current.fontHeadline)
                        Text("ACTIVITY LOG")
                            .font(Theme.current.fontTitleBold)
                    }
                    .foregroundColor(Theme.current.foreground)

                    Text("View workflow execution history and results.")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Divider()

                Text("Coming soon: Activity log with workflow execution history")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.surfaceInput)
    }
}

// ModelsContentView is now in its own file: ModelsContentView.swift

