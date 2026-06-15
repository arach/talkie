//
//  HomeGrid.swift
//  Talkie
//
//  Grid-based layout system for the Home screen.
//  12-column grid where cards can span 3 (4-up), 4 (3-up), 6 (2-up), or 12 (full-width).
//

import SwiftUI
import TalkieKit

// MARK: - Card Span

/// A card's width in the 12-column grid
enum CardSpan: Int, Codable {
    case three = 3    // 4-up layout (3+3+3+3 = 12)
    case four = 4     // 3-up layout (4+4+4 = 12)
    case six = 6      // 2-up layout (6+6 = 12)
    case twelve = 12  // Full-width
}

// MARK: - Home Card Protocol

/// Any card that can be placed in the grid
@MainActor
protocol HomeCard: Identifiable {
    var id: String { get }
    var cardType: HomeCardType { get }
    var span: CardSpan { get }

    @MainActor @ViewBuilder func render() -> AnyView
}

// MARK: - Home Row

/// A horizontal row of cards (spans should sum to 12)
@MainActor
struct HomeRow: Identifiable {
    let id: String
    let cards: [any HomeCard]

    var totalSpan: Int { cards.reduce(0) { $0 + $1.span.rawValue } }
    var isValid: Bool { totalSpan == 12 }

    init(id: String, cards: [any HomeCard]) {
        self.id = id
        self.cards = cards
        #if DEBUG
        // Catch layout bugs early - all rows should sum to exactly 12 columns
        assert(totalSpan == 12, "HomeRow '\(id)' has invalid span: \(totalSpan) (expected 12)")
        #endif
    }
}

// MARK: - Home Grid

/// The complete grid of rows
@MainActor
struct HomeGrid {
    var rows: [HomeRow]

    var allCards: [any HomeCard] {
        rows.flatMap { $0.cards }
    }
}

// MARK: - Card Type Registry

/// All available card types in the system
enum HomeCardType: String, CaseIterable, Codable {
    // Stats (typically span: .three for 4-up)
    case statToday
    case statMemos
    case statDictations
    case statWords

    // Actions (typically span: .three for 4-up)
    case actionRecord
    case actionHelpers
    case actionWorkflows
    case actionSettings

    // Devices (typically span: .six for 2-up)
    case devicesBridge
    case bridgeDebug

    // Widgets (typically span: .four for 3-up)
    case widgetTrending
    case widgetShortcuts
    case widgetActivity
    case widgetCalendar

    // Content (typically span: .six for 2-up)
    case recentMemos
    case recentDictations

    // Features (typically span: .four for 3-up)
    case featureCaptures
    case featureWorkflowRuns
    case featureAgentConsole

    // Narrative (typically span: .twelve for full-width)
    case brandHero

    // Onboarding/Setup (various spans)
    case setupHotkey
    case setupAppearance
    case systemStatus

    /// Default span for this card type
    var defaultSpan: CardSpan {
        switch self {
        case .statToday, .statMemos, .statDictations, .statWords,
             .actionRecord, .actionHelpers, .actionWorkflows, .actionSettings:
            return .three

        case .devicesBridge, .bridgeDebug:
            return .six

        case .widgetTrending, .widgetShortcuts, .widgetActivity, .widgetCalendar,
             .featureCaptures, .featureWorkflowRuns, .featureAgentConsole:
            return .four

        case .recentMemos, .recentDictations:
            return .six

        case .brandHero, .systemStatus:
            return .twelve

        case .setupHotkey, .setupAppearance:
            return .four
        }
    }
}

// MARK: - Home Context

/// Context for determining which cards to show
struct HomeContext {
    let isOnboarding: Bool
    let hasActivity: Bool
    let useCalendarWidget: Bool
    let helpersRunningCount: Int
    let helpersExpectedCount: Int

    // Stats
    let todayTotal: Int
    let todayMemos: Int
    let todayDictations: Int
    let totalMemos: Int
    let totalDictations: Int
    let totalWords: Int
}

