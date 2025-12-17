//
//  HistoryView.swift
//  TalkieLive
//
//  Main window showing utterance history - matches macOS Talkie style
//

import SwiftUI
import Carbon.HIToolbox
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Safe AVMetadata helpers

private extension AVURLAsset {
    func safeLoadMetadata() async -> [(String, String)] {
        do {
            let items = try await load(.metadata)
            return await items.asyncCompactMap { item in
                guard let key = item.commonKey?.rawValue ?? item.key as? String,
                      let value = try? await item.load(.stringValue),
                      !value.isEmpty else { return nil }
                return (key, value)
            }
        } catch {
            return []
        }
    }

    func safeLoadMetadata(for format: AVMetadataFormat) async -> [(String, String)] {
        do {
            let items = try await loadMetadata(for: format)
            return await items.asyncCompactMap { item in
                guard let key = item.key as? String,
                      let value = try? await item.load(.stringValue),
                      !value.isEmpty else { return nil }
                return (key, value)
            }
        } catch {
            return []
        }
    }
}

private extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            if let value = try await transform(element) {
                results.append(value)
            }
        }
        return results
    }
}

// MARK: - Main Navigation View

struct LiveNavigationView: View {
    @ObservedObject private var store = UtteranceStore.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: LiveNavigationSection? = .home
    @State private var selectedUtteranceIDs: Set<Utterance.ID> = []  // Multi-select support
    @State private var settingsSection: SettingsSection? = nil  // Deep link to specific settings section
    @State private var searchText = ""
    @State private var isSidebarCollapsed: Bool = false
    @State private var isChevronHovered: Bool = false
    @State private var isChevronPressed: Bool = false
    @State private var appFilter: String? = nil  // Filter by app name

    // Drop zone state
    @State private var isDropTargeted = false
    @State private var dropMessage: String?
    @State private var isTranscribingDrop = false

