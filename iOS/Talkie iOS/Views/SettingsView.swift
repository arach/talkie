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

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
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
                                DebugInfoRow(label: "Device", value: deviceModel)
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "iOS", value: iosVersion)
                                Divider().background(Color.borderPrimary)
                                DebugInfoRow(label: "Environment", value: isDebugBuild ? "DEBUG" : "RELEASE")
                            }
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                            )
                            .padding(.horizontal, Spacing.md)
                        }

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
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
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

#Preview {
    SettingsView()
}