// MARK: - Grid Presets (Debug)

#if DEBUG
/// Preset configurations for testing different grid states
enum HomeGridPreset: String, CaseIterable, Identifiable {
    case live = "Agent Data"
    case newUser = "New User"
    case activeUser = "Active User"
    case powerUser = "Power User"
    case minimal = "Minimal"
    case widgetsOnly = "Widgets Only"
    case onboardingFlow = "Onboarding Flow"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .live: return "Uses real data from the database"
        case .newUser: return "Empty state, first launch experience"
        case .activeUser: return "Regular usage with moderate activity"
        case .powerUser: return "Heavy usage, all features active"
        case .minimal: return "Stripped down, essential cards only"
        case .widgetsOnly: return "Just the widget row"
        case .onboardingFlow: return "Full onboarding with brand + status"
        }
    }

    /// Generate a synthetic context for this preset
    var context: HomeContext {
        switch self {
        case .live:
            // This is handled specially - uses real data
            return HomeContext(
                isOnboarding: false,
                hasActivity: true,
                useCalendarWidget: false,
                helpersRunningCount: 2,
                helpersExpectedCount: 2,
                todayTotal: 0,
                todayMemos: 0,
                todayDictations: 0,
                totalMemos: 0,
                totalDictations: 0,
                totalWords: 0
            )

        case .newUser:
            return HomeContext(
                isOnboarding: false,
                hasActivity: false,
                useCalendarWidget: false,
                helpersRunningCount: 0,
                helpersExpectedCount: 1,
                todayTotal: 0,
                todayMemos: 0,
                todayDictations: 0,
                totalMemos: 0,
                totalDictations: 0,
                totalWords: 0
            )

        case .activeUser:
            return HomeContext(
                isOnboarding: false,
                hasActivity: true,
                useCalendarWidget: false,
                helpersRunningCount: 2,
                helpersExpectedCount: 2,
                todayTotal: 7,
                todayMemos: 3,
                todayDictations: 4,
                totalMemos: 42,
                totalDictations: 156,
                totalWords: 12_450
            )

        case .powerUser:
            return HomeContext(
                isOnboarding: false,
                hasActivity: true,
                useCalendarWidget: true,
                helpersRunningCount: 2,
                helpersExpectedCount: 2,
                todayTotal: 23,
                todayMemos: 8,
                todayDictations: 15,
                totalMemos: 847,
                totalDictations: 6_829,
                totalWords: 892_156
            )

        case .minimal:
            return HomeContext(
                isOnboarding: false,
                hasActivity: true,
                useCalendarWidget: false,
                helpersRunningCount: 1,
                helpersExpectedCount: 1,
                todayTotal: 2,
                todayMemos: 1,
                todayDictations: 1,
                totalMemos: 5,
                totalDictations: 12,
                totalWords: 1_200
            )

        case .widgetsOnly:
            return HomeContext(
                isOnboarding: false,
                hasActivity: true,
                useCalendarWidget: false,
                helpersRunningCount: 2,
                helpersExpectedCount: 2,
                todayTotal: 5,
                todayMemos: 2,
                todayDictations: 3,
                totalMemos: 50,
                totalDictations: 200,
                totalWords: 25_000
            )

        case .onboardingFlow:
            return HomeContext(
                isOnboarding: true,
                hasActivity: false,
                useCalendarWidget: false,
                helpersRunningCount: 0,
                helpersExpectedCount: 1,
                todayTotal: 0,
                todayMemos: 0,
                todayDictations: 0,
                totalMemos: 0,
                totalDictations: 0,
                totalWords: 0
            )
        }
    }
}

/// Manager for switching between grid presets in debug builds
@MainActor
class HomeGridPresetManager: ObservableObject {
    static let shared = HomeGridPresetManager()

    @Published var activePreset: HomeGridPreset = .live
    @Published var isPresetPickerVisible = false

    private init() {}

    var isUsingLiveData: Bool { activePreset == .live }
}
#endif

