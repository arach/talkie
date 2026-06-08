//
//  HistorySection.swift
//  TalkieAgent
//
//  History view for the settings panel sidebar
//

import SwiftUI
import TalkieKit

struct HistorySection: View {
    @State private var dictations: [LiveRecording] = []
    @State private var copiedId: UUID?
    @State private var searchText = ""

    private var filteredDictations: [LiveRecording] {
        if searchText.isEmpty {
            return dictations
        }
        return dictations.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Search
            searchBar

            Divider()
                .background(TalkieTheme.border)

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
        .onAppear {
            refresh()
        }
    }

    // MARK: - Actions

    private func refresh() {
        dictations = UnifiedDatabase.recentDictations(limit: 100)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundManager.shared.playPasted()
    }

    private func openInTalkie() {
        let scheme = TalkieEnvironment.current.talkieURLScheme
        guard let url = URL(string: "\(scheme)://agent/recent") else { return }
        TalkieAppOpener.open(url)
    }

    private func openDictationInTalkie(_ id: UUID) {
        let scheme = TalkieEnvironment.current.talkieURLScheme
        guard let url = URL(string: "\(scheme)://agent/dictation?id=\(id.uuidString)") else { return }
        TalkieAppOpener.open(url)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Dictations")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("\(dictations.count) items")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
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
                    HistoryDictationRow(
                        dictation: dictation,
                        isCopied: copiedId == dictation.id,
                        onCopy: {
                            copyText(dictation.text)
                            copiedId = dictation.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedId == dictation.id {
                                    copiedId = nil
                                }
                            }
                        },
                        onOpenInTalkie: {
                            openDictationInTalkie(dictation.id)
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
            Button(action: openInTalkie) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                    Text("Open in Talkie")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - History Dictation Row

struct HistoryDictationRow: View {
    let dictation: LiveRecording
    let isCopied: Bool
    let onCopy: () -> Void
    let onOpenInTalkie: () -> Void

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

            // Action buttons
            HStack(spacing: 6) {
                // Open in Talkie (shown on hover)
                if isHovered {
                    Button(action: onOpenInTalkie) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textSecondary)
                            .padding(5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(TalkieTheme.hover)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Open in Talkie")
                }

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
    HistorySection()
        .frame(width: 400, height: 500)
}
