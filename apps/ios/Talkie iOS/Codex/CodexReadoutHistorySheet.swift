//
//  CodexReadoutHistorySheet.swift
//  Talkie iOS
//
//  THESIS: A spoken-readout log is deck instrumentation, not a settings list.
//  OWN WORLD: Recessed theme panels, monospaced eyebrow rows, a retained-count
//  manifest, and a single HEAR/STOP transport per record. Chrome accent is
//  reserved for the one readout that is actually speaking; every other
//  affordance goes through the neutral action ink.
//  NATIVE: NavigationStack, inline title, Refresh/Done toolbar, pull-to-refresh,
//  and real Buttons stay native so VoiceOver and navigation are unchanged.
//

import SwiftUI

/// A compact queue of agent-report notifications that can be heard again.
struct CodexReadoutHistorySheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var voicePlayback = WalkieFX.shared
    @State private var readouts: [CodexReadout] = []
    @State private var activeReadoutID: String?
    @State private var isLoading = false
    @State private var loadFailure: String?

    private static let provenance = "TalkieNotifications · private iCloud database"

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Spoken History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await loadReadouts() }
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadReadouts() }
        .onChange(of: voicePlayback.isVoicePlaybackActive) { _, isActive in
            if !isActive {
                activeReadoutID = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !readouts.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    manifest

                    if let loadFailure {
                        connectionBanner(loadFailure)
                    }

                    ForEach(readouts.enumerated(), id: \.element.id) { index, readout in
                        readoutCard(readout, position: index + 1)
                    }
                }
                .padding(18)
            }
            .refreshable { await loadReadouts() }
        } else if let loadFailure, !isLoading {
            noticePanel(
                eyebrow: "SPOKEN HISTORY UNAVAILABLE",
                eyebrowColor: .orange,
                message: loadFailure,
                retryTitle: "Retry"
            )
        } else if isLoading {
            loadingManifest
        } else {
            noticePanel(
                eyebrow: "NO SPOKEN READOUTS YET",
                eyebrowColor: theme.chrome.panelAccent,
                message: "Agent responses that arrive as notifications collect here, ready to hear again.",
                retryTitle: "Check again"
            )
        }
    }

    // MARK: Manifest

    private var manifest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SPOKEN READOUTS")
                Spacer()
                Text("\(readouts.count) RETAINED")
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(theme.chrome.panelAccent)

            HStack(alignment: .lastTextBaseline, spacing: 9) {
                Text("\(readouts.count)")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("ON THIS DEVICE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
            }

            if let latest = readouts.first {
                Label("LATEST · \(stamp(latest.createdAt))", systemImage: "clock")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Text(Self.provenance)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Agent reports that arrived as spoken notifications. Hear speaks any response again.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            theme.chrome.panelInkFaint.opacity(0.18),
                            lineWidth: theme.chrome.hairlineWidth
                        )
                }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Readout record

    private func readoutCard(_ readout: CodexReadout, position: Int) -> some View {
        let isActive = activeReadoutID == readout.id && voicePlayback.isVoicePlaybackActive

        return VStack(alignment: .leading, spacing: 0) {
            recordHeader(readout, position: position, isActive: isActive)

            Rectangle()
                .fill(theme.chrome.panelInkFaint.opacity(0.12))
                .frame(height: theme.chrome.hairlineWidth)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(readout.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(2)

                    Text(readout.spokenText)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(readout.createdAt, format: .relative(presentation: .named))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                transportButton(readout, isActive: isActive)
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? theme.chrome.accentTint : theme.chrome.panel.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isActive
                                ? theme.chrome.accent.opacity(0.55)
                                : theme.chrome.panelInkFaint.opacity(0.14),
                            lineWidth: isActive ? 1 : theme.chrome.hairlineWidth
                        )
                }
        }
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }

    private func recordHeader(_ readout: CodexReadout, position: Int, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(sequence(position))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.chrome.panelAccent)

            Text("·")
            Text(stamp(readout.createdAt))

            if let source = readout.source {
                Text("·")
                Text(source.uppercased())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if isActive {
                Text("SPEAKING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(theme.chrome.accent)
            }
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.colors.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func transportButton(_ readout: CodexReadout, isActive: Bool) -> some View {
        Button {
            toggleReadout(readout)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isActive ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isActive ? "STOP" : "HEAR")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundStyle(isActive ? theme.chrome.accent : theme.colors.textSecondary)
            .frame(width: 52, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? theme.chrome.accentTint : theme.chrome.actionTint)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? theme.chrome.accent.opacity(0.55)
                                    : theme.chrome.action.opacity(0.35),
                                lineWidth: theme.chrome.hairlineWidth
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Stop" : "Hear")
        .accessibilityHint(isActive ? "Stops this readout" : "Speaks this notification again")
        .frame(minWidth: 44, minHeight: 44)
    }

    // MARK: Loading / notice states

    private var loadingManifest: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SPOKEN READOUTS")
                    Spacer()
                    Text("READING ICLOUD")
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(theme.chrome.panelAccent)
                .padding(.bottom, 2)

                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.textTertiary.opacity(0.18))
                            .frame(width: index.isMultiple(of: 2) ? 96 : 128, height: 7)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.textSecondary.opacity(0.16))
                            .frame(width: index.isMultiple(of: 3) ? 148 : 196, height: 11)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.textTertiary.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 9)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.textTertiary.opacity(0.12))
                            .frame(width: index.isMultiple(of: 2) ? 168 : 124, height: 9)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.chrome.panel.opacity(0.72))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        theme.chrome.panelInkFaint.opacity(0.14),
                                        lineWidth: theme.chrome.hairlineWidth
                                    )
                            }
                    }
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading spoken readouts")
    }

    private func noticePanel(
        eyebrow: String,
        eyebrowColor: Color,
        message: String,
        retryTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(eyebrowColor)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.provenance)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(retryTitle, systemImage: "arrow.clockwise") {
                Task { await loadReadouts() }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .buttonStyle(.bordered)
            .tint(theme.chrome.action)
            .disabled(isLoading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            theme.chrome.panelInkFaint.opacity(0.18),
                            lineWidth: theme.chrome.hairlineWidth
                        )
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func connectionBanner(_ message: String) -> some View {
        Label("Showing saved readouts. \(message)", systemImage: "wifi.exclamationmark")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    // MARK: Formatting

    private func sequence(_ position: Int) -> String {
        position < 10 ? "R0\(position)" : "R\(position)"
    }

    private func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute()).uppercased()
    }

    // MARK: Behavior

    private func toggleReadout(_ readout: CodexReadout) {
        if activeReadoutID == readout.id, voicePlayback.isVoicePlaybackActive {
            CodexLaneStore.shared.interruptNarration()
            activeReadoutID = nil
            return
        }

        CodexLaneStore.shared.interruptNarration()
        activeReadoutID = readout.id
        Task { @MainActor in
            await CodexLaneStore.shared.narrateNotificationResponse(
                readout.spokenText,
                preview: readout.title,
                jobID: readout.sessionID
            )
            if !voicePlayback.isVoicePlaybackActive {
                activeReadoutID = nil
            }
        }
    }

    private func loadReadouts() async {
        isLoading = true
        loadFailure = nil
        defer { isLoading = false }

        do {
            readouts = try await CodexReadoutHistoryLoader.load()
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}
