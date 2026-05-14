//
//  AppNavigation.swift
//  Talkie macOS
//
//  Main app navigation using native NavigationSplitView
//
//  Sidebar has 3 display states:
//    State 0 — Hidden: NavigationSplitView fully collapsed (native behavior)
//    State 1 — Compact: Icons only (52px), accent bar + fixed-position icons
//    State 2 — Expanded: Icons + labels (200px), wordmark + section headers
//
//  Design principle: Icons stay at the SAME X position between State 1 and State 2.
//  Only the label text area appears/disappears. The Talkie logo fills the accent+icon
//  zone, and the wordmark aligns with section label text.
//
//  We use NavigationSplitView as the container — DO NOT replace it with custom
//  HStack/VStack column management. Sidebar content is custom (List + SidebarRow).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TalkieKit

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

struct AppNavigation: View {
    // GRDB-backed ViewModel for memo data
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    // Singletons - observe remote data
    private let settings = SettingsManager.shared
    private let pendingActionsManager = PendingActionsManager.shared

    // Central navigation state (observable)
    private var nav: NavigationState { NavigationState.shared }

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

    // Column visibility (NavigationSplitView manages this for us)
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Sidebar display mode
    @AppStorage("app.sidebar.iconsOnly") private var appSidebarIconsOnly = false
    @State private var sidebarEdgeHovered = false
    @State private var didPrepareConsoleRegistry = false

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
    }

    private static func resolveInitialSection(_ initialSection: NavigationSection?) -> NavigationSection? {
        let env = ProcessInfo.processInfo.environment

        if env["TALKIE_START_IN_CONSOLE"] == "1" {
            return .systemConsole
        }

        return initialSection
    }

    private func toggleSidebarRenderMode() {
        withAnimation(SidebarMotion.toggleAnimation) {
            appSidebarIconsOnly.toggle()
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func sectionName(for section: NavigationSection) -> String {
        switch section {
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
        case .screenshots: return "Screenshots"
        case .pendingActions: return "PendingActions"
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

    // Sidebar width - fixed to prevent resizing when dragging content column divider
    // Icons-only mode uses narrow fixed width, expanded mode uses standard fixed width
    private static let sidebarWidthExpanded: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (140, 170, 220)
    private static let sidebarWidthCompact: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (48, 48, 48)
    private static let workflowsColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (260, 300, 400)
    private var contentColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if selectedSection == .workflows { return Self.workflowsColumnWidth }
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

    private var sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        sidebarIconsOnly ? Self.sidebarWidthCompact : Self.sidebarWidthExpanded
    }

    private var sidebarIconsOnly: Bool {
        appSidebarIconsOnly
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
        let _ = logBodyAccessIfNeeded()
        mainLayout
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
                SidebarTooltipOverlay()
            }
            .overlay(alignment: .top) {
                GlobalActionBar()
                    .padding(.top, 7)
                    // Offset right by half the sidebar width to center in content area
                    // (moves from screen center to content area center)
                    .offset(x: sidebarWidth.ideal / 2)
            }
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
            .overlay(alignment: .top) {
                // Structural horizontal rule at the header datum (44pt).
                // Decorative line that visually connects columns.
                Rectangle()
                    .fill(Theme.current.foreground.opacity(0.06))
                    .frame(height: 0.5)
                    .offset(y: PageLayout.headerHeight)
                    .allowsHitTesting(false)
            }
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
            .modifier(SidebarButtonOverlayModifier(columnVisibility: $columnVisibility))
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
            .alertObservers()
            .onAppear {
                StartupProfiler.shared.mark("nav.onAppear")
                if !didPrepareConsoleRegistry {
                    didPrepareConsoleRegistry = true
                    TabDefinitionRegistry.shared.prepareForAppLaunch()
                }
            }
    }

    @ViewBuilder
    private var navigationSplitViewCore: some View {
        if usesTwoColumns || (isNarrowForThreeColumns && !usesTwoColumns) {
            // 2-column layout: either for 2-column sections, or narrow 3-column sections
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarView
                    .navigationSplitViewColumnWidth(
                        min: sidebarWidth.min,
                        ideal: sidebarWidth.ideal,
                        max: sidebarWidth.max
                    )
            } detail: {
                if isNarrowForThreeColumns && !usesTwoColumns {
                    // Show content with navigation button for Settings/Workflows
                    narrowThreeColumnContent
                } else {
                    mainContentView
                }
            }
        } else {
            // Full 3-column layout
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarView
                    .navigationSplitViewColumnWidth(
                        min: sidebarWidth.min,
                        ideal: sidebarWidth.ideal,
                        max: sidebarWidth.max
                    )
            } content: {
                contentView
                    .navigationSplitViewColumnWidth(
                        min: contentColumnWidth.min,
                        ideal: contentColumnWidth.ideal,
                        max: contentColumnWidth.max
                    )
            } detail: {
                mainContentView
            }
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
             .recordings, .liveDashboard, .dictations, .systemConsole, .pendingActions, .contextRules, .screenshots:
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
        dropTask = Task {
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
                    NavigationState.shared.navigate(
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
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

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
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        sidebarList
            .overlay(alignment: .trailing) {
                // Hover-reveal toggle tab at the sidebar edge
                sidebarEdgeToggle
            }
    }

    @State private var edgeHandleHovered = false

    private var sidebarEdgeToggle: some View {
        // Subtle edge handle — thin pill that reveals on hover
        Button {
            toggleSidebarRenderMode()
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.current.foreground.opacity(edgeHandleHovered ? 0.2 : 0.06))
                .frame(width: 4, height: 28)
                .contentShape(Rectangle().inset(by: -6)) // Larger hit target
        }
        .buttonStyle(.plain)
        .help(sidebarIconsOnly ? "Expand sidebar" : "Collapse sidebar")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                edgeHandleHovered = hovering
            }
        }
        .offset(x: 4)
    }

    private var sidebarList: some View {
        List(selection: $selectedSection) {
            // General section
            Section {
                SidebarRow(section: .home, selectedSection: $selectedSection, title: "Home", icon: "house", iconsOnly: sidebarIconsOnly)
                SidebarRow(section: .recordings, selectedSection: $selectedSection, title: "Library", icon: "rectangle.stack", iconsOnly: sidebarIconsOnly)

                // Legacy screens (hidden by default, enable via DebugToolbar)
                #if DEBUG
                if showLegacyScreens {
                    SidebarRow(section: .allMemos, selectedSection: $selectedSection, title: "Memos", icon: "square.stack", iconsOnly: sidebarIconsOnly)
                    SidebarRow(section: .dictations, selectedSection: $selectedSection, title: "Dictations", icon: "waveform.badge.mic", iconsOnly: sidebarIconsOnly)
                }
                #endif
                SidebarRow(section: .notes, selectedSection: $selectedSection, title: "Notes", icon: "note.text", iconsOnly: sidebarIconsOnly)

                // Advanced features — unlock after 7 transcriptions or manual override
                if settings.hasUnlockedAdvancedFeatures {
                    SidebarRow(section: .drafts, selectedSection: $selectedSection, title: "Compose", icon: "square.and.pencil", iconsOnly: sidebarIconsOnly)
                    SidebarRow(section: .contextRules, selectedSection: $selectedSection, title: "Context", icon: "square.stack.3d.forward.dottedline", iconsOnly: sidebarIconsOnly)
                }
            }

            // Activity — only visible when there's something to show
            if pendingActionsManager.hasActiveActions || pendingActionsManager.recentActions.count > 0 {
                Section {
                    SidebarRow(section: .aiResults, selectedSection: $selectedSection, title: "Actions", icon: "chart.line.uptrend.xyaxis", iconsOnly: sidebarIconsOnly)

                    // Only show Pending when there are active actions
                    if pendingActionsManager.hasActiveActions {
                        SidebarRow(section: .pendingActions, selectedSection: $selectedSection, title: "Pending", icon: "clock.arrow.circlepath", iconsOnly: sidebarIconsOnly)
                    }
                } header: {
                    sidebarSectionHeader("Activity")
                }
            }

            // Tools
            Section {
                SidebarRow(section: .liveDashboard, selectedSection: $selectedSection, title: "Stats", icon: "waveform.path.ecg", iconsOnly: sidebarIconsOnly)

                SidebarRow(section: .models, selectedSection: $selectedSection, title: "Models", icon: "brain", iconsOnly: sidebarIconsOnly)

                if settings.hasUnlockedAdvancedFeatures {
                    SidebarRow(section: .workflows, selectedSection: $selectedSection, title: "Workflows", icon: "wand.and.stars", iconsOnly: sidebarIconsOnly)
                    SidebarRow(section: .screenshots, selectedSection: $selectedSection, title: "Screenshots", icon: "camera.viewfinder", iconsOnly: sidebarIconsOnly)
                }
                if settings.isProToolsActive {
                    SidebarRow(section: .systemConsole, selectedSection: $selectedSection, title: "Console", icon: "terminal", iconsOnly: sidebarIconsOnly)
                }
            } header: {
                sidebarSectionHeader("Tools")
            }

            #if DEBUG
            if DesignModeManager.shared.isEnabled {
                Section {
                    SidebarRow(section: .designHome, selectedSection: $selectedSection, title: "Design Home", icon: "paintbrush", iconsOnly: sidebarIconsOnly)

                    SidebarRow(section: .designAudit, selectedSection: $selectedSection, title: "Audit", icon: "checkmark.seal", iconsOnly: sidebarIconsOnly)

                    SidebarRow(section: .designComponents, selectedSection: $selectedSection, title: "Components", icon: "square.grid.2x2", iconsOnly: sidebarIconsOnly)
                } header: {
                    sidebarSectionHeader("Design")
                }
            }
            #endif
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .safeAreaInset(edge: .top) {
            generalSectionHeader
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.current.foreground.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.bottom, 12)

                SidebarFooterRow(
                    section: .settings,
                    selectedSection: $selectedSection,
                    title: "Settings",
                    icon: "gear",
                    iconsOnly: sidebarIconsOnly
                )
                .frame(height: 36)
            }
        }
    }

    @ViewBuilder
    private var generalSectionHeader: some View {
        // Outside the List (safeAreaInset) — full control over position.
        // Logo center-X = compactWidth / 2 in both modes → zero movement on toggle.
        Button {
            toggleSidebarRenderMode()
        } label: {
            HStack(spacing: 0) {
                talkieLogo
                    .frame(width: Self.sidebarWidthCompact.ideal, alignment: .center)

                wordmarkText
                    .opacity(sidebarIconsOnly ? 0 : 1)
                    .offset(x: sidebarIconsOnly ? SidebarMotion.hiddenLabelOffset : 0)
                    .blur(radius: sidebarIconsOnly ? SidebarMotion.hiddenLabelBlur : 0)
                    .scaleEffect(sidebarIconsOnly ? 0.985 : 1, anchor: .leading)
                    .accessibilityHidden(sidebarIconsOnly)

                Spacer(minLength: 0)
            }
            .frame(height: PageLayout.headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sidebarIconsOnly ? "Expand sidebar" : "Collapse sidebar")
        .animation(SidebarMotion.toggleAnimation, value: sidebarIconsOnly)
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
            .offset(y: offsetY)
            .padding(.leading, gap)
        #else
        Text("TALKIE")
            .font(Font.system(size: Self.wordmarkSize, weight: Self.wordmarkWeight, design: .monospaced))
            .tracking(Self.wordmarkTracking)
            .foregroundColor(Theme.current.foreground)
            .offset(y: Self.wordmarkOffsetY)
            .padding(.leading, Self.wordmarkGap)
        #endif
    }

    @ViewBuilder
    private func sidebarSectionHeader(_ baseTitle: String) -> some View {
        // Single hierarchy — text slides out, height stays consistent
        // Leading offset: 2pt icon padding + 20pt icon frame + 8pt gap = 30pt from row edge
        HStack(spacing: 0) {
            Text(settings.uiAllCaps ? baseTitle.uppercased() : baseTitle)
                .font(Theme.current.fontXSBold)
                .tracking(TechnicalStyle.isActive ? 0.4 : 0.8)
                .foregroundColor(Theme.current.foregroundMuted)
                .textCase(nil)
                .padding(.leading, 2 + SidebarLayout.iconFrameWidth + SidebarLayout.iconToLabelGap)
                .opacity(sidebarIconsOnly ? 0 : 1)
                .offset(x: sidebarIconsOnly ? SidebarMotion.hiddenLabelOffset : 0)
                .blur(radius: sidebarIconsOnly ? SidebarMotion.hiddenLabelBlur : 0)
                .scaleEffect(sidebarIconsOnly ? 0.985 : 1, anchor: .leading)
                .accessibilityHidden(sidebarIconsOnly)
        }
        .frame(height: SidebarLayout.sectionGapCompact)
        .clipped()
        .animation(SidebarMotion.toggleAnimation, value: sidebarIconsOnly)
    }

    // MARK: - Content (Middle Column)

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .workflows:
            if SettingsManager.shared.isScopeTheme {
                ScopeWorkflowListColumn(
                    selectedWorkflowID: $selectedWorkflowID,
                    editingWorkflow: $editingWorkflow
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
                    RecordingsScreen(initialTypeFilter: RecordingTypeFilter.notes)
                case .models:
                    ModelsContentView()
                        .wrapInTalkieSection("Models")
                case .allowedCommands:
                    AllowedCommandsView()
                        .wrapInTalkieSection("AllowedCommands")
                case .aiResults:
                    ActivityLogFullView()
                        .wrapInTalkieSection("AIResults")
                case .allMemos:
                    RecordingsScreen()
                case .recordings:
                    RecordingsScreen()
                case .liveDashboard:
                    StatsScreen(
                        onSelectDictation: { _ in selectedSection = .dictations }
                    )
                    .wrapInTalkieSection("Stats")
                case .dictations:
                    // RecordingsScreen already shows TalkieSection("Library"). Omit the outer
                    // "Dictations" header so we don't stack two chrome rows.
                    RecordingsScreen()
                        .wrapInTalkieSection("Dictations", showHeader: false)
                case .systemConsole:
                    ConsoleScreen()
                        .wrapInTalkieSection("Console")
                case .screenshots:
                    ScreenshotsScreen()
                        .wrapInTalkieSection("Screenshots")
                case .pendingActions:
                    PendingActionsScreen()
                        .wrapInTalkieSection("PendingActions")

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
    }
}


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
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
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
        AudioDropService.shouldAcceptDrop(providers: providers(from: info))
    }

    func dropEntered(info: DropInfo) {
        isDropTargeted = AudioDropService.shouldAcceptDrop(providers: providers(from: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let shouldAccept = AudioDropService.shouldAcceptDrop(providers: providers(from: info))
        isDropTargeted = shouldAccept
        return DropProposal(operation: shouldAccept ? .copy : .cancel)
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        let itemProviders = providers(from: info)
        guard AudioDropService.shouldAcceptDrop(providers: itemProviders) else {
            return true
        }
        return handleAudioDrop(itemProviders)
    }

    private func providers(from info: DropInfo) -> [NSItemProvider] {
        info.itemProviders(for: AudioDropService.supportedUTTypes)
    }
}

/// Sidebar toggle button overlay when sidebar is hidden
struct SidebarButtonOverlayModifier: ViewModifier {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if columnVisibility == .detailOnly {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility = .all
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(8)
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
                    .help("Show sidebar")
                    .padding(.top, 8)
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
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
            .onChange(of: selectedSection) { _, newSection in
                if newSection != nav.selectedSection {
                    nav.selectedSection = newSection
                }
            }
            .onChange(of: selectedSettingsSection) { _, newSection in
                if newSection != nav.settingsSection {
                    nav.settingsSection = newSection
                }
            }
    }
}

// MARK: - Sidebar Layout Constants

// MARK: - Sidebar Tooltip State

/// Window-level tooltip state so the tooltip renders above the sidebar column boundary.
@MainActor
@Observable
final class SidebarTooltipState {
    static let shared = SidebarTooltipState()
    var label: String?
    var anchor: CGPoint = .zero // In "mainLayout" coordinate space
    private var dismissTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private init() {}

    func show(label: String, anchor: CGPoint) {
        dismissTask?.cancel()
        autoDismissTask?.cancel()
        self.label = label
        self.anchor = anchor
        // Safety net: auto-dismiss after 4s in case onHover exit is missed
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.label == label {
                self.label = nil
            }
        }
    }

    func updateAnchor(_ anchor: CGPoint) {
        self.anchor = anchor
    }

    func dismiss(matching label: String) {
        // Delay dismissal so the tooltip doesn't flicker between adjacent items
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if self.label == label {
                self.label = nil
            }
        }
    }
}

