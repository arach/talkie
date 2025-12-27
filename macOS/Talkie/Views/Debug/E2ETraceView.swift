//
//  E2ETraceView.swift
//  Talkie
//
//  End-to-end performance trace viewer for the Talkie suite.
//  Shows dictation flows across TalkieLive → TalkieEngine with drill-down.
//

import SwiftUI

// MARK: - User-Controlled Steps

/// Steps that represent user action time, not system latency
/// These are excluded from bottleneck detection and shown differently
private let userControlledSteps: Set<String> = [
    "recording",
    "record",
    "user_input",
    "speaking"
]

/// Check if a step name represents user-controlled time
private func isUserControlledStep(_ name: String) -> Bool {
    userControlledSteps.contains(name.lowercased())
}

// MARK: - Trace Data Models

/// A single step in any trace (Live or Engine)
struct TraceStep: Identifiable {
    let id = UUID()
    let name: String
    let startMs: Int
    let durationMs: Int
    let metadata: String?

    var endMs: Int { startMs + durationMs }

    /// Whether this step is user-controlled (not system latency)
    var isUserControlled: Bool {
        isUserControlledStep(name)
    }
}

/// Scope identifier for drill-down
enum TraceScope: String, CaseIterable {
    case live = "Live"
    case engine = "Engine"

    var color: Color {
        switch self {
        case .live: return Color(red: 0.7, green: 0.5, blue: 1.0)   // Purple
        case .engine: return Color(red: 1.0, green: 0.6, blue: 0.3) // Orange
        }
    }

    var icon: String {
        switch self {
        case .live: return "menubar.rectangle"
        case .engine: return "gearshape.fill"
        }
    }
}

/// Trace from a single scope (Live or Engine)
struct ScopeTrace: Identifiable {
    let id = UUID()
    let scope: TraceScope
    let traceId: String
    let timestamp: Date
    let totalMs: Int
    let steps: [TraceStep]