    private var filteredUtterances: [Utterance] {
        var result = store.utterances

        // Apply section-based filters (Queue, Today)
        switch selectedSection {
        case .queue:
            // Items created in Talkie view that haven't been pasted yet
            result = result.filter { utterance in
                guard let liveID = utterance.liveID,
                      let live = LiveDatabase.fetch(id: liveID) else { return false }
                return live.createdInTalkieView && live.pasteTimestamp == nil
            }
        case .today:
            // Items from today
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            result = result.filter { $0.timestamp >= startOfToday }
        default:
            break
        }

        // Apply app filter
        if let appFilter = appFilter {
            result = result.filter { $0.metadata.activeAppName == appFilter }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    /// Selected utterances for batch operations
    private var selectedUtterances: [Utterance] {
        filteredUtterances.filter { selectedUtteranceIDs.contains($0.id) }
    }

    /// Single selected utterance for detail view (uses first selected if multi)
    private var selectedUtterance: Utterance? {
        guard let firstID = selectedUtteranceIDs.first else { return nil }
        return filteredUtterances.first { $0.id == firstID }
    }

    /// Sections that need full-width (no detail column)
    /// History-based sections (Recent, Queue, Today) show detail column; others are full-width
    private var needsFullWidth: Bool {
        !(selectedSection?.isHistoryBased ?? false)
    }

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 56 : 180
    }

    var body: some View {
        HStack(spacing: 0) {
            // Full-height sidebar
            sidebarContent
                .frame(width: sidebarWidth)

            // Subtle divider between sidebar and content
            Rectangle()
                .fill(TalkieTheme.border.opacity(0.5))
                .frame(width: 1)

            // Main content area with StatusBar at bottom
            VStack(spacing: 0) {
                // Content/detail area
                if needsFullWidth {
                    fullWidthContentView
                } else {
                    // Two-column layout for history
                    HSplitView {
                        historyListView
                            .frame(minWidth: 280, idealWidth: 400)
                        detailColumnView
                            .frame(minWidth: 300)
                    }
                }

                // StatusBar only under content, not sidebar
                StatusBar()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .observeTheme()
        .onAppear {
            LiveSettings.shared.applyAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLogs)) { _ in
            selectedSection = .logs
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToRecent)) { _ in
            selectedSection = .history
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettings)) { _ in
            selectedSection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettingsAudio)) { _ in
            settingsSection = .audio
            selectedSection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettingsEngine)) { _ in
            settingsSection = .engine
            selectedSection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectUtterance)) { notification in
            // Handle deep link to select specific utterance
            if let id = notification.userInfo?["id"] as? Int64 {
                // Switch to history view
                selectedSection = .history
                // Find and select the utterance by liveID
                if let utterance = store.utterances.first(where: { $0.liveID == id }) {
                    selectedUtteranceIDs = [utterance.id]
                }
            }
        }
        // MARK: - Drop Zone for Audio Files
        .onDrop(of: [.audio, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleAudioDrop(providers)
        }
        .overlay {
            // Drop zone visual feedback
            if isDropTargeted || isTranscribingDrop {
                dropZoneOverlay
            }
        }
    }

    // MARK: - Drop Zone

    /// Supported audio file extensions
    private static let supportedAudioExtensions = Set(["m4a", "mp3", "wav", "aac", "flac", "ogg", "mp4", "caf"])

    /// Visual overlay when dragging audio files
    private var dropZoneOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.6)

            // Drop zone indicator
            VStack(spacing: 16) {
                if isTranscribingDrop {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text(dropMessage ?? "Transcribing...")
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                    Text("Drop audio file to transcribe")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Supports: m4a, mp3, wav, aac, flac")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.1)))
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }

    /// Handle dropped audio files
    private func handleAudioDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Log what types we're getting for debugging
        let types = provider.registeredTypeIdentifiers
        AppLogger.shared.log(.system, "Drop types", detail: types.joined(separator: ", "))

        // Try multiple approaches to get the file URL
        let validTypes = [
            UTType.audio.identifier,
            UTType.fileURL.identifier,
            "public.file-url",
            "public.audio"
        ]

        for typeId in validTypes {
            if provider.hasItemConformingToTypeIdentifier(typeId) {
                isTranscribingDrop = true
                dropMessage = "Reading file..."

                provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
                    guard let url = url else {
                        Task { @MainActor in
                            self.showDropError("Could not read: \(error?.localizedDescription ?? "unknown")")
                        }
                        return
                    }

                    // loadFileRepresentation gives us a temporary copy - we need to copy it before the callback ends
                    let ext = url.pathExtension.lowercased()
                    guard Self.supportedAudioExtensions.contains(ext) else {
                        Task { @MainActor in
                            self.showDropError("Unsupported format: .\(ext)")
                        }
                        return
                    }

                    // Copy to our storage immediately (temp file may be deleted after callback)
                    let originalFilename = url.lastPathComponent
                    guard let storedFilename = AudioStorage.copyToStorage(url) else {
                        Task { @MainActor in
                            self.showDropError("Failed to copy file")
                        }
                        return
                    }

                    Task { @MainActor in
                        await self.processDroppedAudioFromStorage(storedFilename: storedFilename, originalFilename: originalFilename)
                    }
                }
                return true
            }
        }

        AppLogger.shared.log(.error, "Drop rejected", detail: "No matching type")
        return false
    }

    /// Extract metadata from an audio file using AVFoundation
    private func extractAudioMetadata(from url: URL, originalFilename: String) -> (duration: Double?, metadata: [String: String]) {
        var metadata: [String: String] = [:]
        metadata["sourceFilename"] = originalFilename

        // File size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attrs[.size] as? Int64 {
                metadata["sourceSize"] = "\(size)"
            }
            if let created = attrs[.creationDate] as? Date {
                metadata["fileCreatedAt"] = ISO8601DateFormatter().string(from: created)
            }
            if let modified = attrs[.modificationDate] as? Date {
                metadata["fileModifiedAt"] = ISO8601DateFormatter().string(from: modified)
            }
        }

        // AVAsset metadata
        let asset = AVURLAsset(url: url)
        var duration: Double? = nil

        // Duration
        Task {
            do {
                let assetDuration = try await asset.load(.duration)
                if assetDuration.isValid && !assetDuration.isIndefinite {
                    let seconds = CMTimeGetSeconds(assetDuration)
                    if seconds.isFinite && seconds > 0 {
                        duration = seconds
                        metadata["audioDuration"] = String(format: "%.2f", seconds)
                    }
                }
            } catch { }
        }

        // Audio track info
        Task {
            if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                let formatDescriptions = (try? await audioTrack.load(.formatDescriptions)) ?? []
                if let formatDesc = formatDescriptions.first,
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    metadata["sampleRate"] = "\(Int(asbd.pointee.mSampleRate))"
                    metadata["channels"] = "\(asbd.pointee.mChannelsPerFrame)"
                    metadata["bitsPerChannel"] = "\(asbd.pointee.mBitsPerChannel)"
                }
                if let estimatedRate = try? await audioTrack.load(.estimatedDataRate) {
                    metadata["estimatedBitrate"] = "\(Int(estimatedRate))"
                }
            }
        }

        // File type
        metadata["fileExtension"] = url.pathExtension.lowercased()

        // Apple/Common metadata (recording date, device, location, etc.)
        Task {
            let metadataItems = await asset.safeLoadMetadata()
            for (key, value) in metadataItems {
                switch key {
                case "creationDate", AVMetadataKey.commonKeyCreationDate.rawValue:
                    metadata["recordingDate"] = value
                case "make", AVMetadataKey.commonKeyMake.rawValue:
                    metadata["deviceMake"] = value
                case "model", AVMetadataKey.commonKeyModel.rawValue:
                    metadata["deviceModel"] = value
                case "software", AVMetadataKey.commonKeySoftware.rawValue:
                    metadata["recordingSoftware"] = value
                case "author", AVMetadataKey.commonKeyAuthor.rawValue:
                    metadata["author"] = value
                case "title", AVMetadataKey.commonKeyTitle.rawValue:
                    metadata["title"] = value
                case "album", AVMetadataKey.commonKeyAlbumName.rawValue:
                    metadata["album"] = value
                case "artist", AVMetadataKey.commonKeyArtist.rawValue:
                    metadata["artist"] = value
                case "location", AVMetadataKey.commonKeyLocation.rawValue:
                    metadata["recordingLocation"] = value
                case "description", AVMetadataKey.commonKeyDescription.rawValue:
                    metadata["description"] = value
                default:
                    if !key.isEmpty && !value.isEmpty && value.count < 500 {
                        let sanitizedKey = key.replacingOccurrences(of: " ", with: "_")
                        metadata["meta_\(sanitizedKey)"] = value
                    }
                }
            }
        }

        // Also check ID3 and iTunes metadata for MP3/M4A
        Task {
            let id3Items = await asset.safeLoadMetadata(for: .id3Metadata)
            let itunesItems = await asset.safeLoadMetadata(for: .iTunesMetadata)
            for (key, value) in (id3Items + itunesItems) where !metadata.keys.contains(key) && !value.isEmpty && value.count < 500 {
                metadata["tag_\(key)"] = value
            }
        }

        return (duration, metadata)
    }

    /// Process a dropped audio file that's already been copied to storage
    private func processDroppedAudioFromStorage(storedFilename: String, originalFilename: String) async {
        AppLogger.shared.log(.file, "Audio file dropped", detail: originalFilename)

        // Get file info and audio metadata from stored file
        let storedURL = AudioStorage.url(for: storedFilename)
        let (duration, metadata) = extractAudioMetadata(from: storedURL, originalFilename: originalFilename)

        let fileSize = Int64(metadata["sourceSize"] ?? "0") ?? 0
        let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        let durationStr = duration.map { String(format: "%.1fs", $0) } ?? ""
        let detailStr = durationStr.isEmpty ? fileSizeStr : "\(durationStr) • \(fileSizeStr)"

        dropMessage = "Transcribing \(detailStr)..."
        AppLogger.shared.log(.transcription, "Transcribing dropped file", detail: "\(originalFilename) (\(detailStr))")

        // Create pending utterance first (so we have audio saved even if transcription fails)
        let pendingUtterance = LiveUtterance(
            text: "[Transcription pending...]",
            mode: "dropped",
            appBundleID: "dropped.file",
            appName: "File Drop",
            windowTitle: originalFilename,
            durationSeconds: duration,
            transcriptionModel: settings.selectedModelId,
            perfEngineMs: nil,
            metadata: metadata,
            audioFilename: storedFilename,
            transcriptionStatus: .pending,
            createdInTalkieView: true,
            pasteTimestamp: nil
        )
        LiveDatabase.store(pendingUtterance)
        store.refresh()

        // Get the ID of the just-stored utterance
        let storedId = LiveDatabase.all().first { $0.audioFilename == storedFilename }?.id

        do {
            // Transcribe via engine - pass path directly, engine reads the file
            let startTime = Date()
            let text = try await EngineClient.shared.transcribe(
                audioPath: storedURL.path,
                modelId: settings.selectedModelId
            )
            let transcriptionMs = Int(Date().timeIntervalSince(startTime) * 1000)

            // Update the database record with success
            if let id = storedId {
                LiveDatabase.markTranscriptionSuccess(
                    id: id,
                    text: text,
                    perfEngineMs: transcriptionMs,
                    model: settings.selectedModelId
                )
            }

            let wordCount = text.split(separator: " ").count
            let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", Double(transcriptionMs) / 1000.0)
            AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr)")

            // Refresh and select the new utterance
            store.refresh()
            selectedSection = .history
            if let newUtterance = store.utterances.first(where: { $0.metadata.audioFilename == storedFilename }) {
                selectedUtteranceIDs = [newUtterance.id]
            }

            SoundManager.shared.playPasted()
            isTranscribingDrop = false
            dropMessage = nil

        } catch {
            AppLogger.shared.log(.error, "Transcription failed", detail: error.localizedDescription)

            // Mark as failed in database
            if let id = storedId {
                LiveDatabase.markTranscriptionFailed(id: id, error: error.localizedDescription)
            }

            store.refresh()
            showDropError("Transcription failed: \(error.localizedDescription)")
        }
    }

    /// Show a drop error message briefly
    private func showDropError(_ message: String) {
        dropMessage = message
        AppLogger.shared.log(.error, "Drop failed", detail: message)
        SoundManager.shared.playFinish() // Different sound for error

        // Keep showing for a moment then hide
        Task {
            try? await Task.sleep(for: .seconds(2))
            isTranscribingDrop = false
            dropMessage = nil
        }
    }

    // MARK: - Sidebar Content (Collapsible)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // App branding header with collapse toggle
            sidebarHeader

            // Navigation items with hover feedback
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    // Home
                    SidebarNavItem(
                        isSelected: selectedSection == .home,
                        isCollapsed: isSidebarCollapsed,
                        icon: "house",
                        title: "Home"
                    ) {
                        selectedSection = .home
                    }

                    if !isSidebarCollapsed {
                        sidebarSectionHeader("Library")
                    }

                    // Recent
                    SidebarNavItem(
                        isSelected: selectedSection == .history,
                        isCollapsed: isSidebarCollapsed,
                        icon: "waveform",
                        title: "Recent",
                        badge: store.utterances.count > 0 ? "\(store.utterances.count)" : nil
                    ) {
                        selectedSection = .history
                    }

                    // Queue (items waiting to be pasted)
                    let queueCount = LiveDatabase.countQueued()
                    SidebarNavItem(
                        isSelected: selectedSection == .queue,
                        isCollapsed: isSidebarCollapsed,
                        icon: "tray.and.arrow.down",
                        title: "Queue",
                        badge: queueCount > 0 ? "\(queueCount)" : nil,
                        badgeColor: SemanticColor.info
                    ) {
                        selectedSection = .queue
                    }

                    // Today
                    let todayCount = store.utterances.filter { Calendar.current.isDateInToday($0.timestamp) }.count
                    SidebarNavItem(
                        isSelected: selectedSection == .today,
                        isCollapsed: isSidebarCollapsed,
                        icon: "calendar",
                        title: "Today",
                        badge: todayCount > 0 ? "\(todayCount)" : nil
                    ) {
                        selectedSection = .today
                    }

                    if !isSidebarCollapsed {
                        sidebarSectionHeader("System")
                    }

                    // Logs
                    let errorCount = SystemEventManager.shared.events.filter { $0.type == .error }.count
                    SidebarNavItem(
                        isSelected: selectedSection == .logs,
                        isCollapsed: isSidebarCollapsed,
                        icon: "terminal",
                        title: "Logs",
                        badge: errorCount > 0 ? "\(errorCount)" : nil,
                        badgeColor: SemanticColor.error
                    ) {
                        selectedSection = .logs
                    }
                }
                .padding(.top, 4)
            }

            Spacer()

            // Settings pinned to bottom
            SidebarNavItem(
                isSelected: selectedSection == .settings,
                isCollapsed: isSidebarCollapsed,
                icon: "gearshape",
                title: "Settings",
                isSubtle: true
            ) {
                selectedSection = .settings
            }
            .padding(.bottom, 4)
        }
        .background(TalkieTheme.surfaceElevated)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(TalkieTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    /// Sidebar header with app branding and collapse toggle
    private var sidebarHeader: some View {
        HStack {
            if isSidebarCollapsed {
                // Collapsed: show expand chevron centered
                chevronButton(icon: "chevron.right", help: "Expand Sidebar")
            } else {
                // Expanded: show app name and collapse button
                Text("TALKIE LIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(TalkieTheme.textTertiary)

                Spacer()

                chevronButton(icon: "chevron.left", help: "Collapse Sidebar")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.leading, isSidebarCollapsed ? 0 : 72) // Clear traffic light buttons horizontally
        .padding(.trailing, isSidebarCollapsed ? 0 : 12)
        .padding(.top, 38) // Clear traffic light buttons vertically
    }

    /// Interactive chevron button with hover and press feedback
    private func chevronButton(icon: String, help: String) -> some View {
        Button(action: {
            // Haptic-like press feedback
            withAnimation(.easeOut(duration: 0.1)) {
                isChevronPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChevronPressed = false
                toggleSidebarCollapse()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isChevronHovered ? TalkieTheme.textPrimary : TalkieTheme.textTertiary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isChevronHovered ? TalkieTheme.border : Color.clear)
                )
                .scaleEffect(isChevronPressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isChevronHovered = hovering
            }
        }
        .help(help)
    }

    private func toggleSidebarCollapse() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarCollapsed.toggle()
        }
    }

    // MARK: - Full Width Content (for Home, Logs and Settings)

    @ViewBuilder
    private var fullWidthContentView: some View {
        switch selectedSection {
        case .home:
            HomeView(
                onSelectUtterance: { utterance in
                    // Navigate to history and select this utterance
                    selectedSection = .history
                    selectedUtteranceIDs = [utterance.id]
                },
                onSelectApp: { appName, _ in
                    // Navigate to history filtered by this app
                    appFilter = appName
                    selectedSection = .history
                    selectedUtteranceIDs = []
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .logs:
            consoleContentView
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TalkieTheme.surface)
        case .settings:
            settingsContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }

    private var historyListView: some View {
        VStack(spacing: 0) {
            // Search
            SidebarSearchField(text: $searchText, placeholder: "Search transcripts...")

            // Active filter indicator
            if let appFilter = appFilter {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SemanticColor.info)

                    Text("App: \(appFilter)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textSecondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.appFilter = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SemanticColor.info.opacity(0.1))
            }

            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(height: 0.5)

            // Multi-select toolbar
            if selectedUtteranceIDs.count > 1 {
                multiSelectToolbar
            }

            if filteredUtterances.isEmpty {
                emptyHistoryState
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            // Footer
            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(height: 0.5)

            HStack {
                Text("\(store.utterances.count) \(store.utterances.count == 1 ? "recording" : "recordings")")
                    .font(Design.fontXS)
                    .foregroundColor(TalkieTheme.textMuted)

                Spacer()

                if !store.utterances.isEmpty {
                    Button("Clear All") {
                        store.clear()
                    }
                    .font(Design.fontXS)
                    .foregroundColor(SemanticColor.error.opacity(0.8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(TalkieTheme.surface)
    }

    private var settingsContentView: some View {
        EmbeddedSettingsView(initialSection: $settingsSection)
    }

    // MARK: - Console Content

    private var consoleContentView: some View {
        LogViewerConsole()
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.5))
            Text("No Recordings Yet")
                .font(Design.fontBodyMedium)
                .foregroundColor(TalkieTheme.textSecondary)
            Text("Press \(LiveSettings.shared.hotkey.displayString) to start recording")
                .font(Design.fontSM)
                .foregroundColor(TalkieTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Multi-Select Toolbar

    private var multiSelectToolbar: some View {
        HStack(spacing: 10) {
            // Selection count with subtle badge
            HStack(spacing: 6) {
                Text("\(selectedUtteranceIDs.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(TalkieTheme.accent)
                    .clipShape(Circle())

                Text("selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            // Cancel - text only
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedUtteranceIDs.removeAll()
                }
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            // Delete - red button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    for utterance in selectedUtterances {
                        store.delete(utterance)
                    }
                    selectedUtteranceIDs.removeAll()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(SemanticColor.error)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(TalkieTheme.surfaceElevated)
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumnView: some View {
        if selectedSection == .settings {
            settingsDetailPlaceholder
        } else if selectedSection == .logs {
            consoleDetailPlaceholder
        } else if let utterance = selectedUtterance {
            UtteranceDetailView(utterance: utterance)
        } else {
            emptyDetailState
        }
    }

    private var settingsDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.3))
            Text("Configure TalkieLive settings")
                .font(Design.fontSM)
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }

    private var consoleDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.3))
            Text("System event logs")
                .font(Design.fontSM)
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.3))
            Text("Select an item to view details")
                .font(Design.fontSM)
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }
}

// MARK: - Utterance Row

struct UtteranceRowView: View {
    let utterance: Utterance
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Preview text - scales with fontSize setting
            Text(utterance.text)
                .font(settings.fontSize.bodyFont)
                .foregroundColor(TalkieTheme.textPrimary)
                .lineLimit(2)

            // Metadata - scales with fontSize setting
            HStack(spacing: 4) {
                if let duration = utterance.durationSeconds {
                    Text(formatDuration(duration))
                        .font(settings.fontSize.xsFont)

                    Text("·")
                        .font(settings.fontSize.xsFont)
                        .foregroundColor(TalkieTheme.textMuted)
                }

                Text(formatDate(utterance.timestamp))
                    .font(settings.fontSize.xsFont)

                if let appName = utterance.metadata.activeAppName {
                    Text("·")
                        .font(settings.fontSize.xsFont)
                        .foregroundColor(TalkieTheme.textMuted)

                    HStack(spacing: 4) {
                        if let bundleID = utterance.metadata.activeAppBundleID {
                            AppIconView(bundleIdentifier: bundleID, size: 12)
                                .frame(width: 12, height: 12)
                        }

                        Text(appName)
                            .font(settings.fontSize.xsFont)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(TalkieTheme.textSecondary)
        }
        .padding(.vertical, 6)
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Utterance Detail

struct UtteranceDetailView: View {
    let utterance: Utterance
    @State private var copied = false
    @State private var showJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header: Date + actions
                    MinimalHeader(utterance: utterance)

                    // Text/JSON toggle at top right
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            ContentToggle(showJSON: $showJSON)

                            Button(action: copyCurrentContent) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(copied ? SemanticColor.success : TalkieTheme.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(TalkieTheme.surfaceCard)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Combined transcript + stats container
                    TranscriptContainer(
                        utterance: utterance,
                        showJSON: $showJSON
                    )

                    // Info cards row
                    MinimalInfoCards(utterance: utterance)

                    // Audio asset
                    MinimalAudioCard(utterance: utterance)

                    // Actions section
                    ActionsSection(utterance: utterance)
                }
                .padding(24)
            }
        }
        .background(TalkieTheme.surface)  // Near black background
    }

    private func copyCurrentContent() {
        // Copy JSON when JSON view is active; otherwise copy plain text
        if showJSON {
            let json = JSONContentView(utterance: utterance).renderedString()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        } else {
            copyPlainText()
        }

        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }

    private func copyPlainText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(utterance.text, forType: .string)
    }

    private func pasteText() {
        copyPlainText()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Minimal Detail Components

private struct MinimalHeader: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                // Date + time badge
                HStack(spacing: 8) {
                    Text(formatDate(utterance.timestamp))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text(formatTime(utterance.timestamp))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(TalkieTheme.border, lineWidth: 1)
                        )
                }

                Spacer()

                // Export action only (Copy moved to text area)
                GhostButton(icon: "square.and.arrow.up", label: "Export", isActive: false, accentColor: SemanticColor.info) {
                    // Export action
                }
            }

            // ID row
            Text("ID: T-\(utterance.id.uuidString.prefix(5).uppercased())")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(TalkieTheme.textMuted)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private struct GhostButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var accentColor: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var textColor: Color {
        if isActive { return SemanticColor.success }
        if let accent = accentColor {
            return isHovered ? accent : TalkieTheme.textSecondary
        }
        return isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary
    }

    private var borderColor: Color {
        if isActive { return SemanticColor.success.opacity(0.4) }
        if isHovered {
            return accentColor?.opacity(0.4) ?? TalkieTheme.textMuted
        }
        return TalkieTheme.border
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "checkmark" : icon)
                    .font(.system(size: 10))
                Text(isActive ? "Copied" : label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? TalkieTheme.surfaceCard : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ContentToggle: View {
    @Binding var showJSON: Bool

    var body: some View {
        HStack(spacing: 0) {
            ToggleSegment(label: "Text", isSelected: !showJSON) {
                showJSON = false
            }
            ToggleSegment(label: "JSON", isSelected: showJSON) {
                showJSON = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(TalkieTheme.surfaceCard)
        )
    }
}

private struct ToggleSegment: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: label == "Text" ? "text.alignleft" : "curlybraces")
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : TalkieTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? TalkieTheme.border : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combined Transcript Container (Stats + Text in one bordered container)

private struct TranscriptContainer: View {
    let utterance: Utterance
    @Binding var showJSON: Bool
    @ObservedObject private var settings = LiveSettings.shared

    // Crisp text colors - solid grays instead of opacity
    private static let textPrimary = Color.white
    private static let textSecondary = TalkieTheme.textSecondary
    private static let textMuted = TalkieTheme.textTertiary

    private var tokenEstimate: Int {
        // Rough estimate: ~4 chars per token
        utterance.characterCount / 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Transcript content (no overlay, buttons moved above)
            HStack(spacing: 0) {
                // Left accent bar
                Rectangle()
                    .fill(showJSON ? SemanticColor.info.opacity(0.5) : TalkieTheme.textMuted)
                    .frame(width: 3)

                // Text content
                if showJSON {
                    JSONContentView(utterance: utterance)
                } else {
                    Text(utterance.text)
                        .font(settings.fontSize.detailFont)
                        .foregroundColor(Self.textPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }

            // Bottom bar: Stats left, Tokens right
            HStack(alignment: .center) {
                HStack(spacing: 16) {
                    StatPill(label: "WORDS", value: "\(utterance.wordCount)")
                    StatPill(label: "CHARS", value: "\(utterance.characterCount)")
                }

                Spacer()

                StatPill(label: "TOKENS", value: "~\(tokenEstimate)", color: SemanticColor.info)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(TalkieTheme.surface)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surfaceCard, lineWidth: 1)
        )
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color?.opacity(0.6) ?? TalkieTheme.textTertiary)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color ?? TalkieTheme.textPrimary)
        }
    }
}

private struct JSONContentView: View {
    let utterance: Utterance

    /// Render the JSON content as a string for copying
    func renderedString() -> String {
        let m = utterance.metadata
        var lines: [String] = []
        lines.append("{")
        appendLine(&lines, key: "id", value: "\"\(utterance.id.uuidString)\"")
        appendLine(&lines, key: "liveID", value: utterance.liveID.map { String($0) } ?? "null")
        appendLine(&lines, key: "timestamp", value: "\"\(ISO8601DateFormatter().string(from: utterance.timestamp))\"")
        appendLine(&lines, key: "text", value: "\"\(escapeJSON(utterance.text))\"")

        appendLine(&lines, key: "words", value: "\(utterance.wordCount)")
        appendLine(&lines, key: "chars", value: "\(utterance.characterCount)")
        if let duration = utterance.durationSeconds {
            appendLine(&lines, key: "durationSeconds", value: String(format: "%.2f", duration))
        }

        appendIfPresent(&lines, key: "appBundleID", value: m.activeAppBundleID)
        appendIfPresent(&lines, key: "appName", value: m.activeAppName)
        appendIfPresent(&lines, key: "windowTitle", value: m.activeWindowTitle)

        appendIfPresent(&lines, key: "documentURL", value: m.documentURL)
        appendIfPresent(&lines, key: "browserURL", value: m.browserURL)
        appendIfPresent(&lines, key: "focusedElementRole", value: m.focusedElementRole)
        appendIfPresent(&lines, key: "focusedElementValue", value: m.focusedElementValue)
        appendIfPresent(&lines, key: "terminalWorkingDir", value: m.terminalWorkingDir)

        appendIfPresent(&lines, key: "transcriptionModel", value: m.transcriptionModel)
        appendIfPresent(&lines, key: "perfEngineMs", value: m.perfEngineMs.map { "\($0)" })
        appendIfPresent(&lines, key: "perfEndToEndMs", value: m.perfEndToEndMs.map { "\($0)" })
        appendIfPresent(&lines, key: "perfInAppMs", value: m.perfInAppMs.map { "\($0)" })

        appendIfPresent(&lines, key: "routingMode", value: m.routingMode)
        appendLine(&lines, key: "wasRouted", value: "\(m.wasRouted)", isLast: true)

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        let json = renderedString()

        ScrollView {
            Text(json)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(TalkieTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private func jsonString(_ value: String?) -> String {
        guard let v = value else { return "null" }
        return "\"\(escapeJSON(v))\""
    }

    private func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func appendIfPresent(_ lines: inout [String], key: String, value: String?) {
        guard let value, !value.isEmpty else { return }
        appendLine(&lines, key: key, value: "\"\(escapeJSON(value))\"")
    }

    private func appendLine(_ lines: inout [String], key: String, value: String, isLast: Bool = false) {
        let suffix = isLast ? "" : ","
        lines.append("  \"\(key)\": \(value)\(suffix)")
    }
}

private struct MinimalInfoCards: View {
    let utterance: Utterance

    var body: some View {
        HStack(spacing: 12) {
            // Input source - purple (with app icon)
            if let appName = utterance.metadata.activeAppName {
                InfoCard(
                    label: "INPUT SOURCE",
                    icon: "chevron.left.forwardslash.chevron.right",
                    value: appName,
                    iconColor: .purple,
                    appBundleID: utterance.metadata.activeAppBundleID
                )
            }

            // Model config - blue
            if let model = utterance.metadata.transcriptionModel {
                InfoCard(
                    label: "MODEL CONFIG",
                    icon: "cpu",
                    value: model,
                    iconColor: .blue
                )
            }

            // Duration - orange
            if let duration = utterance.durationSeconds {
                InfoCard(
                    label: "DURATION",
                    icon: "clock",
                    value: formatDuration(duration),
                    iconColor: SemanticColor.warning
                )
            }

            // Performance breakdown
            PerformanceCard(utterance: utterance)
        }
    }

    private func formatDuration(_ d: Double) -> String {
        String(format: "%.2fs", d)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

private struct InfoCard: View {
    let label: String
    let icon: String
    let value: String
    var iconColor: Color = .white
    var appBundleID: String? = nil

    @State private var isHovered = false

    var body: some View {
        let baseFill = TalkieTheme.surface
        let hoverFill = TalkieTheme.hover
        let borderColor = isHovered ? iconColor.opacity(0.35) : TalkieTheme.surfaceCard

        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)

            HStack(spacing: 6) {
                if let bundleID = appBundleID {
                    AppIconView(bundleIdentifier: bundleID, size: 14)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(iconColor.opacity(isHovered ? 1.0 : 0.8))
                }

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? hoverFill : baseFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct PerformanceCard: View {
    let utterance: Utterance
    @State private var isHovered = false
    @State private var showPopover = false
    @State private var showCopied = false

    // End-to-End: total perceived latency (stop recording → delivered)
    private var endToEndMs: Int? { utterance.metadata.perfEndToEndMs ?? utterance.metadata.perfEngineMs }
    // Engine: transcription time in TalkieEngine
    private var engineMs: Int? { utterance.metadata.perfEngineMs }
    // App: everything TalkieLive does (file save, context, routing, paste)
    private var appMs: Int? {
        if let stored = utterance.metadata.perfInAppMs { return stored }
        if let total = endToEndMs, let engine = engineMs { return max(0, total - engine) }
        return nil
    }

    private var displayValue: String {
        if let total = endToEndMs { return formatTime(total) }
        if let engine = engineMs { return formatTime(engine) }
        return "—"
    }

    private let iconColor = SemanticColor.success

    var body: some View {
        let baseFill = TalkieTheme.surface
        let hoverFill = TalkieTheme.hover
        let borderColor = isHovered ? iconColor.opacity(0.35) : TalkieTheme.surfaceCard

        Button(action: { if hasBreakdown { showPopover.toggle() } }) {
            VStack(alignment: .leading, spacing: 8) {
                // Label row - matches InfoCard
                Text("PERFORMANCE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)

                // Value row - matches InfoCard
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(iconColor.opacity(isHovered ? 1.0 : 0.8))

                    Text(displayValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textPrimary)

                    if hasBreakdown {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? hoverFill : baseFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                Text("PERFORMANCE BREAKDOWN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TalkieTheme.textTertiary)

                // Breakdown items
                VStack(alignment: .leading, spacing: 8) {
                    if let total = endToEndMs {
                        PerfBreakdownItem(label: "End-to-End", value: formatTime(total), color: TalkieTheme.textPrimary)
                    }
                    if let engine = engineMs {
                        PerfBreakdownItem(label: "Engine", value: formatTime(engine), color: SemanticColor.success)
                    }
                    if let app = appMs, app > 0 {
                        PerfBreakdownItem(label: "App", value: formatTime(app), color: .orange)
                    }
                }

                Divider()

                // Copy diagnostics button
                Button(action: copyDiagnostics) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopied ? "Copied" : "Copy Diagnostics")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(showCopied ? SemanticColor.success : TalkieTheme.textSecondary)
                }
                .buttonStyle(.plain)

                // View in Engine button (only if sessionID exists)
                if let sessionID = utterance.metadata.sessionID {
                    Button(action: { openEngineTrace(sessionID) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "engine.combustion")
                                .font(.system(size: 10))
                            Text("View in Engine")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(TalkieTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(minWidth: 180)
        }
    }

    private func openEngineTrace(_ sessionID: String) {
        // Validate sessionID format (8 lowercase hex chars)
        let hexPattern = "^[0-9a-f]{8}$"
        guard sessionID.range(of: hexPattern, options: .regularExpression) != nil else {
            return
        }

        // Open Engine with deep link
        if let url = URL(string: "talkieengine://trace/\(sessionID)") {
            NSWorkspace.shared.open(url)
        }
    }

    private var hasBreakdown: Bool {
        engineMs != nil || appMs != nil
    }

    private func formatTime(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }

    private func copyDiagnostics() {
        var lines: [String] = []
        lines.append("Performance Diagnostics")
        lines.append("=======================")
        lines.append("Utterance ID: \(utterance.id)")
        lines.append("Created: \(utterance.timestamp)")
        if let total = endToEndMs { lines.append("End-to-End: \(total)ms") }
        if let engine = engineMs { lines.append("Engine: \(engine)ms") }
        if let app = appMs { lines.append("App: \(app)ms") }
        if let model = utterance.metadata.transcriptionModel { lines.append("Model: \(model)") }
        if let duration = utterance.durationSeconds { lines.append("Audio Duration: \(String(format: "%.2f", duration))s") }
        if let app = utterance.metadata.activeAppName { lines.append("Input App: \(app)") }
        lines.append("Word Count: \(utterance.wordCount)")
        lines.append("Char Count: \(utterance.text.count)")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

private struct PerfBreakdownItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TalkieTheme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TalkieTheme.textSecondary)
        }
    }
}

private struct PerfChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(TalkieTheme.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(TalkieTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(TalkieTheme.surface)
        )
    }
}
private struct MinimalAudioCard: View {
    let utterance: Utterance
    @ObservedObject private var playback = AudioPlaybackManager.shared
    @State private var isHovering = false
    @State private var isPlayButtonHovered = false

    private var isThisPlaying: Bool {
        playback.currentAudioID == utterance.id.uuidString && playback.isPlaying
    }

    private var isThisLoaded: Bool {
        playback.currentAudioID == utterance.id.uuidString
    }

    private var displayProgress: Double {
        isThisLoaded ? playback.progress : 0
    }

    private var displayCurrentTime: TimeInterval {
        isThisLoaded ? playback.currentTime : 0
    }

    private var totalDuration: TimeInterval {
        utterance.durationSeconds ?? 0
    }

    private var hasAudio: Bool {
        utterance.metadata.hasAudio
    }

    /// Short ID for display (last 8 chars of filename before extension)
    private var shortFileId: String {
        guard let url = utterance.metadata.audioURL else { return "—" }
        let filename = url.deletingPathExtension().lastPathComponent
        if filename.count > 8 {
            return String(filename.suffix(8))
        }
        return filename
    }

    private var fullFilename: String {
        utterance.metadata.audioURL?.deletingPathExtension().lastPathComponent ?? "No audio"
    }

    private var fileSize: String {
        guard let url = utterance.metadata.audioURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main playback row
            HStack(spacing: 12) {
                // Play button with hover effect
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(playButtonBackground)
                            .frame(width: 36, height: 36)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(playButtonForeground)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasAudio)
                .onHover { isPlayButtonHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isPlayButtonHovered)

                // Waveform + timeline (fills available space)
                VStack(spacing: 6) {
                    // Waveform with click-to-seek
                    SeekableWaveform(
                        progress: displayProgress,
                        isPlaying: isThisPlaying,
                        hasAudio: hasAudio,
                        onSeek: seekToPosition
                    )
                    .frame(height: 32)

                    // Time row - aligned with waveform edges
                    HStack {
                        Text(formatTime(displayCurrentTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)

                        Spacer()

                        Text(formatTime(totalDuration))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Divider
            Rectangle()
                .fill(TalkieTheme.surfaceCard)
                .frame(height: 1)

            // File info row - Cmd+click to reveal
            HStack {
                // File ID (truncated, full on hover)
                Text(isHovering ? fullFilename : shortFileId)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovering ? TalkieTheme.textSecondary : TalkieTheme.textMuted)
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.15), value: isHovering)

                Spacer()

                // File size
                if !fileSize.isEmpty {
                    Text(fileSize)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                }

                // Cmd+click hint on hover
                if isHovering && hasAudio {
                    Text("⌘ click to reveal")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasAudio else { return }
                // Cmd+click: reveal file in Finder
                if NSEvent.modifierFlags.contains(.command) {
                    revealInFinder()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surfaceCard, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private var playButtonBackground: Color {
        if !hasAudio { return TalkieTheme.hover }
        if isThisPlaying { return Color.accentColor.opacity(0.25) }
        if isPlayButtonHovered { return TalkieTheme.border }
        return TalkieTheme.surfaceCard
    }

    private var playButtonForeground: Color {
        if !hasAudio { return TalkieTheme.textMuted }
        if isThisPlaying { return .white }
        if isPlayButtonHovered { return .white }
        return TalkieTheme.textPrimary
    }

    private func togglePlayback() {
        guard let url = utterance.metadata.audioURL else { return }
        playback.togglePlayPause(url: url, id: utterance.id.uuidString)
    }

    /// Seek to a position - loads audio first if not already loaded
    private func seekToPosition(_ progress: Double) {
        guard let url = utterance.metadata.audioURL else {
            print("⚠️ seekToPosition: No audio URL")
            return
        }

        print("🎯 seekToPosition: \(Int(progress * 100))% - isLoaded: \(isThisLoaded)")

        // If audio isn't loaded yet, load it first then seek
        if !isThisLoaded {
            print("📂 Loading audio first...")
            playback.play(url: url, id: utterance.id.uuidString)
            playback.pause()  // Load but don't auto-play
        }
        playback.seek(to: progress)
        print("✅ Seeked to \(Int(progress * 100))%")
    }

    private func revealInFinder() {
        guard let url = utterance.metadata.audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct ActionsSection: View {
    let utterance: Utterance

    // Grid columns adapt to available width
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIONS")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)

            LazyVGrid(columns: columns, spacing: 10) {
                ActionCard(
                    icon: "waveform.badge.magnifyingglass",
                    title: "Enhance Audio",
                    subtitle: "Pro model",
                    color: SemanticColor.info
                )

                ActionCard(
                    icon: "arrow.up.doc",
                    title: "Promote to Memo",
                    subtitle: "Full features",
                    color: SemanticColor.success
                )

                ActionCard(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Export",
                    color: .blue
                )

                ActionCard(
                    icon: "ellipsis",
                    title: "More",
                    subtitle: "Options",
                    color: .gray
                )
            }
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var color: Color = .white

    @State private var isHovered = false

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isHovered ? color : TalkieTheme.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? color.opacity(0.12) : TalkieTheme.surfaceElevated)
                    )

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isHovered ? TalkieTheme.textPrimary : TalkieTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 8))
                            .foregroundColor(isHovered ? color.opacity(0.7) : TalkieTheme.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? TalkieTheme.hover : TalkieTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? color.opacity(0.3) : TalkieTheme.surfaceCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Transcription Info Card (Context + Metadata)

private struct TranscriptionInfoCard: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Row 1: Source context
            HStack(spacing: Spacing.lg) {
                // Source app
                if let appName = utterance.metadata.activeAppName {
                    InfoPill(
                        icon: "app.fill",
                        label: "Source",
                        value: appName,
                        color: .blue
                    )
                }

                // Window
                if let windowTitle = utterance.metadata.activeWindowTitle, !windowTitle.isEmpty {
                    InfoPill(
                        icon: "macwindow",
                        label: "Window",
                        value: String(windowTitle.prefix(25)),
                        color: .purple
                    )
                }

                Spacer()
            }

            // Row 1.5: Rich context (URL, document, etc.)
            if hasRichContext {
                HStack(spacing: Spacing.lg) {
                    // Browser URL
                    if let url = utterance.metadata.browserURL ?? utterance.metadata.documentURL {
                        InfoPill(
                            icon: url.hasPrefix("http") ? "globe" : "doc.text",
                            label: url.hasPrefix("http") ? "URL" : "Document",
                            value: formatURL(url),
                            color: url.hasPrefix("http") ? .cyan : .orange
                        )
                    }

                    // Focused element type
                    if let role = utterance.metadata.focusedElementRole {
                        InfoPill(
                            icon: focusedRoleIcon(role),
                            label: "Focus",
                            value: formatRole(role),
                            color: .indigo
                        )
                    }

                    // Terminal working directory
                    if let dir = utterance.metadata.terminalWorkingDir {
                        InfoPill(
                            icon: "folder",
                            label: "Directory",
                            value: dir,
                            color: .mint
                        )
                    }

                    Spacer()
                }
            }

            // Divider
            Rectangle()
                .fill(TalkieTheme.surface)
                .frame(height: 1)

            // Row 2: Transcription metadata
            HStack(spacing: Spacing.lg) {
                // Model
                if let model = utterance.metadata.transcriptionModel {
                    InfoPill(
                        icon: "cpu",
                        label: "Model",
                        value: model.capitalized,
                        color: SemanticColor.info
                    )
                }

                // Duration
                if let duration = utterance.durationSeconds {
                    InfoPill(
                        icon: "clock",
                        label: "Duration",
                        value: formatDuration(duration),
                        color: SemanticColor.warning
                    )
                }

                // Transcription time
                if let transcriptionMs = utterance.metadata.perfEngineMs {
                    InfoPill(
                        icon: "bolt",
                        label: "Engine",
                        value: formatTranscriptionTime(transcriptionMs),
                        color: SemanticColor.success
                    )
                }

                if let totalMs = utterance.metadata.perfEndToEndMs {
                    InfoPill(
                        icon: "timer",
                        label: "End-to-End",
                        value: formatTranscriptionTime(totalMs),
                        color: .cyan
                    )
                }

                if let appMs = utterance.metadata.perfInAppMs {
                    InfoPill(
                        icon: "app",
                        label: "App",
                        value: formatTranscriptionTime(appMs),
                        color: .orange
                    )
                }

                // Routing
                if let routingMode = utterance.metadata.routingMode {
                    InfoPill(
                        icon: routingMode == "paste" ? "doc.on.clipboard" : "clipboard",
                        label: "Routing",
                        value: routingMode == "paste" ? "Paste" : "Clipboard",
                        color: .pink
                    )
                }

                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.divider)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surface, lineWidth: 1)
        )
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }

    // MARK: - Rich Context Helpers

    private var hasRichContext: Bool {
        utterance.metadata.browserURL != nil ||
        utterance.metadata.documentURL != nil ||
        utterance.metadata.focusedElementRole != nil ||
        utterance.metadata.terminalWorkingDir != nil
    }

    private func formatURL(_ url: String) -> String {
        // Extract domain or filename for compact display
        if url.hasPrefix("http") {
            if let urlObj = URL(string: url), let host = urlObj.host {
                let path = urlObj.path
                if path.count > 1 {
                    return "\(host)\(path.prefix(20))"
                }
                return host
            }
        } else if url.hasPrefix("file://") {
            // File path - show last component
            return URL(string: url)?.lastPathComponent ?? url.suffix(30).description
        }
        return String(url.suffix(30))
    }

    private func focusedRoleIcon(_ role: String) -> String {
        switch role {
        case "AXTextArea", "AXTextField": return "text.cursor"
        case "AXWebArea": return "globe"
        case "AXScrollArea": return "scroll"
        case "AXGroup": return "square.stack"
        case "AXButton": return "rectangle.and.hand.point.up.left"
        default: return "cursorarrow.rays"
        }
    }

    private func formatRole(_ role: String) -> String {
        // Convert AXRole to friendly name
        let mapping: [String: String] = [
            "AXTextArea": "Text Editor",
            "AXTextField": "Text Field",
            "AXWebArea": "Web Content",
            "AXScrollArea": "Scroll Area",
            "AXGroup": "Group",
            "AXButton": "Button",
            "AXStaticText": "Text"
        ]
        return mapping[role] ?? role.replacingOccurrences(of: "AX", with: "")
    }
}

private struct InfoPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color.opacity(0.8))

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(TalkieTheme.textMuted)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Transcript Card

private struct TranscriptCard: View {
    let text: String
    let onCopy: () -> Void
    let copied: Bool

    @State private var isHoveringCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area - clean, readable
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TalkieTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)

            // Bottom bar with quick copy
            HStack {
                // Word/char count
                HStack(spacing: Spacing.md) {
                    Label("\(text.split(separator: " ").count) words", systemImage: "text.word.spacing")
                    Label("\(text.count) chars", systemImage: "character.cursor.ibeam")
                }
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textMuted)

                Spacer()

                // Quick copy button
                Button(action: onCopy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(copied ? SemanticColor.success : (isHoveringCopy ? .white : TalkieTheme.textTertiary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(copied ? SemanticColor.success.opacity(0.15) : (isHoveringCopy ? TalkieTheme.surfaceElevated : Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCopy = $0 }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(TalkieTheme.divider)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TalkieTheme.hover, lineWidth: 1)
        )
    }
}

// MARK: - Stats Card

private struct StatsCard: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("STATS", systemImage: "chart.bar")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(TalkieTheme.textMuted)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                StatBox(
                    value: "\(utterance.wordCount)",
                    label: "Words",
                    icon: "text.word.spacing",
                    color: .blue
                )

                StatBox(
                    value: "\(utterance.characterCount)",
                    label: "Characters",
                    icon: "character.cursor.ibeam",
                    color: .purple
                )

                if let duration = utterance.durationSeconds {
                    StatBox(
                        value: formatDuration(duration),
                        label: "Duration",
                        icon: "clock",
                        color: SemanticColor.warning
                    )
                }

                if let totalMs = utterance.metadata.perfEndToEndMs {
                    StatBox(
                        value: formatTranscriptionTime(totalMs),
                        label: "End-to-End",
                        icon: "timer",
                        color: .cyan
                    )
                }

                if let appMs = utterance.metadata.perfInAppMs {
                    StatBox(
                        value: formatTranscriptionTime(appMs),
                        label: "App",
                        icon: "app",
                        color: .orange
                    )
                }

                if let transcriptionMs = utterance.metadata.perfEngineMs {
                    StatBox(
                        value: formatTranscriptionTime(transcriptionMs),
                        label: "Engine",
                        icon: "bolt",
                        color: SemanticColor.success
                    )
                }
            }

            // Additional stats row
            if utterance.metadata.transcriptionModel != nil || utterance.metadata.routingMode != nil {
                Divider().background(TalkieTheme.surfaceElevated)

                HStack(spacing: Spacing.lg) {
                    if let model = utterance.metadata.transcriptionModel {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                                .foregroundColor(SemanticColor.info.opacity(0.7))
                            Text("Model:")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textMuted)
                            Text(model)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }
                    }

                    if let routingMode = utterance.metadata.routingMode {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 9))
                                .foregroundColor(.pink.opacity(0.7))
                            Text("Routing:")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textMuted)
                            Text(routingMode == "paste" ? "Paste" : "Clipboard")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.divider)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surface, lineWidth: 1)
        )
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.2fs", seconds)
        }
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color.opacity(0.7))

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Quick Actions Card (replaces Smart Actions)

private struct SmartActionsCard: View {
    let utterance: Utterance
    @State private var hoveredAction: QuickActionKind? = nil
    @State private var actionFeedback: QuickActionKind? = nil

    // Map Utterance to LiveUtterance for database operations
    private var liveUtterance: LiveUtterance? {
        // Find matching LiveUtterance by timestamp and text
        LiveDatabase.recent(limit: 50).first { live in
            live.text == utterance.text &&
            abs(live.createdAt.timeIntervalSince(utterance.timestamp)) < 5
        }
    }

    private var promotionStatus: PromotionStatus {
        liveUtterance?.promotionStatus ?? .none
    }

    private var canPromote: Bool {
        liveUtterance?.canPromote ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with promotion status
            HStack {
                Label("QUICK ACTIONS", systemImage: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(TalkieTheme.textMuted)

                Spacer()

                // Show promotion status badge if promoted
                if promotionStatus != .none {
                    promotionStatusBadge
                }
            }

            // Primary actions row (most common)
            HStack(spacing: Spacing.sm) {
                QuickActionButton(
                    action: .copyToClipboard,
                    isHovered: hoveredAction == .copyToClipboard,
                    showFeedback: actionFeedback == .copyToClipboard,
                    onHover: { hoveredAction = $0 ? .copyToClipboard : nil },
                    onTap: { executeAction(.copyToClipboard) }
                )

                if canPromote {
                    QuickActionButton(
                        action: .promoteToMemo,
                        isHovered: hoveredAction == .promoteToMemo,
                        showFeedback: actionFeedback == .promoteToMemo,
                        onHover: { hoveredAction = $0 ? .promoteToMemo : nil },
                        onTap: { executeAction(.promoteToMemo) }
                    )

                    QuickActionButton(
                        action: .sendToClaude,
                        isHovered: hoveredAction == .sendToClaude,
                        showFeedback: actionFeedback == .sendToClaude,
                        onHover: { hoveredAction = $0 ? .sendToClaude : nil },
                        onTap: { executeAction(.sendToClaude) }
                    )
                }
            }

            // Secondary actions (overflow)
            if canPromote || utterance.metadata.hasAudio {
                Divider().background(TalkieTheme.surface)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.xs) {
                    QuickActionButton(
                        action: .typeAgain,
                        isHovered: hoveredAction == .typeAgain,
                        showFeedback: actionFeedback == .typeAgain,
                        compact: true,
                        onHover: { hoveredAction = $0 ? .typeAgain : nil },
                        onTap: { executeAction(.typeAgain) }
                    )

                    if utterance.metadata.hasAudio {
                        QuickActionButton(
                            action: .retryTranscription,
                            isHovered: hoveredAction == .retryTranscription,
                            showFeedback: actionFeedback == .retryTranscription,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .retryTranscription : nil },
                            onTap: { executeAction(.retryTranscription) }
                        )
                    }

                    if canPromote {
                        QuickActionButton(
                            action: .runWorkflow,
                            isHovered: hoveredAction == .runWorkflow,
                            showFeedback: actionFeedback == .runWorkflow,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .runWorkflow : nil },
                            onTap: { executeAction(.runWorkflow) }
                        )

                        QuickActionButton(
                            action: .markIgnored,
                            isHovered: hoveredAction == .markIgnored,
                            showFeedback: actionFeedback == .markIgnored,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .markIgnored : nil },
                            onTap: { executeAction(.markIgnored) }
                        )
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.divider)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surface, lineWidth: 1)
        )
    }

    private var promotionStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: promotionStatus.icon)
                .font(.system(size: 8))

            Text(promotionStatus.displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(promotionStatusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(promotionStatusColor.opacity(0.15))
        )
    }

    private var promotionStatusColor: Color {
        switch promotionStatus {
        case .none: return TalkieTheme.textMuted
        case .memo: return .blue
        case .command: return .purple
        case .ignored: return .gray
        }
    }

    private func executeAction(_ action: QuickActionKind) {
        guard let live = liveUtterance else {
            // Fallback for legacy utterances without LiveUtterance
            if action == .copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(utterance.text, forType: .string)
                showFeedback(for: action)
            }
            return
        }

        // Show feedback
        showFeedback(for: action)

        // Execute action
        Task {
            await QuickActionRunner.shared.run(action, for: live)
        }
    }

    private func showFeedback(for action: QuickActionKind) {
        withAnimation(.easeOut(duration: 0.15)) {
            actionFeedback = action
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                actionFeedback = nil
            }
        }
    }
}

