//
//  PerformanceInstrumentation.swift
//  Talkie
//
//  Native performance instrumentation using os_signpost
//  Single source of truth: os_signpost → Instruments + In-App View
//

import Foundation
import SwiftUI
import OSLog
import Observation

// MARK: - Signpost Configuration

/// Talkie performance signposting subsystem
let talkiePerformanceLog = OSLog(subsystem: "live.talkie.performance", category: .pointsOfInterest)

/// Signposter for UI performance tracking (for Instruments)
let talkieSignposter = OSSignposter(subsystem: "live.talkie.performance", category: .pointsOfInterest)

/// Logger for events readable via OSLogStore (for in-app Performance Monitor)
/// os_signpost may not be immediately queryable, so we also use os_log
let talkieEventLogger = Logger(subsystem: "live.talkie.performance", category: "Events")

// MARK: - Instrumentation Helpers

/// Instrument a database operation
///
/// Creates a signpost interval for database reads/writes.
/// Automatically tracks operation name and duration.
///
/// Usage:
/// ```swift
/// let memos = try await instrumentDatabaseRead(
///     section: "AllMemos",
///     operation: "fetchMemos"
/// ) {
///     try await repository.fetchMemos(...)
/// }
/// ```
func instrumentDatabaseRead<T>(
    section: String,
    operation: String,
    _ work: () async throws -> T
) async rethrows -> T {
    let id = talkieSignposter.makeSignpostID()
    let state = talkieSignposter.beginInterval("DatabaseRead", id: id)

    let result = try await work()

    talkieSignposter.endInterval("DatabaseRead", state, "\(section).\(operation)")

    return result
}

/// Instrument a user interaction (click, tap, etc.)
///
/// Creates a point-in-time signpost for user clicks.
///
/// Usage:
/// ```swift
/// trackClick(section: "AllMemos", component: "RefreshButton")
/// ```
@MainActor
func trackClick(section: String, component: String? = nil) {
    let eventName = component != nil ? "\(section).\(component!)" : section
    let id = talkieSignposter.makeSignpostID()

    // Emit a point-in-time event
    talkieSignposter.emitEvent("Click", id: id, "\(eventName)")
}

/// Track action completion (for sync operations)
@MainActor
func trackActionComplete(section: String, component: String, duration: TimeInterval) {
    let eventName = "\(section).\(component)"
    let id = talkieSignposter.makeSignpostID()

    talkieSignposter.emitEvent("ActionComplete", id: id, "\(eventName)")
}

// MARK: - SwiftUI View Modifier

struct InstrumentationModifier: ViewModifier {
    let section: String
    @State private var hasAppeared = false
    @State private var signpostState: OSSignpostIntervalState?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    let id = talkieSignposter.makeSignpostID()
                    let state = talkieSignposter.beginInterval("ViewLifecycle", id: id)
                    signpostState = state
                }
            }
            .onDisappear {
                if let state = signpostState {
                    talkieSignposter.endInterval("ViewLifecycle", state, "\(section)")
                    signpostState = nil
                }
            }
    }
}

extension View {
    /// Instrument performance for this section using os_signpost
    ///
    /// Usage:
    /// ```swift
    /// AllMemosView()
    ///     .instrument(section: "AllMemos")
    /// ```
    func instrument(section: String) -> some View {
        modifier(InstrumentationModifier(section: section))
    }
}

// MARK: - In-App Performance Viewer (Reads from OSLog)

/// Performance event parsed from OSLog signpost data
struct PerformanceEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: String
    let name: String
    let message: String
    let duration: TimeInterval?

    var icon: String {
        switch name {
        case "Click": return "🖱️"
        case "DB Read Complete": return "💾"
        case "Action Complete": return "📦"
        case "View Appeared": return "👁️"
        case "Section Ready": return "✅"
        default: return "•"
        }
    }

    var displayText: String {
        // Parse duration from message if present
        if let duration = duration {
            return "\(icon) [\(category)] \(name) (\(Int(duration * 1000))ms)"
        } else {
            return "\(icon) [\(category)] \(name) - \(message)"
        }
    }
}

/// Operation category for processing time breakdown
enum OperationCategory: String, CaseIterable {
    case database = "DB"
    case network = "Network"
    case llm = "LLM"
    case inference = "Inference"
    case engine = "Engine"
    case tts = "TTS"
    case processing = "Processing"
    case other = "Other"

