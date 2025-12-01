//
//  WorkflowViews.swift
//  Talkie macOS
//
//  UI components for workflow management
//

import SwiftUI

// MARK: - Workflow List Item

struct WorkflowListItem: View {
    let workflow: WorkflowDefinition
    let isSelected: Bool
    let isSystem: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: workflow.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(workflow.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workflow Detail View

struct WorkflowDetailView: View {
    let workflow: WorkflowDefinition
    let isSystem: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRun: () -> Void

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
        }
    }
}

// MARK: - Step Details Views

struct LLMStepDetails: View {
    let config: LLMStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DetailBadge(label: config.provider.displayName.uppercased(), color: .blue)
                DetailBadge(label: config.selectedModel?.name ?? config.modelId, color: .purple)
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

    @State private var showingStepTypePicker = false

    private var editedWorkflow: Binding<WorkflowDefinition> {
        Binding(
            get: { workflow ?? WorkflowDefinition(name: "", description: "") },
            set: { workflow = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: editedWorkflow.wrappedValue.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Workflow name", text: editedWorkflow.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textFieldStyle(.plain)

                Spacer()

                // Duplicate button
                Button(action: onDuplicate) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("DUPLICATE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: onRun) {
                    HStack(spacing: 4) {
                        Image(systemName: "play")
                            .font(.system(size: 9))
                        Text("RUN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(editedWorkflow.wrappedValue.steps.isEmpty)

                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 9))
                        Text("SAVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
                .opacity(0.5)

            // Editor content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary.opacity(0.6))

                        TextField("What does this workflow do?", text: editedWorkflow.description)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }

                    // Icon selector (compact)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ICON")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.secondary.opacity(0.6))

                            HStack(spacing: 6) {
                                Image(systemName: editedWorkflow.wrappedValue.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary.opacity(0.7))
                                    .frame(width: 28, height: 28)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(4)

                                TextField("SF Symbol", text: editedWorkflow.icon)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                    .frame(width: 120)
                            }
                        }

                        Spacer()
                    }

                    Divider()
                        .opacity(0.3)

                    // Steps section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("STEPS")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.secondary.opacity(0.6))

                            Spacer()

                            Button(action: { showingStepTypePicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9))
                                    Text("ADD STEP")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .tracking(0.5)
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        if editedWorkflow.wrappedValue.steps.isEmpty {
                            // Empty state
                            VStack(spacing: 10) {
                                Image(systemName: "rectangle.stack.badge.plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.2))

                                Text("NO STEPS")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(.secondary.opacity(0.5))

                                Text("Add steps to define workflow actions")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.4))

                                Button(action: { showingStepTypePicker = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 9))
                                        Text("ADD FIRST STEP")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        } else {
                            ForEach(Array(editedWorkflow.wrappedValue.steps.enumerated()), id: \.element.id) { index, step in
                                WorkflowStepEditor(
                                    step: stepBinding(at: index),
                                    stepNumber: index + 1,
                                    onDelete: { deleteStep(at: index) },
                                    onMoveUp: index > 0 ? { moveStep(from: index, to: index - 1) } : nil,
                                    onMoveDown: index < editedWorkflow.wrappedValue.steps.count - 1 ? { moveStep(from: index, to: index + 1) } : nil
                                )

                                if index < editedWorkflow.wrappedValue.steps.count - 1 {
                                    StepConnector()
                                }
                            }
                        }
                    }
                }
                .padding(16)
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
    }

    private func stepBinding(at index: Int) -> Binding<WorkflowStep> {
        Binding(
            get: {
                guard let wf = workflow, index < wf.steps.count else {
                    return WorkflowStep(type: .llm, config: .llm(LLMStepConfig(provider: .gemini, prompt: "")), outputKey: "")
                }
                return wf.steps[index]
            },
            set: { newValue in
                workflow?.steps[index] = newValue
            }
        )
    }

    private func addStep(of type: WorkflowStep.StepType) {
        let stepCount = workflow?.steps.count ?? 0
        let newStep = WorkflowStep(
            type: type,
            config: StepConfig.defaultConfig(for: type),
            outputKey: "output_\(stepCount + 1)"
        )
        workflow?.steps.append(newStep)
    }

    private func deleteStep(at index: Int) {
        workflow?.steps.remove(at: index)
    }

    private func moveStep(from source: Int, to destination: Int) {
        guard var wf = workflow else { return }
        let step = wf.steps.remove(at: source)
        wf.steps.insert(step, at: destination)
        workflow = wf
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

                        TextField("Workflow Name", text: $editedWorkflow.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        TextField("Description", text: $editedWorkflow.description)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

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
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Text("\(stepNumber)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .cornerRadius(6)

                Image(systemName: step.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)

                Text(step.type.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                Spacer()

                // Reorder buttons
                if let moveUp = onMoveUp {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                if let moveDown = onMoveDown {
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()

                // Step-specific fields
                stepConfigEditor
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var stepConfigEditor: some View {
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
        }

        // Output key (common to all steps)
        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("OUTPUT KEY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.secondary)

            TextField("Key name for storing output", text: $step.outputKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

            Text("Use {{" + step.outputKey + "}} in subsequent steps")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
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
        if config.provider == .mlx {
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
        return config.provider.models
    }

    // Validated model ID - ensures selection is always valid
    private var validatedModelId: String {
        let models = availableModels
        // If current modelId is in available models, use it
        if models.contains(where: { $0.id == config.modelId }) {
            return config.modelId
        }
        // Otherwise return first available model's ID, or empty string
        return models.first?.id ?? ""
    }

    // Check if current provider is local
    private var isLocalProvider: Bool {
        config.provider == .mlx
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
                        get: { config.provider },
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