/// Window-level tooltip — rendered above the sidebar column so it's never clipped.
/// Row anchors are in .global coordinate space. The overlay converts to local.
struct SidebarTooltipOverlay: View {
    private var tooltip: SidebarTooltipState { SidebarTooltipState.shared }
    /// Measured height of the tooltip pill for vertical centering
    @State private var tooltipHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            if let label = tooltip.label {
                // Convert global anchor to overlay-local coordinates
                let overlayOrigin = geo.frame(in: .global).origin
                let localX = tooltip.anchor.x - overlayOrigin.x
                let localY = tooltip.anchor.y - overlayOrigin.y

                HStack(spacing: 0) {
                    SidebarTooltipArrow()
                        .fill(Theme.current.surfaceBase)
                        .frame(width: 6, height: 10)

                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.current.surfaceBase)
                                .shadow(color: .black.opacity(0.5), radius: 8, x: 3, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.current.foreground.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .fixedSize()
                .background {
                    GeometryReader { tipGeo in
                        Color.clear.onAppear { tooltipHeight = tipGeo.size.height }
                    }
                }
                // Place tooltip: left edge at row's right edge, vertically centered on row
                .offset(x: localX, y: localY - tooltipHeight / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.08), value: label)
            }
        }
    }
}

/// Shared layout constants for sidebar icon/label alignment.
/// All values derive from the 8pt grid (Spacing system).
///
/// Expanded: left accent bar (3pt) + gap + icon + gap + label
/// Compact:  centered icon + bottom accent bar (2pt)
enum SidebarLayout {
    // ── Accent Indicator ──
    static let accentBarWidth: CGFloat = 3          // Left bar width (expanded)
    static let accentBarHeight: CGFloat = Spacing.xxs  // 2pt — bottom bar height (compact)
    static let accentBarLength: CGFloat = iconFrameWidth // Bottom bar matches icon width

