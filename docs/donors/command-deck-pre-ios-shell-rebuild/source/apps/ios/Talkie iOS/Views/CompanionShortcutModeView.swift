//
//  CompanionShortcutModeView.swift
//  Talkie iOS
//
//  Mac-authored shortcut keyboard shown when a paired Mac publishes the
//  companion shortcut board and this device is configured to follow it.
//

import SwiftUI
import UIKit
import PhotosUI

struct CompanionShortcutModeView: View {
    @Binding var showingSettings: Bool
    @Binding var showingHelper: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("deck.columnCount") private var deckColumnCount = 4
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var bridgeManager = BridgeManager.shared
    @State private var runningShortcutID: String?
    @State private var showingScreenPreview = false
    @State private var selectedPageID = "talkie"
    @State private var lastTriggeredShortcutID: String?
    @State private var lastTriggeredAt: Date?
    @State private var latestTriggerFeedback: CompanionTriggerFeedback?
    @State private var resultDismissedAt: Date?
    @State private var showingMacPicker = false
    @State private var showingPageSwitcher = false
    @State private var showingAppSwitcher = false
    @State private var suppressMacPickerTap = false
    @State private var displayedShortcutPages = CompanionDeckPage.resolvedPages(from: nil)
    @State private var isSwitchingMac = false
    @State private var isTrackpadInteracting = false
    @State private var showingMacPastePhotoPicker = false
    @State private var macPastePhotoPickerItems: [PhotosPickerItem] = []
    @State private var isPastingImageToMac = false
    @State private var optimisticRuntimeState: CompanionShortcutRuntimeState?
    @State private var optimisticRuntimeToken = UUID()
    @State private var idleResetToken = UUID()
    @State private var activatingAppSwitcherAppID: String?
    @State private var appSwitcherPresentationDetent: PresentationDetent = .large

    private let transientIdleResetDelay: Duration = .seconds(5)
    private let recentResultIdleResetDelay: Duration = .seconds(30)
    private let recentShortcutContextLifetime: TimeInterval = 10

    init(showingSettings: Binding<Bool>, showingHelper: Binding<Bool>) {
        _showingSettings = showingSettings
        _showingHelper = showingHelper
    }

    var body: some View {
        contentRoot
            .navigationTitle("Command Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                syncDisplayedPages()
                syncCompanionDeckLiveness(refreshImmediately: false)
                await bridgeManager.refreshCompanionState()
                syncDisplayedPages()
            }
            .onDisappear {
                bridgeManager.setCompanionDeckVisible(false)
                bridgeManager.setCompanionRuntimeActive(false)
            }
            .onChange(of: livePageSelectionSignature) { _, _ in
                syncDisplayedPages(animated: true)
            }
            .onChange(of: scenePhase) { _, _ in
                syncCompanionDeckLiveness(refreshImmediately: scenePhase == .active)
            }
            .onChange(of: bridgeManager.activePairedMacID) { _, _ in
                dismissRecentResult(animated: true)
                withAnimation(.easeOut(duration: 0.18)) {
                    showingMacPicker = false
                    showingAppSwitcher = false
                }
            }
            .onChange(of: remoteRuntimeStates) { _, states in
                guard !states.isEmpty else { return }
                clearOptimisticRuntimeState()
            }
            .onChange(of: remoteRecentResults) { _, results in
                guard !results.isEmpty else { return }
                clearOptimisticRuntimeState()
            }
            .onChange(of: hasActiveRuntime) { wasActive, isActive in
                guard wasActive, !isActive, hasIdleResettablePresentation else { return }
                scheduleIdleReset()
            }
            .onChange(of: latestTriggerFeedback?.createdAt) { _, createdAt in
                guard createdAt != nil else { return }
                scheduleIdleReset()
            }
            .onChange(of: selectedPageID) { _, _ in
                dismissRecentResult(animated: true)
                guard showingPageSwitcher else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    showingPageSwitcher = false
                }
            }
            .task(id: recentCompanionResult?.completedAt) {
                guard recentCompanionResult != nil else { return }
                try? await Task.sleep(for: recentResultIdleResetDelay)
                guard recentCompanionResult != nil else { return }
                resetIdlePresentation(animated: true)
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
            .sheet(isPresented: $showingScreenPreview) {
                CompanionScreenPreviewView(macName: activeMacName)
            }
            .sheet(isPresented: $showingAppSwitcher) {
                NavigationStack {
                    CompanionAppSwitcherSheet(
                        apps: appSwitcherApps,
                        activatingAppID: activatingAppSwitcherAppID,
                        selectApp: { app in
                            Task { await activateAppFromSwitcher(app) }
                        },
                        dismiss: {
                            showingAppSwitcher = false
                        }
                    )
                }
                .presentationDetents(appSwitcherPresentationDetents, selection: $appSwitcherPresentationDetent)
                .presentationDragIndicator(.visible)
            }
    }

    private var contentRoot: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView {
                    HStack(spacing: 0) {
                        deckContent(availableHeight: geometry.size.height)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
                .scrollDisabled(isTrackpadInteracting || showingPageSwitcher)
                .background(Color.surfacePrimary.ignoresSafeArea())

                if showingPageSwitcher {
                    CommandDeckSpaceSwitcher(
                        pages: shortcutPages,
                        selectedPageID: selectedPageID,
                        selectPage: { page in
                            withAnimation(.snappy(duration: 0.22)) {
                                selectedPageID = page.id
                                showingPageSwitcher = false
                            }
                        },
                        dismiss: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showingPageSwitcher = false
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: returnToApp) {
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            .accessibilityLabel("Return to Talkie")
            .accessibilityHint("Go back to the main app view")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if canSwitchPages {
                Button {
                    togglePageSwitcher()
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(showingPageSwitcher ? .textPrimary : .textTertiary)
                }
                .accessibilityLabel("Switch command deck space")
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Layout

    private var usesSplitLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var usesCompactPhoneMetrics: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var appSwitcherPresentationDetents: Set<PresentationDetent> {
        if usesCompactPhoneMetrics {
            return [.fraction(0.58), .medium, .large]
        }
        return [.fraction(0.46), .medium, .large]
    }

    private var canSwitchPages: Bool {
        shortcutPages.count > 1
    }

    private var maintainsLiveDeckSession: Bool {
        scenePhase == .active
    }

    private var hasActiveRuntime: Bool {
        activeRuntimeEntry != nil
    }

    private var compactPhoneContentWidth: CGFloat {
        348
    }

    private var deckVerticalSpacing: CGFloat {
        14
    }

    private var deckBottomPadding: CGFloat {
        10
    }

    private var contentHorizontalPadding: CGFloat {
        if usesSplitLayout {
            return 20
        }
        if usesCompactPhoneMetrics {
            return 0
        }
        return 16
    }

    private func deckContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: deckVerticalSpacing) {
            statusStrip
            shortcutPager(availableHeight: availableHeight)
        }
        .frame(maxWidth: usesCompactPhoneMetrics ? compactPhoneContentWidth : .infinity, alignment: .leading)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, deckBottomPadding)
        .overlay(alignment: .topLeading) {
            if showingMacPicker && canSwitchActiveMac {
                CustomMacSwitcher(
                    macs: bridgeManager.pairedMacs,
                    activeID: bridgeManager.activePairedMacID,
                    nameProvider: { pairedMac in
                        shortMacName(
                            preferredName: pairedMac.pairedMacName,
                            fallbackHostname: pairedMac.hostname
                        )
                    },
                    selectMac: { pairedMac in
                        Task { await activateMacFromPicker(id: pairedMac.id) }
                    }
                )
                .padding(.leading, 4)
                .padding(.top, 56)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(10)
            }
        }
    }

    private var boardColumnCount: Int {
        usesSplitLayout ? 4 : max(2, min(4, deckColumnCount))
    }

    private func shortcutSurfaceHeight(availableHeight: CGFloat) -> CGFloat {
        let remainingHeight = availableHeight - cockpitMinHeight - deckVerticalSpacing - deckBottomPadding
        return max(boardHeight, remainingHeight)
    }

    private func togglePageSwitcher() {
        withAnimation(.easeOut(duration: 0.18)) {
            showingMacPicker = false
            showingAppSwitcher = false
            showingPageSwitcher.toggle()
        }
    }

    private func toggleAppSwitcher() {
        guard canOpenAppSwitcher else { return }
        appSwitcherPresentationDetent = .large
        showingMacPicker = false
        showingPageSwitcher = false
        showingAppSwitcher.toggle()

        if showingAppSwitcher {
            Task { await bridgeManager.refreshCompanionState() }
        }
    }

    private func syncCompanionDeckLiveness(refreshImmediately: Bool) {
        bridgeManager.setCompanionDeckVisible(scenePhase == .active)
        bridgeManager.setCompanionRuntimeActive(maintainsLiveDeckSession)

        guard refreshImmediately, scenePhase == .active else { return }
        Task { await bridgeManager.refreshCompanionState() }
    }

    private func returnToApp() {
        withAnimation(.easeOut(duration: 0.18)) {
            showingMacPicker = false
            showingPageSwitcher = false
            showingAppSwitcher = false
            showingHelper = false
        }
    }

    private var tileSpacing: CGFloat {
        boardColumnCount >= 4 ? 6 : boardColumnCount == 3 ? 8 : 10
    }

    private var boardColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: boardColumnCount)
    }

    private var tileMinHeight: CGFloat {
        switch boardColumnCount {
        case 4: return 80
        case 3: return 96
        default: return 118
        }
    }

    private var boardHeight: CGFloat {
        let rowCount = Int(ceil(Double(selectedPage.shortcutSlots.count) / Double(boardColumnCount)))
        return CGFloat(rowCount) * tileMinHeight + CGFloat(max(0, rowCount - 1)) * tileSpacing + 8
    }

    // MARK: - Data

    private var liveShortcutPages: [CompanionDeckPage]? {
        guard bridgeManager.status == .connected,
              bridgeManager.companionState != nil else { return nil }
        return CompanionDeckPage.resolvedPages(from: bridgeManager.companionState?.shortcutPages)
    }

    private var shortcutPages: [CompanionDeckPage] {
        displayedShortcutPages
    }

    private var livePageSelectionSignature: String {
        guard let liveShortcutPages else { return "" }
        return pageSignature(for: liveShortcutPages)
    }

    private var selectedPage: CompanionDeckPage {
        shortcutPages.first(where: { $0.id == selectedPageID }) ?? shortcutPages[0]
    }

    private var shortcutStatesByID: [String: CompanionShortcutRuntimeState] {
        Dictionary(
            uniqueKeysWithValues: (bridgeManager.companionState?.shortcutStates ?? []).map { ($0.shortcutId, $0) }
        )
    }

    private var remoteRuntimeStates: [CompanionShortcutRuntimeState] {
        bridgeManager.companionState?.shortcutStates ?? []
    }

    private var recentResultsByShortcutID: [String: CompanionShortcutRecentResult] {
        Dictionary(
            uniqueKeysWithValues: (bridgeManager.companionState?.recentResults ?? []).map { ($0.shortcutId, $0) }
        )
    }

    private var appSwitcherApps: [CompanionAppSwitcherApp] {
        bridgeManager.companionState?.appSwitcherApps ?? []
    }

    private var remoteRecentResults: [CompanionShortcutRecentResult] {
        bridgeManager.companionState?.recentResults ?? []
    }

