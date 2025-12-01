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
    @ObservedObject private var settings = SettingsManager.shared

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
                            .font(settings.fontSMBold)
                            .tracking(2)
                            .foregroundColor(.primary)

                        Text("\(voiceMemos.count) MEMOS")
                            .font(settings.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Settings button
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(settings.fontBody)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

                Divider()

                // List
                if voiceMemos.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: "waveform")
                            .font(settings.fontDisplay)
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Text("NO MEMOS")
                                .font(settings.fontSMBold)
                                .tracking(2)
                                .foregroundColor(.secondary)

                            Text("Record on iPhone to sync")
                                .font(settings.fontSM)
                                .foregroundColor(.secondary.opacity(0.7))
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
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
                        .font(settings.fontDisplay)
                        .foregroundColor(.secondary)

                    Text("Select a memo")
                        .font(settings.fontTitle)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
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
                    .font(settings.fontXSBold)
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 16)

            Spacer()

            // Right side - sync status with context
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(settings.fontXSMedium)
                        .foregroundColor(.secondary)

                    Text("SYNCED \(syncedMemoCount) \(syncedMemoCount == 1 ? "MEMO" : "MEMOS")")
                        .font(settings.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(settings.fontXSMedium)
                        .foregroundColor(.secondary)

                    Text(formatSyncTime(lastSyncTime))
                        .font(settings.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))
                }

                HStack(spacing: 6) {
                    Image(systemName: "icloud")
                        .font(settings.fontXSMedium)
                        .foregroundColor(.secondary)

                    Text("\(voiceMemos.count)")
                        .font(settings.fontXSMedium)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 28)
        .background(.ultraThinMaterial)
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
                .frame(minWidth: 900, minHeight: 600)
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