// MARK: - Grid Builder

/// Builds the grid based on user context
@MainActor
class HomeGridBuilder {

    #if DEBUG
    /// Build grid for a specific preset (debug only)
    func build(preset: HomeGridPreset) -> HomeGrid {
        switch preset {
        case .live:
            // Handled by caller with real context
            fatalError("Use build(context:) for live data")

        case .minimal:
            return buildMinimal(context: preset.context)

        case .widgetsOnly:
            return buildWidgetsOnly(context: preset.context)

        default:
            return build(context: preset.context)
        }
    }

    /// Minimal grid - just stats and actions
    private func buildMinimal(context: HomeContext) -> HomeGrid {
        var rows: [HomeRow] = []

        // Stats only - use full config for debug
        if let statsRow = buildStatsRow(context: context, config: .full) {
            rows.append(statsRow)
        }

        // Actions only - use full config for debug
        if let actionsRow = buildActionsRow(context: context, config: .full) {
            rows.append(actionsRow)
        }

        return HomeGrid(rows: rows)
    }

    /// Widgets only - for testing widget layouts
    private func buildWidgetsOnly(context: HomeContext) -> HomeGrid {
        var rows: [HomeRow] = []

        // Just the widgets row - use full config for debug
        if let widgetsRow = buildWidgetsRow(context: context, config: .full) {
            rows.append(widgetsRow)
        }

        return HomeGrid(rows: rows)
    }
    #endif

    /// Build the default grid for given context
    func build(context: HomeContext) -> HomeGrid {
        let settings = SettingsManager.shared
        var config = settings.homeLayoutConfig
        config.migrateForNewFeatures()
        if config != settings.homeLayoutConfig {
            settings.homeLayoutConfig = config
        }

        var rows: [HomeRow] = []

        // Row 1: Brand hero (onboarding only, full-width)
        if context.isOnboarding && config.isRowVisible(.brand) {
            rows.append(buildBrandRow())
        }

        // Build rows based on user config
        for rowType in config.visibleRows {
            switch rowType {
            case .brand:
                // Already handled above for onboarding
                continue
            case .stats:
                if let row = buildStatsRow(context: context, config: config) {
                    rows.append(row)
                }
            case .actions:
                if let row = buildActionsRow(context: context, config: config) {
                    rows.append(row)
                }
            case .devices:
                if let row = buildDevicesRow(config: config) {
                    rows.append(row)
                }
            case .widgets:
                if let row = buildWidgetsRow(context: context, config: config) {
                    rows.append(row)
                }
            case .features:
                if let row = buildFeaturesRow(config: config) {
                    rows.append(row)
                }
            case .recent:
                if let row = buildRecentRow(config: config) {
                    rows.append(row)
                }
            case .setup:
                // Setup cards handled separately
                continue
            }
        }

        if !rows.contains(where: { $0.id == "devices" }),
           let row = buildDevicesRow(config: config) {
            rows.append(row)
        }

        return HomeGrid(rows: rows)
    }

    // MARK: - Row Builders

    func buildBrandRow() -> HomeRow {
        HomeRow(id: "brand", cards: [BrandHeroCard()])
    }

    func buildStatsRow(context: HomeContext, config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        var cards: [any HomeCard] = []

        if cfg.isCardVisible(.statToday) {
            cards.append(HomeStatCard(
                cardType: .statToday,
                icon: "calendar",
                value: "\(context.todayTotal)",
                label: "Today",
                detail: context.todayTotal == 0 ? "Get started!" : "\(context.todayMemos) memos, \(context.todayDictations) dictations"
            ))
        }
        if cfg.isCardVisible(.statMemos) {
            cards.append(HomeStatCard(
                cardType: .statMemos,
                icon: "doc.text.fill",
                value: formatNumber(context.totalMemos),
                label: "Memos",
                detail: "Voice recordings"
            ))
        }
        if cfg.isCardVisible(.statDictations) {
            cards.append(HomeStatCard(
                cardType: .statDictations,
                icon: "waveform",
                value: formatNumber(context.totalDictations),
                label: "Dictations",
                detail: "Quick captures"
            ))
        }
        if cfg.isCardVisible(.statWords) {
            cards.append(HomeStatCard(
                cardType: .statWords,
                icon: "text.word.spacing",
                value: formatNumber(context.totalWords),
                label: "Words",
                detail: "Total transcribed"
            ))
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "stats", cards: cards)
    }

