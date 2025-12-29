//
//  NavigationViewNative.swift
//  Talkie macOS
//
//  Native NavigationSplitView implementation with automatic column management
//
//  ⚠️ IMPORTANT: DO NOT CREATE CUSTOM SIDEBAR NAVIGATION ⚠️
//  We use Apple's native NavigationSplitView. We've tried custom implementations
//  multiple times and always regress back to native. The native implementation provides:
//  - Automatic column resizing and collapse behavior
//  - Native dividers and drag handles
//  - Proper state management
//  - macOS-appropriate behavior and animations
//  - Built-in accessibility support
//
//  If you need to customize appearance, use native modifiers only.
//  DO NOT rebuild the sidebar with HStack/VStack/custom gestures.
//

import SwiftUI
import CoreData

enum NavigationSection: Hashable {
    case home           // Main Talkie home/dashboard
    case scratchPad     // Quick text editing with voice dictation and AI polish
    case allMemos       // All Memos view (GRDB-based with pagination and filters)
    case liveDashboard  // Live home/insights view
    case liveRecent     // Live utterance list
    case liveSettings   // Live settings (now visible in sidebar)
    case aiResults
    case workflows
    case activityLog
    case systemConsole
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

struct TalkieNavigationViewNative: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Singletons - observe remote data
    private let settings = SettingsManager.shared
    private let liveDataStore = DictationStore.shared
    private let eventManager = SystemEventManager.shared
    private let pendingActionsManager = PendingActionsManager.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ]
    )
    private var allMemos: FetchedResults<VoiceMemo>

    // Navigation state
    @State private var selectedSection: NavigationSection? = .home
    @State private var previousSection: NavigationSection? = .home
    @State private var selectedMemo: VoiceMemo?
    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var selectedSettingsSection: SettingsSection = .appearance
    @State private var searchText = ""

    // Cached counts for badge display
    @State private var cachedErrorCount: Int = 0
    @State private var cachedWorkflowCount: Int = 0

    // Column visibility (NavigationSplitView manages this for us)
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Optional initializer for screenshot capture with specific navigation state
    init(initialSection: NavigationSection? = .home, initialSettingsSection: SettingsSection = .appearance) {
        _selectedSection = State(initialValue: initialSection)
        _selectedSettingsSection = State(initialValue: initialSettingsSection)
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func sectionName(for section: NavigationSection) -> String {
        switch section {
        case .home: return "Home"
        case .scratchPad: return "ScratchPad"
        case .allMemos: return "AllMemos"
        case .liveDashboard: return "LiveDashboard"
        case .liveRecent: return "LiveRecent"
        case .liveSettings: return "LiveSettings"
        case .aiResults: return "AIResults"
        case .workflows: return "Workflows"
        case .activityLog: return "ActivityLog"
        case .systemConsole: return "SystemLogs"
        case .pendingActions: return "PendingActions"
        case .talkieService: return "TalkieService"
        case .talkieLiveMonitor: return "TalkieLiveMonitor"
        case .models: return "Models"
        case .allowedCommands: return "AllowedCommands"
        case .smartFolder(let name): return "SmartFolder:\(name)"
        case .settings: return "Settings"
        #if DEBUG
        case .designHome: return "DesignHome"
        case .designAudit: return "DesignAudit"
        case .designComponents: return "DesignComponents"
        #endif
        }
    }

    // Consistent sidebar width - same for 2-column and 3-column layouts
    private static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (160, 200, 280)
    private static let contentColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (180, 220, 320)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if usesTwoColumns {
                    // 2-column layout: sidebar + detail
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        sidebarView
                            .navigationSplitViewColumnWidth(
                                min: Self.sidebarWidth.min,
                                ideal: Self.sidebarWidth.ideal,
                                max: Self.sidebarWidth.max
                            )
                    } detail: {
                        mainContentView
                    }
                } else {
                    // 3-column layout: sidebar + content + detail
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        sidebarView
                            .navigationSplitViewColumnWidth(
                                min: Self.sidebarWidth.min,
                                ideal: Self.sidebarWidth.ideal,
                                max: Self.sidebarWidth.max
                            )
                    } content: {
                        contentView
                            .navigationSplitViewColumnWidth(
                                min: Self.contentColumnWidth.min,
                                ideal: Self.contentColumnWidth.ideal,
                                max: Self.contentColumnWidth.max
                            )
                    } detail: {
                        mainContentView
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)

            // Full-width status bar at bottom
            StatusBar()
        }
        // Note: NavigationSplitView provides its own sidebar toggle with hiddenTitleBar
        // Don't add a custom one or you'll get duplicates
        .onChange(of: selectedSection) { oldValue, newValue in
            // Track navigation in Performance Monitor
            if let section = newValue, section != oldValue {
                PerformanceMonitor.shared.startAction(
                    type: "Navigate",
                    name: sectionName(for: section),
                    context: "Sidebar"
                )
            }
            // When switching to 3-column sections, ensure all columns are visible
            if let newValue = newValue, !usesTwoColumns {
                columnVisibility = .all
            }
        }
        .setupNotificationObservers(
            selectedSection: $selectedSection,
            previousSection: $previousSection,
            allMemosCount: allMemos.count,
            viewContext: viewContext
        )
    }

    // MARK: - Column Logic

    private var usesTwoColumns: Bool {
        switch selectedSection {
        case .home, .scratchPad, .models, .allowedCommands, .aiResults, .allMemos,
             .liveDashboard, .liveRecent, .liveSettings, .systemConsole,
             .pendingActions:
            return true
        #if DEBUG
        case .designHome, .designAudit, .designComponents:
            return true
        #endif
        default:
            return false  // workflows and settings use 3-column layout
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: $selectedSection) {
            // Header
            Section {
                Text("TALKIE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // Primary navigation (no section header)
            SidebarRow(section: .home, selectedSection: $selectedSection, title: "Home", icon: "house")
            SidebarRow(section: .allMemos, selectedSection: $selectedSection, title: "Recordings", icon: "square.stack")
            SidebarRow(section: .liveRecent, selectedSection: $selectedSection, title: "Dictations", icon: "waveform.badge.mic")

            // Live
            Section(settings.uiAllCaps ? "LIVE" : "Live") {
                SidebarRow(section: .liveDashboard, selectedSection: $selectedSection, title: "Stats", icon: "waveform.path.ecg")
            }

            // Activity
            Section(settings.uiAllCaps ? "ACTIVITY" : "Activity") {
                SidebarRow(section: .aiResults, selectedSection: $selectedSection, title: "Actions", icon: "chart.line.uptrend.xyaxis")

                SidebarRow(section: .pendingActions, selectedSection: $selectedSection, title: "Pending", icon: "clock.arrow.circlepath")
            }

            // Tools
            Section(settings.uiAllCaps ? "TOOLS" : "Tools") {
                SidebarRow(section: .scratchPad, selectedSection: $selectedSection, title: "Commands", icon: "mic")

                SidebarRow(section: .workflows, selectedSection: $selectedSection, title: "Workflows", icon: "wand.and.stars")

                SidebarRow(section: .models, selectedSection: $selectedSection, title: "Models", icon: "brain")

                SidebarRow(section: .systemConsole, selectedSection: $selectedSection, title: "Logs", icon: "terminal")
            }

            #if DEBUG
            if DesignModeManager.shared.isEnabled {
                Section(settings.uiAllCaps ? "DESIGN" : "Design") {
                    SidebarRow(section: .designHome, selectedSection: $selectedSection, title: "Design Home", icon: "paintbrush")

                    SidebarRow(section: .designAudit, selectedSection: $selectedSection, title: "Audit", icon: "checkmark.seal")

                    SidebarRow(section: .designComponents, selectedSection: $selectedSection, title: "Components", icon: "square.grid.2x2")
                }
            }
            #endif
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .safeAreaInset(edge: .bottom) {
            List(selection: $selectedSection) {
                SidebarRow(section: .settings, selectedSection: $selectedSection, title: "Settings", icon: "gear")
            }
            .listStyle(.sidebar)
            .frame(height: 36)
            .scrollDisabled(true)
        }
    }

    // MARK: - Content (Middle Column)

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .workflows:
            WorkflowListColumn(
                selectedWorkflowID: $selectedWorkflowID,
                editingWorkflow: $editingWorkflow
            )
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
                    UnifiedDashboard()
                case .scratchPad:
                    ScratchPadView()
                        .wrapInTalkieSection("ScratchPad")
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
                    AllMemos()
                case .liveDashboard:
                    HomeView(
                        onSelectDictation: { _ in selectedSection = .liveRecent },
                        onSelectApp: { _, _ in selectedSection = .liveRecent }
                    )
                    .wrapInTalkieSection("LiveDashboard")
                case .liveRecent:
                    DictationListView()
                        .wrapInTalkieSection("LiveRecent")
                case .liveSettings:
                    LiveSettingsView()
                case .systemConsole:
                    SystemLogsView(onClose: { selectedSection = previousSection ?? .home })
                        .wrapInTalkieSection("SystemLogs")
                case .pendingActions:
                    PendingActionsView()
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
                case .workflows:
                    WorkflowDetailColumn(
                        editingWorkflow: $editingWorkflow,
                        selectedWorkflowID: $selectedWorkflowID
                    )
                    .wrapInTalkieSection("Workflows")

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
    func wrapInTalkieSection(_ name: String) -> some View {
        TalkieSection(name) {
            self
        }
    }
}

// MARK: - Notification Observers

extension View {
    func setupNotificationObservers(
        selectedSection: Binding<NavigationSection?>,
        previousSection: Binding<NavigationSection?>,
        allMemosCount: Int,
        viewContext: NSManagedObjectContext
    ) -> some View {
        self
            .onChange(of: allMemosCount) { _, _ in
                PersistenceController.markMemosAsReceivedByMac(context: viewContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: .browseWorkflows)) { _ in
                selectedSection.wrappedValue = .workflows
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLive)) { _ in
                selectedSection.wrappedValue = .liveDashboard
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToLiveRecent"))) { _ in
                selectedSection.wrappedValue = .liveRecent
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
                selectedSection.wrappedValue = .settings
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLiveSettings)) { _ in
                selectedSection.wrappedValue = .liveSettings
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToAllMemos"))) { _ in
                selectedSection.wrappedValue = .allMemos
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToMemo"))) { notification in
                // Navigate to All Memos - the memo ID is in notification.object
                selectedSection.wrappedValue = .allMemos
                // Post follow-up to select the memo in the list
                if let memoID = notification.object as? UUID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .init("SelectMemo"), object: memoID)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToDictation"))) { notification in
                // Navigate to Live Recent - the dictation ID is in notification.object
                selectedSection.wrappedValue = .liveRecent
                // Post follow-up to select the dictation in the list
                if let dictationID = notification.object as? UUID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .init("SelectDictation"), object: dictationID)
                    }
                }
            }
    }
}