    // ── Gaps ──
    static let accentToIconGap: CGFloat = Spacing.xs    // 4pt (expanded, between bar and icon)
    static let iconToLabelGap: CGFloat = Spacing.sm     // 8pt (between icon and label text)
    static let accentToIconVerticalGap: CGFloat = Spacing.xxs  // 2pt (compact, icon to bottom bar)

    // ── Icon ──
    static let iconFrameWidth: CGFloat = 20
    static let iconSize: CGFloat = 15               // SF Symbol point size

    // ── Icon Zone (expanded) ──
    /// Total width: accent(3) + gap(4) + icon(20) = 27pt
    static let iconZoneWidth: CGFloat = accentBarWidth + accentToIconGap + iconFrameWidth

    // ── Header ──
    static let headerTopPadding: CGFloat = Spacing.md   // 12pt — breathing room from window chrome
    static let headerBottomPadding: CGFloat = Spacing.sm // 8pt — separation before first nav item
    static let logoSize: CGFloat = 24

    // ── Sidebar Width ──
    static let compactWidth: CGFloat = 48

    // ── Section Groups ──
    static let sectionGapCompact: CGFloat = Spacing.sm   // 8pt — breathing room between icon groups
}

private enum SidebarMotion {
    static let toggleAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86, blendDuration: 0.1)
    static let hiddenLabelOffset: CGFloat = -10
    static let hiddenLabelBlur: CGFloat = 3
}

