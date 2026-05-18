//
//  VoiceMemoDetailNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — Next-style memo detail. Header + waveform
//  + playback transport + transcript + actions. Donor is
//  VoiceMemoDetailView (4823 lines); this is the rebuilt visual
//  frame, full feature set still lives in the donor and gets pulled
//  per the donor-audit pattern.
//

import SwiftUI

@MainActor
final class VoiceMemoDetailStore: ObservableObject {
    @Published var memo: MemoDisplay

    struct MemoDisplay {
        let id: String
        let title: String
        let createdAtLabel: String   // "Today · 9:34 AM"
        let durationLabel: String    // "3:42"
        let transcript: String
        let summary: String?
        let levels: [Float]
        let isPlaying: Bool
        let playheadProgress: Double // 0...1
    }

    init(memoID: String?) {
        self.memo = Self.mockMemo
    }

    private static let mockLevels: [Float] = (0..<100).map { i in
        let v = 0.3 + 0.5 * sin(Double(i) * 0.4) + 0.2 * cos(Double(i) * 0.13)
        return Float(abs(v).truncatingRemainder(dividingBy: 1.0))
    }

    static let mockMemo = MemoDisplay(
        id: "mock",
        title: "Meeting notes — product review",
        createdAtLabel: "Today · 9:34 AM",
        durationLabel: "3:42",
        transcript: """
        alex pushed back on the migration timeline; said we should move it to q3 instead of pushing through in q2. the rest of the team seems fine with that. main concern is the downstream impact on the analytics rewrite which depends on the new schema.

        action items: ship the spec by friday, get sam to sign off, schedule the migration window for the first week of july.
        """,
        summary: "Migration timeline shifts to Q3; spec ships Friday, downstream analytics rewrite affected.",
        levels: VoiceMemoDetailStore.mockLevels,
        isPlaying: false,
        playheadProgress: 0.32
    )
}

struct VoiceMemoDetailNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: VoiceMemoDetailStore

    init(memoID: String? = nil) {
        _store = StateObject(wrappedValue: VoiceMemoDetailStore(memoID: memoID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metaRow
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    playbackCard
                        .padding(.horizontal, 12)

                    if let summary = store.memo.summary {
                        summaryCard(summary)
                            .padding(.horizontal, 12)
                    }

                    transcriptSection
                        .padding(.horizontal, 12)

                    Spacer(minLength: 100)
                }
            }
            .scrollIndicators(.hidden)

            actionBar
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Memos")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Memo")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button(action: { /* TODO: more menu */ }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - Meta

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.memo.title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("· MEMO · \(store.memo.createdAtLabel.uppercased()) · \(store.memo.durationLabel)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    // MARK: - Playback card

    private var playbackCard: some View {
        VStack(spacing: 12) {
            ParticlesWaveformView(
                levels: store.memo.levels,
                height: 60,
                color: theme.currentTheme.chrome.accent
            )
            .frame(height: 60)

            // Scrub track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.currentTheme.chrome.edgeFaint)
                        .frame(height: 3)
                    Capsule()
                        .fill(theme.currentTheme.chrome.accent)
                        .frame(width: geo.size.width * store.memo.playheadProgress, height: 3)
                    Circle()
                        .fill(theme.currentTheme.chrome.accent)
                        .frame(width: 10, height: 10)
                        .offset(x: geo.size.width * store.memo.playheadProgress - 5)
                }
            }
            .frame(height: 10)

            HStack {
                Text(formatTime(store.memo.playheadProgress * 222))  // 3:42 = 222s
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                playbackTransport
                Spacer()
                Text(store.memo.durationLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var playbackTransport: some View {
        HStack(spacing: 18) {
            Button(action: {}) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(theme.currentTheme.chrome.accent)
                        .frame(width: 42, height: 42)
                    Image(systemName: store.memo.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.colors.cardBackground)
                }
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("· SUMMARY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            Text(summary)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(theme.colors.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.currentTheme.chrome.accentTint)
        )
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· TRANSCRIPT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text("\(wordCount) WORDS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 4)

            Text(store.memo.transcript)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(theme.colors.textPrimary)
                .tracking(-0.05)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionChip(label: "Share",   isPrimary: false) { /* TODO */ }
            actionChip(label: "Refine ›", isPrimary: true) {
                AppShellRouter.shared.openCompose(documentID: store.memo.id)
            }
        }
        .padding(.leading, 72)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }

    private func actionChip(label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPrimary
                    ? theme.colors.cardBackground
                    : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(isPrimary ? theme.currentTheme.chrome.accent : Color.clear)
                        .overlay(
                            Capsule().strokeBorder(
                                isPrimary
                                    ? Color.clear
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var wordCount: Int {
        store.memo.transcript.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
