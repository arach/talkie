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
    @State private var searchText = ""

    // Cached counts for badge display
    @State private var cachedErrorCount: Int = 0
    @State private var cachedWorkflowCount: Int = 0

    // Column visibility (NavigationSplitView manages this for us)
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if usesTwoColumns {
                // 2-column layout: sidebar + detail
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarView
                        .navigationSplitViewColumnWidth(
                            min: 160,
                            ideal: 220,
                            max: 320
                        )
                } detail: {
                    detailView
                }
            } else {
                // 3-column layout: sidebar + content + detail
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarView
                        .navigationSplitViewColumnWidth(
                            min: 160,
                            ideal: 220,
                            max: 320
                        )
                } content: {
                    contentView
                        .navigationSplitViewColumnWidth(
                            min: 280,
                            ideal: 320,
                            max: 480
                        )
                } detail: {
                    detailView
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.hidden, for: .windowToolbar)  // Hide title bar divider
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
        case .home, .models, .allowedCommands, .aiResults, .allMemos,
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

            // Home (no section header)
            NavigationLink(value: NavigationSection.home) {
                Label("Home", systemImage: "house.fill")
            }

            // Memos
            Section("MEMOS") {
                NavigationLink(value: NavigationSection.allMemos) {
                    HStack {
                        Label("All Memos", systemImage: "square.stack")
                        Spacer()
                        Text("\(allMemos.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
            }

            // Live
            Section("LIVE") {
                NavigationLink(value: NavigationSection.liveDashboard) {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }

                NavigationLink(value: NavigationSection.liveRecent) {
                    HStack {
                        Label("Recent", systemImage: "waveform.badge.mic")
                        Spacer()
                        Text("\(liveDataStore.dictations.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                NavigationLink(value: NavigationSection.liveSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            // Activity
            Section("ACTIVITY") {
                NavigationLink(value: NavigationSection.aiResults) {
                    Label("Actions", systemImage: "chart.line.uptrend.xyaxis")
                }

                NavigationLink(value: NavigationSection.pendingActions) {
                    Label("Pending", systemImage: "clock.arrow.circlepath")
                }
            }

            // Tools
            Section("TOOLS") {
                NavigationLink(value: NavigationSection.workflows) {
                    Label("Workflows", systemImage: "wand.and.stars")
                }

                NavigationLink(value: NavigationSection.models) {
                    Label("Models", systemImage: "brain")
                }

                NavigationLink(value: NavigationSection.systemConsole) {
                    Label("Logs", systemImage: "terminal")
                }
            }

            // Settings (bottom section)
            Section {
                NavigationLink(value: NavigationSection.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            #if DEBUG
            if DesignModeManager.shared.isEnabled {
                Section("DESIGN") {
                    NavigationLink(value: NavigationSection.designHome) {
                        Label("Design Home", systemImage: "paintbrush.fill")
                    }
                    NavigationLink(value: NavigationSection.designAudit) {
                        Label("Audit", systemImage: "checkmark.seal.fill")
                    }
                    NavigationLink(value: NavigationSection.designComponents) {
                        Label("Components", systemImage: "square.grid.2x2")
                    }
                }
            }
            #endif
        }
        .listStyle(.sidebar)
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
            // Settings uses its own internal layout (sidebar + content)
            SettingsView()
        default:
            Text("Content Column")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surface1)
        }
    }

    // MARK: - Detail (Main Content)

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 0) {
            // Main content
            Group {
                switch selectedSection {
                // Two-column sections
                case .home:
                    UnifiedDashboard()
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

                // Three-column sections (settings handled in contentView + detailView)
                case .settings:
                    // Settings content is shown via SettingsView's own layout
                    // which includes both the subsection sidebar and the actual content
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

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

            // Status bar at bottom
            StatusBar()
        }
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
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
                selectedSection.wrappedValue = .settings
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLiveSettings)) { _ in
                selectedSection.wrappedValue = .liveSettings
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToAllMemos"))) { _ in
                selectedSection.wrappedValue = .allMemos
            }
    }
}

// MARK: - Preview

#Preview {
    TalkieNavigationViewNative()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .frame(width: 1200, height: 800)
}
