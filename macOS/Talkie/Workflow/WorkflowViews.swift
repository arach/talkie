//
//  WorkflowViews.swift
//  Talkie macOS
//
//  UI components for workflow management
//

import SwiftUI
import WFKit

// MARK: - Workflow List Item

struct WorkflowListItem: View {
    let workflow: WorkflowDefinition
    let isSelected: Bool
    let isSystem: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var workflowColor: Color {
        workflow.color.color
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon with workflow color
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(workflowColor.opacity(isSelected ? 0.25 : 0.15))

                    Image(systemName: workflow.icon)
                        .font(settings.fontSM)
                        .foregroundColor(isSelected ? workflowColor : workflowColor.opacity(0.8))
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(workflowColor.opacity(isSelected ? 0.4 : 0.2), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(workflow.name)
                            .font(settings.fontBodyMedium)
                            .foregroundColor(isSelected ? settings.tacticalForeground : settings.tacticalForegroundSecondary)
                            .lineLimit(1)

                        // Pinned indicator
                        if workflow.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundColor(workflowColor.opacity(0.7))
                        }

                        // Auto-run indicator
                        if workflow.autoRun {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }

                    HStack(spacing: 4) {
                        Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                            .font(settings.fontXS)
                            .foregroundColor(settings.tacticalForegroundMuted)

                        if !workflow.isEnabled {
                            Text("·")
                                .font(settings.fontXS)
                                .foregroundColor(settings.tacticalForegroundMuted)
                            Text("DISABLED")
                                .font(settings.fontXS)
                                .foregroundColor(.orange.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Color indicator bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(workflowColor)
                    .frame(width: 3, height: 24)
                    .opacity(isSelected ? 1 : (isHovered ? 0.6 : 0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? workflowColor.opacity(0.12)
                        : (isHovered ? settings.tacticalBackgroundTertiary : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? workflowColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// NOTE: Toggle styles are now in DesignSystem.swift
// Use .toggleStyle(.talkieSuccess), .toggleStyle(.talkieInfo), etc.

// MARK: - Workflow Toggle

struct WorkflowToggle: View {
    @Binding var isOn: Bool
    let label: String
    let icon: String
    let activeColor: Color

    @State private var isHovered = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(isOn ? activeColor : .secondary.opacity(0.4))

                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(isOn ? activeColor : .secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? activeColor.opacity(0.15) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isOn ? activeColor.opacity(0.3) : Color.secondary.opacity(isHovered ? 0.2 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Workflow Detail View

struct WorkflowDetailView: View {
    let workflow: WorkflowDefinition
    let isSystem: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRun: () -> Void

    @State private var showingVisualizer = false

    init(
        workflow: WorkflowDefinition,
        isSystem: Bool,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRun: @escaping () -> Void = {}
    ) {
        self.workflow = workflow
        self.isSystem = isSystem
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onRun = onRun
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: workflow.icon)
                        .font(.system(size: 24))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 48, height: 48)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(workflow.name)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))

                        Text(workflow.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            if isSystem {
                                Text("SYSTEM")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(2)
                            }

                            Text(workflow.isEnabled ? "ACTIVE" : "DISABLED")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(workflow.isEnabled ? .green : .secondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        Button(action: onRun) {
                            HStack(spacing: 4) {
                                Image(systemName: "play")
                                    .font(.system(size: 9))
                                Text("RUN")
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

                        Button(action: { showingVisualizer = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 9))
                                Text("VIEW")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(workflow.steps.isEmpty)

                        Button(action: onEdit) {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9))
                                Text("EDIT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                            }
                            .foregroundColor(isSystem ? .secondary.opacity(0.4) : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSystem)

                        if !isSystem {
                            Button(action: onDelete) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                    Text("DELETE")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .tracking(0.5)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()
                    .opacity(0.5)

                // Steps
                VStack(alignment: .leading, spacing: 12) {
                    Text("STEPS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.secondary)

                    if workflow.steps.isEmpty {
                        Text("No steps configured")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                            WorkflowStepCard(step: step, stepNumber: index + 1)

                            if index < workflow.steps.count - 1 {
                                StepConnector()
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $showingVisualizer) {
            WorkflowVisualizerSheet(workflow: workflow)
        }
    }
}

// MARK: - Workflow Visualizer Sheet

struct WorkflowVisualizerSheet: View {
    let workflow: WorkflowDefinition
    @Environment(\.dismiss) private var dismiss
    @State private var canvasState: CanvasState
    @State private var showInspector: Bool = true

    init(workflow: WorkflowDefinition) {
        self.workflow = workflow
        // Initialize canvas state once
        self._canvasState = State(initialValue: TalkieWorkflowConverter.convert(workflow: workflow))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header (full-width, outside inspector scope)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.name)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text("Workflow Visualization")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Inspector toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showInspector.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showInspector ? .fill : .none)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showInspector ? "Hide Inspector" : "Show Inspector")

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // WFKit Editor with inline inspector (works in modal context)
            WFWorkflowEditor(
                state: canvasState,
                schema: TalkieWorkflowSchema.shared,
                isReadOnly: true,
                inspectorStyle: .inline,
                showInspector: $showInspector
            )
        }
        .frame(minWidth: 1200, idealWidth: 1400, minHeight: 800, idealHeight: 900)
    }
}

// MARK: - Step Connector

struct StepConnector: View {
    var body: some View {
        HStack {
            Spacer()
                .frame(width: 12)
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 3, height: 3)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Workflow Step Card

struct WorkflowStepCard: View {
    let step: WorkflowStep
    let stepNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Step number badge
                Text("\(stepNumber)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)

                Image(systemName: step.type.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.type.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)

                    Text(step.type.description)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Category badge
                Text(step.type.category.rawValue.uppercased())
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Step-specific details
            stepDetails
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var stepDetails: some View {
        switch step.config {
        case .llm(let config):
            LLMStepDetails(config: config)
        case .shell(let config):
            ShellStepDetails(config: config)
        case .webhook(let config):
            WebhookStepDetails(config: config)
        case .email(let config):
            EmailStepDetails(config: config)
        case .notification(let config):
            NotificationStepDetails(config: config)
        case .iOSPush(let config):
            iOSPushStepDetails(config: config)
        case .appleNotes(let config):
            AppleNotesStepDetails(config: config)
        case .appleReminders(let config):
            AppleRemindersStepDetails(config: config)
        case .appleCalendar(let config):
            AppleCalendarStepDetails(config: config)
        case .clipboard(let config):
            ClipboardStepDetails(config: config)
        case .saveFile(let config):
            SaveFileStepDetails(config: config)
        case .conditional(let config):
            ConditionalStepDetails(config: config)
        case .transform(let config):
            TransformStepDetails(config: config)
        case .transcribe(let config):
            TranscribeStepDetails(config: config)
        case .trigger(let config):
            TriggerStepDetails(config: config)
        case .intentExtract(let config):
            IntentExtractStepDetails(config: config)
        case .executeWorkflows(let config):
            ExecuteWorkflowsStepDetails(config: config)
        case .speak(let config):
            SpeakStepDetails(config: config)
        }
    }
}

// MARK: - Step Details Views

struct LLMStepDetails: View {
    let config: LLMStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DetailBadge(label: (config.provider?.displayName ?? "AUTO").uppercased(), color: .blue)
                DetailBadge(label: config.selectedModel?.name ?? config.modelId ?? "auto", color: .purple)
            }

            if !config.prompt.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROMPT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text(config.prompt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                }
            }
        }
    }
}

struct ShellStepDetails: View {
    let config: ShellStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DetailBadge(label: "CLI", color: .green)
                DetailBadge(label: "\(config.timeout)s", color: .orange)
                if config.stdin != nil {
                    DetailBadge(label: "STDIN", color: .blue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("COMMAND")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text(config.executable)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)

                    Text(config.arguments.joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }

            // Security status
            let validation = config.validate()
            if !validation.valid {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 9))
                    Text(validation.errors.first ?? "Validation error")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

struct WebhookStepDetails: View {
    let config: WebhookStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DetailBadge(label: config.method.rawValue, color: .orange)
                if config.includeTranscript {
                    DetailBadge(label: "TRANSCRIPT", color: .green)
                }
            }

            if !config.url.isEmpty {
                Text(config.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
        }
    }
}

struct EmailStepDetails: View {
    let config: EmailStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !config.to.isEmpty {
                HStack(spacing: 4) {
                    Text("To:")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(config.to)
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            if !config.subject.isEmpty {
                HStack(spacing: 4) {
                    Text("Subject:")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(config.subject)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct NotificationStepDetails: View {
    let config: NotificationStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            if !config.body.isEmpty {
                Text(config.body)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if config.sound {
                    DetailBadge(label: "SOUND", color: .blue)
                }
            }
        }
    }
}

struct iOSPushStepDetails: View {
    let config: iOSPushStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "iphone")
                    .font(.system(size: 9))
                    .foregroundColor(.blue)
                if !config.title.isEmpty {
                    Text(config.title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
            if !config.body.isEmpty {
                Text(config.body)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if config.sound {
                    DetailBadge(label: "SOUND", color: .blue)
                }
                if config.includeOutput {
                    DetailBadge(label: "OUTPUT", color: .green)
                }
            }
        }
    }
}

struct AppleNotesStepDetails: View {
    let config: AppleNotesStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let folder = config.folderName {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(folder)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            if config.attachTranscript {
                DetailBadge(label: "ATTACH TRANSCRIPT", color: .green)
            }
        }
    }
}

struct AppleRemindersStepDetails: View {
    let config: AppleRemindersStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let list = config.listName {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 9))
                    Text(list)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            HStack(spacing: 8) {
                if config.priority != .none {
                    DetailBadge(label: config.priority.displayName.uppercased(), color: priorityColor(config.priority))
                }
                if config.dueDate != nil {
                    DetailBadge(label: "DUE DATE", color: .orange)
                }
            }
        }
    }

    private func priorityColor(_ priority: AppleRemindersStepConfig.ReminderPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .gray
        }
    }
}

struct AppleCalendarStepDetails: View {
    let config: AppleCalendarStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            HStack(spacing: 8) {
                DetailBadge(label: formatDuration(config.duration), color: .blue)
                if config.isAllDay {
                    DetailBadge(label: "ALL DAY", color: .purple)
                }
                if config.location != nil {
                    DetailBadge(label: "LOCATION", color: .green)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            return "\(hours)h"
        } else {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
    }
}

struct ClipboardStepDetails: View {
    let config: ClipboardStepConfig

    var body: some View {
        Text(config.content)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
}

struct SaveFileStepDetails: View {
    let config: SaveFileStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.system(size: 9))
                Text(config.filename)
                    .font(.system(size: 10, design: .monospaced))
            }
            if config.appendIfExists {
                DetailBadge(label: "APPEND", color: .orange)
            }
        }
    }
}

struct ConditionalStepDetails: View {
    let config: ConditionalStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !config.condition.isEmpty {
                Text("IF: \(config.condition)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.purple)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                DetailBadge(label: "THEN: \(config.thenSteps.count)", color: .green)
                DetailBadge(label: "ELSE: \(config.elseSteps.count)", color: .orange)
            }
        }
    }
}

struct TransformStepDetails: View {
    let config: TransformStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailBadge(label: config.operation.rawValue.uppercased(), color: .purple)
            Text(config.operation.description)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

struct TranscribeStepDetails: View {
    let config: TranscribeStepConfig

    private var modelName: String {
        TranscribeStepConfig.availableModels.first { $0.id == config.model }?.name ?? config.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DetailBadge(label: "WHISPER", color: .purple)
                DetailBadge(label: modelName.uppercased(), color: .secondary)
            }
            if config.overwriteExisting {
                Text("Will overwrite existing transcript")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.orange)
            }
        }
    }
}

struct SpeakStepDetails: View {
    let config: SpeakStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DetailBadge(label: "SPEAK", color: .cyan)
                if config.playImmediately {
                    DetailBadge(label: "PLAY NOW", color: .green)
                }
                if config.saveToFile {
                    DetailBadge(label: "SAVE", color: .secondary)
                }
            }
            Text(config.text.prefix(50) + (config.text.count > 50 ? "..." : ""))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

struct TriggerStepDetails: View {
    let config: TriggerStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DetailBadge(label: "TRIGGER", color: .orange)
                DetailBadge(label: config.searchLocation.rawValue.uppercased(), color: .secondary)
            }
            Text("Phrases: \(config.phrases.joined(separator: ", "))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            if config.stopIfNoMatch {
                Text("⛔ Stops workflow if no match")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.orange)
            }
        }
    }
}

