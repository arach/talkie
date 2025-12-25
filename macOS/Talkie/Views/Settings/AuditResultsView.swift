//
//  AuditResultsView.swift
//  Talkie
//
//  Display detailed external data audit results with actionable cleanup options
//

import SwiftUI

struct AuditResultsView: View {
    let results: ExternalDataAuditor.AuditResults
    let auditor: ExternalDataAuditor
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var deleteResult: (coreDataDeleted: Int, grdbDeleted: Int, bytesFreed: Int64)?
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("External Data Audit Report")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Generated: \(results.timestamp.formatted())")
                        .font(.caption)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary with explanation
                    summarySection

                    // Quick Actions (if issues found)
                    if results.hasIssues {
                        actionsSection
                    }

                    Divider()

                    // CoreData Details
                    storageSection(
                        title: "CoreData External Storage (Legacy)",
                        location: "~/Library/Application Support/Talkie/.talkie_SUPPORT/_EXTERNAL_DATA/",
                        explanation: "Audio blobs stored externally by CoreData. Being phased out in favor of GRDB.",
                        totalFiles: results.coreDataExternalFiles.count,
                        referencedFiles: results.coreDataReferencedUUIDs.count,
                        orphanedFiles: results.coreDataOrphanedFiles,
                        missingFiles: results.coreDataMissingFiles,
                        storageSize: results.coreDataStorageBytes
                    )

                    Divider()

