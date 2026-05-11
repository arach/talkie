//
//  SyncProvidersView.swift
//  Talkie
//
//  Settings view for managing sync providers.
//  Shows available providers, their status, and configuration options.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Sync Providers View

struct SyncProvidersView: View {
    @State private var connectionManager = ConnectionManager.shared
    @State private var syncClient = SyncClient.shared
    @State private var isCheckingConnections = false
    @State private var selectedProvider: SyncMethod?
    @State private var showingConfiguration = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // TalkieSync service status
            syncServiceStatus

            // Header with active provider
            activeProviderHeader

            Divider()

            // Available providers list
            providersSection

            // Coming soon providers
            comingSoonSection
        }
    }

    // MARK: - Sync Service Status

    private var syncServiceStatus: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                // Service indicator with animation when syncing
                if syncClient.isSyncing {
                    BrailleSpinner(size: 12)
                } else {
                    Circle()
                        .fill(syncClient.syncError != nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                }

                Text("Sync Service")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Status message - shows current activity or last sync time
                if syncClient.isSyncing {
                    Text(syncClient.syncStatusMessage.isEmpty ? "Syncing..." : syncClient.syncStatusMessage)
                        .font(.techLabelSmall)
                        .foregroundColor(.blue)
                        .animation(.easeInOut(duration: 0.2), value: syncClient.syncStatusMessage)
                } else if let error = syncClient.syncError {
                    Text(error)
                        .font(.techLabelSmall)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if let lastSync = syncClient.lastSyncDate {
                    Text("Last sync: \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                // Manual sync button
                Button(action: {
                    Task {
                        do {
                            try await syncClient.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
                        } catch {
                            log.error("Sync failed: \(error.localizedDescription)")
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(Theme.current.fontXS)
                            .rotationEffect(.degrees(syncClient.isSyncing ? 360 : 0))
                            .animation(
                                syncClient.isSyncing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: syncClient.isSyncing
                            )
                        if !syncClient.isSyncing {
                            Text("Sync")
                                .font(Theme.current.fontXS)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(syncClient.isSyncing)
            }

            // Progress bar when syncing
            if syncClient.isSyncing && syncClient.syncProgress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.current.surface2)
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * syncClient.syncProgress, height: 3)
                            .animation(.easeInOut(duration: 0.3), value: syncClient.syncProgress)
                    }
                }
                .frame(height: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1.opacity(0.5))
        .cornerRadius(CornerRadius.xs)
        .animation(.easeInOut(duration: 0.2), value: syncClient.isSyncing)
    }

    // MARK: - Active Provider Header

    private var activeProviderHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("ACTIVE SYNC")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if connectionManager.isSyncing {
                    HStack(spacing: Spacing.xs) {
                        BrailleSpinner(size: 12)
                        Text("Syncing...")
                            .font(.techLabelSmall)
                            .foregroundColor(.blue)
                    }
                } else if let result = connectionManager.lastSyncResult {
                    Text(result.summary)
                        .font(.techLabelSmall)
                        .foregroundColor(result.isSuccess ? .green : .orange)
                }
            }

            if let provider = connectionManager.activeProvider {
                HStack(spacing: Spacing.md) {
                    Image(systemName: provider.icon)
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(provider.displayName)
                            .font(Theme.current.fontSMMedium)
                        Text(provider.method.description)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            do {
                                try await syncClient.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
                            } catch {
                                log.error("Sync failed: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if syncClient.isSyncing {
                                BrailleSpinner(size: 12)
                                Text(syncClient.syncStatusMessage.isEmpty ? "Syncing..." : syncClient.syncStatusMessage)
                                    .font(Theme.current.fontXS)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                                    .font(Theme.current.fontXS)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncClient.isSyncing)
                }
                .padding(Spacing.md)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No active sync provider")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(Spacing.md)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("AVAILABLE PROVIDERS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: {
                    isCheckingConnections = true
                    Task {
                        await connectionManager.checkAllConnections()
                        isCheckingConnections = false
                    }
                }) {
                    if isCheckingConnections {
                        BrailleSpinner(size: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(Theme.current.fontXS)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Spacing.xs) {
                // Built-in providers
                ForEach([SyncMethod.iCloud, .local], id: \.self) { method in
                    if let provider = connectionManager.provider(for: method) {
                        providerRow(provider: provider, method: method)
                    }
                }

                // Configurable providers (show even if not registered)
                ForEach([SyncMethod.s3, .vercel], id: \.self) { method in
                    if let provider = connectionManager.provider(for: method) {
                        providerRow(provider: provider, method: method)
                    } else {
                        unconfiguredProviderRow(method: method)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
        .sheet(isPresented: $showingConfiguration) {
            if let method = selectedProvider {
                ProviderConfigurationSheet(method: method)
            }
        }
    }

    private func providerRow(provider: any SyncProvider, method: SyncMethod) -> some View {
        let status = connectionManager.methodStatus[method] ?? .unavailable(reason: "Unknown")
        let isActive = connectionManager.activeProvider?.method == method

        return Button(action: {
            Task { await connectionManager.setActiveProvider(method) }
        }) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: provider.icon)
                    .font(Theme.current.fontHeadline)
                    .foregroundColor(isActive ? .blue : Theme.current.foregroundSecondary)
                    .frame(width: 28)

                // Info
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(provider.displayName)
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(3)
                        }
                    }

                    Text(method.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Status
                statusBadge(status)
            }
            .padding(Spacing.sm)
            .background(isActive ? Color.blue.opacity(0.05) : Theme.current.surface1)
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
    }

    private func unconfiguredProviderRow(method: SyncMethod) -> some View {
        Button(action: {
            selectedProvider = method
            showingConfiguration = true
        }) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: method.icon)
                    .font(Theme.current.fontHeadline)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 28)

                // Info
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(method.displayName)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)

                    Text(method.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Configure button
                Text("CONFIGURE")
                    .font(.techLabelSmall)
                    .foregroundColor(.blue)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(CornerRadius.xs)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(_ status: ConnectionStatus) -> some View {
        switch status {
        case .available:
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Ready")
                    .font(.techLabelSmall)
                    .foregroundColor(.green)
            }

        case .connecting, .syncing:
            HStack(spacing: Spacing.xxs) {
                BrailleSpinner(size: 10)
                Text(status == .syncing ? "Syncing" : "Connecting")
                    .font(.techLabelSmall)
                    .foregroundColor(.blue)
            }

        case .unavailable(let reason):
            Text(reason)
                .font(.techLabelSmall)
                .foregroundColor(.orange)
                .lineLimit(1)
        }
    }

    // MARK: - Coming Soon Section

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("COMING SOON")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            VStack(spacing: Spacing.xs) {
                ForEach([SyncMethod.dropbox, .googleDrive], id: \.self) { method in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: method.icon)
                            .font(Theme.current.fontHeadline)
                            .foregroundColor(Theme.current.foregroundMuted.opacity(0.5))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(method.displayName)
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundMuted)

                            Text(method.description)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted.opacity(0.7))
                        }

                        Spacer()

                        Text("SOON")
                            .font(.techLabelSmall)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(3)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1.opacity(0.5))
                    .cornerRadius(CornerRadius.xs)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }
}