struct IntentExtractStepDetails: View {
    let config: IntentExtractStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DetailBadge(label: "EXTRACT INTENTS", color: .cyan)
                DetailBadge(label: config.extractionMethod.rawValue.uppercased(), color: .secondary)
            }
            Text("\(config.recognizedIntents.filter { $0.isEnabled }.count) intent(s) configured")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

struct ExecuteWorkflowsStepDetails: View {
    let config: ExecuteWorkflowsStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DetailBadge(label: "EXECUTE", color: .green)
                if config.parallel {
                    DetailBadge(label: "PARALLEL", color: .blue)
                } else {
                    DetailBadge(label: "SEQUENTIAL", color: .secondary)
                }
            }
            if config.stopOnError {
                Text("⛔ Stops on first error")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Detail Badge

struct DetailBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .tracking(0.3)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(2)
    }
}

// MARK: - Workflow Inline Editor (Primary Edit Experience)

struct WorkflowInlineEditor: View {
    @Binding var workflow: WorkflowDefinition?
    let onSave: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onRun: () -> Void

    @ObservedObject private var workflowManager = WorkflowManager.shared
    @State private var showingStepTypePicker = false
    @State private var isEditing = false
    @State private var showingVisualizer = false

    // Get the current workflow from manager (source of truth)
    private var currentWorkflow: WorkflowDefinition? {
        guard let id = workflow?.id else { return nil }
        return workflowManager.workflows.first { $0.id == id }
    }

    private var editedWorkflow: Binding<WorkflowDefinition> {
        Binding(
            get: {
                // Use manager as source of truth
                currentWorkflow ?? workflow ?? WorkflowDefinition(name: "", description: "")
            },
            set: { newValue in
                // Update both manager and binding
                workflowManager.updateWorkflow(newValue)
                workflow = workflowManager.workflows.first { $0.id == newValue.id }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: Spacing.xs) {
                Image(systemName: editedWorkflow.wrappedValue.icon)
                    .font(.headlineSmall)
                    .foregroundColor(editedWorkflow.wrappedValue.color.color)
                    .frame(width: 28, height: 28)
                    .background(editedWorkflow.wrappedValue.color.color.opacity(Opacity.medium))
                    .cornerRadius(CornerRadius.xs)

                if isEditing {
                    TextField("Workflow name", text: editedWorkflow.name)
                        .font(.bodySmall)
                        .textFieldStyle(.plain)
                } else {
                    Text(editedWorkflow.wrappedValue.name)
                        .font(.bodySmall)
                }

                Spacer()

                if isEditing {
                    // Cancel button
                    Button(action: { isEditing = false }) {
                        Text("CANCEL")
                            .font(.techLabelSmall)
                            .tracking(Tracking.tight)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(Opacity.light))
                            .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)

                    // Save button
                    Button(action: {
                        onSave()
                        isEditing = false
                    }) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "checkmark")
                                .font(.techLabelSmall)
                            Text("SAVE")
                                .font(.techLabelSmall)
                                .tracking(Tracking.tight)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(SemanticColor.success)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Edit button
                    Button(action: { isEditing = true }) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "pencil")
                                .font(.techLabelSmall)
                            Text("EDIT")
                                .font(.techLabelSmall)
                                .tracking(Tracking.tight)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)

