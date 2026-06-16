//
//  AppNavigation.swift
//  Talkie macOS
//
//  Main app navigation with a custom self-sized sidebar rail.
//
//  Sidebar has 3 display states:
//    State 0 — Hidden: custom sidebar removed from the leading column
//    State 1 — Compact: fixed icon rail, accent bar + fixed-position icons
//    State 2 — Expanded: icon rail + independent label column, wordmark + section headers
//
//  Design principle: Icons stay at the SAME X position between State 1 and State 2.
//  Only the label text area appears/disappears. The Talkie logo fills the accent+icon
//  zone, and the wordmark aligns with section label text.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TalkieKit

private let appNavigationLog = Log(.ui)

extension NSNotification.Name {
    static let navigateToSettings = NSNotification.Name("navigateToSettings")
    static let navigateToAgentSettings = NSNotification.Name("navigateToAgentSettings")
    static let navigateToEngineMonitor = NSNotification.Name("navigateToEngineMonitor")
    static let navigateToAgentMonitor = NSNotification.Name("navigateToAgentMonitor")

    @available(*, deprecated, renamed: "navigateToAgentSettings")
    static let navigateToLiveSettings = navigateToAgentSettings

    @available(*, deprecated, renamed: "navigateToAgentMonitor")
    static let navigateToLiveMonitor = navigateToAgentMonitor

    #if DEBUG
    static let debugNavigate = NSNotification.Name("debugNavigate")
    #endif
}

enum NavigationSection: Hashable {
    case home           // Main Talkie home/dashboard
    case drafts         // Quick text editing with voice dictation and AI polish (was scratchPad)
    case notes          // Standalone notes (screenshots, text snippets)
    case allMemos       // All Memos view (unified components)
    case recordings     // Unified recordings view (memos + dictations from recordings table)
    case liveDashboard  // Live home/insights view
    case dictations     // Dictations list (unified recordings UI, dictation filter)
    case aiResults
    case workflows
    case activityLog
    case contextRules   // App-aware post-transcription prompting
    case systemConsole
    case screenshots
    case pendingActions
    case recentlyDeleted  // Restore or permanently delete soft-deleted memos / notes
    case talkieService  // Accessible via engine icon click, not in sidebar
    case talkieLiveMonitor  // Accessible via live icon click, not in sidebar
    case models
    case allowedCommands
    case smartFolder(String)

    case settings       // Settings with 3-column layout (sidebar + subsections + content)

    #if DEBUG
    // Design God Mode sections (only visible when DesignModeManager.shared.isEnabled)
    case designHome       // Design system token reference
    case designAudit      // Design system compliance audit
    case designComponents // Component library showcase
    #endif
}

extension NavigationSection {
    var perfName: String {
        switch self {
        case .home: return "Home"
        case .drafts: return "Compose"
        case .notes: return "Notes"
        case .allMemos: return "AllMemos"
        case .recordings: return "Library"
        case .liveDashboard: return "LiveDashboard"
        case .dictations: return "Dictations"
        case .aiResults: return "AIResults"
        case .workflows: return "Workflows"
        case .activityLog: return "ActivityLog"
        case .systemConsole: return "Console"
        case .screenshots: return "Markup"
        case .pendingActions: return "PendingActions"
        case .recentlyDeleted: return "RecentlyDeleted"
        case .talkieService: return "TalkieService"
        case .talkieLiveMonitor: return "TalkieAgentMonitor"
        case .models: return "Models"
        case .allowedCommands: return "AllowedCommands"
        case .contextRules: return "Context"
        case .smartFolder(let name): return "SmartFolder:\(name)"
        case .settings: return "Settings"
        #if DEBUG
        case .designHome: return "DesignHome"
        case .designAudit: return "DesignAudit"
        case .designComponents: return "DesignComponents"
        #endif
        }
    }
}

struct AppNavigation: View {
    @Environment(\.navigationState) private var nav

    // GRDB-backed ViewModel for memo data
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    // Singletons - observe remote data
    private let settings = SettingsManager.shared
    private let pendingActionsManager = PendingActionsManager.shared

    // Local view state (synced with NavigationState)
    @State private var selectedSection: NavigationSection? = .home
    @State private var previousSection: NavigationSection? = .home
    @State private var selectedMemo: VoiceMemo?
    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var selectedSettingsSection: SettingsSection = .about
    @State private var searchText = ""

    // Cached counts for badge display
    @State private var cachedErrorCount: Int = 0
    @State private var cachedWorkflowCount: Int = 0

    // Column visibility for the content/detail NavigationSplitView.
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Sidebar display mode
    @AppStorage("app.sidebar.iconsOnly") private var appSidebarIconsOnly = false
    @State private var didPrepareConsoleRegistry = false
    @AppStorage("sidebar.isHidden") private var sidebarHidden = true
    @AppStorage("sidebar.expandedLabelWidth") private var storedExpandedLabelWidth: Double = Double(SidebarLayout.labelWidth)
    @State private var expandedLabelWidth: Double
    @AppStorage(SidebarStyleStorage.surfaceKey) private var surfaceStyleRaw = SidebarSurfaceStyle.default.rawValue
    @AppStorage(SidebarStyleStorage.indicatorKey) private var indicatorStyleRaw = SidebarIndicatorStyle.default.rawValue
    @AppStorage(SidebarStyleStorage.iconKey) private var iconStyleRaw = SidebarIconStyle.default.rawValue
    @AppStorage(SidebarStyleStorage.motionKey) private var motionStyleRaw = SidebarMotionStyle.default.rawValue
    @AppStorage(SidebarStyleStorage.effectKey) private var effectStyleRaw = SidebarEffectStyle.flush.rawValue
    private static let sidebarMinLabelWidth: Double = 100
    private static let sidebarMaxLabelWidth: Double = 220
    private static let sidebarResizeActivationDistance: CGFloat = 6
    private static let sidebarCollapseLabelWidth: Double = 44

    private static func clampedSidebarLabelWidth(_ width: Double) -> Double {
        min(sidebarMaxLabelWidth, max(sidebarMinLabelWidth, width))
    }

    private var sidebarStyle: SidebarStyle {
        SidebarStyle(
            surface: SidebarSurfaceStyle(rawValue: surfaceStyleRaw) ?? .default,
            indicator: SidebarIndicatorStyle(rawValue: indicatorStyleRaw) ?? .default,
            icon: SidebarIconStyle(rawValue: iconStyleRaw) ?? .default,
            motion: SidebarMotionStyle(rawValue: motionStyleRaw) ?? .default,
            effect: SidebarEffectStyle(rawValue: effectStyleRaw) ?? .flush
        )
    }

    // Responsive 3-column layout - when window is too narrow, middle column becomes a sheet
    @State private var isNarrowForThreeColumns = false
    @State private var showContentSheet = false
    private static let threeColumnThreshold: CGFloat = 700  // Below this, 3-column becomes 2-column + sheet

