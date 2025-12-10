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
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @State private var iCloudStatus: String = "Checking..."

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
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "DEBUG INFO",
                subtitle: "Diagnostic information about the app environment."
            )
        } content: {
            Divider()

            // Info rows
            VStack(spacing: 12) {
                debugRow(label: "Environment", value: environment, valueColor: environment == "Development" ? .orange : .green)
                debugRow(label: "iCloud Status", value: iCloudStatus)
                debugRow(label: "CloudKit Container", value: "iCloud.com.jdi.talkie")
                debugRow(label: "Bundle ID", value: bundleID)
                debugRow(label: "Version", value: "\(version) (\(build))")
                debugRow(label: "Voice Memos", value: "\(allVoiceMemos.count)")
                debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo)
            }

            Divider()

            // Sync status section
            VStack(alignment: .leading, spacing: 12) {
                Text("SYNC STATUS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(syncStatusColor)
                        .frame(width: 8, height: 8)
                    Text(syncStatusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
        }
        .onAppear {
            checkiCloudStatus()
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(valueColor)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.current.surface2)
        .cornerRadius(6)
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