                    // Duplicate button
                    Button(action: onDuplicate) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "doc.on.doc")
                                .font(.techLabelSmall)
                            Text("DUPLICATE")
                                .font(.techLabelSmall)
                                .tracking(Tracking.tight)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)

                    // View button (WFKit visualization)
                    Button(action: { showingVisualizer = true }) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.techLabelSmall)
                            Text("VIEW")
                                .font(.techLabelSmall)
                                .tracking(Tracking.tight)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                    .disabled(editedWorkflow.wrappedValue.steps.isEmpty)

                    // Run button
                    Button(action: onRun) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "play.fill")
                                .font(.techLabelSmall)
                            Text("RUN")
                                .font(.techLabelSmall)
                                .tracking(Tracking.tight)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                    .disabled(editedWorkflow.wrappedValue.steps.isEmpty)

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                            .padding(Spacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(NSColor.controlBackgroundColor))

            // Editor content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Description
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("DESCRIPTION")
                            .font(.techLabelSmall)
                            .tracking(Tracking.normal)
                            .foregroundColor(.secondary.opacity(0.6))

                        if isEditing {
                            TextField("What does this workflow do?", text: editedWorkflow.description)
                                .font(.monoSmall)
                                .textFieldStyle(.plain)
                                .padding(Spacing.xs)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(CornerRadius.xs)
                        } else {
                            Text(editedWorkflow.wrappedValue.description.isEmpty ? "No description" : editedWorkflow.wrappedValue.description)
                                .font(.monoSmall)
                                .foregroundColor(editedWorkflow.wrappedValue.description.isEmpty ? .secondary.opacity(Opacity.half) : .primary)
                                .padding(Spacing.xs)
                        }
                    }

                    // Icon & Color selector (only in edit mode)
                    if isEditing {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("ICON")
                                    .font(.techLabelSmall)
                                    .tracking(Tracking.normal)
                                    .foregroundColor(.secondary.opacity(0.6))

                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: editedWorkflow.wrappedValue.icon)
                                        .font(.bodySmall)
                                        .foregroundColor(editedWorkflow.wrappedValue.color.color)
                                        .frame(width: 28, height: 28)
                                        .background(editedWorkflow.wrappedValue.color.color.opacity(Opacity.medium))
                                        .cornerRadius(CornerRadius.xs)

                                    TextField("SF Symbol", text: editedWorkflow.icon)
                                        .font(.monoXSmall)
                                        .textFieldStyle(.plain)
                                        .padding(.horizontal, Spacing.xs)
                                        .padding(.vertical, Spacing.xs)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(CornerRadius.xs)
                                        .frame(width: 120)
                                }
                            }

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("COLOR")
                                    .font(.techLabelSmall)
                                    .tracking(Tracking.normal)
                                    .foregroundColor(.secondary.opacity(0.6))

                                Picker("", selection: editedWorkflow.color) {
                                    ForEach(WorkflowColor.allCases, id: \.self) { color in
                                        HStack {
                                            Circle()
                                                .fill(color.color)
                                                .frame(width: 10, height: 10)
                                            Text(color.displayName)
                                        }
                                        .tag(color)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 100)
                            }

                            Spacer()
                        }

                        // Workflow toggles section
                        Divider()
                            .opacity(Opacity.strong)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("OPTIONS")
                                .font(.techLabelSmall)
                                .tracking(Tracking.normal)
                                .foregroundColor(.secondary.opacity(0.6))

                            HStack(spacing: 20) {
                                // Enabled toggle
                                WorkflowToggle(
                                    isOn: editedWorkflow.isEnabled,
                                    label: "ENABLED",
                                    icon: "checkmark.circle.fill",
                                    activeColor: SemanticColor.success
                                )

                                // Pinned toggle
                                WorkflowToggle(
                                    isOn: editedWorkflow.isPinned,
                                    label: "PINNED",
                                    icon: "pin.fill",
                                    activeColor: editedWorkflow.wrappedValue.color.color
                                )

                                // Auto-run toggle
                                WorkflowToggle(
                                    isOn: editedWorkflow.autoRun,
                                    label: "AUTO-RUN",
                                    icon: "bolt.fill",
                                    activeColor: SemanticColor.warning
                                )

                                Spacer()
                            }
                        }
                    }

                    Divider()
                        .opacity(Opacity.strong)

                    // Steps section
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("STEPS")
                                .font(.techLabelSmall)
                                .tracking(Tracking.normal)
                                .foregroundColor(.secondary.opacity(0.6))

                            Spacer()

                            if isEditing {
                                Button(action: { showingStepTypePicker = true }) {
                                    HStack(spacing: Spacing.xxs) {
                                        Image(systemName: "plus")
                                            .font(.techLabelSmall)
                                        Text("ADD STEP")
                                            .font(.techLabelSmall)
                                            .tracking(Tracking.tight)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(Color.primary.opacity(Opacity.light))
                                    .cornerRadius(CornerRadius.xs)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        let displaySteps = currentWorkflow?.steps ?? []
                        if displaySteps.isEmpty {
                            // Empty state
                            VStack(spacing: Spacing.sm) {
                                Image(systemName: "rectangle.stack.badge.plus")
                                    .font(.displaySmall)
                                    .foregroundColor(.secondary.opacity(0.2))

                                Text("NO STEPS")
                                    .font(.techLabelSmall)
                                    .tracking(Tracking.normal)
                                    .foregroundColor(.secondary.opacity(Opacity.half))

                                Text(isEditing ? "Add steps to define workflow actions" : "This workflow has no steps yet")
                                    .font(.monoXSmall)
                                    .foregroundColor(.secondary.opacity(0.4))

                                if isEditing {
                                    Button(action: { showingStepTypePicker = true }) {
                                        HStack(spacing: Spacing.xxs) {
                                            Image(systemName: "plus")
                                                .font(.techLabelSmall)
                                            Text("ADD FIRST STEP")
                                                .font(.techLabelSmall)
                                                .tracking(Tracking.tight)
                                        }
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, Spacing.xs)
                                        .background(Color.primary.opacity(Opacity.light))
                                        .cornerRadius(CornerRadius.xs)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xxl)
                            .background(Color(NSColor.controlBackgroundColor).opacity(Opacity.half))
                            .cornerRadius(CornerRadius.sm)
                        } else {
                            ForEach(Array(displaySteps.enumerated()), id: \.element.id) { index, step in
                                WorkflowStepEditor(
                                    step: stepBinding(at: index),
                                    stepNumber: index + 1,
                                    isEditing: isEditing,
                                    onDelete: { deleteStep(at: index) },
                                    onMoveUp: index > 0 ? { moveStep(from: index, to: index - 1) } : nil,
                                    onMoveDown: index < displaySteps.count - 1 ? { moveStep(from: index, to: index + 1) } : nil
                                )

                                if index < displaySteps.count - 1 {
                                    StepConnector()
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $showingStepTypePicker) {
            StepTypePicker { stepType in
                addStep(of: stepType)
                showingStepTypePicker = false
            } onCancel: {
                showingStepTypePicker = false
            }
        }
        .sheet(isPresented: $showingVisualizer) {
            WorkflowVisualizerSheet(workflow: editedWorkflow.wrappedValue)
        }
    }

    private func stepBinding(at index: Int) -> Binding<WorkflowStep> {
        Binding(
            get: {
                guard let wf = currentWorkflow, index < wf.steps.count else {
                    return WorkflowStep(type: .llm, config: .llm(LLMStepConfig(provider: .gemini, prompt: "")), outputKey: "")
                }
                return wf.steps[index]
            },
            set: { newValue in
                guard var wf = currentWorkflow, index < wf.steps.count else { return }
                wf.steps[index] = newValue
                wf.modifiedAt = Date()
                workflowManager.updateWorkflow(wf)
            }
        )
    }

    private func addStep(of type: WorkflowStep.StepType) {
        // Use currentWorkflow from manager as source of truth
        guard var wf = currentWorkflow else { return }
        let newStep = WorkflowStep(
            type: type,
            config: StepConfig.defaultConfig(for: type),
            outputKey: "output_\(wf.steps.count + 1)"
        )
        wf.steps.append(newStep)
        wf.modifiedAt = Date()
        workflowManager.updateWorkflow(wf)
        workflow = workflowManager.workflows.first { $0.id == wf.id }
    }

    private func deleteStep(at index: Int) {
        // Use currentWorkflow from manager as source of truth
        guard var wf = currentWorkflow else { return }
        guard index < wf.steps.count else { return }
        wf.steps.remove(at: index)
        wf.modifiedAt = Date()
        workflowManager.updateWorkflow(wf)
        workflow = workflowManager.workflows.first { $0.id == wf.id }
    }

    private func moveStep(from source: Int, to destination: Int) {
        // Use currentWorkflow from manager as source of truth
        guard var wf = currentWorkflow else { return }
        guard source < wf.steps.count else { return }
        let step = wf.steps.remove(at: source)
        wf.steps.insert(step, at: destination)
        wf.modifiedAt = Date()
        workflowManager.updateWorkflow(wf)
        workflow = workflowManager.workflows.first { $0.id == wf.id }
    }
}

// MARK: - Workflow Editor Sheet (Legacy - kept for reference)

struct WorkflowEditorSheet: View {
    @State private var editedWorkflow: WorkflowDefinition
    let isNew: Bool
    let onSave: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    @State private var showingStepTypePicker = false

    init(workflow: WorkflowDefinition, isNew: Bool, onSave: @escaping (WorkflowDefinition) -> Void, onCancel: @escaping () -> Void) {
        _editedWorkflow = State(initialValue: workflow)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Workflow" : "Edit Workflow")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") {
                    onSave(editedWorkflow)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedWorkflow.name.isEmpty)
            }
            .padding(16)

            Divider()

            // Editor Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Basic Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BASIC INFORMATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("NAME")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            TextField("Workflow Name", text: $editedWorkflow.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESCRIPTION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            TextField("What does this workflow do?", text: $editedWorkflow.description)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ICON")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    Image(systemName: editedWorkflow.icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(editedWorkflow.color.color)
                                        .frame(width: 32, height: 32)
                                        .background(editedWorkflow.color.color.opacity(0.1))
                                        .cornerRadius(6)

                                    TextField("SF Symbol", text: $editedWorkflow.icon)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("COLOR")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Picker("", selection: $editedWorkflow.color) {
                                    ForEach(WorkflowColor.allCases, id: \.self) { color in
                                        HStack {
                                            Circle()
                                                .fill(color.color)
                                                .frame(width: 10, height: 10)
                                            Text(color.displayName)
                                        }
                                        .tag(color)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }

                    Divider()

                    // Steps
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("WORKFLOW STEPS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: { showingStepTypePicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9))
                                    Text("Add Step")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }

                        if editedWorkflow.steps.isEmpty {
                            EmptyStepsView(onAddStep: { showingStepTypePicker = true })
                        } else {
                            ForEach(Array(editedWorkflow.steps.enumerated()), id: \.element.id) { index, step in
                                WorkflowStepEditor(
                                    step: binding(for: step),
                                    stepNumber: index + 1,
                                    onDelete: { deleteStep(at: index) },
                                    onMoveUp: index > 0 ? { moveStep(from: index, to: index - 1) } : nil,
                                    onMoveDown: index < editedWorkflow.steps.count - 1 ? { moveStep(from: index, to: index + 1) } : nil
                                )

                                if index < editedWorkflow.steps.count - 1 {
                                    StepConnector()
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 750, height: 650)
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $showingStepTypePicker) {
            StepTypePicker { stepType in
                addStep(of: stepType)
                showingStepTypePicker = false
            } onCancel: {
                showingStepTypePicker = false
            }
        }
    }

    private func binding(for step: WorkflowStep) -> Binding<WorkflowStep> {
        guard let index = editedWorkflow.steps.firstIndex(where: { $0.id == step.id }) else {
            fatalError("Step not found")
        }
        return $editedWorkflow.steps[index]
    }

    private func addStep(of type: WorkflowStep.StepType) {
        let newStep = WorkflowStep(
            type: type,
            config: StepConfig.defaultConfig(for: type),
            outputKey: "output_\(editedWorkflow.steps.count + 1)"
        )
        editedWorkflow.steps.append(newStep)
    }

    private func deleteStep(at index: Int) {
        editedWorkflow.steps.remove(at: index)
    }

    private func moveStep(from source: Int, to destination: Int) {
        let step = editedWorkflow.steps.remove(at: source)
        editedWorkflow.steps.insert(step, at: destination)
    }
}

// MARK: - Empty Steps View

struct EmptyStepsView: View {
    let onAddStep: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No steps yet")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Text("Add steps to define what this workflow does")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Button(action: onAddStep) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("Add First Step")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Step Type Picker

struct StepTypePicker: View {
    let onSelect: (WorkflowStep.StepType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Step")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
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

            // Categories
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(WorkflowStep.StepCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 10))
                                Text(category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(.secondary)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(category.steps, id: \.self) { stepType in
                                    StepTypeCard(stepType: stepType) {
                                        onSelect(stepType)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: 500)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct StepTypeCard: View {
    let stepType: WorkflowStep.StepType
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: stepType.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stepType.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)

                    Text(stepType.description)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workflow Step Editor

struct WorkflowStepEditor: View {
    @Binding var step: WorkflowStep
    let stepNumber: Int
    var isEditing: Bool = true
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isExpanded = true

    private var stepColor: Color {
        step.type.themeColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            stepHeader

            if isExpanded {
                Divider()
                    .opacity(Opacity.strong)

                // Content: Read-only summary OR full editor
                if isEditing {
                    stepEditView
                        .padding(Spacing.md)
                } else {
                    stepReadView
                        .padding(Spacing.md)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(stepColor.opacity(isEditing ? 0.3 : 0.15), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack(spacing: Spacing.sm) {
            // Step number badge with type color
            Text("\(stepNumber)")
                .font(.monoSmall)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(stepColor)
                .cornerRadius(CornerRadius.xs)

            // Icon and type name
            Image(systemName: step.type.icon)
                .font(.labelMedium)
                .foregroundColor(stepColor)

            Text(step.type.displayName)
                .font(.labelMedium)
                .foregroundColor(.primary)

            Spacer()

            // Reorder buttons (only in edit mode)
            if isEditing {
                HStack(spacing: Spacing.xxs) {
                    if let moveUp = onMoveUp {
                        Button(action: moveUp) {
                            Image(systemName: "chevron.up")
                                .font(.labelSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

                    if let moveDown = onMoveDown {
                        Button(action: moveDown) {
                            Image(systemName: "chevron.down")
                                .font(.labelSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }

            // Expand/collapse
            Button(action: { withAnimation(TalkieAnimation.fast) { isExpanded.toggle() } }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.labelSmall)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            // Delete button (only in edit mode)
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.labelSmall)
                        .foregroundColor(SemanticColor.error.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Read-Only View (Compact Summary)

    @ViewBuilder
    private var stepReadView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch step.config {
            case .llm(let config):
                LLMStepReadView(config: config)
            case .shell(let config):
                ShellStepReadView(config: config)
            case .webhook(let config):
                WebhookStepReadView(config: config)
            case .email(let config):
                EmailStepReadView(config: config)
            case .notification(let config):
                NotificationStepReadView(config: config)
            case .iOSPush(let config):
                iOSPushStepReadView(config: config)
            case .appleNotes(let config):
                AppleNotesStepReadView(config: config)
            case .appleReminders(let config):
                AppleRemindersStepReadView(config: config)
            case .appleCalendar(let config):
                AppleCalendarStepReadView(config: config)
            case .clipboard(let config):
                ClipboardStepReadView(config: config)
            case .saveFile(let config):
                SaveFileStepReadView(config: config)
            case .conditional(let config):
                ConditionalStepReadView(config: config)
            case .transform(let config):
                TransformStepReadView(config: config)
            case .transcribe(let config):
                TranscribeStepReadView(config: config)
            case .trigger(let config):
                TriggerStepReadView(config: config)
            case .intentExtract(let config):
                IntentExtractStepReadView(config: config)
            case .executeWorkflows(let config):
                ExecuteWorkflowsStepReadView(config: config)
            case .speak(let config):
                SpeakStepReadView(config: config)
            }

            // Output key (always shown in read mode)
            if !step.outputKey.isEmpty {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("→ \(step.outputKey)")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Edit View (Full Form)

    @ViewBuilder
    private var stepEditView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch step.config {
            case .llm:
                LLMStepConfigEditor(step: $step)
            case .shell:
                ShellStepConfigEditor(step: $step)
            case .webhook:
                WebhookStepConfigEditor(step: $step)
            case .email:
                EmailStepConfigEditor(step: $step)
            case .notification:
                NotificationStepConfigEditor(step: $step)
            case .iOSPush:
                iOSPushStepConfigEditor(step: $step)
            case .appleNotes:
                AppleNotesStepConfigEditor(step: $step)
            case .appleReminders:
                AppleRemindersStepConfigEditor(step: $step)
            case .appleCalendar:
                AppleCalendarStepConfigEditor(step: $step)
            case .clipboard:
                ClipboardStepConfigEditor(step: $step)
            case .saveFile:
                SaveFileStepConfigEditor(step: $step)
            case .conditional:
                ConditionalStepConfigEditor(step: $step)
            case .transform:
                TransformStepConfigEditor(step: $step)
            case .transcribe:
                TranscribeStepConfigEditor(step: $step)
            case .trigger:
                TriggerStepConfigEditor(step: $step)
            case .intentExtract:
                IntentExtractStepConfigEditor(step: $step)
            case .executeWorkflows:
                ExecuteWorkflowsStepConfigEditor(step: $step)
            case .speak:
                SpeakStepConfigEditor(step: $step)
            }

            // Output key editor
            Divider()
                .opacity(Opacity.strong)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("OUTPUT KEY")
                    .font(.techLabelSmall)
                    .tracking(Tracking.tight)
                    .foregroundColor(.secondary)

                TextField("Key name for storing output", text: $step.outputKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.monoXSmall)

                Text("Use {{\(step.outputKey)}} in subsequent steps")
                    .font(.monoXSmall)
                    .foregroundColor(.secondary.opacity(Opacity.prominent))
            }
        }
    }
}

// MARK: - Read-Only Step Views

struct LLMStepReadView: View {
    let config: LLMStepConfig

    private var modelDisplayName: String {
        // Try to get a friendly name for the model
        if let provider = config.provider,
           let modelId = config.modelId,
           let model = provider.models.first(where: { $0.id == modelId }) {
            return model.name
        }
        // Fallback: extract last component of model ID or show "Auto"
        if let modelId = config.modelId {
            return modelId.components(separatedBy: "/").last ?? modelId
        }
        return "Auto"
    }

    private var modelContextWindow: String? {
        if let provider = config.provider,
           let modelId = config.modelId,
           let model = provider.models.first(where: { $0.id == modelId }) {
            return model.formattedContext
        }
        return nil
    }

    private var providerColor: Color {
        guard let provider = config.provider else {
            return .gray  // Gray for auto-route
        }
        switch provider {
        case .mlx:
            return SemanticColor.processing  // Purple for local AI
        case .anthropic:
            return .orange
        case .openai:
            return SemanticColor.success
        case .groq:
            return SemanticColor.info
        case .gemini:
            return SemanticColor.pin  // Blue for Gemini
        }
    }

    private var temperatureIcon: String {
        if config.temperature < 0.3 {
            return "snowflake"  // Cold/precise
        } else if config.temperature < 0.7 {
            return "thermometer.medium"  // Balanced
        } else {
            return "flame.fill"  // Hot/creative
        }
    }

    private var temperatureColor: Color {
        if config.temperature < 0.3 {
            return SemanticColor.info  // Cool cyan
        } else if config.temperature < 0.7 {
            return SemanticColor.warning  // Warm orange
        } else {
            return SemanticColor.error  // Hot red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Provider & Model info
            HStack(spacing: Spacing.sm) {
                // Provider badge with local/external indicator
                HStack(spacing: 4) {
                    Image(systemName: config.provider == .mlx ? "cpu" : (config.provider == nil ? "arrow.triangle.branch" : "globe"))
                        .font(.system(size: 9))
                    Text(config.provider?.displayName ?? "Auto")
                        .font(.techLabelSmall)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 3)
                .background(providerColor.opacity(0.15))
                .foregroundColor(providerColor)
                .cornerRadius(CornerRadius.xs)

                // Model name with context window
                VStack(alignment: .leading, spacing: 0) {
                    Text(modelDisplayName)
                        .font(.monoSmall)
                        .foregroundColor(.primary)

                    if let context = modelContextWindow {
                        Text(context)
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Row 2: Generation parameters
            HStack(spacing: Spacing.md) {
                // Temperature with visual indicator
                HStack(spacing: 4) {
                    Image(systemName: temperatureIcon)
                        .font(.system(size: 10))
                        .foregroundColor(temperatureColor)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%.1f", config.temperature))
                            .font(.monoSmall)
                            .foregroundColor(.primary)
                        Text("temp")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                    }
                }

                // Max tokens
                HStack(spacing: 4) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(config.maxTokens)")
                            .font(.monoSmall)
                            .foregroundColor(.primary)
                        Text("tokens")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Row 3: Prompt
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("PROMPT")
                    .font(.techLabelSmall)
                    .tracking(Tracking.tight)
                    .foregroundColor(.secondary.opacity(0.6))

                Text(config.prompt)
                    .font(.monoSmall)
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(CornerRadius.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
}

struct ShellStepReadView: View {
    let config: ShellStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Command with security indicator
            HStack(spacing: Spacing.xs) {
                Image(systemName: config.isExecutableAllowed() ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(config.isExecutableAllowed() ? SemanticColor.success : SemanticColor.warning)

                // Full command line
                Text(config.executable)
                    .font(.monoSmall)
                    .foregroundColor(.primary)

                if !config.arguments.isEmpty {
                    Text(config.arguments.joined(separator: " "))
                        .font(.monoSmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Row 2: Metadata badges
            HStack(spacing: Spacing.sm) {
                // Timeout
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("\(config.timeout)s")
                        .font(.monoXSmall)
                }
                .foregroundColor(.secondary)

                // Stderr capture indicator
                if config.captureStderr {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("stderr")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                // Working directory if set
                if let dir = config.workingDirectory, !dir.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(dir.components(separatedBy: "/").last ?? dir)
                            .font(.monoXSmall)
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }

                // Environment vars count
                if !config.environment.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 9))
                        Text("\(config.environment.count) env")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 3: stdin if provided
            if let stdin = config.stdin, !stdin.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("STDIN")
                        .font(.techLabelSmall)
                        .tracking(Tracking.tight)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(stdin)
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.xs)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(CornerRadius.xs)
                }
            }

            // Row 4: Prompt template if used
            if let template = config.promptTemplate, !template.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("PROMPT TEMPLATE")
                        .font(.techLabelSmall)
                        .tracking(Tracking.tight)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(template)
                        .font(.monoXSmall)
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.xs)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(CornerRadius.xs)
                }
            }
        }
    }
}

struct WebhookStepReadView: View {
    let config: WebhookStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Method badge + URL
            HStack(spacing: Spacing.xs) {
                Text(config.method.rawValue)
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(methodColor.opacity(0.2))
                    .foregroundColor(methodColor)
                    .cornerRadius(CornerRadius.xs)

                Text(config.url)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Metadata indicators
            HStack(spacing: Spacing.sm) {
                // Include transcript indicator
                if config.includeTranscript {
                    HStack(spacing: 2) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9))
                        Text("Transcript")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                // Include metadata indicator
                if config.includeMetadata {
                    HStack(spacing: 2) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text("Metadata")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                // Headers count
                if !config.headers.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 9))
                        Text("\(config.headers.count) headers")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 3: Body template if set
            if let body = config.bodyTemplate, !body.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("BODY TEMPLATE")
                        .font(.techLabelSmall)
                        .tracking(Tracking.tight)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(body)
                        .font(.monoXSmall)
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.xs)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(CornerRadius.xs)
                }
            }
        }
    }

    private var methodColor: Color {
        switch config.method {
        case .get: return .blue
        case .post: return .green
        case .put, .patch: return .orange
        case .delete: return .red
        }
    }
}

struct NotificationStepReadView: View {
    let config: NotificationStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: macOS icon + Title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.warning)

                Text(config.title)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Body preview
            Text(config.body)
                .font(.monoXSmall)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Row 3: Options badges
            HStack(spacing: Spacing.sm) {
                // Sound indicator
                HStack(spacing: 2) {
                    Image(systemName: config.sound ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 9))
                    Text(config.sound ? "Sound" : "Silent")
                        .font(.monoXSmall)
                }
                .foregroundColor(config.sound ? SemanticColor.info : .secondary)

                // Action label if set
                if let action = config.actionLabel, !action.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 9))
                        Text(action)
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                Spacer()
            }
        }
    }
}

struct iOSPushStepReadView: View {
    let config: iOSPushStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: iOS icon + Title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "iphone.badge.play")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.info)

                Text(config.title)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Body preview
            Text(config.body)
                .font(.monoXSmall)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Row 3: Options badges
            HStack(spacing: Spacing.sm) {
                // Sound indicator
                HStack(spacing: 2) {
                    Image(systemName: config.sound ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 9))
                    Text(config.sound ? "Sound" : "Silent")
                        .font(.monoXSmall)
                }
                .foregroundColor(config.sound ? SemanticColor.info : .secondary)

                // Include output indicator
                if config.includeOutput {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("Output")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.success)
                }

                Spacer()
            }
        }
    }
}

struct IntentExtractStepReadView: View {
    let config: IntentExtractStepConfig
    @ObservedObject private var workflowManager = WorkflowManager.shared

    private func workflowName(for id: UUID?) -> String? {
        guard let id = id else { return nil }
        return workflowManager.workflows.first { $0.id == id }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Method, Confidence, Notify
            HStack(spacing: Spacing.sm) {
                // Extraction method badge
                HStack(spacing: 4) {
                    Image(systemName: methodIcon)
                        .font(.system(size: 9))
                    Text(config.extractionMethod.rawValue.uppercased())
                        .font(.techLabelSmall)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 3)
                .background(methodColor.opacity(0.15))
                .foregroundColor(methodColor)
                .cornerRadius(CornerRadius.xs)

                // Confidence threshold
                HStack(spacing: 2) {
                    Image(systemName: "dial.low")
                        .font(.system(size: 9))
                    Text("\(Int(config.confidenceThreshold * 100))%")
                        .font(.monoXSmall)
                }
                .foregroundColor(.secondary)

                Spacer()
            }

            // Row 2: Configured intents list
            let enabledIntents = config.recognizedIntents.filter { $0.isEnabled }
            let disabledIntents = config.recognizedIntents.filter { !$0.isEnabled }

            if !enabledIntents.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("INTENTS")
                        .font(.techLabelSmall)
                        .tracking(Tracking.tight)
                        .foregroundColor(.secondary.opacity(0.6))

                    // Intent cards
                    ForEach(enabledIntents) { intent in
                        IntentReadRow(intent: intent, workflowName: workflowName(for: intent.targetWorkflowId))
                    }

                    // Show disabled count if any
                    if !disabledIntents.isEmpty {
                        Text("\(disabledIntents.count) disabled: \(disabledIntents.map { $0.name }.joined(separator: ", "))")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary.opacity(0.5))
                            .italic()
                    }
                }
            } else {
                Text("No intents configured")
                    .font(.monoXSmall)
                    .foregroundColor(.secondary.opacity(0.5))
                    .italic()
            }
        }
    }

    private var methodIcon: String {
        switch config.extractionMethod {
        case .llm: return "brain"
        case .keywords: return "textformat.abc"
        case .hybrid: return "arrow.triangle.merge"
        }
    }

    private var methodColor: Color {
        switch config.extractionMethod {
        case .llm: return .purple
        case .keywords: return .green
        case .hybrid: return .orange
        }
    }
}