    // Debug: Show legacy Memos/Dictations screens (hidden by default, enable via DebugToolbar)
    #if DEBUG
    @AppStorage("debug.showLegacyScreens") private var showLegacyScreens = false
    #endif

    // App-wide drop zone state
    @State private var isDropTargeted = false
    @State private var dropProgress: AudioDropService.DropProgress?
    @State private var dropError: String?
    @State private var dropTask: Task<Void, Never>?

    // Optional initializer for screenshot capture with specific navigation state
    init(initialSection: NavigationSection? = .home, initialSettingsSection: SettingsSection = .about) {
        _selectedSection = State(initialValue: Self.resolveInitialSection(initialSection))
        _selectedSettingsSection = State(initialValue: initialSettingsSection)
        let defaults = UserDefaults.standard
        let storedWidth = defaults.object(forKey: "sidebar.expandedLabelWidth") == nil
            ? Double(SidebarLayout.labelWidth)
            : defaults.double(forKey: "sidebar.expandedLabelWidth")
        _expandedLabelWidth = State(initialValue: Self.clampedSidebarLabelWidth(storedWidth))
    }

    private static func resolveInitialSection(_ initialSection: NavigationSection?) -> NavigationSection? {
        let env = ProcessInfo.processInfo.environment

        if env["TALKIE_START_IN_CONSOLE"] == "1" {
            return .systemConsole
        }

        return initialSection
    }

    private func toggleSidebarRenderMode() {
        let next = !appSidebarIconsOnly
        appNavigationLog.info(
            "[Sidebar] toggleRenderMode",
            detail: "iconsOnly=\(appSidebarIconsOnly) → \(next)",
            section: "SidebarState"
        )
        withAnimation(sidebarTransition.animation) {
            appSidebarIconsOnly.toggle()
        }
    }

    private func collapseSidebarToCompact(restoring width: Double) {
        let restoredWidth = Self.clampedSidebarLabelWidth(width)
        expandedLabelWidth = restoredWidth
        storedExpandedLabelWidth = restoredWidth

        appNavigationLog.info(
            "[Sidebar] collapseToCompact",
            detail: "restoredWidth=\(Int(restoredWidth.rounded()))",
            section: "SidebarState"
        )

        withAnimation(SidebarMotion.defaultSpring) {
            appSidebarIconsOnly = true
        }
    }

    /// Symmetric to `collapseSidebarToCompact` — used when the user
    /// drags the edge handle rightward while in compact mode. Commits
    /// the new label width and flips the icons-only flag off in one
    /// animated transaction so the column springs out to the requested
    /// width.
    private func expandSidebarFromCompact(to width: Double) {
        let clamped = Self.clampedSidebarLabelWidth(width)
        expandedLabelWidth = clamped
        storedExpandedLabelWidth = clamped

        appNavigationLog.info(
            "[Sidebar] expandFromCompact",
            detail: "width=\(Int(clamped.rounded()))",
            section: "SidebarState"
        )

        withAnimation(SidebarMotion.defaultSpring) {
            appSidebarIconsOnly = false
        }
    }

    private func toggleSidebar() {
        withAnimation(SidebarMotion.defaultSpring) {
            sidebarHidden.toggle()
        }
    }

    private func sectionName(for section: NavigationSection) -> String {
        section.perfName
    }

    private func navigateFromLearn(to section: NavigationSection) {
        if section == .workflows || section == .settings {
            columnVisibility = .all
        }
        selectedSection = section
    }

    private func openSettingsFromLearn(_ section: SettingsSection) {
        selectedSettingsSection = section
        columnVisibility = .all
        selectedSection = .settings
    }

