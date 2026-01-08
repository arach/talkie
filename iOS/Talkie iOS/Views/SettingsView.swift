//
//  SettingsView.swift
//  Talkie iOS
//
//  Settings view with theme selection
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var logStore = LogStore.shared
    @State private var showingAllLogs = false

    // App info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.talkie.ios"
    }

    private var deviceName: String {
        UIDevice.current.name
    }

    private var iosVersion: String {
        UIDevice.current.systemVersion
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Appearance Mode
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("APPEARANCE")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            HStack(spacing: 8) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    AppearanceModeButton(
                                        mode: mode,
                                        isSelected: themeManager.appearanceMode == mode,
                                        onSelect: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                themeManager.appearanceMode = mode
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        // Theme Selection
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("THEME")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            VStack(spacing: 0) {
                                ForEach(AppTheme.allCases) { theme in
                                    ThemeRow(
                                        theme: theme,
                                        isSelected: themeManager.currentTheme == theme,
                                        onSelect: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                themeManager.currentTheme = theme
                                            }
                                        }
                                    )

                                    if theme != AppTheme.allCases.last {
                                        Divider()
                                            .background(Color.borderPrimary)
                                    }
                                }
                            }
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                            )
                            .padding(.horizontal, Spacing.md)
                        }

                        // Theme Preview
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PREVIEW")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            ThemePreview(theme: themeManager.currentTheme)
                                .padding(.horizontal, Spacing.md)
                        }

                        // Connections
                        ConnectionsSection()

                        // Mac Availability
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("MAC AVAILABILITY")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            NavigationLink(destination: MacAvailabilityCoachView()) {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.active)
                                    Text("Power & Availability")
                                    Spacer()
                                    MacAvailabilityBadge()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.sm)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        // Debug Info
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("DEBUG INFO")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            VStack(spacing: 0) {
                                DebugInfoRow(label: "Version", value: "\(appVersion) (\(buildNumber))")
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "Bundle ID", value: bundleId)
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "Device", value: deviceName)
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "iOS", value: iosVersion)
                            }
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                            )
                            .padding(.horizontal, Spacing.md)
                        }

                        // Recent Logs
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("RECENT LOGS")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textTertiary)

                                Spacer()

                                if !logStore.entries.isEmpty {
                                    Button(action: {
                                        showingAllLogs = true
                                    }) {
                                        Text("VIEW ALL")
                                            .font(.techLabelSmall)
                                            .tracking(1)
                                            .foregroundColor(.active)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)

                            if logStore.importantEntries.isEmpty {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                    Text("No errors or warnings")
                                        .font(.system(size: 13))
                                        .foregroundColor(.textSecondary)
                                }
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                                .padding(.horizontal, Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(logStore.importantEntries.prefix(5)) { entry in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(entry.formattedTime)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.textTertiary)

                                            Text(entry.message)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(entry.level == .info ? .textPrimary : entry.level.color.opacity(0.85))
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())

                                        if entry.id != logStore.importantEntries.prefix(5).last?.id {
                                            Divider().background(Color.borderPrimary)
                                        }
                                    }
                                }
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                                .padding(.horizontal, Spacing.md)
                            }
                        }

                        // Debug section (only in DEBUG builds)
                        #if DEBUG
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("DEV TOOLS")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, Spacing.md)

                            Button(action: {
                                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                                dismiss()
                                // Small delay to let sheet dismiss, then show onboarding
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(name: talkieApp.showOnboardingNotification, object: nil)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Show Onboarding")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.sm)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                            }
                            .padding(.horizontal, Spacing.md)

                            Button(action: {
                                UserDefaults.standard.set(false, forKey: "hasSeenResumeTooltip")
                            }) {
                                HStack {
                                    Image(systemName: "text.bubble")
                                    Text("Reset Resume Tooltip")
                                    Spacer()
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.sm)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                            }
                            .padding(.horizontal, Spacing.md)
                        }
                        #endif

                        Spacer(minLength: 40)
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.active)
                }
            }
        }
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .sheet(isPresented: $showingAllLogs) {
            LogViewerSheet()
        }
    }
}

