//
//  NavigationViewNative.swift
//  Talkie macOS
//
//  Native NavigationSplitView implementation with automatic column management
//

import SwiftUI
import CoreData

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
                            min: 200,
                            ideal: 220,
                            max: 300
                        )
                } detail: {
                    detailView
                }
            } else {
                // 3-column layout: sidebar + content + detail
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarView
                        .navigationSplitViewColumnWidth(
                            min: 200,
                            ideal: 220,
                            max: 300
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
        .padding(.top, Spacing.sm)  // Breathing room for traffic lights
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
             .pendingActions, .settings:
            return true
        #if DEBUG
        case .designHome, .designAudit, .designComponents:
            return true
        #endif
        default:
            return false
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: $selectedSection) {
            // Header
            Section {
                Text("TALKIE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Theme.current.foreground)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            // Tools
            Section("TOOLS") {
                NavigationLink(value: NavigationSection.home) {
                    Label("Home", systemImage: "house")
                }

                NavigationLink(value: NavigationSection.liveDashboard) {
                    Label("Live", systemImage: "waveform")
                }

                NavigationLink(value: NavigationSection.workflows) {
                    Label("Workflows", systemImage: "wand.and.stars")
                }

                NavigationLink(value: NavigationSection.models) {
                    Label("Models", systemImage: "brain")
                }
            }

            // Library
            Section("LIBRARY") {
                NavigationLink(value: NavigationSection.allMemos) {
                    HStack {
                        Label("All Memos", systemImage: "square.stack")
                        Spacer()
                        Text("\(allMemos.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                NavigationLink(value: NavigationSection.liveRecent) {
                    HStack {
                        Label("Recent", systemImage: "clock")
                        Spacer()
                        Text("\(liveDataStore.dictations.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
            }

            // Settings & Debug
            Section {
                NavigationLink(value: NavigationSection.settings) {
                    Label("Settings", systemImage: "gearshape")
                }

                NavigationLink(value: NavigationSection.systemConsole) {
                    Label("Logs", systemImage: "terminal")
                }

                #if DEBUG
                if DesignModeManager.shared.isEnabled {
                    NavigationLink(value: NavigationSection.designHome) {
                        Label("Design", systemImage: "paintpalette")
                    }
                }
                #endif
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Navigation")
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
        default:
            Text("Content Column")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surface1)
        }
    }

    // MARK: - Detail (Main Content)

    @ViewBuilder
    private var detailView: some View {
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
                onSelectUtterance: { _ in selectedSection = .liveRecent },
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
        case .settings:
            SettingsView()
                .wrapInTalkieSection("Settings")

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