    var color: Color {
        switch self {
        case .database: return .cyan
        case .network: return .orange
        case .llm: return .purple
        case .inference: return .pink
        case .engine: return .blue
        case .tts: return .mint
        case .processing: return .green
        case .other: return .gray
        }
    }
}

/// Individual operation (DB query, network call, LLM inference, etc.)
struct PerformanceOperation: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: OperationCategory
    let name: String
    let duration: TimeInterval

    /// Time relative to action start
    var relativeTime: TimeInterval = 0
}

/// User action with associated processing operations
struct PerformanceAction: Identifiable {
    let id = UUID()
    let timestamp: Date
    let actionType: String  // "Click", "Load", "Sort", etc.
    let actionName: String  // "Refresh button", "AllMemos section", "Sort by date"
    let context: String?    // Optional context (e.g., section name)

    var operations: [PerformanceOperation] = []
    var completedAt: Date?
    var renderedAt: Date?   // When view actually appeared on screen
    var error: String?      // Error message if action failed
    var warnings: [String] = []  // Warnings/errors logged during action

    /// Total processing time (sum of all operations)
    var processingTime: TimeInterval {
        operations.compactMap { $0.duration }.reduce(0, +)
    }

    /// Duration from start to completion
    var totalDuration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(timestamp)
    }

    /// Duration from action start to view rendered (Time to Interactive)
    var timeToInteractive: TimeInterval? {
        guard let rendered = renderedAt else { return nil }
        return rendered.timeIntervalSince(timestamp)
    }

    /// Duration spent rendering (after processing complete)
    var renderingTime: TimeInterval? {
        guard let completed = completedAt, let rendered = renderedAt else { return nil }
        return rendered.timeIntervalSince(completed)
    }

    var isComplete: Bool {
        completedAt != nil
    }

    var isRendered: Bool {
        renderedAt != nil
    }

    /// Operations grouped by category
    var operationsByCategory: [OperationCategory: [PerformanceOperation]] {
        Dictionary(grouping: operations, by: { $0.category })
    }

    /// Breakdown summary text
    var breakdownSummary: String {
        let groups = operationsByCategory
        var parts: [String] = []

        // Show in priority order
        for category in [OperationCategory.llm, .tts, .inference, .network, .database, .engine, .processing] {
            if let ops = groups[category], !ops.isEmpty {
                let totalTime = ops.compactMap { $0.duration }.reduce(0, +)
                let count = ops.count
                if count > 1 {
                    parts.append("\(count) \(category.rawValue) (\(Int(totalTime * 1000))ms)")
                } else {
                    parts.append("\(category.rawValue) (\(Int(totalTime * 1000))ms)")
                }
            }
        }

        return parts.isEmpty ? "—" : parts.joined(separator: " • ")
    }
}

// MARK: - Stats Model

struct PerformanceStats {
    let totalActions: Int
    let recentActions: Int
    let avgProcessingTime: TimeInterval
    let minProcessingTime: TimeInterval
    let maxProcessingTime: TimeInterval
    let p50: TimeInterval
    let p95: TimeInterval
    let p99: TimeInterval
    let categoryBreakdown: [OperationCategory: TimeInterval]
}

