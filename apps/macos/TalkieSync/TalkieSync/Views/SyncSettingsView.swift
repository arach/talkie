//
//  SyncSettingsView.swift
//  TalkieSync
//
//  Settings window for TalkieSync configuration.
//  Shows sync providers, intervals, and status.
//

import SwiftUI
import TalkieKit

struct SyncSettingsView: View {
    @State private var iCloudEnabled = true
    @State private var syncInterval: Double = 600 // 10 minutes

    private let intervalOptions: [(String, Double)] = [
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("30 minutes", 1800),
        ("1 hour", 3600),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providersSection
                    scheduleSection
                    statusSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("TalkieSync Settings")
                    .font(.headline)
                Text("Configure sync providers and schedule")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Environment badge
            Text(TalkieEnvironment.current.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(TalkieEnvironment.current == .production ? .green : .purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (TalkieEnvironment.current == .production ? Color.green : Color.purple)
                        .opacity(0.15)
                )
                .cornerRadius(4)
        }
        .padding(16)
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SYNC PROVIDERS", color: .blue)

            VStack(spacing: 8) {
                // iCloud Provider
                providerRow(
                    name: "iCloud",
                    icon: "icloud.fill",
                    description: "Direct CloudKit sync",
                    isEnabled: $iCloudEnabled,
                    status: .connected
                )

                // Future providers (disabled)
                providerRow(
                    name: "Amazon S3",
                    icon: "externaldrive.fill.badge.icloud",
                    description: "Coming soon",
                    isEnabled: .constant(false),
                    status: .notConfigured
                )

                providerRow(
                    name: "Dropbox",
                    icon: "shippingbox.fill",
                    description: "Coming soon",
                    isEnabled: .constant(false),
                    status: .notConfigured
                )
            }
        }
    }

    private func providerRow(
        name: String,
        icon: String,
        description: String,
        isEnabled: Binding<Bool>,
        status: ProviderStatus
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isEnabled.wrappedValue ? .blue : .secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: 4) {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                Text(status.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(status.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1))
            .cornerRadius(4)

            Toggle("", isOn: isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(status == .notConfigured)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SYNC SCHEDULE", color: .orange)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sync Interval")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $syncInterval) {
                    ForEach(intervalOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                .pickerStyle(.segmented)

                Text("Sync also runs automatically when network or power state changes.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("STATUS", color: .green)

            HStack(spacing: 16) {
                statusItem(label: "Last Sync", value: "2 minutes ago")
                Divider().frame(height: 30)
                statusItem(label: "Records Synced", value: "1,234")
                Divider().frame(height: 30)
                statusItem(label: "Pending", value: "0")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func statusItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 14)

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
        }
    }

    private enum ProviderStatus: Equatable {
        case connected
        case disconnected
        case notConfigured

        var label: String {
            switch self {
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            case .notConfigured: return "Not configured"
            }
        }

        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .red
            case .notConfigured: return .gray
            }
        }
    }
}

#Preview {
    SyncSettingsView()
}