    private var sidebarWidthExpanded: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        let total = SidebarLayout.railWidth + CGFloat(expandedLabelWidth)
        return (total, total, total)
    }

    private static let sidebarWidthCompact: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (
        SidebarLayout.railWidth,
        SidebarLayout.railWidth,
        SidebarLayout.railWidth
    )
    private static let workflowsColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (260, 300, 400)
    private static let libraryColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (280, 320, 440)
    private var contentColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if selectedSection == .workflows { return Self.workflowsColumnWidth }
        if selectedSection == .recordings { return Self.libraryColumnWidth }
        return (selectedSection == .settings && settings.settingsSidebarIconsOnly)
            ? SettingsSidebarState.compactColumnWidth
            : SettingsSidebarState.expandedColumnWidth
    }

    /// Pre-rendered crisp app icon at 2x for Retina
    private static let crispAppIcon: NSImage = {
        if let icon = NSImage(named: "AppIcon") {
            icon.size = NSSize(width: 64, height: 64)
            return icon
        }
        // Fallback: get from bundle at explicit size
        let icon = NSApp.applicationIconImage ?? NSImage()
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }()

    private var sidebarIconsOnly: Bool {
        appSidebarIconsOnly
    }

    private var sidebarTransition: SidebarTransition {
        let animation: Animation = edgeHandleDragging ? .linear(duration: 0) : SidebarMotion.defaultSpring
        return SidebarTransition.resolve(
            isCompact: sidebarIconsOnly,
            scrubOverride: nil,
            expanded: SidebarTransition.WidthSpec(
                min: sidebarWidthExpanded.min,
                ideal: sidebarWidthExpanded.ideal,
                max: sidebarWidthExpanded.max
            ),
            compact: SidebarTransition.WidthSpec(
                min: Self.sidebarWidthCompact.min,
                ideal: Self.sidebarWidthCompact.ideal,
                max: Self.sidebarWidthCompact.max
            ),
            animation: animation
        )
    }

    // Track if body has been accessed (for profiling)
    @State private var didLogBodyAccess = false

    private func logBodyAccessIfNeeded() {
        if !didLogBodyAccess {
            StartupProfiler.shared.mark("nav.body.start")
            DispatchQueue.main.async { didLogBodyAccess = true }
        }
    }


    var body: some View {
        #if DEBUG
        let _ = FrameRateMonitor.shared.recordBodyAccess("AppNavigation")
        #endif
        let _ = logBodyAccessIfNeeded()
        mainLayout
            .environment(\.sidebarTransition, sidebarTransition)
            .environment(\.sidebarStyle, sidebarStyle)
            .environment(\.sidebarShowMeasurements, false)
            .transaction { transaction in
                if edgeHandleDragging {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onAppear {
                columnVisibility = .all
                #if DEBUG
                FrameRateMonitor.shared.setSection(sectionName(for: selectedSection ?? .home))
                FrameRateMonitor.shared.setSidebarMode(sidebarIconsOnly ? "compact" : "expanded")
                #endif
            }
            .onChange(of: storedExpandedLabelWidth) { _, newValue in
                guard !edgeHandleDragging else { return }
                let clamped = Self.clampedSidebarLabelWidth(newValue)
                if expandedLabelWidth != clamped {
                    expandedLabelWidth = clamped
                }
            }
            #if DEBUG
            .onChange(of: selectedSection) { _, new in
                if let new {
                    FrameRateMonitor.shared.setSection(sectionName(for: new))
                }
            }
            .onChange(of: sidebarIconsOnly) { _, new in
                FrameRateMonitor.shared.setSidebarMode(new ? "compact" : "expanded")
            }
            .onChange(of: edgeHandleDragging) { _, dragging in
                FrameRateMonitor.shared.setInteraction(dragging ? "handle-drag" : "")
            }
            #endif
    }

    @ViewBuilder
    private var mainLayout: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < Self.threeColumnThreshold

            VStack(spacing: 0) {
                navigationSplitContent
                StatusBar()
            }
            .coordinateSpace(name: "mainLayout")
            .overlay(alignment: .topLeading) {
                SidebarTooltipOverlay(surface: Theme.current.surfaceBase, foreground: Theme.current.foreground)
            }
            .overlay(alignment: .center) {
                // Big-screen recording companion. Renders on the cream
                // canvas while a memo recording is active; the title-bar
                // pill is the always-on baseline. Sits beneath the chrome
                // bar in z-order so the bar / page header stay readable.
                RecordingCompanionSurface(windowID: nav.id)
                    .padding(.top, PageLayout.headerHeight)
            }
            .overlay(alignment: .top) {
                TalkieChromeBar()
                    // Sits as close to the macOS title-bar baseline as
                    // we can without colliding with the traffic-light
                    // cluster. Gives the page content below room to
                    // breathe — surface list headers no longer compete
                    // with the pill for the same vertical slot.
                    .padding(.top, 4)
                    .offset(x: (sidebarHidden ? 0 : sidebarTransition.width.ideal) / 2)
            }
            .overlay(alignment: .top) {
                // Page-header proxy. Renders above the chrome bar in z-order
                // so the page title + chrome line stay visible where they
                // would otherwise be overwritten by the bar's capsule. The
                // page publishes its content via the window-local ChromeBarHeader.
                ChromeBarPageHeaderOverlay()
                    .allowsHitTesting(false)
            }
            // Settings gear has moved to the status bar (bottom-left,
            // next to SyncStatusIcon). The window's top-right is now
            // clear, which gives the chrome bar's pill + each surface's
            // header chrome room to breathe.
            .overlay(alignment: .bottomTrailing) {
                AgentHealthBanner()
                    .padding(.trailing, Spacing.md)
                    .padding(.bottom, Spacing.xl)
            }
            .onChange(of: narrow) { _, newValue in
                isNarrowForThreeColumns = newValue
                if !newValue {
                    // Exiting narrow mode - dismiss content sheet
                    showContentSheet = false
                }
            }
            .onAppear {
                isNarrowForThreeColumns = narrow
            }
        }
    }

    @ViewBuilder
    private var navigationSplitContent: some View {
        navigationSplitViewCore
            .navigationSplitViewStyle(.balanced)
            .toolbarBackground(
                TechnicalStyle.isActive ? TechnicalStyle.surface0 : Theme.current.surfaceBase,
                for: .windowToolbar
            )
            .modifier(ToolbarBackgroundVisibilityModifier())
            .modifier(AudioDropModifier(
                isDropTargeted: $isDropTargeted,
                dropProgress: dropProgress,
                dropError: dropError,
                audioDropOverlay: { audioDropOverlay },
                handleAudioDrop: handleAudioDrop
            ))
            .modifier(DebugOverlaysModifier())
            .modifier(NavigationChangeHandlersModifier(
                selectedSection: $selectedSection,
                previousSection: $previousSection,
                selectedSettingsSection: $selectedSettingsSection,
                columnVisibility: $columnVisibility,
                nav: nav,
                memosVM: memosVM,
                sectionName: sectionName,
                usesTwoColumns: usesTwoColumns
            ))
            .modifier(MouseBackNavigationModifier {
                nav.goBack()
            })
            .alertObservers()
            .onAppear {
                StartupProfiler.shared.mark("nav.onAppear")
                if !didPrepareConsoleRegistry {
                    didPrepareConsoleRegistry = true
                    TabDefinitionRegistry.shared.prepareForAppLaunch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAppSidebar)) { _ in
                toggleSidebar()
            }
    }

    @ViewBuilder
    private var navigationSplitViewCore: some View {
        SidebarColumns(isHidden: sidebarHidden) {
            sidebarView
        } trailing: {
            trailingContent
        }
        .toolbar {
            if sidebarHidden {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            sidebarHidden.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Show sidebar")
                }
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if usesTwoColumns || (isNarrowForThreeColumns && !usesTwoColumns) {
            if isNarrowForThreeColumns && !usesTwoColumns {
                narrowThreeColumnContent
            } else {
                mainContentView
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                contentView
                    .navigationSplitViewColumnWidth(
                        min: contentColumnWidth.min,
                        ideal: contentColumnWidth.ideal,
                        max: contentColumnWidth.max
                    )
            } detail: {
                mainContentView
            }
            // Let the native split control be the single titlebar affordance
            // for the workflow/settings content column. The inline button in
            // the column header still carries the hide intent while expanded.
        }
    }

    /// Content for 3-column sections when in narrow layout mode
    @ViewBuilder
    private var narrowThreeColumnContent: some View {
        mainContentView
            .overlay(alignment: .topLeading) {
                // Navigation button to show content column as sheet
                Button(action: { showContentSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: contentSheetIcon)
                            .font(.system(size: 11, weight: .medium))
                        Text(contentSheetTitle)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.current.border.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Show \(contentSheetTitle.lowercased()) menu")
                .padding(.top, 8)
                .padding(.leading, 12)
            }
            .sheet(isPresented: $showContentSheet) {
                contentColumnSheet
            }
    }

    /// Icon for the content sheet navigation button
    private var contentSheetIcon: String {
        switch selectedSection {
        case .settings: return "gear"
        case .workflows: return "wand.and.stars"
        default: return "list.bullet"
        }
    }

    /// Title for the content sheet navigation button
    private var contentSheetTitle: String {
        switch selectedSection {
        case .settings: return "Settings"
        case .workflows: return "Workflows"
        default: return "Menu"
        }
    }

    /// Sheet presentation of the content column for narrow layouts
    private var contentColumnSheet: some View {
        NavigationStack {
            contentView
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                .frame(minHeight: 400, idealHeight: 500, maxHeight: .infinity)
                .onChange(of: selectedSettingsSection) { _, _ in
                    // Dismiss sheet when a settings section is selected
                    showContentSheet = false
                }
                .onChange(of: selectedWorkflowID) { _, _ in
                    // Dismiss sheet when a workflow is selected
                    showContentSheet = false
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Column Logic

    private var usesTwoColumns: Bool {
        switch selectedSection {
        case .home, .drafts, .notes, .models, .allowedCommands, .aiResults, .allMemos,
             .recordings, .liveDashboard, .dictations, .systemConsole, .pendingActions,
             .recentlyDeleted, .contextRules, .screenshots:
            return true
        #if DEBUG
        case .designHome, .designAudit, .designComponents:
            return true
        #endif
        default:
            return false  // workflows and settings use 3-column layout
        }
    }

    // MARK: - Drop Zone

    /// Handle dropped content and create Talkie records.
    private func handleAudioDrop(_ providers: [NSItemProvider]) -> Bool {
        guard AudioDropService.shouldAcceptDrop(providers: providers) else {
            isDropTargeted = false
            dropProgress = nil
            dropError = nil
            return true
        }

        dropTask?.cancel()
        dropTask = Task { @MainActor in
            // Defensive cleanup: regardless of how the task ends, the
            // drop-target flag should not survive past the work. Without
            // this, performDrop's `isDropTargeted = false` could be
            // overridden by a late dropUpdated event during navigation,
            // leaving the overlay stuck on the "Drop to import" empty
            // state after a successful import.
            defer {
                isDropTargeted = false
            }
            do {
                let result = try await AudioDropService.shared.processDroppedItems(
                    providers: providers,
                    onProgress: { progress in
                        self.dropProgress = progress
                        if progress.isComplete {
                            // Clear after short delay
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                if !Task.isCancelled {
                                    self.dropProgress = nil
                                }
                            }
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                switch result {
                case .memo(let memo):
                    selectedSection = .allMemos
                    NotificationCenter.default.post(
                        name: .init("SelectMemo"),
                        object: memo.id
                    )
                case .recording(let recordingID):
                    nav.navigate(
                        to: .recordings,
                        params: ["recordingId": recordingID.uuidString]
                    )
                case .noop:
                    break
                }
            } catch is CancellationError {
                dropProgress = nil
                dropError = nil
            } catch {
                dropError = error.localizedDescription
                // Clear error after delay
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        dropError = nil
                    }
                }
            }

            if !Task.isCancelled {
                dropTask = nil
            }
        }
        return true
    }

    private func cancelDrop() {
        dropTask?.cancel()
        dropTask = nil
        isDropTargeted = false
        dropProgress = nil
        dropError = nil
    }

    /// Visual overlay for app-wide drop zone
    private var audioDropOverlay: some View {
        ZStack {
            // Semi-transparent background. Clicking it dismisses the overlay
            // when no import is in flight — the escape hatch for the case
            // where a phantom drag leaves the "Drop to import" state stuck
            // (see handleAudioDrop's note). Mid-import, the Cancel button is
            // the deliberate exit, so a stray backdrop click won't abort it.
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if dropProgress == nil { cancelDrop() }
                }

            // Center content
            VStack(spacing: Spacing.md) {
                if let error = dropError {
                    // Error state
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.white)
                } else if let progress = dropProgress {
                    // Progress states
                    switch progress {
                    case .validating:
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Checking drop...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    case .copying:
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Copying...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    case .extractingMetadata:
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Reading metadata...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    case .importingURL(let url):
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Saving link...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    case .importingText:
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Saving text...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    case .saving(let filename, let kind):
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Importing \(kind)...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    case .transcribing(let filename, let size):
                        BrailleSpinner(size: 18)
                            .foregroundColor(.white)
                        Text("Transcribing \(size)...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    case .complete:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Imported!")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    if !progress.isComplete {
                        Button("Cancel", systemImage: "xmark.circle") {
                            cancelDrop()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, Spacing.xs)
                    }
                } else {
                    // Drag target state
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                    Text("Drop to import")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("URLs, audio, video, images, PDFs, text, code")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    // Explicit exit — covers the case where the overlay
                    // gets stuck without an active drag to drop or escape.
                    Button("Cancel", systemImage: "xmark.circle") {
                        cancelDrop()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, Spacing.xs)
                    Text("press esc or click outside")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.black.opacity(0.5))
                    )
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.2), value: dropProgress)
        // Esc always exits — dismisses the idle/stuck overlay or cancels an
        // in-flight import.
        .onExitCommand { cancelDrop() }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        ResizableSidebar(
            selection: sidebarSelectionBinding,
            entries: sidebarEntries,
            progress: sidebarTransition.progress,
            accent: Theme.current.accent,
            allCaps: settings.uiAllCaps,
            isScopeTheme: SettingsManager.shared.isScopeTheme,
            handleTint: Theme.current.foreground,
            committedLabelWidth: expandedLabelWidth,
            isCompact: sidebarIconsOnly,
            activationDistance: Self.sidebarResizeActivationDistance,
            minWidth: Self.sidebarMinLabelWidth,
            maxWidth: Self.sidebarMaxLabelWidth,
            collapseWidth: Self.sidebarCollapseLabelWidth,
            isDragging: $edgeHandleDragging,
            onToggle: toggleSidebarRenderMode,
            onResizeEnded: { width in
                let clamped = Self.clampedSidebarLabelWidth(width)
                expandedLabelWidth = clamped
                storedExpandedLabelWidth = clamped
            },
            onCollapse: { restoreWidth in
                collapseSidebarToCompact(restoring: restoreWidth)
            },
            onExpand: { width in
                expandSidebarFromCompact(to: width)
            },
            railHeader: { talkieLogo },
            labelHeader: { baselineAnchoredWordmark },
            footer: {
                Image(systemName: selectedSection == .settings ? "gearshape.fill" : "gear")
                    .font(.system(size: SidebarLayout.iconSize))
                    .foregroundColor(selectedSection == .settings ? Theme.current.accent : Color.secondary)
                    .frame(width: SidebarLayout.railWidth, height: SidebarLayout.rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        #if DEBUG
                        FrameRateMonitor.shared.beginNavigation(to: sectionName(for: .settings), source: "sidebar-footer")
                        #endif
                        selectedSection = .settings
                    }
            }
        )
    }

    @State private var edgeHandleDragging = false

    private var sidebarSelectionBinding: Binding<NavigationSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                #if DEBUG
                if let newValue {
                    FrameRateMonitor.shared.beginNavigation(to: sectionName(for: newValue), source: "sidebar")
                }
                #endif
                selectedSection = newValue
            }
        )
    }

    private var sidebarEntries: [SidebarEntry<NavigationSection>] {
        var entries: [SidebarEntry<NavigationSection>] = []

        entries.append(.item(SidebarItem(id: .home, title: "Home", icon: "house", selectedIcon: "house.fill")))
        entries.append(.item(SidebarItem(id: .recordings, title: "Library", icon: "rectangle.stack", selectedIcon: "rectangle.stack.fill")))
        entries.append(.item(SidebarItem(id: .screenshots, title: "Markup", icon: "pencil.tip.crop.circle")))
        #if DEBUG
        if showLegacyScreens {
            entries.append(.item(SidebarItem(id: .allMemos, title: "Memos", icon: "square.stack", selectedIcon: "square.stack.fill")))
            entries.append(.item(SidebarItem(id: .dictations, title: "Dictations", icon: "waveform.badge.mic", selectedIcon: "mic.circle.fill")))
        }
        #endif
        if settings.hasUnlockedAdvancedFeatures {
            entries.append(.item(SidebarItem(id: .drafts, title: "Compose", icon: "square.and.pencil", selectedIcon: "square.and.pencil.circle.fill")))
            entries.append(.item(SidebarItem(id: .contextRules, title: "Context", icon: "square.stack.3d.forward.dottedline", selectedIcon: "square.stack.3d.forward.dottedline.fill")))
        }

        if pendingActionsManager.hasActiveActions {
            entries.append(.section(id: "activity", title: "Activity"))
            entries.append(.item(SidebarItem(id: .pendingActions, title: "Pending", icon: "clock.arrow.circlepath", selectedIcon: "clock.fill")))
        }

        entries.append(.section(id: "intelligence", title: "Intelligence"))
        // Scope theme renames this slot from "Stats" to "Learn" — the
        // screen for that theme is `ScopeLearnScreen`, an agent-powered
        // discovery interstitial that replaces the data-listing Stats
        // page. Standard themes keep "Stats" → `StatsScreen`.
        if settings.isScopeTheme {
            entries.append(.item(SidebarItem(id: .liveDashboard, title: "Learn", icon: "sparkles", selectedIcon: "sparkles")))
        } else {
            entries.append(.item(SidebarItem(id: .liveDashboard, title: "Stats", icon: "waveform.path.ecg", selectedIcon: "chart.bar.fill")))
        }
        entries.append(.item(SidebarItem(id: .models, title: "Models", icon: "brain", selectedIcon: "brain.fill")))
        entries.append(.item(SidebarItem(id: .aiResults, title: "Actions", icon: "chart.line.uptrend.xyaxis", selectedIcon: "chart.xyaxis.line")))

        if settings.hasUnlockedAdvancedFeatures || settings.isProToolsActive {
            entries.append(.section(id: "tools", title: "Tools"))
        }
        if settings.hasUnlockedAdvancedFeatures {
            entries.append(.item(SidebarItem(id: .workflows, title: "Workflows", icon: "wand.and.stars", selectedIcon: "wand.and.rays.inverse")))
        }
        if settings.isProToolsActive {
            entries.append(.item(SidebarItem(id: .systemConsole, title: "Console", icon: "terminal")))
        }

        #if DEBUG
        if DesignModeManager.shared.isEnabled {
            entries.append(.section(id: "design", title: "Design"))
            entries.append(.item(SidebarItem(id: .designHome, title: "Design Home", icon: "paintbrush", selectedIcon: "paintbrush.fill")))
            entries.append(.item(SidebarItem(id: .designAudit, title: "Audit", icon: "checkmark.seal", selectedIcon: "checkmark.seal.fill")))
            entries.append(.item(SidebarItem(id: .designComponents, title: "Components", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill")))
        }
        #endif

        return entries
    }

    private var talkieLogo: some View {
        Image(nsImage: Self.crispAppIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: SidebarLayout.logoSize, height: SidebarLayout.logoSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            #if DEBUG
            .measureFrame(name: "logo")
            #endif
    }

    // Wordmark defaults — tuned via Design God Mode
    private static let wordmarkSize: CGFloat = 18
    private static let wordmarkWeight: Font.Weight = .semibold
    private static let wordmarkTracking: CGFloat = 1.3
    private static let wordmarkGap: CGFloat = -6
    private static let wordmarkOffsetY: CGFloat = 0

    /// Wordmark wrapped in a 44pt ZStack whose first-text-baseline is
    /// pinned to `ScopeTopBandLayout.baselineFromTop` (30pt from top of
    /// band). The donor sidebar handles compact/expanded by collapsing
    /// the label column width to 0, so no opacity/blur is needed here —
    /// just the baseline anchor so the bottom of TALKIE lines up with
    /// every page title's bottom regardless of font metrics.
    private var baselineAnchoredWordmark: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: PageLayout.headerHeight)

            wordmarkText
                .alignmentGuide(.top) { dim in
                    dim[.firstTextBaseline] - ScopeTopBandLayout.baselineFromTop
                }
        }
        .frame(height: PageLayout.headerHeight, alignment: .topLeading)
    }

    private var wordmarkText: some View {
        #if DEBUG
        let dm = DesignModeManager.shared
        let useDesignTuning = dm.isEnabled

        let size = useDesignTuning ? dm.wordmarkFontSize : Self.wordmarkSize
        let weight = useDesignTuning ? dm.wordmarkWeight : Self.wordmarkWeight
        let tracking = useDesignTuning ? dm.wordmarkTracking : Self.wordmarkTracking
        let offsetY = useDesignTuning ? dm.wordmarkOffsetY : Self.wordmarkOffsetY
        let gap = useDesignTuning ? dm.wordmarkGap : Self.wordmarkGap
        let design: Font.Design = (useDesignTuning ? dm.wordmarkMonospaced : true) ? .monospaced : .default

        let font: Font = {
            var f = Font.system(size: size, weight: weight, design: design)
            if useDesignTuning && dm.wordmarkSmallCaps {
                f = f.smallCaps()
            }
            return f
        }()

        return Text("TALKIE")
            .font(font)
            .tracking(tracking)
            .foregroundColor(Theme.current.foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: offsetY)
            .padding(.leading, gap)
        #else
        Text("TALKIE")
            .font(Font.system(size: Self.wordmarkSize, weight: Self.wordmarkWeight, design: .monospaced))
            .tracking(Self.wordmarkTracking)
            .foregroundColor(Theme.current.foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: Self.wordmarkOffsetY)
            .padding(.leading, Self.wordmarkGap)
        #endif
    }

    // MARK: - Content (Middle Column)

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .workflows:
            if SettingsManager.shared.isScopeTheme {
                ScopeWorkflowListColumn(
                    selectedWorkflowID: $selectedWorkflowID,
                    editingWorkflow: $editingWorkflow,
                    columnVisibility: $columnVisibility
                )
            } else {
                WorkflowListColumn(
                    selectedWorkflowID: $selectedWorkflowID,
                    editingWorkflow: $editingWorkflow
                )
            }
        case .contextRules:
            EmptyView()
        case .settings:
            SettingsSidebarColumn(selectedSection: $selectedSettingsSection)
        default:
            Text("Content Column")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surface1)
        }
    }

    // MARK: - Detail (Main Content)

    @ViewBuilder
    private var mainContentView: some View {
        Group {
            switch selectedSection {
                // Two-column sections
                case .home:
                    HomeScreen()
                case .drafts:
                    if SettingsManager.shared.isScopeTheme {
                        ScopeDraftsScreen()
                    } else {
                        DraftsScreen()
                    }
                case .notes:
                    if SettingsManager.shared.isScopeTheme {
                        // Scope ships Notes as its own surface — a two-
                        // column Sheaf of editorial cards on cream paper.
                        // See design/studio/app/mac-notes (Variant II).
                        ScopeNotesScreen()
                    } else {
                        RecordingsScreen(initialTypeFilter: RecordingTypeFilter.notes)
                    }
                case .models:
                    ModelsContentView()
                case .allowedCommands:
                    AllowedCommandsView()
                        .wrapInTalkieSection("AllowedCommands")
                case .aiResults:
                    ActionWorkbenchView()
                        .wrapInTalkieSection("Actions", showHeader: false)
                case .allMemos:
                    if SettingsManager.shared.isScopeTheme {
                        ScopeLibraryView(initialTypeFilter: .memos)
                    } else {
                        RecordingsScreen()
                    }
                case .recordings:
                    if SettingsManager.shared.isScopeTheme {
                        ScopeLibraryView()
                    } else {
                        RecordingsScreen()
                    }
                case .liveDashboard:
                    if SettingsManager.shared.isScopeTheme {
                        // Scope theme renders Learn — the agent-powered
                        // discovery interstitial — in place of the
                        // data-listing Stats page. Scope owns its own
                        // top band via ScopeTopBand; no wrapInTalkieSection
                        // here. ScopeStatsScreen kept in source but no
                        // longer mounted on this branch.
                        ScopeLearnScreen(
                            onNavigate: navigateFromLearn,
                            onOpenSettings: openSettingsFromLearn
                        )
                    } else {
                        StatsScreen(
                            onSelectDictation: { _ in selectedSection = .dictations }
                        )
                        .wrapInTalkieSection("Stats")
                    }
                case .dictations:
                    if SettingsManager.shared.isScopeTheme {
                        ScopeLibraryView(initialTypeFilter: .dictations)
                    } else {
                        // RecordingsScreen already shows TalkieSection("Library"). Omit the outer
                        // "Dictations" header so we don't stack two chrome rows.
                        RecordingsScreen()
                            .wrapInTalkieSection("Dictations", showHeader: false)
                    }
                case .systemConsole:
                    if SettingsManager.shared.isScopeTheme {
                        // Scope console: rail owns the top-left identity
                        // (PhosphorDot + CONSOLE eyebrow), so we drop the
                        // universal header bar so the rail can bleed to the top.
                        ConsoleScreen()
                    } else {
                        ConsoleScreen()
                            .wrapInTalkieSection("Console")
                    }
                case .screenshots:
                    // Markup renders its own mono instrument header in
                    // the grid pane; suppress the universal title to avoid a
                    // duplicate header row.
                    ScreenshotsScreen()
                        .wrapInTalkieSection("Markup", showHeader: false)
                case .pendingActions:
                    PendingActionsScreen()
                        .wrapInTalkieSection("PendingActions")
                case .recentlyDeleted:
                    RecentlyDeletedView()
                        .wrapInTalkieSection("RecentlyDeleted", showHeader: false)

                // Three-column sections
                case .settings:
                    SettingsContentColumn(selectedSection: $selectedSettingsSection)

                // Debug sections
                #if DEBUG
                case .designHome:
                    DesignHomeView()
                        .wrapInTalkieSection("DesignHome")
                case .designAudit:
                    DesignAuditView()
                        .wrapInTalkieSection("DesignAudit")
                case .designComponents:
                    DesignComponentsView()
                        .wrapInTalkieSection("DesignComponents")
                #endif

                // Three-column sections
                case .contextRules:
                    ContextSettingsView(presentation: .consumer)
                        .wrapInTalkieSection("Context", showHeader: false)

                case .workflows:
                    WorkflowDetailColumn(
                        editingWorkflow: $editingWorkflow,
                        selectedWorkflowID: $selectedWorkflowID
                    )
                    .wrapInTalkieSection("Workflows", showHeader: false)

                default:
                    Text("Select an item")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.current.surface1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        .background(
            NavigationShellTimingProbe(sectionName: selectedSection.map(sectionName(for:)) ?? "?")
        )
        #endif
    }
}

#if DEBUG
private struct NavigationShellTimingProbe: View {
    let sectionName: String

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .task(id: sectionName) {
                await Task.yield()
                await MainActor.run {
                    FrameRateMonitor.shared.markNavigationShellVisible(
                        section: sectionName,
                        source: "mainContent"
                    )
                }
            }
    }
}
#endif

