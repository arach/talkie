//
//  DictationListView.swift
//  Talkie
//
//  Live dictations list - harmonized with AllMemos view
//

import SwiftUI

/// List view for all Live dictations (harmonized with AllMemos design)
struct DictationListView: View {
    // Use let for singletons - we subscribe to remote data, we don't own it
    private let store = DictationStore.shared
    @State private var selectedDictationIDs: Set<Dictation.ID> = []
    @State private var searchText = ""
    @State private var retranscribingIDs: Set<Dictation.ID> = []
    @State private var lastClickedID: Dictation.ID?

    // Onboarding state
    @AppStorage("hasDismissedDictationOnboarding") private var hasDismissedOnboarding = false
    @State private var showOnboarding = false

    /// Show onboarding when user has no dictations and hasn't dismissed it
    private var shouldShowOnboarding: Bool {
        store.dictations.isEmpty && !hasDismissedOnboarding && searchText.isEmpty
    }

    private var filteredDictations: [Dictation] {
        guard !searchText.isEmpty else {
            return store.dictations
        }
        return store.dictations.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedDictation: Dictation? {
        guard selectedDictationIDs.count == 1, let firstID = selectedDictationIDs.first else { return nil }
        return filteredDictations.first { $0.id == firstID }
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                // Show onboarding for new users with 0 dictations
                DictationOnboardingView(
                    onComplete: {
                        hasDismissedOnboarding = true
                    },
                    onSkip: {
                        hasDismissedOnboarding = true
                    }
                )
            } else {
                // Normal dictation list view
                mainContent
            }
        }
        .task {
            // Load last 50 dictations in background when navigating to page
            // Non-blocking - page renders immediately, data loads async
            store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SelectDictation"))) { notification in
            if let dictationID = notification.object as? UUID {
                selectedDictationIDs = [dictationID]
            }
        }
    }

    private var mainContent: some View {
        HSplitView {
            // Left: List of dictations
            listColumn
                .frame(minWidth: 300, idealWidth: 450)

            // Right: Detail view
            detailColumn
                .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
        }
        // Note: Audio drop is handled at app level (NavigationViewNative)
    }

    // MARK: - Selection Handling

    private func handleSelection(dictation: Dictation, event: NSEvent?) {
        let id = dictation.id

        if let event = event {
            if event.modifierFlags.contains(.command) {
                // Cmd+click: Toggle selection
                if selectedDictationIDs.contains(id) {
                    selectedDictationIDs.remove(id)
                } else {
                    selectedDictationIDs.insert(id)
                }
            } else if event.modifierFlags.contains(.shift), let lastID = lastClickedID {
                // Shift+click: Range selection
                if let lastIndex = filteredDictations.firstIndex(where: { $0.id == lastID }),
                   let currentIndex = filteredDictations.firstIndex(where: { $0.id == id }) {
                    let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                    for i in range {
                        selectedDictationIDs.insert(filteredDictations[i].id)
                    }
                }
            } else {
                // Regular click: Single selection
                selectedDictationIDs = [id]
            }
        } else {
            // No event (keyboard nav): Single selection
            selectedDictationIDs = [id]
        }

        lastClickedID = id
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            // Header with search
            headerView

            // Dictation list
            if filteredDictations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredDictations) { dictation in
                            DictationRowEnhanced(
                                dictation: dictation,
                                isSelected: selectedDictationIDs.contains(dictation.id),
                                isMultiSelected: selectedDictationIDs.count > 1,
                                onSelect: { event in
                                    handleSelection(dictation: dictation, event: event)
                                }
                            )
                            .id(dictation.id)
                            .contextMenu {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(dictation.text, forType: .string)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }

                                Divider()

                                Button {
                                    promoteToMemo(dictation)
                                } label: {
                                    Label("Promote to Memo", systemImage: "arrow.up.doc")
                                }

                                if dictation.metadata.audioFilename != nil {
                                    Menu {
                                        Section("Parakeet (Recommended)") {
                                            Button("Parakeet v3 (Fast, 25 languages)") {
                                                retranscribe(dictation, with: "parakeet:v3")
                                            }
                                            Button("Parakeet v2 (English, most accurate)") {
                                                retranscribe(dictation, with: "parakeet:v2")
                                            }
                                        }

                                        Divider()

                                        Section("Whisper") {
                                            Button("whisper-small (Fast)") {
                                                retranscribe(dictation, with: "whisper:openai_whisper-small")
                                            }
                                            Button("whisper-large-v3 (Best)") {
                                                retranscribe(dictation, with: "whisper:openai_whisper-large-v3")
                                            }
                                        }
                                    } label: {
                                        Label("Retranscribe", systemImage: "waveform.badge.magnifyingglass")
                                    }
                                }

                                Button {
                                    let text = dictation.text
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
                                        selectedDictationIDs.remove(dictation.id)
                                        store.delete(dictation)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            // Footer
            footerView
        }
        .background(TalkieTheme.surface)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                // Search
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(TalkieTheme.textMuted)
                        .font(Theme.current.fontSM)

                    TextField("Search dictations...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TalkieTheme.textMuted)
                                .font(Theme.current.fontSM)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(TalkieTheme.surfaceCard)
                .cornerRadius(6)

                Spacer()

                // Count
                Text("\(filteredDictations.count) dictations")
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
            }
            .padding(12)

            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)
        }
        .background(TalkieTheme.surfaceElevated)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if selectedDictationIDs.count > 1 {
                Text("\(selectedDictationIDs.count) selected")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(.accentColor)

                Spacer()

                Button {
                    selectedDictationIDs.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(Theme.current.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(TalkieTheme.textMuted)
            } else {
                Text("\(filteredDictations.count) dictations")
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
                Spacer()
            }
        }
        .padding(8)
        .background(TalkieTheme.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var detailColumn: some View {
        Group {
            if selectedDictationIDs.count > 1 {
                // Multi-select state
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor.opacity(Opacity.half))

                    Text("\(selectedDictationIDs.count) DICTATIONS SELECTED")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Cmd+click to toggle, Shift+click for range")
                        .font(Theme.current.fontSM)
                        .foregroundColor(TalkieTheme.textMuted)

                    HStack(spacing: Spacing.sm) {
                        Button {
                            selectedDictationIDs.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let dictation = selectedDictation {
                DictationDetailView(dictation: dictation)
            } else {
                emptyDetailState
            }
        }
        .background(TalkieTheme.surface)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.borderSubtle)
                .frame(width: 1),
            alignment: .leading
        )
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(TalkieTheme.textMuted.opacity(Opacity.strong))

            Text("No recordings found")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)

            if !searchText.isEmpty {
                Text("Try a different search")
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(Opacity.strong))
            Text("Select a recording")
                .font(Theme.current.fontSM)
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promoteToMemo(_ dictation: Dictation) {
        let context = PersistenceController.shared.container.viewContext

        // Create new VoiceMemo with deep copy of dictation metadata
        let memo = VoiceMemo(context: context)
        memo.id = UUID()

        // Basic content
        memo.title = String(dictation.text.prefix(100)) // Use first 100 chars as title
        memo.transcription = dictation.text
        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.sortOrder = Int32(-dictation.timestamp.timeIntervalSince1970)

        // Origin tracking
        memo.originDeviceId = "live" // Mark as coming from Live dictation

        // Context metadata - store in notes field
        var contextNotes: [String] = []
        if let appName = dictation.metadata.activeAppName {
            contextNotes.append("📱 App: \(appName)")
        }
        if let windowTitle = dictation.metadata.activeWindowTitle {
            contextNotes.append("🪟 Window: \(windowTitle)")
        }
        if let browserURL = dictation.metadata.browserURL {
            contextNotes.append("🌐 URL: \(browserURL)")
        } else if let documentURL = dictation.metadata.documentURL {
            contextNotes.append("📄 Document: \(documentURL)")
        }
        if let terminalDir = dictation.metadata.terminalWorkingDir {
            contextNotes.append("💻 Working Dir: \(terminalDir)")
        }

        // Performance metrics
        if let totalMs = dictation.metadata.perfEndToEndMs {
            contextNotes.append("⏱ Latency: \(totalMs)ms")
        }

        // Transcription metadata
        if let model = dictation.metadata.transcriptionModel {
            contextNotes.append("🤖 Model: \(model)")
        }

        if !contextNotes.isEmpty {
            memo.notes = """
            Promoted from Live Dictation

            \(contextNotes.joined(separator: "\n"))

            ---
            Original timestamp: \(dictation.timestamp.formatted())
            """
        }

        // Copy audio file if it exists
        if let audioFilename = dictation.metadata.audioFilename,
           let sourceURL = dictation.metadata.audioURL,
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
            print("[DictationListView] Promoted dictation to memo with metadata: \(memo.title ?? "")")

            // Mark as promoted in Live database (updates promotionStatus and talkieMemoID)
            if let liveID = dictation.liveID, let memoID = memo.id?.uuidString {
                LiveDatabase.markAsMemo(id: liveID, talkieMemoID: memoID)
                print("[DictationListView] Marked Live #\(liveID) as promoted to memo \(memoID)")
            }

            // Show success feedback
            NSSound.beep()
        } catch {
            print("[DictationListView] Failed to save memo: \(error.localizedDescription)")
        }
    }

    private func retranscribe(_ dictation: Dictation, with modelId: String) {
        guard let audioFilename = dictation.metadata.audioFilename else {
            print("[DictationListView] Cannot retranscribe: no audio file")
            return
        }

        // Construct full audio path using shared AudioStorage location
        let audioPath = AudioStorage.audioDirectory
            .appendingPathComponent(audioFilename)
            .path

        retranscribingIDs.insert(dictation.id)

        Task {
            do {
                let engineClient = EngineClient.shared
                let newText = try await engineClient.transcribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    priority: .userInitiated  // User clicked re-transcribe button
                )

                // Update dictation text and model
                await MainActor.run {
                    store.updateText(for: dictation.id, newText: newText, modelId: modelId)
                    retranscribingIDs.remove(dictation.id)
                }

                print("[DictationListView] Successfully retranscribed dictation with \(modelId)")
            } catch {
                print("[DictationListView] Failed to retranscribe: \(error.localizedDescription)")
                _ = await MainActor.run {
                    retranscribingIDs.remove(dictation.id)
                }
            }
        }
    }
}