    private var remoteActiveRuntimeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)? {
        for state in remoteRuntimeStates {
            guard let shortcut = CompanionShortcutDefinition(rawValue: state.shortcutId) else { continue }
            return (shortcut, state)
        }
        return nil
    }

    private var optimisticRuntimeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)? {
        guard remoteActiveRuntimeEntry == nil,
              let optimisticRuntimeState,
              let shortcut = CompanionShortcutDefinition(rawValue: optimisticRuntimeState.shortcutId) else {
            return nil
        }
        return (shortcut, optimisticRuntimeState)
    }

    private var activeRuntimeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)? {
        remoteActiveRuntimeEntry ?? optimisticRuntimeEntry
    }

    private var recentContextShortcut: CompanionShortcutDefinition? {
        if let activeRuntimeEntry {
            return activeRuntimeEntry.shortcut
        }

        if let recentTriggeredShortcut {
            return recentTriggeredShortcut
        }

        return recentResultShortcut
    }

    private var recentTriggerFeedback: CompanionTriggerFeedback? {
        guard activeRuntimeEntry == nil,
              recentCompanionResult == nil,
              let latestTriggerFeedback,
              Date().timeIntervalSince(latestTriggerFeedback.createdAt) <= 2.5 else {
            return nil
        }

        return latestTriggerFeedback
    }

    private var recentTriggeredShortcut: CompanionShortcutDefinition? {
        guard activeRuntimeEntry == nil,
              let lastTriggeredShortcutID,
              let lastTriggeredAt,
              Date().timeIntervalSince(lastTriggeredAt) <= recentShortcutContextLifetime,
              let shortcut = CompanionShortcutDefinition(rawValue: lastTriggeredShortcutID) else {
            return nil
        }
        return shortcut
    }

    private var recentDisplayShortcut: CompanionShortcutDefinition? {
        recentTriggeredShortcut ?? recentResultShortcut
    }

    private var recentResultShortcut: CompanionShortcutDefinition? {
        guard let recentCompanionResult else { return nil }
        return CompanionShortcutDefinition(rawValue: recentCompanionResult.shortcutId)
    }

    private var recentCompanionResult: CompanionShortcutRecentResult? {
        guard activeRuntimeEntry == nil else { return nil }

        func isVisible(_ result: CompanionShortcutRecentResult) -> Bool {
            guard result.isFresh else { return false }
            if let dismissedAt = resultDismissedAt,
               let cd = result.completedDate { return cd > dismissedAt }
            return true
        }

        if let recentTriggeredShortcut,
           let result = recentResultsByShortcutID[recentTriggeredShortcut.rawValue],
           isVisible(result) {
            return result
        }

        return (bridgeManager.companionState?.recentResults ?? []).first(where: isVisible)
    }

    private var hasIdleResettablePresentation: Bool {
        recentCompanionResult != nil || recentTriggeredShortcut != nil || latestTriggerFeedback != nil
    }

    private var activeMacName: String {
        shortMacName(
            preferredName: bridgeManager.pairedMacDisplayName,
            fallbackHostname: bridgeManager.activePairedMac?.hostname
        )
    }

    private var canSwitchActiveMac: Bool {
        bridgeManager.pairedMacs.count > 1 && activeRuntimeEntry == nil
    }

    private var canOpenAppSwitcher: Bool {
        selectedPage.context == .mac && activeRuntimeEntry == nil && !appSwitcherApps.isEmpty
    }

    private var runningShortcutDefinition: CompanionShortcutDefinition? {
        guard let runningShortcutID else { return nil }
        return CompanionShortcutDefinition(rawValue: runningShortcutID)
    }

    private var runningCommandDefinition: CompanionCommandDefinition? {
        guard let runningShortcutID else { return nil }
        return CompanionCommandDefinition.definition(for: runningShortcutID)
    }

    private var showsCompactPhoneResultCommands: Bool {
        usesCompactPhoneMetrics &&
        recentCompanionResult != nil &&
        recentContextShortcut?.prefersDictationCommands == true
    }

    private var compactPhoneResultCommands: [CompanionCommandDefinition] {
        guard activeRuntimeEntry == nil,
              showsCompactPhoneResultCommands else {
            return []
        }

        return [.paste, .enter, .delete]
    }

    // MARK: - Status Strip

    private var waveformColor: Color {
        guard let entry = activeRuntimeEntry else { return .green }
        switch entry.state.phase {
        case .recording:              return .red
        case .preparing, .processing: return .orange
        }
    }

    private var cockpitHeaderHeight: CGFloat { 38 }
    private var cockpitPrimaryHeight: CGFloat { recentCompanionResult != nil ? 76 : 48 }
    private var cockpitFollowUpHeight: CGFloat { 36 }
    private var cockpitMinHeight: CGFloat { recentCompanionResult != nil ? 198 : 168 }

    private var statusStrip: some View {
        let activeEntry = activeRuntimeEntry
        let isActive = activeEntry != nil
        let isStopEnabled = activeEntry?.state.canStop == true

        return Group {
            if let activeEntry, isStopEnabled {
                Button {
                    Task { await runShortcut(activeEntry.shortcut) }
                } label: {
                    statusStripBody(activeEntry: activeEntry)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop current live action")
            } else {
                statusStripBody(activeEntry: activeEntry)
                    .accessibilityLabel("Command deck status")
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .opacity(isSwitchingMac ? 0.92 : 1)
    }

    private func statusStripBody(
        activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)?
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                statusStripHeader(activeEntry: activeEntry)
                    .frame(maxWidth: .infinity)
                    .frame(height: cockpitHeaderHeight)
                    .padding(.horizontal, usesCompactPhoneMetrics ? 12 : 14)
                    .padding(.top, 12)

                statusStripPrimary(activeEntry: activeEntry)
                    .frame(maxWidth: .infinity)
                    .frame(height: cockpitPrimaryHeight)
                    .padding(.horizontal, usesCompactPhoneMetrics ? 16 : 20)
                    .padding(.top, 6)

                DeckWaveformView(
                    color: activeEntry != nil ? waveformColor : .white.opacity(0.18),
                    signalLevel: activeEntry?.state.signalLevel,
                    isProcessing: activeEntry?.state.phase == .processing,
                    isActive: activeEntry != nil
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 80)
                    .onEnded { value in
                        let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5

                        guard recentCompanionResult != nil, activeRuntimeEntry == nil else { return }
                        let isMeaningful = isHorizontal ? abs(value.translation.width) > 120 : abs(value.translation.height) > 80
                        if isMeaningful {
                            dismissRecentResult(animated: true)
                        }
                    }
            )

            statusStripShelf(activeEntry: activeEntry)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: cockpitFollowUpHeight)
                .padding(.horizontal, usesCompactPhoneMetrics ? 8 : 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, minHeight: cockpitMinHeight, alignment: .top)
    }

    private func statusStripHeader(
        activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let activeEntry {
                HStack(spacing: 8) {
                    StatusLamp(color: waveformColor)

                    Text(activeStatusContextLabel(for: activeEntry.shortcut))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                ActiveTimerCapsule(
                    shortcutId: activeEntry.state.shortcutId,
                    phase: activeEntry.state.phase,
                    elapsedSeconds: activeEntry.state.elapsedSeconds
                )

                Spacer(minLength: 12)

                ActiveStatusBadge(
                    title: activeEntry.state.phase.badgeTitle,
                    color: waveformColor
                )
            } else {
                StatusLamp(color: .green)

                macSwitcherControl

                Spacer()

                if let recentTriggerFeedback {
                    CommandFeedbackBadge(feedback: recentTriggerFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
    }

    private func statusStripPrimary(
        activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)?
    ) -> some View {
        VStack(spacing: 4) {
            if activeEntry != nil {
                // Silent — waveform + badge carry the active state
                Spacer()
            } else if recentCompanionResult == nil {
                TrackpadSurface(
                    onEvent: { event, dx, dy in
                        Task { try? await bridgeManager.client.companionTrackpad(event: event, dx: dx, dy: dy) }
                    },
                    onInteractionChanged: { isInteracting in
                        isTrackpadInteracting = isInteracting
                    }
                )
            } else if let recentCompanionResult {
                ZStack(alignment: .topTrailing) {
                    Text(recentCompanionResult.resultPreview)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                        .padding(.trailing, 30)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                        )
                        .accessibilityLabel("Recent dictation result")

                    Button {
                        dismissRecentResult(animated: true)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.42))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .accessibilityLabel("Dismiss result")
                }
            } else {
                TalkieEyebrow(text: "Ready", tint: .panelInk, showLeader: false)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func statusStripShelf(
        activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)?
    ) -> some View {
        if activeEntry == nil {
            if showsCompactPhoneResultCommands {
                compactPhoneResultCommandRail
            } else if selectedPage.context == .mac {
                macNavigationRail
            } else {
                suggestedCommandRail
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Shortcut Pager

    private func shortcutPager(availableHeight: CGFloat) -> some View {
        let surfaceHeight = shortcutSurfaceHeight(availableHeight: availableHeight)

        return TabView(selection: $selectedPageID) {
            ForEach(shortcutPages) { page in
                shortcutBoard(for: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .tag(page.id)
                    .padding(.top, 2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(height: surfaceHeight, alignment: .top)
        .animation(.snappy(duration: 0.22), value: selectedPageID)
        .overlay {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ThreeFingerSwipeCapture(
                    onSwipeLeft: { moveToNextPage() },
                    onSwipeRight: { moveToPreviousPage() },
                    onSwipeUp: { showingHelper = false },
                    onSwipeDown: { showingHelper = false },
                    onPinchIn: { moveToNextPage() },
                    onPinchOut: { moveToPreviousPage() }
                )
            }
        }
    }

    private func shortcutBoard(for page: CompanionDeckPage) -> some View {
        ZStack(alignment: .top) {
            Color.clear

            LazyVGrid(columns: boardColumns, spacing: tileSpacing) {
                ForEach(Array(page.shortcutSlots.enumerated()), id: \.offset) { _, slotID in
                    let shortcut = CompanionShortcutDefinition(rawValue: slotID)
                    let splitAction = splitShortcutCardAction(for: shortcut)
                    let primaryTriggerID = slotID
                    let secondaryTriggerID = splitAction == nil ? nil : CompanionCommandDefinition.enter.id
                    ShortcutCard(
                        shortcut: shortcut,
                        isActive: isShortcutActive(shortcut),
                        isTriggering: runningShortcutID == primaryTriggerID && shortcut != nil,
                        isSecondaryTriggering: secondaryTriggerID != nil
                            && runningShortcutID == secondaryTriggerID
                            && shortcut != nil,
                        columnCount: boardColumnCount,
                        minHeight: tileMinHeight,
                        splitAction: splitAction
                    ) {
                        guard let shortcut else { return }
                        await runShortcut(shortcut)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if value.magnification > 1.15 {
                            deckColumnCount = max(2, deckColumnCount - 1)
                        } else if value.magnification < 0.85 {
                            deckColumnCount = min(4, deckColumnCount + 1)
                        }
                    }
                }
        )
    }

    private func splitShortcutCardAction(
        for shortcut: CompanionShortcutDefinition?
    ) -> ShortcutCard.SplitAction? {
        guard let shortcut,
              let recentShortcut = recentResultShortcut,
              recentShortcut == shortcut,
              shortcut.prefersDictationCommands,
              recentCompanionResult != nil else {
            return nil
        }

        return .init(
            primaryTitle: "Enter",
            primaryIcon: CompanionCommandDefinition.enter.icon,
            primaryColor: CompanionCommandDefinition.enter.color,
            primaryAction: { await runCommand(.enter) },
            secondaryAction: { await restartDictationFromRecentResult(shortcut) }
        )
    }

    // MARK: - Suggested Commands

    private var compactPhoneResultCommandRail: some View {
        HStack(spacing: 8) {
            ForEach(compactPhoneResultCommands) { command in
                ShelfCommandButton(
                    command: command,
                    showLabel: true,
                    compact: false,
                    isTriggering: runningShortcutID == command.id
                ) { await runCommand(command) }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityLabel("Dictation follow-up commands")
    }

    private var suggestedCommandRail: some View {
        let compact = usesCompactPhoneMetrics

        return HStack(spacing: compact ? 4 : 6) {
            // Left group: Escape, Copy, Paste
            ShelfCommandButton(
                command: .escape,
                showLabel: false,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.escape.id
            ) { await runCommand(.escape) }

            ShelfCommandButton(
                command: .copy,
                showLabel: false,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.copy.id
            ) { await runCommand(.copy) }

            ShelfCommandButton(
                command: .paste,
                showLabel: false,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.paste.id
            ) { await runCommand(.paste) }

            Spacer(minLength: compact ? 2 : 4)

            // Center: arrow cluster
            CursorNavCluster(
                compact: compact,
                runningCommandId: runningShortcutID,
                runCommand: { cmd in await runCommand(cmd) }
            )

            Spacer(minLength: compact ? 2 : 4)

            // Right group: Select, Delete, Enter
            ShelfCommandButton(
                command: .select,
                showLabel: false,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.select.id
            ) { await runCommand(.select) }

            ShelfCommandButton(
                command: .delete,
                showLabel: false,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.delete.id
            ) { await runCommand(.delete) }

            ShelfCommandButton(
                command: .enter,
                showLabel: !compact,
                compact: compact,
                isTriggering: runningShortcutID == CompanionCommandDefinition.enter.id
            ) { await runCommand(.enter) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityLabel("Cursor navigation and text commands")
    }

    private var macNavigationRail: some View {
        HStack(spacing: usesCompactPhoneMetrics ? 6 : 8) {
            MacShelfNavigator(
                title: "WIN",
                icon: "rectangle.on.rectangle",
                isTriggering: runningShortcutID == CompanionCommandDefinition.windowPrevious.id
                    || runningShortcutID == CompanionCommandDefinition.windowNext.id,
                centerAction: nil,
                centerIsHighlighted: false,
                previousAction: { await runCommand(.windowPrevious) },
                nextAction: { await runCommand(.windowNext) }
            )

            MacShelfNavigator(
                title: "TAB",
                icon: "square.split.2x1",
                isTriggering: runningShortcutID == CompanionCommandDefinition.tabPrevious.id
                    || runningShortcutID == CompanionCommandDefinition.tabNext.id,
                centerAction: nil,
                centerIsHighlighted: false,
                previousAction: { await runCommand(.tabPrevious) },
                nextAction: { await runCommand(.tabNext) }
            )

            MacShelfNavigator(
                title: "APP",
                icon: "square.stack.3d.up",
                isTriggering: runningShortcutID == CompanionCommandDefinition.appPrevious.id
                    || runningShortcutID == CompanionCommandDefinition.appNext.id,
                centerAction: canOpenAppSwitcher ? toggleAppSwitcher : nil,
                centerIsHighlighted: showingAppSwitcher,
                previousAction: { await runCommand(.appPrevious) },
                nextAction: { await runCommand(.appNext) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityLabel("Mac navigation commands")
    }

    // MARK: - Actions

    @MainActor
    private func runShortcut(_ shortcut: CompanionShortcutDefinition) async {
        await runShortcutID(shortcut.rawValue)
    }

    @MainActor
    private func runCommand(_ command: CompanionCommandDefinition) async {
        await runShortcutID(command.id)
        if command.id == CompanionCommandDefinition.enter.id, recentCompanionResult != nil {
            try? await Task.sleep(for: .milliseconds(250))
            dismissRecentResult(animated: true)
        }
    }

    @MainActor
    private func restartDictationFromRecentResult(_ shortcut: CompanionShortcutDefinition) async {
        dismissRecentResult(animated: true)
        await runShortcut(shortcut)
    }

    @MainActor
    private func runShortcutID(_ shortcutID: String) async {
        if shortcutID == CompanionShortcutDefinition.macWindows.rawValue {
            latestTriggerFeedback = CompanionTriggerFeedback(
                title: "DESKTOP",
                icon: "display",
                color: .green
            )
            showingScreenPreview = true
            return
        }

        if shortcutID == CompanionShortcutDefinition.macPasteImage.rawValue {
            latestTriggerFeedback = CompanionTriggerFeedback(
                title: "IMAGE",
                icon: "photo.on.rectangle.angled",
                color: .cyan
            )
            showingMacPastePhotoPicker = true
            return
        }

        guard runningShortcutID == nil else { return }
        runningShortcutID = shortcutID
        defer { runningShortcutID = nil }

        let response: CompanionTriggerResponse
        do {
            response = try await bridgeManager.triggerCompanionShortcut(shortcutID)
        } catch {
            latestTriggerFeedback = failureFeedback(for: shortcutID, errorDescription: error.localizedDescription)
            Task { await bridgeManager.refreshCompanionState() }
            return
        }

        guard response.ok else {
            latestTriggerFeedback = failureFeedback(for: shortcutID, errorDescription: response.error ?? response.message)
            Task { await bridgeManager.refreshCompanionState() }
            return
        }

        if let shortcut = CompanionShortcutDefinition(rawValue: shortcutID) {
            lastTriggeredShortcutID = shortcut.rawValue
            lastTriggeredAt = Date()
        }

        if let feedback = triggerFeedback(for: shortcutID, response: response) {
            latestTriggerFeedback = feedback
        }

        if let runtimeState = response.runtimeState {
            applyOptimisticRuntimeState(runtimeState)
        }

        Task { await bridgeManager.refreshCompanionState() }
    }

    private func loadMacPastePhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    latestTriggerFeedback = CompanionTriggerFeedback(
                        title: "IMAGE FAILED",
                        icon: "exclamationmark.triangle",
                        color: .orange
                    )
                }
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
            latestTriggerFeedback = CompanionTriggerFeedback(
                title: "PAIR MAC",
                icon: "wifi.exclamationmark",
                color: .orange
            )
            return
        }

        guard let payload = preparedCompanionImagePayload(from: image) else {
            latestTriggerFeedback = CompanionTriggerFeedback(
                title: "IMAGE FAILED",
                icon: "exclamationmark.triangle",
                color: .orange
            )
            return
        }

        do {
            let response = try await bridgeManager.client.companionPasteImage(
                imageData: payload.data,
                mimeType: payload.mimeType,
                autoPaste: true
            )

            latestTriggerFeedback = CompanionTriggerFeedback(
                title: response.ok ? "IMAGE SENT" : "IMAGE FAILED",
                icon: response.ok ? "photo.badge.checkmark" : "exclamationmark.triangle",
                color: response.ok ? .green : .orange
            )
        } catch {
            latestTriggerFeedback = CompanionTriggerFeedback(
                title: "IMAGE FAILED",
                icon: "exclamationmark.triangle",
                color: .orange
            )
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

    @MainActor
    private func applyOptimisticRuntimeState(_ state: CompanionShortcutRuntimeState) {
        optimisticRuntimeToken = UUID()
        optimisticRuntimeState = state

        let token = optimisticRuntimeToken
        let expiry: Duration = state.phase == .processing ? .seconds(6) : .seconds(3)

        Task {
            try? await Task.sleep(for: expiry)
            await MainActor.run {
                guard optimisticRuntimeToken == token else { return }
                guard remoteActiveRuntimeEntry == nil else { return }
                optimisticRuntimeState = nil
            }
        }
    }

    @MainActor
    private func clearOptimisticRuntimeState() {
        optimisticRuntimeToken = UUID()
        optimisticRuntimeState = nil
    }

    @MainActor
    private func scheduleIdleReset() {
        let token = UUID()
        idleResetToken = token

        Task {
            try? await Task.sleep(for: transientIdleResetDelay)
            await MainActor.run {
                guard idleResetToken == token else { return }
                guard activeRuntimeEntry == nil else { return }
                if recentCompanionResult != nil {
                    clearTransientPresentation(animated: true)
                    return
                }
                guard hasIdleResettablePresentation else { return }
                resetIdlePresentation(animated: true)
            }
        }
    }

    @MainActor
    private func resetIdlePresentation(animated: Bool) {
        idleResetToken = UUID()

        let updates = {
            if recentCompanionResult != nil {
                resultDismissedAt = Date()
            }
            latestTriggerFeedback = nil
            lastTriggeredShortcutID = nil
            lastTriggeredAt = nil
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25), updates)
        } else {
            updates()
        }
    }

    @MainActor
    private func dismissRecentResult(animated: Bool) {
        guard recentCompanionResult != nil else { return }

        let updates = {
            resultDismissedAt = Date()
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2), updates)
        } else {
            updates()
        }
    }

    @MainActor
    private func clearTransientPresentation(animated: Bool) {
        let updates = {
            latestTriggerFeedback = nil
            lastTriggeredShortcutID = nil
            lastTriggeredAt = nil
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25), updates)
        } else {
            updates()
        }
    }

    private func isShortcutActive(_ shortcut: CompanionShortcutDefinition?) -> Bool {
        guard let shortcut else { return false }

        if let remoteActiveRuntimeEntry {
            return remoteActiveRuntimeEntry.shortcut == shortcut
        }

        return optimisticRuntimeEntry?.shortcut == shortcut
    }

    private func failureFeedback(
        for shortcutID: String,
        errorDescription: String?
    ) -> CompanionTriggerFeedback {
        let normalizedError = errorDescription?.localizedLowercase ?? ""
        let title: String

        if normalizedError.contains("talkie not running") || normalizedError.contains("start talkie.app") {
            title = "START TALKIE"
        } else if normalizedError.contains("could not connect") || normalizedError.contains("connection") {
            title = "MAC OFFLINE"
        } else if let command = CompanionCommandDefinition.definition(for: shortcutID) {
            title = "\(command.shortCode) FAILED"
        } else if let shortcut = CompanionShortcutDefinition(rawValue: shortcutID) {
            title = "\(shortcut.shortCode) FAILED"
        } else {
            title = "NOT SENT"
        }

        return CompanionTriggerFeedback(
            title: title,
            icon: "xmark",
            color: .orange
        )
    }

    private func triggerFeedback(
        for shortcutID: String,
        response: CompanionTriggerResponse?
    ) -> CompanionTriggerFeedback? {
        if let command = CompanionCommandDefinition.definition(for: shortcutID) {
            return CompanionTriggerFeedback(
                title: command.confirmationTitle,
                icon: command.icon,
                color: command.color
            )
        }

        if let shortcut = CompanionShortcutDefinition(rawValue: shortcutID) {
            return CompanionTriggerFeedback(
                title: shortcut.confirmationTitle(from: response?.message),
                icon: shortcut.icon,
                color: shortcut.color
            )
        }

        return nil
    }

    // MARK: - Page Helpers

    @MainActor
    private func syncSelectedPage() {
        if shortcutPages.contains(where: { $0.id == selectedPageID }) {
            return
        }
        selectedPageID = shortcutPages.first?.id ?? "talkie"
    }

    @MainActor
    private func moveToNextPage() {
        guard let index = shortcutPages.firstIndex(where: { $0.id == selectedPage.id }) else { return }
        let nextIndex = min(index + 1, shortcutPages.count - 1)
        guard nextIndex != index else { return }
        withAnimation(.snappy(duration: 0.22)) {
            selectedPageID = shortcutPages[nextIndex].id
        }
    }

    @MainActor
    private func moveToPreviousPage() {
        guard let index = shortcutPages.firstIndex(where: { $0.id == selectedPage.id }) else { return }
        let previousIndex = max(index - 1, 0)
        guard previousIndex != index else { return }
        withAnimation(.snappy(duration: 0.22)) {
            selectedPageID = shortcutPages[previousIndex].id
        }
    }

    // MARK: - Status Helpers

    private var statusHeadline: String {
        if let runningCommandDefinition {
            return "SENDING \(runningCommandDefinition.shortCode)"
        }

        if let runningShortcutDefinition {
            return "SENDING \(runningShortcutDefinition.title.uppercased())"
        }

        if let entry = activeRuntimeEntry {
            return entry.state.headerCaption(for: entry.shortcut)
        }

        if let recentDisplayShortcut {
            if recentDisplayShortcut.prefersDictationCommands && recentCompanionResult == nil {
                return "\(selectedPage.title.uppercased()) READY"
            }
            return "\(recentDisplayShortcut.shortCode) COMPLETE"
        }

        return "\(selectedPage.title.uppercased()) READY"
    }

    private var statusContextLabel: String {
        if activeRuntimeEntry != nil {
            return activeMacName.uppercased()
        }

        if recentDisplayShortcut != nil {
            return activeMacName.uppercased()
        }

        switch selectedPage.context {
        case .mac:
            return "APPS@MINI"
        case .talkie:
            return "TALKIE@MINI"
        case .custom:
            return selectedPage.title.uppercased()
        }
    }

    private func activeStatusContextLabel(for shortcut: CompanionShortcutDefinition) -> String {
        switch shortcut {
        case .talkieDictate, .itermDictate, .talkieRecord:
            return "MAC MIC"
        default:
            return activeMacName.uppercased()
        }
    }

    private var statusDetail: String {
        if let runningCommandDefinition {
            return runningCommandDefinition.subtitle
        }

        if let runningShortcutDefinition {
            return "Dispatching \(runningShortcutDefinition.title.lowercased()) to your Mac."
        }

        if let entry = activeRuntimeEntry {
            return entry.state.secondaryStatusLine(for: entry.shortcut)
        }

        if let recentDisplayShortcut {
            if recentDisplayShortcut.prefersDictationCommands && recentCompanionResult == nil {
                return selectedPage.readySubtitle
            }
            return "\(recentDisplayShortcut.title) finished on your Mac."
        }

        return selectedPage.readySubtitle
    }

    private var statusReadout: String {
        if let runningCommandDefinition {
            return runningCommandDefinition.shortCode
        }

        if let runningShortcutDefinition {
            return runningShortcutDefinition.shortCode
        }

        if let entry = activeRuntimeEntry {
            let timer = entry.state.formattedElapsed ?? "--:--"
            return "\(entry.state.phase.badgeTitle) \(timer)"
        }

        if let recentDisplayShortcut {
            return recentDisplayShortcut.shortCode
        }

        return "READY"
    }

    private var statusAccentColor: Color {
        if let runningCommandDefinition {
            return runningCommandDefinition.color
        }

        if let runningShortcutDefinition {
            return runningShortcutDefinition.color
        }

        if let entry = activeRuntimeEntry {
            return entry.state.canStop ? entry.shortcut.color : .orange
        }

        if let recentDisplayShortcut {
            return recentDisplayShortcut.color
        }

        return selectedPage.accentColor
    }

    private func statusHeaderTitle(
        activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)?
    ) -> String {
        if let activeEntry {
            return activeEntry.shortcut.title
        }

        if recentCompanionResult != nil {
            return "Recent Dictation"
        }

        if let recentDisplayShortcut {
            return recentDisplayShortcut.title
        }

        return selectedPage.headerTitle
    }

    private func activePhaseDetail(
        for activeEntry: (shortcut: CompanionShortcutDefinition, state: CompanionShortcutRuntimeState)
    ) -> String {
        switch activeEntry.state.phase {
        case .recording:
            switch activeEntry.shortcut {
            case .talkieRecord:
                return "Recording memo on your Mac."
            case .talkieDictate:
                return "Listening on your Mac."
            case .itermDictate:
                return "Listening for iTerm on your Mac."
            default:
                return "Live on your Mac."
            }
        case .preparing:
            return "Getting ready on your Mac."
        case .processing:
            switch activeEntry.shortcut {
            case .talkieRecord:
                return "Saving memo on your Mac."
            case .talkieDictate:
                return "Finishing dictation on your Mac."
            case .itermDictate:
                return "Sending dictated text to iTerm."
            default:
                return "Wrapping up on your Mac."
            }
        }
    }

    private var macSwitcherControl: some View {
        Button {
            guard canSwitchActiveMac else { return }
            if suppressMacPickerTap {
                suppressMacPickerTap = false
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                showingPageSwitcher = false
                showingMacPicker.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Text(activeMacName)
                    .font(.system(size: usesCompactPhoneMetrics ? 14 : 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.74))
                    .lineLimit(1)
                    .contentTransition(.opacity)

                if canSwitchActiveMac {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .rotationEffect(.degrees(showingMacPicker ? 180 : 0))
                }
            }
            .padding(.trailing, 2)
        }
        .buttonStyle(.plain)
        .disabled(!canSwitchActiveMac)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard canSwitchActiveMac else { return }
                    suppressMacPickerTap = true
                    Task { await cycleActiveMac() }
                }
        )
        .accessibilityLabel(canSwitchActiveMac ? "Switch active computer" : activeMacName)
    }

    private func shortMacName(preferredName: String?, fallbackHostname: String?) -> String {
        let candidate = (preferredName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? preferredName : fallbackHostname) ?? "Paired Mac"
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "Paired Mac" }

        if let firstSegment = trimmed.split(separator: ".", omittingEmptySubsequences: true).first {
            return String(firstSegment)
        }

        return trimmed
    }

    @MainActor
    private func cycleActiveMac() async {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSwitchingMac = true
        }
        await bridgeManager.activateAdjacentPairedMac(offset: 1)
        syncDisplayedPages(animated: true)
        withAnimation(.easeOut(duration: 0.18)) {
            showingMacPicker = false
        }
        latestTriggerFeedback = CompanionTriggerFeedback(
            title: activeMacName,
            icon: "desktopcomputer",
            color: .white
        )
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeOut(duration: 0.22)) {
            isSwitchingMac = false
        }
    }

    @MainActor
    private func activateMacFromPicker(id: String) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSwitchingMac = true
        }
        await bridgeManager.activatePairedMac(id: id)
        syncDisplayedPages(animated: true)
        withAnimation(.easeOut(duration: 0.18)) {
            showingMacPicker = false
        }
        latestTriggerFeedback = CompanionTriggerFeedback(
            title: activeMacName,
            icon: "desktopcomputer",
            color: .white
        )
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeOut(duration: 0.22)) {
            isSwitchingMac = false
        }
    }

    @MainActor
    private func activateAppFromSwitcher(_ app: CompanionAppSwitcherApp) async {
        guard activatingAppSwitcherAppID == nil else { return }
        activatingAppSwitcherAppID = app.id
        defer { activatingAppSwitcherAppID = nil }

        do {
            let response = try await bridgeManager.client.companionActivateApp(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier
            )

            guard response.ok else {
                latestTriggerFeedback = failureFeedback(
                    for: "companion-activate-app",
                    errorDescription: response.error ?? "Failed to focus \(app.displayName)"
                )
                Task { await bridgeManager.refreshCompanionState() }
                return
            }

            latestTriggerFeedback = CompanionTriggerFeedback(
                title: app.displayName,
                icon: "square.stack.3d.up.fill",
                color: CompanionCommandDefinition.appNext.color
            )
            dismissRecentResult(animated: true)

            withAnimation(.easeOut(duration: 0.18)) {
                showingAppSwitcher = false
            }

            await bridgeManager.refreshCompanionState()
        } catch {
            latestTriggerFeedback = failureFeedback(
                for: "companion-activate-app",
                errorDescription: error.localizedDescription
            )
            Task { await bridgeManager.refreshCompanionState() }
        }
    }

    private func pageSignature(for pages: [CompanionDeckPage]) -> String {
        pages.map { page in
            "\(page.id):\(page.shortcutSlots.joined(separator: ","))"
        }.joined(separator: "|")
    }

    @MainActor
    private func syncDisplayedPages(animated: Bool = false) {
        let previousPage = displayedShortcutPages.first(where: { $0.id == selectedPageID })
        let nextPages = liveShortcutPages ?? displayedShortcutPages
        let resolvedPages = nextPages.isEmpty ? CompanionDeckPage.resolvedPages(from: nil) : nextPages

        if pageSignature(for: resolvedPages) != pageSignature(for: displayedShortcutPages) {
            if animated {
                withAnimation(.snappy(duration: 0.22)) {
                    displayedShortcutPages = resolvedPages
                }
            } else {
                displayedShortcutPages = resolvedPages
            }
        }

        if resolvedPages.count <= 1 {
            showingPageSwitcher = false
        }

        syncSelectedPage(in: displayedShortcutPages, preferredPage: previousPage, animated: animated)
    }

    @MainActor
    private func syncSelectedPage(
        in pages: [CompanionDeckPage],
        preferredPage: CompanionDeckPage? = nil,
        animated: Bool = false
    ) {
        guard pages.isEmpty == false else {
            selectedPageID = "talkie"
            return
        }

        if pages.contains(where: { $0.id == selectedPageID }) {
            return
        }

        let targetPage = preferredPage ?? displayedShortcutPages.first(where: { $0.id == selectedPageID })
        let nextPageID =
            pages.first(where: { page in
                guard let targetPage else { return false }
                return page.context == targetPage.context && page.title == targetPage.title
            })?.id
            ?? pages.first(where: { page in
                guard let targetPage else { return false }
                return page.context == targetPage.context
            })?.id
            ?? pages.first?.id
            ?? "talkie"

        if animated {
            withAnimation(.snappy(duration: 0.22)) {
                selectedPageID = nextPageID
            }
        } else {
            selectedPageID = nextPageID
        }
    }
}

