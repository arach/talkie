//
//  DebugSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os
import CloudKit
import CoreData

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Design Exploration Window

struct DesignExplorationWindow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MemoRowExplorationPreview()
            .frame(minWidth: 900, minHeight: 700)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var iCloudStatus: String = "Checking..."
    @State private var showDesignExploration = false

    private let syncIntervalOptions = [1, 5, 10, 15, 30, 60]

    private var environment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        @Bindable var settings = settingsManager

        return SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "DEBUG INFO",
                subtitle: "Diagnostic information about the app environment."
            )
        } content: {
            // MARK: - App Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("APP INFORMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    // Environment badge
                    Text(environment.uppercased())
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(environment == "Development" ? Color.orange : Color.green)
                        .cornerRadius(CornerRadius.xs)
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Bundle ID", value: bundleID, icon: "app.badge")
                    debugRow(label: "Version", value: "\(version) (\(build))", icon: "number")
                    debugRow(label: "Voice Memos", value: "\(allVoiceMemos.count)", icon: "doc.text")
                    debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo, icon: "arrow.triangle.2.circlepath")
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - iCloud Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("ICLOUD STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Account Status", value: iCloudStatus, icon: "icloud", valueColor: iCloudStatusColor)
                    debugRow(label: "Container", value: "iCloud.com.jdi.talkie", icon: "externaldrive.connected.to.line.below")
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Sync Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(syncStatusColor)
                        .frame(width: 3, height: 14)

                    Text("SYNC STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusText.uppercased())
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(syncStatusColor)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Text("Sync every")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: $settings.syncIntervalMinutes) {
                        ForEach(syncIntervalOptions, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                Text("Manual sync is always available via the toolbar button. Lower intervals use more battery and network.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Onboarding
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("ONBOARDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Setup Wizard")
                            .font(Theme.current.fontSMMedium)
                        Text("Re-run the setup wizard to configure permissions, services, and models.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button(action: {
                        OnboardingManager.shared.resetOnboarding()
                    }) {
                        Text("RESTART")
                            .font(Theme.current.fontXSBold)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Design System
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("DESIGN SYSTEM")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "paintpalette")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.cyan)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Design Exploration")
                            .font(Theme.current.fontSMMedium)
                        Text("Interactive before/after comparison with grid overlay and highlight modes.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button(action: {
                        showDesignExploration = true
                    }) {
                        Text("OPEN")
                            .font(Theme.current.fontXSBold)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                Text("Press G for grid, H for hierarchy, F for fonts, S for spacing, C to toggle views.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)
        }
        .sheet(isPresented: $showDesignExploration) {
            DesignExplorationWindow()
        }
        .onAppear {
            checkiCloudStatus()
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, icon: String, valueColor: Color = Theme.current.foreground) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 16)

            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }

    private var iCloudStatusColor: Color {
        switch iCloudStatus {
        case "Available": return .green
        case "Checking...": return .secondary
        default: return .orange
        }
    }

    private var syncStatusColor: Color {
        switch SyncStatusManager.shared.state {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }

    private var syncStatusText: String {
        switch SyncStatusManager.shared.state {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func checkiCloudStatus() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    iCloudStatus = "Error: \(error.localizedDescription)"
                    return
                }

                switch status {
                case .available:
                    iCloudStatus = "Available"
                case .noAccount:
                    iCloudStatus = "No Account"
                case .restricted:
                    iCloudStatus = "Restricted"
                case .couldNotDetermine:
                    iCloudStatus = "Could Not Determine"
                case .temporarilyUnavailable:
                    iCloudStatus = "Temporarily Unavailable"
                @unknown default:
                    iCloudStatus = "Unknown"
                }
            }
        }
    }
}
