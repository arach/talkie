//
//  HomeView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData
import CloudKit
import AVFoundation
import PhotosUI
import TalkieMobileKit

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

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    // Use StateObject for singletons to avoid unnecessary re-renders
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var iCloudStatus = iCloudStatusManager.shared
    private var bridgeManager = BridgeManager.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \WorkflowRun.runDate, ascending: false)
        ],
        animation: .default
    )
    private var allWorkflowRuns: FetchedResults<WorkflowRun>

    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showingRecordingView = false
    @State private var showingSettings = false
    @State private var showingSSHTerminal = false
    @State private var displayLimit = 10
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var deepLinkMemo: VoiceMemo? = nil
    @State private var scrollToActivity: Bool = false
    @State private var showingKeyboard = false
    @State private var showingKeyboardActivation = false
    @ObservedObject private var headlessDictation = HeadlessDictationService.shared
    @State private var selectedKeyboardCategory: KeyboardModeCategory? = nil
    @State private var showingKeyboardStateSnapshot = false
    @State private var keyboardStateSnapshotText = ""
    @State private var contentFilter: ContentFilter = .memos
    @State private var dockContentFilter: ContentFilter = .memos
    @State private var hasDictations = false  // Track if any dictations exist
    @State private var appSettings = TalkieAppSettings.shared
    @State private var showingFeedbackSheet = false
    @State private var showingShakeMenu = false
    @State private var showingCompanionHelper = false
    @State private var showingLibrary = false
    @State private var isImportingURL = false
    @State private var urlImportError: String?
    @State private var clipboardURL: URL?
    @State private var sshTerminalConnectionManager = SSHTerminalConnectionManager.shared
    @State private var showingOCRPhotoPicker = false
    @State private var ocrPhotoPickerItems: [PhotosPickerItem] = []
    @State private var isRunningOCR = false
    @State private var ocrPreview: OCRPreviewData?
    @State private var shareConfirmationMessage: String?
    @State private var showingMacPastePhotoPicker = false
    @State private var macPastePhotoPickerItems: [PhotosPickerItem] = []
    @State private var showingMacPasteCamera = false
    @State private var isPastingImageToMac = false
    @State private var showingCaptureLauncher = false
    @State private var showingCaptureCompose = false
    @State private var selectedCapture: Capture?
    @State private var selectedHomeDictation: KeyboardDictation?
    @State private var homeDictations: [KeyboardDictation] = []
    @State private var homeCaptures: [Capture] = []
    @State private var libraryFilter: ContentFilter = .memos
    private let sshTerminalRouter = SSHTerminalRouter.shared
    #if DEBUG
    @State private var showDebugTools = false
    #endif

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

    private var showsCompanionShortcutMode: Bool {
        guard appSettings.followComputerShortcutMode else { return false }
        guard bridgeManager.status == .connected else { return false }
        guard let companionState = bridgeManager.companionState else { return false }
        return companionState.isAvailable && companionState.requestedSurface == .shortcut
    }

    private var showsDeckButton: Bool {
        bridgeManager.pairedMacName != nil || showsCompanionShortcutMode
    }

    private var latestSecurityEvent: BridgeSecurityEvent? {
        bridgeManager.companionState?.securityEvents?.first
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

        return NavigationStack {
            if showingCompanionHelper && showsDeckButton {
                CompanionShortcutModeView(
                    showingSettings: $showingSettings,
                    showingHelper: $showingCompanionHelper
                )
            } else {
                standardHomeContent(
                    filteredMemos: filteredMemos,
                    voiceMemos: voiceMemos,
                    hasMore: hasMore,
                    companionShortcutAvailable: showsDeckButton
                )
                .overlay {
                    if showsDeckButton && UIDevice.current.userInterfaceIdiom == .pad {
                        ThreeFingerSwipeCapture(
                            onSwipeUp: { showingCompanionHelper = true },
                            onSwipeDown: { showingCompanionHelper = true }
                        )
                    }
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
        .photosPicker(
            isPresented: $showingOCRPhotoPicker,
            selection: $ocrPhotoPickerItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .onChange(of: ocrPhotoPickerItems) { _, newItems in
            guard let item = newItems.first else { return }
            ocrPhotoPickerItems = []
            Task {
                await createMemoFromOCR(pickerItem: item)
            }
        }
        .photosPicker(
            isPresented: $showingMacPastePhotoPicker,
            selection: $macPastePhotoPickerItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .onChange(of: macPastePhotoPickerItems) { _, newItems in
            guard let item = newItems.first else { return }
            macPastePhotoPickerItems = []
            loadMacPastePhotoPickerItem(item)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            homeActionDock
        }
        .fullScreenCover(isPresented: $showingKeyboard) {
            KeyboardView()
        }
        .sheet(isPresented: $showingKeyboardActivation) {
            KeyboardActivationView()
        }
        .sheet(isPresented: $showingKeyboardStateSnapshot) {
            keyboardStateSnapshotSheet
        }
        .sheet(item: $deepLinkMemo) { memo in
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer, scrollToActivity: scrollToActivity)
                .onDisappear {
                    scrollToActivity = false
                }
        }
        .sheet(isPresented: $showingCaptureCompose) {
            CaptureComposeView { capture in
                saveAndShowCapture(capture)
            }
        }
        .sheet(isPresented: $showingCaptureLauncher) {
            HomeCaptureLauncherView(
                showsMacShortcuts: bridgeManager.isPaired || showsDeckButton,
                macName: bridgeManager.pairedMacName ?? bridgeManager.pairedHostname
            ) { action in
                Task { @MainActor in
                    showingCaptureLauncher = false
                    try? await Task.sleep(for: .milliseconds(120))
                    presentCaptureLauncherAction(action)
                }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            HomeLibraryView(
                selection: $libraryFilter,
                voiceMemos: Array(allVoiceMemos),
                audioPlayer: audioPlayer,
                onContentChanged: refreshHomePreviewCollections
            )
        }
        .sheet(isPresented: $showingMacPasteCamera) {
            CameraImagePicker { image in
                Task {
                    await pasteImageToActiveMac(image)
                }
            }
        }
        .sheet(item: $selectedCapture) { capture in
            CaptureDetailView(capture: capture)
        }
        .sheet(item: $selectedHomeDictation) { dictation in
            DictationDetailView(dictation: dictation)
        }
        .sheet(item: $ocrPreview) { preview in
            OCRPreviewSheet(preview: preview) {
                saveOCRPreview(preview)
            }
        }
        .overlay(alignment: .top) {
            if let message = shareConfirmationMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .onAppear {
            refreshHomePreviewCollections()
        }
        .onChange(of: deepLinkManager.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Check clipboard for a URL when app becomes active
                checkClipboardForURL()

                // Sync any pending captures to Mac
                CaptureSyncService.shared.syncIfConnected()

                // Check for Control Center widget trigger when app becomes active
                checkForControlCenterAction()

                // Refresh dictation count (might have new dictations from keyboard)
                KeyboardDictationStore.shared.reload()
                hasDictations = !KeyboardDictationStore.shared.isEmpty
                sshTerminalConnectionManager.reload()
                refreshHomePreviewCollections()

                if bridgeManager.shouldConnect {
                    Task {
                        await bridgeManager.connect()
                    }
                } else if bridgeManager.status == .connected {
                    Task {
                        await bridgeManager.refreshCompanionState()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            refreshHomePreviewCollections()
        }
        .onChange(of: contentFilter) { _, filter in
            if filter != .memos {
                dismissSearch()
            }
        }
        .onChange(of: showsCompanionShortcutMode) { _, isAvailable in
            if !isAvailable && bridgeManager.pairedMacName == nil {
                showingCompanionHelper = false
            }
        }
            .onAppear {
                // Check if any dictations exist (for showing toggle)
                KeyboardDictationStore.shared.reload()
                hasDictations = !KeyboardDictationStore.shared.isEmpty
                sshTerminalConnectionManager.reload()

                if bridgeManager.shouldConnect {
                    Task {
                        await bridgeManager.connect()
                    }
                } else if bridgeManager.status == .connected {
                    Task {
                        await bridgeManager.refreshCompanionState()
                    }
                }

            // If keyboard mode is active, default to QWERTY category
            if headlessDictation.isActive && selectedKeyboardCategory == nil {
                selectedKeyboardCategory = .qwerty
            }

            // Handle any pending deep link when view appears - prioritize this!
            if deepLinkManager.pendingAction != .none {
                handleDeepLinkAction(deepLinkManager.pendingAction)
            }

            // Check clipboard for URL to import
            checkClipboardForURL()

            // Check for Control Center widget trigger
            checkForControlCenterAction()

            // Start observing Mac status for async memo processing awareness
            MacStatusObserver.shared.startObserving()

            // Release faulted memo data when playback finishes to prevent memory accumulation
            audioPlayer.onPlaybackFinished = {
                PersistenceController.releaseAllFaultedObjects(context: viewContext)
            }

            // Note: Widget data is only refreshed when memos are saved/deleted
            // WidgetKit handles periodic refresh every 30 minutes via timeline policy
        }
        .onDisappear {
            // Stop observing Mac status when view disappears
            MacStatusObserver.shared.stopObserving()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if isSearching {
                    dismissSearch()
                }
            },
            including: isSearching ? .all : .none
        )
        .onShake {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showingShakeMenu = true
        }
        .confirmationDialog("Shake Menu", isPresented: $showingShakeMenu) {
            Button("Send Feedback") { showingFeedbackSheet = true }
            #if DEBUG
            Button("Toggle Debug Tools") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showDebugTools.toggle()
                }
            }
            #endif
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheet()
        }
    }

    private func standardHomeContent(
        filteredMemos: [VoiceMemo],
        voiceMemos: [VoiceMemo],
        hasMore: Bool,
        companionShortcutAvailable: Bool
    ) -> some View {
        ZStack {
            // Main content layer
            ZStack(alignment: .bottom) {
                Color.surfacePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if contentFilter == .memos && !searchText.isEmpty {
                        HStack {
                            Text("\(filteredMemos.count) RESULT\(filteredMemos.count == 1 ? "" : "S")")
                                .font(.techLabelSmall)
                                .tracking(1)
                                .foregroundColor(.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)
                    }

                    if !showsPhoneHomeDashboard {
                        ContentFilterToggle(selection: $contentFilter)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.sm)
                    }

                    if showsPhoneHomeDashboard {
                        phoneHomeDashboard()
                    } else if contentFilter == .captures {
                        CaptureListSection(selectedCapture: $selectedCapture)
                            .padding(.horizontal, Spacing.sm)
                    } else if contentFilter == .dictations {
                        DictationListSection()
                            .padding(.horizontal, Spacing.sm)
                    } else if allVoiceMemos.isEmpty {
                        EmptyStateView(
                            onRecordTapped: {
                                showingRecordingView = true
                            },
                            showsSyncPrompt: iCloudStatus.status == .noAccount && !iCloudStatus.isDismissed,
                            onSyncTapped: openICloudSettings,
                            onDismissSyncPrompt: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    iCloudStatus.dismissBanner()
                                }
                            }
                        )
                    } else if voiceMemos.isEmpty && !searchText.isEmpty {
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
                    } else {
                        if let url = clipboardURL, !isImportingURL {
                            clipboardURLBanner(url: url)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if isImportingURL {
                            urlImportProgressBanner
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let error = urlImportError {
                            urlImportErrorBanner(message: error)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if allVoiceMemos.count >= 5 && !appSettings.tagLocationEnabled && !appSettings.locationTipDismissed {
                            locationTipBanner
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                        }

                        if let securityEvent = latestSecurityEvent {
                            securityEventBanner(securityEvent)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.xs)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        VStack(spacing: 0) {
                            HStack {
                                Text("MEMOS")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(themeManager.colors.textTertiary)

                                Spacer()

                                Text("ACTIONS")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(themeManager.colors.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(themeManager.colors.tableHeaderBackground)

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
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteMemo(memo)
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }
                                    }
                                }

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
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if contentFilter == .memos
                    && !allVoiceMemos.isEmpty
                    && !iCloudStatus.status.isAvailable
                    && !iCloudStatus.isDismissed
                    && !ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT") {
                    VStack {
                        Spacer()
                        iCloudStatusBanner
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 100)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: iCloudStatus.status.isAvailable)
                    .zIndex(1)
                    .allowsHitTesting(true)
                }
            }
        }
        .navigationTitle("TALKIE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
        .navigationDestination(isPresented: $showingSSHTerminal) {
            SSHTerminalView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if showsPhoneHomeDashboard {
                    if companionShortcutAvailable {
                        Button(action: {
                            showingCompanionHelper = true
                        }) {
                            Image(systemName: "rectangle.grid.2x2.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .accessibilityLabel("Open Command Deck")
                    }
                } else if !isSearching {
                    Button(action: {
                        isSearching = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSearchFieldFocused = true
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    #if DEBUG
                    .opacity(showDebugTools ? 0 : 1)
                    #endif
                }
            }
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                if showDebugTools && !isSearching {
                    DebugToolbarButton(
                        content: {
                            VStack(spacing: 10) {
                                ListViewDebugContent()
                                DockLayoutDebugContent()
                            }
                        },
                        debugInfo: {
                            [
                                "View": "MemoList",
                                "Memos": "\(allVoiceMemos.count)",
                                "Displayed": "\(voiceMemos.count)",
                                "Search": searchText.isEmpty ? "Off" : "On"
                            ]
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            #endif
            ToolbarItem(placement: .principal) {
                if isSearching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textTertiary)

                        TextField("Search memos...", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isSearchFieldFocused)

                        Button(action: dismissSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                } else {
                    TalkieNavigationHeader(subtitle: "Home")
                }
            }
            if !isSearching {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !showsPhoneHomeDashboard && companionShortcutAvailable {
                        Button(action: {
                            showingCompanionHelper = true
                        }) {
                            Image(systemName: "rectangle.grid.2x2.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .accessibilityLabel("Open Helper")
                    }

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private var showsPhoneHomeDashboard: Bool {
        searchText.isEmpty
    }

    private var recentWorkflowRunPreviews: [WorkflowRun] {
        Array(
            allWorkflowRuns
                .filter { $0.runDate != nil }
                .prefix(3)
        )
    }

    private var homeRecentEntries: [HomeRecentEntry] {
        let memoEntries = allVoiceMemos.map { HomeRecentEntry.memo($0) }
        let dictationEntries = homeDictations.map { HomeRecentEntry.dictation($0) }
        let captureEntries = homeCaptures.map { HomeRecentEntry.capture($0) }

        return (memoEntries + dictationEntries + captureEntries)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(8)
            .map { $0 }
    }

    private var homeRecentTotalCount: Int {
        allVoiceMemos.count + homeDictations.count + homeCaptures.count
    }

    private func phoneHomeDashboard() -> some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                if let url = clipboardURL, !isImportingURL {
                    clipboardURLBanner(url: url)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isImportingURL {
                    urlImportProgressBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let error = urlImportError {
                    urlImportErrorBanner(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if allVoiceMemos.count >= 5 && !appSettings.tagLocationEnabled && !appSettings.locationTipDismissed {
                    locationTipBanner
                }

                if let securityEvent = latestSecurityEvent {
                    securityEventBanner(securityEvent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if homeRecentTotalCount == 0 {
                    EmptyStateView(
                        onRecordTapped: {
                            showingRecordingView = true
                        },
                        showsSyncPrompt: iCloudStatus.status == .noAccount && !iCloudStatus.isDismissed,
                        onSyncTapped: openICloudSettings,
                        onDismissSyncPrompt: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                iCloudStatus.dismissBanner()
                            }
                        }
                    )
                } else {
                    recentDashboardSection(entries: homeRecentEntries)

                    HomePreviewSection(title: "COMMAND DECK") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.xs) {
                                HomeToolButton(
                                    title: "Record",
                                    icon: "mic.badge.plus",
                                    tint: .indigo,
                                    width: 88,
                                    accessibilityLabel: "Record a memo on your Mac"
                                ) {
                                    Task { await triggerHomeMacShortcut(shortcutID: "talkie-record", fallbackTitle: "RECORD MEMO") }
                                }

                                HomeToolButton(
                                    title: "Dictate",
                                    icon: "waveform.badge.mic",
                                    tint: .orange,
                                    width: 88,
                                    accessibilityLabel: "Start dictation on your Mac"
                                ) {
                                    Task { await triggerHomeMacShortcut(shortcutID: "talkie-dictate", fallbackTitle: "DICTATE") }
                                }

                                HomeToolButton(
                                    title: "Palette",
                                    icon: "command",
                                    tint: .indigo,
                                    width: 88
                                ) {
                                    Task { await triggerHomeMacShortcut(shortcutID: "talkie-command", fallbackTitle: "PALETTE") }
                                }

                                HomeToolButton(
                                    title: "Claude",
                                    icon: "sparkles",
                                    tint: .purple,
                                    width: 88
                                ) {
                                    Task { await triggerHomeMacShortcut(shortcutID: "mac-claude", fallbackTitle: "CLAUDE") }
                                }

                                HomeToolButton(
                                    title: "Shell",
                                    icon: "terminal",
                                    tint: .mint,
                                    width: 88
                                ) {
                                    if bridgeManager.status == .connected {
                                        Task { await triggerHomeMacShortcut(shortcutID: "talkie-ssh", fallbackTitle: "SHELL") }
                                    } else {
                                        openTerminalPicker()
                                    }
                                }
                            }
                            .padding(Spacing.sm)
                        }
                    }

                    if !recentWorkflowRunPreviews.isEmpty {
                        HomePreviewSection(
                            title: "RECENT ACTIONS",
                            itemCount: allWorkflowRuns.filter { $0.runDate != nil }.count
                        ) {
                            let workflowPreviewItems = recentWorkflowRunPreviews
                            previewListContainer {
                                ForEach(workflowPreviewItems.enumerated(), id: \.element.objectID) { index, run in
                                    Button {
                                        openWorkflowRun(run)
                                    } label: {
                                        HomeWorkflowRunPreviewRow(run: run)
                                    }
                                    .buttonStyle(.plain)

                                    if index < workflowPreviewItems.count - 1 {
                                        previewDivider
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func recentDashboardSection(entries: [HomeRecentEntry]) -> some View {
        HomePreviewSection(
            title: "RECENT",
            itemCount: homeRecentTotalCount,
            trailingTitle: "All",
            trailingAction: {
                showingLibrary = true
            }
        ) {
            homeRecentList(entries: entries)
        }
    }

    @ViewBuilder
    private func homeRecentList(entries: [HomeRecentEntry]) -> some View {
        List {
            ForEach(entries) { entry in
                homeRecentListRow(entry)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(entries.count) * 62)
    }

    @ViewBuilder
    private func homeRecentListRow(_ entry: HomeRecentEntry) -> some View {
        switch entry {
        case .memo(let memo):
            VoiceMemoRow(
                memo: memo,
                audioPlayer: audioPlayer
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(themeManager.colors.tableCellBackground)
            .listRowSeparatorTint(themeManager.colors.tableDivider)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteMemo(memo)
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            }

        case .dictation(let dictation):
            Button {
                selectedHomeDictation = dictation
            } label: {
                DictationRow(dictation: dictation)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(themeManager.colors.tableCellBackground)
            .listRowSeparatorTint(themeManager.colors.tableDivider)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    promoteHomeDictationToMemo(dictation)
                } label: {
                    Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                }
                .tint(.accentColor)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteHomeDictation(dictation)
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            }

        case .capture(let capture):
            Button {
                selectedCapture = capture
            } label: {
                CaptureRow(capture: capture)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(themeManager.colors.tableCellBackground)
            .listRowSeparatorTint(themeManager.colors.tableDivider)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteHomeCapture(capture)
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func previewListContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(themeManager.colors.tableCellBackground)
    }

    private var previewDivider: some View {
        Rectangle()
            .fill(themeManager.colors.tableDivider)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func refreshHomePreviewCollections() {
        KeyboardDictationStore.shared.reload()
        CaptureStore.shared.reload()
        homeDictations = KeyboardDictationStore.shared.all()
        homeCaptures = CaptureStore.shared.all()
        hasDictations = !homeDictations.isEmpty
    }

    private func promoteHomeDictationToMemo(_ dictation: KeyboardDictation) {
        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()
        memo.title = deriveMemoTitle(from: dictation.text)
        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(dictation.timestamp.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        memo.addSystemTranscript(
            content: dictation.text,
            fromMacOS: false,
            engine: "keyboard_dictation"
        )

        do {
            try viewContext.save()
            PersistenceController.refreshWidgetData(context: viewContext)
            KeyboardDictationStore.shared.delete(dictation.id)
            withAnimation {
                refreshHomePreviewCollections()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            AppLogger.app.error("Failed to promote dictation to memo: \(error)")
        }
    }

    private func deleteHomeDictation(_ dictation: KeyboardDictation) {
        KeyboardDictationStore.shared.delete(dictation.id)
        withAnimation {
            refreshHomePreviewCollections()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteHomeCapture(_ capture: Capture) {
        CaptureStore.shared.delete(capture.id)
        withAnimation {
            refreshHomePreviewCollections()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deriveMemoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count < text.count ? title + "…" : title
    }

    private func loadMacPastePhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                showShareConfirmation("Couldn't load image", feedback: .warning)
                return
            }

            await pasteImageToActiveMac(image)
        }
    }

    @MainActor
    private func pasteImageToActiveMac(_ image: UIImage) async {
        guard !isPastingImageToMac else { return }
        isPastingImageToMac = true
        defer { isPastingImageToMac = false }

        if bridgeManager.status != .connected && bridgeManager.isPaired {
            await bridgeManager.connect()
        }

        guard bridgeManager.status == .connected else {
            showShareConfirmation("Pair a Mac to paste images", feedback: .warning)
            return
        }

        guard let payload = preparedCompanionImagePayload(from: image) else {
            showShareConfirmation("Couldn't prepare image", feedback: .warning)
            return
        }

        do {
            let response = try await bridgeManager.client.companionPasteImage(
                imageData: payload.data,
                mimeType: payload.mimeType,
                autoPaste: true
            )

            if response.ok {
                let message = response.message?.isEmpty == false ? response.message! : "Image pasted"
                showShareConfirmation(message.uppercased())
            } else {
                showShareConfirmation("IMAGE PASTE FAILED", feedback: .warning)
            }
        } catch {
            showShareConfirmation("IMAGE PASTE FAILED", feedback: .warning)
        }
    }

    private func preparedCompanionImagePayload(from image: UIImage) -> (data: Data, mimeType: String)? {
        let resizedImage = resizedCompanionPasteImageIfNeeded(image)

        if let pngData = resizedImage.pngData(), pngData.count <= 6_000_000 {
            return (pngData, "image/png")
        }

        if let jpegData = resizedImage.jpegData(compressionQuality: 0.9) {
            return (jpegData, "image/jpeg")
        }

        return nil
    }

    private func resizedCompanionPasteImageIfNeeded(
        _ image: UIImage,
        maxDimension: CGFloat = 2400
    ) -> UIImage {
        let largestDimension = max(image.size.width, image.size.height)
        guard largestDimension > maxDimension, largestDimension > 0 else {
            return image
        }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(
            width: floor(image.size.width * scale),
            height: floor(image.size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func openWorkflowRun(_ run: WorkflowRun) {
        guard let memo = run.memo ?? allVoiceMemos.first(where: { $0.id == run.memoId }) else { return }
        scrollToActivity = true
        deepLinkMemo = memo
    }

    private func openLibrary(_ filter: ContentFilter) {
        libraryFilter = filter
        showingLibrary = true
    }

    @MainActor
    private func presentCaptureLauncherAction(_ action: HomeCaptureLauncherAction) {
        switch action {
        case .recordMemo:
            showingRecordingView = true
        case .startDictation:
            showingKeyboard = true
        case .recordMemoOnMac:
            Task {
                await triggerHomeMacShortcut(
                    shortcutID: "talkie-record",
                    fallbackTitle: "Record Memo"
                )
            }
        case .startDictationOnMac:
            Task {
                await triggerHomeMacShortcut(
                    shortcutID: "talkie-dictate",
                    fallbackTitle: "Dictate"
                )
            }
        case .newCapture:
            showingCaptureCompose = true
        case .scanHandwriting:
            showingOCRPhotoPicker = true
        case .pasteImageToMac:
            showingMacPastePhotoPicker = true
        case .captureAndPasteToMac:
            showingMacPasteCamera = true
        }
    }

    @MainActor
    private func triggerHomeMacShortcut(shortcutID: String, fallbackTitle: String) async {
        if bridgeManager.status != .connected && bridgeManager.isPaired {
            await bridgeManager.connect()
        }

        guard bridgeManager.status == .connected else {
            showShareConfirmation("Pair a Mac to use \(fallbackTitle.lowercased())", feedback: .warning)
            return
        }

        do {
            let response = try await bridgeManager.triggerCompanionShortcut(shortcutID)
            if response.ok {
                showShareConfirmation(
                    (response.message?.isEmpty == false ? response.message! : fallbackTitle).uppercased()
                )
                await bridgeManager.refreshCompanionState()
            } else {
                showShareConfirmation("\(fallbackTitle) FAILED", feedback: .warning)
            }
        } catch {
            showShareConfirmation("\(fallbackTitle) FAILED", feedback: .warning)
        }
    }

    private var keyboardStateSnapshotSheet: some View {
        NavigationStack {
            ScrollView {
                Text(keyboardStateSnapshotText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color.surfacePrimary)
            .navigationTitle("Keyboard Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingKeyboardStateSnapshot = false
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Refresh") {
                        keyboardStateSnapshotText = buildKeyboardStateSnapshot()
                    }
                    Button("Copy") {
                        UIPasteboard.general.string = keyboardStateSnapshotText
                    }
                }
            }
            .onAppear {
                if keyboardStateSnapshotText.isEmpty {
                    keyboardStateSnapshotText = buildKeyboardStateSnapshot()
                }
            }
        }
    }

    private var homeActionDock: some View {
        ActionDock(
            showingRecordingView: $showingRecordingView,
            showingKeyboard: $showingKeyboard,
            showingSSHTerminal: $showingSSHTerminal,
            showingCaptureLauncher: $showingCaptureLauncher,
            showingCaptureCompose: $showingCaptureCompose,
            contentFilter: showsPhoneHomeDashboard ? $dockContentFilter : $contentFilter,
            terminalState: terminalDockState,
            onTerminalTapped: openTerminalPicker
        )
    }

    private func buildKeyboardStateSnapshot() -> String {
        let shared = DictationSharedStore.shared.snapshot()
        let now = Date().timeIntervalSince1970

        let appHeartbeatAge: String = {
            guard shared.appHeartbeat > 0 else { return "none" }
            return "\(Int((now - shared.appHeartbeat).rounded()))s"
        }()

        let keyboardHeartbeatAge: String = {
            guard shared.keyboardHeartbeat > 0 else { return "none" }
            return "\(Int((now - shared.keyboardHeartbeat).rounded()))s"
        }()

        let commandSummary: String = {
            guard let command = shared.command else { return "none" }
            let age = Int((now - command.requestedAt).rounded())
            return "\(command.kind.rawValue) id=\(command.id.uuidString) session=\(command.sessionId.uuidString) age=\(age)s epoch=\(command.epoch)"
        }()

        let ackSummary: String = {
            guard let ack = shared.commandAck else { return "none" }
            return "\(ack.id.uuidString) phase=\(ack.phase.rawValue)"
        }()

        let resultSummary: String = {
            guard let result = shared.lastResult else { return "none" }
            return "session=\(result.sessionId.uuidString) chars=\(result.text.count)"
        }()

        let errorSummary: String = {
            guard let error = shared.lastError else { return "none" }
            return "session=\(error.sessionId?.uuidString ?? "none") message=\(error.message)"
        }()

        return """
        Headless
          isActive: \(headlessDictation.isActive)
          isRecording: \(headlessDictation.isRecording)
          isInReadyMode: \(headlessDictation.isInReadyMode)

        Shared State
          phase: \(shared.phase.rawValue)
          phaseAge: \(Int(shared.phaseAge.rounded()))s
          capability: \(shared.capability.rawValue)
          epoch: \(shared.epoch)
          activeSession: \(shared.activeSessionId?.uuidString ?? "none")
          command: \(commandSummary)
          ack: \(ackSummary)
          result: \(resultSummary)
          error: \(errorSummary)
          appHeartbeatAge: \(appHeartbeatAge)
          keyboardHeartbeatAge: \(keyboardHeartbeatAge)
        """
    }

    private func dismissSearch() {
        searchText = ""
        isSearching = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openTerminalPicker() {
        AppLogger.ui.info("Opening terminal picker from Home")
        sshTerminalRouter.beginPresentation()
        sshTerminalConnectionManager.requestResume(for: nil)
        showingSSHTerminal = true
    }

    private var terminalDockState: ActionDockTerminalState {
        if sshTerminalConnectionManager.devices.count > 1 {
            return .open
        }

        if sshTerminalConnectionManager.activeConnection != nil {
            return .resume
        }

        if sshTerminalConnectionManager.devices.isEmpty {
            return .pair
        }

        return .open
    }

    /// Dismiss all open sheets so a new one can present.
    /// SwiftUI only allows one sheet at a time per view hierarchy.
    private func dismissAllSheets() {
        showingSettings = false
        showingSSHTerminal = false
        showingRecordingView = false
        showingKeyboard = false
        showingKeyboardActivation = false
        showingKeyboardStateSnapshot = false
        deepLinkMemo = nil
    }

    // MARK: - Deep Link Handling

    private func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .record:
            showingRecordingView = true
            deepLinkManager.clearAction()

        case .dictate:
            // Route dictate to the same view as keyboardActivate
            AppLogger.app.info("Handling dictate deep link - showing KeyboardActivationView")
            // Mark early that activation is starting - prevents race condition with handleAppDidBecomeActive
            HeadlessDictationService.shared.prepareForDictation()
            // Dismiss any other sheets first — SwiftUI only presents one sheet at a time
            dismissAllSheets()
            showingKeyboardActivation = true
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

        case .openSSHTerminal:
            openTerminalPicker()
            deepLinkManager.clearAction()

        case .importAudio(let url):
            importAudioFile(from: url)
            deepLinkManager.clearAction()

        case .importURL(let url, let title):
            importURLContent(from: url, suggestedTitle: title)
            deepLinkManager.clearAction()

        case .processShare(let id):
            processShareFromExtension(id: id)
            deepLinkManager.clearAction()

        case .keyboardActivate:
            // Mark early that activation is starting - prevents race condition with handleAppDidBecomeActive
            HeadlessDictationService.shared.prepareForDictation()
            // Dismiss any other sheets first — SwiftUI only presents one sheet at a time
            dismissAllSheets()
            showingKeyboardActivation = true
            deepLinkManager.clearAction()

        case .keyboardDeactivate:
            HeadlessDictationService.shared.deactivate(explicit: true)
            deepLinkManager.clearAction()

        case .keyboardView:
            showingKeyboard = true
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

    /// Import content from a URL as a bookmark-style capture.
    private func importURLContent(from url: URL, suggestedTitle: String? = nil) {
        guard !isImportingURL else { return }
        isImportingURL = true
        urlImportError = nil

        Task {
            defer { isImportingURL = false }

            let result = await URLBookmarkMetadataService.buildCapture(
                from: url,
                suggestedTitle: suggestedTitle,
                sourceDevice: "iPhone",
                ingestionMethod: "deeplink"
            )

            let captureID = result.capture.id
            var capture = result.capture
            if let imageData = result.imageData {
                let filename = CaptureStore.shared.saveImage(imageData, id: captureID)
                capture = Capture(
                    id: captureID,
                    sourceType: capture.sourceType,
                    text: capture.text,
                    title: capture.title,
                    sourceURL: capture.sourceURL,
                    bookmark: capture.bookmark,
                    imageFilename: filename,
                    deferredPageFilenames: capture.deferredPageFilenames,
                    totalPageCount: capture.totalPageCount,
                    timestamp: capture.timestamp,
                    syncedToMac: capture.syncedToMac
                )
            }

            await MainActor.run {
                saveAndShowCapture(capture)
            }
        }
    }

    /// Process content queued by the Share Extension — local-first with background Mac sync
    private func processShareFromExtension(id: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else { return }

        let fileURL = containerURL
            .appendingPathComponent("Library/Application Support/Talkie/share-queue")
            .appendingPathComponent("\(id).json")

        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.app.warning("Share queue: file not found for \(id)")
            return
        }

        struct SharePayload: Codable {
            let sourceType: String
            let text: String
            var title: String?
            var sourceURL: String?
            var imageBase64: String?
            var imageFilename: String?
        }

        guard let payload = try? JSONDecoder().decode(SharePayload.self, from: data) else {
            AppLogger.app.error("Share queue: failed to decode \(id)")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        // Clean up the queued file
        try? FileManager.default.removeItem(at: fileURL)

        // Route by source type
        switch payload.sourceType {
        case "url":
            if let urlString = payload.sourceURL, let url = URL(string: urlString) {
                Task {
                    let result = await URLBookmarkMetadataService.buildCapture(
                        from: url,
                        suggestedTitle: payload.title,
                        sourceDevice: "iPhone",
                        ingestionMethod: "share-extension"
                    )

                    let captureID = result.capture.id
                    var capture = result.capture
                    if let imageData = result.imageData {
                        let filename = CaptureStore.shared.saveImage(imageData, id: captureID)
                        capture = Capture(
                            id: captureID,
                            sourceType: capture.sourceType,
                            text: capture.text,
                            title: capture.title,
                            sourceURL: capture.sourceURL,
                            bookmark: capture.bookmark,
                            imageFilename: filename,
                            deferredPageFilenames: capture.deferredPageFilenames,
                            totalPageCount: capture.totalPageCount,
                            timestamp: capture.timestamp,
                            syncedToMac: capture.syncedToMac
                        )
                    }

                    saveAndShowCapture(capture)
                }
            }

        case "photo":
            Task {
                await processSharedPhoto(
                    imageBase64: payload.imageBase64,
                    imageFilename: payload.imageFilename
                )
            }

        case "text":
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let capture = Capture(
                sourceType: "text",
                text: text,
                title: payload.title
            )
            saveAndShowCapture(capture)

        default:
            AppLogger.app.warning("Share queue: unknown sourceType \(payload.sourceType)")
        }
    }

    private func processSharedPhoto(imageBase64: String?, imageFilename: String?) async {
        guard let base64 = imageBase64,
              let imageData = Data(base64Encoded: base64),
              let image = UIImage(data: imageData) else {
            AppLogger.app.warning("Share: couldn't decode photo data")
            return
        }

        // Run OCR
        var ocrText = ""
        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            ocrText = result.text
            AppLogger.ai.info("Share OCR: extracted \(ocrText.count) chars")
        } catch {
            AppLogger.ai.info("Share OCR: no text found in image")
        }

        // Save image file
        let captureId = UUID()
        let savedFilename = CaptureStore.shared.saveImage(imageData, id: captureId)

        let capture = Capture(
            id: captureId,
            sourceType: "photo",
            text: ocrText.isEmpty ? "Photo (no text detected)" : ocrText,
            imageFilename: savedFilename
        )

        await MainActor.run {
            saveAndShowCapture(capture)
        }
    }

    private func saveAndShowCapture(_ capture: Capture) {
        CaptureStore.shared.add(capture)

        // Switch to captures tab and show detail
        withAnimation {
            contentFilter = .captures
        }
        selectedCapture = capture

        if capture.bookmark != nil {
            showShareConfirmation("Saved bookmark")
        } else {
            let wordCount = capture.wordCount
            showShareConfirmation("Captured - \(wordCount) word\(wordCount == 1 ? "" : "s")")
        }

        // Try syncing to Mac
        CaptureSyncService.shared.syncIfConnected()

        // Auto-title in background using Apple Intelligence
        if capture.title == nil || capture.title?.isEmpty == true {
            Task {
                await OnDeviceAIService.shared.autoTitleCapture(capture)
            }
        }
    }

    private func showShareConfirmation(
        _ message: String,
        feedback: UINotificationFeedbackGenerator.FeedbackType = .success
    ) {
        withAnimation(.easeInOut(duration: 0.3)) {
            shareConfirmationMessage = message
        }
        UINotificationFeedbackGenerator().notificationOccurred(feedback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                shareConfirmationMessage = nil
            }
        }
    }

    /// Check clipboard for a URL and update clipboardURL state
    private func checkClipboardForURL() {
        guard UIPasteboard.general.hasURLs,
              let url = UIPasteboard.general.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            clipboardURL = nil
            return
        }
        clipboardURL = url
    }

    /// Check if Control Center widget triggered a recording action
    private func checkForControlCenterAction() {
        guard let defaults = UserDefaults(suiteName: TalkieMobileRuntimeIdentifiers.appGroupIdentifier) else {
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

            // Trigger recording immediately - no delay needed
            showingRecordingView = true
        }
    }

    // MARK: - Pull to Refresh

    private func refreshMemos() async {
        AppLogger.persistence.info("📲 Pull-to-refresh - fetching latest 10 memos from CloudKit")

        let container = CKContainer(identifier: TalkieMobileRuntimeIdentifiers.cloudKitContainerIdentifier)
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
        // Use uniquingKeysWith to handle duplicate IDs gracefully (keep first)
        let memoById: [UUID: VoiceMemo] = Dictionary(
            allMemos.compactMap { memo -> (UUID, VoiceMemo)? in
                guard let id = memo.id else { return nil }
                return (id, memo)
            },
            uniquingKeysWith: { first, _ in first }
        )

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

    private var locationTipBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "location")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.active)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tag memos with location")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text("Remember where you recorded. Enable in Settings.")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.active)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.active.opacity(0.1))
                    .cornerRadius(CornerRadius.sm)
            }

            Button {
                withAnimation { appSettings.locationTipDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func securityEventBanner(_ event: BridgeSecurityEvent) -> some View {
        let tint = securityEventTint(event)

        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: securityEventIcon(event))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text(event.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: Spacing.xs)

            Button {
                Task {
                    await bridgeManager.acknowledgeSecurityEvent(id: event.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(Color.surfaceSecondary.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.surfaceSecondary.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
        )
    }

    private func securityEventIcon(_ event: BridgeSecurityEvent) -> String {
        if event.type.contains("ssh") {
            return "terminal"
        }
        if event.type.contains("pair") || event.type.contains("approved") {
            return "checkmark.shield"
        }
        return "shield"
    }

    private func securityEventTint(_ event: BridgeSecurityEvent) -> Color {
        switch event.severity {
        case "critical":
            return .red
        case "warning":
            return .orange
        case "notice":
            return .blue
        default:
            return .secondary
        }
    }

    // MARK: - URL Import Banners

    private func clipboardURLBanner(url: URL) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.active)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import from clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation { importURLContent(from: url) }
            } label: {
                Text("Import")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.active)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.active.opacity(0.1))
                    .cornerRadius(CornerRadius.sm)
            }

            Button {
                withAnimation { clipboardURL = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var urlImportProgressBanner: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .tint(.textSecondary)

            Text("Importing web content...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textPrimary)

            Spacer()
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func urlImportErrorBanner(message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.recording)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation { urlImportError = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(Color.recording.opacity(0.3), lineWidth: 0.5)
        )
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

    // MARK: - Screenshot OCR

    private func createMemoFromOCR(pickerItem: PhotosPickerItem) async {
        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            AppLogger.ai.warning("OCR: couldn't load selected image")
            return
        }

        await MainActor.run { isRunningOCR = true }

        // Run OCR
        var ocrText = ""
        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            ocrText = result.text
            AppLogger.ai.info("OCR: extracted \(ocrText.count) chars")
        } catch {
            AppLogger.ai.info("OCR: no text found in image")
        }

        await MainActor.run {
            isRunningOCR = false
            // Show preview for review instead of auto-saving
            ocrPreview = OCRPreviewData(image: image, imageData: data, text: ocrText)
        }
    }

    private func saveOCRPreview(_ preview: OCRPreviewData) {
        let captureId = UUID()
        let savedFilename = CaptureStore.shared.saveImage(preview.imageData, id: captureId)

        let capture = Capture(
            id: captureId,
            sourceType: "photo",
            text: preview.text.isEmpty ? "Photo (no text detected)" : preview.text,
            imageFilename: savedFilename
        )

        saveAndShowCapture(capture)
        ocrPreview = nil
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 36, height: 36)

                Image(systemName: "icloud")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Keep Talkie in sync")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))

                Text("Turn on iCloud when you want your iPhone and Mac to stay aligned.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: openICloudSettings) {
                Text("Open Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(.capsule)
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
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.clear)
                .glassEffect(.regular.tint(.blue.opacity(0.45)))
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
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.clear)
                .glassEffect(.regular.tint(.blue))
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

// MARK: - Content Filter

enum ContentFilter: String, CaseIterable {
    case memos = "Memos"
    case dictations = "Dictations"
    case captures = "Items"

    var icon: String {
        switch self {
        case .memos: return "waveform"
        case .dictations: return "keyboard"
        case .captures: return "tray.and.arrow.down"
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .memos: return "waveform"
        case .dictations: return "keyboard"
        case .captures: return "tray"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .memos: return "NO MEMOS"
        case .dictations: return "NO DICTATIONS"
        case .captures: return "NO ITEMS"
        }
    }

    var emptyStateSubtitle: String {
        switch self {
        case .memos: return "Record or import something to start your library"
        case .dictations: return "Use dictation to build up quick captures"
        case .captures: return "Photos, links, handwriting, and shared text will show up here"
        }
    }

    var searchPrompt: String {
        switch self {
        case .memos:
            "Search memos"
        case .dictations:
            "Search dictations"
        case .captures:
            "Search items"
        }
    }
}

private struct HomePreviewSection<Content: View>: View {
    let title: String
    var itemCount: Int? = nil
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                    .foregroundColor(themeManager.colors.textTertiary)

                if let itemCount {
                    Text("\(itemCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surfaceSecondary)
                        .clipShape(Capsule())
                }

                Spacer()

                if let trailingTitle, let trailingAction {
                    Button(trailingTitle, action: trailingAction)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(themeManager.colors.tableHeaderBackground)

            content()
        }
        .background(themeManager.colors.tableCellBackground)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(themeManager.colors.tableBorder, lineWidth: 0.5)
        )
    }
}

private enum HomeRecentEntry: Identifiable {
    case memo(VoiceMemo)
    case dictation(KeyboardDictation)
    case capture(Capture)

    var id: String {
        switch self {
        case .memo(let memo):
            "memo-\(memo.id?.uuidString ?? memo.objectID.uriRepresentation().absoluteString)"
        case .dictation(let dictation):
            "dictation-\(dictation.id.uuidString)"
        case .capture(let capture):
            "capture-\(capture.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .memo(let memo):
            memo.createdAt ?? .distantPast
        case .dictation(let dictation):
            dictation.timestamp
        case .capture(let capture):
            capture.timestamp
        }
    }
}

private enum HomeCaptureLauncherAction {
    case recordMemo
    case startDictation
    case recordMemoOnMac
    case startDictationOnMac
    case newCapture
    case scanHandwriting
    case pasteImageToMac
    case captureAndPasteToMac
}

private struct HomeCaptureLauncherView: View {
    @Environment(\.dismiss) private var dismiss

    let showsMacShortcuts: Bool
    let macName: String?
    let onSelect: (HomeCaptureLauncherAction) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        premiumPrimaryCard

                        VStack(spacing: Spacing.sm) {
                            Text("ON THIS IPHONE")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: Spacing.sm) {
                                compactCard(
                                    title: "Dictation",
                                    subtitle: "Direct text input",
                                    icon: "character.cursor.ibeam",
                                    tint: .orange,
                                    action: .startDictation
                                )

                                compactCard(
                                    title: "Capture",
                                    subtitle: "Photo, web, or text",
                                    icon: "plus.viewfinder",
                                    tint: .blue,
                                    action: .newCapture
                                )
                            }

                            compactCard(
                                title: "Scan Handwriting",
                                subtitle: "Use a photo and run OCR",
                                icon: "text.viewfinder",
                                tint: .green,
                                action: .scanHandwriting
                            )

                            if showsMacShortcuts {
                                Text(macSectionTitle)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, Spacing.xs)

                                HStack(spacing: Spacing.sm) {
                                    compactCard(
                                        title: "Record on Mac",
                                        subtitle: "Start a memo on your paired Mac",
                                        icon: "mic.badge.plus",
                                        tint: .indigo,
                                        action: .recordMemoOnMac
                                    )

                                    compactCard(
                                        title: "Dictate on Mac",
                                        subtitle: "Start live dictation on your Mac",
                                        icon: "waveform.badge.mic",
                                        tint: .orange,
                                        action: .startDictationOnMac
                                    )
                                }

                                HStack(spacing: Spacing.sm) {
                                    compactCard(
                                        title: "Paste Photo",
                                        subtitle: "Send an image to the active Mac",
                                        icon: "photo.on.rectangle.angled",
                                        tint: .purple,
                                        action: .pasteImageToMac
                                    )

                                    compactCard(
                                        title: "Shoot + Paste",
                                        subtitle: "Use the camera and paste immediately",
                                        icon: "camera",
                                        tint: .pink,
                                        action: .captureAndPasteToMac
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var premiumPrimaryCard: some View {
        Button {
            onSelect(.recordMemo)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.14))
                            .frame(width: 52, height: 52)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Record Memo")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Jump straight into a full memo recording with the premium recorder flow.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.borderPrimary.opacity(0.6), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var macSectionTitle: String {
        let resolvedName = macName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if resolvedName.isEmpty {
            return "ON YOUR MAC"
        }
        return "ON \(resolvedName.uppercased())"
    }

    private func compactCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: HomeCaptureLauncherAction
    ) -> some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @Binding var selection: ContentFilter
    let voiceMemos: [VoiceMemo]
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onContentChanged: () -> Void

    @State private var searchText = ""
    @State private var dictations: [KeyboardDictation] = []
    @State private var captures: [Capture] = []
    @State private var selectedDictation: KeyboardDictation?
    @State private var selectedCapture: Capture?
    @StateObject private var themeManager = ThemeManager.shared

    private var filteredMemos: [VoiceMemo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return voiceMemos }

        return voiceMemos.filter { memo in
            let titleMatch = memo.title?.localizedStandardContains(query) ?? false
            let transcriptionMatch = memo.transcription?.localizedStandardContains(query) ?? false
            return titleMatch || transcriptionMatch
        }
    }

    private var filteredDictations: [KeyboardDictation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return dictations }

        return dictations.filter { dictation in
            dictation.text.localizedStandardContains(query)
                || (dictation.appContext?.localizedStandardContains(query) ?? false)
        }
    }

    private var filteredCaptures: [Capture] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return captures }

        return captures.filter { capture in
            capture.text.localizedStandardContains(query)
                || (capture.title?.localizedStandardContains(query) ?? false)
                || (capture.sourceURL?.localizedStandardContains(query) ?? false)
                || capture.sourceType.localizedStandardContains(query)
        }
    }

    private var activeCount: Int {
        switch selection {
        case .memos:
            filteredMemos.count
        case .dictations:
            filteredDictations.count
        case .captures:
            filteredCaptures.count
        }
    }

    private var totalCount: Int {
        switch selection {
        case .memos:
            voiceMemos.count
        case .dictations:
            dictations.count
        case .captures:
            captures.count
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ContentFilterToggle(selection: $selection)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)

                    if activeCount == 0 {
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.horizontal, Spacing.lg)
                    } else {
                        List {
                            switch selection {
                            case .memos:
                                ForEach(filteredMemos) { memo in
                                    VoiceMemoRow(
                                        memo: memo,
                                        audioPlayer: audioPlayer
                                    )
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(themeManager.colors.tableCellBackground)
                                    .listRowSeparatorTint(themeManager.colors.tableDivider)
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteMemo(memo)
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }
                                    }
                                }

                            case .dictations:
                                ForEach(filteredDictations) { dictation in
                                    Button {
                                        selectedDictation = dictation
                                    } label: {
                                        DictationRow(dictation: dictation)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(themeManager.colors.tableCellBackground)
                                    .listRowSeparatorTint(themeManager.colors.tableDivider)
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            promoteToMemo(dictation)
                                        } label: {
                                            Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                        }
                                        .tint(.accentColor)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteDictation(dictation)
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }
                                    }
                                }

                            case .captures:
                                ForEach(filteredCaptures) { capture in
                                    Button {
                                        selectedCapture = capture
                                    } label: {
                                        CaptureRow(capture: capture)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(themeManager.colors.tableCellBackground)
                                    .listRowSeparatorTint(themeManager.colors.tableDivider)
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteCapture(capture)
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(activeCount)/\(totalCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .onAppear {
                refreshSupplementalCollections()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshSupplementalCollections()
            }
            .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
                refreshSupplementalCollections()
            }
            .sheet(item: $selectedDictation) { dictation in
                DictationDetailView(dictation: dictation)
            }
            .sheet(item: $selectedCapture) { capture in
                CaptureDetailView(capture: capture)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: selection.emptyStateIcon)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.textTertiary)

            Text(searchText.isEmpty ? selection.emptyStateTitle : "NO MATCHES")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textSecondary)

            Text(searchText.isEmpty ? selection.emptyStateSubtitle : "Try a different search term")
                .font(.bodySmall)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var searchPrompt: String {
        selection.searchPrompt
    }

    private func refreshSupplementalCollections() {
        KeyboardDictationStore.shared.reload()
        CaptureStore.shared.reload()
        dictations = KeyboardDictationStore.shared.all()
        captures = CaptureStore.shared.all()
    }

    private func promoteToMemo(_ dictation: KeyboardDictation) {
        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()
        memo.title = deriveMemoTitle(from: dictation.text)
        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(dictation.timestamp.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        memo.addSystemTranscript(
            content: dictation.text,
            fromMacOS: false,
            engine: "keyboard_dictation"
        )

        do {
            try viewContext.save()
            PersistenceController.refreshWidgetData(context: viewContext)
            KeyboardDictationStore.shared.delete(dictation.id)
            withAnimation {
                refreshSupplementalCollections()
            }
            onContentChanged()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            AppLogger.app.error("Failed to promote dictation to memo: \(error)")
        }
    }

    private func deleteDictation(_ dictation: KeyboardDictation) {
        KeyboardDictationStore.shared.delete(dictation.id)
        withAnimation {
            refreshSupplementalCollections()
        }
        onContentChanged()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteCapture(_ capture: Capture) {
        CaptureStore.shared.delete(capture.id)
        withAnimation {
            refreshSupplementalCollections()
        }
        onContentChanged()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteMemo(_ memo: VoiceMemo) {
        withAnimation {
            if let filename = memo.fileURL {
                let fileURL = URL.documentsDirectory.appending(path: filename)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            viewContext.delete(memo)

            do {
                try viewContext.save()
                PersistenceController.refreshWidgetData(context: viewContext)
                onContentChanged()
            } catch {
                let nsError = error as NSError
                AppLogger.persistence.error("Error deleting memo: \(nsError.localizedDescription)")
            }
        }
    }

    private func deriveMemoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count < text.count ? title + "…" : title
    }
}

private struct HomeToolButton: View {
    let title: String
    let icon: String
    let tint: Color
    var width: CGFloat? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .padding(.vertical, 12)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

private struct HomeWorkflowRunPreviewRow: View {
    let run: WorkflowRun

    private var statusColor: Color {
        switch run.status {
        case "completed": return .success
        case "failed": return .red
        case "claimed", "running": return .transcribing
        case "queued": return .active
        default: return .textTertiary
        }
    }

    private var formattedDate: String {
        guard let date = run.runDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var previewText: String {
        if let output = run.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            let line = output.components(separatedBy: .newlines).first ?? output
            return line
        }
        return run.status?.capitalized ?? "Pending"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.workflowName ?? "Workflow")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(previewText)
                        .lineLimit(1)
                    Spacer()
                    Text(formattedDate)
                }
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentFilterToggle: View {
    @Binding var selection: ContentFilter

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 2) {
                ForEach(ContentFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selection = filter
                        }
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 10, weight: .medium))
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(selection == filter ? .white : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == filter ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.surfaceSecondary)
            .cornerRadius(8)

            Spacer()
        }
    }
}

// MARK: - Keyboard Mode Tile Selector

enum KeyboardModeCategory: String, CaseIterable {
    case qwerty = "ABC"
    case numbers = "123"
    case symbols = "#+="
    case emoji = "emoji"

    var icon: String {
        switch self {
        case .qwerty: return "textformat.abc"
        case .numbers: return "number"
        case .symbols: return "textformat"
        case .emoji: return "face.smiling"
        }
    }

    var displayLabel: String {
        switch self {
        case .qwerty: return "ABC"
        case .numbers: return "123"
        case .symbols: return "#+="
        case .emoji: return ""  // Will use icon
        }
    }

    /// Returns the keyboard mode IDs associated with this category
    var modeIds: [String] {
        switch self {
        case .qwerty: return ["abc"]
        case .numbers: return ["numbers"]
        case .symbols: return ["symbols"]
        case .emoji: return ["emoji"]
        }
    }

    /// Returns the primary mode ID for this category
    var primaryModeId: String {
        modeIds.first ?? "shortcuts"
    }
}

struct KeyboardModeTileSelector: View {
    @Binding var selectedCategory: KeyboardModeCategory?
    var onCategorySelected: ((KeyboardModeCategory?) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(KeyboardModeCategory.allCases, id: \.self) { category in
                KeyboardModeTile(
                    category: category,
                    isSelected: selectedCategory == category,
                    onTap: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            if selectedCategory == category {
                                // Deselect - turn off keyboard mode
                                selectedCategory = nil
                                HeadlessDictationService.shared.deactivate(explicit: true)
                            } else {
                                // Select new category
                                selectedCategory = category
                                HeadlessDictationService.shared.activate()
                                // TODO: Also set the active keyboard mode via KeyboardBridge
                            }
                        }
                        onCategorySelected?(selectedCategory)
                    }
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
    }
}

struct KeyboardModeTile: View {
    let category: KeyboardModeCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if category == .emoji {
                    Image(systemName: category.icon)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text(category.displayLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.8))
            .frame(width: 36, height: 28)
            .background(isSelected ? Color.white : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shake Gesture Detection

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

struct ShakeDetector: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(action: action))
    }
}

#Preview {
    HomeView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(DeepLinkManager.shared)
}