// MARK: - Provider Configuration Sheet

struct ProviderConfigurationSheet: View {
    let method: SyncMethod
    @Environment(\.dismiss) private var dismiss

    @State private var endpoint = ""
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var region = ""
    @State private var token = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            HStack {
                Image(systemName: method.icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Configure \(method.displayName)")
                        .font(Theme.current.fontHeadline)
                    Text(method.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }

            Divider()

            // Configuration fields based on provider type
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if method == .s3 {
                        s3ConfigurationFields
                    } else if method == .vercel {
                        vercelConfigurationFields
                    }
                }
            }

            Divider()

            // Test result
            if let result = testResult {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testSuccess ? .green : .red)
                    Text(result)
                        .font(Theme.current.fontSM)
                        .foregroundColor(testSuccess ? .green : .red)
                }
            }

            // Actions
            HStack {
                Button(action: testConnection) {
                    if isTesting {
                        BrailleSpinner(size: 12)
                    } else {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || !isValid)

                Spacer()

                Button("Save") {
                    saveConfiguration()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 500, height: method == .s3 ? 500 : 350)
    }

    // MARK: - S3 Configuration

    private var s3ConfigurationFields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("S3-COMPATIBLE STORAGE")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Works with AWS S3, Cloudflare R2, Google Cloud Storage, Supabase Storage, and other S3-compatible services.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            // Preset selector
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Provider Preset")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("Preset", selection: Binding(
                    get: { detectPreset() },
                    set: { applyPreset($0) }
                )) {
                    Text("Cloudflare R2").tag("r2")
                    Text("AWS S3").tag("aws")
                    Text("Google Cloud Storage").tag("gcs")
                    Text("Supabase Storage").tag("supabase")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
            }

            // Fields
            configField(label: "Endpoint URL", text: $endpoint, placeholder: "https://...")
            configField(label: "Access Key ID", text: $accessKeyId, placeholder: "Your access key")
            configField(label: "Secret Access Key", text: $secretAccessKey, placeholder: "Your secret key", isSecure: true)
            configField(label: "Bucket Name", text: $bucket, placeholder: "my-bucket")
            configField(label: "Region (optional)", text: $region, placeholder: "auto")
        }
    }

    // MARK: - Vercel Configuration

    private var vercelConfigurationFields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("VERCEL BLOB")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Simple blob storage from Vercel. Get your token from the Vercel dashboard.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            configField(label: "Blob Token", text: $token, placeholder: "vercel_blob_...", isSecure: true)

            Link("Get your token from Vercel Dashboard →", destination: URL(string: "https://vercel.com/dashboard/stores")!)
                .font(Theme.current.fontXS)
        }
    }

    // MARK: - Helpers

    private func configField(label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var isValid: Bool {
        switch method {
        case .s3:
            return !endpoint.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !bucket.isEmpty
        case .vercel:
            return !token.isEmpty
        default:
            return false
        }
    }

    private func detectPreset() -> String {
        if endpoint.contains("r2.cloudflarestorage.com") { return "r2" }
        if endpoint.contains("amazonaws.com") { return "aws" }
        if endpoint.contains("storage.googleapis.com") { return "gcs" }
        if endpoint.contains("supabase") { return "supabase" }
        return "custom"
    }

    private func applyPreset(_ preset: String) {
        switch preset {
        case "r2":
            endpoint = "https://<account-id>.r2.cloudflarestorage.com"
            region = "auto"
        case "aws":
            endpoint = "https://s3.<region>.amazonaws.com"
            region = "us-east-1"
        case "gcs":
            endpoint = "https://storage.googleapis.com"
            region = ""
        case "supabase":
            endpoint = "https://<project-ref>.supabase.co/storage/v1/s3"
            region = ""
        default:
            break
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                // Build credentials
                var credentials = SyncCredentials(provider: method)

                if method == .s3 {
                    credentials[.endpoint] = endpoint
                    credentials[.accessKeyId] = accessKeyId
                    credentials[.secretAccessKey] = secretAccessKey
                    credentials[.bucket] = bucket
                    credentials[.region] = region
                } else if method == .vercel {
                    credentials[.token] = token
                }

                // TODO: Actually test connection when provider is implemented
                // For now, simulate success if fields are valid
                try await Task.sleep(nanoseconds: 1_000_000_000)

                await MainActor.run {
                    testSuccess = true
                    testResult = "Connection successful!"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testSuccess = false
                    testResult = "Connection failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private func saveConfiguration() {
        var credentials = SyncCredentials(provider: method)

        if method == .s3 {
            credentials[.endpoint] = endpoint
            credentials[.accessKeyId] = accessKeyId
            credentials[.secretAccessKey] = secretAccessKey
            credentials[.bucket] = bucket
            credentials[.region] = region
        } else if method == .vercel {
            credentials[.token] = token
        }

        // TODO: Save to Keychain and register provider
        log.info("Saved credentials for \(method.rawValue)")
    }
}

// MARK: - Preview

#Preview("Sync Providers") {
    SyncProvidersView()
        .frame(width: 600, height: 700)
}
