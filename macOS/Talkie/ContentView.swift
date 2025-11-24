//
//  ContentView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var voiceMemos: FetchedResults<VoiceMemo>

    @State private var selectedMemo: VoiceMemo?

    var body: some View {
        NavigationSplitView {
            // Sidebar - List of memos
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TALKIE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.primary)

                        Text("\(voiceMemos.count) MEMOS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // List
                if voiceMemos.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: "waveform")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Text("NO MEMOS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.secondary)

                            Text("Record on iPhone to sync")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                } else {
                    List(selection: $selectedMemo) {
                        ForEach(voiceMemos) { memo in
                            MemoRowView(memo: memo)
                                .tag(memo)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 280)
        } detail: {
            // Detail view
            if let selectedMemo = selectedMemo {
                MemoDetailView(memo: selectedMemo)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundColor(.secondary)

                    Text("Select a memo")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
