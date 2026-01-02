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
    private let workflowService = WorkflowService.shared
    @State private var selectedWorkflow: Workflow?
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("PINNED WORKFLOWS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if !pinnedWorkflows.isEmpty {
                        Text("\(pinnedWorkflows.count) PINNED")
                            .font(.techLabelSmall)
                            .foregroundColor(.orange.opacity(Opacity.prominent))
                    }
                }

                if pinnedWorkflows.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "pin.slash")
                            .font(Theme.current.fontHeadline)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("No workflows pinned")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
                            Text("Pin workflows from the list below to show them as quick actions.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(pinnedWorkflows) { workflow in
                            workflowRow(workflow, isPinned: true)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Available Workflows
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("AVAILABLE WORKFLOWS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if !unpinnedWorkflows.isEmpty {
                        Text("\(unpinnedWorkflows.count) AVAILABLE")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                    }
                }

                if unpinnedWorkflows.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.current.fontHeadline)
                            .foregroundColor(SemanticColor.success)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("All workflows are pinned")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
                            Text("All your workflows are showing as quick actions.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(unpinnedWorkflows) { workflow in
                            workflowRow(workflow, isPinned: false)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Info
            HStack(spacing: Spacing.sm) {
                Image(systemName: "icloud")
                    .font(Theme.current.fontXS)
                    .foregroundColor(SemanticColor.pin)

                Text("Pinned workflows sync to your iPhone via iCloud for quick access in the iOS app.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .background(SemanticColor.pin.opacity(Opacity.light))
            .cornerRadius(CornerRadius.sm)
        }
        .sheet(isPresented: $showingWorkflowEditor) {
            if let workflow = selectedWorkflow {
                WorkflowEditorSheet(
                    workflow: workflow.definition,
                    isNew: false,
                    onSave: { updatedWorkflow in
                        Task {
                            try? await workflowService.save(updatedWorkflow)
                        }
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

    private var pinnedWorkflows: [Workflow] {
        workflowService.pinnedWorkflows
    }

    private var unpinnedWorkflows: [Workflow] {
        workflowService.workflows.filter { !$0.isPinned }
    }

    @ViewBuilder
    private func workflowRow(_ workflow: Workflow, isPinned: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: workflow.icon)
                .font(.headlineSmall)
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            // Name and description
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            if !workflow.isEnabled {
                Text("DISABLED")
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Theme.current.foregroundSecondary.opacity(Opacity.medium))
                    .cornerRadius(CornerRadius.xs)
            }

            // Edit button
            Button(action: { editWorkflow(workflow) }) {
                Image(systemName: "pencil")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
            .help("Edit workflow")

            // Pin/unpin button
            TalkieButtonSync("TogglePin", section: "Settings") {
                togglePin(workflow)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(Theme.current.fontSM)
                    .foregroundColor(isPinned ? SemanticColor.warning : Theme.current.foregroundSecondary)
                    .frame(width: 28, height: 28)
                    .background(isPinned ? SemanticColor.warning.opacity(Opacity.medium) : Theme.current.surface2)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin from quick actions" : "Pin to quick actions")
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func editWorkflow(_ workflow: Workflow) {
        selectedWorkflow = workflow
        showingWorkflowEditor = true
    }

    private func togglePin(_ workflow: Workflow) {
        Task {
            try? await workflowService.setPinned(!workflow.isPinned, for: workflow.id)
        }
    }
}