// MARK: - View Extensions

extension View {
    func wrapInTalkieSection(_ name: String, showHeader: Bool = true) -> some View {
        TalkieSection(name, showUniversalHeader: showHeader) {
            self
        }
    }
}

// MARK: - Notification Observers

extension View {
    func setupNotificationObservers(
        selectedSection: Binding<NavigationSection?>,
        previousSection: Binding<NavigationSection?>,
        settingsSection: Binding<SettingsSection>,
        memoCount: Int
    ) -> some View {
        self
            .navigationObservers(selectedSection: selectedSection, settingsSection: settingsSection)
            .itemNavigationObservers(selectedSection: selectedSection)
            .alertObservers()
    }

    // MARK: - Navigation Observers (Group 1)

    private func navigationObservers(
        selectedSection: Binding<NavigationSection?>,
        settingsSection: Binding<SettingsSection>
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .init("browseWorkflows"))) { _ in
                selectedSection.wrappedValue = .workflows
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToWorkflows"))) { _ in
                selectedSection.wrappedValue = .workflows
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateAgent)) { _ in
                selectedSection.wrappedValue = .liveDashboard
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateLive)) { _ in
                selectedSection.wrappedValue = .liveDashboard
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToDictations"))) { _ in
                selectedSection.wrappedValue = .dictations
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { notification in
                selectedSection.wrappedValue = .settings
                if let sectionName = notification.object as? String {
                    switch sectionName {
                    case "context": settingsSection.wrappedValue = .context
                    case "apiKeys": settingsSection.wrappedValue = .aiProviders
                    case "appearance": settingsSection.wrappedValue = .appearance
                    case "voiceIO", "voice-io": settingsSection.wrappedValue = .voiceIO
                    case "helpers": settingsSection.wrappedValue = .helpers
                    default: break
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToHelpers"))) { _ in
                selectedSection.wrappedValue = .settings
                settingsSection.wrappedValue = .helpers
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
                if let section = notification.object as? NavigationSection {
                    selectedSection.wrappedValue = section
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToAgentSettings)) { _ in
                selectedSection.wrappedValue = .settings
                settingsSection.wrappedValue = .voiceIO
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLiveSettings)) { _ in
                selectedSection.wrappedValue = .settings
                settingsSection.wrappedValue = .voiceIO
            }
    }

    // MARK: - Item Navigation Observers (Group 2)

    private func itemNavigationObservers(
        selectedSection: Binding<NavigationSection?>
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToAllMemos"))) { _ in
                selectedSection.wrappedValue = .allMemos
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToMemo"))) { notification in
                selectedSection.wrappedValue = .allMemos
                if let memoID = notification.object as? UUID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .init("SelectMemo"), object: memoID)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToDictation"))) { notification in
                selectedSection.wrappedValue = .dictations
                if let dictationID = notification.object as? UUID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .init("SelectDictation"), object: dictationID)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToDictationsPending"))) { _ in
                selectedSection.wrappedValue = .dictations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .init("FilterDictationsPending"), object: nil)
                }
            }
    }

    // MARK: - Alert Observers (Group 3)

    func alertObservers() -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .showMicrophonePermissionRequired)) { _ in
                let alert = NSAlert()
                alert.messageText = "Microphone Access Required"
                alert.informativeText = "Talkie needs microphone access to record audio. Please enable it in System Settings."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    PermissionsManager.shared.openMicrophoneSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showEngineRequiredToast)) { _ in
                let alert = NSAlert()
                alert.messageText = "Talkie Agent Required"
                alert.informativeText = "TalkieAgent hosts the embedded transcription engine. Would you like to launch it now?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Launch Agent")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    ServiceManager.shared.launchEngine()
                }
            }
    }
}