// MARK: - Shortcut Card

private struct ShortcutCard: View {
    struct SplitAction {
        let primaryTitle: String
        let primaryIcon: String
        let primaryColor: Color
        let primaryAction: @Sendable () async -> Void
        let secondaryAction: @Sendable () async -> Void
    }

    let shortcut: CompanionShortcutDefinition?
    let isActive: Bool
    let isTriggering: Bool
    var isSecondaryTriggering = false
    var columnCount: Int = 2
    var minHeight: CGFloat = 118
    let splitAction: SplitAction?
    let action: @Sendable () async -> Void

    private var accentColor: Color { shortcut?.color ?? .textTertiary }
    private var displayTitle: String { shortcut?.title ?? "Empty" }
    private var displaySubtitle: String { shortcut?.subtitle ?? "" }
    private var displayIcon: String { shortcut?.icon ?? "plus" }
    private var isCompact: Bool { columnCount >= 3 }
    private var isDense: Bool { columnCount >= 4 }

    private var iconSize: CGFloat { isDense ? 28 : isCompact ? 34 : 40 }
    private var iconFontSize: CGFloat { isDense ? 12 : isCompact ? 14 : 17 }
    private var tilePadding: CGFloat { isDense ? 8 : isCompact ? 10 : 14 }
    private var cornerSize: CGFloat { isDense ? 12 : 16 }
    private var titleFont: CGFloat { isDense ? 11 : isCompact ? 12 : 13 }
    private var subtitleFont: CGFloat { isDense ? 9 : isCompact ? 10 : 11 }
    private var overlayButtonWidth: CGFloat { isDense ? 58 : isCompact ? 64 : 72 }
    private var overlayButtonHeight: CGFloat { isDense ? 28 : isCompact ? 30 : 32 }
    private var overlayInset: CGFloat { isDense ? 7 : isCompact ? 8 : 10 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                Task {
                    if let splitAction {
                        await splitAction.secondaryAction()
                    } else {
                        await action()
                    }
                }
            } label: {
                tileShell(mainTileContent())
            }
            .buttonStyle(TileButtonStyle())
            .disabled(shortcut == nil || isTriggering || isSecondaryTriggering)

