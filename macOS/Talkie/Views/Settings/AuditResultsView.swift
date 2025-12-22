//
//  AuditResultsView.swift
//  Talkie
//
//  Display detailed external data audit results
//

import SwiftUI

struct AuditResultsView: View {
    let results: ExternalDataAuditor.AuditResults
    @Environment(\.dismiss) private var dismiss

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
                        .foregroundColor(.secondary)
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
                    // Summary
                    summarySection

                    Divider()

                    // CoreData Details
                    storageSection(
                        title: "CoreData External Storage",
                        location: "~/Library/Application Support/Talkie/.talkie_SUPPORT/_EXTERNAL_DATA/",
                        totalFiles: results.coreDataExternalFiles.count,
                        referencedFiles: results.coreDataReferencedUUIDs.count,
                        orphanedFiles: results.coreDataOrphanedFiles,
                        missingFiles: results.coreDataMissingFiles,
                        storageSize: results.coreDataStorageBytes
                    )

                    Divider()

                    // GRDB Details
                    storageSection(
                        title: "GRDB Audio Storage",
                        location: "~/Library/Application Support/Talkie/Audio/",
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
        .frame(width: 700, height: 600)
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
                .foregroundColor(.secondary)

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
        totalFiles: Int,
        referencedFiles: Int,
        orphanedFiles: Set<String>,
        missingFiles: Set<String>,
        storageSize: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                AuditInfoRow(label: "Location", value: location)
                AuditInfoRow(label: "Total Files", value: "\(totalFiles)")
                AuditInfoRow(label: "Referenced in DB", value: "\(referencedFiles)")
                AuditInfoRow(
                    label: "Orphaned Files",
                    value: "\(orphanedFiles.count)",
                    valueColor: orphanedFiles.isEmpty ? .green : .orange
                )
                AuditInfoRow(
                    label: "Missing Files",
                    value: "\(missingFiles.count)",
                    valueColor: missingFiles.isEmpty ? .green : .red
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
                    title: "Orphaned Files (\(orphanedFiles.count))",
                    files: orphanedFiles,
                    icon: "doc.badge.ellipsis",
                    color: .orange
                )
            }

            // Show missing files
            if !missingFiles.isEmpty {
                fileListSection(
                    title: "Missing Files (\(missingFiles.count))",
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
                            .foregroundColor(.secondary)
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

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

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
        )
    )
}
#endif