// MARK: - View Modifiers for Body Decomposition

/// App-wide drop zone modifier
struct AudioDropModifier<DropOverlay: View>: ViewModifier {
    @Binding var isDropTargeted: Bool
    let dropProgress: AudioDropService.DropProgress?
    let dropError: String?
    @ViewBuilder let audioDropOverlay: () -> DropOverlay
    let handleAudioDrop: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        content
            .onDrop(of: AudioDropService.supportedUTTypes, delegate: AppWideDropDelegate(
                isDropTargeted: $isDropTargeted,
                handleAudioDrop: handleAudioDrop
            ))
            .overlay {
                if isDropTargeted || dropProgress != nil || dropError != nil {
                    audioDropOverlay()
                }
            }
    }
}

private struct AppWideDropDelegate: DropDelegate {
    @Binding var isDropTargeted: Bool
    let handleAudioDrop: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        shouldAcceptDrop(info)
    }

    func dropEntered(info: DropInfo) {
        isDropTargeted = shouldAcceptDrop(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let shouldAccept = shouldAcceptDrop(info)
        isDropTargeted = shouldAccept
        return DropProposal(operation: shouldAccept ? .copy : .cancel)
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        guard let itemProviders = acceptableProviders(from: info) else {
            return true
        }
        return handleAudioDrop(itemProviders)
    }

    private func shouldAcceptDrop(_ info: DropInfo) -> Bool {
        guard let itemProviders = acceptableProviders(from: info) else {
            return false
        }
        return AudioDropService.shouldAcceptDrop(providers: itemProviders)
    }

    private func acceptableProviders(from info: DropInfo) -> [NSItemProvider]? {
        let itemProviders = providers(from: info)
        guard !itemProviders.isEmpty else { return nil }
        guard !TalkieInternalDrag.isInternal(itemProviders) else { return nil }
        return itemProviders
    }

    private func providers(from info: DropInfo) -> [NSItemProvider] {
        info.itemProviders(for: AudioDropService.supportedUTTypes + [TalkieInternalDrag.utType])
    }
}

