//
//  WorkflowImportView.swift
//  Talkie
//
//  UI for importing a workflow from a URL.
//  Simple: paste URL, optionally enter passphrase, connect.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct WorkflowImportView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String = ""
    @State private var passphrase: String = ""
    @State private var needsPassphrase: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var importedWorkflow: WorkflowDefinition?

    var body: some View {
        VStack(spacing: 24) {
            header
            urlInput
            if needsPassphrase {
                passphraseInput
            }
            if let error = error {
                errorView(error)
            }
            if let workflow = importedWorkflow {
                successView(workflow)
            } else {
                actionButton
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: needsPassphrase ? 340 : 280)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Import Workflow")
                .font(.title2.bold())

            Text("Paste a URL to import a workflow with credentials")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - URL Input

    private var urlInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import URL")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("https://tawkie.dev/import/...", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading || importedWorkflow != nil)
                .onChange(of: urlString) { _, newValue in
                    error = nil
                    checkIfNeedsPassphrase(url: newValue)
                }
        }
    }

    // MARK: - Passphrase Input

    private var passphraseInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Passphrase")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("Enter passphrase from setup", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading || importedWorkflow != nil)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Success View

    private func successView(_ workflow: WorkflowDefinition) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("Connected!")
                        .font(.headline)
                    Text(workflow.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: importWorkflow) {
            if isLoading {
                BrailleSpinner()
            } else {
                Label("Connect", systemImage: "arrow.down.circle")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(urlString.isEmpty || isLoading || (needsPassphrase && passphrase.isEmpty))
    }

    // MARK: - Actions

    private func checkIfNeedsPassphrase(url: String) {
        guard !url.isEmpty, URL(string: url) != nil else {
            needsPassphrase = false
            return
        }

        Task {
            do {
                let needs = try await WorkflowImportService.shared.requiresPassphrase(urlString: url)
                await MainActor.run {
                    withAnimation {
                        needsPassphrase = needs
                    }
                }
            } catch {
                // Ignore - will show error on import attempt
            }
        }
    }

    private func importWorkflow() {
        guard !urlString.isEmpty else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let workflow = try await WorkflowImportService.shared.importWorkflow(
                    from: urlString,
                    passphrase: needsPassphrase ? passphrase : nil
                )

                // Save the workflow to imported/ directory
                try await WorkflowFileRepository.shared.save(workflow, source: .imported)

                await MainActor.run {
                    isLoading = false
                    importedWorkflow = workflow
                    log.info("Successfully imported workflow: \(workflow.name)")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = error.localizedDescription
                    log.error("Failed to import workflow: \(error)")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WorkflowImportView()
}
