//
//  AutoRunSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Auto-Run Settings View

struct AutoRunSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private let workflowManager = WorkflowManager.shared
    @State private var selectedWorkflowId: UUID?

    private var autoRunWorkflows: [WorkflowDefinition] {
        workflowManager.workflows
            .filter { $0.autoRun }
            .sorted { $0.autoRunOrder < $1.autoRunOrder }
    }

    private var availableWorkflows: [WorkflowDefinition] {
        workflowManager.workflows
            .filter { !$0.autoRun }
    }

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt.circle",
                title: "AUTO-RUN",
                subtitle: "Configure workflows that run automatically when memos sync."
            )
        } content: {
            // Master toggle
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.autoRunWorkflowsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Auto-Run Workflows")
                                .font(Theme.current.fontSMBold)
                            Text("When enabled, workflows marked as auto-run will execute automatically when new memos sync from your iPhone.")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(16)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                if settingsManager.autoRunWorkflowsEnabled {
                    Divider()

                    // Auto-run workflows list
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AUTO-RUN WORKFLOWS")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(.secondary)

                            Spacer()

                            if !availableWorkflows.isEmpty {
                                Menu {
                                    ForEach(availableWorkflows) { workflow in
                                        Button(action: { enableAutoRun(workflow) }) {
                                            Label(workflow.name, systemImage: workflow.icon)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("Add")
                                    }
                                    .font(Theme.current.fontXSMedium)
                                }
                            }
                        }

                        if autoRunWorkflows.isEmpty {
                            // Default Hey Talkie workflow info
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform.badge.mic")
                                        .font(.system(size: 16))
                                        .foregroundColor(.purple)
                                        .frame(width: 32, height: 32)
                                        .background(Color.purple.opacity(0.15))
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Hey Talkie (Default)")
                                            .font(Theme.current.fontSMBold)
                                        Text("Detects \"Hey Talkie\" voice commands and routes to workflows")
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                                .padding(12)
                                .background(Theme.current.surface1)
                                .cornerRadius(8)

                                Text("The default Hey Talkie workflow runs automatically. Add your own workflows to customize.")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }
                        } else {
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

                    Divider()

                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HOW IT WORKS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            howItWorksRow(number: "1", text: "Record a memo on iPhone")
                            howItWorksRow(number: "2", text: "Memo syncs to Mac via iCloud")
                            howItWorksRow(number: "3", text: "Auto-run workflows execute in order")
                            howItWorksRow(number: "4", text: "Workflows with trigger steps gate themselves (e.g., \"Hey Talkie\")")
                            howItWorksRow(number: "5", text: "Universal workflows (like indexers) run on all memos")
                        }
                        .padding(12)
                        .background(Theme.current.surface1)
                        .cornerRadius(8)
                    }
            }
        }
    }

    private func howItWorksRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(8)

            Text(text)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        }
    }

    private func enableAutoRun(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.autoRun = true
        updated.autoRunOrder = (autoRunWorkflows.map { $0.autoRunOrder }.max() ?? -1) + 1
        workflowManager.updateWorkflow(updated)
    }

    private func disableAutoRun(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.autoRun = false
        updated.autoRunOrder = 0
        workflowManager.updateWorkflow(updated)
    }

    private func moveWorkflowUp(_ workflow: WorkflowDefinition) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index > 0 else { return }
        let previous = autoRunWorkflows[index - 1]

        var updatedCurrent = workflow
        var updatedPrevious = previous
        let tempOrder = updatedCurrent.autoRunOrder
        updatedCurrent.autoRunOrder = updatedPrevious.autoRunOrder
        updatedPrevious.autoRunOrder = tempOrder

        workflowManager.updateWorkflow(updatedCurrent)
        workflowManager.updateWorkflow(updatedPrevious)
    }

    private func moveWorkflowDown(_ workflow: WorkflowDefinition) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index < autoRunWorkflows.count - 1 else { return }
        let next = autoRunWorkflows[index + 1]

        var updatedCurrent = workflow
        var updatedNext = next
        let tempOrder = updatedCurrent.autoRunOrder
        updatedCurrent.autoRunOrder = updatedNext.autoRunOrder
        updatedNext.autoRunOrder = tempOrder

        workflowManager.updateWorkflow(updatedCurrent)
        workflowManager.updateWorkflow(updatedNext)
    }
}

struct AutoRunWorkflowRow: View {
    let workflow: WorkflowDefinition
    let onDisable: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Reorder buttons
            VStack(spacing: 4) {
                if let moveUp = onMoveUp {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                if let moveDown = onMoveDown {
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .frame(width: 16)

            // Workflow icon
            Image(systemName: workflow.icon)
                .font(.system(size: 14))
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Workflow info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(Theme.current.fontSMBold)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if workflow.isEnabled {
                Text("ACTIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            } else {
                Text("DISABLED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)
            }

            // Remove button
            Button(action: onDisable) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from auto-run")
        }
        .padding(12)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }
}