/// Sidebar toggle in the window title bar, shown only while the
/// sidebar is collapsed. Lives in the standard macOS toolbar leading
/// slot — no floating chip overlay. When the sidebar is open the
/// wordmark itself is the toggle, so the title-bar button hides.
struct SidebarButtonOverlayModifier: ViewModifier {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    func body(content: Content) -> some View {
        content
            .toolbar {
                if columnVisibility == .detailOnly {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                columnVisibility = .all
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Show sidebar")
                    }
                }
            }
    }
}

private struct MouseBackNavigationModifier: ViewModifier {
    private static let backButtonNumber = 3

    let navigateBack: () -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                installMonitorIfNeeded()
            }
            .onDisappear {
                removeMonitor()
            }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == Self.backButtonNumber else {
                return event
            }

            return navigateBack() ? nil : event
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

/// Debug overlays (only in DEBUG builds)
struct DebugOverlaysModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content
            .coordinateSpace(name: "designGuides")
            .overlay(alignment: .bottomTrailing) {
                // Debug toolbar only visible when Design Mode is active (⌘⇧D)
                if DesignModeManager.shared.isEnabled {
                    TalkieDebugToolbar {
                        ListViewDebugContent()
                    }
                    .padding(.trailing, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                }
            }
            // FPS readout moved off this floating bottomLeading overlay
            // (it overlapped content like the capture-markup speak strip)
            // and into the status bar's dev cluster — see PerfStatusReadout
            // in StatusBar.swift. CVDisplayLink monitor is started there.
            .overlay {
                DesignToolsOverlay()
            }
            .animation(.easeInOut(duration: 0.15), value: DesignModeManager.shared.isEnabled)
        #else
        content
        #endif
    }
}