                    // GRDB Details
                    storageSection(
                        title: "GRDB Audio Storage (Current)",
                        location: "~/Library/Application Support/Talkie/Audio/",
                        explanation: "Audio files managed by the new GRDB database layer.",
                        totalFiles: results.grdbAudioFiles.count,
                        referencedFiles: results.grdbReferencedFiles.count,
                        orphanedFiles: results.grdbOrphanedFiles,
                        missingFiles: results.grdbMissingFiles,
                        storageSize: results.grdbStorageBytes
                    )
                }
                .padding()
            }
        }
        .frame(width: 750, height: 700)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECOMMENDED ACTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)

            if deleteResult != nil {
                // Show success message
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Cleaned up \(deleteResult!.coreDataDeleted + deleteResult!.grdbDeleted) files, freed \(ByteCountFormatter.string(fromByteCount: deleteResult!.bytesFreed, countStyle: .file))")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else if let error = deleteError {
                // Show error message
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Error: \(error)")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else {
                // Show action buttons
                VStack(alignment: .leading, spacing: 12) {
                    // Orphaned files action
                    if !results.coreDataOrphanedFiles.isEmpty || !results.grdbOrphanedFiles.isEmpty {
                        actionCard(
                            icon: "trash.fill",
                            iconColor: .orange,
                            title: "Delete Orphaned Files",
                            description: "Remove \(results.coreDataOrphanedFiles.count + results.grdbOrphanedFiles.count) files that exist on disk but are not referenced in the database. These are safe to delete.",
                            buttonLabel: isDeleting ? "Deleting..." : "Delete Orphans",
                            isDestructive: true,
                            isLoading: isDeleting
                        ) {
                            deleteOrphanedFiles()
                        }
                    }

                    // Missing files info (no action, just informational)
                    if !results.coreDataMissingFiles.isEmpty || !results.grdbMissingFiles.isEmpty {
                        infoCard(
                            icon: "exclamationmark.circle.fill",
                            iconColor: .red,
                            title: "Missing Files Detected",
                            description: """
                            \(results.coreDataMissingFiles.count + results.grdbMissingFiles.count) database entries reference files that no longer exist. \
                            This may indicate data loss from a failed sync or crash. \
                            The memos will show "No audio available" when played.
                            """
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func actionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        buttonLabel: String,
        isDestructive: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(buttonLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? .orange : .blue)
                .disabled(isLoading)
            }
        }
        .padding()
        .background(iconColor.opacity(0.05))
        .cornerRadius(8)
    }

    private func infoCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(iconColor.opacity(0.05))
        .cornerRadius(8)
    }

    private func deleteOrphanedFiles() {
        isDeleting = true
        Task {
            do {
                let result = try await auditor.cleanupOrphanedFiles()
                await MainActor.run {
                    deleteResult = result
                    isDeleting = false
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    isDeleting = false
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.headline)

                Spacer()

                if results.hasIssues {
                    Label("Issues Found", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else {
                    Label("All Clear", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 20) {
                statBox(
                    title: "Total Files",
                    value: "\(results.coreDataExternalFiles.count + results.grdbAudioFiles.count)",
                    color: .blue
                )

                statBox(
                    title: "Orphaned Files",
                    value: "\(results.coreDataOrphanedFiles.count + results.grdbOrphanedFiles.count)",
                    color: results.hasIssues ? .orange : .green
                )

                statBox(
                    title: "Missing Files",
                    value: "\(results.coreDataMissingFiles.count + results.grdbMissingFiles.count)",
                    color: results.coreDataMissingFiles.isEmpty && results.grdbMissingFiles.isEmpty ? .green : .red
                )

                statBox(
                    title: "Total Storage",
                    value: ByteCountFormatter.string(fromByteCount: results.totalStorageBytes, countStyle: .file),
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func storageSection(
        title: String,
        location: String,
        explanation: String,
        totalFiles: Int,
        referencedFiles: Int,
        orphanedFiles: Set<String>,
        missingFiles: Set<String>,
        storageSize: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(explanation)
                    .font(.caption)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                AuditInfoRow(label: "Location", value: location)
                AuditInfoRow(label: "Total Files", value: "\(totalFiles)")
                AuditInfoRow(label: "Referenced in DB", value: "\(referencedFiles)")
                AuditInfoRow(
                    label: "Orphaned Files",
                    value: "\(orphanedFiles.count)",
                    valueColor: orphanedFiles.isEmpty ? .green : .orange,
                    helpText: "Files on disk not referenced by any memo"
                )
                AuditInfoRow(
                    label: "Missing Files",
                    value: "\(missingFiles.count)",
                    valueColor: missingFiles.isEmpty ? .green : .red,
                    helpText: "Database references files that don't exist"
                )
                AuditInfoRow(
                    label: "Storage Size",
                    value: ByteCountFormatter.string(fromByteCount: storageSize, countStyle: .file)
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)

            // Show orphaned files
            if !orphanedFiles.isEmpty {
                fileListSection(
                    title: "Orphaned Files (\(orphanedFiles.count)) — Safe to delete",
                    files: orphanedFiles,
                    icon: "doc.badge.ellipsis",
                    color: .orange
                )
            }

            // Show missing files
            if !missingFiles.isEmpty {
                fileListSection(
                    title: "Missing Files (\(missingFiles.count)) — Data loss",
                    files: missingFiles,
                    icon: "exclamationmark.circle",
                    color: .red
                )
            }
        }
    }

    private func fileListSection(title: String, files: Set<String>, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(color)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(files).sorted(), id: \.self) { filename in
                        Text(filename)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(color.opacity(0.05))
            .cornerRadius(4)
        }
    }
}

private struct AuditInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var helpText: String? = nil

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if let help = helpText {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                        .help(help)
                }
            }

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AuditResultsView(
        results: ExternalDataAuditor.AuditResults(
            timestamp: Date(),
            coreDataExternalFiles: Set(["file1.dat", "file2.dat", "file3.dat"]),
            coreDataReferencedUUIDs: Set(["file1.dat"]),
            coreDataOrphanedFiles: Set(["file2.dat", "file3.dat"]),
            coreDataMissingFiles: Set(["missing.dat"]),
            grdbAudioFiles: Set(["audio1.m4a", "audio2.m4a"]),
            grdbReferencedFiles: Set(["audio1.m4a", "audio2.m4a"]),
            grdbOrphanedFiles: Set(),
            grdbMissingFiles: Set(),
            totalStorageBytes: 1024 * 1024 * 100,
            coreDataStorageBytes: 1024 * 1024 * 60,
            grdbStorageBytes: 1024 * 1024 * 40
        ),
        auditor: ExternalDataAuditor()
    )
}
#endif
