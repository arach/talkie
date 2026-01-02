//
//  AutoRunSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Automations Settings View

struct AutomationsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private let workflowService = WorkflowService.shared
    @State private var selectedWorkflowId: UUID?

    private var autoRunWorkflows: [Workflow] {
        workflowService.autoRunWorkflows
    }

    private var availableWorkflows: [Workflow] {
        workflowService.workflows.filter { !$0.autoRun }
    }

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt.circle",
                title: "AUTOMATIONS",
                subtitle: "Configure workflows that run automatically when memos sync."
            )
        } content: {
            // MARK: - Master Toggle Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.autoRunWorkflowsEnabled ? Color.green : Theme.current.foregroundSecondary)
                        .frame(width: 3, height: 14)

                    Text("AUTOMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(settingsManager.autoRunWorkflowsEnabled ? Color.green : Theme.current.foregroundSecondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.autoRunWorkflowsEnabled ? "ENABLED" : "DISABLED")
                            .font(.techLabelSmall)
                            .foregroundColor(settingsManager.autoRunWorkflowsEnabled ? .green : Theme.current.foregroundSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(settingsManager.autoRunWorkflowsEnabled ? .green : Theme.current.foregroundSecondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Enable Automations")
                            .font(Theme.current.fontSMMedium)
                        Text("Workflows marked for automation will execute automatically when new memos sync from your iPhone.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.autoRunWorkflowsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            if settingsManager.autoRunWorkflowsEnabled {
                // MARK: - Auto-run Workflows Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.purple)
                            .frame(width: 3, height: 14)

                        Text("AUTOMATION WORKFLOWS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        if !autoRunWorkflows.isEmpty {
                            Text("\(autoRunWorkflows.count) ACTIVE")
                                .font(.techLabelSmall)
                                .foregroundColor(.purple.opacity(Opacity.prominent))
                        }

                        if !availableWorkflows.isEmpty {
                            Menu {
                                ForEach(availableWorkflows) { workflow in
                                    Button(action: { enableAutoRun(workflow) }) {
                                        Label(workflow.name, systemImage: workflow.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(Theme.current.fontXSMedium)
                            }
                        }
                    }

                    if autoRunWorkflows.isEmpty {
                        // Default Hey Talkie workflow info
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "waveform.badge.mic")
                                    .font(Theme.current.fontHeadline)
                                    .foregroundColor(.purple)
                                    .frame(width: 32, height: 32)
                                    .background(Color.purple.opacity(Opacity.medium))
                                    .cornerRadius(CornerRadius.xs)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("Hey Talkie (Default)")
                                        .font(Theme.current.fontSMMedium)
                                    Text("Detects \"Hey Talkie\" voice commands and routes to workflows")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                Spacer()

                                Text("ACTIVE")
                                    .font(.techLabelSmall)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(SemanticColor.success.opacity(Opacity.medium))
                                    .foregroundColor(SemanticColor.success)
                                    .cornerRadius(CornerRadius.xs)
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)

                            Text("The default Hey Talkie workflow runs automatically. Add your own workflows to customize.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    } else {
                        VStack(spacing: Spacing.sm) {
                            ForEach(autoRunWorkflows) { workflow in
                                AutoRunWorkflowRow(
                                    workflow: workflow,
                                    onDisable: { disableAutoRun(workflow) },
                                    onMoveUp: autoRunWorkflows.first?.id == workflow.id ? nil : { moveWorkflowUp(workflow) },
                                    onMoveDown: autoRunWorkflows.last?.id == workflow.id ? nil : { moveWorkflowDown(workflow) }
                                )
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

                // MARK: - How It Works Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.cyan)
                            .frame(width: 3, height: 14)

                        Text("HOW IT WORKS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        howItWorksRow(number: "1", text: "Record a memo on iPhone")
                        howItWorksRow(number: "2", text: "Memo syncs to Mac via iCloud")
                        howItWorksRow(number: "3", text: "Automation workflows execute in order")
                        howItWorksRow(number: "4", text: "Workflows with trigger steps gate themselves (e.g., \"Hey Talkie\")")
                        howItWorksRow(number: "5", text: "Universal workflows (like indexers) run on all memos")
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
                .padding(Spacing.md)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    private func howItWorksRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(number)
                .font(.techLabel)
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)
                .background(Color.accentColor.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.sm)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func enableAutoRun(_ workflow: Workflow) {
        let nextOrder = (autoRunWorkflows.map { $0.autoRunOrder }.max() ?? -1) + 1
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: nextOrder)
        }
    }

    private func disableAutoRun(_ workflow: Workflow) {
        Task {
            try? await workflowService.setAutoRun(false, for: workflow.id, order: 0)
        }
    }

    private func moveWorkflowUp(_ workflow: Workflow) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index > 0 else { return }
        let previous = autoRunWorkflows[index - 1]

        let tempOrder = workflow.autoRunOrder
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: previous.autoRunOrder)
            try? await workflowService.setAutoRun(true, for: previous.id, order: tempOrder)
        }
    }

    private func moveWorkflowDown(_ workflow: Workflow) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index < autoRunWorkflows.count - 1 else { return }
        let next = autoRunWorkflows[index + 1]

        let tempOrder = workflow.autoRunOrder
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: next.autoRunOrder)
            try? await workflowService.setAutoRun(true, for: next.id, order: tempOrder)
        }
    }
}

struct AutoRunWorkflowRow: View {
    let workflow: Workflow
    let onDisable: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Reorder buttons
            VStack(spacing: Spacing.xs) {
                if let moveUp = onMoveUp {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
                if let moveDown = onMoveDown {
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .frame(width: 16)

            // Workflow icon
            Image(systemName: workflow.icon)
                .font(Theme.current.fontBody)
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            // Workflow info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontSMBold)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if workflow.isEnabled {
                Text("ACTIVE")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(SemanticColor.success.opacity(Opacity.medium))
                    .foregroundColor(SemanticColor.success)
                    .cornerRadius(CornerRadius.xs)
            } else {
                Text("DISABLED")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.foregroundSecondary.opacity(Opacity.medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .cornerRadius(CornerRadius.xs)
            }

            // Remove button
            Button(action: onDisable) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove from automations")
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }
}
