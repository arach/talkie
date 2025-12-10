//
//  ActivityLogViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

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
    private let settings = SettingsManager.shared

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
                        .font(Theme.current.fontTitleMedium)
                        .foregroundColor(.primary)

                    Text("\(allRuns.count) events")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.current.surface1)

                Divider()

                if allRuns.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wand.and.rays")
                            .font(SettingsManager.shared.fontDisplay)
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO ACTIVITY YET")
                            .font(Theme.current.fontXSBold)
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
                                .font(Theme.current.fontBodyBold)
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
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        Text("Click a row to see details")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.current.surface1)
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
    private let settings = SettingsManager.shared

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
                        .font(Theme.current.fontBodyMedium)
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
            .background(Theme.current.surface1)

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
            .background(Theme.current.surface2)

            Divider()

            // Step-by-step content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("OUTPUT")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(2)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.current.surface1)
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
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this run")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.current.surface2)
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
    private let settings = SettingsManager.shared

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(step.stepNumber)")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.blue)
                    .cornerRadius(3)

                Image(systemName: step.stepIcon)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Image(systemName: showInput ? "chevron.up" : "chevron.down")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showInput {
                VStack(alignment: .leading, spacing: 3) {
                    Text("INPUT")
                        .font(Theme.current.fontXSBold)
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
                        .font(Theme.current.fontXSBold)
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
                    .background(Theme.current.surface1)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .background(Theme.current.surface2)
        .cornerRadius(6)
    }
}

// MARK: - Inspector Resize Handle

struct InspectorResizeHandle: View {
    @Binding var width: CGFloat
    private let settings = SettingsManager.shared

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