            if let splitAction, shortcut != nil {
                EmbeddedShortcutActionButton(
                    title: splitAction.primaryTitle,
                    icon: splitAction.primaryIcon,
                    tintColor: splitAction.primaryColor,
                    width: overlayButtonWidth,
                    height: overlayButtonHeight,
                    isTriggering: isSecondaryTriggering,
                    isDisabled: isTriggering
                ) {
                    await splitAction.primaryAction()
                }
                .padding(.top, overlayInset)
                .padding(.trailing, overlayInset)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
    }

    private func mainTileContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if isTriggering {
                    ProgressView()
                        .tint(accentColor)
                        .scaleEffect(isDense ? 0.65 : 0.85)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: displayIcon)
                        .font(.system(size: iconFontSize, weight: .semibold))
                        .foregroundColor(shortcut == nil ? .textTertiary.opacity(0.35) : accentColor)
                        .frame(width: iconSize, height: iconSize)
                        .background(accentColor.opacity(shortcut == nil ? 0 : isActive ? 0.22 : 0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, isDense ? 6 : isCompact ? 8 : 12)

            Spacer(minLength: 0)

            Text(displayTitle)
                .font(.system(size: titleFont, weight: .semibold))
                .foregroundColor(shortcut == nil ? .textTertiary.opacity(0.3) : .textPrimary)
                .lineLimit(1)

            if !isDense {
                Text(displaySubtitle)
                    .font(.system(size: subtitleFont, weight: .regular))
                    .foregroundColor(.textTertiary)
                    .lineLimit(isCompact ? 1 : 2)
                    .padding(.top, 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tileShell<Content: View>(_ content: Content) -> some View {
        content
        .padding(tilePadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background(tileBackground)
        .clipShape(.rect(cornerRadius: cornerSize))
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [.white.opacity(shortcut == nil ? 0.015 : 0.04), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.6, y: 0.6)
            )
            .clipShape(.rect(cornerRadius: cornerSize))
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerSize)
                .stroke(
                    LinearGradient(
                        colors: isActive
                            ? [accentColor.opacity(0.55), accentColor.opacity(0.15)]
                            : [.white.opacity(0.16), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 1.25 : 1
                )
        )
    }

    private var tileBackground: Color {
        if shortcut == nil { return Color.surfaceSecondary.opacity(0.4) }
        if isActive { return accentColor.opacity(0.09) }
        return Color.surfaceSecondary
    }
}

private struct EmbeddedShortcutActionButton: View {
    let title: String
    let icon: String
    let tintColor: Color
    let width: CGFloat
    let height: CGFloat
    let isTriggering: Bool
    var isDisabled = false
    let action: @Sendable () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                if isTriggering {
                    ProgressView()
                        .tint(tintColor)
                        .scaleEffect(0.62)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tintColor)
                        .frame(width: 13, height: 13)
                }

                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary.opacity(0.78))
                    .lineLimit(1)
            }
            .frame(width: width, height: height)
            .background(Color.surfacePrimary.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tintColor.opacity(0.24), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(TileButtonStyle())
        .disabled(isTriggering || isDisabled)
        .accessibilityLabel(title)
    }
}