/// Compact row showing a single intent's configuration
struct IntentReadRow: View {
    let intent: IntentDefinition
    let workflowName: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Intent name
            Text(intent.name)
                .font(.monoSmall)
                .foregroundColor(.primary)

            // Synonyms count
            if !intent.synonyms.isEmpty {
                Text("(+\(intent.synonyms.count))")
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)
            }

            // Arrow and target workflow
            if let workflow = workflowName {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)

                Text(workflow)
                    .font(.monoXSmall)
                    .foregroundColor(SemanticColor.info)
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.xs)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(CornerRadius.xs)
    }
}

struct EmailStepReadView: View {
    let config: EmailStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Recipients
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.info)

                Text(config.to)
                    .font(.monoSmall)
                    .foregroundColor(.primary)

                // CC/BCC indicators
                if config.cc != nil || config.bcc != nil {
                    Text("•")
                        .foregroundColor(.secondary)

                    if config.cc != nil {
                        Text("CC")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                    }
                    if config.bcc != nil {
                        Text("BCC")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Row 2: Subject line
            Text(config.subject)
                .font(.monoSmall)
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(1)

            // Row 3: Body preview with HTML indicator
            HStack(spacing: Spacing.xs) {
                if config.isHTML {
                    Text("HTML")
                        .font(.techLabelSmall)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(SemanticColor.processing.opacity(0.2))
                        .foregroundColor(SemanticColor.processing)
                        .cornerRadius(CornerRadius.xs)
                }

                Text(config.body)
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct AppleNotesStepReadView: View {
    let config: AppleNotesStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Notes icon + folder + title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)

                if let folder = config.folderName, !folder.isEmpty {
                    Text(folder)
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)

                    Text("/")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Text(config.title)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Body preview
            Text(config.body)
                .font(.monoXSmall)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Row 3: Options
            HStack(spacing: Spacing.sm) {
                if config.attachTranscript {
                    HStack(spacing: 2) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9))
                        Text("Attach Transcript")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                Spacer()
            }
        }
    }
}

