//
//  VoiceMemoListView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

enum SortOption: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case title = "Title (A-Z)"
    case duration = "Duration"

    var descriptor: NSSortDescriptor {
        switch self {
        case .dateNewest:
            return NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        case .dateOldest:
            return NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: true)
        case .title:
            return NSSortDescriptor(keyPath: \VoiceMemo.title, ascending: true)
        case .duration:
            return NSSortDescriptor(keyPath: \VoiceMemo.duration, ascending: false)
        }
    }

    var menuIcon: String {
        switch self {
        case .dateNewest: return "arrow.down"
        case .dateOldest: return "arrow.up"
        case .title: return "textformat"
        case .duration: return "clock"
        }
    }
}

struct VoiceMemoListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var voiceMemos: FetchedResults<VoiceMemo>

    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showingRecordingView = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                if voiceMemos.isEmpty {
                    // Empty state
                    EmptyStateView(onRecordTapped: {
                        showingRecordingView = true
                    })
                } else {
                    // List of voice memos
                    List {
                        ForEach(voiceMemos) { memo in
                            VoiceMemoRow(
                                memo: memo,
                                audioPlayer: audioPlayer,
                                onDelete: { deleteMemo(memo) }
                            )
                        }
                        .onDelete(perform: deleteMemos)
                        .onMove(perform: moveMemos)
                    }
                    .listStyle(.plain)

                    // Floating record button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingRecordingView = true }) {
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 70, height: 70)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.red, Color.red.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(Circle())
                                    .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Voice Memos")
            .sheet(isPresented: $showingRecordingView) {
                RecordingView()
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func deleteMemo(_ memo: VoiceMemo) {
        withAnimation {
            // Delete audio file
            if let filename = memo.fileURL {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filePath = documentsPath.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filePath.path) {
                    try? FileManager.default.removeItem(at: filePath)
                }
            }

            viewContext.delete(memo)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Error deleting memo: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteMemos(offsets: IndexSet) {
        withAnimation {
            offsets.map { voiceMemos[$0] }.forEach { memo in
                deleteMemo(memo)
            }
        }
    }

    private func moveMemos(from source: IndexSet, to destination: Int) {
        // Get memos to move
        var memos = voiceMemos
        memos.move(fromOffsets: source, toOffset: destination)

        // Update sortOrder for all memos
        for (index, memo) in memos.enumerated() {
            memo.sortOrder = Int32(index)
        }

        do {
            try viewContext.save()
        } catch {
            print("Error moving memos: \(error)")
        }
    }
}

#Preview {
    VoiceMemoListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
