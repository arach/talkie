//
//  E2ETraceView.swift
//  Talkie
//
//  End-to-end performance trace viewer for the Talkie suite.
//  Reads trace logs directly from TalkieLive and TalkieEngine log files.
//
//  Architecture:
//  - TraceLogReader: Directly scans log files for "Trace complete" entries
//  - E2ETraceStore: Manages trace state with auto-refresh
//  - E2ETraceView: Displays traces with timeline visualization
//

import SwiftUI

// MARK: - Data Models

/// A single step in a trace pipeline
struct TraceStep: Identifiable {
    let id = UUID()
    let name: String
    let durationMs: Int
    let startMs: Int

    var isUserControlled: Bool {
        ["recording", "record", "user_input", "speaking"].contains(name.lowercased())
    }
}

/// A parsed trace from a single app (Live or Engine)
struct ParsedTrace: Identifiable {
    let id = UUID()
    let traceId: String
    let timestamp: Date
    let source: TraceSource
    let totalMs: Int
    let steps: [TraceStep]

    enum TraceSource: String {
        case live = "Live"
        case engine = "Engine"

        var color: Color {
            switch self {
            case .live: return .purple
            case .engine: return .orange
            }
        }

        var icon: String {
            switch self {
            case .live: return "menubar.rectangle"
            case .engine: return "gearshape.fill"
            }
        }
    }

    /// System latency (excludes user-controlled time like recording)
    var systemLatencyMs: Int {
        steps.filter { !$0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// Bottleneck step (excluding user-controlled)
    var bottleneck: TraceStep? {
        steps.filter { !$0.isUserControlled }.max { $0.durationMs < $1.durationMs }
    }
}

/// Combined E2E trace with optional Live + Engine components
struct E2ETrace: Identifiable {
    let id = UUID()
    let timestamp: Date
    let traceId: String?
    var liveTrace: ParsedTrace?
    var engineTrace: ParsedTrace?

    var systemLatencyMs: Int {
        (liveTrace?.systemLatencyMs ?? 0) + (engineTrace?.systemLatencyMs ?? 0)
    }

    var userTimeMs: Int {
        let liveUser = liveTrace?.steps.filter { $0.isUserControlled }.reduce(0) { $0 + $1.durationMs } ?? 0
        let engineUser = engineTrace?.steps.filter { $0.isUserControlled }.reduce(0) { $0 + $1.durationMs } ?? 0
        return liveUser + engineUser
    }

    var totalMs: Int {
        (liveTrace?.totalMs ?? 0) + (engineTrace?.totalMs ?? 0)
    }

    var isComplete: Bool {
        liveTrace != nil && engineTrace != nil
    }
}

// MARK: - Trace Log Reader

/// Reads trace entries directly from log files
struct TraceLogReader {

    /// Log directories for each app
    private static func logDirectory(for source: ParsedTrace.TraceSource) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        switch source {
        case .live:
            return appSupport.appendingPathComponent("TalkieLive/logs")
        case .engine:
            return appSupport.appendingPathComponent("TalkieEngine/logs")
        }
    }

    /// Get today's log file path
    private static func logFilePath(for source: ParsedTrace.TraceSource, date: Date = Date()) -> URL? {
        guard let dir = logDirectory(for: source) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "talkie-\(formatter.string(from: date)).log"
        return dir.appendingPathComponent(filename)
    }

    /// Read all "Trace complete" entries from a log file
    static func readTraces(from source: ParsedTrace.TraceSource, date: Date = Date()) -> [ParsedTrace] {
        guard let path = logFilePath(for: source, date: date),
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }

        var traces: [ParsedTrace] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            // Only process "Trace complete" lines
            guard line.contains("Trace complete") else { continue }

            // Parse: 2025-12-29T17:15:57.635Z|TalkieLive|SYSTEM|Trace complete|[traceId] Xms total: step=Xms, ...
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 5 else { continue }

            // Parse timestamp
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let timestamp = isoFormatter.date(from: parts[0]) else { continue }

            // Parse detail (the trace data)
            let detail = parts[4]
            guard let trace = parseTraceDetail(detail, timestamp: timestamp, source: source) else { continue }

            traces.append(trace)
        }