    func buildActionsRow(context: HomeContext, config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        var cards: [any HomeCard] = []

        if cfg.isCardVisible(.actionRecord) {
            cards.append(HomeActionCard(cardType: .actionRecord, icon: "mic.fill", title: "Record", color: .cyan) {
                NavigationState.shared.navigate(to: .recordings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .init("ShowRecordingView"), object: nil)
                }
            })
        }
        if cfg.isCardVisible(.actionHelpers) {
            cards.append(HomeActionCard(
                cardType: .actionHelpers,
                icon: "app.connected.to.app.below.fill",
                title: "Helpers",
                color: helpersColor(running: context.helpersRunningCount, expected: context.helpersExpectedCount),
                badge: context.helpersRunningCount < context.helpersExpectedCount
                    ? "\(context.helpersRunningCount)/\(context.helpersExpectedCount)"
                    : nil
            ) {
                NavigationState.shared.navigateToHelpers()
            })
        }
        if cfg.isCardVisible(.actionWorkflows) {
            cards.append(HomeActionCard(cardType: .actionWorkflows, icon: "wand.and.stars", title: "Workflows", color: .orange) {
                NavigationState.shared.navigateToWorkflows()
            })
        }
        if cfg.isCardVisible(.actionSettings) {
            cards.append(HomeActionCard(cardType: .actionSettings, icon: "gear", title: "Settings", color: .gray) {
                NavigationState.shared.navigate(to: .settings)
            })
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "actions", cards: cards)
    }

    func buildDevicesRow(config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        let showDevices = cfg.isCardVisible(.devicesBridge)
        let showBridgeDebug = cfg.isCardVisible(.bridgeDebug)

        var cards: [any HomeCard] = []
        if showDevices {
            cards.append(HomeDevicesCard(span: showBridgeDebug ? .six : .twelve))
        }
        if showBridgeDebug {
            cards.append(HomeBridgeDebugCard(span: showDevices ? .six : .twelve))
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "devices", cards: cards)
    }

    func buildWidgetsRow(context: HomeContext, config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        var cards: [any HomeCard] = []

        // For low activity users: prioritize setup/status widgets
        if !context.hasActivity || context.isOnboarding {
            if cfg.isCardVisible(.systemStatus) {
                cards.append(SystemStatusWidgetCard())
            }
            if cfg.isCardVisible(.widgetShortcuts) {
                cards.append(ShortcutsWidgetCard())
            }
            // SetupGuide is part of setup row, but shown here for low activity
            cards.append(SetupGuideWidgetCard())
        } else {
            // For active users
            if cfg.isCardVisible(.widgetTrending) {
                cards.append(TrendingWidgetCard())
            }
            if cfg.isCardVisible(.widgetShortcuts) {
                cards.append(ShortcutsWidgetCard())
            }
            if cfg.isCardVisible(.widgetCalendar) && context.useCalendarWidget {
                cards.append(CalendarWidgetCard())
            } else if cfg.isCardVisible(.widgetActivity) {
                cards.append(ActivityWidgetCard())
            }
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "widgets", cards: cards)
    }

    func buildFeaturesRow(config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        var cards: [any HomeCard] = []

        if cfg.isCardVisible(.featureCaptures) {
            cards.append(CapturesFeatureCard())
        }
        if cfg.isCardVisible(.featureWorkflowRuns) {
            cards.append(WorkflowRunsFeatureCard())
        }
        if cfg.isCardVisible(.featureAgentConsole) {
            cards.append(AgentConsoleFeatureCard())
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "features", cards: cards)
    }

    func buildRecentRow(config: HomeLayoutConfig? = nil) -> HomeRow? {
        let cfg = config ?? SettingsManager.shared.homeLayoutConfig
        var cards: [any HomeCard] = []

        if cfg.isCardVisible(.recentMemos) {
            cards.append(RecentMemosCard())
        }
        if cfg.isCardVisible(.recentDictations) {
            cards.append(RecentDictationsCard())
        }

        guard !cards.isEmpty else { return nil }
        return HomeRow(id: "recent", cards: cards)
    }

    func buildStatusRow() -> HomeRow {
        // 2-up: System status + Setup guidance
        HomeRow(
            id: "status",
            cards: [
                SystemStatusCard(),
                SetupGuideCard()
            ]
        )
    }

    // MARK: - Helpers

    private func helpersColor(running: Int, expected: Int) -> Color {
        if running >= expected { return .green }
        if running == 0 { return .red }
        return .orange
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}

