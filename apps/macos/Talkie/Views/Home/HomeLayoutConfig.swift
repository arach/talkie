//
//  HomeLayoutConfig.swift
//  Talkie macOS
//
//  User-configurable home screen layout settings.
//  Defines which cards/widgets are visible and row configuration.
//

import Foundation
import TalkieKit

// MARK: - Row Types

/// The different row types that can appear on the home screen
enum HomeRowType: String, CaseIterable, Codable, Identifiable {
    case brand = "brand"           // Brand hero (onboarding)
    case stats = "stats"           // Stats 4-up
    case actions = "actions"       // Quick actions 4-up
    case devices = "devices"       // Bridge and paired devices
    case widgets = "widgets"       // Widgets 3-up
    case features = "features"     // Feature spotlight 3-up
    case recent = "recent"         // Recent content 2-up
    case setup = "setup"           // Setup/onboarding cards

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brand: return "Brand Hero"
        case .stats: return "Stats"
        case .actions: return "Quick Actions"
        case .devices: return "Devices"
        case .widgets: return "Widgets"
        case .features: return "Features"
        case .recent: return "Recent Activity"
        case .setup: return "Setup"
        }
    }

    var icon: String {
        switch self {
        case .brand: return "star.fill"
        case .stats: return "chart.bar.fill"
        case .actions: return "bolt.fill"
        case .devices: return "ipad.and.iphone"
        case .widgets: return "square.grid.2x2"
        case .features: return "sparkles"
        case .recent: return "clock.fill"
        case .setup: return "gear"
        }
    }

    var description: String {
        switch self {
        case .brand: return "Welcome banner for new users"
        case .stats: return "Today's activity and totals"
        case .actions: return "Record, workflows, settings"
        case .devices: return "Pair iPhone and monitor Bridge"
        case .widgets: return "Calendar, shortcuts, activity"
        case .features: return "Captures, workflows, agent"
        case .recent: return "Recent memos and dictations"
        case .setup: return "Configuration and onboarding"
        }
    }

    /// Cards that belong to this row type
    var availableCards: [HomeCardType] {
        switch self {
        case .brand:
            return [.brandHero]
        case .stats:
            return [.statToday, .statMemos, .statDictations, .statWords]
        case .actions:
            return [.actionRecord, .actionHelpers, .actionWorkflows, .actionSettings]
        case .devices:
            return [.devicesBridge, .bridgeDebug]
        case .widgets:
            return [.widgetCalendar, .widgetShortcuts, .widgetActivity, .widgetTrending]
        case .features:
            return [.featureCaptures, .featureWorkflowRuns, .featureAgentConsole]
        case .recent:
            return [.recentMemos, .recentDictations]
        case .setup:
            return [.setupHotkey, .setupAppearance, .systemStatus]
        }
    }
}

// MARK: - Home Layout Config

/// User's home screen configuration
struct HomeLayoutConfig: Codable, Equatable {
    /// Which rows are visible (in order)
    var visibleRows: [HomeRowType]

    /// Which individual cards are visible (by card type)
    var visibleCards: Set<HomeCardType>

    /// Default configuration for new users
    static let `default` = HomeLayoutConfig(
        visibleRows: [.stats, .actions, .widgets, .recent, .features, .devices],
        visibleCards: Set(HomeCardType.allCases).subtracting([.brandHero, .setupHotkey, .setupAppearance])
    )

    /// Minimal configuration
    static let minimal = HomeLayoutConfig(
        visibleRows: [.stats, .actions],
        visibleCards: Set([
            .statToday, .statMemos, .statDictations, .statWords,
            .actionRecord, .actionHelpers, .actionWorkflows, .actionSettings
        ])
    )

    /// Full configuration with everything visible
    static let full = HomeLayoutConfig(
        visibleRows: HomeRowType.allCases.filter { $0 != .brand && $0 != .setup },
        visibleCards: Set(HomeCardType.allCases).subtracting([.brandHero])
    )

    // MARK: - Visibility Helpers

    /// Check if a specific card is visible
    func isCardVisible(_ card: HomeCardType) -> Bool {
        visibleCards.contains(card)
    }

    /// Check if a row type is visible
    func isRowVisible(_ row: HomeRowType) -> Bool {
        visibleRows.contains(row)
    }

    /// Get visible cards for a specific row
    func visibleCardsForRow(_ row: HomeRowType) -> [HomeCardType] {
        row.availableCards.filter { visibleCards.contains($0) }
    }

