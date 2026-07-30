//
//  CodexLaneBar.swift
//  Talkie iOS
//
//  The Command Deck's Codex strip: lane selection, honest phase reporting, and
//  the capture control that drives the narrated loop.
//
//  It sits above the 4×4 keybed and stays compact on purpose — the deck is the
//  primary surface, and the lane strip is an instrument on it, not a screen of
//  its own. Anything that needs room (full response text, the task mapper)
//  opens as a sheet.
//

import SwiftUI

struct CodexLaneBar: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared

    @State private var showingMapper = false
    @State private var showingResponse = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                laneChips
                Spacer(minLength: 6)
                captureButton
            }

            statusLine
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingMapper) {
            CodexLaneMapperView()
        }
        .sheet(isPresented: $showingResponse) {
            if let turn = store.lastTurn {
                CodexResponseSheet(turn: turn)
            }
        }
    }

    // MARK: - Lanes

    private var laneChips: some View {
        HStack(spacing: 5) {
            ForEach(Array(CodexLane.range), id: \.self) { number in
                if let lane = store.lane(number) {
                    laneChip(lane)
                }
            }

            Button {
                showingMapper = true
            } label: {
                Image(systemName: store.lanes.isEmpty ? "plus.circle" : "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map Codex tasks to lanes")
        }
    }

    private func laneChip(_ lane: CodexLane) -> some View {
        let isActive = store.activeLaneNumber == lane.number
        return Button {
            Task { await store.activate(lane.number) }
        } label: {
            Text("\(lane.number)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive
                              ? theme.colors.accent.opacity(0.20)
                              : theme.colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isActive ? theme.colors.accent : theme.colors.tableBorder,
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
                .foregroundStyle(isActive ? theme.colors.accent : theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: lane, isActive: isActive))
    }

    private func accessibilityLabel(for lane: CodexLane, isActive: Bool) -> String {
        let state = isActive ? "selected" : "mapped"
        return "Lane \(lane.number), \(lane.task.title), \(state)"
    }

    // MARK: - Capture

    private var captureButton: some View {
        Button {
            store.handleCaptureControl()
        } label: {
            Image(systemName: captureIcon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(captureTint.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(captureTint.opacity(0.6), lineWidth: 1)
                )
                .foregroundStyle(captureTint)
        }
        .buttonStyle(.plain)
        .disabled(store.activeLaneNumber == nil)
        .opacity(store.activeLaneNumber == nil ? 0.4 : 1)
        .accessibilityLabel(captureAccessibilityLabel)
    }

    private var captureIcon: String {
        switch store.phase {
        case .listening: return "stop.fill"
        case .speaking: return "waveform"
        case .transcribing, .submitting, .preparingSpeech: return "ellipsis"
        case .idle, .failed: return "mic.fill"
        }
    }

    private var captureAccessibilityLabel: String {
        switch store.phase {
        case .listening: return "Stop recording and send to Codex"
        case .speaking: return "Interrupt the response and record a new instruction"
        default: return "Record an instruction for the active lane"
        }
    }

    private var captureTint: Color {
        switch store.phase {
        case .listening: return .red
        case .speaking: return theme.colors.success
        case .failed: return .orange
        default: return theme.colors.accent
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            if let failure = store.failure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(failure.combined)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let lane = store.activeLane {
                Text(store.phase.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(phaseTint)
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("\(lane.task.projectName) — \(lane.task.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            } else if store.lanes.isEmpty {
                Text("Map a Codex task to a lane to start.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
            } else {
                Text("Pick a lane.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer(minLength: 4)

            if let turn = store.lastTurn {
                Button {
                    showingResponse = true
                } label: {
                    HStack(spacing: 3) {
                        // A speech failure is surfaced here without demoting
                        // the turn: the response is still there to read.
                        if turn.speechFailure != nil {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 9))
                        }
                        Text("Response")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseTint: Color {
        switch store.phase {
        case .failed: return .orange
        case .idle: return theme.colors.textTertiary
        default: return theme.colors.accent
        }
    }
}

/// Full text of the last completed turn. Exists so the response is always
/// readable — narration is a convenience layered on top of it, never the only
/// way to receive the answer.
struct CodexResponseSheet: View {
    let turn: CodexTurnRecord

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(turn.laneNumber.map { "Lane \($0)" } ?? "No lane") · \(turn.taskTitle)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(turn.delivery.detailLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.colors.accent)
                        }

                        if let speechFailure = turn.speechFailure {
                            noticeRow(
                                icon: "speaker.slash.fill",
                                tint: .orange,
                                text: "Codex answered, but narration failed: \(speechFailure)"
                            )
                        } else if turn.narrationSuppressed {
                            noticeRow(
                                icon: "speaker.slash",
                                tint: theme.colors.textTertiary,
                                text: "Narration is off for this output route."
                            )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("You said")
                                .font(.system(size: 10, weight: .semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(theme.colors.textTertiary)
                            Text(turn.instruction)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.colors.textSecondary)
                                .textSelection(.enabled)
                        }

                        Divider().overlay(theme.colors.tableDivider)

                        Text(turn.response)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Codex Response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func noticeRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }
}
