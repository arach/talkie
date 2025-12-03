//
//  VoiceMemoListView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData
import CloudKit

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


    private var filteredMemos: [VoiceMemo] {
        if searchText.isEmpty {
            return Array(allVoiceMemos)
        }
        return allVoiceMemos.filter { memo in
            let titleMatch = memo.title?.localizedCaseInsensitiveContains(searchText) ?? false
            let transcriptionMatch = memo.transcription?.localizedCaseInsensitiveContains(searchText) ?? false
            return titleMatch || transcriptionMatch
        }
    }

    private var voiceMemos: [VoiceMemo] {
        Array(filteredMemos.prefix(displayLimit))
    }

    private var hasMore: Bool {
        filteredMemos.count > displayLimit
    }

    var body: some View {
        NavigationView {
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
                            // Top padding for record area
                            Spacer()
                                .frame(height: Spacing.md)

                            // Push-to-talk visualization when active
                            if isPushToTalkActive {
                                VStack(spacing: Spacing.sm) {
                                    // Quick memo indicator
                                    Text("QUICK MEMO")
                                        .font(.techLabelSmall)
                                        .tracking(2)
                                        .foregroundColor(.textTertiary)

                                    // Live waveform - particles style
                                    LiveWaveformView(
                                        levels: pushToTalkRecorder.audioLevels,
                                        height: 60,
                                        color: .recording,
                                        style: .particles
                                    )
                                    .padding(.horizontal, Spacing.sm)
                                    .background(Color.surfacePrimary.opacity(0.5))
                                    .cornerRadius(CornerRadius.md)
                                    .padding(.horizontal, Spacing.lg)

                                    // Duration
                                    Text(formatPushToTalkDuration(pushToTalkRecorder.recordingDuration))
                                        .font(.monoMedium)
                                        .foregroundColor(.textPrimary)

                                    Text("RELEASE TO SAVE")
                                        .font(.techLabelSmall)
                                        .tracking(1)
                                        .foregroundColor(.textTertiary)
                                }
                                .padding(.top, Spacing.md)
                                .padding(.bottom, Spacing.xs)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            // Centered record button
                            ZStack {
                                // Subtle glow - only when recording
                                if isPushToTalkActive {
                                    Circle()
                                        .fill(Color.recording)
                                        .frame(width: 68, height: 68)
                                        .blur(radius: 20)
                                        .opacity(0.6)
                                }

                                // Main button with subtle border
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.recording, Color.recordingGlow],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 58, height: 58)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.recordingGlow.opacity(0.5), lineWidth: 1.5)
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
                            .scaleEffect(isPushToTalkActive ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPushToTalkActive)
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
                            .padding(.top, Spacing.xs)
                            .padding(.bottom, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            themeManager.colors.cardBackground.opacity(0.95)
                        )
                        .background(
                            // Top edge highlight
                            VStack {
                                Rectangle()
                                    .fill(themeManager.colors.tableBorder)
                                    .frame(height: 0.5)
                                Spacer()
                            }
                        )
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPushToTalkActive)
                }
            }
            .navigationTitle("TALKIE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("TALKIE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.textPrimary)
                        Text("\(allVoiceMemos.count) MEMOS")
                            .font(.techLabelSmall)
                            .tracking(1)
                            .foregroundColor(.textTertiary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
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

            // Note: Widget data is only refreshed when memos are saved/deleted
            // WidgetKit handles periodic refresh every 30 minutes via timeline policy
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

        case .none:
            break
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
        AppLogger.persistence.info("📲 Pull-to-refresh - fetching from CloudKit")

        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Fetch WorkflowRun records using zone fetch (no query needed)
        do {
            var allRecords: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor? = nil

            // First, get all record IDs of type CD_WorkflowRun
            let query = CKQuery(recordType: "CD_WorkflowRun", predicate: NSPredicate(value: true))

            repeat {
                let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor = cursor {
                    result = try await privateDB.records(continuingMatchFrom: cursor)
                } else {
                    result = try await privateDB.records(matching: query, inZoneWith: zoneID, resultsLimit: 100)
                }

                for (_, recordResult) in result.matchResults {
                    if case .success(let record) = recordResult {
                        allRecords.append(record)
                    }
                }
                cursor = result.queryCursor
            } while cursor != nil

            AppLogger.persistence.info("📲 CloudKit returned \(allRecords.count) workflow run records")

            // Import workflow runs into Core Data
            if !allRecords.isEmpty {
                await MainActor.run {
                    importWorkflowRuns(allRecords)
                }
            }
        } catch {
            AppLogger.persistence.error("📲 WorkflowRun fetch error: \(error.localizedDescription)")
        }

        await MainActor.run {
            viewContext.refreshAllObjects()
            for memo in voiceMemos {
                viewContext.refresh(memo, mergeChanges: true)
            }
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func importWorkflowRuns(_ records: [CKRecord]) {
        var addedCount = 0
        var skippedExisting = 0
        var skippedNoMemo = 0
        var updatedCount = 0

        // Fetch all local workflow runs once
        let existingRunsRequest: NSFetchRequest<WorkflowRun> = WorkflowRun.fetchRequest()
        let existingRuns = (try? viewContext.fetch(existingRunsRequest)) ?? []
        let existingRunIds = Set(existingRuns.compactMap { $0.id })

        // Fetch all memos once
        let memoFetch: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        let allMemos = (try? viewContext.fetch(memoFetch)) ?? []

        let runsWithMemo = existingRuns.filter { $0.memo != nil }.count
        let completedRuns = existingRuns.filter { $0.status == "completed" }.count
        AppLogger.persistence.info("📲 Processing \(records.count) records, have \(existingRuns.count) local runs (\(runsWithMemo) with memo, \(completedRuns) completed), \(allMemos.count) memos")

        for record in records {
            // CD_id can be UUID or String depending on how it was stored
            var runUUID: UUID?
            if let uuid = record["CD_id"] as? UUID {
                runUUID = uuid
            } else if let str = record["CD_id"] as? String, let uuid = UUID(uuidString: str) {
                runUUID = uuid
            }
            guard let runId = runUUID else { continue }

            // Find the memo this run belongs to
            guard let memoRef = record["CD_memo"] as? CKRecord.Reference else { continue }
            let memoRecordName = memoRef.recordID.recordName

            var targetMemo: VoiceMemo?
            for memo in allMemos {
                if let memoId = memo.id, memoRecordName.contains(memoId.uuidString) {
                    targetMemo = memo
                    break
                }
            }

            guard let memo = targetMemo else {
                skippedNoMemo += 1
                continue
            }

            // Check if we already have this run
            if existingRunIds.contains(runId) {
                // Update existing run's memo relationship if needed
                if let existingRun = existingRuns.first(where: { $0.id == runId }) {
                    if existingRun.memo == nil {
                        existingRun.memo = memo
                        updatedCount += 1
                    }
                }
                skippedExisting += 1
                continue
            }

            // Create WorkflowRun
            let workflowRun = WorkflowRun(context: viewContext)
            workflowRun.id = runId
            workflowRun.workflowId = record["CD_workflowId"] as? UUID
            workflowRun.workflowName = record["CD_workflowName"] as? String
            workflowRun.workflowIcon = record["CD_workflowIcon"] as? String
            workflowRun.runDate = record["CD_runDate"] as? Date
            workflowRun.status = record["CD_status"] as? String
            workflowRun.output = record["CD_output"] as? String
            workflowRun.memo = memo

            addedCount += 1
        }

        AppLogger.persistence.info("📲 Import summary: added=\(addedCount), updated=\(updatedCount), skippedExisting=\(skippedExisting), skippedNoMemo=\(skippedNoMemo)")

        if addedCount > 0 || updatedCount > 0 {
            try? viewContext.save()
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
        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = "Quick memo \(formatPushToTalkDate(Date()))"
        newMemo.createdAt = Date()
        newMemo.duration = pushToTalkRecorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
        newMemo.autoProcessed = false  // Mark for macOS auto-run processing

        // Load audio data
        do {
            let audioData = try Data(contentsOf: url)
            newMemo.audioData = audioData
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

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let savedMemo = viewContext.object(with: memoObjectID) as? VoiceMemo {
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: viewContext)
                }
            }
        } catch {
            AppLogger.persistence.error("Error saving push-to-talk memo: \(error.localizedDescription)")
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
}

#Preview {
    VoiceMemoListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(DeepLinkManager.shared)
}