// MARK: - Sidebar Row with Selection Indicator

/// Custom sidebar row that shows a left accent bar when selected
/// Also switches icons to filled variant when selected for better visual feedback
struct SidebarRow<Content: View>: View {
    let section: NavigationSection
    @Binding var selectedSection: NavigationSection?
    @ViewBuilder let content: (_ isSelected: Bool) -> Content

    private var isSelected: Bool {
        selectedSection == section
    }

    var body: some View {
        NavigationLink(value: section) {
            HStack(spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? (SettingsManager.shared.accentColor.color ?? Color.accentColor) : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .animation(.easeOut(duration: 0.15), value: isSelected)

                content(isSelected)
                    .padding(.leading, 6)
            }
        }
    }
}

/// Sidebar label that switches between outlined and filled icons based on selection
struct SidebarLabel: View {
    let title: String
    let icon: String
    let isSelected: Bool

    /// Converts an icon name to its filled variant if available
    private var selectedIcon: String {
        // Already filled
        if icon.hasSuffix(".fill") { return icon }

        // Common mappings for icons without direct .fill suffix
        let fillableMappings: [String: String] = [
            "house": "house.fill",
            "note.text": "doc.text.fill",
            "square.stack": "square.stack.fill",
            "gear": "gearshape.fill",
            "brain": "brain.fill",
            "terminal": "terminal.fill",
            "paintbrush": "paintbrush.fill",
            "checkmark.seal": "checkmark.seal.fill",
            "square.grid.2x2": "square.grid.2x2.fill"
        ]

        return fillableMappings[icon] ?? icon
    }

    var body: some View {
        Label(title, systemImage: isSelected ? selectedIcon : icon)
    }
}

/// Convenience initializer for SidebarRow with just title and icon
extension SidebarRow where Content == SidebarLabel {
    init(section: NavigationSection, selectedSection: Binding<NavigationSection?>, title: String, icon: String) {
        self.section = section
        self._selectedSection = selectedSection
        self.content = { isSelected in
            SidebarLabel(title: title, icon: icon, isSelected: isSelected)
        }
    }
}

// MARK: - Preview

#Preview {
    TalkieNavigationViewNative()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .frame(width: 1200, height: 800)
}
