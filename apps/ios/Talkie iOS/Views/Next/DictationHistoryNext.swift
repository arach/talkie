//
//  DictationHistoryNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — keyboard dictation history. Day-grouped
//  list of dictation entries (timestamp · word count · preview),
//  per-day section headers, total counter pill in the header.
//

import Foundation
import SwiftUI

@MainActor
final class DictationHistoryFeed: ObservableObject {
    @Published var totalCount: Int
    @Published var sections: [DaySection]

    struct DaySection: Identifiable {
        let id: String  // "today" / "yesterday" / "mon-04-21"
        let label: String
        let entries: [Entry]
    }

    struct Entry: Identifiable {
        let id: String
        let timestamp: String     // "9:34 AM"
        let preview: String
        let wordCount: Int
        // NOTE: KeyboardDictation in the donor doesn't track the
        // source app; the per-app tag was invented. Left off until
        // / unless the data layer actually carries it.
    }

    init() {
        self.sections = Self.mockSections
        self.totalCount = Self.mockSections.flatMap { $0.entries }.count
    }

    static let mockSections: [DaySection] = [
        DaySection(id: "today", label: "Today", entries: [
            Entry(id: "t1", timestamp: "9:34 AM", preview: "thanks for the breakdown — let's talk through it tomorrow", wordCount: 11),
            Entry(id: "t2", timestamp: "8:12 AM", preview: "moving the meeting to 4pm if that works for everyone", wordCount: 10),
            Entry(id: "t3", timestamp: "7:51 AM", preview: "need to refactor the auth flow before we ship the migration", wordCount: 11),
        ]),
        DaySection(id: "yesterday", label: "Yesterday", entries: [
            Entry(id: "y1", timestamp: "4:22 PM", preview: "quick reminder to drop the docs in the channel", wordCount: 9),
            Entry(id: "y2", timestamp: "11:08 AM", preview: "the api rate limits hit us again on the analytics export", wordCount: 11),
        ]),
        DaySection(id: "mon", label: "Monday", entries: [
            Entry(id: "m1", timestamp: "3:14 PM", preview: "follow up on the figma comments before standup tomorrow", wordCount: 9),
        ]),
    ]
}

struct DictationHistoryNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var feed = DictationHistoryFeed()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(feed.sections) { section in
                        sectionView(section)
                            .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Dictations")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text("\(feed.totalCount)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(theme.currentTheme.chrome.accentTint)
                )
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

    private func sectionView(_ section: DictationHistoryFeed.DaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("· \(section.label.uppercased())")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                Text("\(section.entries.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { idx, entry in
                    entryRow(entry, showDivider: idx > 0)
                }
            }
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
    }

    private func entryRow(_ entry: DictationHistoryFeed.Entry, showDivider: Bool) -> some View {
        Button(action: {
            // Dictations are typed-text — route to a compose surface
            // seeded with the dictation's text. ID maps to the
            // KeyboardDictation entity via ComposeStore lookup.
            AppShellRouter.shared.openCompose(documentID: entry.id)
        }) {
            VStack(spacing: 0) {
                if showDivider {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeSubtle)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                        .padding(.leading, 14)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(entry.timestamp)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 60, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.preview)
                            .font(.system(size: 13.5))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(2)
                            .tracking(-0.05)

                        Text("\(entry.wordCount) words")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.colors.textTertiary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}
