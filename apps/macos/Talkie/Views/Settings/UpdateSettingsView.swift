//
//  UpdateSettingsView.swift
//  Talkie
//
//  Settings section for checking and managing app updates.
//

import SwiftUI
import TalkieKit

struct UpdateSettingsView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var showingReleaseNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)

                Spacer()

                Toggle("Check automatically", isOn: $updateChecker.autoCheckEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            // Current version
            HStack {
                Text("Current version")
                    .foregroundColor(Theme.current.foregroundSecondary)
                Spacer()
                Text("\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)
            }

            // Update status
            if let update = updateChecker.availableUpdate {
                updateAvailableView(update)
            } else if updateChecker.isChecking {
                checkingView
            } else if let error = updateChecker.lastError {
                errorView(error)
            } else {
                upToDateView
            }

            // Check button
            HStack {
                if let lastChecked = updateChecker.lastChecked {
                    Text("Last checked: \(lastChecked, formatter: relativeDateFormatter)")
                        .font(.caption)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Button {
                    Task { await updateChecker.check() }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .disabled(updateChecker.isChecking)
            }
        }
        .padding()
        .sheet(isPresented: $showingReleaseNotes) {
            if let update = updateChecker.availableUpdate {
                ReleaseNotesSheet(update: update)
            }
        }
    }

    // MARK: - Subviews

    private func updateAvailableView(_ update: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundColor(.orange)
                Text("Update available: \(update.displayVersion)")
                    .fontWeight(.medium)
            }

            // Release notes preview
            if !update.releaseNotes.isEmpty {
                Text(update.releaseNotes.prefix(200) + (update.releaseNotes.count > 200 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: Spacing.sm) {
                Button("Download") {
                    updateChecker.downloadUpdate()
                }
                .buttonStyle(.borderedProminent)

                Button("View Release") {
                    showingReleaseNotes = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Skip") {
                    updateChecker.skipCurrentUpdate()
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding()
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }

    private var checkingView: some View {
        HStack {
            BrailleSpinner(size: 12)
            Text("Checking for updates...")
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private var upToDateView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("You're up to date")
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }
}

// MARK: - Release Notes Sheet

private struct ReleaseNotesSheet: View {
    let update: AppUpdateInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Version \(update.displayVersion)")
                        .font(.title2.bold())
                    Text("Released \(update.publishedAt, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Release notes (markdown)
            ScrollView {
                Text(try! AttributedString(markdown: update.releaseNotes))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("View on GitHub") {
                    NSWorkspace.shared.open(update.htmlURL)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Download") {
                    UpdateChecker.shared.downloadUpdate()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Update Available") {
    UpdateSettingsView()
        .frame(width: 400)
        .padding()
}
#endif