struct AppleRemindersStepReadView: View {
    let config: AppleRemindersStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Reminders icon + list + title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)

                if let list = config.listName, !list.isEmpty {
                    Text(list)
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)

                    Text("/")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Text(config.title)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Metadata badges
            HStack(spacing: Spacing.sm) {
                // Due date
                if let due = config.dueDate, !due.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(due)
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.warning)
                }

                // Priority
                if config.priority != .none {
                    HStack(spacing: 2) {
                        Image(systemName: priorityIcon)
                            .font(.system(size: 9))
                        Text(config.priority.displayName)
                            .font(.monoXSmall)
                    }
                    .foregroundColor(priorityColor)
                }

                Spacer()
            }

            // Row 3: Notes preview if set
            if let notes = config.notes, !notes.isEmpty {
                Text(notes)
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var priorityIcon: String {
        switch config.priority {
        case .high: return "exclamationmark.3"
        case .medium: return "exclamationmark.2"
        case .low: return "exclamationmark"
        case .none: return "minus"
        }
    }

    private var priorityColor: Color {
        switch config.priority {
        case .high: return SemanticColor.error
        case .medium: return SemanticColor.warning
        case .low: return SemanticColor.info
        case .none: return .secondary
        }
    }
}

struct AppleCalendarStepReadView: View {
    let config: AppleCalendarStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Calendar icon + calendar name + title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.red)

                if let calendar = config.calendarName, !calendar.isEmpty {
                    Text(calendar)
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)

                    Text("/")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Text(config.title)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Metadata badges
            HStack(spacing: Spacing.sm) {
                // Duration or All Day
                if config.isAllDay {
                    HStack(spacing: 2) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 9))
                        Text("All Day")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.warning)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("\(config.duration / 60) min")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                // Start date if set
                if let start = config.startDate, !start.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 9))
                        Text(start)
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                // Location
                if let loc = config.location, !loc.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                        Text(loc)
                            .font(.monoXSmall)
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 3: Notes preview if set
            if let notes = config.notes, !notes.isEmpty {
                Text(notes)
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct ClipboardStepReadView: View {
    let config: ClipboardStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Icon + content preview
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.success)

                Text("Copy to Clipboard")
                    .font(.monoSmall)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Row 2: Content template in code box
            Text(config.content)
                .font(.monoXSmall)
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.xs)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(CornerRadius.xs)
        }
    }
}

struct SaveFileStepReadView: View {
    let config: SaveFileStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Icon + filename
            HStack(spacing: Spacing.xs) {
                Image(systemName: config.appendIfExists ? "doc.badge.arrow.up" : "doc.badge.plus")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.success)

                Text(config.filename)
                    .font(.monoSmall)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Row 2: Metadata
            HStack(spacing: Spacing.sm) {
                // Directory
                if let dir = config.directory, !dir.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(dir.components(separatedBy: "/").last ?? dir)
                            .font(.monoXSmall)
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("Default")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                // Append mode
                if config.appendIfExists {
                    HStack(spacing: 2) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 9))
                        Text("Append")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.info)
                }

                Spacer()
            }

            // Row 3: Content template preview
            if !config.content.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("CONTENT")
                        .font(.techLabelSmall)
                        .tracking(Tracking.tight)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(config.content)
                        .font(.monoXSmall)
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.xs)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(CornerRadius.xs)
                }
            }
        }
    }
}

struct ConditionalStepReadView: View {
    let config: ConditionalStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Icon + condition
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.warning)

                Text("IF")
                    .font(.techLabelSmall)
                    .foregroundColor(SemanticColor.warning)

                Text(config.condition)
                    .font(.monoSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Branch info
            HStack(spacing: Spacing.sm) {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                    Text("\(config.thenSteps.count) then")
                        .font(.monoXSmall)
                }
                .foregroundColor(SemanticColor.success)

                HStack(spacing: 2) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 9))
                    Text("\(config.elseSteps.count) else")
                        .font(.monoXSmall)
                }
                .foregroundColor(config.elseSteps.isEmpty ? .secondary : SemanticColor.error)

                Spacer()
            }
        }
    }
}

struct TransformStepReadView: View {
    let config: TransformStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Operation badge + description
            HStack(spacing: Spacing.xs) {
                Text(config.operation.rawValue.uppercased())
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(SemanticColor.processing.opacity(0.2))
                    .foregroundColor(SemanticColor.processing)
                    .cornerRadius(CornerRadius.xs)

                Text(config.operation.description)
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }

            // Row 2: Parameters if any
            if !config.parameters.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(config.parameters.keys.sorted().prefix(3)), id: \.self) { key in
                        if let value = config.parameters[key], !value.isEmpty {
                            HStack(spacing: 2) {
                                Text(key)
                                    .font(.techLabelSmall)
                                    .foregroundColor(.secondary)
                                Text(value)
                                    .font(.monoXSmall)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

struct TranscribeStepReadView: View {
    let config: TranscribeStepConfig

    private var modelName: String {
        TranscribeStepConfig.availableModels.first { $0.id == config.model }?.name ?? config.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Model info
            HStack(spacing: Spacing.xs) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.processing)

                Text("Whisper")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(SemanticColor.processing.opacity(0.2))
                    .foregroundColor(SemanticColor.processing)
                    .cornerRadius(CornerRadius.xs)

                Text(modelName)
                    .font(.monoSmall)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Row 2: Options
            HStack(spacing: Spacing.sm) {
                if config.overwriteExisting {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Overwrite")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.orange)
                }

                if config.saveAsVersion {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 9))
                        Text("Save version")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.success)
                }

                Spacer()
            }
        }
    }
}

struct SpeakStepReadView: View {
    let config: SpeakStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Speak mode info
            HStack(spacing: Spacing.xs) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)

                Text("Walkie-Talkie")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.2))
                    .foregroundColor(.cyan)
                    .cornerRadius(2)

                if config.playImmediately {
                    Text("PLAY NOW")
                        .font(.techLabelSmall)
                        .foregroundColor(SemanticColor.success)
                }

                if config.saveToFile {
                    Text("SAVE")
                        .font(.techLabelSmall)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 2: Text preview
            Text(config.text.prefix(80) + (config.text.count > 80 ? "..." : ""))
                .font(.monoXSmall)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
}

struct TriggerStepReadView: View {
    let config: TriggerStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Phrases
            HStack(spacing: Spacing.xs) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.info)

                ForEach(config.phrases.prefix(3), id: \.self) { phrase in
                    Text("\"\(phrase)\"")
                        .font(.monoSmall)
                        .foregroundColor(.primary)
                }

                if config.phrases.count > 3 {
                    Text("+\(config.phrases.count - 3)")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 2: Search options
            HStack(spacing: Spacing.sm) {
                // Search location
                HStack(spacing: 2) {
                    Image(systemName: locationIcon)
                        .font(.system(size: 9))
                    Text(config.searchLocation.rawValue)
                        .font(.monoXSmall)
                }
                .foregroundColor(.secondary)

                // Case sensitive
                if config.caseSensitive {
                    HStack(spacing: 2) {
                        Image(systemName: "textformat")
                            .font(.system(size: 9))
                        Text("Case sensitive")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(.secondary)
                }

                // Context window
                HStack(spacing: 2) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 9))
                    Text("\(config.contextWindowSize) words")
                        .font(.monoXSmall)
                }
                .foregroundColor(.secondary)

                // Gate indicator
                if config.stopIfNoMatch {
                    HStack(spacing: 2) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 9))
                        Text("Gate")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(SemanticColor.warning)
                }

                Spacer()
            }
        }
    }

    private var locationIcon: String {
        switch config.searchLocation {
        case .start: return "arrow.backward.to.line"
        case .end: return "arrow.forward.to.line"
        case .anywhere: return "arrow.left.and.right"
        }
    }
}

struct ExecuteWorkflowsStepReadView: View {
    let config: ExecuteWorkflowsStepConfig

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundColor(SemanticColor.info)

            // Show parallel vs sequential
            Text(config.parallel ? "PARALLEL" : "SEQUENTIAL")
                .font(.techLabelSmall)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(SemanticColor.info.opacity(0.2))
                .foregroundColor(SemanticColor.info)
                .cornerRadius(CornerRadius.xs)
        }
    }
}

// MARK: - Step Config Editors