// MARK: - Grid Row View

/// Renders a single row of cards
struct HomeRowView: View {
    let row: HomeRow
    var fixedHeight: CGFloat? = nil
    @Binding var selectedCardID: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(row.cards, id: \.id) { card in
                card.render()
                    .frame(maxWidth: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .overlay {
                        if selectedCardID == card.id {
                            HomeKeyboardSelectionRing()
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            selectedCardID = card.id
                        }
                    )
            }
        }
        .frame(height: fixedHeight)
        .clipped()
    }
}

// MARK: - Grid View

/// Renders the complete grid
struct HomeGridView: View {
    let grid: HomeGrid
    @State private var selectedCardID: String?
    @State private var isKeyboardPreviewVisible = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ForEach(grid.rows) { row in
                HomeRowView(
                    row: row,
                    fixedHeight: cardHeight(for: row.id),
                    selectedCardID: $selectedCardID
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isKeyboardPreviewVisible, let selectedPreview {
                HomeKeyboardPreviewHUD(preview: selectedPreview)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .homeKeyboardNavigation(
            items: navigationItems,
            selectedCardID: $selectedCardID,
            isPreviewVisible: $isKeyboardPreviewVisible,
            onActivate: activateCard
        )
        .onChange(of: grid.allCards.map(\.id)) { _, visibleIDs in
            guard let selectedCardID, !visibleIDs.contains(selectedCardID) else { return }
            self.selectedCardID = visibleIDs.first
        }
        .animation(.easeOut(duration: 0.12), value: selectedCardID)
        .animation(.easeOut(duration: 0.12), value: isKeyboardPreviewVisible)
    }

    private var selectedPreview: HomeCardKeyboardPreview? {
        guard let selectedCardID,
              let card = grid.allCards.first(where: { $0.id == selectedCardID }) else {
            return nil
        }
        return HomeCardKeyboardPreview(cardType: card.cardType)
    }

    private var navigationItems: [HomeKeyboardNavigationItem] {
        grid.rows.enumerated().flatMap { rowIndex, row in
            var currentColumn = 0
            return row.cards.enumerated().map { cardIndex, card in
                let startColumn = currentColumn
                currentColumn += card.span.rawValue
                return HomeKeyboardNavigationItem(
                    id: card.id,
                    cardType: card.cardType,
                    rowIndex: rowIndex,
                    cardIndex: cardIndex,
                    columnMidpoint: Double(startColumn) + (Double(card.span.rawValue) / 2)
                )
            }
        }
    }

    /// Fixed heights for card rows using CardHeight t-shirt sizes.
    /// Returns nil for rows that should size to content (e.g. brand hero).
    private func cardHeight(for rowId: String) -> CGFloat? {
        switch rowId {
        case "stats":              return CardHeight.sm
        case "actions":            return CardHeight.xs
        case "recent":             return CardHeight.md
        default:                   return nil  // widgets size to content
        }
    }

    @MainActor
    private func activateCard(_ item: HomeKeyboardNavigationItem) {
        switch item.cardType {
        case .statToday, .widgetActivity:
            NavigationState.shared.navigateToDate(Date())
        case .statMemos, .recentMemos:
            NavigationState.shared.navigateToAllMemos()
        case .statDictations, .recentDictations:
            NavigationState.shared.navigateToDictations()
        case .statWords:
            NotificationCenter.default.post(name: .showContentSearch, object: nil)
        case .actionRecord:
            NavigationState.shared.navigate(to: .recordings)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .init("ShowRecordingView"), object: nil)
            }
        case .actionHelpers, .devicesBridge, .bridgeDebug, .systemStatus:
            NavigationState.shared.navigateToHelpers()
        case .actionWorkflows, .widgetTrending, .featureWorkflowRuns:
            NavigationState.shared.navigateToWorkflows()
        case .actionSettings, .setupHotkey, .setupAppearance:
            NavigationState.shared.navigate(to: .settings)
        case .widgetShortcuts:
            NotificationCenter.default.post(name: .showCommandPalette, object: nil)
        case .widgetCalendar:
            NavigationState.shared.navigateToDate(Date())
        case .featureCaptures:
            NavigationState.shared.navigate(to: .screenshots)
        case .featureAgentConsole:
            NavigationState.shared.navigateToConsole()
        case .brandHero:
            NotificationCenter.default.post(name: .showContentSearch, object: nil)
        }
    }
}