// MARK: - Sidebar Row with Selection Indicator

/// Custom sidebar row with mode-aware selection indicator:
/// - Expanded: vertical accent bar on the left edge
/// - Compact: horizontal accent bar below the centered icon
struct SidebarRow<Content: View>: View {
    let section: NavigationSection
    @Binding var selectedSection: NavigationSection?
    var iconsOnly: Bool = false
    var tooltipLabel: String? = nil
    @ViewBuilder let content: (_ isSelected: Bool) -> Content

    @State private var isHovering = false
    @State private var rowFrame: CGRect = .zero

    private var isSelected: Bool {
        selectedSection == section
    }

    private var accentColor: Color {
        SettingsManager.shared.accentColor.color ?? Color.accentColor
    }

    var body: some View {
        NavigationLink(value: section) {
            VStack(spacing: SidebarLayout.accentToIconVerticalGap) {
                content(isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom accent bar — only in compact
                RoundedRectangle(cornerRadius: 1)
                    .fill(iconsOnly && isSelected ? accentColor : Color.clear)
                    .frame(width: SidebarLayout.accentBarLength, height: iconsOnly ? SidebarLayout.accentBarHeight : 0)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 0, trailing: -4))
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrame = newFrame
                    }
            }
        }
        .onContinuousHover { phase in
            guard iconsOnly, let label = tooltipLabel else { return }
            let tooltip = SidebarTooltipState.shared
            switch phase {
            case .active:
                isHovering = true
                // Use row geometry for X (right edge), row midY for vertical center
                let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                if tooltip.label == label {
                    tooltip.updateAnchor(anchor)
                } else {
                    tooltip.show(label: label, anchor: anchor)
                }
            case .ended:
                isHovering = false
                tooltip.dismiss(matching: label)
            }
        }
    }
}