    /// System latency (excludes user-controlled time like recording)
    var systemLatencyMs: Int {
        steps.filter { !$0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// User-controlled time (recording, etc.)
    var userTimeMs: Int {
        steps.filter { $0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// Bottleneck - only considers system steps, never user-controlled time
    var bottleneck: TraceStep? {
        steps.filter { !$0.isUserControlled }.max(by: { $0.durationMs < $1.durationMs })
    }

    var stepsSummary: String {
        steps.map { "\($0.name):\($0.durationMs)ms" }.joined(separator: " → ")
    }
}

/// End-to-end trace combining Live and Engine scopes
struct E2ETrace: Identifiable {
    let id = UUID()
    let timestamp: Date
    let externalRefId: String?

    var liveTrace: ScopeTrace?
    var engineTrace: ScopeTrace?

    /// Total end-to-end duration (includes user time)
    var totalMs: Int {
        (liveTrace?.totalMs ?? 0) + (engineTrace?.totalMs ?? 0)
    }

    /// System latency only (excludes user-controlled time like recording)
    var systemLatencyMs: Int {
        (liveTrace?.systemLatencyMs ?? 0) + (engineTrace?.systemLatencyMs ?? 0)
    }

    /// User-controlled time (recording, etc.)
    var userTimeMs: Int {
        (liveTrace?.userTimeMs ?? 0) + (engineTrace?.userTimeMs ?? 0)
    }

    /// Check if we have both scopes
    var isComplete: Bool {
        liveTrace != nil && engineTrace != nil
    }

    /// Summary for display
    var summary: String {
        var parts: [String] = []
        if let live = liveTrace {
            parts.append("Live: \(live.totalMs)ms")
        }
        if let engine = engineTrace {
            parts.append("Engine: \(engine.totalMs)ms")
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Trace Parser

/// Parses trace summaries from log file events
struct TraceParser {

    /// Parse a Live trace from log detail
    /// Format: "[traceId] Xms total: step1=Xms, step2=Xms, step3=Xms"
    static func parseLiveTrace(detail: String, timestamp: Date, traceId: String?) -> ScopeTrace? {
        var steps: [TraceStep] = []
        var currentStartMs = 0
        var extractedTraceId = traceId

        var workingDetail = detail

        // Extract trace ID from brackets at start: "[abc12345]"
        if let bracketRange = detail.range(of: #"^\[([a-zA-Z0-9\-]+)\]"#, options: .regularExpression) {
            let match = String(detail[bracketRange])
            extractedTraceId = String(match.dropFirst().dropLast())
            workingDetail = String(detail[bracketRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Skip past "Xms total: " prefix if present
        if let colonRange = workingDetail.range(of: "total:") {
            workingDetail = String(workingDetail[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Parse steps: "step1=Xms, step2=Xms, step3=Xms"
        let parts = workingDetail.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // Parse "name=Xms"
            let components = trimmed.components(separatedBy: "=")
            guard components.count >= 2 else { continue }

            let name = components[0].trimmingCharacters(in: .whitespaces)
            let msString = components[1]
                .replacingOccurrences(of: "ms", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let durationMs = Int(msString), !name.isEmpty else { continue }

            steps.append(TraceStep(
                name: name,
                startMs: currentStartMs,
                durationMs: durationMs,
                metadata: nil
            ))
            currentStartMs += durationMs
        }

        guard !steps.isEmpty else { return nil }

        return ScopeTrace(
            scope: .live,
            traceId: extractedTraceId ?? UUID().uuidString,
            timestamp: timestamp,
            totalMs: currentStartMs,
            steps: steps
        )
    }

    /// Parse an Engine trace from log detail
    /// Format: "[traceId] Xms total: step1=Xms, step2=Xms" or similar
    static func parseEngineTrace(detail: String, timestamp: Date, traceId: String?) -> ScopeTrace? {
        var steps: [TraceStep] = []
        var currentStartMs = 0
        var extractedTraceId = traceId

        var workingDetail = detail

        // Extract trace ID from brackets at start
        if let bracketRange = detail.range(of: #"^\[([a-zA-Z0-9\-]+)\]"#, options: .regularExpression) {
            let match = String(detail[bracketRange])
            extractedTraceId = String(match.dropFirst().dropLast())
            workingDetail = String(detail[bracketRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Skip past "Xms total: " or "Xms: " prefix if present
        if let colonRange = workingDetail.range(of: "total:") {
            workingDetail = String(workingDetail[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let colonRange = workingDetail.range(of: ":") {
            // Also handle simpler "Xms: step1=..." format
            let beforeColon = String(workingDetail[..<colonRange.lowerBound])
            if beforeColon.hasSuffix("ms") {
                workingDetail = String(workingDetail[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Parse steps: "step1=Xms, step2=Xms"
        let parts = workingDetail.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let components = trimmed.components(separatedBy: "=")
            guard components.count >= 2 else { continue }

            let name = components[0].trimmingCharacters(in: .whitespaces)
            let msString = components[1]
                .replacingOccurrences(of: "ms", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let durationMs = Int(msString), !name.isEmpty else { continue }

            steps.append(TraceStep(
                name: name,
                startMs: currentStartMs,
                durationMs: durationMs,
                metadata: nil
            ))
            currentStartMs += durationMs
        }

        guard !steps.isEmpty else { return nil }

        return ScopeTrace(
            scope: .engine,
            traceId: extractedTraceId ?? UUID().uuidString,
            timestamp: timestamp,
            totalMs: currentStartMs,
            steps: steps
        )
    }

    /// Extract externalRefId from log detail if present
    static func extractRefId(from detail: String) -> String? {
        // Look for pattern like "refId:abc12345" or "[abc12345]"
        if let range = detail.range(of: #"refId:([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let match = String(detail[range])
            return String(match.dropFirst(6)) // Remove "refId:"
        }
        if let range = detail.range(of: #"\[([a-zA-Z0-9\-]{8})\]"#, options: .regularExpression) {
            let match = String(detail[range])
            return String(match.dropFirst().dropLast()) // Remove brackets
        }
        return nil
    }
}

// MARK: - E2E Trace Manager

@MainActor
@Observable
class E2ETraceManager {
    static let shared = E2ETraceManager()

    var traces: [E2ETrace] = []
    var isLoading = false
    var lastRefresh: Date?

    private init() {}

    /// Load and correlate traces from all sources
    func loadTraces() {
        isLoading = true

        Task.detached { [weak self] in
            // Load events from both sources
            let liveEvents = LogFileManager.shared.loadEventsFrom(source: .talkieLive, date: Date(), limit: 200)
            let engineEvents = LogFileManager.shared.loadEventsFrom(source: .talkieEngine, date: Date(), limit: 200)

            // Parse traces
            var liveTraces: [String: ScopeTrace] = [:] // keyed by refId or timestamp
            var engineTraces: [String: ScopeTrace] = [:]
            var e2eTraces: [E2ETrace] = []

            // Parse Live traces
            for event in liveEvents {
                guard event.message.contains("Trace complete") || event.message.contains("trace") else { continue }
                guard let detail = event.detail else { continue }

                let refId = TraceParser.extractRefId(from: detail)
                if let trace = TraceParser.parseLiveTrace(detail: detail, timestamp: event.timestamp, traceId: refId) {
                    let key = refId ?? event.timestamp.timeIntervalSince1970.description
                    liveTraces[key] = trace
                }
            }

            // Parse Engine traces
            for event in engineEvents {
                guard event.message.contains("Trace complete") || event.message.contains("trace") || event.message.contains("Transcription") else { continue }
                guard let detail = event.detail else { continue }

                let refId = TraceParser.extractRefId(from: detail)
                if let trace = TraceParser.parseEngineTrace(detail: detail, timestamp: event.timestamp, traceId: refId) {
                    let key = refId ?? event.timestamp.timeIntervalSince1970.description
                    engineTraces[key] = trace
                }
            }

            // Correlate by refId
            var usedEngineKeys = Set<String>()
            for (key, liveTrace) in liveTraces {
                var e2e = E2ETrace(
                    timestamp: liveTrace.timestamp,
                    externalRefId: key.count == 8 ? key : nil,
                    liveTrace: liveTrace
                )

                // Try to find matching engine trace
                if let engineTrace = engineTraces[key] {
                    e2e.engineTrace = engineTrace
                    usedEngineKeys.insert(key)
                }

                e2eTraces.append(e2e)
            }

            // Add orphan engine traces (no matching Live)
            for (key, engineTrace) in engineTraces where !usedEngineKeys.contains(key) {
                let e2e = E2ETrace(
                    timestamp: engineTrace.timestamp,
                    externalRefId: key.count == 8 ? key : nil,
                    liveTrace: nil,
                    engineTrace: engineTrace
                )
                e2eTraces.append(e2e)
            }

            // Sort by timestamp (newest first)
            e2eTraces.sort { $0.timestamp > $1.timestamp }

            await MainActor.run { [weak self] in
                self?.traces = e2eTraces
                self?.isLoading = false
                self?.lastRefresh = Date()
            }
        }
    }

    func clear() {
        traces.removeAll()
        lastRefresh = nil
    }
}

// MARK: - E2E Trace View

struct E2ETraceView: View {
    @State private var manager = E2ETraceManager.shared
    @State private var expandedTraces: Set<UUID> = []
    @State private var selectedScope: TraceScope? = nil
    @State private var showOnlyComplete = false

    var filteredTraces: [E2ETrace] {
        var result = manager.traces

        if showOnlyComplete {
            result = result.filter { $0.isComplete }
        }

        if let scope = selectedScope {
            result = result.filter { trace in
                switch scope {
                case .live: return trace.liveTrace != nil
                case .engine: return trace.engineTrace != nil
                }
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Controls
            controlsView

            Divider()

            // Content
            if manager.isLoading {
                loadingView
            } else if filteredTraces.isEmpty {
                emptyStateView
            } else {
                traceListView
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if manager.traces.isEmpty {
                manager.loadTraces()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("END-TO-END TRACE VIEWER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("CROSS-APP TRACING")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let lastRefresh = manager.lastRefresh {
                Text("Updated \(lastRefresh, formatter: timeFormatter)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Button(action: { manager.loadTraces() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Refresh")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .disabled(manager.isLoading)

            Button(action: { manager.clear() }) {
                Text("Clear")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 12) {
            // Scope filter
            Menu {
                Button("All Scopes") {
                    selectedScope = nil
                }
                Divider()
                ForEach(TraceScope.allCases, id: \.self) { scope in
                    Button(action: { selectedScope = scope }) {
                        HStack {
                            Image(systemName: scope.icon)
                            Text(scope.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let scope = selectedScope {
                        Circle()
                            .fill(scope.color)
                            .frame(width: 6, height: 6)
                        Text(scope.rawValue)
                    } else {
                        Text("All Scopes")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)

            // Complete only toggle
            Toggle(isOn: $showOnlyComplete) {
                Text("Complete only")
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            Spacer()

            Text("\(filteredTraces.count) traces")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Trace List

    private var traceListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                traceHeaderRow

                ForEach(filteredTraces) { trace in
                    expandableTraceRow(trace: trace)
                    Divider()
                }
            }
        }
    }

    private var traceHeaderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundColor(.clear)
                .frame(width: 12)

            Text("TIME")
                .frame(width: 80, alignment: .leading)

            Text("LATENCY")
                .frame(width: 90, alignment: .leading)

            Text("SCOPES")
                .frame(width: 100, alignment: .leading)

            Text("BREAKDOWN")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func expandableTraceRow(trace: E2ETrace) -> some View {
        let isExpanded = expandedTraces.contains(trace.id)

        return VStack(spacing: 0) {
            // Main row
            Button(action: {
                if isExpanded {
                    expandedTraces.remove(trace.id)
                } else {
                    expandedTraces.insert(trace.id)
                }
            }) {
                HStack(spacing: 8) {
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    // Timestamp
                    Text(trace.timestamp, formatter: timeFormatter)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    // System latency (the metric that matters) + user time dimmed
                    HStack(spacing: 4) {
                        Text("\(trace.systemLatencyMs)ms")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(durationColor(trace.systemLatencyMs))

                        if trace.userTimeMs > 0 {
                            Text("+\(trace.userTimeMs / 1000)s")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .help("User recording time (not counted as latency)")
                        }
                    }
                    .frame(width: 90, alignment: .leading)

                    // Scope badges
                    HStack(spacing: 4) {
                        if trace.liveTrace != nil {
                            scopeBadge(.live)
                        }
                        if trace.engineTrace != nil {
                            scopeBadge(.engine)
                        }
                    }
                    .frame(width: 100, alignment: .leading)

                    // Timeline bar
                    timelineBar(trace: trace)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.05) : Color.clear)

            // Expanded detail
            if isExpanded {
                traceDetailView(trace: trace)
            }
        }
    }

    private func scopeBadge(_ scope: TraceScope) -> some View {
        HStack(spacing: 3) {
            Image(systemName: scope.icon)
                .font(.system(size: 7))
            Text(scope.rawValue)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(scope.color)
        )
    }

    private func timelineBar(trace: E2ETrace) -> some View {
        GeometryReader { geo in
            let total = CGFloat(max(trace.totalMs, 1))
            let liveWidth = CGFloat(trace.liveTrace?.totalMs ?? 0) / total * geo.size.width
            let engineWidth = CGFloat(trace.engineTrace?.totalMs ?? 0) / total * geo.size.width

            HStack(spacing: 1) {
                if trace.liveTrace != nil {
                    Rectangle()
                        .fill(TraceScope.live.color)
                        .frame(width: max(liveWidth, 2))
                }
                if trace.engineTrace != nil {
                    Rectangle()
                        .fill(TraceScope.engine.color)
                        .frame(width: max(engineWidth, 2))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 12)
            .cornerRadius(2)
        }
        .frame(height: 12)
    }

    // MARK: - Detail View

    private func traceDetailView(trace: E2ETrace) -> some View {
        VStack(spacing: 0) {
            // Live scope section
            if let liveTrace = trace.liveTrace {
                scopeDetailSection(trace: liveTrace)
            }

            // Engine scope section
            if let engineTrace = trace.engineTrace {
                scopeDetailSection(trace: engineTrace)
            }

            // Reference ID
            if let refId = trace.externalRefId {
                HStack {
                    Text("Correlation ID:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(refId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func scopeDetailSection(trace: ScopeTrace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scope header - show system latency prominently
            HStack {
                Image(systemName: trace.scope.icon)
                    .foregroundColor(trace.scope.color)
                Text("\(trace.scope.rawValue.uppercased()) SCOPE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                // System latency (primary metric)
                Text("\(trace.systemLatencyMs)ms latency")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(trace.scope.color)

                // User time (dimmed, if any)
                if trace.userTimeMs > 0 {
                    Text("• \(String(format: "%.1f", Double(trace.userTimeMs) / 1000))s user")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)

            // Step timeline
            GeometryReader { geo in
                let total = CGFloat(max(trace.totalMs, 1))
                let width = geo.size.width - 120

                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 24)

                    // Steps
                    ForEach(trace.steps) { step in
                        let startX = CGFloat(step.startMs) / total * width
                        let stepWidth = CGFloat(step.durationMs) / total * width

                        // User-controlled steps shown with lower opacity and dashed border
                        if step.isUserControlled {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .foregroundColor(.secondary.opacity(0.3))
                                )
                                .frame(width: max(stepWidth, 2), height: 24)
                                .offset(x: startX)
                                .help("\(step.name): \(step.durationMs)ms (user time - not counted)")
                        } else {
                            Rectangle()
                                .fill(stepColor(step.name, scope: trace.scope))
                                .frame(width: max(stepWidth, 2), height: 24)
                                .offset(x: startX)
                                .help("\(step.name): \(step.durationMs)ms")
                        }
                    }
                }
                .cornerRadius(4)
            }
            .frame(height: 24)
            .padding(.horizontal, 60)

            // Steps table
            VStack(spacing: 0) {
                ForEach(trace.steps) { step in
                    stepRow(step: step, systemLatencyMs: trace.systemLatencyMs, scope: trace.scope, isBottleneck: step.id == trace.bottleneck?.id)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 12)
        }
    }

    private func stepRow(step: TraceStep, systemLatencyMs: Int, scope: TraceScope, isBottleneck: Bool) -> some View {
        let isUserTime = step.isUserControlled

        return HStack(spacing: 8) {
            // Circle indicator - dashed for user time
            if isUserTime {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(stepColor(step.name, scope: scope))
                    .frame(width: 6, height: 6)
            }

            // Step name - dimmed for user time
            HStack(spacing: 4) {
                Text(step.name)
                    .font(.system(size: 10))
                    .foregroundColor(isUserTime ? .secondary : .primary)
                if isUserTime {
                    Text("(user)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: 140, alignment: .leading)

            // Duration - formatted differently for user time
            if isUserTime {
                Text("\(String(format: "%.1f", Double(step.durationMs) / 1000))s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 60, alignment: .leading)
            } else {
                Text("\(step.durationMs)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isBottleneck ? .orange : .primary)
                    .frame(width: 60, alignment: .leading)
            }

            // Percentage bar - only for system steps, uses system latency as denominator
            if !isUserTime {
                let pct = systemLatencyMs > 0 ? Double(step.durationMs) / Double(systemLatencyMs) * 100 : 0
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                            Rectangle()
                                .fill(stepColor(step.name, scope: scope))
                                .frame(width: geo.size.width * CGFloat(pct / 100))
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 6)

                    Text("\(Int(pct))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(width: 120)
            } else {
                // Empty space for user time rows
                Spacer()
                    .frame(width: 120)
            }

            // Bottleneck badge - never shown for user time
            if isBottleneck && !isUserTime {
                Text("BOTTLENECK")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                    )
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isUserTime ? 0.6 : 1.0)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading traces...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No traces found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Use TalkieLive to record dictations")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Button(action: { manager.loadTraces() }) {
                Text("Refresh")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func durationColor(_ ms: Int) -> Color {
        if ms >= 2000 { return .red }
        if ms >= 1000 { return .orange }
        return .green
    }

    private func stepColor(_ name: String, scope: TraceScope) -> Color {
        // Different colors for different step types
        switch name.lowercased() {
        case "hotkey_pressed", "hotkey": return .purple
        case "context_capture", "context": return .blue
        case "recording", "record": return .cyan
        case "file_save", "save": return .teal
        case "xpc_request", "xpc": return .indigo
        case "routing", "route", "paste": return .mint
        case "file_check": return .gray
        case "model_check", "model_load": return .yellow
        case "audio_load", "audio": return .blue
        case "inference", "transcribe": return .orange
        case "post_process", "format": return .green
        default: return scope.color
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}

// MARK: - Preview

#Preview {
    E2ETraceView()
        .frame(width: 1000, height: 600)
}
