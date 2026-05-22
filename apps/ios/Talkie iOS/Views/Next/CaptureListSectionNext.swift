//
//  CaptureListSectionNext.swift
//  Talkie iOS
//
//  List section that surfaces captures (text / url / photo) from
//  CaptureStore with sync state, an unsynced-count badge in the
//  section header, a Sync-all CTA, and swipe-to-delete rows. Painted
//  per the C2 painter contract: init(store:onSelect:onSyncAll:onDelete:).
//  Codex-c2 wires the callbacks to CaptureStore + CaptureSyncService.
//

import SwiftUI
import TalkieMobileKit

struct CaptureListSectionNext: View {
    let store: CaptureStore
    let onSelect: (Capture) -> Void
    let onSyncAll: () -> Void
    let onDelete: (Capture) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var captures: [Capture] = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if captures.isEmpty {
                EmptyCapturesState()
                    .padding(.vertical, 24)
            } else {
                List {
                    ForEach(captures) { capture in
                        CaptureRowNext(capture: capture)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(capture) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(capture)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(captures.count) * 64)
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            reload()
        }
    }

    private var unsyncedCount: Int {
        captures.filter { !$0.syncedToMac }.count
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("· CAPTURES")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .textCase(.uppercase)

            if unsyncedCount > 0 {
                Text("\(unsyncedCount) UNSYNCED")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer()

            if unsyncedCount > 0 {
                Button(action: onSyncAll) {
                    Text("SYNC ALL")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reload() {
        store.reload()
        captures = store.all()
    }
}

// MARK: - Row

private struct CaptureRowNext: View {
    let capture: Capture

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Source icon
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: sourceIcon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Text(metaLine)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .textCase(.uppercase)
            }

            Spacer()

            // Sync indicator
            Image(systemName: capture.syncedToMac ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(
                    capture.syncedToMac
                        ? theme.currentTheme.chrome.accent
                        : theme.colors.textTertiary
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeSubtle)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }

    private var sourceIcon: String {
        switch capture.sourceType {
        case "url": return "globe"
        case "photo": return "photo"
        default: return "doc.text"
        }
    }

    private var displayTitle: String {
        if let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled capture" : String(text.prefix(64))
    }

    private var metaLine: String {
        let kind = capture.sourceType.uppercased()
        let sync = capture.syncedToMac ? "SYNCED" : "PENDING"
        let count = capture.wordCount > 0 ? "\(capture.wordCount) WORDS" : nil
        return [kind, sync, count].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Empty state

private struct EmptyCapturesState: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "viewfinder")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No captures yet")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Text("Scan a page, save a link, or grab text to start.")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}
