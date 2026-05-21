//
//  MemoCLISheetNext.swift
//  Talkie iOS
//
//  Next-style memo-scoped CLI runner. Restores the donor preset command
//  surface and custom command path through the paired Mac Bridge.
//

import SwiftUI
import UIKit

struct MemoCLISheetNext: View {
    let memo: VoiceMemoDetailStore.MemoDisplay

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    @State private var bridge = BridgeManager.shared
    @State private var customCommand: String = ""
    @State private var isRunning: Bool = false
    @State private var commandOutput: String?
    @State private var commandError: String?
    @State private var lastCommand: String?
    @FocusState private var commandFieldFocused: Bool

    private var presetCommands: [MemoCLIPreset] {
        let idArg = memo.id.isEmpty ? "UNKNOWN" : memo.id
        return [
            MemoCLIPreset(
                icon: "doc.text.magnifyingglass",
                label: "Show Memo",
                command: "talkie memos \(idArg)"
            ),
            MemoCLIPreset(
                icon: "arrow.triangle.2.circlepath",
                label: "Sync Latest",
                command: "talkie sync now --limit 1 --pretty"
            ),
            MemoCLIPreset(
                icon: "list.bullet",
                label: "Recent Memos",
                command: "talkie memos --limit 5"
            ),
            MemoCLIPreset(
                icon: "chart.bar",
                label: "Workflow Runs",
                command: "talkie workflows --limit 5"
            ),
            MemoCLIPreset(
                icon: "internaldrive",
                label: "Data Stats",
                command: "talkie data"
            ),
            MemoCLIPreset(
                icon: "stethoscope",
                label: "Service Status",
                command: "talkie-dev status"
            ),
        ]
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        memoContextCard
                        presetsSection
                        customCommandSection
                        outputSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run CLI")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(connectionLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(connectionTint)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .talkieType(.fieldLabel)
            .foregroundStyle(theme.colors.textSecondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    private var memoContextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("MEMO CONTEXT")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text("\(wordCount) WORDS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Text(memo.title)
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)

            Text(memo.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 12))
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· COMMANDS")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(presetCommands) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: MemoCLIPreset) -> some View {
        Button {
            runCommand(preset.command)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 22, height: 22, alignment: .leading)

                Text(preset.label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(preset.command)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardBackground(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
    }

    private var customCommandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· CUSTOM")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)

                TextField("talkie ...", text: $customCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($commandFieldFocused)
                    .onSubmit(runCustomCommand)

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if canRunCustomCommand {
                    Button(action: runCustomCommand) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run custom command")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBackground(cornerRadius: 10))

            Text("Only talkie and talkie-dev commands run on the paired Mac.")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        if let commandOutput, !commandOutput.isEmpty {
            outputCard(commandOutput)
        }

        if let commandError, !commandError.isEmpty {
            errorCard(commandError)
        }
    }

    private func outputCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)

                Text(lastCommand ?? "Command output")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .accessibilityLabel("Copy output")
                }
                .buttonStyle(.plain)
            }

            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)

            Text(text)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(cardBackground(cornerRadius: 10))
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
    }

    private var canRunCustomCommand: Bool {
        !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var connectionLabel: String {
        if bridge.isPaired {
            return "\(bridge.status.rawValue.uppercased()) · \(bridge.pairedMacDisplayName ?? "PAIRED MAC")"
        }

        return "NOT PAIRED"
    }

    private var connectionTint: Color {
        switch bridge.status {
        case .connected:
            return Color.green.opacity(0.9)
        case .connecting:
            return Color.orange.opacity(0.9)
        case .disconnected:
            return theme.colors.textTertiary
        case .error:
            return Color.red.opacity(0.9)
        }
    }

    private var wordCount: Int {
        memo.transcript.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func runCustomCommand() {
        let command = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        runCommand(command)
    }

    private func runCommand(_ command: String) {
        guard !isRunning else { return }

        isRunning = true
        commandError = nil
        commandOutput = nil
        lastCommand = command
        commandFieldFocused = false

        Task { @MainActor in
            defer { isRunning = false }

            do {
                let response = try await bridge.executeCLI(command: command)

                if response.success {
                    commandOutput = response.output ?? "Command finished."
                    appendCommandMetadata(response)
                } else {
                    commandError = response.error ?? "Command failed."
                    if let output = response.output, !output.isEmpty {
                        commandOutput = output
                    }
                    appendCommandMetadata(response)
                }
            } catch {
                commandError = error.localizedDescription
            }
        }
    }

    private func appendCommandMetadata(_ response: CLIResponse) {
        var metadata: [String] = []
        if let exitCode = response.exitCode {
            metadata.append("exit \(exitCode)")
        }
        if let durationMs = response.durationMs {
            metadata.append("\(durationMs)ms")
        }
        guard !metadata.isEmpty else { return }

        let suffix = "\n\n[\(metadata.joined(separator: " · "))]"
        if commandOutput == nil {
            commandOutput = suffix
        } else {
            commandOutput?.append(suffix)
        }
    }
}

private struct MemoCLIPreset: Identifiable {
    let icon: String
    let label: String
    let command: String

    var id: String { command }
}
