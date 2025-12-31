//
//  MigrationView.swift
//  Talkie
//
//  UI for migrating from Core Data to GRDB
//  One-time migration to preserve user's 200 memos
//

import SwiftUI
import CoreData

// MARK: - Migration View

struct MigrationView: View {
    @Environment(\.managedObjectContext) private var coreDataContext
    @Environment(\.dismiss) private var dismiss

    @State private var isMigrating = false
    @State private var migrationComplete = false
    @State private var successCount = 0
    @State private var failedCount = 0
    @State private var errors: [Error] = []
    @State private var coreDataCount = 0

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            VStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Database Migration")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text("Migrate your memos to the new high-performance database")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .multilineTextAlignment(.center)

                if coreDataCount > 0 {
                    Text("\(coreDataCount) memo\(coreDataCount == 1 ? "" : "s") to migrate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.top, 4)
                }
            }

            Divider()
                .background(Theme.current.border)

            if !migrationComplete {
                // Pre-migration info
                VStack(alignment: .leading, spacing: Spacing.md) {
                    MigrationInfoRow(
                        icon: "checkmark.shield",
                        title: "Safe Migration",
                        description: "Your original data will be preserved during migration"
                    )

                    MigrationInfoRow(
                        icon: "bolt.fill",
                        title: "Performance Boost",
                        description: "New database is 10-20x faster with proper indexing"
                    )

                    MigrationInfoRow(
                        icon: "doc.on.doc",
                        title: "All Data Included",
                        description: "Memos, transcripts, workflows, and audio files"
                    )
                }
                .padding(Spacing.md)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(Theme.current.border.opacity(0.5), lineWidth: 1)
                )

                Spacer()

                // Migration button
                if isMigrating {
                    VStack(spacing: Spacing.sm) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Migrating your memos...")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .frame(height: 60)
                } else {
                    Button(action: startMigration) {
                        Text("Start Migration")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .cornerRadius(CornerRadius.md)
                    }
                    .buttonStyle(.plain)

                    Button("Skip for Now") {
                        dismissMigration()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.top, 4)
                }

            } else {
                // Post-migration results
                VStack(spacing: Spacing.md) {
                    if failedCount == 0 {
                        // Success
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)

                        Text("Migration Complete!")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.current.foreground)

                        Text("Successfully migrated \(successCount) memos")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.current.foregroundSecondary)

                    } else {
                        // Partial success
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.orange)

                        Text("Migration Completed with Warnings")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.current.foreground)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(successCount) migrated", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.green)

                            Label("\(failedCount) failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        }

                        if !errors.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(0..<min(errors.count, 5), id: \.self) { index in
                                        Text("• \(errors[index].localizedDescription)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                    }
                                }
                            }
                            .frame(maxHeight: 100)
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)
                        }
                    }

                    Spacer()

                    Button("Continue to App") {
                        dismissMigration()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(CornerRadius.md)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 500, height: 600)
        .background(Theme.current.surfaceBase)
        .onAppear {
            countCoreDataMemos()
        }
    }

    private func countCoreDataMemos() {
        let fetchRequest = NSFetchRequest<NSNumber>(entityName: "VoiceMemo")
        fetchRequest.resultType = .countResultType
        do {
            let results = try coreDataContext.fetch(fetchRequest)
            coreDataCount = results.first?.intValue ?? 0
        } catch {
            coreDataCount = 0
        }
    }

    // MARK: - Actions

    private func startMigration() {
        isMigrating = true

        Task {
            let migration = CoreDataMigration(coreDataContext: coreDataContext)
            let result = await migration.migrate()

            await MainActor.run {
                successCount = result.success
                failedCount = result.failed
                errors = result.errors
                isMigrating = false
                migrationComplete = true
            }
        }
    }

    private func dismissMigration() {
        // Mark migration as complete in UserDefaults
        UserDefaults.standard.set(true, forKey: "grdb_migration_complete")

        print("✅ [Migration] Marked complete, reloading app...")

        // Post notification to reload app
        NotificationCenter.default.post(name: NSNotification.Name("MigrationCompleted"), object: nil)

        // Dismiss this view
        dismiss()
    }
}

// MARK: - Migration Info Row

private struct MigrationInfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MigrationView()
}
