//
//  VoiceMemoListView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

struct VoiceMemoListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default)
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
                    }
                    .listStyle(.insetGrouped)

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
            if let urlString = memo.fileURL,
               let url = URL(string: urlString),
               FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
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
}

#Preview {
    VoiceMemoListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