private struct CockpitSuggestionButton: View {
    let command: CompanionCommandDefinition
    let isTriggering: Bool
    let action: @Sendable () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if isTriggering {
                        ProgressView()
                            .tint(command.color)
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: command.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(command.color)
                    }
                }
                .frame(width: 22, height: 22)

                Text(command.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(command.color.opacity(0.10))
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .stroke(command.color.opacity(0.22), lineWidth: 0.75)
            )
        }
        .buttonStyle(TileButtonStyle())
        .disabled(isTriggering)
        .accessibilityLabel("\(command.title), \(command.caption)")
    }
}

// Compact arrow cluster: ← ↑ ↓ → grouped in a subtle pill
private struct CursorNavCluster: View {
    let compact: Bool
    let runningCommandId: String?
    let runCommand: @Sendable (CompanionCommandDefinition) async -> Void

    private let arrows: [CompanionCommandDefinition] = [.left, .up, .down, .right]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(arrows) { cmd in
                Button {
                    Task { await runCommand(cmd) }
                } label: {
                    ZStack {
                        if runningCommandId == cmd.id {
                            ProgressView()
                                .tint(.white.opacity(0.5))
                                .scaleEffect(compact ? 0.46 : 0.5)
                        } else {
                            Image(systemName: cmd.icon)
                                .font(.system(size: compact ? 10 : 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .frame(width: compact ? 22 : 26, height: compact ? 24 : 26)
                }
                .buttonStyle(TileButtonStyle())
                .disabled(runningCommandId == cmd.id)
            }
        }
        .padding(compact ? 2 : 3)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
    }
}

// Compact shelf button: key-style rounded rect, neutral palette
private struct ShelfCommandButton: View {
    let command: CompanionCommandDefinition
    let showLabel: Bool
    let compact: Bool
    let isTriggering: Bool
    let action: @Sendable () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: showLabel ? (compact ? 4 : 5) : 0) {
                ZStack {
                    if isTriggering {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .scaleEffect(compact ? 0.52 : 0.6)
                    } else {
                        Image(systemName: command.icon)
                            .font(.system(size: compact ? 11 : 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)

                if showLabel {
                    Text(command.title)
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? (showLabel ? 8 : 6) : (showLabel ? 11 : 8))
            .padding(.vertical, compact ? 4 : 5)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(TileButtonStyle())
        .disabled(isTriggering)
        .accessibilityLabel(command.title)
    }
}

private struct CompactTextCommandCluster: View {
    let title: String
    let commands: [CompanionCommandDefinition]
    let runningCommandId: String?
    let runCommand: @Sendable (CompanionCommandDefinition) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            HStack(spacing: 1) {
                ForEach(commands) { command in
                    Button {
                        Task { await runCommand(command) }
                    } label: {
                        ZStack {
                            if runningCommandId == command.id {
                                ProgressView()
                                    .tint(.white.opacity(0.55))
                                    .scaleEffect(0.5)
                            } else {
                                Text(command.shortCode)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.68))
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 34, height: 26)
                    }
                    .buttonStyle(TileButtonStyle())
                    .disabled(runningCommandId == command.id)
                    .accessibilityLabel("\(command.title), \(command.caption)")
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
        }
    }
}

private struct MacShelfNavigator: View {
    let title: String
    let icon: String
    let isTriggering: Bool
    let centerAction: (() -> Void)?
    let centerIsHighlighted: Bool
    let previousAction: @Sendable () async -> Void
    let nextAction: @Sendable () async -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Button {
                    Task { await previousAction() }
                } label: {
                    navTapRegion(systemName: "chevron.left", alignLeading: true)
                }
                .buttonStyle(TileButtonStyle())
                .disabled(isTriggering)
                .accessibilityLabel("\(title) previous")

                Button {
                    Task { await nextAction() }
                } label: {
                    navTapRegion(systemName: "chevron.right", alignLeading: false)
                }
                .buttonStyle(TileButtonStyle())
                .disabled(isTriggering)
                .accessibilityLabel("\(title) next")
            }

            Group {
                if let centerAction {
                    Button(action: centerAction) {
                        centerLabel
                    }
                    .buttonStyle(TileButtonStyle())
                    .disabled(isTriggering)
                    .accessibilityLabel("Choose \(title.lowercased()) directly")
                } else {
                    centerLabel
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(.horizontal, 1)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
    }

    private var centerLabel: some View {
        HStack(spacing: 6) {
            if isTriggering {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(centerIsHighlighted ? 0.8 : 0.55))
                    .frame(width: 12, height: 12)
            }

            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(centerIsHighlighted ? 0.9 : 0.74))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(centerIsHighlighted ? 0.08 : 0.001))
        .clipShape(Capsule())
    }

    private func navTapRegion(systemName: String, alignLeading: Bool) -> some View {
        HStack(spacing: 0) {
            if alignLeading {
                HStack(spacing: 6) {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

private struct ActiveStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .light, design: .monospaced))
            .foregroundColor(color.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.05))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.14), lineWidth: 0.75)
            )
    }
}

private struct ActiveTimerCapsule: View {
    let shortcutId: String
    let phase: CompanionShortcutRuntimeState.Phase
    let elapsedSeconds: Double?

    @State private var baselineDate = Date()
    @State private var baselineElapsedSeconds: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 7) {
                if phase == .processing {
                    BrailleSpinner()
                        .padding(.horizontal, 2)
                } else {
                    Text(formattedElapsed(at: context.date))
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(white: 1.0, opacity: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .onAppear(perform: syncBaseline)
        .onChange(of: shortcutId) { _, _ in syncBaseline() }
        .onChange(of: phase) { _, _ in syncBaseline() }
        .onChange(of: elapsedSeconds) { _, _ in syncBaseline() }
    }

    private func syncBaseline() {
        baselineDate = Date()
        baselineElapsedSeconds = elapsedSeconds
    }

    private func formattedElapsed(at date: Date) -> String {
        guard let baseline = baselineElapsedSeconds ?? elapsedSeconds else {
            return "--:--"
        }

        let elapsed = max(0, baseline + date.timeIntervalSince(baselineDate))
        return Self.format(elapsed)
    }

    private static func format(_ elapsedSeconds: Double) -> String {
        let total = max(0, Int(elapsedSeconds.rounded(.down)))
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes.formatted()):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}

private struct BrailleSpinner: View {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09, paused: false)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 10)
            Text(frames[tick % frames.count])
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.orange.opacity(0.82))
                .frame(width: 10)
        }
    }
}

private struct CommandFeedbackBadge: View {
    let feedback: CompanionTriggerFeedback

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: feedback.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(feedback.color.opacity(0.68))

            Text(feedback.title)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.56))
                .tracking(0.4)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.035))
        .clipShape(.capsule)
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.08), feedback.color.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
    }
}