/// Performance monitor tracking user actions and processing time
@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    var actions: [PerformanceAction] = []
    var isMonitoring = true

    // Metrics
    var totalActions = 0
    var averageProcessingTime: TimeInterval = 0

    // Track active action for associating operations
    private var activeActionID: UUID?

    private init() {}

    /// Start a new action (Load, Click, Sort, etc.)
    func startAction(type: String, name: String, context: String? = nil) {
        let action = PerformanceAction(
            timestamp: Date(),
            actionType: type,
            actionName: name,
            context: context
        )

        actions.insert(action, at: 0) // Most recent first
        activeActionID = action.id

        print("📊 PerformanceMonitor: Action started - [\(type)] \(name)")

        // Keep last 50 actions
        if actions.count > 50 {
            actions.removeLast(actions.count - 50)
        }
    }

    /// Complete the current action
    func completeAction() {
        guard let actionID = activeActionID,
              let index = actions.firstIndex(where: { $0.id == actionID }) else {
            return
        }

        var action = actions[index]
        action.completedAt = Date()
        actions[index] = action

        totalActions += 1
        updateMetrics()

        print("📊 PerformanceMonitor: Action completed - \(action.actionName) (processing: \(Int(action.processingTime * 1000))ms)")

        activeActionID = nil
    }

    /// Record an error for the current action
    func recordError(_ error: String) {
        guard let actionID = activeActionID,
              let index = actions.firstIndex(where: { $0.id == actionID }) else {
            // No active action - log error anyway
            print("❌ Action error: \(error)")
            return
        }

        var action = actions[index]
        action.error = error
        action.completedAt = Date()  // Mark as completed (failed)
        actions[index] = action

        print("❌ Action error: \(error)")

        activeActionID = nil
    }

    /// Record a warning/error during the current action (non-fatal)
    func recordWarning(_ warning: String) {
        guard let actionID = activeActionID,
              let index = actions.firstIndex(where: { $0.id == actionID }) else {
            // No active action - ignore warning (or could log globally)
            return
        }

        var action = actions[index]
        action.warnings.append(warning)
        actions[index] = action

        print("⚠️ Action warning (\(action.actionName)): \(warning)")
    }

    /// Mark the most recent action as rendered (when view appears)
    func markActionAsRendered(actionName: String) {
        // Find the most recent action matching this name
        guard let index = actions.firstIndex(where: { $0.actionName == actionName && $0.renderedAt == nil }) else {
            return
        }

        var action = actions[index]
        action.renderedAt = Date()
        actions[index] = action

        let tti = action.timeToInteractive ?? 0
        let renderTime = action.renderingTime ?? 0

        print("🎨 PerformanceMonitor: View rendered - \(action.actionName) (TTI: \(Int(tti * 1000))ms, render: \(Int(renderTime * 1000))ms)")
    }

    /// Add an operation to the current active action
    func addOperation(category: OperationCategory, name: String, duration: TimeInterval) {
        guard let actionID = activeActionID,
              let index = actions.firstIndex(where: { $0.id == actionID }) else {
            // Silently ignore operations without an active action - this is normal for background work
            return
        }

        var action = actions[index]

        // Calculate relative time from action start
        let relativeTime = Date().timeIntervalSince(action.timestamp)

        var op = PerformanceOperation(
            timestamp: Date(),
            category: category,
            name: name,
            duration: duration
        )
        op.relativeTime = relativeTime

        action.operations.append(op)
        actions[index] = action

        print("📊 PerformanceMonitor: [\(category.rawValue)] \(name) (\(Int(duration * 1000))ms) @ +\(Int(relativeTime * 1000))ms")
    }

    /// Legacy event handler for backwards compatibility
    func addEvent(category: String, name: String, message: String, duration: TimeInterval? = nil) {
        // Handle section lifecycle
        if category == "Section" {
            if name == "Appeared" {
                startAction(type: "Load", name: message, context: nil)
            } else if name == "Disappeared" {
                completeAction()
            }
        }
        // Handle operations
        else if let duration = duration {
            let opCategory = mapToOperationCategory(category: category)
            addOperation(category: opCategory, name: name, duration: duration)
        }
    }

    /// Map event category to operation category
    private func mapToOperationCategory(category: String) -> OperationCategory {
        switch category {
        case "Database": return .database
        case "Network": return .network
        case "LLM": return .llm
        case "Inference": return .inference
        case "Engine": return .engine
        case "TTS": return .tts
        case "Task", "Processing": return .processing
        default: return .other
        }
    }

    private func updateMetrics() {
        let completedActions = actions.filter { $0.isComplete }
        if !completedActions.isEmpty {
            let totalProcessing = completedActions.map { $0.processingTime }.reduce(0, +)
            averageProcessingTime = totalProcessing / Double(completedActions.count)
        }
    }

    /// Clear all events
    func clear() {
        actions.removeAll()
        totalActions = 0
        averageProcessingTime = 0
        activeActionID = nil
    }
}

// MARK: - Performance Debug View

struct PerformanceDebugView: View {
    // Access singleton directly without property wrapper to avoid retain cycle
    private let monitor = PerformanceMonitor.shared