#if DEBUG
// MARK: - Design Guide Frame Measurement

/// Preference key for collecting named element frames for design guides
struct DesignGuideFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Measure this view's frame in the "designGuides" coordinate space and report it
    func measureFrame(name: String) -> some View {
        self.background(GeometryReader { geo in
            Color.clear.preference(
                key: DesignGuideFrameKey.self,
                value: [name: geo.frame(in: .named("designGuides"))]
            )
        })
    }
}
#endif

/// Navigation state change handlers
struct NavigationChangeHandlersModifier: ViewModifier {
    @Binding var selectedSection: NavigationSection?
    @Binding var previousSection: NavigationSection?
    @Binding var selectedSettingsSection: SettingsSection
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let nav: NavigationState
    let memosVM: MemosViewModel
    let sectionName: (NavigationSection) -> String
    let usesTwoColumns: Bool

    func body(content: Content) -> some View {
        content
            // Nav state → local state (programmatic navigation)
            .onChange(of: nav.selectedSection) { _, newSection in
                if let section = newSection, section != selectedSection {
                    #if DEBUG
                    FrameRateMonitor.shared.beginNavigation(to: sectionName(section), source: "navigation-state")
                    #endif
                    previousSection = selectedSection
                    selectedSection = section
                    // Ensure 3-column sections show all columns
                    if !usesTwoColumns {
                        columnVisibility = .all
                    }
                }
            }
            .onChange(of: nav.settingsSection) { _, newSection in
                if newSection != selectedSettingsSection {
                    selectedSettingsSection = newSection
                }
            }
            // Local state → nav state (sidebar clicks)
            .onChange(of: selectedSection) { previous, newSection in
                #if DEBUG
                if let newSection {
                    FrameRateMonitor.shared.beginNavigation(to: sectionName(newSection), source: "selection-state")
                }
                #endif
                if newSection != nav.selectedSection {
                    if let newSection {
                        nav.navigateFromUI(to: newSection)
                    } else {
                        nav.selectedSection = nil
                    }
                }
                // Scope-only: Console is terminal-first. Collapse the outer
                // app sidebar so the rail + tab content fill the canvas;
                // SidebarButtonOverlayModifier leaves a small "show sidebar"
                // affordance in the top-left as the hint.
                guard SettingsManager.shared.isScopeTheme else { return }
                if newSection == .systemConsole {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        columnVisibility = .detailOnly
                    }
                } else if previous == .systemConsole {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        columnVisibility = .all
                    }
                }
            }
            .onChange(of: selectedSettingsSection) { _, newSection in
                if newSection != nav.settingsSection {
                    nav.settingsSection = newSection
                }
            }
    }
}