private struct CustomMacSwitcher: View {
    let macs: [BridgeManager.PairedMac]
    let activeID: String?
    let nameProvider: (BridgeManager.PairedMac) -> String
    let selectMac: (BridgeManager.PairedMac) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            switcherContent
        }
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.black.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
    }

    private var switcherContent: some View {
        HStack(spacing: 6) {
            ForEach(macs) { pairedMac in
                CustomMacSwitcherPill(
                    title: nameProvider(pairedMac),
                    isActive: pairedMac.id == activeID,
                    action: { selectMac(pairedMac) }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

private struct CustomMacSwitcherPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundColor(foregroundColor)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(backgroundColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        isActive ? .white.opacity(0.92) : .white.opacity(0.72)
    }

    private var backgroundColor: Color {
        isActive ? .white.opacity(0.14) : .white.opacity(0.06)
    }

    private var borderColor: Color {
        isActive ? .white.opacity(0.16) : .white.opacity(0.08)
    }
}

private struct CompanionAppSwitcherSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let apps: [CompanionAppSwitcherApp]
    let activatingAppID: String?
    let selectApp: (CompanionAppSwitcherApp) -> Void
    let dismiss: () -> Void

    private let accentColor = CompanionCommandDefinition.appNext.color
    private let cornerRadius: CGFloat = 18

    private var gridSpacing: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 18 : 14
    }

    private var contentPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 18
    }

    private var tileMinimumWidth: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return horizontalSizeClass == .regular ? 124 : 108
        }
        return horizontalSizeClass == .compact ? 96 : 108
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: tileMinimumWidth, maximum: tileMinimumWidth + 24),
                spacing: gridSpacing,
                alignment: .top
            )
        ]
    }

    private var iconSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 60 : 52
    }

    private var tileMinHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 128 : 112
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(apps) { app in
                    Button {
                        selectApp(app)
                    } label: {
                        appTile(for: app)
                    }
                    .buttonStyle(.plain)
                    .disabled(activatingAppID != nil)
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.top, contentPadding)
            .padding(.bottom, contentPadding + 6)
        }
        .background(Color.surfacePrimary.ignoresSafeArea())
        .navigationTitle("Mac Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: dismiss)
            }
        }
    }

    private func appTile(for app: CompanionAppSwitcherApp) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                appIcon(for: app)

                if activatingAppID == app.id {
                    activatingBadge
                        .padding(4)
                } else if app.isFrontmost {
                    currentAppBadge
                        .padding(4)
                }
            }
            .frame(maxWidth: .infinity)

            Text(app.displayName)
                .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 13 : 12, weight: .semibold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: tileMinHeight, alignment: .top)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    app.isFrontmost ? accentColor.opacity(0.28) : Color.white.opacity(0.08),
                    lineWidth: app.isFrontmost ? 1.2 : 1
                )
        )
    }

    @ViewBuilder
    private func appIcon(for app: CompanionAppSwitcherApp) -> some View {
        if let iconData = app.iconData,
           let image = UIImage(data: iconData) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accentColor.opacity(app.isFrontmost ? 0.20 : 0.12))
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Text(monogram(for: app.displayName))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor.opacity(app.isFrontmost ? 0.95 : 0.82))
                }
        }
    }

    private var activatingBadge: some View {
        ZStack {
            Circle()
                .fill(Color.surfacePrimary.opacity(0.96))
                .frame(width: 22, height: 22)

            ProgressView()
                .tint(accentColor)
                .scaleEffect(0.62)
        }
    }

    private var currentAppBadge: some View {
        Circle()
            .fill(accentColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.surfaceSecondary, lineWidth: 2)
            )
    }

    private func monogram(for title: String) -> String {
        let parts = title
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)

        let letters = parts.compactMap { part in
            part.first.map { String($0).uppercased() }
        }

        if let first = letters.first {
            return letters.count > 1 ? letters.joined() : first
        }

        return String(title.prefix(1)).uppercased()
    }
}

private struct CompanionTriggerFeedback {
    let title: String
    let icon: String
    let color: Color
    let createdAt: Date = .now
}

private struct TalkieToolbarGlyph: View {
    var body: some View {
        ZStack {
            TalkieToolbarWing(side: .left)
            TalkieToolbarWing(side: .right)
        }
        .frame(width: 22, height: 18)
        .foregroundStyle(Color.textSecondary)
        .overlay {
            Image("TalkieBowtie")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.black)
                .blendMode(.destinationOut)
                .padding(0.6)
        }
        .compositingGroup()
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

private struct TalkieToolbarWing: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        switch side {
        case .left:
            leftWing(in: rect)
        case .right:
            rightWing(in: rect)
        }
    }

    private func leftWing(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.08, 0.84, in: rect))
        path.addCurve(
            to: point(0.13, 0.20, in: rect),
            control1: point(0.05, 0.64, in: rect),
            control2: point(0.06, 0.28, in: rect)
        )
        path.addCurve(
            to: point(0.56, 0.56, in: rect),
            control1: point(0.28, 0.13, in: rect),
            control2: point(0.41, 0.38, in: rect)
        )
        path.addCurve(
            to: point(0.08, 0.84, in: rect),
            control1: point(0.37, 0.70, in: rect),
            control2: point(0.17, 0.79, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func rightWing(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.44, 0.44, in: rect))
        path.addCurve(
            to: point(0.90, 0.18, in: rect),
            control1: point(0.60, 0.30, in: rect),
            control2: point(0.78, 0.16, in: rect)
        )
        path.addCurve(
            to: point(0.84, 0.84, in: rect),
            control1: point(0.95, 0.34, in: rect),
            control2: point(0.96, 0.76, in: rect)
        )
        path.addCurve(
            to: point(0.44, 0.44, in: rect),
            control1: point(0.69, 0.82, in: rect),
            control2: point(0.53, 0.60, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Deck Waveform View

private struct DeckWaveformView: View {
    let color: Color
    let signalLevel: Double?
    let isProcessing: Bool
    let isActive: Bool

    private let barCount = 22
    private let maxBarHeight: CGFloat = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.066, paused: !isActive)) { context in
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let barWidth = max(2, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let h = barHeight(index: index, date: context.date)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(barOpacity(height: h)))
                            .frame(width: barWidth, height: h)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .mask(
                    LinearGradient(
                        colors: [.black.opacity(0.30), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 28)
        }
    }

    private func barOpacity(height: CGFloat) -> Double {
        guard isActive else { return 0.16 }
        let fraction = Double(height / maxBarHeight)
        let base: Double = isProcessing ? 0.55 : 0.88
        return base * (0.45 + fraction * 0.55)
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let i = Double(index)
        let n = Double(barCount)

        if !isActive {
            let phase = t * 0.7 + i * 0.55
            return CGFloat(2 + (sin(phase) + 1) * 0.9)
        }

        if isProcessing {
            let w1 = sin(t * 1.7 + i / n * .pi * 3.2)
            let w2 = sin(t * 0.55 + i / n * .pi * 1.1) * 0.35
            let norm = (w1 + w2 + 1.35) / 2.7
            return CGFloat(4 + norm * 20)
        }

        let base = max(0.2, min(signalLevel ?? 0.55, 1.0))
        let f1 = sin(t * 10.5 + i * 0.65) * 0.32
        let f2 = sin(t * 4.2 + i * 1.05) * 0.24
        let f3 = sin(t * 1.7 + i * 0.25) * 0.44
        let raw = base * 0.42 + (f1 + f2 + f3 + 1.0) * 0.29
        return CGFloat(3 + raw * 25)
    }
}

// MARK: - Status Lamp

private struct StatusLamp: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 4)
                    .blur(radius: 2)
            )
            .shadow(color: color.opacity(0.45), radius: 8, x: 0, y: 0)
    }
}

// MARK: - Three Finger Swipe

struct ThreeFingerSwipeCapture: UIViewRepresentable {
    let onSwipeLeft: (@MainActor () -> Void)?
    let onSwipeRight: (@MainActor () -> Void)?
    let onSwipeUp: (@MainActor () -> Void)?
    let onSwipeDown: (@MainActor () -> Void)?
    let onPinchIn: (@MainActor () -> Void)?
    let onPinchOut: (@MainActor () -> Void)?

    init(
        onSwipeLeft: (@MainActor () -> Void)? = nil,
        onSwipeRight: (@MainActor () -> Void)? = nil,
        onSwipeUp: (@MainActor () -> Void)? = nil,
        onSwipeDown: (@MainActor () -> Void)? = nil,
        onPinchIn: (@MainActor () -> Void)? = nil,
        onPinchOut: (@MainActor () -> Void)? = nil
    ) {
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onPinchIn = onPinchIn
        self.onPinchOut = onPinchOut
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onPinchIn: onPinchIn,
            onPinchOut: onPinchOut
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.installIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onSwipeLeft: (@MainActor () -> Void)?
        private let onSwipeRight: (@MainActor () -> Void)?
        private let onSwipeUp: (@MainActor () -> Void)?
        private let onSwipeDown: (@MainActor () -> Void)?
        private let onPinchIn: (@MainActor () -> Void)?
        private let onPinchOut: (@MainActor () -> Void)?
        private weak var installedView: UIView?
        private lazy var recognizer: UIPanGestureRecognizer = {
            let r = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            r.minimumNumberOfTouches = 3
            r.maximumNumberOfTouches = 3
            r.cancelsTouchesInView = false
            r.delegate = self
            return r
        }()
        private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
            let r = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            r.cancelsTouchesInView = false
            r.delegate = self
            return r
        }()

        init(
            onSwipeLeft: (@MainActor () -> Void)?,
            onSwipeRight: (@MainActor () -> Void)?,
            onSwipeUp: (@MainActor () -> Void)?,
            onSwipeDown: (@MainActor () -> Void)?,
            onPinchIn: (@MainActor () -> Void)?,
            onPinchOut: (@MainActor () -> Void)?
        ) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.onSwipeUp = onSwipeUp
            self.onSwipeDown = onSwipeDown
            self.onPinchIn = onPinchIn
            self.onPinchOut = onPinchOut
        }

        func installIfNeeded(from view: UIView) {
            // Install on the root view for full-screen coverage; superview
            // is a small hosting container and misses touches outside it.
            guard let targetView = view.window?.rootViewController?.view,
                  installedView !== targetView else { return }
            uninstall()
            targetView.addGestureRecognizer(recognizer)
            targetView.addGestureRecognizer(pinchRecognizer)
            installedView = targetView
        }

        func uninstall() {
            recognizer.view?.removeGestureRecognizer(recognizer)
            pinchRecognizer.view?.removeGestureRecognizer(pinchRecognizer)
            installedView = nil
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let t = recognizer.translation(in: recognizer.view)
            let isHorizontal = abs(t.x) > abs(t.y)

            Task { @MainActor in
                if isHorizontal {
                    guard abs(t.x) > 70 else { return }
                    if t.x < 0 { onSwipeLeft?() } else { onSwipeRight?() }
                } else {
                    guard abs(t.y) > 60 else { return }
                    if t.y < 0 { onSwipeUp?() } else { onSwipeDown?() }
                }
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let scale = recognizer.scale

            Task { @MainActor in
                if scale < 0.88 {
                    onPinchIn?()
                } else if scale > 1.12 {
                    onPinchOut?()
                }
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - Trackpad Surface

private struct TrackpadSurface: View {
    let onEvent: (BridgeClient.TrackpadEvent, Double, Double) -> Void
    let onInteractionChanged: (Bool) -> Void

    @State private var lastLocation: CGPoint? = nil
    @State private var isTouching = false
    @State private var isDragging = false
    @State private var dragActivationTask: Task<Void, Never>?
    private let sensitivity: Double = 2.2

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            VStack(spacing: 4) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.white.opacity(isTouching ? 0.55 : 0.18))
                Text("TRACKPAD")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(isTouching ? 0.35 : 0.12))
                    .tracking(1.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if !isTouching {
                        isTouching = true
                        onInteractionChanged(true)
                        scheduleDragActivation()
                    }
                    if let last = lastLocation {
                        let dx = (value.location.x - last.x) * sensitivity
                        let dy = (last.y - value.location.y) * sensitivity
                        if abs(dx) > 0.5 || abs(dy) > 0.5 {
                            onEvent(isDragging ? .drag : .move, dx, dy)
                        }
                    }
                    lastLocation = value.location
                }
                .onEnded { _ in
                    dragActivationTask?.cancel()
                    dragActivationTask = nil
                    if isDragging {
                        onEvent(.mouseUp, 0, 0)
                    }
                    isDragging = false
                    lastLocation = nil
                    withAnimation(.easeOut(duration: 0.2)) { isTouching = false }
                    onInteractionChanged(false)
                }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded { onEvent(.click, 0, 0) }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onEvent(.rightClick, 0, 0) }
        )
        .onDisappear {
            dragActivationTask?.cancel()
            dragActivationTask = nil
            if isDragging {
                onEvent(.mouseUp, 0, 0)
            }
            isDragging = false
            onInteractionChanged(false)
        }
    }

    private func scheduleDragActivation() {
        dragActivationTask?.cancel()
        dragActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard isTouching, !isDragging else { return }
            isDragging = true
            onEvent(.mouseDown, 0, 0)
        }
    }
}

