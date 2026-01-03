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
    private let workflowService = WorkflowService.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "wand.and.stars",
                title: "WORKFLOWS",
                subtitle: "Manage and customize your workflow actions."
            )
        } content: {
            // MARK: - Workflow Library Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("WORKFLOW LIBRARY")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("\(workflowService.workflows.count) WORKFLOWS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.purple.opacity(0.8))
                }

                VStack(spacing: 8) {
                    ForEach(workflowService.workflows.prefix(5)) { workflow in
                        WorkflowPreviewRow(workflow: workflow)
                    }

                    if workflowService.workflows.count > 5 {
                        HStack {
                            Text("+ \(workflowService.workflows.count - 5) more workflows")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Spacer()
                        }
                        .padding(8)
                    }
                }
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Coming Soon Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("WORKFLOW BUILDER")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(3)
                }

                HStack(spacing: 16) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue.opacity(0.6))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Visual Workflow Editor")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text("Create custom workflows with a drag-and-drop interface. Chain together transcription, AI processing, file actions, and more.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                // Feature list
                VStack(alignment: .leading, spacing: 8) {
                    WorkflowFeatureRow(icon: "square.stack.3d.up", text: "Chain multiple steps together")
                    WorkflowFeatureRow(icon: "arrow.triangle.branch", text: "Conditional branching based on content")
                    WorkflowFeatureRow(icon: "brain", text: "AI processing with custom prompts")
                    WorkflowFeatureRow(icon: "doc.text", text: "Save to files in various formats")
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Learn More
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)

                Text("Workflows currently run automatically or from Quick Actions. See Auto-Run and Quick Actions settings to configure.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Workflow Preview Row
private struct WorkflowPreviewRow: View {
    let workflow: Workflow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workflow.icon)
                .font(.system(size: 14))
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(CornerRadius.xs)

            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(Theme.current.fontSMMedium)
                Text("\(workflow.steps.count) step(s)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            if !workflow.isEnabled {
                Text("DISABLED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(3)
            }

            if workflow.isPinned {
                Image(systemName: "pin.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
            }

            if workflow.autoRun {
                Image(systemName: "bolt.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)
            }
        }
        .padding(10)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }
}

// MARK: - Workflow Feature Row
private struct WorkflowFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(.blue)
                .frame(width: 16)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }
}

// MARK: - Activity Log View
struct ActivityLogView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "list.bullet.clipboard",
                title: "ACTIVITY LOG",
                subtitle: "View workflow execution history."
            )
        } content: {
            // MARK: - Recent Activity Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("RECENT ACTIVITY")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan)
                        .cornerRadius(3)
                }

                HStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan.opacity(0.6))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execution History")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text("Track when workflows run, view results, and debug any issues. See which memos triggered which workflows.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                // Planned features
                VStack(alignment: .leading, spacing: 8) {
                    ActivityFeatureRow(icon: "checkmark.circle", text: "Success/failure status for each run")
                    ActivityFeatureRow(icon: "clock", text: "Execution time tracking")
                    ActivityFeatureRow(icon: "doc.text.magnifyingglass", text: "View input/output for each step")
                    ActivityFeatureRow(icon: "arrow.counterclockwise", text: "Re-run failed workflows")
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)
        }
    }
}

// MARK: - Activity Feature Row
private struct ActivityFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(.cyan)
                .frame(width: 16)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }
}

// MARK: - Allowed Commands View
struct AllowedCommandsView: View {
    @State private var newCommandPath: String = ""
    @State private var customCommands: [String] = []
    @State private var showingWhichResult: String?
    private let settings = SettingsManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "terminal",
                title: "ALLOWED COMMANDS",
                subtitle: "Manage which CLI tools can be executed by workflow shell steps."
            )
        } content: {
            // MARK: - Add Command Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 3, height: 14)

                    Text("ADD COMMAND")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("/path/to/executable", text: $newCommandPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        Button(action: findCommand) {
                            Text("Which")
                                .font(Theme.current.fontXSMedium)
                        }
                        .buttonStyle(.bordered)
                        .help("Find path for a command name")

                        Button(action: addCommand) {
                            Text("Add")
                                .font(Theme.current.fontXSMedium)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newCommandPath.isEmpty)
                    }

                    if let result = showingWhichResult {
                        HStack(spacing: 6) {
                            Image(systemName: result.contains("Found") ? "checkmark.circle.fill" : "info.circle.fill")
                                .font(Theme.current.fontXS)
                                .foregroundColor(result.contains("Found") ? .green : .blue)
                            Text(result)
                                .font(Theme.current.fontXS)
                                .foregroundColor(result.contains("Found") ? .green : .secondary)
                        }
                        .padding(8)
                        .background(result.contains("Found") ? Color.green.opacity(0.1) : Theme.current.surface1)
                        .cornerRadius(CornerRadius.xs)
                    }

                    Text("Enter the full path to the executable (e.g., /Users/you/.bun/bin/claude)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Custom Commands Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("YOUR CUSTOM COMMANDS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if !customCommands.isEmpty {
                        Text("\(customCommands.count) ADDED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                }

                if customCommands.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "terminal")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No custom commands added")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
                            Text("Add executable paths above to allow them in Shell workflow steps.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    VStack(spacing: 6) {
                        ForEach(customCommands, id: \.self) { path in
                            HStack(spacing: 10) {
                                Image(systemName: "terminal.fill")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(.green)

                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Theme.current.foreground)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button(action: { removeCommand(path) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.xs)
                        }
                    }
                }
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Built-in Commands Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("BUILT-IN COMMANDS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("\(ShellStepConfig.defaultAllowedExecutables.count) AVAILABLE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.8))
                }

                DisclosureGroup {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(ShellStepConfig.defaultAllowedExecutables.sorted(), id: \.self) { path in
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                        Text("Show built-in allowed commands")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(.blue)
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Security Note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)

                Text("Only add commands you trust. Shell steps can execute arbitrary code with access to your file system.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(CornerRadius.sm)
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