/// Sidebar label — icon always at the same X position in both modes.
/// In expanded mode, label text appears to the right.
/// In compact mode, a hover tooltip shows the label.
struct SidebarLabel: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var iconsOnly: Bool = false

    private var selectedIcon: String {
        if icon.hasSuffix(".fill") { return icon }

        let fillableMappings: [String: String] = [
            // Core navigation
            "house": "house.fill",
            "square.and.pencil": "square.and.pencil.circle.fill",
            "note.text": "doc.text.fill",
            "doc.text": "doc.text.fill",
            "square.stack": "square.stack.fill",
            "gear": "gearshape.fill",
            "brain": "brain.fill",
            "paintbrush": "paintbrush.fill",
            "checkmark.seal": "checkmark.seal.fill",
            "square.grid.2x2": "square.grid.2x2.fill",
            // Library & content
            "rectangle.stack": "rectangle.stack.fill",
            "waveform.badge.mic": "mic.circle.fill",
            "square.stack.3d.forward.dottedline": "square.stack.3d.forward.dottedline.fill",
            "chart.line.uptrend.xyaxis": "chart.xyaxis.line",
            "clock.arrow.circlepath": "clock.fill",
            // Stats & capture
            "waveform.path.ecg": "chart.bar.fill",
            "wand.and.stars": "wand.and.rays.inverse",
            "camera.viewfinder": "camera.fill",
        ]

        return fillableMappings[icon] ?? icon
    }

    private var iconImage: some View {
        Image(systemName: isSelected ? selectedIcon : icon)
            .font(.system(size: SidebarLayout.iconSize))
            .frame(width: SidebarLayout.iconFrameWidth, alignment: .center)
            #if DEBUG
            .background {
                if isSelected {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DesignGuideFrameKey.self,
                            value: ["iconBox": geo.frame(in: .named("designGuides"))]
                        )
                    }
                }
            }
            #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            iconImage
                .padding(.leading, 2) // Align icon center-X with logo center-X (29pt → 32pt)
                .padding(.trailing, iconsOnly ? 0 : SidebarLayout.iconToLabelGap)

            Text(title)
                .lineLimit(1)
                .opacity(iconsOnly ? 0 : 1)
                .offset(x: iconsOnly ? SidebarMotion.hiddenLabelOffset : 0)
                .blur(radius: iconsOnly ? SidebarMotion.hiddenLabelBlur : 0)
                .scaleEffect(iconsOnly ? 0.985 : 1, anchor: .leading)
                .accessibilityHidden(iconsOnly)
        }
        .clipped()
        .contentShape(Rectangle())
        .animation(SidebarMotion.toggleAnimation, value: iconsOnly)
    }
}

