//
//  DictationListView.swift
//  Talkie
//
//  Simplified utterance list without sidebar navigation
//

import SwiftUI

/// Simple list view for all Live utterances (no sidebar, for embedding in main navigation)
struct DictationListView: View {
    @State private var store = DictationStore.shared
    @State private var selectedUtteranceIDs: Set<Utterance.ID> = []
    @State private var searchText = ""
    @State private var retranscribingIDs: Set<Utterance.ID> = []

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
                                promoteToMemo(utterance)
                            } label: {
                                Label("Promote to Memo", systemImage: "arrow.up.doc")
                            }

                            if utterance.metadata.audioFilename != nil {
                                Menu {
                                    Button("whisper-small (Fast)") {
                                        retranscribe(utterance, with: "whisper:openai_whisper-small")
                                    }
                                    Button("whisper-medium") {
                                        retranscribe(utterance, with: "whisper:openai_whisper-medium")
                                    }
                                    Button("whisper-large-v3 (Best)") {
                                        retranscribe(utterance, with: "whisper:openai_whisper-large-v3")
                                    }
                                } label: {
                                    Label("Retranscribe", systemImage: "waveform.badge.magnifyingglass")
                                }
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

    private func promoteToMemo(_ utterance: Utterance) {
        let context = PersistenceController.shared.container.viewContext

        // Create new VoiceMemo with deep copy of utterance metadata
        let memo = VoiceMemo(context: context)
        memo.id = UUID()

        // Basic content
        memo.title = String(utterance.text.prefix(100)) // Use first 100 chars as title
        memo.transcription = utterance.text
        memo.createdAt = utterance.timestamp
        memo.lastModified = Date()
        memo.duration = utterance.durationSeconds ?? 0
        memo.sortOrder = Int32(-utterance.timestamp.timeIntervalSince1970)

        // Origin tracking
        memo.originDeviceId = "live" // Mark as coming from Live dictation

        // Context metadata - store in notes field
        var contextNotes: [String] = []
        if let appName = utterance.metadata.activeAppName {
            contextNotes.append("📱 App: \(appName)")
        }
        if let windowTitle = utterance.metadata.activeWindowTitle {
            contextNotes.append("🪟 Window: \(windowTitle)")
        }
        if let browserURL = utterance.metadata.browserURL {
            contextNotes.append("🌐 URL: \(browserURL)")
        } else if let documentURL = utterance.metadata.documentURL {
            contextNotes.append("📄 Document: \(documentURL)")
        }
        if let terminalDir = utterance.metadata.terminalWorkingDir {
            contextNotes.append("💻 Working Dir: \(terminalDir)")
        }

        // Performance metrics
        if let totalMs = utterance.metadata.perfEndToEndMs {
            contextNotes.append("⏱ Latency: \(totalMs)ms")
        }

        // Transcription metadata
        if let model = utterance.metadata.transcriptionModel {
            contextNotes.append("🤖 Model: \(model)")
        }

        if !contextNotes.isEmpty {
            memo.notes = """
            Promoted from Live Dictation

            \(contextNotes.joined(separator: "\n"))

            ---
            Original timestamp: \(utterance.timestamp.formatted())
            """
        }

        // Copy audio file if it exists
        if let audioFilename = utterance.metadata.audioFilename,
           let sourceURL = utterance.metadata.audioURL,
           FileManager.default.fileExists(atPath: sourceURL.path) {

            // Create destination path in Talkie's storage
            let destDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Talkie/Audio", isDirectory: true)

            // Create directory if needed
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            let destURL = destDir.appendingPathComponent(audioFilename)

            // Copy audio file
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                memo.fileURL = destURL.path
                print("[DictationListView] Copied audio file to Talkie storage")
            } catch {
                print("[DictationListView] Failed to copy audio: \(error.localizedDescription)")
                // Continue without audio
            }
        }

        // Save to CoreData
        do {
            try context.save()
            print("[DictationListView] Promoted utterance to memo with metadata: \(memo.title ?? "")")

            // Mark as promoted in Live database (updates promotionStatus and talkieMemoID)
            if let liveID = utterance.liveID, let memoID = memo.id?.uuidString {
                LiveDatabase.markAsMemo(id: liveID, talkieMemoID: memoID)
                print("[DictationListView] Marked Live #\(liveID) as promoted to memo \(memoID)")
            }

            // Show success feedback
            NSSound.beep()
        } catch {
            print("[DictationListView] Failed to save memo: \(error.localizedDescription)")
        }
    }

    private func retranscribe(_ utterance: Utterance, with modelId: String) {
        guard let audioFilename = utterance.metadata.audioFilename else {
            print("[DictationListView] Cannot retranscribe: no audio file")
            return
        }

        // Construct full audio path
        let audioPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TalkieLive/Utterances")
            .appendingPathComponent(audioFilename)
            .path

        retranscribingIDs.insert(utterance.id)

        Task {
            do {
                let engineClient = EngineClient.shared
                let newText = try await engineClient.transcribe(audioPath: audioPath, modelId: modelId)

                // Update utterance text
                await MainActor.run {
                    store.updateText(for: utterance.id, newText: newText)
                    retranscribingIDs.remove(utterance.id)
                }

                print("[DictationListView] Successfully retranscribed utterance with \(modelId)")
            } catch {
                print("[DictationListView] Failed to retranscribe: \(error.localizedDescription)")
                _ = await MainActor.run {
                    retranscribingIDs.remove(utterance.id)
                }
            }
        }
    }
}