        return traces
    }

    /// Parse trace detail: "[traceId] Xms total: step1=Xms, step2=Xms"
    private static func parseTraceDetail(_ detail: String, timestamp: Date, source: ParsedTrace.TraceSource) -> ParsedTrace? {
        var workingDetail = detail
        var traceId: String = UUID().uuidString.prefix(8).lowercased()

        // Extract trace ID from brackets: "[abc12345]"
        if let bracketRange = detail.range(of: #"^\[([a-zA-Z0-9\-]+)\]"#, options: .regularExpression) {
            let match = String(detail[bracketRange])
            traceId = String(match.dropFirst().dropLast())
            workingDetail = String(detail[bracketRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Skip past "Xms total: " prefix
        if let colonRange = workingDetail.range(of: "total:") {
            workingDetail = String(workingDetail[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Parse steps: "step1=Xms, step2=Xms"
        var steps: [TraceStep] = []
        var currentStartMs = 0

        let stepParts = workingDetail.components(separatedBy: ",")
        for part in stepParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let components = trimmed.components(separatedBy: "=")
            guard components.count >= 2 else { continue }

            let name = components[0].trimmingCharacters(in: .whitespaces)
            let msString = components[1].replacingOccurrences(of: "ms", with: "").trimmingCharacters(in: .whitespaces)
            guard let durationMs = Int(msString), !name.isEmpty else { continue }

            steps.append(TraceStep(name: name, durationMs: durationMs, startMs: currentStartMs))
            currentStartMs += durationMs
        }

        guard !steps.isEmpty else { return nil }

        return ParsedTrace(
            traceId: traceId,
            timestamp: timestamp,
            source: source,
            totalMs: currentStartMs,
            steps: steps
        )
    }

    /// Get file modification date for change detection
    static func lastModified(for source: ParsedTrace.TraceSource) -> Date? {
        guard let path = logFilePath(for: source) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attrs?[.modificationDate] as? Date
    }
}

// MARK: - E2E Trace Store

@MainActor
@Observable
class E2ETraceStore {
    static let shared = E2ETraceStore()

    var traces: [E2ETrace] = []
    var isLoading = false
    var lastRefresh: Date?
    var traceCount: Int { traces.count }

    // File watching state
    private var lastLiveModified: Date?
    private var lastEngineModified: Date?
    private var refreshTimer: Timer?

    private init() {}

    /// Start watching for changes (call on view appear)
    func startWatching() {
        // Initial load
        loadTraces()

        // Check for changes every 2 seconds
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
    }

    /// Stop watching (call on view disappear)
    func stopWatching() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Check if log files have been modified
    private func checkForUpdates() {
        let liveModified = TraceLogReader.lastModified(for: .live)
        let engineModified = TraceLogReader.lastModified(for: .engine)

        let needsRefresh = (liveModified != lastLiveModified) || (engineModified != lastEngineModified)

        if needsRefresh {
            lastLiveModified = liveModified
            lastEngineModified = engineModified
            loadTraces()
        }
    }

    /// Load all traces from log files
    func loadTraces() {
        isLoading = true

        Task.detached { [weak self] in
            // Read traces from both sources
            let liveTraces = TraceLogReader.readTraces(from: .live)
            let engineTraces = TraceLogReader.readTraces(from: .engine)

            // Correlate by trace ID
            var e2eTraces: [E2ETrace] = []
            var usedEngineIds = Set<String>()

            // Start with Live traces, try to match Engine traces
            for live in liveTraces {
                var e2e = E2ETrace(
                    timestamp: live.timestamp,
                    traceId: live.traceId,
                    liveTrace: live
                )

                // Find matching engine trace by ID
                if let engine = engineTraces.first(where: { $0.traceId == live.traceId }) {
                    e2e.engineTrace = engine
                    usedEngineIds.insert(engine.traceId)
                }

                e2eTraces.append(e2e)
            }

            // Add orphan engine traces
            for engine in engineTraces where !usedEngineIds.contains(engine.traceId) {
                e2eTraces.append(E2ETrace(
                    timestamp: engine.timestamp,
                    traceId: engine.traceId,
                    engineTrace: engine
                ))
            }

            // Sort newest first
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
    @State private var store = E2ETraceStore.shared
    @State private var expandedTraces: Set<UUID> = []
    @State private var showOnlyComplete = false
    @State private var selectedSource: ParsedTrace.TraceSource? = nil

    private var filteredTraces: [E2ETrace] {
        var result = store.traces

        if showOnlyComplete {
            result = result.filter { $0.isComplete }
        }

        if let source = selectedSource {
            result = result.filter { trace in
                switch source {
                case .live: return trace.liveTrace != nil
                case .engine: return trace.engineTrace != nil
                }
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            controlsView
            Divider()

            if store.isLoading && store.traces.isEmpty {
                loadingView
            } else if filteredTraces.isEmpty {
                emptyStateView
            } else {
                traceListView
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.startWatching() }
        .onDisappear { store.stopWatching() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("E2E TRACE VIEWER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(store.isLoading ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(store.isLoading ? "REFRESHING" : "WATCHING")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let lastRefresh = store.lastRefresh {
                Text("Updated \(lastRefresh, formatter: timeFormatter)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Button(action: { store.loadTraces() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Refresh")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)
        }
        .padding(16)
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 12) {
            // Source filter
            Picker("Source", selection: $selectedSource) {
                Text("All Sources").tag(nil as ParsedTrace.TraceSource?)
                Divider()
                ForEach([ParsedTrace.TraceSource.live, .engine], id: \.self) { source in
                    Label(source.rawValue, systemImage: source.icon).tag(source as ParsedTrace.TraceSource?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Toggle("Complete only", isOn: $showOnlyComplete)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))

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
                headerRow

                ForEach(filteredTraces) { trace in
                    traceRow(trace)
                    Divider()
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundColor(.clear)
                .frame(width: 12)

            Text("TIME")
                .frame(width: 70, alignment: .leading)

            Text("LATENCY")
                .frame(width: 100, alignment: .leading)

            Text("SOURCES")
                .frame(width: 100, alignment: .leading)

            Text("TIMELINE")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func traceRow(_ trace: E2ETrace) -> some View {
        let isExpanded = expandedTraces.contains(trace.id)

        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedTraces.remove(trace.id)
                } else {
                    expandedTraces.insert(trace.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    // Time
                    Text(trace.timestamp, formatter: timeFormatter)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)

                    // Latency
                    HStack(spacing: 4) {
                        Text("\(trace.systemLatencyMs)ms")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(latencyColor(trace.systemLatencyMs))

                        if trace.userTimeMs > 0 {
                            Text("+\(trace.userTimeMs / 1000)s")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .frame(width: 100, alignment: .leading)

                    // Source badges
                    HStack(spacing: 4) {
                        if trace.liveTrace != nil {
                            sourceBadge(.live)
                        }
                        if trace.engineTrace != nil {
                            sourceBadge(.engine)
                        }
                    }
                    .frame(width: 100, alignment: .leading)

                    // Timeline bar
                    timelineBar(trace)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.05) : Color.clear)

            if isExpanded {
                detailView(trace)
            }
        }
    }

    private func sourceBadge(_ source: ParsedTrace.TraceSource) -> some View {
        HStack(spacing: 3) {
            Image(systemName: source.icon)
                .font(.system(size: 7))
            Text(source.rawValue)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(source.color))
    }

    private func timelineBar(_ trace: E2ETrace) -> some View {
        GeometryReader { geo in
            let total = CGFloat(max(trace.totalMs, 1))
            let liveWidth = CGFloat(trace.liveTrace?.totalMs ?? 0) / total * geo.size.width
            let engineWidth = CGFloat(trace.engineTrace?.totalMs ?? 0) / total * geo.size.width

            HStack(spacing: 1) {
                if trace.liveTrace != nil {
                    Rectangle()
                        .fill(ParsedTrace.TraceSource.live.color)
                        .frame(width: max(liveWidth, 2))
                }
                if trace.engineTrace != nil {
                    Rectangle()
                        .fill(ParsedTrace.TraceSource.engine.color)
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

    private func detailView(_ trace: E2ETrace) -> some View {
        VStack(spacing: 0) {
            if let live = trace.liveTrace {
                sourceDetail(live)
            }
            if let engine = trace.engineTrace {
                sourceDetail(engine)
            }
            if let traceId = trace.traceId {
                HStack {
                    Text("Trace ID:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(traceId)
                        .font(.system(size: 9, design: .monospaced))
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func sourceDetail(_ trace: ParsedTrace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: trace.source.icon)
                    .foregroundColor(trace.source.color)
                Text("\(trace.source.rawValue.uppercased())")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(trace.systemLatencyMs)ms latency")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(trace.source.color)
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)

            // Steps
            VStack(spacing: 2) {
                ForEach(trace.steps) { step in
                    stepRow(step, trace: trace)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 12)
        }
    }

    private func stepRow(_ step: TraceStep, trace: ParsedTrace) -> some View {
        let isBottleneck = step.id == trace.bottleneck?.id

        return HStack(spacing: 8) {
            Circle()
                .fill(step.isUserControlled ? Color.secondary.opacity(0.3) : stepColor(step.name, source: trace.source))
                .frame(width: 6, height: 6)

            Text(step.name)
                .font(.system(size: 10))
                .foregroundColor(step.isUserControlled ? .secondary : .primary)
                .frame(width: 120, alignment: .leading)

            if step.isUserControlled {
                Text("\(String(format: "%.1f", Double(step.durationMs) / 1000))s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                Text("\(step.durationMs)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isBottleneck ? .orange : .primary)
            }

            if isBottleneck && !step.isUserControlled {
                Text("BOTTLENECK")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.orange))
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(step.isUserControlled ? 0.6 : 1.0)
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
            Text("Record a dictation with TalkieLive to see traces")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Button("Refresh") { store.loadTraces() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func latencyColor(_ ms: Int) -> Color {
        if ms >= 2000 { return .red }
        if ms >= 1000 { return .orange }
        return .green
    }

    private func stepColor(_ name: String, source: ParsedTrace.TraceSource) -> Color {
        switch name.lowercased() {
        case "hotkey_pressed", "hotkey": return .purple
        case "context_capture", "context": return .blue
        case "recording", "record": return .cyan
        case "file_save", "save": return .teal
        case "engine", "xpc": return .indigo
        case "routing", "route", "paste": return .mint
        case "inference", "transcribe": return .orange
        default: return source.color
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}

#Preview {
    E2ETraceView()
        .frame(width: 1000, height: 600)
}