/// Convenience initializer for SidebarRow with just title and icon
extension SidebarRow where Content == SidebarLabel {
    init(section: NavigationSection, selectedSection: Binding<NavigationSection?>, title: String, icon: String, iconsOnly: Bool = false) {
        self.section = section
        self._selectedSection = selectedSection
        self.iconsOnly = iconsOnly
        self.tooltipLabel = title
        self.content = { isSelected in
            SidebarLabel(title: title, icon: icon, isSelected: isSelected, iconsOnly: iconsOnly)
        }
    }
}

/// Bottom-pinned sidebar item. This intentionally avoids nesting a second List
/// inside the sidebar safe-area inset, which gives the footer different row
/// metrics and selection behavior from the rest of the sidebar.
struct SidebarFooterRow: View {
    let section: NavigationSection
    @Binding var selectedSection: NavigationSection?
    let title: String
    let icon: String
    var iconsOnly: Bool = false

    @State private var isHovering = false
    @State private var rowFrame: CGRect = .zero

    private var isSelected: Bool {
        selectedSection == section
    }

    private var accentColor: Color {
        SettingsManager.shared.accentColor.color ?? Color.accentColor
    }

    var body: some View {
        Button {
            selectedSection = section
        } label: {
            VStack(spacing: SidebarLayout.accentToIconVerticalGap) {
                SidebarLabel(title: title, icon: icon, isSelected: isSelected, iconsOnly: iconsOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)

                RoundedRectangle(cornerRadius: 1)
                    .fill(iconsOnly && isSelected ? accentColor : Color.clear)
                    .frame(width: SidebarLayout.accentBarLength, height: iconsOnly ? SidebarLayout.accentBarHeight : 0)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(footerBackground)
            )
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrame = newFrame
                    }
            }
        }
        .onContinuousHover { phase in
            guard iconsOnly else { return }
            let tooltip = SidebarTooltipState.shared
            switch phase {
            case .active:
                isHovering = true
                let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                if tooltip.label == title {
                    tooltip.updateAnchor(anchor)
                } else {
                    tooltip.show(label: title, anchor: anchor)
                }
            case .ended:
                isHovering = false
                tooltip.dismiss(matching: title)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
    }

    private var footerBackground: Color {
        if isSelected {
            return accentColor.opacity(iconsOnly ? 0 : 0.14)
        }
        if isHovering {
            return Theme.current.foreground.opacity(0.06)
        }
        return .clear
    }
}