    var body: some View {
        MonitorContentView(monitor: monitor)
            .frame(width: 1200, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MonitorContentView: View {
    var monitor: PerformanceMonitor

    @State private var expandedActions: Set<UUID> = []
    @State private var filterActionType: String? = nil
    @State private var filterCategory: OperationCategory? = nil
    @State private var searchText = ""
    @State private var sortMode: SortMode = .newestFirst
    @State private var showStats = true

    enum SortMode: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case slowestFirst = "Slowest First"
        case fastestFirst = "Fastest First"
        case mostOps = "Most Operations"
    }

    var filteredActions: [PerformanceAction] {
        var actions = monitor.actions

        // Filter by action type
        if let type = filterActionType {
            actions = actions.filter { $0.actionType == type }
        }

        // Filter by operation category
        if let category = filterCategory {
            actions = actions.filter { action in
                action.operations.contains { $0.category == category }
            }
        }

        // Search filter
        if !searchText.isEmpty {
            actions = actions.filter { action in
                action.actionName.localizedCaseInsensitiveContains(searchText) ||
                action.actionType.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        switch sortMode {
        case .newestFirst:
            return actions
        case .oldestFirst:
            return actions.reversed()
        case .slowestFirst:
            return actions.sorted { $0.processingTime > $1.processingTime }
        case .fastestFirst:
            return actions.sorted { $0.processingTime < $1.processingTime }
        case .mostOps:
            return actions.sorted { $0.operations.count > $1.operations.count }
        }
    }

    var stats: PerformanceStats {
        let times = monitor.actions.map { $0.processingTime }.filter { $0 > 0 }
        return PerformanceStats(
            totalActions: monitor.totalActions,
            recentActions: monitor.actions.count,
            avgProcessingTime: times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count),
            minProcessingTime: times.min() ?? 0,
            maxProcessingTime: times.max() ?? 0,
            p50: percentile(times, 0.5),
            p95: percentile(times, 0.95),
            p99: percentile(times, 0.99),
            categoryBreakdown: calculateCategoryBreakdown()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Stats panel (collapsible)
            if showStats {
                statsPanel
                Divider()
            }

            // Filters & controls
            controlsView

            Divider()

            // Actions list
            if filteredActions.isEmpty {
                emptyStateView
            } else {
                actionsListView
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PERFORMANCE MONITOR")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("INSTRUMENTED")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { showStats.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                    Text(showStats ? "Hide Stats" : "Show Stats")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)

            TalkieButtonSync("CopyAll", section: "Performance") {
                copyAllToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                    Text("Copy All")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)

            TalkieButtonSync("Clear", section: "Performance") {
                monitor.clear()
                expandedActions.removeAll()
            } label: {
                Text("Clear All")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // All metrics in a flowing grid
            FlowLayout(spacing: 8) {
                statCard(title: "TOTAL", value: "\(stats.totalActions)", color: .blue)
                statCard(title: "AVG", value: formatDuration(stats.avgProcessingTime), color: .green)
                statCard(title: "MIN", value: formatDuration(stats.minProcessingTime), color: .cyan)
                statCard(title: "MAX", value: formatDuration(stats.maxProcessingTime), color: .red)
                statCard(title: "P50", value: formatDuration(stats.p50), color: .orange)
                statCard(title: "P95", value: formatDuration(stats.p95), color: .pink)
                statCard(title: "P99", value: formatDuration(stats.p99), color: .purple)
            }

            // Category breakdown
            if !stats.categoryBreakdown.isEmpty {
                HStack(spacing: 12) {
                    Text("BY CATEGORY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(Array(stats.categoryBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { category, time in
                        categoryChip(category: category, time: time)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }

    private func categoryChip(category: OperationCategory, time: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(categoryColor(category))
                .frame(width: 6, height: 6)
            Text(category.rawValue.uppercased())
                .font(.system(size: 9, weight: .medium))
            Text(formatDuration(time))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(categoryColor(category).opacity(0.15))
        )
    }

    private var controlsView: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Search actions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(width: 200)

            // Filter by action type
            Menu {
                Button("All Actions") {
                    filterActionType = nil
                }
                ForEach(Array(Set(monitor.actions.map { $0.actionType })).sorted(), id: \.self) { type in
                    Button(type) {
                        filterActionType = type
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filterActionType ?? "All Types")
                        .font(.system(size: 10))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)

            // Filter by category
            Menu {
                Button("All Categories") {
                    filterCategory = nil
                }
                ForEach([OperationCategory.database, .network, .llm, .inference, .engine, .tts, .processing], id: \.self) { category in
                    Button(category.rawValue.capitalized) {
                        filterCategory = category
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let cat = filterCategory {
                        Circle()
                            .fill(categoryColor(cat))
                            .frame(width: 6, height: 6)
                    }
                    Text(filterCategory?.rawValue.capitalized ?? "All Categories")
                        .font(.system(size: 10))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            // Sort
            Menu {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button(action: { sortMode = mode }) {
                        HStack {
                            Text(mode.rawValue)
                            if sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9))
                    Text(sortMode.rawValue)
                        .font(.system(size: 10))
                }
            }
            .menuStyle(.borderlessButton)

            Text("\(filteredActions.count) actions")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var actionsListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                actionHeaderRow

                // Actions
                ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                    expandableActionRow(action: action, index: index + 1)
                    if index < filteredActions.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var actionHeaderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundColor(.clear)
                .frame(width: 12)

            Text("#")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)

            Text("ACTION")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .leading)

            Text("TOTAL TIME")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text("WHAT TOOK TIME")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func expandableActionRow(action: PerformanceAction, index: Int) -> some View {
        let isExpanded = expandedActions.contains(action.id)

        return VStack(spacing: 0) {
            // Main row
            Button(action: {
                if isExpanded {
                    expandedActions.remove(action.id)
                } else {
                    expandedActions.insert(action.id)
                }
            }) {
                HStack(spacing: 8) {
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(action.operations.isEmpty ? .clear : .secondary)
                        .frame(width: 12)

                    // Index
                    Text("#\(index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)

                    // Action (type + name)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(action.actionType.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(actionTypeColor(action.actionType))
                                )

                            Text(action.actionName)
                                .font(.system(size: 11, weight: .medium))

                            // Warning badge
                            if !action.warnings.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                    Text("\(action.warnings.count)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.15))
                                )
                            }
                        }

                        if let context = action.context {
                            Text(context)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 200, alignment: .leading)

                    // Total Time (Time to Interactive)
                    if let tti = action.timeToInteractive {
                        Text(formatDuration(tti))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(processingTimeColor(tti))
                            .frame(width: 80, alignment: .leading)
                    } else if action.processingTime > 0 {
                        Text(formatDuration(action.processingTime))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(processingTimeColor(action.processingTime))
                            .frame(width: 80, alignment: .leading)
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                    }

                    // Breakdown with mini bar chart
                    breakdownView(for: action)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.05) : Color.clear)

            // Expanded details
            if isExpanded {
                if !action.operations.isEmpty {
                    operationsDetailView(for: action)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Show warnings if any
                if !action.warnings.isEmpty {
                    warningsDetailView(for: action)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func breakdownView(for action: PerformanceAction) -> some View {
        HStack(spacing: 8) {
            // Show error if action failed
            if let error = action.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.red)

                    Text("ERROR:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)

                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            } else {
                // Show operation categories with clear labels
                ForEach(Array(action.operationsByCategory.keys.sorted(by: { k1, k2 in
                    (action.operationsByCategory[k1] ?? []).reduce(0.0) { $0 + $1.duration } >
                    (action.operationsByCategory[k2] ?? []).reduce(0.0) { $0 + $1.duration }
                })), id: \.self) { category in
                    let ops = action.operationsByCategory[category] ?? []
                    let totalTime = ops.reduce(0.0) { $0 + $1.duration }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(categoryColor(category))
                            .frame(width: 6, height: 6)

                        Text(category.rawValue.capitalized + ":")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)

                        Text("\(Int(totalTime * 1000))ms")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(categoryColor(category))

                        Text("(\(ops.count) \(ops.count == 1 ? "query" : "queries"))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                // Show SwiftUI/rendering time if we have TTI
                if let tti = action.timeToInteractive {
                    let swiftuiTime = tti - action.processingTime
                    if swiftuiTime > 0.001 { // Only show if meaningful (>1ms)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 6, height: 6)

                            Text("SwiftUI:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary)

                            Text("\(Int(swiftuiTime * 1000))ms")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.purple)

                            Text("(layout + paint)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Show "Instant" if nothing took time
                if action.operations.isEmpty && action.timeToInteractive == nil {
                    Text("Instant")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func operationsDetailView(for action: PerformanceAction) -> some View {
        VStack(spacing: 0) {
            // Timeline visualization
            timelineView(for: action)

            Divider()
                .padding(.horizontal, 16)

            // Operations table
            VStack(spacing: 0) {
                // Operations header
                HStack(spacing: 8) {
                    Text("OPERATION")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 200, alignment: .leading)

                    Text("DURATION")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Text("START")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Text("% OF TOTAL")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                // Operations
                ForEach(action.operations) { operation in
                    operationRow(operation: operation, totalTime: action.processingTime)
                }
            }
        }
        .padding(.bottom, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func warningsDetailView(for action: PerformanceAction) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)

                    Text("WARNINGS (\(action.warnings.count))")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Warning list
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(action.warnings.enumerated()), id: \.offset) { index, warning in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 20, alignment: .leading)

                            Text(warning)
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(4)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func timelineView(for action: PerformanceAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIMELINE")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 60)

            GeometryReader { geometry in
                let maxTime = action.processingTime > 0 ? action.processingTime : 0.001
                let width = geometry.size.width - 120

                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 20)

                    // Operations as colored bars
                    ForEach(action.operations) { operation in
                        let startX = (operation.relativeTime / maxTime) * width
                        let opWidth = ((operation.duration) / maxTime) * width

                        Rectangle()
                            .fill(categoryColor(operation.category))
                            .frame(width: max(opWidth, 2), height: 20)
                            .offset(x: startX)
                            .help("\(operation.name): \(formatDuration(operation.duration))")
                    }
                }
                .cornerRadius(4)
                .padding(.horizontal, 60)
            }
            .frame(height: 20)
        }
        .padding(.vertical, 8)
    }

    private func operationRow(operation: PerformanceOperation, totalTime: TimeInterval) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(categoryColor(operation.category))
                    .frame(width: 6, height: 6)

                Text(operation.category.rawValue.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                Text(operation.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)

            Text(formatDuration(operation.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(processingTimeColor(operation.duration))
                .frame(width: 80, alignment: .leading)

            Text("+\(formatDuration(operation.relativeTime))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            let percentage = totalTime > 0 ? (operation.duration) / totalTime * 100 : 0
            HStack(spacing: 4) {
                Text("\(Int(percentage))%")
                    .font(.system(size: 9, design: .monospaced))

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        Rectangle()
                            .fill(categoryColor(operation.category))
                            .frame(width: geo.size.width * CGFloat(percentage / 100), height: 4)
                    }
                    .cornerRadius(2)
                }
                .frame(height: 4)
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 4)
    }

    private func actionTypeColor(_ type: String) -> Color {
        switch type {
        case "Load": return .blue
        case "Click": return .green
        case "Sort": return .orange
        case "Search": return .purple
        case "Filter": return .pink
        default: return .gray
        }
    }

    private func categoryColor(_ category: OperationCategory) -> Color {
        switch category {
        case .database: return .blue
        case .network: return .orange
        case .llm: return .purple
        case .inference: return .pink
        case .engine: return .cyan
        case .tts: return .mint
        case .processing: return .green
        case .other: return .gray
        }
    }

    private func processingTimeColor(_ time: TimeInterval) -> Color {
        let ms = time * 1000
        if ms >= 800 { return .red }      // Red: 800ms+ (feels slow)
        if ms >= 400 { return .orange }   // Orange: 400-800ms (noticeable)
        return .green                      // Green: <400ms (feels instant)
    }

    private func percentile(_ values: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * p)
        return sorted[min(index, sorted.count - 1)]
    }

    private func calculateCategoryBreakdown() -> [OperationCategory: TimeInterval] {
        var breakdown: [OperationCategory: TimeInterval] = [:]
        for action in monitor.actions {
            for (category, ops) in action.operationsByCategory {
                let total = ops.reduce(0.0) { $0 + $1.duration }
                breakdown[category, default: 0] += total
            }
        }
        return breakdown
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No actions yet")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Navigate between sections to see performance data")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    /// Copy all performance data to clipboard as markdown
    private func copyAllToClipboard() {
        let actions = filteredActions

        // Compute stats
        let times = actions.compactMap { $0.timeToInteractive ?? $0.processingTime }.filter { $0 > 0 }
        let avgTime = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)

        // Generate markdown export
        var markdown = "# Performance Monitor Export\n\n"

        // Timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        markdown += "**Exported:** \(dateFormatter.string(from: Date()))\n\n"

        // Summary stats
        markdown += "## Summary\n\n"
        markdown += "- **Total Actions:** \(monitor.totalActions)\n"
        markdown += "- **Showing:** \(actions.count) actions\n"
        markdown += "- **Average Time:** \(formatDuration(avgTime))\n"
        markdown += "- **Min Time:** \(formatDuration(times.min() ?? 0))\n"
        markdown += "- **Max Time:** \(formatDuration(times.max() ?? 0))\n"
        markdown += "- **P50 (Median):** \(formatDuration(percentile(times, 0.5)))\n"
        markdown += "- **P95:** \(formatDuration(percentile(times, 0.95)))\n"
        markdown += "- **P99:** \(formatDuration(percentile(times, 0.99)))\n\n"

        // Time by category
        let categoryBreakdown = calculateCategoryBreakdown()
        if !categoryBreakdown.isEmpty {
            markdown += "## Time by Category\n\n"
            for (category, time) in categoryBreakdown.sorted(by: { $0.value > $1.value }) {
                markdown += "- **\(category.rawValue.capitalized):** \(formatDuration(time))\n"
            }
            markdown += "\n"
        }

        // Actions table
        markdown += "## Actions (\(actions.count) total)\n\n"
        markdown += "| # | Type | Action | Total Time | What Took Time |\n"
        markdown += "|---|------|--------|-----------|----------------|\n"

        for (index, action) in actions.enumerated() {
            let num = index + 1
            let type = action.actionType
            let name = action.actionName
            let totalTime = formatDuration(action.timeToInteractive ?? action.processingTime)

            // Build breakdown text
            var breakdown = ""

            if let error = action.error {
                breakdown = "❌ ERROR: \(error)"
            } else {
                var parts: [String] = []

                // DB operations
                if let dbOps = action.operationsByCategory[.database], !dbOps.isEmpty {
                    let dbTime = dbOps.reduce(0.0) { $0 + $1.duration }
                    parts.append("DB: \(formatDuration(dbTime)) (\(dbOps.count) queries)")
                }

                // Network operations
                if let netOps = action.operationsByCategory[.network], !netOps.isEmpty {
                    let netTime = netOps.reduce(0.0) { $0 + $1.duration }
                    parts.append("Network: \(formatDuration(netTime))")
                }

                // LLM operations
                if let llmOps = action.operationsByCategory[.llm], !llmOps.isEmpty {
                    let llmTime = llmOps.reduce(0.0) { $0 + $1.duration }
                    parts.append("LLM: \(formatDuration(llmTime))")
                }

                // SwiftUI rendering
                if let tti = action.timeToInteractive {
                    let swiftuiTime = tti - action.processingTime
                    if swiftuiTime > 0.001 {
                        parts.append("SwiftUI: \(formatDuration(swiftuiTime))")
                    }
                }

                breakdown = parts.isEmpty ? "—" : parts.joined(separator: " • ")
            }

            // Add warnings count if any
            let warningNote = action.warnings.isEmpty ? "" : " ⚠️\(action.warnings.count)"
            markdown += "| \(num) | \(type) | \(name)\(warningNote) | \(totalTime) | \(breakdown) |\n"
        }

        // Add warnings section if any actions have warnings
        let actionsWithWarnings = actions.filter { !$0.warnings.isEmpty }
        if !actionsWithWarnings.isEmpty {
            markdown += "\n## Warnings\n\n"
            for action in actionsWithWarnings {
                markdown += "### \(action.actionName) (\(action.warnings.count) warnings)\n\n"
                for (index, warning) in action.warnings.enumerated() {
                    markdown += "\(index + 1). \(warning)\n"
                }
                markdown += "\n"
            }
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)

        print("📋 Copied \(actions.count) performance actions to clipboard")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 0.001 {
            return "—"
        } else if duration < 1.0 {
            return "\(Int(duration * 1000))ms"
        } else {
            return String(format: "%.2fs", duration)
        }
    }

    private func loadTimeColor(_ duration: TimeInterval) -> Color {
        if duration < 0.1 { return .green }
        if duration < 0.5 { return .orange }
        return .red
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    PerformanceDebugView()
}