// MARK: - Enhanced Dictation Row (Harmonized with MemoRowEnhanced)

struct DictationRowEnhanced: View {
    let dictation: Dictation
    let isSelected: Bool
    let isMultiSelected: Bool
    let onSelect: (NSEvent?) -> Void

    @State private var isHovering = false

    /// First ~60 chars of transcript as "title"
    private var displayTitle: String {
        let text = dictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= 60 {
            return text
        }
        let truncated = String(text.prefix(60))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    /// Rest of transcript as preview
    private var previewText: String? {
        let text = dictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 60 else { return nil }
        let remaining = String(text.dropFirst(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.count <= 80 {
            return remaining
        }
        let truncated = String(remaining.prefix(80))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Leading: App icon or Live icon
            leadingIcon

            // Main content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Title row
                HStack {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TalkieTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Relative time (minutes only, then actual time after 1h)
                    Text(formatTimeAgo(dictation.timestamp))
                        .font(Theme.current.fontSM)
                        .foregroundColor(TalkieTheme.textMuted)
                }

                // Preview + metadata
                HStack(spacing: Spacing.xs) {
                    if let preview = previewText {
                        Text(preview)
                            .font(Theme.current.fontSM)
                            .foregroundColor(TalkieTheme.textMuted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }

                    // Duration badge
                    if let duration = dictation.durationSeconds {
                        durationBadge(duration)
                    }
                }
            }

        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border.opacity(0.5))
                .frame(height: 1),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect(NSApp.currentEvent)
        }
    }

    // MARK: - Subviews

    private var leadingIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconColor.opacity(Opacity.medium))
                .frame(width: 36, height: 36)

            if let bundleID = dictation.metadata.activeAppBundleID {
                AppIconView(bundleIdentifier: bundleID, size: 28)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }
        }
    }

    private var iconColor: Color {
        // Use cyan for Live dictations (matches MemoModel.Source.live.color)
        .cyan
    }

    private func durationBadge(_ duration: Double) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "waveform")
                .font(.system(size: 9))
            Text(formatDuration(duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundColor(TalkieTheme.textMuted)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(TalkieTheme.surfaceCard)
        .cornerRadius(4)
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(Opacity.medium)
            } else if isHovering {
                TalkieTheme.surfaceCard.opacity(Opacity.half)
            } else {
                Color.clear
            }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Relative time: minutes only, then actual time after 1 hour
    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)

        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            // Less than 1 hour: show minutes only
            return "\(seconds / 60)m"
        } else {
            // 1 hour or more: show actual time
            let formatter = DateFormatter()
            let calendar = Calendar.current

            if calendar.isDateInToday(date) {
                formatter.dateFormat = "h:mm a"  // "2:30 PM"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                formatter.dateFormat = "MMM d"  // "Dec 22"
            }

            return formatter.string(from: date)
        }
    }
}