// MARK: - Sidebar Tooltip Overlay

// `SidebarTooltipState` now lives in TalkieKit (alongside the shared Sidebar
// primitives that drive it). The overlay below stays here — it's app chrome.

/// Window-level tooltip — rendered above the sidebar column so it's never clipped.
/// Row anchors are in .global coordinate space. The overlay converts to local.
// `SidebarTooltipOverlay` + `SidebarTooltipArrow` now live in TalkieKit
// (alongside the shared Sidebar + SidebarTooltipState), color-parameterized so
// both Talkie and TalkieAgent render the same component. Mounted above at
// `sidebarView`'s overlay with `Theme` colors.

// MARK: - Toolbar Background Visibility (macOS 15+)

/// Applies toolbarBackgroundVisibility only on macOS 15+
struct ToolbarBackgroundVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackgroundVisibility(
                    TechnicalStyle.isActive ? .visible : .automatic,
                    for: .windowToolbar
                )
        } else {
            content
        }
    }
}

// MARK: - Global Action Bar

/// Centered top bar with three elements: dictate (left), record (center), create (right).
/// Always visible. Record button expands to show elapsed time during recording.
/// Designed to feel native to the midnight aesthetic — no material blur, just surface + border.
private struct GlobalActionBar: View {
    @Environment(\.navigationState) private var nav

    private let controller = MemoRecordingController.shared
    private let screenRecorder = ScreenRecordingController.shared
    @State private var dictateHovered = false
    @State private var createHovered = false

    private var isPreparing: Bool { controller.state.isPreparing }
    private var isRecording: Bool { controller.state.isRecording }
    private var isProcessing: Bool { controller.state.isProcessing }
    private var captureStatusMessage: String? { controller.captureStatusMessage }
    private var isScreenRecording: Bool { screenRecorder.state == .recording }
    private var isScreenSelecting: Bool { screenRecorder.state == .selecting }
    private var isActive: Bool { isPreparing || isRecording || isScreenRecording || isScreenSelecting }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Dictate
            actionButton(
                icon: "waveform",
                isHovered: $dictateHovered,
                help: "Dictations (D)"
            ) {
                nav.navigate(to: .dictations)
            }

            // Center: Record
            recordSection

            // Right: Create menu
            createMenuButton
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(TechnicalStyle.isActive ? TechnicalStyle.surface1 : Color(white: 0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
        .fixedSize(horizontal: true, vertical: true)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
    }

    @State private var recordHovered = false

    // MARK: - Record Section

    private var recordSection: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 5) {
                if isPreparing {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                        Text("Preparing…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity
                    ))
                } else if isScreenRecording {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.dashed.badge.record")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red.opacity(0.95))
                        Text("Screen")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                } else if isScreenSelecting {
                    HStack(spacing: 4) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                        Text("Selecting")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity
                    ))
                } else if isRecording {
                    HStack(spacing: 4) {
                        Text(formatElapsed(controller.elapsedTime))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))

                        if captureStatusMessage != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange.opacity(0.9))
                            Text("Mic reconnecting")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange.opacity(0.85))
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                }

                RecordButtonContent(isRecording: isActive, isHovered: recordHovered)

                if isProcessing && !isRecording && !isPreparing {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Processing")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, isActive || isProcessing ? 8 : 2)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isActive ? Color.red.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { recordHovered = $0 }
        .disabled(isScreenSelecting)
        .help(isScreenRecording ? "Stop screen recording" : (isActive ? "Stop recording (R)" : "Record memo (R)"))
    }

    // MARK: - Action Button

    private func actionButton(
        icon: String,
        isHovered: Binding<Bool>,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(isHovered.wrappedValue ? 0.9 : 0.45))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered.wrappedValue ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered.wrappedValue = $0 }
        .help(help)
    }

    // MARK: - Create Menu

    private var createMenuButton: some View {
        Menu {
            Button {
                nav.navigate(to: .drafts)
            } label: {
                Label("Compose", systemImage: "square.and.pencil")
            }

            Button {
                createNewNote()
            } label: {
                Label("Note", systemImage: "note.text")
            }

            Divider()

            Divider()

            Button {
                nav.navigate(to: .workflows)
            } label: {
                Label("Workflows", systemImage: "wand.and.stars")
            }

            Button {
                nav.navigate(to: .screenshots)
            } label: {
                Label("Markup", systemImage: "pencil.tip.crop.circle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(createHovered ? 0.9 : 0.45))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white.opacity(createHovered ? 0.9 : 0.45))
        .frame(width: 24, height: 24)
        .background(
            Circle()
                .fill(Color.white.opacity(createHovered ? 0.12 : 0))
        )
        .onHover { createHovered = $0 }
        .help("Create new…")
    }

    // MARK: - Actions

    private func toggleRecording() {
        if isScreenRecording {
            Task { @MainActor in
                await screenRecorder.stopRecording()
            }
        } else if isRecording {
            controller.stopRecording()
        } else {
            controller.startRecording()
        }
    }

    private func createNewNote() {
        Task { @MainActor in
            let noteId = UUID()
            let note = TalkieObject.newNote(id: noteId, text: "")
            do {
                let repository = TalkieObjectRepository()
                try await repository.saveRecording(note)
                await RecordingsViewModel.shared.loadRecordings()
                nav.navigate(to: .recordings, params: ["recordingId": noteId.uuidString])
            } catch {
                Log(.ui).error("Failed to create note: \(error)")
            }
        }
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Record button — red circle with morphing icon (dot → square) and pulsing ring.
private struct RecordButtonContent: View {
    let isRecording: Bool
    var isHovered: Bool = false
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Hover ring (idle only)
            if !isRecording && isHovered {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 24, height: 24)
            }

            // Pulsing ring when recording
            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            Circle()
                .fill(isRecording ? Color.red : Color.red.opacity(isHovered ? 1.0 : 0.8))
                .frame(width: 18, height: 18)
                .scaleEffect(isHovered && !isRecording ? 1.12 : 1.0)
                .overlay(
                    Group {
                        if isRecording {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 7, height: 7)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 6, height: 6)
                        }
                    }
                )
                .shadow(color: Color.red.opacity(isRecording ? 0.4 : (isHovered ? 0.35 : 0.15)), radius: isRecording ? 5 : (isHovered ? 4 : 2), y: 0)
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onChange(of: isRecording) { _, recording in
            isPulsing = recording
        }
        .onAppear {
            if isRecording { isPulsing = true }
        }
    }
}

/// Subtle pulsing effect for the recording dot
private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview {
    AppNavigation()
        .frame(width: 1200, height: 800)
}

// MARK: - Backwards Compatibility Alias
typealias TalkieNavigationViewNative = AppNavigation