struct LLMStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: LLMStepConfig {
        if case .llm(let c) = step.config { return c }
        return LLMStepConfig(provider: .gemini, prompt: "")
    }

    // Get available models for the current provider
    // For MLX (local), only show installed models
    private var availableModels: [WorkflowModelOption] {
        guard let provider = config.provider else {
            // Auto-route mode - return empty for now (model selected at runtime)
            return []
        }
        if provider == .mlx {
            // Get installed MLX models dynamically
            let installedModels = MLXModelManager.shared.availableModels()
                .filter { $0.isInstalled }
                .map { model in
                    WorkflowModelOption(
                        id: model.id,
                        name: model.displayName.replacingOccurrences(of: " (4-bit)", with: ""),
                        contextWindow: 8192 // Default context for local models
                    )
                }
            return installedModels
        }
        return provider.models
    }

    // Validated model ID - ensures selection is always valid
    private var validatedModelId: String {
        let models = availableModels
        // If current modelId is in available models, use it
        if let modelId = config.modelId, models.contains(where: { $0.id == modelId }) {
            return modelId
        }
        // Otherwise return first available model's ID, or empty string
        return models.first?.id ?? ""
    }

    // Check if current provider is local
    private var isLocalProvider: Bool {
        config.provider == .mlx
    }

    // Check if in auto-route mode
    private var isAutoRoute: Bool {
        config.provider == nil
    }

    // Local providers
    private var localProviders: [WorkflowLLMProvider] {
        [.mlx]
    }

    // External providers
    private var externalProviders: [WorkflowLLMProvider] {
        WorkflowLLMProvider.allCases.filter { $0 != .mlx }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider selection with LOCAL/EXTERNAL distinction
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROVIDER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { config.provider ?? .gemini },
                        set: { newProvider in
                            var newConfig = config
                            newConfig.provider = newProvider
                            // Reset to provider's default model when switching
                            if newProvider == .mlx {
                                // For MLX, pick first installed model or empty
                                let installed = MLXModelManager.shared.availableModels().filter { $0.isInstalled }
                                newConfig.modelId = installed.first?.id ?? ""
                            } else {
                                newConfig.modelId = newProvider.defaultModel.id
                            }
                            step.config = .llm(newConfig)
                        }
                    )) {
                        // LOCAL section
                        Section {
                            ForEach(localProviders, id: \.self) { provider in
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.green)
                                    Text(provider.displayName)
                                }
                                .tag(provider)
                            }
                        } header: {
                            Label("LOCAL", systemImage: "cpu")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.green)
                        }

                        // EXTERNAL section
                        Section {
                            ForEach(externalProviders, id: \.self) { provider in
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 8))
                                        .foregroundColor(.orange)
                                    Text(provider.displayName)
                                }
                                .tag(provider)
                            }
                        } header: {
                            Label("EXTERNAL", systemImage: "globe")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 10, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("MODEL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)

                        // Badge showing LOCAL or EXTERNAL
                        if isLocalProvider {
                            Text("LOCAL")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(2)
                        } else {
                            Text("API")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(2)
                        }
                    }

                    if availableModels.isEmpty && isLocalProvider {
                        // No models installed warning
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("No models installed")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.vertical, 4)
                    } else {
                        Picker("", selection: Binding(
                            get: { validatedModelId },
                            set: { newModelId in
                                var newConfig = config
                                newConfig.modelId = newModelId
                                step.config = .llm(newConfig)
                            }
                        )) {
                            ForEach(availableModels) { model in
                                HStack {
                                    Text(model.name)
                                    Text("(\(model.formattedContext))")
                                        .foregroundColor(.secondary)
                                }
                                .tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .font(.system(size: 10, design: .monospaced))
                        .onAppear {
                            // Auto-fix invalid model selection
                            if config.modelId != validatedModelId && !validatedModelId.isEmpty {
                                var newConfig = config
                                newConfig.modelId = validatedModelId
                                step.config = .llm(newConfig)
                            }
                        }
                    }
                }
            }

            // Temperature and Max Tokens
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TEMPERATURE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    HStack {
                        Slider(value: Binding(
                            get: { config.temperature },
                            set: { newValue in
                                var newConfig = config
                                newConfig.temperature = newValue
                                step.config = .llm(newConfig)
                            }
                        ), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", config.temperature))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 30)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MAX TOKENS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    TextField("1024", value: Binding(
                        get: { config.maxTokens },
                        set: { newValue in
                            var newConfig = config
                            newConfig.maxTokens = newValue
                            step.config = .llm(newConfig)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                }
            }

            // Prompt
            VStack(alignment: .leading, spacing: 6) {
                Text("PROMPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.prompt },
                    set: { newValue in
                        var newConfig = config
                        newConfig.prompt = newValue
                        step.config = .llm(newConfig)
                    }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)

                Text("Available: {{TRANSCRIPT}}, {{TITLE}}, {{DATE}}, {{PREVIOUS_OUTPUT}}")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}

struct ShellStepConfigEditor: View {
    @Binding var step: WorkflowStep
    @State private var argumentsText: String = ""
    @State private var promptTemplate: String = ""
    @State private var usePromptTemplate: Bool = false

    private var config: ShellStepConfig {
        if case .shell(let c) = step.config { return c }
        return ShellStepConfig(executable: "/bin/echo", arguments: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preset selector
            VStack(alignment: .leading, spacing: 6) {
                Text("PRESET")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(ShellStepConfig.Preset.allCases, id: \.self) { preset in
                        Button(action: {
                            let newConfig = preset.exampleConfig
                            step.config = .shell(newConfig)
                            argumentsText = newConfig.arguments.joined(separator: " ")
                            promptTemplate = newConfig.promptTemplate ?? ""
                            usePromptTemplate = newConfig.promptTemplate != nil
                        }) {
                            Text(preset.rawValue)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Executable path
            VStack(alignment: .leading, spacing: 6) {
                Text("EXECUTABLE PATH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("/path/to/command", text: Binding(
                        get: { config.executable },
                        set: { newValue in
                            var newConfig = config
                            newConfig.executable = newValue
                            step.config = .shell(newConfig)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))

                    // Security indicator
                    if config.isExecutableAllowed() {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                            .help("Executable is in allowlist")
                    } else {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                            .help("Executable not in allowlist - add via Settings")
                    }
                }
            }

            // Arguments
            VStack(alignment: .leading, spacing: 6) {
                Text("ARGUMENTS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextField("arg1 arg2 {{TRANSCRIPT}}", text: $argumentsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .onChange(of: argumentsText) { _, newValue in
                        var newConfig = config
                        // Split by space but preserve quoted strings
                        newConfig.arguments = parseArguments(newValue)
                        step.config = .shell(newConfig)
                    }
                    .onAppear {
                        argumentsText = config.arguments.joined(separator: " ")
                        promptTemplate = config.promptTemplate ?? ""
                        usePromptTemplate = config.promptTemplate != nil
                    }

                if usePromptTemplate {
                    Text("Note: Arguments are passed before -p flag. Leave empty for claude.")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                } else {
                    Text("Supports template variables. Arguments are passed directly (no shell expansion).")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            // Prompt Template toggle and editor
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $usePromptTemplate) {
                    HStack(spacing: 4) {
                        Text("PROMPT TEMPLATE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)
                        Text("(for claude -p)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .onChange(of: usePromptTemplate) { _, enabled in
                    var newConfig = config
                    newConfig.promptTemplate = enabled ? promptTemplate : nil
                    // Clear arguments when enabling prompt template to avoid duplicate content
                    if enabled && !config.arguments.isEmpty {
                        newConfig.arguments = []
                        argumentsText = ""
                    }
                    step.config = .shell(newConfig)
                }

                if usePromptTemplate {
                    TextEditor(text: $promptTemplate)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: promptTemplate) { _, newValue in
                            var newConfig = config
                            newConfig.promptTemplate = newValue.isEmpty ? nil : newValue
                            step.config = .shell(newConfig)
                        }

                    Text("Multi-line prompt passed via -p flag. Use {{TRANSCRIPT}}, {{PREVIOUS_OUTPUT}}, etc.")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            // Stdin input
            VStack(alignment: .leading, spacing: 6) {
                Text("STDIN INPUT (OPTIONAL)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextField("{{TRANSCRIPT}} or {{OUTPUT}}", text: Binding(
                    get: { config.stdin ?? "" },
                    set: { newValue in
                        var newConfig = config
                        newConfig.stdin = newValue.isEmpty ? nil : newValue
                        step.config = .shell(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                Text("Data to pipe to the command's stdin. Use for tools like jq, python, etc.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Timeout
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIMEOUT (SECONDS)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    TextField("30", value: Binding(
                        get: { config.timeout },
                        set: { newValue in
                            var newConfig = config
                            newConfig.timeout = max(1, min(300, newValue))
                            step.config = .shell(newConfig)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 60)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("OPTIONS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    Toggle("Capture stderr", isOn: Binding(
                        get: { config.captureStderr },
                        set: { newValue in
                            var newConfig = config
                            newConfig.captureStderr = newValue
                            step.config = .shell(newConfig)
                        }
                    ))
                    .font(.system(size: 10))
                }
            }

            // Available variables help
            Text("Variables: {{TRANSCRIPT}}, {{TITLE}}, {{DATE}}, {{OUTPUT}}, {{PREVIOUS_OUTPUT}}")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))

            // Security note
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                Text("Only allowlisted executables can run. No shell expansion or command chaining.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // Simple argument parser - splits by space, respects quotes
    private func parseArguments(_ input: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""

        for char in input {
            if (char == "\"" || char == "'") && !inQuotes {
                inQuotes = true
                quoteChar = char
            } else if char == quoteChar && inQuotes {
                inQuotes = false
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            args.append(current)
        }

        return args
    }
}

struct WebhookStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: WebhookStepConfig {
        if case .webhook(let c) = step.config { return c }
        return WebhookStepConfig(url: "", method: .post)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("METHOD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { config.method },
                        set: { newValue in
                            var newConfig = config
                            newConfig.method = newValue
                            step.config = .webhook(newConfig)
                        }
                    )) {
                        ForEach(WebhookStepConfig.HTTPMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("URL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    TextField("https://...", text: Binding(
                        get: { config.url },
                        set: { newValue in
                            var newConfig = config
                            newConfig.url = newValue
                            step.config = .webhook(newConfig)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                }
            }

            HStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { config.includeTranscript },
                    set: { newValue in
                        var newConfig = config
                        newConfig.includeTranscript = newValue
                        step.config = .webhook(newConfig)
                    }
                )) {
                    Text("Include Transcript")
                        .font(.system(size: 10, design: .monospaced))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { config.includeMetadata },
                    set: { newValue in
                        var newConfig = config
                        newConfig.includeMetadata = newValue
                        step.config = .webhook(newConfig)
                    }
                )) {
                    Text("Include Metadata")
                        .font(.system(size: 10, design: .monospaced))
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

struct EmailStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: EmailStepConfig {
        if case .email(let c) = step.config { return c }
        return EmailStepConfig(to: "", subject: "", body: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("email@example.com", text: Binding(
                    get: { config.to },
                    set: { newValue in
                        var newConfig = config
                        newConfig.to = newValue
                        step.config = .email(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SUBJECT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Email subject", text: Binding(
                    get: { config.subject },
                    set: { newValue in
                        var newConfig = config
                        newConfig.subject = newValue
                        step.config = .email(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BODY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.body },
                    set: { newValue in
                        var newConfig = config
                        newConfig.body = newValue
                        step.config = .email(newConfig)
                    }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
        }
    }
}

struct NotificationStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: NotificationStepConfig {
        if case .notification(let c) = step.config { return c }
        return NotificationStepConfig(title: "", body: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Notification title", text: Binding(
                    get: { config.title },
                    set: { newValue in
                        var newConfig = config
                        newConfig.title = newValue
                        step.config = .notification(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BODY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Notification body", text: Binding(
                    get: { config.body },
                    set: { newValue in
                        var newConfig = config
                        newConfig.body = newValue
                        step.config = .notification(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            Toggle(isOn: Binding(
                get: { config.sound },
                set: { newValue in
                    var newConfig = config
                    newConfig.sound = newValue
                    step.config = .notification(newConfig)
                }
            )) {
                Text("Play Sound")
                    .font(.system(size: 10, design: .monospaced))
            }
            .toggleStyle(.checkbox)
        }
    }
}

struct iOSPushStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: iOSPushStepConfig {
        if case .iOSPush(let c) = step.config { return c }
        return iOSPushStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "iphone.badge.play")
                    .foregroundColor(.blue)
                Text("Sends a push notification to your iPhone via CloudKit")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("{{WORKFLOW_NAME}} Complete", text: Binding(
                    get: { config.title },
                    set: { newValue in
                        var newConfig = config
                        newConfig.title = newValue
                        step.config = .iOSPush(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                Text("Use {{WORKFLOW_NAME}}, {{TITLE}}, {{OUTPUT}}")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BODY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Finished processing {{TITLE}}", text: Binding(
                    get: { config.body },
                    set: { newValue in
                        var newConfig = config
                        newConfig.body = newValue
                        step.config = .iOSPush(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            HStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { config.sound },
                    set: { newValue in
                        var newConfig = config
                        newConfig.sound = newValue
                        step.config = .iOSPush(newConfig)
                    }
                )) {
                    Text("Play Sound")
                        .font(.system(size: 10, design: .monospaced))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { config.includeOutput },
                    set: { newValue in
                        var newConfig = config
                        newConfig.includeOutput = newValue
                        step.config = .iOSPush(newConfig)
                    }
                )) {
                    Text("Include Output")
                        .font(.system(size: 10, design: .monospaced))
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

struct AppleNotesStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: AppleNotesStepConfig {
        if case .appleNotes(let c) = step.config { return c }
        return AppleNotesStepConfig(title: "", body: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FOLDER (OPTIONAL)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Folder name", text: Binding(
                    get: { config.folderName ?? "" },
                    set: { newValue in
                        var newConfig = config
                        newConfig.folderName = newValue.isEmpty ? nil : newValue
                        step.config = .appleNotes(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Note title", text: Binding(
                    get: { config.title },
                    set: { newValue in
                        var newConfig = config
                        newConfig.title = newValue
                        step.config = .appleNotes(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BODY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.body },
                    set: { newValue in
                        var newConfig = config
                        newConfig.body = newValue
                        step.config = .appleNotes(newConfig)
                    }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }

            Toggle(isOn: Binding(
                get: { config.attachTranscript },
                set: { newValue in
                    var newConfig = config
                    newConfig.attachTranscript = newValue
                    step.config = .appleNotes(newConfig)
                }
            )) {
                Text("Attach Transcript")
                    .font(.system(size: 10, design: .monospaced))
            }
            .toggleStyle(.checkbox)
        }
    }
}

struct AppleRemindersStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: AppleRemindersStepConfig {
        if case .appleReminders(let c) = step.config { return c }
        return AppleRemindersStepConfig(title: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIST (OPTIONAL)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("List name", text: Binding(
                    get: { config.listName ?? "" },
                    set: { newValue in
                        var newConfig = config
                        newConfig.listName = newValue.isEmpty ? nil : newValue
                        step.config = .appleReminders(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Reminder title", text: Binding(
                    get: { config.title },
                    set: { newValue in
                        var newConfig = config
                        newConfig.title = newValue
                        step.config = .appleReminders(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRIORITY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { config.priority },
                        set: { newValue in
                            var newConfig = config
                            newConfig.priority = newValue
                            step.config = .appleReminders(newConfig)
                        }
                    )) {
                        ForEach(AppleRemindersStepConfig.ReminderPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DUE DATE (OPTIONAL)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("{{NOW+1d}}", text: Binding(
                        get: { config.dueDate ?? "" },
                        set: { newValue in
                            var newConfig = config
                            newConfig.dueDate = newValue.isEmpty ? nil : newValue
                            step.config = .appleReminders(newConfig)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }
}

struct AppleCalendarStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: AppleCalendarStepConfig {
        if case .appleCalendar(let c) = step.config { return c }
        return AppleCalendarStepConfig(title: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Event title", text: Binding(
                    get: { config.title },
                    set: { newValue in
                        var newConfig = config
                        newConfig.title = newValue
                        step.config = .appleCalendar(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DURATION (MINUTES)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("60", value: Binding(
                        get: { config.duration / 60 },
                        set: { newValue in
                            var newConfig = config
                            newConfig.duration = newValue * 60
                            step.config = .appleCalendar(newConfig)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("LOCATION (OPTIONAL)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("Location", text: Binding(
                        get: { config.location ?? "" },
                        set: { newValue in
                            var newConfig = config
                            newConfig.location = newValue.isEmpty ? nil : newValue
                            step.config = .appleCalendar(newConfig)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                }
            }

            Toggle(isOn: Binding(
                get: { config.isAllDay },
                set: { newValue in
                    var newConfig = config
                    newConfig.isAllDay = newValue
                    step.config = .appleCalendar(newConfig)
                }
            )) {
                Text("All Day Event")
                    .font(.system(size: 10, design: .monospaced))
            }
            .toggleStyle(.checkbox)
        }
    }
}

struct ClipboardStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: ClipboardStepConfig {
        if case .clipboard(let c) = step.config { return c }
        return ClipboardStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTENT TO COPY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            TextField("{{OUTPUT}}", text: Binding(
                get: { config.content },
                set: { newValue in
                    var newConfig = config
                    newConfig.content = newValue
                    step.config = .clipboard(newConfig)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 10, design: .monospaced))

            Text("Variables: {{OUTPUT}}, {{TRANSCRIPT}}, {{TITLE}}")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

struct SaveFileStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: SaveFileStepConfig {
        if case .saveFile(let c) = step.config { return c }
        return SaveFileStepConfig(filename: "output.txt", content: "{{OUTPUT}}")
    }

    /// Parse the filename to check for @alias and return status info
    private var aliasInfo: (hasAlias: Bool, aliasName: String?, resolvedPath: String?, isValid: Bool) {
        let filename = config.filename
        guard filename.hasPrefix("@") else {
            return (false, nil, nil, false)
        }

        // Extract alias name
        let withoutAt = String(filename.dropFirst())
        let components = withoutAt.split(separator: "/", maxSplits: 1)
        let aliasName = String(components.first ?? "")

        // Check if alias exists
        let aliases = SaveFileStepConfig.pathAliases
        if let resolvedBase = aliases[aliasName] {
            let remainder = components.count > 1 ? "/" + components[1] : ""
            return (true, aliasName, resolvedBase + remainder, true)
        } else {
            return (true, aliasName, nil, false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FILENAME")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("@Obsidian/{{DATE}}.md", text: Binding(
                    get: { config.filename },
                    set: { newValue in
                        var newConfig = config
                        newConfig.filename = newValue
                        step.config = .saveFile(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                // Alias feedback
                if aliasInfo.hasAlias {
                    if aliasInfo.isValid, let resolved = aliasInfo.resolvedPath {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                            Text("@\(aliasInfo.aliasName ?? "")")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text(resolved)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 9, design: .monospaced))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text("@\(aliasInfo.aliasName ?? "") not found")
                                .foregroundColor(.orange)
                            Text("— define in Settings → Output Directory")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }
                } else {
                    // Show default directory hint
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                            .font(.system(size: 9))
                        Text("Will save to: \(SaveFileStepConfig.defaultOutputDirectory)/...")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 9, design: .monospaced))
                }

                // Variables hint
                Text("Variables: {{DATE}}, {{DATETIME}}, {{TITLE}}")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CONTENT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.content },
                    set: { newValue in
                        var newConfig = config
                        newConfig.content = newValue
                        step.config = .saveFile(newConfig)
                    }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }

            Toggle(isOn: Binding(
                get: { config.appendIfExists },
                set: { newValue in
                    var newConfig = config
                    newConfig.appendIfExists = newValue
                    step.config = .saveFile(newConfig)
                }
            )) {
                Text("Append if file exists")
                    .font(.system(size: 10, design: .monospaced))
            }
            .toggleStyle(.checkbox)
        }
    }
}

struct ConditionalStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: ConditionalStepConfig {
        if case .conditional(let c) = step.config { return c }
        return ConditionalStepConfig(condition: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONDITION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("{{OUTPUT}} contains 'urgent'", text: Binding(
                    get: { config.condition },
                    set: { newValue in
                        var newConfig = config
                        newConfig.condition = newValue
                        step.config = .conditional(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                Text("Operators: contains, equals, startsWith, endsWith, isEmpty, isNotEmpty")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Text("Note: Conditional branching configuration is simplified. Full support coming soon.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.orange)
                .italic()
        }
    }
}

struct TransformStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: TransformStepConfig {
        if case .transform(let c) = step.config { return c }
        return TransformStepConfig(operation: .extractJSON)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPERATION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { config.operation },
                    set: { newValue in
                        var newConfig = config
                        newConfig.operation = newValue
                        step.config = .transform(newConfig)
                    }
                )) {
                    ForEach(TransformStepConfig.TransformOperation.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                .labelsHidden()

                Text(config.operation.description)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Transcribe Step Config Editor

struct TranscribeStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: TranscribeStepConfig {
        if case .transcribe(let c) = step.config { return c }
        return TranscribeStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model selection
            VStack(alignment: .leading, spacing: 6) {
                Text("WHISPER MODEL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { config.model },
                    set: { newValue in
                        var newConfig = config
                        newConfig.model = newValue
                        step.config = .transcribe(newConfig)
                    }
                )) {
                    ForEach(TranscribeStepConfig.availableModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()

                // Model description
                if let model = TranscribeStepConfig.availableModels.first(where: { $0.id == config.model }) {
                    Text(model.description)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .opacity(0.3)

            // Options
            VStack(alignment: .leading, spacing: 8) {
                Text("OPTIONS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                Toggle(isOn: Binding(
                    get: { config.overwriteExisting },
                    set: { newValue in
                        var newConfig = config
                        newConfig.overwriteExisting = newValue
                        step.config = .transcribe(newConfig)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Overwrite existing transcript")
                            .font(.system(size: 10, design: .monospaced))
                        Text("Re-transcribe even if memo already has a transcript")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle(isOn: Binding(
                    get: { config.saveAsVersion },
                    set: { newValue in
                        var newConfig = config
                        newConfig.saveAsVersion = newValue
                        step.config = .transcribe(newConfig)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save as transcript version")
                            .font(.system(size: 10, design: .monospaced))
                        Text("Store the transcript in memo's version history")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Info note
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                Text("Model will be downloaded on first use (~40MB-750MB)")
                    .font(.system(size: 8, design: .monospaced))
            }
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
    }
}

// MARK: - Speak Step Config Editor (Walkie-Talkie!)

struct SpeakStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: SpeakStepConfig {
        if case .speak(let c) = step.config { return c }
        return SpeakStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Text to speak
            VStack(alignment: .leading, spacing: 6) {
                Text("TEXT TO SPEAK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.text },
                    set: { newValue in
                        var newConfig = config
                        newConfig.text = newValue
                        step.config = .speak(newConfig)
                    }
                ))
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 60, maxHeight: 100)
                .padding(4)
                .background(Color.black.opacity(0.2))
                .cornerRadius(4)

                Text("Use {{OUTPUT}} for previous step result, {{TRANSCRIPT}} for memo text")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()
                .opacity(0.3)

            // Rate slider
            VStack(alignment: .leading, spacing: 6) {
                Text("SPEECH RATE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Slow")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)

                    Slider(value: Binding(
                        get: { Double(config.rate) },
                        set: { newValue in
                            var newConfig = config
                            newConfig.rate = Float(newValue)
                            step.config = .speak(newConfig)
                        }
                    ), in: 0.1...1.0)

                    Text("Fast")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .opacity(0.3)

            // Options
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { config.playImmediately },
                    set: { newValue in
                        var newConfig = config
                        newConfig.playImmediately = newValue
                        step.config = .speak(newConfig)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play immediately")
                            .font(.system(size: 10, design: .monospaced))
                        Text("Speak the text when step executes")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle(isOn: Binding(
                    get: { config.saveToFile },
                    set: { newValue in
                        var newConfig = config
                        newConfig.saveToFile = newValue
                        step.config = .speak(newConfig)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to file")
                            .font(.system(size: 10, design: .monospaced))
                        Text("Also save speech as audio file")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Info note
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 9))
                Text("Walkie-Talkie mode: Talkie speaks back to you!")
                    .font(.system(size: 8, design: .monospaced))
            }
            .foregroundColor(.cyan)
            .padding(.top, 4)
        }
    }
}

// MARK: - Trigger Step Config Editor

struct TriggerStepConfigEditor: View {
    @Binding var step: WorkflowStep
    @State private var newPhrase = ""

    private var config: TriggerStepConfig {
        if case .trigger(let c) = step.config { return c }
        return TriggerStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Trigger phrases
            VStack(alignment: .leading, spacing: 6) {
                Text("TRIGGER PHRASES")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                ForEach(config.phrases, id: \.self) { phrase in
                    HStack {
                        Text(phrase)
                            .font(.system(size: 10, design: .monospaced))
                        Spacer()
                        Button(action: {
                            var newConfig = config
                            newConfig.phrases.removeAll { $0 == phrase }
                            step.config = .trigger(newConfig)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }

                HStack {
                    TextField("Add phrase...", text: $newPhrase)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                    Button(action: {
                        guard !newPhrase.isEmpty else { return }
                        var newConfig = config
                        newConfig.phrases.append(newPhrase.lowercased())
                        step.config = .trigger(newConfig)
                        newPhrase = ""
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(newPhrase.isEmpty)
                }
            }

            Divider()

            // Search location
            VStack(alignment: .leading, spacing: 6) {
                Text("SEARCH LOCATION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { config.searchLocation },
                    set: { newValue in
                        var newConfig = config
                        newConfig.searchLocation = newValue
                        step.config = .trigger(newConfig)
                    }
                )) {
                    ForEach(TriggerStepConfig.SearchLocation.allCases, id: \.self) { loc in
                        Text(loc.rawValue.capitalized).tag(loc)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(searchLocationDescription)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Options
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTEXT WINDOW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("", value: Binding(
                            get: { config.contextWindowSize },
                            set: { newValue in
                                var newConfig = config
                                newConfig.contextWindowSize = newValue
                                step.config = .trigger(newConfig)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.system(size: 10, design: .monospaced))

                        Text("words")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { config.stopIfNoMatch },
                    set: { newValue in
                        var newConfig = config
                        newConfig.stopIfNoMatch = newValue
                        step.config = .trigger(newConfig)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STOP IF NO MATCH")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)
                        Text("Gates workflow execution")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .toggleStyle(.switch)
            }

            Toggle(isOn: Binding(
                get: { config.caseSensitive },
                set: { newValue in
                    var newConfig = config
                    newConfig.caseSensitive = newValue
                    step.config = .trigger(newConfig)
                }
            )) {
                Text("Case sensitive matching")
                    .font(.system(size: 9, design: .monospaced))
            }
            .toggleStyle(.switch)
        }
    }

    private var searchLocationDescription: String {
        switch config.searchLocation {
        case .end: return "Search from end of transcript (best for voice commands)"
        case .anywhere: return "Search entire transcript"
        case .start: return "Search beginning of transcript only"
        }
    }
}

// MARK: - Intent Extract Step Config Editor

struct IntentExtractStepConfigEditor: View {
    @Binding var step: WorkflowStep
    @State private var expandedIntentId: UUID?
    @State private var showPromptEditor = false

    private var config: IntentExtractStepConfig {
        if case .intentExtract(let c) = step.config { return c }
        return IntentExtractStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Extraction method
            VStack(alignment: .leading, spacing: 6) {
                Text("EXTRACTION METHOD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { config.extractionMethod },
                    set: { newValue in
                        var newConfig = config
                        newConfig.extractionMethod = newValue
                        step.config = .intentExtract(newConfig)
                    }
                )) {
                    ForEach(IntentExtractStepConfig.ExtractionMethod.allCases, id: \.self) { method in
                        Text(method.rawValue.uppercased()).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(extractionMethodDescription)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Input key
            VStack(alignment: .leading, spacing: 6) {
                Text("INPUT KEY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextField("", text: Binding(
                    get: { config.inputKey },
                    set: { newValue in
                        var newConfig = config
                        newConfig.inputKey = newValue
                        step.config = .intentExtract(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                Text("Use {{TRANSCRIPT}} for memo transcript, {{PREVIOUS_OUTPUT}} for previous step, or {{key_name}} for specific output")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // LLM Settings (only show when LLM or Hybrid is selected)
            if config.extractionMethod != .keywords {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("LLM SETTINGS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { showPromptEditor.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showPromptEditor ? "chevron.up" : "chevron.down")
                                Text(showPromptEditor ? "Hide Prompt" : "Edit Prompt")
                            }
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    // Confidence threshold slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Confidence Threshold:")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(String(format: "%.0f%%", config.confidenceThreshold * 100))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }

                        Slider(value: Binding(
                            get: { config.confidenceThreshold },
                            set: { newValue in
                                var newConfig = config
                                newConfig.confidenceThreshold = newValue
                                step.config = .intentExtract(newConfig)
                            }
                        ), in: 0...1, step: 0.05)

                        Text("Intents below this confidence will be filtered out")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Expandable prompt editor
                    if showPromptEditor {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("LLM Prompt Template")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))

                                Spacer()

                                Button(action: resetPromptToDefault) {
                                    Text("Reset to Default")
                                        .font(.system(size: 8, design: .monospaced))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.orange)
                            }

                            TextEditor(text: Binding(
                                get: { config.llmPromptTemplate },
                                set: { newValue in
                                    var newConfig = config
                                    newConfig.llmPromptTemplate = newValue
                                    step.config = .intentExtract(newConfig)
                                }
                            ))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(minHeight: 150, maxHeight: 250)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                            // Available variables
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Available Variables:")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)

                                FlowLayout(spacing: 4) {
                                    ForEach(["{{INPUT}}", "{{TRANSCRIPT}}", "{{INTENT_NAMES}}"], id: \.self) { variable in
                                        Text(variable)
                                            .font(.system(size: 8, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.purple.opacity(0.15))
                                            .cornerRadius(3)
                                    }
                                }

                                Text("The LLM should return: ACTION: [name] | PARAM: [value] | CONFIDENCE: [0.0-1.0]")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
            }

            Divider()

            // Recognized intents
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RECOGNIZED INTENTS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: addNewIntent) {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                Text("Map intents to workflows. When an intent is detected, its target workflow will execute.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))

                ForEach(config.recognizedIntents) { intent in
                    IntentDefinitionRow(
                        intent: intent,
                        isExpanded: expandedIntentId == intent.id,
                        onToggleExpand: { expandedIntentId = expandedIntentId == intent.id ? nil : intent.id },
                        onUpdate: { updated in updateIntent(updated) },
                        onDelete: { deleteIntent(intent) }
                    )
                }
            }
        }
    }

    private var extractionMethodDescription: String {
        switch config.extractionMethod {
        case .llm: return "Use LLM for intelligent intent detection (requires API)"
        case .keywords: return "Simple keyword matching (fast, works offline)"
        case .hybrid: return "Try LLM first, fall back to keywords if unavailable"
        }
    }

    private func resetPromptToDefault() {
        var newConfig = config
        newConfig.llmPromptTemplate = IntentExtractStepConfig.defaultPromptTemplate
        step.config = .intentExtract(newConfig)
    }

    private func addNewIntent() {
        var newConfig = config
        let newIntent = IntentDefinition(
            id: UUID(),
            name: "new_intent",
            synonyms: [],
            targetWorkflowId: nil,
            isEnabled: true
        )
        newConfig.recognizedIntents.append(newIntent)
        step.config = .intentExtract(newConfig)
        expandedIntentId = newIntent.id
    }

    private func updateIntent(_ intent: IntentDefinition) {
        var newConfig = config
        if let index = newConfig.recognizedIntents.firstIndex(where: { $0.id == intent.id }) {
            newConfig.recognizedIntents[index] = intent
            step.config = .intentExtract(newConfig)
        }
    }

    private func deleteIntent(_ intent: IntentDefinition) {
        var newConfig = config
        newConfig.recognizedIntents.removeAll { $0.id == intent.id }
        step.config = .intentExtract(newConfig)
    }
}

struct IntentDefinitionRow: View {
    let intent: IntentDefinition
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onUpdate: (IntentDefinition) -> Void
    let onDelete: () -> Void

    @State private var newSynonym = ""
    @ObservedObject private var workflowManager = WorkflowManager.shared

    /// Available workflows for mapping (excludes Hey Talkie to prevent recursion)
    private var availableWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { $0.id != WorkflowDefinition.heyTalkieWorkflowId }
    }

    /// Get workflow name for display
    private func workflowName(for id: UUID?) -> String {
        guard let id = id else { return "None (use name matching)" }
        if id == IntentDefinition.doNothingId { return "Detect only" }
        return availableWorkflows.first { $0.id == id }?.name ?? "Unknown"
    }

    /// Description for the current target workflow selection
    private var targetWorkflowDescription: String {
        if intent.targetWorkflowId == nil {
            return "Will try to find a workflow matching '\(intent.name)'"
        } else if intent.targetWorkflowId == IntentDefinition.doNothingId {
            return "Intent will be logged but no workflow will execute"
        } else {
            return "When this intent is detected, the selected workflow will execute"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { intent.isEnabled },
                    set: { newValue in
                        var updated = intent
                        updated.isEnabled = newValue
                        onUpdate(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                Text(intent.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(intent.isEnabled ? .primary : .secondary)

                if !intent.synonyms.isEmpty {
                    Text("(\(intent.synonyms.count) synonyms)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Show mapped workflow indicator
                if let workflowId = intent.targetWorkflowId,
                   let workflow = availableWorkflows.first(where: { $0.id == workflowId }) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7))
                        Image(systemName: workflow.icon)
                            .font(.system(size: 8))
                        Text(workflow.name)
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .foregroundColor(workflow.color.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(workflow.color.color.opacity(0.15))
                    .cornerRadius(4)
                }

                Spacer()

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Intent name
                    HStack {
                        Text("Name:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        TextField("", text: Binding(
                            get: { intent.name },
                            set: { newValue in
                                var updated = intent
                                updated.name = newValue.lowercased().replacingOccurrences(of: " ", with: "_")
                                onUpdate(updated)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9, design: .monospaced))
                    }

                    // Synonyms
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Synonyms:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 4) {
                            ForEach(intent.synonyms, id: \.self) { synonym in
                                HStack(spacing: 2) {
                                    Text(synonym)
                                        .font(.system(size: 8, design: .monospaced))
                                    Button(action: {
                                        var updated = intent
                                        updated.synonyms.removeAll { $0 == synonym }
                                        onUpdate(updated)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.15))
                                .cornerRadius(3)
                            }
                        }

                        HStack {
                            TextField("Add synonym...", text: $newSynonym)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 9, design: .monospaced))
                            Button(action: {
                                guard !newSynonym.isEmpty else { return }
                                var updated = intent
                                updated.synonyms.append(newSynonym.lowercased())
                                onUpdate(updated)
                                newSynonym = ""
                            }) {
                                Text("Add")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                            }
                            .buttonStyle(.plain)
                            .disabled(newSynonym.isEmpty)
                        }
                    }

                    // Target workflow picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Workflow:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)

                        Picker("", selection: Binding(
                            get: { intent.targetWorkflowId },
                            set: { newValue in
                                var updated = intent
                                updated.targetWorkflowId = newValue
                                onUpdate(updated)
                            }
                        )) {
                            Text("Auto (match by name)")
                                .tag(nil as UUID?)

                            Text("Detect only")
                                .tag(IntentDefinition.doNothingId as UUID?)

                            Divider()

                            ForEach(availableWorkflows) { workflow in
                                HStack(spacing: 4) {
                                    Image(systemName: workflow.icon)
                                    Text(workflow.name)
                                }
                                .tag(workflow.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text(targetWorkflowDescription)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Execute Workflows Step Config Editor

struct ExecuteWorkflowsStepConfigEditor: View {
    @Binding var step: WorkflowStep

    private var config: ExecuteWorkflowsStepConfig {
        if case .executeWorkflows(let c) = step.config { return c }
        return ExecuteWorkflowsStepConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Intents key
            VStack(alignment: .leading, spacing: 6) {
                Text("INTENTS INPUT KEY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                TextField("", text: Binding(
                    get: { config.intentsKey },
                    set: { newValue in
                        var newConfig = config
                        newConfig.intentsKey = newValue
                        step.config = .executeWorkflows(newConfig)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

                Text("Key containing the intents array from previous step")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Divider()

            // Execution options
            VStack(alignment: .leading, spacing: 8) {
                Text("EXECUTION OPTIONS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.secondary)

                HStack(spacing: 24) {
                    Toggle(isOn: Binding(
                        get: { config.parallel },
                        set: { newValue in
                            var newConfig = config
                            newConfig.parallel = newValue
                            step.config = .executeWorkflows(newConfig)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parallel Execution")
                                .font(.system(size: 9, design: .monospaced))
                            Text("Run workflows concurrently")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: Binding(
                        get: { config.stopOnError },
                        set: { newValue in
                            var newConfig = config
                            newConfig.stopOnError = newValue
                            step.config = .executeWorkflows(newConfig)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop on Error")
                                .font(.system(size: 9, design: .monospaced))
                            Text("Halt if any workflow fails")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            // Info box
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflow Routing")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    Text("This step reads intents from the previous step and executes the workflow mapped to each intent's targetWorkflowId.")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
    }
}