// MARK: - Log Viewer Sheet

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var logStore = LogStore.shared
    @State private var filterLevel: LogEntry.LogLevel? = nil

    var filteredLogs: [LogEntry] {
        if let level = filterLevel {
            return logStore.entries.filter { $0.level == level }
        }
        return logStore.entries
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                if logStore.entries.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text("No logs yet")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Filter buttons
                        HStack(spacing: Spacing.xs) {
                            FilterButton(title: "All", isSelected: filterLevel == nil) {
                                filterLevel = nil
                            }
                            FilterButton(title: "Errors", isSelected: filterLevel == .error) {
                                filterLevel = .error
                            }
                            FilterButton(title: "Warnings", isSelected: filterLevel == .warning) {
                                filterLevel = .warning
                            }
                            Spacer()
                            Button(action: { logStore.clear() }) {
                                Text("Clear")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)

                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredLogs) { entry in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.formattedTime)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.textTertiary)

                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(entry.level == .info ? .textPrimary : entry.level.color.opacity(0.85))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 5)
                                    .background(Color.surfaceSecondary)
                                    .contextMenu {
                                        Button(action: {
                                            UIPasteboard.general.string = "[\(entry.formattedTime)] \(entry.message)"
                                        }) {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LOGS")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.active)
                }
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(isSelected ? Color.active : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Appearance Mode Button

struct AppearanceModeButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .active : .textSecondary)

                Text(mode.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.active.opacity(0.1) : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isSelected ? Color.active : Color.borderPrimary, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Debug Info Row

struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Theme Row

struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Color swatch
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(theme.colors.tableHeaderBackground)
                        .frame(width: 12, height: 24)
                    Rectangle()
                        .fill(theme.colors.tableCellBackground)
                        .frame(width: 12, height: 24)
                    Rectangle()
                        .fill(theme.colors.tableDivider)
                        .frame(width: 4, height: 24)
                }
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textPrimary)

                    Text(theme.description)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.active)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NAME")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                Spacer()
                Text("DURATION")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
            }
            .foregroundColor(theme.colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.colors.tableHeaderBackground)

            // Sample rows
            ForEach(0..<3) { index in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.colors.tableDivider)
                        .frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(["Meeting notes", "Quick idea", "Voice memo"][index])
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.colors.textPrimary)
                            Text("10:30 AM | 1.2 MB | M4A")
                                .font(.system(size: 10))
                                .foregroundColor(theme.colors.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(["2:34", "0:45", "5:12"][index])
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(theme.colors.textSecondary)
                            HStack(spacing: 4) {
                                Text("TXT")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.colors.success)
                                Image(systemName: "checkmark.icloud.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.colors.success)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.colors.tableCellBackground)
                }
            }
        }
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(theme.colors.tableBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Sync Section

struct SyncSection: View {
    @AppStorage(SyncSettingsKey.iCloudEnabled) private var iCloudEnabled = true
    @ObservedObject var cloudStatusManager = iCloudStatusManager.shared
    @State private var showingEnableConfirmation = false
    @State private var localMemoCount: Int = 0

    /// Whether iCloud is actually available (signed in and accessible)
    private var isActuallyAvailable: Bool {
        cloudStatusManager.status.isAvailable
    }

    /// Effective toggle state: only ON if preference enabled AND actually available
    private var effectivelyEnabled: Bool {
        iCloudEnabled && isActuallyAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("SYNC")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                // iCloud Sync Row
                HStack {
                    Image(systemName: cloudStatusManager.status.icon)
                        .foregroundColor(effectivelyEnabled ? .active : .textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    statusBadge

                    // Only show toggle if iCloud is actually available
                    if isActuallyAvailable {
                        Toggle("", isOn: Binding(
                            get: { iCloudEnabled },
                            set: { newValue in
                                if newValue && !iCloudEnabled {
                                    // Enabling - show confirmation
                                    countLocalMemos()
                                    showingEnableConfirmation = true
                                } else if !newValue && iCloudEnabled {
                                    // Disabling - no confirmation needed, just pause
                                    iCloudEnabled = false
                                    handleToggleChange(false)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .padding(Spacing.sm)
                .alert("Enable iCloud Sync?", isPresented: $showingEnableConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Enable") {
                        iCloudEnabled = true
                        handleToggleChange(true)
                    }
                } message: {
                    Text(localMemoCount > 0
                         ? "\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s") will be uploaded to iCloud. This may take a few moments."
                         : "Your memos will sync across all your Apple devices via iCloud.")
                }

            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private var statusBadge: some View {
        Group {
            if cloudStatusManager.status == .checking {
                ProgressView()
                    .controlSize(.small)
            } else if !effectivelyEnabled {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var statusMessage: String {
        switch cloudStatusManager.status {
        case .checking:
            return "Checking..."
        case .available:
            return iCloudEnabled ? "Connected" : "Disabled"
        case .noAccount:
            return "Not signed in"
        case .restricted:
            return "Restricted"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        case .couldNotDetermine:
            return "Status unknown"
        case .error:
            return "Error"
        }
    }

    private func countLocalMemos() {
        // Count memos in local Core Data store
        Task {
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deletedAt == nil")

            do {
                let count = try await context.perform {
                    try context.count(for: fetchRequest)
                }
                await MainActor.run {
                    localMemoCount = count
                }
            } catch {
                AppLogger.app.error("Failed to count local memos: \(error)")
                await MainActor.run {
                    localMemoCount = 0
                }
            }
        }
    }

    private func handleToggleChange(_ enabled: Bool) {
        AppLogger.app.info("iCloud sync \(enabled ? "enabled" : "disabled")")

        if enabled {
            // Resume sync - Core Data + CloudKit automatically sync
            AppLogger.app.info("iCloud sync resumed - Core Data will push changes")
        } else {
            // Pause sync - preference tracked, automatic sync paused
            AppLogger.app.info("iCloud sync paused")
        }

        Task {
            await ConnectionManager.shared.checkAllConnections()
        }
    }
}

// MARK: - Connections Section

struct ConnectionsSection: View {
    @ObservedObject var cloudStatusManager = iCloudStatusManager.shared
    @State private var bridgeManager = BridgeManager.shared

    private var connectionSummary: String {
        var connected: [String] = ["Local"]

        // Check iCloud
        if cloudStatusManager.status.isAvailable {
            let enabled = UserDefaults.standard.bool(forKey: SyncSettingsKey.iCloudEnabled)
            if enabled {
                connected.append("iCloud")
            }
        }

        // Check Bridge
        if bridgeManager.isPaired && bridgeManager.status == .connected {
            connected.append("Bridge")
        }

        if connected.count == 1 {
            return "Local only"
        } else {
            return connected.joined(separator: " + ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("CONNECTIONS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            NavigationLink(destination: ConnectionCenterView()) {
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(.active)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection Center")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text(connectionSummary)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(Spacing.sm)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}

// MARK: - Bridge Status Badge

struct BridgeStatusBadge: View {
    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(bridgeManager.status.color)
                .frame(width: 6, height: 6)
            Text(bridgeManager.status.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Mac Availability Badge

struct MacAvailabilityBadge: View {
    @State private var observer = MacStatusObserver.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .task {
            await observer.refresh()
        }
    }

    private var statusColor: Color {
        guard let status = observer.macStatus else {
            return .textTertiary
        }
        switch status.powerState {
        case "active", "idle":
            return .success
        case "screenOff":
            return status.canProcessMemos ? .success : .warning
        case "powerNap":
            return .warning
        default:
            return .textTertiary
        }
    }

    private var statusText: String {
        guard let status = observer.macStatus else {
            return "No Mac"
        }
        if status.canProcessMemos {
            return "Available"
        } else {
            return "Unavailable"
        }
    }
}

#Preview {
    SettingsView()
}