// MARK: - Deck Pages

private struct CompanionDeckPage: Identifiable {
    let id: String
    let title: String
    let shortcutSlots: [String]
    let context: Context

    enum Context {
        case talkie
        case mac
        case custom

        var caption: String {
            switch self {
            case .talkie: return "TALKIE"
            case .mac:    return "MAC"
            case .custom: return "CUSTOM"
            }
        }
    }

    var accentColor: Color {
        switch context {
        case .talkie: return .indigo
        case .mac:    return .teal
        case .custom: return .gray
        }
    }

    var headerTitle: String {
        switch context {
        case .talkie: return "Talkie@Mini"
        case .mac:    return "Apps@Mini"
        case .custom: return title
        }
    }

    var readySubtitle: String {
        switch context {
        case .talkie:
            return "Talkie@Mini is ready for your paired Mac."
        case .mac:
            return "Apps@Mini is ready for your paired Mac."
        case .custom:
            return "\(title) shortcuts are ready for your paired Mac."
        }
    }

    var activeShortcutCount: Int {
        shortcutSlots.filter { !$0.isEmpty }.count
    }

    var switcherIcon: String {
        switch context {
        case .talkie:
            return "waveform"
        case .mac:
            return "desktopcomputer"
        case .custom:
            return "square.grid.2x2"
        }
    }

    var switcherSubtitle: String {
        let previews = shortcutSlots
            .filter { !$0.isEmpty }
            .compactMap { CompanionShortcutDefinition(rawValue: $0)?.title }
            .prefix(3)

        if previews.isEmpty {
            return "\(activeShortcutCount) shortcuts"
        }

        return previews.joined(separator: ", ")
    }

    static func resolvedPages(from livePages: [CompanionShortcutPage]?) -> [CompanionDeckPage] {
        let pages = (livePages ?? []).map { page in
            CompanionDeckPage(
                id: page.id,
                title: page.title,
                shortcutSlots: normalizedSlots(page.shortcutSlots),
                context: inferredContext(id: page.id, title: page.title)
            )
        }

        var merged = pages
        for fallback in defaultPages where !merged.contains(where: { $0.id == fallback.id }) {
            merged.append(fallback)
        }

        return merged.sorted { lhs, rhs in
            sortRank(for: lhs.id) < sortRank(for: rhs.id)
        }
    }

    private static let defaultPages: [CompanionDeckPage] = [
        CompanionDeckPage(
            id: "talkie",
            title: "Talkie",
            shortcutSlots: normalizedSlots(CompanionShortcutDefinition.talkiePageSlots),
            context: .talkie
        ),
        CompanionDeckPage(
            id: "mac",
            title: "Mac",
            shortcutSlots: normalizedSlots(CompanionShortcutDefinition.macPageSlots),
            context: .mac
        ),
    ]

    private static func normalizedSlots(_ slots: [String]) -> [String] {
        let trimmed = Array(slots.prefix(16))
        if trimmed.count == 16 { return trimmed }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }

    private static func inferredContext(id: String, title: String) -> Context {
        let normalizedID = id.lowercased()
        let normalizedTitle = title.lowercased()

        if normalizedID == "talkie" || normalizedTitle.contains("talkie") {
            return .talkie
        }
        if normalizedID == "mac" || normalizedTitle.contains("mac") {
            return .mac
        }
        return .custom
    }

    private static func sortRank(for id: String) -> Int {
        switch id {
        case "talkie": return 0
        case "mac":    return 1
        default:       return 10
        }
    }
}

private struct CommandDeckSpaceSwitcher: View {
    let pages: [CompanionDeckPage]
    let selectedPageID: String
    let selectPage: (CompanionDeckPage) -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Switch Space")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        Text("Choose which published command deck space to control from your iPhone.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(pages) { page in
                            CommandDeckSpaceRow(
                                page: page,
                                isSelected: page.id == selectedPageID,
                                action: { selectPage(page) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 320)
            }
            .padding(18)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Color.black.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 20)
        }
    }
}

private struct CommandDeckSpaceRow: View {
    let page: CompanionDeckPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.switcherIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .frame(width: 36, height: 36)
                    .background(page.accentColor.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(page.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text("\(page.activeShortcutCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.72))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Text(page.switcherSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(page.accentColor.opacity(0.48))
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.32))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColor, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        isSelected ? page.accentColor.opacity(0.18) : Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        isSelected ? page.accentColor.opacity(0.42) : Color.white.opacity(0.08)
    }
}

// MARK: - Contextual Commands

private struct CompanionCommandDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let caption: String
    let icon: String
    let color: Color

    let shortCode: String

    static let enter = CompanionCommandDefinition(
        id: "deck-enter",
        title: "Enter",
        subtitle: "Press Return in the current Mac app.",
        caption: "RETURN",
        icon: "return",
        color: .green,
        shortCode: "ENTER"
    )

    static let delete = CompanionCommandDefinition(
        id: "deck-delete",
        title: "Delete",
        subtitle: "Send a delete key press to the current Mac app.",
        caption: "DELETE",
        icon: "delete.left",
        color: .orange,
        shortCode: "DELETE"
    )

    static let select = CompanionCommandDefinition(
        id: "deck-select-all",
        title: "Select",
        subtitle: "Select everything in the current context.",
        caption: "CMD+A",
        icon: "selection.pin.in.out",
        color: .blue,
        shortCode: "SELECT"
    )

    static let paste = CompanionCommandDefinition(
        id: "deck-paste",
        title: "Paste",
        subtitle: "Paste clipboard contents into the current Mac app.",
        caption: "CMD+V",
        icon: "doc.on.clipboard",
        color: .mint,
        shortCode: "PASTE"
    )

    static let copy = CompanionCommandDefinition(
        id: "deck-copy",
        title: "Copy",
        subtitle: "Copy selection in the current Mac app.",
        caption: "CMD+C",
        icon: "doc.on.doc",
        color: .mint,
        shortCode: "COPY"
    )

    static let escape = CompanionCommandDefinition(
        id: "deck-escape",
        title: "Esc",
        subtitle: "Press Escape in the current Mac app.",
        caption: "ESC",
        icon: "escape",
        color: .gray,
        shortCode: "ESC"
    )

    static let up = CompanionCommandDefinition(
        id: "deck-up",
        title: "Up",
        subtitle: "Move focus up in the current Mac app.",
        caption: "ARROW",
        icon: "arrow.up",
        color: .cyan,
        shortCode: "UP"
    )

    static let down = CompanionCommandDefinition(
        id: "deck-down",
        title: "Down",
        subtitle: "Move focus down in the current Mac app.",
        caption: "ARROW",
        icon: "arrow.down",
        color: .cyan,
        shortCode: "DOWN"
    )

    static let left = CompanionCommandDefinition(
        id: "deck-left",
        title: "Left",
        subtitle: "Move focus left in the current Mac app.",
        caption: "ARROW",
        icon: "arrow.left",
        color: .cyan,
        shortCode: "LEFT"
    )

    static let right = CompanionCommandDefinition(
        id: "deck-right",
        title: "Right",
        subtitle: "Move focus right in the current Mac app.",
        caption: "ARROW",
        icon: "arrow.right",
        color: .cyan,
        shortCode: "RIGHT"
    )

    static let space = CompanionCommandDefinition(
        id: "deck-space",
        title: "Space",
        subtitle: "Press Space in the current Mac app.",
        caption: "SPACE",
        icon: "space",
        color: .pink,
        shortCode: "SPACE"
    )

    static let ctrlC = CompanionCommandDefinition(
        id: "deck-ctrl-c",
        title: "Ctrl-C",
        subtitle: "Send an interrupt to the current Mac terminal.",
        caption: "CONTROL",
        icon: "xmark.circle",
        color: .red,
        shortCode: "CTRL-C"
    )

    static let windowPrevious = CompanionCommandDefinition(
        id: "deck-window-previous",
        title: "Prev Window",
        subtitle: "Switch to the previous window in the current Mac app.",
        caption: "CMD+SHIFT+`",
        icon: "rectangle.on.rectangle",
        color: .teal,
        shortCode: "WIN<"
    )

    static let windowNext = CompanionCommandDefinition(
        id: "deck-window-next",
        title: "Next Window",
        subtitle: "Switch to the next window in the current Mac app.",
        caption: "CMD+`",
        icon: "rectangle.on.rectangle",
        color: .teal,
        shortCode: "WIN>"
    )

    static let tabPrevious = CompanionCommandDefinition(
        id: "deck-tab-previous",
        title: "Prev Tab",
        subtitle: "Switch to the previous tab in supported Mac apps.",
        caption: "APP-AWARE",
        icon: "arrow.left.square",
        color: .indigo,
        shortCode: "TAB<"
    )

    static let tabNext = CompanionCommandDefinition(
        id: "deck-tab-next",
        title: "Next Tab",
        subtitle: "Switch to the next tab in supported Mac apps.",
        caption: "APP-AWARE",
        icon: "arrow.right.square",
        color: .indigo,
        shortCode: "TAB>"
    )

    static let appPrevious = CompanionCommandDefinition(
        id: "deck-app-previous",
        title: "Prev App",
        subtitle: "Switch to the previous recent app on your Mac.",
        caption: "CMD+SHIFT+TAB",
        icon: "square.stack.3d.up",
        color: .orange,
        shortCode: "APP<"
    )

    static let appNext = CompanionCommandDefinition(
        id: "deck-app-next",
        title: "Next App",
        subtitle: "Switch to the next recent app on your Mac.",
        caption: "CMD+TAB",
        icon: "square.stack.3d.up.fill",
        color: .orange,
        shortCode: "APP>"
    )

    static let spaceLeft = CompanionCommandDefinition(
        id: "deck-space-left",
        title: "Space Left",
        subtitle: "Move one macOS Space to the left.",
        caption: "CTRL+LEFT",
        icon: "arrow.left",
        color: .cyan,
        shortCode: "SP<"
    )

    static let spaceRight = CompanionCommandDefinition(
        id: "deck-space-right",
        title: "Space Right",
        subtitle: "Move one macOS Space to the right.",
        caption: "CTRL+RIGHT",
        icon: "arrow.right",
        color: .cyan,
        shortCode: "SP>"
    )

    static let spaceLeftTwo = CompanionCommandDefinition(
        id: "deck-space-left-2",
        title: "Two Left",
        subtitle: "Move two macOS Spaces to the left.",
        caption: "CTRL+LEFT x2",
        icon: "chevron.left.2",
        color: .cyan,
        shortCode: "2<"
    )

    static let spaceRightTwo = CompanionCommandDefinition(
        id: "deck-space-right-2",
        title: "Two Right",
        subtitle: "Move two macOS Spaces to the right.",
        caption: "CTRL+RIGHT x2",
        icon: "chevron.right.2",
        color: .cyan,
        shortCode: "2>"
    )

    static func definition(for id: String) -> CompanionCommandDefinition? {
        all.first(where: { $0.id == id })
    }

    private static let all: [CompanionCommandDefinition] = [
        .enter,
        .delete,
        .select,
        .paste,
        .copy,
        .escape,
        .up,
        .down,
        .left,
        .right,
        .space,
        .ctrlC,
        .windowPrevious,
        .windowNext,
        .tabPrevious,
        .tabNext,
        .appPrevious,
        .appNext,
        .spaceLeft,
        .spaceRight,
        .spaceLeftTwo,
        .spaceRightTwo,
    ]
}