// MARK: - Keyboard Navigation

private struct HomeKeyboardNavigationItem: Identifiable, Equatable {
    let id: String
    let cardType: HomeCardType
    let rowIndex: Int
    let cardIndex: Int
    let columnMidpoint: Double
}

private struct HomeCardKeyboardPreview: Equatable {
    let icon: String
    let title: String
    let detail: String

    init(cardType: HomeCardType) {
        switch cardType {
        case .statToday:
            icon = "calendar"; title = "Today"; detail = "Open today in the activity timeline."
        case .statMemos:
            icon = "doc.text.fill"; title = "Memos"; detail = "Jump to all voice memos."
        case .statDictations:
            icon = "waveform"; title = "Dictations"; detail = "Jump to dictation history."
        case .statWords:
            icon = "text.word.spacing"; title = "Words"; detail = "Search your captured content."
        case .actionRecord:
            icon = "mic.fill"; title = "Record"; detail = "Start a new recording."
        case .actionHelpers:
            icon = "app.connected.to.app.below.fill"; title = "Helpers"; detail = "Inspect helper app status."
        case .actionWorkflows:
            icon = "wand.and.stars"; title = "Workflows"; detail = "Open workflow automation."
        case .actionSettings:
            icon = "gear"; title = "Settings"; detail = "Open Talkie settings."
        case .devicesBridge:
            icon = "iphone.gen3"; title = "Devices"; detail = "Review paired devices and bridge status."
        case .bridgeDebug:
            icon = "network"; title = "Bridge Debug"; detail = "Inspect bridge diagnostics."
        case .widgetTrending:
            icon = "chart.line.uptrend.xyaxis"; title = "Trending"; detail = "Open workflow and insight activity."
        case .widgetShortcuts:
            icon = "command"; title = "Shortcuts"; detail = "Open the command palette."
        case .widgetActivity:
            icon = "square.grid.3x3"; title = "Activity"; detail = "Open today in the activity timeline."
        case .widgetCalendar:
            icon = "calendar.day.timeline.left"; title = "Calendar"; detail = "Open today in the calendar view."
        case .recentMemos:
            icon = "doc.text"; title = "Recent Memos"; detail = "Open the memo library."
        case .recentDictations:
            icon = "waveform.path"; title = "Recent Dictations"; detail = "Open recent dictations."
        case .featureCaptures:
            icon = "camera.viewfinder"; title = "Captures"; detail = "Open the screenshot and capture grid."
        case .featureWorkflowRuns:
            icon = "wand.and.stars"; title = "Workflow Runs"; detail = "Open workflow runs."
        case .featureAgentConsole:
            icon = "terminal"; title = "Agent & Console"; detail = "Open the agent console."
        case .brandHero:
            icon = "sparkles"; title = "Talkie Home"; detail = "Search across your Talkie workspace."
        case .setupHotkey:
            icon = "keyboard"; title = "Hotkey Setup"; detail = "Open setup in settings."
        case .setupAppearance:
            icon = "paintpalette"; title = "Appearance"; detail = "Open appearance settings."
        case .systemStatus:
            icon = "checkmark.seal"; title = "System Status"; detail = "Inspect helper and sync status."
        }
    }
}

