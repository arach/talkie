//
//  VoiceMemoListView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData
import CloudKit
import AVFoundation

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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var iCloudStatus = iCloudStatusManager.shared
    private var bridgeManager = BridgeManager.shared
    @State private var showingMacView = false
    @State private var macButtonVisible = false
    @State private var justPaired = false

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var pushToTalkRecorder = AudioRecorderManager()
    @State private var showingRecordingView = false
    @State private var showingSettings = false
    @State private var displayLimit = 10
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isPushToTalkActive = false
    @State private var pushToTalkScale: CGFloat = 1.0
    @State private var deepLinkMemo: VoiceMemo? = nil
    @State private var scrollToActivity: Bool = false

    // Helper for action handlers (delete, move) - not used during rendering
    private var displayedMemos: [VoiceMemo] {
        let filtered: [VoiceMemo] = searchText.isEmpty
            ? Array(allVoiceMemos)
            : allVoiceMemos.filter { memo in
                let titleMatch = memo.title?.localizedCaseInsensitiveContains(searchText) ?? false
                let transcriptionMatch = memo.transcription?.localizedCaseInsensitiveContains(searchText) ?? false
                return titleMatch || transcriptionMatch
            }
        return Array(filtered.prefix(displayLimit))
    }

    var body: some View {
        // Compute filtered results once per render to avoid repeated recalculation
        let filteredMemos: [VoiceMemo] = {
            if searchText.isEmpty {
                return Array(allVoiceMemos)
            }
            return allVoiceMemos.filter { memo in
                let titleMatch = memo.title?.localizedCaseInsensitiveContains(searchText) ?? false
                let transcriptionMatch = memo.transcription?.localizedCaseInsensitiveContains(searchText) ?? false
                return titleMatch || transcriptionMatch
            }
        }()
        let voiceMemos = Array(filteredMemos.prefix(displayLimit))
        let hasMore = filteredMemos.count > displayLimit

        return NavigationView {
            ZStack {
                // Main content layer
                ZStack(alignment: .bottom) {
                    Color.surfacePrimary
                        .ignoresSafeArea()

                if allVoiceMemos.isEmpty {
                    // Empty state - no memos at all
                    EmptyStateView(onRecordTapped: {
                        showingRecordingView = true
                    })
                } else {
                    // List of voice memos
                    VStack(spacing: 0) {
                        // Search bar
                        HStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textTertiary)

                                TextField("SEARCH", text: $searchText)
                                    .font(.bodySmall)
                                    .foregroundColor(.textPrimary)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.asciiCapable)
                                    .submitLabel(.search)
                                    .focused($isSearchFieldFocused)
                                    .onTapGesture {
                                        isSearching = true
                                    }

                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(themeManager.colors.searchBackground)
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(themeManager.colors.tableBorder, lineWidth: 0.5)
                            )

                            if isSearching {
                                Button(action: {
                                    searchText = ""
                                    isSearching = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }) {
                                    Text("ESC")
                                        .font(.techLabel)
                                        .tracking(1)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)

                        // Results count when searching
                        if !searchText.isEmpty {
                            HStack {
                                Text("\(filteredMemos.count) RESULT\(filteredMemos.count == 1 ? "" : "S")")
                                    .font(.techLabelSmall)
                                    .tracking(1)
                                    .foregroundColor(.textTertiary)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.xs)
                        }

                    if voiceMemos.isEmpty && !searchText.isEmpty {
                        // No search results
                        VStack(spacing: Spacing.md) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.textTertiary)
                            Text("NO MATCHES")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textSecondary)
                            Text("Try a different search term")
                                .font(.bodySmall)
                                .foregroundColor(.textTertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                    }

                    // Table with header
                    VStack(spacing: 0) {
                        // Fixed table header
                        HStack {
                            Text("MEMOS")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1)
                                .foregroundColor(themeManager.colors.textTertiary)

                            Spacer()

                            Text("ACTIONS")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1)
                                .foregroundColor(themeManager.colors.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(themeManager.colors.tableHeaderBackground)

                        // List with native swipe actions and pull-to-refresh
                        List {
                            ForEach(voiceMemos) { memo in
                                VoiceMemoRow(
                                    memo: memo,
                                    audioPlayer: audioPlayer
                                )
                                .id("\(memo.id?.uuidString ?? "")-\((memo.workflowRuns as? Set<WorkflowRun>)?.count ?? 0)")
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(themeManager.colors.tableCellBackground)
                                .listRowSeparatorTint(themeManager.colors.tableDivider)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteMemo(memo)
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
                                    }
                                }
                            }

                            // Load More button
                            if hasMore {
                                Button(action: {
                                    withAnimation(TalkieAnimation.spring) {
                                        displayLimit += 10
                                    }
                                }) {
                                    HStack(spacing: Spacing.xs) {
                                        Spacer()
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Load \(min(10, allVoiceMemos.count - displayLimit)) more")
                                            .font(.system(size: 13))
                                        Spacer()
                                    }
                                    .foregroundColor(themeManager.colors.textSecondary)
                                    .padding(.vertical, 14)
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(themeManager.colors.tableCellBackground)
                                .listRowSeparatorTint(themeManager.colors.tableDivider)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .refreshable {
                            await refreshMemos()
                        }
                    }
                    .background(themeManager.colors.tableCellBackground)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(themeManager.colors.tableBorder, lineWidth: 0.5)
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 90) // Space for mic area
                    } // end VStack

                    // Record button area with distinct background
                    VStack(spacing: 0) {
                        Spacer()

                        // Record area container - expands for push-to-talk
                        VStack(spacing: 0) {
                            // Push-to-talk visualization when active
                            if isPushToTalkActive {
                                VStack(spacing: Spacing.xs) {
                                    // Quick memo indicator
                                    Text("QUICK MEMO")
                                        .font(.techLabelSmall)
                                        .tracking(2)
                                        .foregroundColor(.textTertiary)

                                    // Live waveform - particles style, compact
                                    LiveWaveformView(
                                        levels: pushToTalkRecorder.audioLevels,
                                        height: 48,
                                        color: .recording,
                                        style: .particles
                                    )
                                    .padding(.horizontal, Spacing.xs)
                                    .background(Color.surfacePrimary.opacity(0.3))
                                    .cornerRadius(CornerRadius.sm)
                                    .padding(.horizontal, Spacing.md)

                                    // Duration + release label inline
                                    HStack(spacing: Spacing.sm) {
                                        Text(formatPushToTalkDuration(pushToTalkRecorder.recordingDuration))
                                            .font(.monoSmall)
                                            .foregroundColor(.textPrimary)

                                        Text("·")
                                            .foregroundColor(.textTertiary)

                                        Text("RELEASE TO SAVE")
                                            .font(.techLabelSmall)
                                            .tracking(1)
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                                .padding(.top, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            // Button row: Settings (left) - Record (center) - Mac (right)
                            HStack {
                                // Settings button (left)
                                BottomCircleButton(
                                    icon: "gearshape.fill",
                                    isActive: false
                                ) {
                                    showingSettings = true
                                }

                                Spacer()

                                // Centered record button - flat, tactical style
                                ZStack {
                                    // Subtle glow - only when recording
                                    if isPushToTalkActive {
                                        Circle()
                                            .fill(Color.recording)
                                            .frame(width: 64, height: 64)
                                            .blur(radius: 16)
                                            .opacity(0.4)
                                    }

                                    // Main button - flat solid fill
                                    Circle()
                                        .fill(Color.recording)
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.recordingGlow.opacity(0.4), lineWidth: 1)
                                        )
                                        .scaleEffect(pushToTalkScale)

                                    // Icon changes based on state
                                    if isPushToTalkActive {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.white)
                                            .frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                                .scaleEffect(isPushToTalkActive ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPushToTalkActive)
                                .onTapGesture {
                                    // Short tap opens the sheet
                                    showingRecordingView = true
                                }
                                .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                                    if pressing {
                                        // Started long press - begin push-to-talk
                                        startPushToTalk()
                                    } else if isPushToTalkActive {
                                        // Released - stop and save
                                        stopPushToTalk()
                                    }
                                }, perform: {
                                    // Long press completed (finger still down) - do nothing, handled in pressing
                                })

                                Spacer()

                                // Mac button (right) - animates in when paired
                                ZStack {
                                    if macButtonVisible {
                                        BottomCircleButton(
                                            icon: "desktopcomputer",
                                            isActive: bridgeManager.status == .connected
                                        ) {
                                            showingMacView = true
                                        }
                                        .transition(.asymmetric(
                                            insertion: .scale.combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                        .onAppear {
                                            if justPaired {
                                                // Celebration haptic for newly paired
                                                let generator = UINotificationFeedbackGenerator()
                                                generator.notificationOccurred(.success)
                                                justPaired = false
                                            }
                                        }
                                    } else {
                                        // Invisible placeholder to keep record button centered
                                        Color.clear
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .onAppear {
                                    // Check if we just completed pairing (from another view)
                                    if bridgeManager.justCompletedPairing {
                                        bridgeManager.justCompletedPairing = false
                                        justPaired = true
                                        // Slight delay so the view has time to appear first
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                                macButtonVisible = true
                                            }
                                        }
                                    } else {
                                        // Initialize visibility without animation
                                        macButtonVisible = bridgeManager.isPaired
                                    }
                                }
                                .onChange(of: bridgeManager.isPaired) { wasPaired, isPaired in
                                    if isPaired && !wasPaired {
                                        // Just paired while on this view - animate in
                                        justPaired = true
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                            macButtonVisible = true
                                        }
                                    } else if !isPaired && wasPaired {
                                        // Unpaired - fade out
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            macButtonVisible = false
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.sm)
                            .padding(.bottom, Spacing.sm)
                        }
                        .frame(maxWidth: .infinity)
                        .background {
                            if #available(iOS 26.0, *) {
                                // Liquid Glass background - edge-to-edge, sharp corners
                                Rectangle()
                                    .fill(.clear)
                                    .glassEffect(.regular.interactive())
                                    .ignoresSafeArea(edges: .bottom)
                            } else {
                                // Fallback solid background for older iOS
                                themeManager.colors.cardBackground.opacity(0.95)
                            }
                        }
                        .background {
                            // Top edge highlight (only for non-glass)
                            if #unavailable(iOS 26.0) {
                                VStack {
                                    Rectangle()
                                        .fill(themeManager.colors.tableBorder)
                                        .frame(height: 0.5)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPushToTalkActive)
                }

                // Floating iCloud status banner - pinned above record button area
                if !iCloudStatus.status.isAvailable && !iCloudStatus.isDismissed && !isPushToTalkActive {
                    VStack {
                        Spacer()
                        iCloudStatusBanner
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 100) // Above the glass control bar
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: iCloudStatus.status.isAvailable)
                    .zIndex(1) // Ensure banner stays above other content
                    .allowsHitTesting(true)
                }
                }
                .navigationTitle("TALKIE")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TalkieNavigationHeader(subtitle: "Memos")
                    }
                    #if DEBUG
                    ToolbarItem(placement: .topBarTrailing) {
                        DebugToolbarButton(
                            content: { ListViewDebugContent() },
                            debugInfo: {
                                [
                                    "View": "MemoList",
                                    "Memos": "\(allVoiceMemos.count)",
                                    "Displayed": "\(voiceMemos.count)",
                                    "Search": searchText.isEmpty ? "Off" : "On"
                                ]
                            }
                        )
                    }
                    #endif
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingRecordingView) {
                RecordingView()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $deepLinkMemo) { memo in
                VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer, scrollToActivity: scrollToActivity)
                    .onDisappear {
                        scrollToActivity = false
                    }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .sheet(isPresented: $showingMacView) {
            NavigationView {
                SessionListView()
            }
        }
        .onChange(of: deepLinkManager.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Check for Control Center widget trigger when app becomes active
                checkForControlCenterAction()
            }
        }
        .onAppear {
            // Handle any pending deep link when view appears - prioritize this!
            if deepLinkManager.pendingAction != .none {
                handleDeepLinkAction(deepLinkManager.pendingAction)
            }

            // Check for Control Center widget trigger
            checkForControlCenterAction()

            // Start observing Mac status for async memo processing awareness
            MacStatusObserver.shared.startObserving()

            // Note: Widget data is only refreshed when memos are saved/deleted
            // WidgetKit handles periodic refresh every 30 minutes via timeline policy
        }
        .onDisappear {
            // Stop observing Mac status when view disappears
            MacStatusObserver.shared.stopObserving()
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .record:
            showingRecordingView = true
            deepLinkManager.clearAction()

        case .openMemo(let id):
            // Find memo by ID and show detail
            if let memo = allVoiceMemos.first(where: { $0.id == id }) {
                scrollToActivity = false
                deepLinkMemo = memo
            }
            deepLinkManager.clearAction()

        case .openMemoActivity(let id):
            // Find memo by ID and show detail scrolled to activity
            if let memo = allVoiceMemos.first(where: { $0.id == id }) {
                scrollToActivity = true
                deepLinkMemo = memo
            }
            deepLinkManager.clearAction()

        case .playLastMemo:
            // Play the most recent memo
            if let lastMemo = allVoiceMemos.first,
               let audioData = lastMemo.audioData {
                audioPlayer.togglePlayPause(data: audioData)
            }
            deepLinkManager.clearAction()

        case .search(let query):
            // Set the search text to trigger filtering
            searchText = query
            isSearching = true
            isSearchFieldFocused = true
            deepLinkManager.clearAction()

        case .openSearch:
            // Dismiss any open detail sheet first, then activate search
            deepLinkMemo = nil
            isSearching = true
            // Delay focus slightly to allow sheet dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFieldFocused = true
            }
            deepLinkManager.clearAction()

        case .openAllMemos:
            // Already on memo list, just clear search
            searchText = ""
            isSearching = false
            deepLinkManager.clearAction()

        case .openSettings:
            showingSettings = true
            deepLinkManager.clearAction()

        case .importAudio(let url):
            importAudioFile(from: url)
            deepLinkManager.clearAction()

        case .none:
            break
        }
    }

    /// Import an audio file from external source (e.g., Voice Memos share sheet)
    private func importAudioFile(from url: URL) {
        // Security-scoped access for files from other apps
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Read audio data
            let audioData = try Data(contentsOf: url)

            // Get audio duration
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

            // Create filename without extension for title
            let filename = url.deletingPathExtension().lastPathComponent

            // Create new VoiceMemo
            let newMemo = VoiceMemo(context: viewContext)
            newMemo.id = UUID()
            newMemo.title = filename
            newMemo.audioData = audioData
            newMemo.duration = duration
            newMemo.createdAt = Date()
            newMemo.lastModified = Date()
            newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
            newMemo.originDeviceId = PersistenceController.deviceId
            newMemo.autoProcessed = false  // Mark for macOS auto-processing

            // Save context
            try viewContext.save()

            AppLogger.app.info("Imported audio file: \(filename), duration: \(duration)s, size: \(audioData.count) bytes")

            // Open the imported memo
            deepLinkMemo = newMemo

        } catch {
            AppLogger.app.error("Failed to import audio file: \(error.localizedDescription)")
        }
    }

    /// Check if Control Center widget triggered a recording action
    private func checkForControlCenterAction() {
        guard let defaults = UserDefaults(suiteName: "group.com.jdi.talkie") else {
            AppLogger.app.warning("Failed to access App Group UserDefaults")
            return
        }

        // Synchronize to get latest values from other processes (widget)
        defaults.synchronize()

        if defaults.bool(forKey: "shouldStartRecording") {
            AppLogger.app.info("Control Center recording trigger detected")
            // Clear the flag first
            defaults.set(false, forKey: "shouldStartRecording")
            defaults.synchronize()

            // Trigger recording with slight delay to ensure UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingRecordingView = true
            }
        }
    }

    // MARK: - Pull to Refresh

    private func refreshMemos() async {
        AppLogger.persistence.info("📲 Pull-to-refresh - fetching latest 10 memos from CloudKit")

        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Step 1: Fetch latest 10 VoiceMemo records from CloudKit
        var cloudMemoIds: Set<UUID> = []
        var cloudMemoRecordIds: [CKRecord.ID] = []

        do {
            let memoQuery = CKQuery(recordType: "CD_VoiceMemo", predicate: NSPredicate(value: true))
            memoQuery.sortDescriptors = [NSSortDescriptor(key: "CD_createdAt", ascending: false)]

            let memoResult = try await privateDB.records(matching: memoQuery, inZoneWith: zoneID, resultsLimit: 10)

            for (recordId, recordResult) in memoResult.matchResults {
                if case .success(let record) = recordResult {
                    // Extract UUID from CD_id field
                    if let uuid = record["CD_id"] as? UUID {
                        cloudMemoIds.insert(uuid)
                    } else if let str = record["CD_id"] as? String, let uuid = UUID(uuidString: str) {
                        cloudMemoIds.insert(uuid)
                    }
                    cloudMemoRecordIds.append(recordId)
                }
            }

            AppLogger.persistence.info("📲 CloudKit returned \(cloudMemoIds.count) memo(s)")

        } catch {
            AppLogger.persistence.error("📲 VoiceMemo fetch error: \(error.localizedDescription)")
            // Don't proceed with deletion if we couldn't fetch from CloudKit
            await MainActor.run {
                viewContext.refreshAllObjects()
            }
            return
        }

        // Step 2: Compare with local memos and delete any not in CloudKit
        // Only delete memos that SHOULD be in the top 10 by createdAt but aren't
        await MainActor.run {
            // Sort local memos by createdAt (same as CloudKit query) to compare apples to apples
            let localMemosByDate = allVoiceMemos.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            let localTop10 = Array(localMemosByDate.prefix(10))
            var deletedCount = 0

            for memo in localTop10 {
                guard let memoId = memo.id else { continue }

                // If this memo is in our local top 10 by date but NOT in CloudKit's top 10, it was deleted
                if !cloudMemoIds.contains(memoId) {
                    AppLogger.persistence.info("📲 Deleting memo not found in CloudKit: \(memo.title ?? "Untitled")")

                    // Delete associated audio file
                    if let filename = memo.fileURL {
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let filePath = documentsPath.appendingPathComponent(filename)
                        if FileManager.default.fileExists(atPath: filePath.path) {
                            try? FileManager.default.removeItem(at: filePath)
                        }
                    }

                    viewContext.delete(memo)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                do {
                    try viewContext.save()
                    AppLogger.persistence.info("📲 Deleted \(deletedCount) memo(s) not found in CloudKit")
                    PersistenceController.refreshWidgetData(context: viewContext)
                } catch {
                    AppLogger.persistence.error("📲 Failed to save after deleting memos: \(error.localizedDescription)")
                }
            }
        }

        // Step 3: Fetch WorkflowRun records for the memos we have
        // Uses denormalized memoId field for efficient IN query
        guard !cloudMemoIds.isEmpty else {
            await MainActor.run {
                viewContext.refreshAllObjects()
            }
            return
        }

        do {
            // Query by memoId (UUID) which supports IN predicate
            let memoIdStrings = cloudMemoIds.map { $0.uuidString }
            let workflowQuery = CKQuery(
                recordType: "CD_WorkflowRun",
                predicate: NSPredicate(format: "CD_memoId IN %@", memoIdStrings)
            )

            // Only fetch the fields we need for display (skip large output field)
            let desiredKeys = ["CD_id", "CD_memoId", "CD_workflowId", "CD_workflowName", "CD_workflowIcon", "CD_runDate", "CD_status"]

            var workflowRecords: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor? = nil

            repeat {
                let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor = cursor {
                    result = try await privateDB.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys)
                } else {
                    result = try await privateDB.records(matching: workflowQuery, inZoneWith: zoneID, desiredKeys: desiredKeys, resultsLimit: 200)
                }

                for (_, recordResult) in result.matchResults {
                    if case .success(let record) = recordResult {
                        workflowRecords.append(record)
                    }
                }
                cursor = result.queryCursor
            } while cursor != nil

            AppLogger.persistence.info("📲 CloudKit returned \(workflowRecords.count) workflow run(s) for \(cloudMemoIds.count) memo(s)")

            if !workflowRecords.isEmpty {
                await MainActor.run {
                    importWorkflowRuns(workflowRecords)
                }
            }
        } catch {
            AppLogger.persistence.error("📲 WorkflowRun fetch error: \(error.localizedDescription)")
        }

        await MainActor.run {
            // Force refresh from store (mergeChanges: false) to pick up all relationship changes
            viewContext.refreshAllObjects()
            for memo in allVoiceMemos {
                viewContext.refresh(memo, mergeChanges: false)
            }
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func importWorkflowRuns(_ records: [CKRecord]) {
        var addedCount = 0
        var skippedExisting = 0
        var skippedNoMemo = 0
        var updatedCount = 0
        var affectedMemos: Set<NSManagedObjectID> = []

        // Fetch all local workflow runs once
        let existingRunsRequest: NSFetchRequest<WorkflowRun> = WorkflowRun.fetchRequest()
        let existingRuns = (try? viewContext.fetch(existingRunsRequest)) ?? []
        let existingRunIds = Set(existingRuns.compactMap { $0.id })

        // Fetch all memos once, indexed by ID for fast lookup
        let memoFetch: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        let allMemos = (try? viewContext.fetch(memoFetch)) ?? []
        let memoById: [UUID: VoiceMemo] = Dictionary(uniqueKeysWithValues: allMemos.compactMap { memo in
            guard let id = memo.id else { return nil }
            return (id, memo)
        })

        AppLogger.persistence.info("📲 Processing \(records.count) workflow runs, have \(existingRuns.count) local runs, \(allMemos.count) memos")

        for record in records {
            // Extract run ID
            var runUUID: UUID?
            if let uuid = record["CD_id"] as? UUID {
                runUUID = uuid
            } else if let str = record["CD_id"] as? String, let uuid = UUID(uuidString: str) {
                runUUID = uuid
            }
            guard let runId = runUUID else { continue }

            // Find memo by memoId (denormalized UUID field)
            var memoUUID: UUID?
            if let uuid = record["CD_memoId"] as? UUID {
                memoUUID = uuid
            } else if let str = record["CD_memoId"] as? String, let uuid = UUID(uuidString: str) {
                memoUUID = uuid
            }

            guard let memoId = memoUUID, let memo = memoById[memoId] else {
                skippedNoMemo += 1
                continue
            }

            // Check if we already have this run
            if existingRunIds.contains(runId) {
                // Update existing run's memo relationship if needed
                if let existingRun = existingRuns.first(where: { $0.id == runId }) {
                    if existingRun.memo == nil {
                        existingRun.memo = memo
                        existingRun.memoId = memoId
                        affectedMemos.insert(memo.objectID)
                        updatedCount += 1
                    }
                }
                skippedExisting += 1
                continue
            }

            // Create WorkflowRun (without output - we didn't fetch it)
            let workflowRun = WorkflowRun(context: viewContext)
            workflowRun.id = runId
            workflowRun.memoId = memoId
            workflowRun.workflowId = record["CD_workflowId"] as? UUID
            workflowRun.workflowName = record["CD_workflowName"] as? String
            workflowRun.workflowIcon = record["CD_workflowIcon"] as? String
            workflowRun.runDate = record["CD_runDate"] as? Date
            workflowRun.status = record["CD_status"] as? String
            workflowRun.memo = memo

            affectedMemos.insert(memo.objectID)
            addedCount += 1
        }

        AppLogger.persistence.info("📲 Import summary: added=\(addedCount), updated=\(updatedCount), skippedExisting=\(skippedExisting), skippedNoMemo=\(skippedNoMemo)")

        if addedCount > 0 || updatedCount > 0 {
            do {
                try viewContext.save()

                // Refresh affected memos so their workflowRuns relationship updates
                for objectID in affectedMemos {
                    if let memo = try? viewContext.existingObject(with: objectID) {
                        viewContext.refresh(memo, mergeChanges: true)
                    }
                }
                AppLogger.persistence.info("📲 Refreshed \(affectedMemos.count) memo(s) with new workflow runs")
            } catch {
                AppLogger.persistence.error("📲 Failed to save workflow runs: \(error.localizedDescription)")
            }
        }
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
                // Update widget after deletion
                PersistenceController.refreshWidgetData(context: viewContext)
            } catch {
                let nsError = error as NSError
                AppLogger.persistence.error("Error deleting memo: \(nsError.localizedDescription)")
            }
        }
    }

    private func deleteMemos(offsets: IndexSet) {
        withAnimation {
            offsets.map { displayedMemos[$0] }.forEach { memo in
                deleteMemo(memo)
            }
        }
    }

    private func moveMemos(from source: IndexSet, to destination: Int) {
        // Get memos to move
        var memos = displayedMemos
        memos.move(fromOffsets: source, toOffset: destination)

        // Update sortOrder for all memos
        for (index, memo) in memos.enumerated() {
            memo.sortOrder = Int32(index)
        }

        do {
            try viewContext.save()
        } catch {
            AppLogger.persistence.error("Error moving memos: \(error.localizedDescription)")
        }
    }

    // MARK: - Push-to-Talk

    private func startPushToTalk() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            isPushToTalkActive = true
            pushToTalkScale = 0.9
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        pushToTalkRecorder.startRecording()
    }

    private func stopPushToTalk() {
        // Fully stop (not pause) so file is released for transcription
        pushToTalkRecorder.finalizeRecording()

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Save if we have a recording
        if let url = pushToTalkRecorder.currentRecordingURL,
           pushToTalkRecorder.recordingDuration > 0.5 { // Minimum 0.5s to save
            savePushToTalkRecording(url: url)
        } else {
            // Too short, delete it
            if let url = pushToTalkRecorder.currentRecordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            isPushToTalkActive = false
            pushToTalkScale = 1.0
        }
    }

    private func savePushToTalkRecording(url: URL) {
        // Small delay to ensure audio file is fully flushed to disk after stop()
        // audioRecorder.stop() writes asynchronously
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms for file flush

            let newMemo = VoiceMemo(context: viewContext)
            newMemo.id = UUID()
            newMemo.title = "Quick memo \(formatPushToTalkDate(Date()))"
            newMemo.createdAt = Date()
            newMemo.lastModified = Date()
            newMemo.duration = pushToTalkRecorder.recordingDuration
            newMemo.fileURL = url.lastPathComponent
            newMemo.isTranscribing = false
            newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
            newMemo.originDeviceId = PersistenceController.deviceId
            newMemo.autoProcessed = false  // Mark for macOS auto-run processing

            // Load audio data
            do {
                let audioData = try Data(contentsOf: url)
                newMemo.audioData = audioData
                AppLogger.recording.info("Push-to-talk audio data loaded: \(audioData.count) bytes")
            } catch {
                AppLogger.recording.warning("Failed to load audio data: \(error.localizedDescription)")
            }

            // Save waveform
            if let waveformData = try? JSONEncoder().encode(pushToTalkRecorder.audioLevels) {
                newMemo.waveformData = waveformData
            }

            do {
                try viewContext.save()
                AppLogger.persistence.info("Push-to-talk memo saved")

                // Update widget with new memo
                PersistenceController.refreshWidgetData(context: viewContext)

                let memoObjectID = newMemo.objectID

                // Start transcription after brief delay for Core Data to sync
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if let savedMemo = viewContext.object(with: memoObjectID) as? VoiceMemo {
                    AppLogger.transcription.info("Starting transcription for push-to-talk memo")
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: viewContext)
                }
            } catch {
                AppLogger.persistence.error("Error saving push-to-talk memo: \(error.localizedDescription)")
            }
        }
    }

    private func formatPushToTalkDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatPushToTalkDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - iCloud Status Banner

    private var iCloudStatusBanner: some View {
        Group {
            if iCloudStatus.status == .noAccount {
                // Marketing message for users not signed in
                iCloudPromoView
            } else {
                // Warning for error states
                iCloudWarningView
            }
        }
    }

    /// Promotional banner encouraging sign-in (for .noAccount)
    private var iCloudPromoView: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "icloud")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Text("Sign into iCloud to sync with Talkie for Mac")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            Spacer(minLength: 0)

            Button(action: openICloudSettings) {
                Text("Sign In")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
            }

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    iCloudStatus.dismissBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(4)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.blue))
            } else {
                ZStack {
                    Color.black
                    Color.blue.opacity(0.35)
                }
                .cornerRadius(CornerRadius.md)
            }
        }
    }

    /// Warning banner for error states (restricted, unavailable, etc.)
    private var iCloudWarningView: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "icloud")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Text("Recordings won't sync right now, but we'll catch up when connectivity returns")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))

            Spacer(minLength: 0)

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    iCloudStatus.dismissBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(4)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.blue))
            } else {
                ZStack {
                    Color.black
                    Color.blue.opacity(0.35)
                }
                .cornerRadius(CornerRadius.md)
            }
        }
    }

    private func openICloudSettings() {
        // Deep link to iCloud settings
        if let url = URL(string: "App-Prefs:root=APPLE_ACCOUNT") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            // Fallback to app settings if iCloud URL doesn't work
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Bottom Circle Button

struct BottomCircleButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass button for iOS 26+ - compact, tactical
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? .textPrimary : .textSecondary)
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(.clear)
                            .glassEffect(.regular.interactive())
                    }
            }
            .buttonStyle(.plain)
        } else {
            // Fallback solid button for older iOS
            Button(action: action) {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isActive ? Color.success.opacity(0.08) : Color.surfaceSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isActive ? Color.success.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
                    )
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isActive ? .textPrimary : .textSecondary)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    VoiceMemoListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(DeepLinkManager.shared)
}
