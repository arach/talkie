//
//  WorkflowListView.swift
//  Talkie
//
//  Lists and manages imported workflows (connected Claws).
//

import SwiftUI
import TalkieKit

struct WorkflowListView: View {

    @State private var workflows: [WorkflowDefinition] = []
    @State private var showImportSheet: Bool = false

    var body: some View {
        List {
            Section {
                if workflows.isEmpty {
                    emptyState
                } else {
                    ForEach(workflows) { workflow in
                        ImportedWorkflowRow(
                            workflow: workflow,
                            onDelete: { delete(workflow) }
                        )
                    }
                }
            } header: {
                Text("Connected Claws")
            } footer: {
                Text("Workflows imported from external URLs. Used for 'Send to Claw' actions.")
            }

            Section {
                Button(action: { showImportSheet = true }) {
                    Label("Import Workflow", systemImage: "link.badge.plus")
                }
            }
        }
        .onAppear(perform: loadWorkflows)
        .sheet(isPresented: $showImportSheet) {
            WorkflowImportView()
                .onDisappear(perform: loadWorkflows)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No workflows connected")
                .font(.headline)
            Text("Import a workflow from tawkie.dev or another source")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Actions

    private func loadWorkflows() {
        Task {
            // Load only imported workflows from the repository
            let allWorkflows = await WorkflowFileRepository.shared.loadedWorkflows
            workflows = allWorkflows.filter { $0.definition.source.isImported }.map { $0.definition }
        }
    }

    private func delete(_ workflow: WorkflowDefinition) {
        Task {
            guard let loadedWorkflow = await WorkflowFileRepository.shared.workflow(byID: workflow.id) else { return }
            try? await WorkflowFileRepository.shared.delete(loadedWorkflow)
            // Also delete associated credentials
            if case .imported(let metadata) = workflow.source {
                // Credentials are stored with IDs from the steps
                for step in workflow.steps {
                    if case .cloudUpload(let config) = step.config, let credId = config.credentialId {
                        try? await CredentialStore.shared.delete(id: credId)
                    }
                    if case .webhook(let config) = step.config, let auth = config.auth {
                        try? await CredentialStore.shared.delete(id: auth.credentialId)
                    }
                }
            }
            loadWorkflows()
        }
    }
}

// MARK: - Imported Workflow Row

struct ImportedWorkflowRow: View {

    let workflow: WorkflowDefinition
    let onDelete: () -> Void

    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.headline)
                Text(workflow.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let metadata = workflow.source.importMetadata {
                    Text("Imported \(metadata.importedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Step type badges
            HStack(spacing: 4) {
                ForEach(uniqueStepTypes, id: \.self) { type in
                    StepTypeBadge(type: type)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog("Delete Workflow?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove '\(workflow.name)' and its stored credentials.")
        }
    }

    private var uniqueStepTypes: [WorkflowStep.StepType] {
        Array(Set(workflow.steps.map { $0.type }))
    }
}

// MARK: - Step Type Badge

struct StepTypeBadge: View {
    let type: WorkflowStep.StepType

    var body: some View {
        Text(type.displayName.uppercased())
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(3)
    }
}

// MARK: - Provider Badge

// MARK: - Preview

#Preview {
    WorkflowListView()
        .frame(width: 500, height: 400)
}
