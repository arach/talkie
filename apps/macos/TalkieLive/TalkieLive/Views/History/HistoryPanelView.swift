//
//  HistoryPanelView.swift
//  TalkieLive
//
//  Lightweight history view for quick access to recent dictations
//

import SwiftUI
import TalkieKit

struct HistoryPanelView: View {
    @ObservedObject var controller: HistoryPanelController
    let onDismiss: () -> Void

    @State private var copiedId: UUID?
    @State private var searchText = ""

    private var filteredDictations: [LiveRecording] {
        if searchText.isEmpty {
            return controller.dictations
        }
        return controller.dictations.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(TalkieTheme.border)

            // Search
            searchBar

            // Content
            if filteredDictations.isEmpty {
                emptyState
            } else {
                dictationList
            }

            Divider()
                .background(TalkieTheme.border)

            // Footer
            footer
        }
        .frame(minWidth: 380, minHeight: 400)
        .background(TalkieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Dictations")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("\(controller.dictations.count) items")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            Button(action: { controller.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .padding(6)
                    .background(Circle().fill(TalkieTheme.hover))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textTertiary)

            TextField("Search dictations...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textPrimary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TalkieTheme.surfaceElevated)
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Dictation List

    private var dictationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredDictations) { dictation in
                    DictationRow(
                        dictation: dictation,
                        isCopied: copiedId == dictation.id,
                        onCopy: {
                            controller.copyText(dictation.text)
                            copiedId = dictation.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedId == dictation.id {
                                    copiedId = nil
                                }
                            }
                        }
                    )

                    if dictation.id != filteredDictations.last?.id {
                        Divider()
                            .background(TalkieTheme.border)
                            .padding(.leading, 12)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(TalkieTheme.textTertiary)

            Text(searchText.isEmpty ? "No dictations yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TalkieTheme.textSecondary)

            Text(searchText.isEmpty ? "Start recording to see your history" : "Try a different search")
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: { controller.openInTalkie() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                    Text("Open Full History in Talkie")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("⌘H to toggle")
                .font(.system(size: 10))
                .foregroundColor(TalkieTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Dictation Row

private struct DictationRow: View {
    let dictation: LiveRecording
    let isCopied: Bool
    let onCopy: () -> Void

    @State private var isHovered = false

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: dictation.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Text preview
            VStack(alignment: .leading, spacing: 4) {
                Text(dictation.text)
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    // Time
                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)

                    // App context
                    if let appName = dictation.parsedMetadata.app?.name {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .lineLimit(1)
                    }

                    // Word count
                    let wordCount = dictation.text.split(separator: " ").count
                    if wordCount > 0 {
                        Text("\(wordCount) words")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 10, weight: .medium))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(isCopied ? SemanticColor.success : .accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCopied ? SemanticColor.success.opacity(0.15) : Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isCopied ? 1 : 0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? TalkieTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    HistoryPanelView(
        controller: HistoryPanelController.shared,
        onDismiss: {}
    )
    .frame(width: 480, height: 520)
}
