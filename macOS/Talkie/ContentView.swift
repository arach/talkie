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
    @State private var lastSyncTime: Date = Date()
    @State private var syncedMemoCount: Int = 0
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
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

                    // Settings button
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
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

        // Tactical Status Bar
        HStack(spacing: 0) {
            // Left side - connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text("CONNECTED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 16)

            Spacer()

            // Right side - sync status with context
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("SYNCED \(syncedMemoCount) \(syncedMemoCount == 1 ? "MEMO" : "MEMOS")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(formatSyncTime(lastSyncTime))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }

                HStack(spacing: 6) {
                    Image(systemName: "icloud")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("\(voiceMemos.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 28)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 0.5),
            alignment: .top
        )
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            DispatchQueue.main.async {
                lastSyncTime = Date()
                syncedMemoCount = voiceMemos.count
            }
        }
        .onAppear {
            syncedMemoCount = voiceMemos.count
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }

    private func formatSyncTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 5 {
            return "JUST NOW"
        } else if seconds < 60 {
            return "\(seconds)S AGO"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)M AGO"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