    // MARK: - Mutation Helpers

    /// Toggle a card's visibility
    mutating func toggleCard(_ card: HomeCardType) {
        if visibleCards.contains(card) {
            visibleCards.remove(card)
        } else {
            visibleCards.insert(card)
        }
    }

    /// Toggle a row's visibility
    mutating func toggleRow(_ row: HomeRowType) {
        if let index = visibleRows.firstIndex(of: row) {
            visibleRows.remove(at: index)
        } else {
            // Insert in default order
            let defaultOrder = HomeRowType.allCases
            let insertIndex = visibleRows.firstIndex { existingRow in
                guard let existingIndex = defaultOrder.firstIndex(of: existingRow),
                      let newIndex = defaultOrder.firstIndex(of: row) else { return false }
                return existingIndex > newIndex
            } ?? visibleRows.endIndex
            visibleRows.insert(row, at: insertIndex)
        }
    }

    /// Set all cards in a row visible/hidden
    mutating func setRowCardsVisible(_ row: HomeRowType, visible: Bool) {
        for card in row.availableCards {
            if visible {
                visibleCards.insert(card)
            } else {
                visibleCards.remove(card)
            }
        }
    }

    /// Apply one-time migrations to existing persisted configs so new rows/cards
    /// added after the config was first saved show up without a full reset.
    mutating func migrateForNewFeatures() {
        // Features row — place after .recent. If it was previously inserted above .recent
        // by an earlier migration, move it below.
        visibleRows.removeAll { $0 == .features }
        if let recentIdx = visibleRows.firstIndex(of: .recent) {
            visibleRows.insert(.features, at: recentIdx + 1)
        } else {
            visibleRows.append(.features)
        }
        for card in HomeRowType.features.availableCards {
            visibleCards.insert(card)
        }

        visibleRows.removeAll { $0 == .devices }
        visibleRows.append(.devices)
        visibleCards.insert(.devicesBridge)
        visibleCards.insert(.bridgeDebug)
    }
}

// MARK: - HomeCardType Metadata Extension

extension HomeCardType {
    var displayName: String {
        switch self {
        case .statToday: return "Today"
        case .statMemos: return "Memos"
        case .statDictations: return "Dictations"
        case .statWords: return "Words"
        case .actionRecord: return "Record"
        case .actionHelpers: return "Helpers"
        case .actionWorkflows: return "Workflows"
        case .actionSettings: return "Settings"
        case .devicesBridge: return "Devices"
        case .bridgeDebug: return "Bridge Debug"
        case .widgetTrending: return "Trending"
        case .widgetShortcuts: return "Shortcuts"
        case .widgetActivity: return "Activity"
        case .widgetCalendar: return "Calendar"
        case .recentMemos: return "Recent Memos"
        case .recentDictations: return "Recent Dictations"
        case .featureCaptures: return "Captures"
        case .featureWorkflowRuns: return "Workflow Runs"
        case .featureAgentConsole: return "Agent & Console"
        case .brandHero: return "Brand Hero"
        case .setupHotkey: return "Hotkey Setup"
        case .setupAppearance: return "Appearance Setup"
        case .systemStatus: return "System Status"
        }
    }

    var icon: String {
        switch self {
        case .statToday: return "calendar"
        case .statMemos: return "doc.text.fill"
        case .statDictations: return "waveform"
        case .statWords: return "textformat"
        case .actionRecord: return "record.circle"
        case .actionHelpers: return "app.connected.to.app.below.fill"
        case .actionWorkflows: return "sparkles"
        case .actionSettings: return "gear"
        case .devicesBridge: return "ipad.and.iphone"
        case .bridgeDebug: return "ladybug"
        case .widgetTrending: return "chart.line.uptrend.xyaxis"
        case .widgetShortcuts: return "command"
        case .widgetActivity: return "flame.fill"
        case .widgetCalendar: return "calendar"
        case .recentMemos: return "doc.text"
        case .recentDictations: return "waveform"
        case .featureCaptures: return "camera.viewfinder"
        case .featureWorkflowRuns: return "wand.and.stars"
        case .featureAgentConsole: return "terminal.fill"
        case .brandHero: return "star.fill"
        case .setupHotkey: return "keyboard"
        case .setupAppearance: return "paintbrush"
        case .systemStatus: return "checkmark.circle"
        }
    }
}
