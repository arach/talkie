//
//  AppsSettingsView.swift
//  Talkie
//
//  Settings view for managing Talkie Apps.
//  Apps are mini JavaScript programs that extend Talkie (like Chrome extensions).
//

import SwiftUI
import TalkieKit

// MARK: - Apps Settings View

struct AppsSettingsView: View {
    @State private var settingsManager = SettingsManager.shared

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "square.stack.3d.up",
                title: "APPS",
                subtitle: "Extend Talkie with JavaScript apps."
            )
        } content: {
            VStack(spacing: Spacing.lg) {
                ExtensionsFrameworkToggle(isEnabled: $settings.extensionsFrameworkEnabled)

                if settings.extensionsFrameworkEnabled {
                    AppsEnabledContent()
                } else {
                    ExtensionsFrameworkDisabledView()
                }
            }
            .padding(Spacing.md)
        }
        .onChange(of: settings.extensionsFrameworkEnabled) { _, isEnabled in
            if !isEnabled {
                AppsRuntime.shared.stop()
            }
        }
    }
}

// MARK: - Framework Toggle

private struct ExtensionsFrameworkToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Extensions Framework")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("Enable JavaScript apps and extension events")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Text(
                isEnabled
                    ? "Apps can run scripts, render widgets, and receive memo/dictation events."
                    : "Disabled by default for lower launch memory and faster cold start."
            )
            .font(Theme.current.fontXS)
            .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.backgroundSecondary)
        )
    }
}

// MARK: - Enabled Content

private struct AppsEnabledContent: View {
    @State private var runtime = AppsRuntime.shared

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if runtime.loadedApps.isEmpty {
                EmptyAppsView()
            } else {
                AppsListView(runtime: runtime)
            }

            AppsActionsView()
        }
        .task {
            runtime.ensureStarted()
        }
    }
}

// MARK: - Disabled State

private struct ExtensionsFrameworkDisabledView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bolt.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundMuted)

                Text("Framework disabled")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Text("Talkie is skipping app discovery, JS runtime boot, and extension event processing.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.backgroundSecondary)
        )
    }
}

// MARK: - Empty State

private struct EmptyAppsView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No apps installed")
                .font(Theme.current.fontBodyMedium)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Apps extend Talkie with custom features.\nEach app is a folder with manifest.json + background.js.\nClick \"Open Apps Folder\" below to get started.")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Apps List

private struct AppsListView: View {
    let runtime: AppsRuntime

    private var sortedApps: [LoadedApp] {
        runtime.loadedApps.values.sorted { $0.manifest.name < $1.manifest.name }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(sortedApps) { app in
                AppRowView(app: app)
            }
        }
    }
}

// MARK: - App Row

private struct AppRowView: View {
    let app: LoadedApp

    @State private var isEnabled: Bool
    @State private var isHovered = false

    init(app: LoadedApp) {
        self.app = app
        self._isEnabled = State(initialValue: app.isEnabled)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            AppLogoView(app: app)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(app.manifest.name)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("v\(app.manifest.version)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    if app.isBundled {
                        Text("BUNDLED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Theme.current.backgroundTertiary)
                            .cornerRadius(CornerRadius.xs)
                    }
                }

                if let description = app.manifest.description {
                    Text(description)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                }

                // Status
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(app.isLoaded ? Color.green : (app.isEnabled ? Color.orange : Color.gray))
                        .frame(width: 6, height: 6)

                    Text(app.isLoaded ? "Running" : (app.isEnabled ? "Loading..." : "Disabled"))
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    if let error = app.loadError {
                        Text("• \(error)")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: isEnabled) { _, newValue in
                    Task { @MainActor in
                        AppsRuntime.shared.appManager.setEnabled(app.id, enabled: newValue)
                    }
                }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isHovered ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if app.isLoaded {
                Button("Reload") {
                    AppsRuntime.shared.reloadApp(app.id)
                }
            }

            if !app.isBundled {
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.directory])
                }
                Divider()
                Button("Uninstall", role: .destructive) {
                    try? AppsRuntime.shared.appManager.uninstallApp(app.id)
                }
            }
        }
    }
}

// MARK: - App Icon

private struct AppLogoView: View {
    let app: LoadedApp

    var body: some View {
        Group {
            if let iconURL = app.iconURL(size: 32),
               let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
        .frame(width: 32, height: 32)
        .background(Theme.current.backgroundTertiary)
        .cornerRadius(CornerRadius.xs)
    }
}

// MARK: - Actions

private struct AppsActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()

            HStack(spacing: Spacing.md) {
                Button(action: {
                    AppsRuntime.shared.appManager.openUserAppsDirectory()
                }) {
                    Label("Open Apps Folder", systemImage: "folder")
                        .font(Theme.current.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(SettingsManager.shared.accentColor.color ?? .accentColor)

                Button(action: {
                    AppsRuntime.shared.appManager.refresh()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(Theme.current.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: {
                    AppsRuntime.shared.reloadAllApps()
                }) {
                    Label("Reload All", systemImage: "arrow.counterclockwise")
                        .font(Theme.current.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(.top, Spacing.sm)

            // Help text
            Text("Drop app folders here to install. Each app is a folder with manifest.json + background.js (like Chrome extensions).")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.top, Spacing.xs)
        }
    }
}

// MARK: - Preview

#Preview("Apps Settings") {
    AppsSettingsView()
        .frame(width: 500, height: 600)
}