private extension CompanionCommandDefinition {
    var confirmationTitle: String {
        "\(shortCode) SENT"
    }
}

private extension CompanionShortcutDefinition {
    func confirmationTitle(from message: String?) -> String {
        if let message {
            let trimmed = message
                .replacingOccurrences(of: " opened", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: " started", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: " on your mac", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: " on mac", with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty, trimmed.count <= 18 {
                return trimmed.uppercased()
            }
        }

        return title.uppercased()
    }
}

// MARK: - Shortcut Definitions

private enum CompanionShortcutDefinition: String, CaseIterable {
    case talkieRecord = "talkie-record"
    case talkieDictate = "talkie-dictate"
    case talkieSearch = "talkie-search"
    case macSessions = "mac-sessions"
    case macWindows = "mac-windows"
    case macClaude = "mac-claude"
    case talkieSSH = "talkie-ssh"
    case itermDictate = "iterm-dictate"
    case talkieSettings = "talkie-settings"
    case talkieMemos = "talkie-memos"
    case talkieKeyboard = "talkie-keyboard"
    case talkieHome = "talkie-home"
    case talkieAgent = "talkie-agent"
    case talkiePending = "talkie-pending"
    case talkieCommand = "talkie-command"
    case talkieRecent = "talkie-recent"
    case talkieDevices = "talkie-devices"
    case macPasteImage = "mac-paste-image"

    static let talkiePageSlots: [String] = [
        Self.talkieDictate.rawValue,
        Self.talkieRecord.rawValue,
        Self.talkieSettings.rawValue,
        Self.talkieSearch.rawValue,
        Self.macClaude.rawValue,
        Self.talkieAgent.rawValue,
        Self.talkieSSH.rawValue,
        Self.macSessions.rawValue,
        Self.macWindows.rawValue,
        Self.talkieKeyboard.rawValue,
        Self.talkieMemos.rawValue,
        Self.talkieCommand.rawValue,
        Self.talkiePending.rawValue,
        Self.talkieRecent.rawValue,
        Self.talkieHome.rawValue,
        Self.macPasteImage.rawValue,
    ]

    static let macPageSlots: [String] = [
        Self.macWindows.rawValue,
        Self.macPasteImage.rawValue,
        Self.talkieKeyboard.rawValue,
        Self.itermDictate.rawValue,
        Self.macSessions.rawValue,
        Self.macClaude.rawValue,
        Self.talkieAgent.rawValue,
        Self.talkieSSH.rawValue,
        Self.talkieCommand.rawValue,
        Self.talkieSearch.rawValue,
        Self.talkieMemos.rawValue,
        Self.talkieRecent.rawValue,
        Self.talkieDevices.rawValue,
        Self.talkieHome.rawValue,
        Self.talkiePending.rawValue,
        "",
    ]

    static let defaultSlots = talkiePageSlots

    var title: String {
        switch self {
        case .talkieRecord:   return "Record Memo"
        case .talkieDictate:  return "Dictate"
        case .talkieSearch:   return "Search"
        case .macSessions:    return "Workflows"
        case .macWindows:     return "Desktop Preview"
        case .macClaude:      return "Claude"
        case .talkieSSH:      return "Shell"
        case .itermDictate:   return "New iTerm"
        case .talkieSettings: return "Voice Command"
        case .talkieMemos:    return "Memos"
        case .talkieKeyboard: return "Record Screen"
        case .talkieHome:     return "Home"
        case .talkieAgent:    return "Pi"
        case .talkiePending:  return "Pending"
        case .talkieCommand:  return "Palette"
        case .talkieRecent:   return "Recents"
        case .talkieDevices:  return "Pairing"
        case .macPasteImage:  return "Share Image"
        }
    }

    var subtitle: String {
        switch self {
        case .talkieRecord:   return "Start or stop a memo on your Mac."
        case .talkieDictate:  return "Start or stop dictation on your Mac."
        case .talkieSearch:   return "Open search inside Talkie on Mac."
        case .macSessions:    return "Jump into your workflow picker on Mac."
        case .macWindows:     return "See the current state of your Mac desktop."
        case .macClaude:      return "Open the Claude console tab on your Mac."
        case .talkieSSH:      return "Open the Talkie Shell tab on your Mac."
        case .itermDictate:   return "Open iTerm, then arm dictation."
        case .talkieSettings: return "Start voice command capture on Mac."
        case .talkieMemos:    return "Jump to your memo library on Mac."
        case .talkieKeyboard: return "Begin screen recording on your Mac."
        case .talkieHome:     return "Bring Talkie home to the front."
        case .talkieAgent:    return "Open the Pi console tab on your Mac."
        case .talkiePending:  return "Open pending actions on Mac."
        case .talkieCommand:  return "Open the Mac command palette."
        case .talkieRecent:   return "Open recent agent activity on Mac."
        case .talkieDevices:  return "Open device and companion settings on Mac."
        case .macPasteImage:  return "Send a screenshot or photo to your Mac."
        }
    }

    var icon: String {
        switch self {
        case .talkieRecord:   return "square.and.pencil"
        case .talkieDictate:  return "mic.fill"
        case .talkieSearch:   return "magnifyingglass"
        case .macSessions:    return "wand.and.stars"
        case .macWindows:     return "display"
        case .macClaude:      return "sparkles"
        case .talkieSSH:      return "terminal"
        case .itermDictate:   return "command.circle"
        case .talkieSettings: return "waveform.badge.mic"
        case .talkieMemos:    return "waveform"
        case .talkieKeyboard: return "record.circle"
        case .talkieHome:     return "house"
        case .talkieAgent:    return "circle.grid.cross"
        case .talkiePending:  return "hourglass"
        case .talkieCommand:  return "command"
        case .talkieRecent:   return "clock.arrow.circlepath"
        case .talkieDevices:  return "ipad.and.iphone"
        case .macPasteImage:  return "photo.on.rectangle.angled"
        }
    }

    var color: Color {
        switch self {
        case .talkieRecord:   return .indigo
        case .talkieDictate:  return .orange
        case .talkieSearch:   return .blue
        case .macSessions:    return .teal
        case .macWindows:     return .green
        case .macClaude:      return .purple
        case .talkieSSH:      return .mint
        case .itermDictate:   return .orange
        case .talkieSettings: return .pink
        case .talkieMemos:    return .pink
        case .talkieKeyboard: return .red
        case .talkieHome:     return .indigo
        case .talkieAgent:    return .blue
        case .talkiePending:  return .yellow
        case .talkieCommand:  return .indigo
        case .talkieRecent:   return .gray
        case .talkieDevices:  return .cyan
        case .macPasteImage:  return .cyan
        }
    }
}

// MARK: - Runtime State Extensions

private extension CompanionShortcutRuntimeState.Phase {
    var badgeTitle: String {
        switch self {
        case .preparing:  return "PREP"
        case .recording:  return "LIVE"
        case .processing: return "FINISH"
        }
    }
}

private extension CompanionShortcutRuntimeState {
    var formattedElapsed: String? {
        guard let elapsedSeconds else { return nil }
        let total = max(0, Int(elapsedSeconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return "\(m.formatted()):\(s.formatted(.number.precision(.integerLength(2))))"
    }

    func headerCaption(for shortcut: CompanionShortcutDefinition) -> String {
        switch phase {
        case .preparing:  return "GETTING READY"
        case .recording:  return shortcut.liveVerb.uppercased()
        case .processing: return "WRAPPING UP"
        }
    }

    func secondaryStatusLine(for shortcut: CompanionShortcutDefinition) -> String {
        switch (shortcut, phase, canStop) {
        case (_, .recording, true):               return "Tap this strip to stop."
        case (_, .preparing, _):                  return "Talkie is spinning up the shortcut now."
        case (.talkieRecord, .processing, _):     return "Audio is being finalized and saved into Talkie."
        case (.talkieDictate, .processing, _):    return "Talkie is transcribing and routing your dictation."
        case (.itermDictate, .processing, _):     return "Talkie is transcribing and sending to iTerm."
        case (_, _, true):                        return "Tap this strip to stop."
        default:                                  return "Still running on your Mac."
        }
    }
}

private extension CompanionShortcutRecentResult {
    var completedDate: Date? {
        ISO8601DateFormatter().date(from: completedAt)
    }

    var isFresh: Bool {
        guard let completedDate else { return false }
        let age = Date().timeIntervalSince(completedDate)
        return age >= 0 && age <= 120
    }

    var resultPreview: String {
        let trimmed = resultText
            .replacing("\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            return trimmed
        }

        switch CompanionShortcutDefinition(rawValue: shortcutId) {
        case .some(.talkieDictate), .some(.itermDictate):
            return "Dictation finished. No text captured."
        default:
            return "Command finished."
        }
    }
}

private extension CompanionShortcutDefinition {
    var liveVerb: String {
        switch self {
        case .talkieDictate, .itermDictate: return "Listening"
        default:                            return "Live"
        }
    }

    var shortCode: String {
        switch self {
        case .talkieRecord:   return "REC"
        case .talkieDictate:  return "DICT"
        case .talkieSearch:   return "FIND"
        case .macSessions:    return "FLOW"
        case .macWindows:     return "PEEK"
        case .macClaude:      return "AI"
        case .talkieSSH:      return "TTY"
        case .itermDictate:   return "ITRM"
        case .talkieSettings: return "VOICE"
        case .talkieMemos:    return "MEMO"
        case .talkieKeyboard: return "SCRN"
        case .talkieHome:     return "HOME"
        case .talkieAgent:    return "AGENT"
        case .talkiePending:  return "QUEUE"
        case .talkieCommand:  return "CMD"
        case .talkieRecent:   return "LOG"
        case .talkieDevices:  return "LINK"
        case .macPasteImage:  return "IMG"
        }
    }

    var prefersDictationCommands: Bool {
        switch self {
        case .talkieRecord, .talkieDictate, .itermDictate:
            return true
        default:
            return false
        }
    }
}
