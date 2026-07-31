//
//  CodexChannelHistorySheet.swift
//  Talkie iOS
//

import Foundation
import SwiftUI

/// Loads the selected channel's public turn history from the paired Mac.
struct CodexChannelHistorySheet: View {
    let task: CodexTaskSummary

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var history: CodexChannelHistory?
    @State private var isLoading = false
    @State private var loadFailure: String?
    @State private var expandedTurnIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Channel History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(theme.chrome.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await loadHistory() }
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: task.id) { await loadHistory() }
    }

    @ViewBuilder private var content: some View {
        if let history {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    channelIdentity(history.task, turnCount: history.turns.count)

                    if let loadFailure {
                        connectionBanner(loadFailure)
                    }

                    if history.turns.isEmpty {
                        ContentUnavailableView(
                            "No completed turns yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("This is the right channel, but its host history is still empty.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        HStack {
                            Text("RECENT TURNS")
                            Spacer()
                            Text("TAP TO EXPAND")
                        }
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, 2)

                        ForEach(history.turns) { turn in
                            turnCard(turn)
                        }
                    }
                }
                .padding(18)
            }
            .refreshable { await loadHistory() }
        } else if let loadFailure, !isLoading {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadFailure)
            } actions: {
                Button("Retry", systemImage: "arrow.clockwise") {
                    Task { await loadHistory() }
                }
            }
        } else {
            ProgressView("Loading history from Mac…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func channelIdentity(_ task: CodexTaskSummary, turnCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SELECTED CHANNEL")
                Spacer()
                Text("\(turnCount) TURNS")
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(theme.chrome.panelAccent)

            Text(task.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.chrome.panelInk)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(task.projectName, systemImage: "folder")
                if let gitBranch = task.gitBranch, !gitBranch.isEmpty {
                    Label(gitBranch, systemImage: "arrow.triangle.branch")
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.chrome.panelInkFaint)
            .lineLimit(1)

            Text(task.cwd)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)

            if !task.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(task.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.chrome.panelInk.opacity(0.82))
                    .lineLimit(3)
            }

            Text("Loaded from this channel on the paired Mac. Public prompts, agent notes, actions, and answers only.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.chrome.panelEdge.opacity(0.92), lineWidth: theme.chrome.hairlineWidth)
                }
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(theme.chrome.panelAccent)
                        .frame(width: 42, height: 2)
                        .padding(.leading, 16)
                }
        }
    }

    private func turnCard(_ turn: CodexChannelHistory.Turn) -> some View {
        let isExpanded = expandedTurnIDs.contains(turn.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedTurnIDs.remove(turn.id)
                } else {
                    expandedTurnIDs.insert(turn.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: isExpanded ? "minus.circle.fill" : "plus.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.chrome.panelAccent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(turn.latestInstruction ?? turn.publicResponse ?? fallbackTitle(for: turn))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(isExpanded ? 4 : 2)

                        Text("\(turn.updates.count) PUBLIC UPDATES · \(formattedDate(turn.completedAt ?? turn.startedAt))")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.colors.textTertiary)
                    }

                    Spacer(minLength: 4)

                    Text(statusLabel(for: turn))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor(for: turn))
                }
                .contentShape(.rect)
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(statusLabel(for: turn)), \(turn.latestInstruction ?? fallbackTitle(for: turn))")
            .accessibilityHint(isExpanded ? "Collapses this turn" : "Shows this turn")

            if isExpanded {
                turnDetails(turn)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.chrome.edgeFaint, lineWidth: theme.chrome.hairlineWidth)
                }
                .shadow(color: theme.colors.textPrimary.opacity(0.055), radius: 5, y: 2)
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private func turnDetails(_ turn: CodexChannelHistory.Turn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(turn.instructions.enumerated(), id: \.offset) { _, instruction in
                detailBlock(label: "YOU ASKED", text: instruction, accent: theme.chrome.panelAccent)
            }

            if !turn.updates.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("PUBLIC ACTIVITY")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(theme.colors.textTertiary)

                    ForEach(turn.updates) { update in
                        HStack(alignment: .top, spacing: 9) {
                            Text(update.kind == "commentary" ? "NOTE" : "TOOL")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.chrome.panelAccent)
                                .frame(width: 36, alignment: .leading)
                            Text(update.text)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let response = turn.publicResponse {
                detailBlock(label: "DELIVERED", text: response, accent: theme.colors.textTertiary)
            } else if let error = turn.error {
                detailBlock(label: "OUTCOME", text: error, accent: failureColor)
            }
        }
        .padding(.top, 2)
    }

    private func detailBlock(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 2)
        }
    }

    private func connectionBanner(_ message: String) -> some View {
        Label("Showing the last loaded history. \(message)", systemImage: "wifi.exclamationmark")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(failureColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(failureColor.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func statusLabel(for turn: CodexChannelHistory.Turn) -> String {
        switch turn.status {
        case "completed": return "DONE"
        case "failed": return "FAILED"
        default: return "STOPPED"
        }
    }

    private func statusColor(for turn: CodexChannelHistory.Turn) -> Color {
        turn.status == "completed" ? theme.chrome.accent : failureColor
    }

    private var failureColor: Color {
        Color(red: 0.92, green: 0.42, blue: 0.30)
    }

    private func fallbackTitle(for turn: CodexChannelHistory.Turn) -> String {
        turn.status == "completed" ? "Completed turn" : "Turn ended"
    }

    private func formattedDate(_ value: String?) -> String {
        guard let value,
              let date = ISO8601DateFormatter().date(from: value) else {
            return "DATE UNKNOWN"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute()).uppercased()
    }

    private func loadHistory() async {
        isLoading = true
        loadFailure = nil
        defer { isLoading = false }
        do {
            history = try await BridgeManager.shared.codexTaskHistory(taskId: task.id)
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}
