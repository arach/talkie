//
//  AuditRunsListView.swift
//  Talkie macOS
//
//  Runs list for Design System Audit - left pane in master-detail view
//  Shows all previous audit runs with date, branch, grade at a glance
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import TalkieKit

#if DEBUG

struct AuditRunsListView: View {
    @Binding var selectedRunNumber: Int?
    let availableRuns: [DesignAuditor.AuditRunInfo]
    let isRunningAudit: Bool
    let includeScreenshots: Bool
    let onToggleScreenshots: () -> Void
    let onRunAudit: () -> Void
    var onViewLogs: ((Int) -> Void)? = nil  // Optional callback to view logs for a run

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if availableRuns.isEmpty {
                emptyState
            } else {
                runsList
            }
        }
        .background(Theme.current.background)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Audit Runs")
                    .font(Theme.current.fontTitle)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                // Screenshots toggle
                Toggle(isOn: Binding(
                    get: { includeScreenshots },
                    set: { _ in onToggleScreenshots() }
                )) {
                    Image(systemName: "camera")
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(includeScreenshots ? "Screenshots enabled" : "Screenshots disabled (faster)")

                // New Audit button
                Button(action: onRunAudit) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("New")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(TalkieTheme.accent.opacity(Opacity.light))
                    .foregroundColor(TalkieTheme.accent)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
                .disabled(isRunningAudit)
            }

            Text("\(availableRuns.count) runs")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(Spacing.md)
    }

    // MARK: - Runs List

    @ViewBuilder
    private var runsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(availableRuns) { run in
                    runRow(run)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
    }

    @ViewBuilder
    private func runRow(_ run: DesignAuditor.AuditRunInfo) -> some View {
        let isSelected = selectedRunNumber == run.id

        Button(action: {
            selectedRunNumber = run.id
        }) {
            HStack(spacing: Spacing.sm) {
                // Grade badge
                Text(run.grade)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(gradeColor(run.grade))
                    .frame(width: 24, height: 24)
                    .background(gradeColor(run.grade).opacity(Opacity.light))
                    .cornerRadius(4)

                // Run info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text("Run \(run.id)")
                            .font(Theme.current.fontSMBold)
                            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                        if let branch = run.gitBranch {
                            Text("•")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(branch)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(relativeDate(run.timestamp))
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if run.totalIssues > 0 {
                            Text("•")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text("\(run.totalIssues) issues")
                                .font(Theme.current.fontXS)
                                .foregroundColor(SemanticColor.warning)
                        }
                    }
                }

                Spacer()

                // Score
                Text("\(run.overallScore)%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Theme.current.surface2 : Color.clear)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                selectedRunNumber = run.id
            } label: {
                Label("View Details", systemImage: "doc.text")
            }

            if let onViewLogs = onViewLogs {
                Button {
                    onViewLogs(run.id)
                } label: {
                    Label("View Logs", systemImage: "terminal")
                }
            }

            Divider()

            Button {
                // Open screenshot folder
                let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Talkie/DesignAudit/run-\(run.id)/screenshots")
                if FileManager.default.fileExists(atPath: path.path) {
                    NSWorkspace.shared.open(path)
                }
            } label: {
                Label("Open Screenshots Folder", systemImage: "folder")
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No audit runs yet")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Click 'New' to run your first design system audit")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Spacing.xl)
    }

    // MARK: - Helpers

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return SemanticColor.success
        case "B": return Color.green.opacity(0.7)
        case "C": return SemanticColor.warning
        case "D": return Color.orange
        default: return SemanticColor.error
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#endif
