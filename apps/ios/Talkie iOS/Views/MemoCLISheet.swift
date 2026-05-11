//
//  MemoCLISheet.swift
//  Talkie iOS
//
//  Run talkie CLI commands on the paired Mac from the phone.
//  Preset commands with memo context, plus custom input.
//

import SwiftUI

struct MemoCLISheet: View {
    let memoTitle: String
    let memoId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var customCommand = ""
    @State private var isRunning = false
    @State private var commandOutput: String?
    @State private var commandError: String?
    @State private var lastCommand: String?
    @FocusState private var commandFieldFocused: Bool

    private let bridge = BridgeManager.shared

    // Predefined commands that work on a memo
    private var presetCommands: [(icon: String, label: String, command: String)] {
        let idArg = memoId ?? "UNKNOWN"
        return [
            ("doc.text.magnifyingglass", "Show Memo", "talkie memos \(idArg)"),
            ("arrow.triangle.2.circlepath", "Sync Latest", "talkie sync now --limit 1 --pretty"),
            ("list.bullet", "Recent Memos", "talkie memos --limit 5"),
            ("chart.bar", "Workflow Runs", "talkie workflows --limit 5"),
            ("internaldrive", "Data Stats", "talkie data"),
            ("stethoscope", "Service Status", "talkie-dev status"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Preset commands
                    presetsSection

                    // Custom command input
                    customCommandSection

                    // Output area
                    if let output = commandOutput {
                        outputCard(output)
                    }

                    if let error = commandError {
                        errorCard(error)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Run CLI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("COMMANDS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.xs),
                GridItem(.flexible(), spacing: Spacing.xs),
            ], spacing: Spacing.xs) {
                ForEach(presetCommands, id: \.command) { preset in
                    Button {
                        runCommand(preset.command)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20)

                            Text(preset.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }
        }
    }

    // MARK: - Custom Command

    private var customCommandSection: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("CUSTOM")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                TextField("talkie ...", text: $customCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($commandFieldFocused)
                    .onSubmit {
                        if !customCommand.trimmingCharacters(in: .whitespaces).isEmpty {
                            runCommand(customCommand)
                        }
                    }

                if isRunning {
                    ProgressView().scaleEffect(0.7)
                } else if !customCommand.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        runCommand(customCommand)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Output

    private func outputCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                if let cmd = lastCommand {
                    Text(cmd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer()

                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    // MARK: - Execution

    private func runCommand(_ command: String) {
        guard bridge.status == .connected else {
            commandError = "Not connected to Mac. Check your pairing."
            return
        }

        isRunning = true
        commandError = nil
        commandOutput = nil
        lastCommand = command
        commandFieldFocused = false

        Task {
            do {
                let response = try await bridge.client.executeCLI(command: command)

                if response.success, let output = response.output {
                    commandOutput = output
                } else {
                    commandError = response.error ?? "Command failed"
                    if let output = response.output, !output.isEmpty {
                        commandOutput = output
                    }
                }
            } catch {
                commandError = error.localizedDescription
            }

            isRunning = false
        }
    }
}