private struct HomeKeyboardSelectionRing: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.cardLarge, style: .continuous)
            .strokeBorder(
                Theme.current.accent.opacity(0.85),
                lineWidth: 1.5
            )
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.cardLarge, style: .continuous)
                    .fill(Theme.current.accent.opacity(0.08))
            }
            .shadow(color: Theme.current.accent.opacity(0.22), radius: 10, y: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HomeKeyboardPreviewHUD: View {
    let preview: HomeCardKeyboardPreview

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: preview.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.current.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.current.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preview.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    Text("Return")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.current.foreground.opacity(0.06))
                        )
                }

                Text(preview.detail)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.current.surface1.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.current.border.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .frame(maxWidth: 320, alignment: .trailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HomeKeyboardNavigationModifier: ViewModifier {
    @Environment(\.navigationState) private var navigationState

    let items: [HomeKeyboardNavigationItem]
    @Binding var selectedCardID: String?
    @Binding var isPreviewVisible: Bool
    let onActivate: (HomeKeyboardNavigationItem) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: installMonitor)
            .onDisappear(perform: removeMonitor)
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    @MainActor
    private func handle(_ event: NSEvent) -> Bool {
        guard navigationState.selectedSection == .home,
              !items.isEmpty,
              !SettingsManager.shared.isCommandPalettePresented,
              !SettingsManager.shared.isVoiceCommandPresented,
              !isTextInputActive else {
            return false
        }

        let significantModifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard significantModifiers.isEmpty else { return false }

        switch event.keyCode {
        case 123, 4: // Left arrow, H
            move(.left)
        case 124, 37: // Right arrow, L
            move(.right)
        case 125, 38: // Down arrow, J
            move(.down)
        case 126, 40: // Up arrow, K
            move(.up)
        case 115: // Home
            select(items.first)
        case 119: // End
            select(items.last)
        case 36, 49: // Return, Space
            if let selectedItem {
                onActivate(selectedItem)
                isPreviewVisible = false
            }
        case 53: // Escape
            selectedCardID = nil
            isPreviewVisible = false
        default:
            return false
        }

        return true
    }

    private enum Direction {
        case left, right, up, down
    }

    private var selectedItem: HomeKeyboardNavigationItem? {
        guard let selectedCardID else { return nil }
        return items.first { $0.id == selectedCardID }
    }

    private var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        let className = String(describing: type(of: responder))
        return className.localizedCaseInsensitiveContains("TextField")
            || className.localizedCaseInsensitiveContains("FieldEditor")
            || className.localizedCaseInsensitiveContains("Search")
    }

    @MainActor
    private func move(_ direction: Direction) {
        guard let current = selectedItem else {
            select(direction == .up || direction == .left ? items.last : items.first)
            return
        }

        switch direction {
        case .left:
            select(flatItem(offsetFrom: current, by: -1) ?? current)
        case .right:
            select(flatItem(offsetFrom: current, by: 1) ?? current)
        case .up:
            select(nearestVerticalItem(from: current, rowOffset: -1) ?? current)
        case .down:
            select(nearestVerticalItem(from: current, rowOffset: 1) ?? current)
        }
    }

    private func flatItem(offsetFrom item: HomeKeyboardNavigationItem, by offset: Int) -> HomeKeyboardNavigationItem? {
        guard let index = items.firstIndex(of: item) else { return nil }
        let newIndex = min(max(index + offset, 0), items.count - 1)
        return items[newIndex]
    }

    private func nearestVerticalItem(from item: HomeKeyboardNavigationItem, rowOffset: Int) -> HomeKeyboardNavigationItem? {
        let targetRow = item.rowIndex + rowOffset
        let candidates = items.filter { $0.rowIndex == targetRow }
        return candidates.min {
            abs($0.columnMidpoint - item.columnMidpoint) < abs($1.columnMidpoint - item.columnMidpoint)
        }
    }

    @MainActor
    private func select(_ item: HomeKeyboardNavigationItem?) {
        guard let item else { return }
        selectedCardID = item.id
        isPreviewVisible = true
    }
}

