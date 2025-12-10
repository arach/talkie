//
//  WorkflowSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Workflows View
struct WorkflowsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(SettingsManager.shared.fontTitle)
                        Text("WORKFLOWS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.primary)

                    Text("Manage and customize your workflow actions.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Workflow builder and customization")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsManager.shared.surfaceInput)
    }
}

// MARK: - Activity Log View
struct ActivityLogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(SettingsManager.shared.fontTitle)
                        Text("ACTIVITY LOG")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.primary)

                    Text("View workflow execution history.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Activity log and execution history")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsManager.shared.surfaceInput)
    }
}

// MARK: - Allowed Commands View
struct AllowedCommandsView: View {
    @State private var newCommandPath: String = ""
    @State private var customCommands: [String] = []
    @State private var showingWhichResult: String?

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "terminal",
                title: "ALLOWED COMMANDS",
                subtitle: "Manage which CLI tools can be executed by workflow shell steps."
            )
        } content: {
            // Add new command
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD COMMAND")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("/path/to/executable", text: $newCommandPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Theme.current.surface1)
                            .cornerRadius(6)

                        Button(action: findCommand) {
                            Text("WHICH")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.secondary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Find path for a command name")

                        Button(action: addCommand) {
                            Text("ADD")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(newCommandPath.isEmpty ? Color.gray : Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(newCommandPath.isEmpty)
                    }

                    if let result = showingWhichResult {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.blue)
                            Text(result)
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.blue)
                        }
                    }

                    Text("Enter the full path to the executable (e.g., /Users/you/.bun/bin/claude)")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Custom commands
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR CUSTOM COMMANDS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    if customCommands.isEmpty {
                        Text("No custom commands added yet.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(customCommands, id: \.self) { path in
                            HStack {
                                Image(systemName: "terminal")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.green)

                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button(action: { removeCommand(path) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(SettingsManager.shared.fontSM)
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Theme.current.surface1)
                            .cornerRadius(6)
                        }
                    }
                }

                Divider()

                // Default commands (collapsed)
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUILT-IN COMMANDS (\(ShellStepConfig.defaultAllowedExecutables.count))")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    DisclosureGroup {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(ShellStepConfig.defaultAllowedExecutables.sorted(), id: \.self) { path in
                                Text(path)
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } label: {
                        Text("Show built-in allowed commands")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.blue)
                    }
                }
        }
        .onAppear {
            loadCustomCommands()
        }
    }

    private func loadCustomCommands() {
        customCommands = ShellStepConfig.customAllowedExecutables
    }

    private func addCommand() {
        let path = newCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        ShellStepConfig.addAllowedExecutable(path)
        customCommands = ShellStepConfig.customAllowedExecutables
        newCommandPath = ""
        showingWhichResult = nil
    }

    private func removeCommand(_ path: String) {
        ShellStepConfig.removeAllowedExecutable(path)
        customCommands = ShellStepConfig.customAllowedExecutables
    }

    private func findCommand() {
        let name = newCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Only search system paths that won't trigger permission dialogs
        // Avoid ~/Library and other protected user directories
        let systemPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]

        // Check system paths first (safe, no permission prompts)
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                newCommandPath = path
                showingWhichResult = "Found: \(path)"
                return
            }
        }

        // For user-specific paths, provide suggestions without checking
        // This avoids triggering macOS permission dialogs
        let suggestions = [
            "~/.bun/bin/\(name)",
            "~/.claude/local/\(name)",
            "~/.local/bin/\(name)",
            "~/.cargo/bin/\(name)",
        ]

        showingWhichResult = "Not found in system paths. Try one of:\n" + suggestions.joined(separator: "\n")
    }
}

