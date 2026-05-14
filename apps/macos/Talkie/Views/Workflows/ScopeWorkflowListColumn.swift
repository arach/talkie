//
//  ScopeWorkflowListColumn.swift
//  Talkie macOS
//
//  Scope-flavored workflows list: instrument-panel chrome on a narrow
//  middle column. Hero with eyebrow + serif title at top, channel-tag
//  rows below. Replaces WorkflowListColumn when isScopeTheme.
//

import SwiftUI
import TalkieKit
import WFKit

struct ScopeWorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?

    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared

    @State private var showingTemplatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            heroHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(workflowService.workflows.enumerated()), id: \.element.id) { idx, registered in
                        ScopeWorkflowRow(
                            index: idx,
                            workflow: registered.definition,
                            isSelected: selectedWorkflowID == registered.id,
                            isSystem: registered.isSystem,
                            onSelect: { selectWorkflow(registered) }
                        )
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ScopeCanvas.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(width: 1)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            WorkflowTemplatePicker(
                templates: fileRepo.loadTemplates(),
                onSelectBlank: {
                    createNewWorkflow(from: nil)
                    showingTemplatePicker = false
                },
                onSelectTemplate: { template in
                    createNewWorkflow(from: template)
                    showingTemplatePicker = false
                },
                onCancel: {
                    showingTemplatePicker = false
                }
            )
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Workflows")
                Spacer()
                Text("\(workflowService.workflows.count) ON FILE")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice")
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(ScopeInk.primary)
                        .tracking(-0.6)
                    HStack(spacing: 6) {
                        Text("→")
                            .font(ScopeType.eyebrow)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeAmber.solid)
                        Text("output")
                            .font(.system(size: 32, weight: .regular, design: .serif))
                            .foregroundStyle(ScopeInk.muted)
                            .tracking(-0.6)
                            .italic()
                    }
                }

                Spacer()

                Button(action: { showingTemplatePicker = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScopeAmber.solid)
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ScopeEdge.normal, lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ScopeAmber.tintSubtle)
                        )
                }
                .buttonStyle(.plain)
                .help("New workflow")
            }

            Text("CAPTURE · TRANSFORM · DELIVER")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.extraWide)
                .foregroundStyle(ScopeInk.subtle)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopeEdge.faint).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func selectWorkflow(_ registered: Workflow) {
        selectedWorkflowID = registered.id
        editingWorkflow = registered.definition
    }

    private func createNewWorkflow(from template: WorkflowDefinition?) {
        let newWorkflow: WorkflowDefinition
        if let template = template {
            newWorkflow = WorkflowDefinition(
                id: UUID(),
                name: template.name,
                description: template.description,
                icon: template.icon,
                color: template.color,
                steps: template.steps.map { step in
                    WorkflowStep(
                        id: UUID(),
                        type: step.type,
                        config: step.config,
                        outputKey: step.outputKey,
                        isEnabled: step.isEnabled,
                        condition: step.condition
                    )
                },
                isEnabled: true,
                isPinned: false,
                autoRun: false,
                autoRunOrder: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        } else {
            newWorkflow = WorkflowDefinition(
                name: "Untitled Workflow",
                description: ""
            )
        }
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }
}

// MARK: - Row

private struct ScopeWorkflowRow: View {
    let index: Int
    let workflow: WorkflowDefinition
    let isSelected: Bool
    let isSystem: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var channel: String {
        String(format: "WF-%02d", index + 1)
    }

    private var stepLabel: String {
        let n = workflow.steps.count
        return "\(n) STEP\(n == 1 ? "" : "S")"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    iconBadge

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workflow.name)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.dim)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(channel)
                                .font(ScopeType.chrome)
                                .tracking(ScopeType.Tracking.wide)
                                .foregroundStyle(ScopeInk.subtle)

                            Text("·")
                                .font(ScopeType.chrome)
                                .foregroundStyle(ScopeInk.subtle)

                            Text(stepLabel)
                                .font(ScopeType.chrome)
                                .tracking(ScopeType.Tracking.wide)
                                .foregroundStyle(ScopeInk.faint)

                            if workflow.isPinned {
                                Text("·")
                                    .font(ScopeType.chrome)
                                    .foregroundStyle(ScopeInk.subtle)
                                Text("PINNED")
                                    .font(ScopeType.chrome)
                                    .tracking(ScopeType.Tracking.wide)
                                    .foregroundStyle(ScopeAmber.solid)
                            }

                            if workflow.autoRun {
                                Text("·")
                                    .font(ScopeType.chrome)
                                    .foregroundStyle(ScopeInk.subtle)
                                Text("AUTO")
                                    .font(ScopeType.chrome)
                                    .tracking(ScopeType.Tracking.wide)
                                    .foregroundStyle(ScopeAmber.solid)
                            }

                            if !workflow.isEnabled {
                                Text("·")
                                    .font(ScopeType.chrome)
                                    .foregroundStyle(ScopeInk.subtle)
                                Text("DISABLED")
                                    .font(ScopeType.chrome)
                                    .tracking(ScopeType.Tracking.wide)
                                    .foregroundStyle(ScopeInk.subtle)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Step-type pipeline strip — visualizes the workflow
                // shape at a glance. Each tile is one step.
                if !workflow.steps.isEmpty {
                    pipelineStrip
                        .padding(.leading, 40)  // align under the title (past iconBadge)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    ScopeAmber.tintSubtle
                } else if isHovered {
                    ScopeCanvas.canvasOverlay
                }
            }
            .overlay(alignment: .leading) {
                if isSelected || isHovered {
                    Rectangle()
                        .fill(isSelected ? ScopeAmber.solid : ScopeAmber.solid.opacity(0.4))
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var pipelineStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(workflow.steps.prefix(8).enumerated()), id: \.offset) { _, step in
                stepTile(for: step)
            }
            if workflow.steps.count > 8 {
                Text("+\(workflow.steps.count - 8)")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopeInk.subtle)
                    .padding(.leading, 2)
            }
        }
    }

    private func stepTile(for step: WorkflowStep) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(ScopeCanvas.canvas)
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(ScopeEdge.normal, lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: step.type.icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(step.isEnabled ? ScopeInk.muted : ScopeInk.subtle)
            )
            .help(step.type.rawValue)
    }

    private var iconBadge: some View {
        let baseColor = workflow.color.color
        return RoundedRectangle(cornerRadius: 4)
            .fill(baseColor.opacity(isSelected ? 0.22 : 0.14))
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(baseColor.opacity(isSelected ? 0.45 : 0.25), lineWidth: 1)
            )
            .overlay(
                Image(systemName: workflow.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(baseColor)
            )
    }
}
