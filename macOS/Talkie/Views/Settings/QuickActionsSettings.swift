//
//  QuickActionsSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Quick Actions Settings View

struct QuickActionsSettingsView: View {
    private let workflowManager = WorkflowManager.shared
    @State private var selectedWorkflow: WorkflowDefinition?
    @State private var showingWorkflowEditor = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt",
                title: "QUICK ACTIONS",
                subtitle: "Pin workflows to show them as quick actions when viewing a memo. Pinned workflows sync to iOS via iCloud."
            )
        } content: {
            // MARK: - Pinned Workflows
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("PINNED WORKFLOWS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !pinnedWorkflows.isEmpty {
                        Text("\(pinnedWorkflows.count) PINNED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }

                if pinnedWorkflows.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "pin.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No workflows pinned")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(.primary)
                            Text("Pin workflows from the list below to show them as quick actions.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(pinnedWorkflows) { workflow in
                            workflowRow(workflow, isPinned: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Available Workflows
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("AVAILABLE WORKFLOWS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !unpinnedWorkflows.isEmpty {
                        Text("\(unpinnedWorkflows.count) AVAILABLE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                if unpinnedWorkflows.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("All workflows are pinned")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(.primary)
                            Text("All your workflows are showing as quick actions.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(unpinnedWorkflows) { workflow in
                            workflowRow(workflow, isPinned: false)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Info
            HStack(spacing: 8) {
                Image(systemName: "icloud")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.blue)

                Text("Pinned workflows sync to your iPhone via iCloud for quick access in the iOS app.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showingWorkflowEditor) {
            if let workflow = selectedWorkflow {
                WorkflowEditorSheet(
                    workflow: workflow,
                    isNew: false,
                    onSave: { updatedWorkflow in
                        workflowManager.updateWorkflow(updatedWorkflow)
                        showingWorkflowEditor = false
                    },
                    onCancel: {
                        showingWorkflowEditor = false
                    }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
    }

    private var pinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { $0.isPinned }
    }

    private var unpinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { !$0.isPinned }
    }

    @ViewBuilder
    private func workflowRow(_ workflow: WorkflowDefinition, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(.system(size: 14))
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(.primary)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            if !workflow.isEnabled {
                Text("DISABLED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(3)
            }

            // Edit button
            Button(action: { editWorkflow(workflow) }) {
                Image(systemName: "pencil")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.current.surface2)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Edit workflow")

            // Pin/unpin button
            TalkieButtonSync("TogglePin", section: "Settings") {
                togglePin(workflow)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(Theme.current.fontSM)
                    .foregroundColor(isPinned ? .orange : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isPinned ? Color.orange.opacity(0.15) : Theme.current.surface2)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin from quick actions" : "Pin to quick actions")
        }
        .padding(12)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }

    private func editWorkflow(_ workflow: WorkflowDefinition) {
        selectedWorkflow = workflow
        showingWorkflowEditor = true
    }

    private func togglePin(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.isPinned.toggle()
        updated.modifiedAt = Date()
        workflowManager.updateWorkflow(updated)
    }
}
