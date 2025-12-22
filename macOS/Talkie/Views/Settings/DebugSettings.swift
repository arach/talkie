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

// MARK: - Debug Info View

struct DebugInfoView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var iCloudStatus: String = "Checking..."

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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("APP INFORMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Environment badge
                    Text(environment.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(environment == "Development" ? Color.orange : Color.green)
                        .cornerRadius(3)
                }

                VStack(spacing: 8) {
                    debugRow(label: "Bundle ID", value: bundleID, icon: "app.badge")
                    debugRow(label: "Version", value: "\(version) (\(build))", icon: "number")
                    debugRow(label: "Voice Memos", value: "\(allVoiceMemos.count)", icon: "doc.text")
                    debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo, icon: "arrow.triangle.2.circlepath")
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - iCloud Status
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("ICLOUD STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(spacing: 8) {
                    debugRow(label: "Account Status", value: iCloudStatus, icon: "icloud", valueColor: iCloudStatusColor)
                    debugRow(label: "Container", value: "iCloud.com.jdi.talkie", icon: "externaldrive.connected.to.line.below")
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Sync Status
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(syncStatusColor)
                        .frame(width: 3, height: 14)

                    Text("SYNC STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusText.uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(syncStatusColor)
                    }
                }

                HStack(spacing: 12) {
                    Text("Sync every")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.secondary)

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
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                Text("Manual sync is always available via the toolbar button. Lower intervals use more battery and network.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Onboarding
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("ONBOARDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup Wizard")
                            .font(Theme.current.fontSMMedium)
                        Text("Re-run the setup wizard to configure permissions, services, and models.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary)
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
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)
        }
        .onAppear {
            checkiCloudStatus()
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, icon: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.current.surface1)
        .cornerRadius(6)
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