private struct QuickActionButton: View {
    let action: QuickActionKind
    let isHovered: Bool
    var showFeedback: Bool = false
    var compact: Bool = false
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private var actionColor: Color {
        switch action {
        case .copyToClipboard: return .blue
        case .typeAgain: return SemanticColor.warning
        case .retryTranscription: return SemanticColor.info
        case .promoteToMemo: return SemanticColor.success
        case .createResearchMemo: return .teal
        case .sendToClaude: return .purple
        case .runWorkflow: return .pink
        case .markIgnored: return .gray
        }
    }

    var body: some View {
        Button(action: onTap) {
            if compact {
                compactContent
            } else {
                fullContent
            }
        }
        .buttonStyle(.plain)
        .onHover { onHover($0) }
    }

    private var fullContent: some View {
        HStack(spacing: 10) {
            Image(systemName: showFeedback ? "checkmark" : action.icon)
                .font(.system(size: 14))
                .foregroundColor(showFeedback ? SemanticColor.success : actionColor.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(showFeedback ? SemanticColor.success.opacity(0.15) : actionColor.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(showFeedback ? "Done!" : action.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(showFeedback ? SemanticColor.success : TalkieTheme.textPrimary)

                    if let shortcut = action.shortcut, !showFeedback {
                        Text(shortcut)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                }

                Text(actionDescription)
                    .font(.system(size: 8))
                    .foregroundColor(TalkieTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(showFeedback ? SemanticColor.success.opacity(0.1) : (isHovered ? actionColor.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(showFeedback ? SemanticColor.success.opacity(0.3) : (isHovered ? actionColor.opacity(0.3) : TalkieTheme.divider), lineWidth: 1)
        )
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: showFeedback ? "checkmark" : action.icon)
                .font(.system(size: 10))
                .foregroundColor(showFeedback ? SemanticColor.success : actionColor.opacity(0.7))

            Text(showFeedback ? "Done" : action.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(showFeedback ? SemanticColor.success : TalkieTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(showFeedback ? SemanticColor.success.opacity(0.1) : (isHovered ? actionColor.opacity(0.08) : TalkieTheme.divider))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(showFeedback ? SemanticColor.success.opacity(0.2) : (isHovered ? actionColor.opacity(0.2) : Color.clear), lineWidth: 1)
        )
    }

    private var actionDescription: String {
        switch action {
        case .copyToClipboard: return "Copy text to clipboard"
        case .typeAgain: return "Type into active app"
        case .retryTranscription: return "Re-transcribe audio"
        case .promoteToMemo: return "Save as Talkie memo"
        case .createResearchMemo: return "Create research memo"
        case .sendToClaude: return "Send to Claude"
        case .runWorkflow: return "Run a workflow"
        case .markIgnored: return "Don't show again"
        }
    }
}

#Preview {
    LiveNavigationView()
}
