//
//  DictationHistoryNext.swift
//  Talkie iOS
//
//  Faithful port of DictationListSection (DictationHistoryView.swift,
//  ~line 285). Flat list with pagination, swipe actions, inline copy,
//  empty state. Each row shows the cursor-ibeam badge + 1-line text
//  + `duration · timestamp` footer.
//
//  Donor differences carried across:
//  - Tap opens Compose seeded with the dictation id (M3 wire added
//    KeyboardDictation lookup to ComposeStore). Donor opens a
//    DictationDetailView in a sheet; deferred until that has a Next
//    counterpart.
//  - Swipe-leading "Save as memo" + swipe-trailing "Delete" closures
//    are paint-side TODOs. Codex wires the side effects (promoteToMemo
//    + deletion) when they're scoped.
//

import Foundation
import SwiftUI
import TalkieMobileKit

@MainActor
final class DictationHistoryFeed: ObservableObject {
    @Published private(set) var entries: [Entry]
    @Published var displayLimit: Int = 10

    struct Entry: Identifiable {
        let id: String
        let text: String
        let timestamp: Date
        let durationSeconds: Double?
    }

    init() {
        // Codex wires the live load against KeyboardDictationStore.
        // For paint, return a small mock so the list renders.
        self.entries = Self.mockEntries
    }

    var displayed: [Entry] { Array(entries.prefix(displayLimit)) }
    var hasMore: Bool      { entries.count > displayLimit }
    var totalCount: Int    { entries.count }

    static let mockEntries: [Entry] = [
        Entry(id: "1", text: "thanks for the breakdown — let's talk through it tomorrow", timestamp: Date().addingTimeInterval(-3600), durationSeconds: 8),
        Entry(id: "2", text: "moving the meeting to 4pm if that works for everyone", timestamp: Date().addingTimeInterval(-7200), durationSeconds: 6),
        Entry(id: "3", text: "need to refactor the auth flow before we ship the migration", timestamp: Date().addingTimeInterval(-10800), durationSeconds: 9),
        Entry(id: "4", text: "quick reminder to drop the docs in the channel", timestamp: Date().addingTimeInterval(-86400), durationSeconds: nil),
        Entry(id: "5", text: "the api rate limits hit us again on the analytics export", timestamp: Date().addingTimeInterval(-90000), durationSeconds: 7),
    ]
}

struct DictationHistoryNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var feed = DictationHistoryFeed()

    var body: some View {
        VStack(spacing: 0) {
            header

            if feed.entries.isEmpty {
                emptyState
            } else {
                listBody
            }
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
                .background(Capsule().fill(theme.currentTheme.chrome.accentTint))
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

    // MARK: - List (matches donor's List + swipeActions)

    private var listBody: some View {
        List {
            ForEach(feed.displayed) { entry in
                DictationEntryRow(entry: entry)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(theme.colors.cardBackground)
                    .listRowSeparatorTint(theme.currentTheme.chrome.edgeSubtle)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AppShellRouter.shared.openCompose(documentID: entry.id)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            // TODO M3+ wire: promote to VoiceMemo.
                        } label: {
                            Label("Save as memo", systemImage: "square.and.arrow.down.fill")
                        }
                        .tint(theme.currentTheme.chrome.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            // TODO M3+ wire: delete dictation.
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
            }

            if feed.hasMore {
                Button(action: {
                    withAnimation { feed.displayLimit += 10 }
                }) {
                    HStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Load \(min(10, feed.entries.count - feed.displayLimit)) more")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.vertical, 14)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(theme.colors.cardBackground)
                .listRowSeparatorTint(theme.currentTheme.chrome.edgeSubtle)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state (matches donor)

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text("· NO DICTATIONS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.colors.textTertiary)
            Text("Use the keyboard to add dictations")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Row (cursor-ibeam badge + text + duration·timestamp + copy)

private struct DictationEntryRow: View {
    let entry: DictationHistoryFeed.Entry
    @ObservedObject private var theme = ThemeManager.shared
    @State private var showCopied = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d h:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Type badge — cursor-ibeam in a soft circle (matches donor)
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.colors.background))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if let duration = entry.durationSeconds, duration > 0 {
                        Text(formatDuration(duration))
                        Text("  \u{00B7}  ").foregroundStyle(theme.colors.textTertiary.opacity(0.5))
                    }
                    Text(formatTimestamp(entry.timestamp))
                    Spacer()
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.colors.textTertiary)
            }

            Button(action: copyText) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(showCopied ? .green : theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func copyText() {
        UIPasteboard.general.string = entry.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }
}