private extension View {
    func homeKeyboardNavigation(
        items: [HomeKeyboardNavigationItem],
        selectedCardID: Binding<String?>,
        isPreviewVisible: Binding<Bool>,
        onActivate: @escaping (HomeKeyboardNavigationItem) -> Void
    ) -> some View {
        modifier(HomeKeyboardNavigationModifier(
            items: items,
            selectedCardID: selectedCardID,
            isPreviewVisible: isPreviewVisible,
            onActivate: onActivate
        ))
    }
}

// MARK: - Debug Preset Picker

#if DEBUG
/// Floating picker for switching between grid presets
struct HomeGridPresetPicker: View {
    @ObservedObject private var presetManager = HomeGridPresetManager.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.sm) {
            // Toggle button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 12, weight: .medium))

                    Text(presetManager.activePreset.rawValue)
                        .font(.system(size: 11, weight: .medium))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.purple.gradient)
                )
            }
            .buttonStyle(.plain)

            // Preset options
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(HomeGridPreset.allCases) { preset in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                presetManager.activePreset = preset
                                isExpanded = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.current.foreground)

                                    Text(preset.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.current.foregroundMuted)
                                }

                                Spacer()

                                if preset == presetManager.activePreset {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                preset == presetManager.activePreset
                                    ? Color.purple.opacity(0.1)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        if preset != HomeGridPreset.allCases.last {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .background(Theme.current.surface1)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.current.border.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .frame(width: 220)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
    }
}

/// Preview container that shows the grid with preset picker
struct HomeGridPreview: View {
    @ObservedObject private var presetManager = HomeGridPresetManager.shared
    private let gridBuilder = HomeGridBuilder()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header
                    HStack {
                        TalkieText("Home", style: .pageTitle)
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Grid
                    if presetManager.activePreset == .live {
                        Text("Agent data - use actual HomeScreen")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 100)
                    } else {
                        HomeGridView(grid: gridBuilder.build(preset: presetManager.activePreset))
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.current.surfaceBase)

            // Floating preset picker
            HomeGridPresetPicker()
                .padding()
        }
    }
}
#endif

// MARK: - Previews

#if DEBUG
#Preview("Grid - Preset Switcher") {
    HomeGridPreview()
        .frame(width: 800, height: 700)
}

#Preview("Grid - New User") {
    let builder = HomeGridBuilder()
    let grid = builder.build(context: HomeGridPreset.newUser.context)

    return ScrollView {
        HomeGridView(grid: grid)
            .padding()
    }
    .frame(width: 800, height: 600)
    .background(Theme.current.surfaceBase)
}

#Preview("Grid - Power User") {
    let builder = HomeGridBuilder()
    let grid = builder.build(context: HomeGridPreset.powerUser.context)

    return ScrollView {
        HomeGridView(grid: grid)
            .padding()
    }
    .frame(width: 800, height: 600)
    .background(Theme.current.surfaceBase)
}

#Preview("Grid - Onboarding") {
    let builder = HomeGridBuilder()
    let grid = builder.build(context: HomeGridPreset.onboardingFlow.context)

    return ScrollView {
        HomeGridView(grid: grid)
            .padding()
    }
    .frame(width: 800, height: 700)
    .background(Theme.current.surfaceBase)
}
#endif
