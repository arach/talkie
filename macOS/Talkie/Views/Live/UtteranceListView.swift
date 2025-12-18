//
//  UtteranceListView.swift
//  Talkie
//
//  Simplified utterance list without sidebar navigation
//

import SwiftUI

/// Simple list view for all Live utterances (no sidebar, for embedding in main navigation)
struct UtteranceListView: View {
    @ObservedObject private var store = UtteranceStore.shared
    @State private var selectedUtteranceIDs: Set<Utterance.ID> = []
    @State private var searchText = ""

    private var filteredUtterances: [Utterance] {
        guard !searchText.isEmpty else {
            return store.utterances
        }
        return store.utterances.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedUtterance: Utterance? {
        guard let firstID = selectedUtteranceIDs.first else { return nil }
        return filteredUtterances.first { $0.id == firstID }
    }

    var body: some View {
        HSplitView {
            // Left: List of utterances
            listColumn
                .frame(minWidth: 300, idealWidth: 400)

            // Right: Detail view
            detailColumn
                .frame(minWidth: 300)
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            // Search
            SidebarSearchField(text: $searchText, placeholder: "Search transcripts...")

            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(height: 0.5)

            // Utterance list
            if filteredUtterances.isEmpty {
                emptyState
            } else {
                List(filteredUtterances, selection: $selectedUtteranceIDs) { utterance in
                    UtteranceRowView(utterance: utterance)
                        .tag(utterance.id)
                        .contextMenu {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(utterance.text, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button {
                                // TODO: Promote to Talkie Core memo
                            } label: {
                                Label("Promote to Memo", systemImage: "arrow.up.doc")
                            }

                            Button {
                                // TODO: Re-transcribe with better model
                            } label: {
                                Label("Enhance", systemImage: "waveform.badge.magnifyingglass")
                            }

                            Button {
                                let text = utterance.text
                                let picker = NSSharingServicePicker(items: [text])
                                if let window = NSApp.keyWindow, let contentView = window.contentView {
                                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                                }
                            } label: {
                                Label("Share...", systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                withAnimation {
                                    selectedUtteranceIDs.remove(utterance.id)
                                    store.delete(utterance)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    selectedUtteranceIDs.remove(utterance.id)
                                    store.delete(utterance)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .background(TalkieTheme.surface)
    }

    private var detailColumn: some View {
        Group {
            if let utterance = selectedUtterance {
                UtteranceDetailView(utterance: utterance)
            } else {
                emptyDetailState
            }
        }
        .background(TalkieTheme.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.3))

            Text("No recordings found")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TalkieTheme.textSecondary)

            if !searchText.isEmpty {
                Text("Try a different search")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.3))
            Text("Select a recording")
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
