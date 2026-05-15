//
//  SemanticFilter.swift
//  Talkie
//
//  Declarative filter system that maps semantic labels to SQL predicates.
//

import Foundation
import TalkieKit

// MARK: - Semantic Filter Definition

struct SemanticFilter: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let group: FilterGroup
    let sql: String  // SQL WHERE clause fragment

    enum FilterGroup: String, CaseIterable {
        case type      // All, Memos, Dictations
        case time      // Today, This Week, This Month
        case status    // Has Tasks, Failed, etc.
        case source    // iPhone, Watch, Mac, Live

        /// Whether filters in this group are mutually exclusive
        var isExclusive: Bool {
            switch self {
            case .type, .time: return true
            case .status, .source: return false
            }
        }

        var displayName: String {
            switch self {
            case .type: return "Type"
            case .time: return "Time"
            case .status: return "Status"
            case .source: return "Source"
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SemanticFilter, rhs: SemanticFilter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Predefined Filters

extension SemanticFilter {
    // Type (mutually exclusive)
    static let all = SemanticFilter(
        id: "all", label: "All", icon: "square.grid.2x2",
        group: .type, sql: "1=1"
    )
    static let memos = SemanticFilter(
        id: "memos", label: "Memos", icon: "mic.fill",
        group: .type, sql: "type = 'memo'"
    )
    static let dictations = SemanticFilter(
        id: "dictations", label: "Dictations", icon: "waveform",
        group: .type, sql: "type = 'dictation'"
    )
    static let notes = SemanticFilter(
        id: "notes", label: "Notes", icon: "note.text",
        group: .type, sql: "type = 'note'"
    )
    static let captures = SemanticFilter(
        id: "captures", label: "Captures", icon: "tray.and.arrow.down",
        group: .type, sql: "type = 'selection'"
    )

    // Time (mutually exclusive)
    static let today = SemanticFilter(
        id: "today", label: "Today", icon: "calendar",
        group: .time, sql: "date(createdAt, 'localtime') = date('now', 'localtime')"
    )
    static let thisWeek = SemanticFilter(
        id: "week", label: "This Week", icon: "calendar.badge.clock",
        // Start of week: go to next Sunday ('weekday 0'), then back 6 days to get current week's Sunday
        group: .time, sql: "date(createdAt, 'localtime') >= date('now', 'localtime', 'weekday 0', '-6 days')"
    )
    static let thisMonth = SemanticFilter(
        id: "month", label: "This Month", icon: "calendar.circle",
        // Start of current month in local timezone
        group: .time, sql: "date(createdAt, 'localtime') >= date('now', 'localtime', 'start of month')"
    )

    // Status (multi-select)
    static let hasTasks = SemanticFilter(
        id: "tasks", label: "Has Tasks", icon: "checklist",
        group: .status, sql: "tasks IS NOT NULL AND tasks != '' AND tasks != '[]'"
    )
    static let hasSummary = SemanticFilter(
        id: "summary", label: "Summarized", icon: "text.alignleft",
        group: .status, sql: "summary IS NOT NULL AND summary != ''"
    )
    static let failed = SemanticFilter(
        id: "failed", label: "Failed", icon: "exclamationmark.triangle",
        group: .status, sql: "transcriptionStatus = 'failed'"
    )
    static let hasAudio = SemanticFilter(
        id: "audio", label: "Has Audio", icon: "waveform.circle",
        group: .status, sql: "audioFilename IS NOT NULL"
    )

    // Source (multi-select)
    static let iphone = SemanticFilter(
        id: "iphone", label: "iPhone", icon: "iphone",
        group: .source, sql: "source = 'iphone'"
    )
    static let mac = SemanticFilter(
        id: "mac", label: "Mac", icon: "desktopcomputer",
        group: .source, sql: "source = 'mac'"
    )
    static let watch = SemanticFilter(
        id: "watch", label: "Watch", icon: "applewatch",
        group: .source, sql: "source = 'watch'"
    )
    static let live = SemanticFilter(
        id: "live", label: "Agent", icon: "bolt.horizontal.circle",
        group: .source, sql: "source = 'live'"
    )

    // Grouped for UI display
    static let typeFilters: [SemanticFilter] = [.all, .memos, .dictations, .captures, .notes]
    static let timeFilters: [SemanticFilter] = [.today, .thisWeek, .thisMonth]
    static let statusFilters: [SemanticFilter] = [.hasTasks, .hasSummary, .failed, .hasAudio]
    static let sourceFilters: [SemanticFilter] = [.iphone, .watch, .mac, .live]

    /// Default visible filters (shown in main chip bar)
    /// Note: Type filters (all, memos, dictations) are now in the title toggle
    static let defaultFilters: [SemanticFilter] = [.today, .thisWeek]
}

// MARK: - Filter State

@Observable
class RecordingFilterState {
    var activeFilters: Set<SemanticFilter> = [.all]
    var searchQuery: String = ""

    /// Date filter — mutually exclusive with time group filters (.today, .thisWeek, .thisMonth)
    var dateFilter: Date? = nil

    /// Select a filter without toggling it back off when it is already active.
    /// Useful for navigation-driven state restoration where entering a screen
    /// should be idempotent.
    func select(_ filter: SemanticFilter) {
        if filter.group.isExclusive {
            activeFilters = activeFilters.filter { $0.group != filter.group }

            // Time group filters are mutually exclusive with dateFilter.
            if filter.group == .time {
                dateFilter = nil
            }

            // "All" in type group means no type filter.
            if filter.id != "all" || filter.group != .type {
                activeFilters.insert(filter)
            }
        } else if !activeFilters.contains(filter) {
            activeFilters.insert(filter)
        }
    }

    /// Toggle a filter on/off
    func toggle(_ filter: SemanticFilter) {
        if filter.group.isExclusive {
            let wasActive = isActive(filter)

            // Remove other filters in same group. Re-selecting the same exclusive
            // filter leaves the group cleared, which returns the view to its
            // unfiltered/default state for that group.
            activeFilters = activeFilters.filter { $0.group != filter.group }

            // Time group filters are mutually exclusive with dateFilter
            if filter.group == .time {
                dateFilter = nil
            }

            guard !wasActive else { return }

            // "All" in type group means no type filter
            if filter.id != "all" || filter.group != .type {
                activeFilters.insert(filter)
            }
        } else {
            // Multi-select: toggle
            if activeFilters.contains(filter) {
                activeFilters.remove(filter)
            } else {
                activeFilters.insert(filter)
            }
        }
    }

    /// Set a specific date filter, clearing any time group filters
    func setDateFilter(_ date: Date) {
        dateFilter = date
        activeFilters = activeFilters.filter { $0.group != .time }
    }

    /// Clear the date filter
    func clearDateFilter() {
        dateFilter = nil
    }

    /// Check if a filter is active
    func isActive(_ filter: SemanticFilter) -> Bool {
        // "All" is active when no type filter is set
        if filter.id == "all" && filter.group == .type {
            return !activeFilters.contains(where: { $0.group == .type })
        }
        return activeFilters.contains(filter)
    }

    /// Clear all filters
    func clearAll() {
        activeFilters = []
        searchQuery = ""
        dateFilter = nil
    }

    /// Clear filters in a specific group
    func clearGroup(_ group: SemanticFilter.FilterGroup) {
        activeFilters = activeFilters.filter { $0.group != group }
    }

    /// Generate SQL WHERE clause from current state
    func toSQL() -> String {
        var clauses: [String] = []

        // Date filter (mutually exclusive with time group)
        if let date = dateFilter {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = formatter.string(from: date)
            clauses.append("(date(createdAt, 'localtime') = date('\(dateStr)'))")
        }

        // Group active filters by their group
        let byGroup = Dictionary(grouping: activeFilters) { $0.group }

        for (group, filters) in byGroup {
            // Skip "all" filter as it's just 1=1
            let validFilters = filters.filter { $0.id != "all" }
            guard !validFilters.isEmpty else { continue }

            // Skip time group if dateFilter is set (shouldn't happen, but safety)
            if group == .time && dateFilter != nil { continue }

            if group.isExclusive {
                // Exclusive groups: just use the one filter
                if let filter = validFilters.first {
                    clauses.append("(\(filter.sql))")
                }
            } else {
                // Multi-select groups: OR within group
                let groupSQL = validFilters.map { "(\($0.sql))" }.joined(separator: " OR ")
                clauses.append("(\(groupSQL))")
            }
        }

        // Search query
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let escaped = searchQuery
                .replacingOccurrences(of: "'", with: "''")
                .replacingOccurrences(of: "%", with: "\\%")
            clauses.append("(text LIKE '%\(escaped)%' ESCAPE '\\')")
        }

        return clauses.isEmpty ? "1=1" : clauses.joined(separator: " AND ")
    }

    /// Human-readable description of active filters
    var description: String {
        var parts: [String] = []

        if let date = dateFilter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            parts.append(formatter.string(from: date))
        }

        let byGroup = Dictionary(grouping: activeFilters) { $0.group }
        for (_, filters) in byGroup.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let labels = filters.map { $0.label }
            parts.append(contentsOf: labels)
        }

        if !searchQuery.isEmpty {
            parts.append("\"\(searchQuery)\"")
        }

        return parts.isEmpty ? "All Recordings" : parts.joined(separator: " + ")
    }

    /// Whether any filters are active (beyond default "All")
    var hasActiveFilters: Bool {
        !activeFilters.isEmpty || !searchQuery.isEmpty || dateFilter != nil
    }
}