// MARK: - Sidebar Tooltip Arrow

/// Left-pointing triangle for sidebar hover tooltip
struct SidebarTooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

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
    private let controller = MemoRecordingController.shared
    private let screenRecorder = ScreenRecordingController.shared
    @State private var dictateHovered = false
    @State private var createHovered = false

    private var isPreparing: Bool { controller.state.isPreparing }
    private var isRecording: Bool { controller.state.isRecording }
    private var isProcessing: Bool { controller.state.isProcessing }
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
                NavigationState.shared.navigate(to: .dictations)
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
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.red.opacity(0.8))
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
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.red.opacity(0.8))
                        Text("Selecting")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity
                    ))
                } else if isRecording {
                    Text(formatElapsed(controller.elapsedTime))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                }

                RecordButtonContent(isRecording: isActive, isHovered: recordHovered)

                if isProcessing && !isRecording && !isPreparing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.6))
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
                NavigationState.shared.navigate(to: .drafts)
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
                NavigationState.shared.navigate(to: .workflows)
            } label: {
                Label("Workflows", systemImage: "wand.and.stars")
            }

            Button {
                NavigationState.shared.navigate(to: .screenshots)
            } label: {
                Label("Screenshots", systemImage: "camera.viewfinder")
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
                NavigationState.shared.navigate(to: .recordings, params: ["recordingId": noteId.uuidString])
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
