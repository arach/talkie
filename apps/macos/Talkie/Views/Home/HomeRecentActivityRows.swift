//
//  HomeRecentActivityRows.swift
//  Talkie
//
//  Recent memo and dictation rows for Home cards.
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Memo Activity Row

struct MemoActivityRow: View {
    let memo: MemoModel
    var onSelect: (() -> Void)?

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: 8) {
                // Provenance icon (where it came from)
                Image(systemName: memo.source.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .frame(width: 20, height: 20)

                // Title/Preview
                Text(memoTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                Spacer()

                // Duration
                if memo.duration > 0 {
                    Text(formatDuration(memo.duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.current.foregroundMuted)
                }

                // Time ago
                Text(timeAgo(from: memo.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.current.foregroundMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.current.foregroundMuted.opacity(0.6))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Spacing.cardInset)
            .padding(.horizontal, -Spacing.cardInset)
            .background(HomeHoverChrome(style: .standardRow(cornerRadius: 8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.transcription ?? "", forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                let text = memo.transcription ?? ""
                let picker = NSSharingServicePicker(items: [text])
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                }
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                Task { await MemosViewModel.shared.deleteMemo(memo) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let paddedSeconds = secs.formatted(.number.precision(.integerLength(2)))
        if mins > 0 {
            return "\(mins):\(paddedSeconds)"
        }
        return "0:\(paddedSeconds)"
    }

    private var memoTitle: String {
        if let title = memo.title, !title.isEmpty {
            return title
        } else if let transcription = memo.transcription, !transcription.isEmpty {
            return String(transcription.prefix(60))
        }
        return "Untitled Memo"
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Dictation Activity Row

struct DictationActivityRow: View {
    let dictation: Dictation
    var onSelect: (() -> Void)?

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: 8) {
                // App icon - larger now without status dot
                Group {
                    if let bundleID = dictation.metadata.activeAppBundleID {
                        AppIconView(bundleIdentifier: bundleID, size: 20)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.current.foregroundMuted)
                            .frame(width: 20, height: 20)
                    }
                }

                // Text preview
                Text(dictation.text.isEmpty ? "No transcription" : String(dictation.text.prefix(60)))
                    .font(.system(size: 12))
                    .foregroundStyle(dictation.text.isEmpty ? Theme.current.foregroundMuted : Theme.current.foreground)
                    .lineLimit(1)

                Spacer()

                // Time ago
                Text(timeAgo(from: dictation.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.current.foregroundMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.current.foregroundMuted.opacity(0.6))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Spacing.cardInset)
            .padding(.horizontal, -Spacing.cardInset)
            .background(HomeHoverChrome(style: .standardRow(cornerRadius: 8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dictation.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                Task {
                    _ = try? await TalkieObjectRepository().promoteToMemo(id: dictation.id)
                    DictationStore.shared.refresh()
                }
            } label: {
                Label("Promote to Memo", systemImage: "arrow.up.doc")
            }

            Button {
                let picker = NSSharingServicePicker(items: [dictation.text])
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                }
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                DictationStore.shared.delete(dictation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
