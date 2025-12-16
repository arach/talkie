//
//  EngineStatusView.swift
//  TalkieEngine
//
//  Dashboard view showing engine status, logs, and model management
//

import SwiftUI

// MARK: - Engine Log Entry

struct EngineLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return Color(red: 0.4, green: 0.6, blue: 1.0)
            case .warning: return .orange
            case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
            }
        }
    }
}

// MARK: - Model Info for Display

struct EngineModelInfo: Identifiable {
    let id: String
    let family: String
    let modelId: String
    let displayName: String
    let sizeDescription: String
    let description: String
    var isDownloaded: Bool
    var isLoaded: Bool
}

// MARK: - Transcription Trace (Step-Level Timing)

/// A single step in the transcription pipeline
struct TranscriptionStep: Identifiable {
    let id = UUID()
    let name: String        // e.g., "file_check", "audio_load", "inference"
    let startMs: Int        // Milliseconds from transcription start
    let durationMs: Int     // How long this step took
    let metadata: String?   // Optional detail (e.g., "8000 samples", "model loaded")

    var endMs: Int { startMs + durationMs }
}

/// Collects timing for all steps in a transcription job
final class TranscriptionTrace {
    let jobId = UUID()
    let startTime: Date = Date()
    private var steps: [TranscriptionStep] = []
    private var stepStart: Date?
    private var currentStepName: String?

    /// Begin timing a step
    func begin(_ name: String) {
        // End any previous step first
        if let prevName = currentStepName, let prevStart = stepStart {
            endStep(prevName, start: prevStart)
        }
        currentStepName = name
        stepStart = Date()
    }

    /// End the current step with optional metadata
    func end(_ metadata: String? = nil) {
        guard let name = currentStepName, let start = stepStart else { return }
        endStep(name, start: start, metadata: metadata)
        currentStepName = nil
        stepStart = nil
    }

    private func endStep(_ name: String, start: Date, metadata: String? = nil) {
        let startMs = Int(start.timeIntervalSince(startTime) * 1000)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        steps.append(TranscriptionStep(
            name: name,
            startMs: startMs,
            durationMs: durationMs,
            metadata: metadata
        ))
    }

    /// Mark a point in time (zero-duration step)
    func mark(_ name: String, metadata: String? = nil) {
        let startMs = Int(Date().timeIntervalSince(startTime) * 1000)
        steps.append(TranscriptionStep(
            name: name,
            startMs: startMs,
            durationMs: 0,
            metadata: metadata
        ))
    }

    /// Get all recorded steps (sorted by start time)
    func getSteps() -> [TranscriptionStep] {
        return steps.sorted { $0.startMs < $1.startMs }
    }

    /// Total elapsed time since start
    var elapsedMs: Int {
        Int(Date().timeIntervalSince(startTime) * 1000)
    }

    /// Total elapsed seconds
    var elapsedSeconds: Double {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Transcription Metric

struct TranscriptionMetric: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSeconds: Double
    let audioDurationSeconds: Double?
    let wordCount: Int
    let transcriptPreview: String?  // First ~30 chars for reference

    // Step-level breakdown for drill-down
    let steps: [TranscriptionStep]
    let modelId: String?
    let audioFilename: String?
    let audioSamples: Int?   // Number of samples processed

    init(
        timestamp: Date,
        elapsedSeconds: Double,
        audioDurationSeconds: Double? = nil,
        wordCount: Int,
        transcriptPreview: String? = nil,
        steps: [TranscriptionStep] = [],
        modelId: String? = nil,
        audioFilename: String? = nil,
        audioSamples: Int? = nil
    ) {
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.audioDurationSeconds = audioDurationSeconds
        self.wordCount = wordCount
        self.transcriptPreview = transcriptPreview
        self.steps = steps
        self.modelId = modelId
        self.audioFilename = audioFilename
        self.audioSamples = audioSamples
    }

    /// Has detailed step breakdown
    var hasTrace: Bool { !steps.isEmpty }

    /// Longest step (bottleneck)
    var bottleneck: TranscriptionStep? {
        steps.max { $0.durationMs < $1.durationMs }
    }
}

// MARK: - Process Snapshot (for monitoring)

struct ProcessSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let memoryMB: Double          // Process memory in MB
    let cpuPercent: Double        // Process CPU %
    let systemCpuPercent: Double? // System-wide CPU % (optional)

    var memoryFormatted: String {
        if memoryMB < 1024 {
            return String(format: "%.0f MB", memoryMB)
        }
        return String(format: "%.1f GB", memoryMB / 1024)
    }
}

// MARK: - Engine Status Manager

// Note: Uses EngineServiceMode from EngineProtocol.swift for launch mode

@MainActor
class EngineStatusManager: ObservableObject {
    static let shared = EngineStatusManager()

    @Published var logs: [EngineLogEntry] = []
    @Published var isTranscribing = false
    @Published var currentModel: String?
    @Published var totalTranscriptions = 0
    @Published var uptime: TimeInterval = 0

    // Launch mode info (set from main.swift)
    @Published var launchMode: EngineServiceMode = .dev
    @Published var activeServiceName: String = ""

    // Executable path for debugging
    let executablePath: String = Bundle.main.executablePath ?? "Unknown"

    // Model management
    @Published var models: [EngineModelInfo] = []

    // Latency metrics (dev only)
    @Published var recentMetrics: [TranscriptionMetric] = []
    private let maxMetrics = 100

    // Process monitoring (dev only)
    #if DEBUG
    @Published var processSnapshots: [ProcessSnapshot] = []
    @Published var currentMemoryMB: Double = 0
    @Published var currentCpuPercent: Double = 0
    @Published var peakMemoryMB: Double = 0
    private let maxSnapshots = 300  // ~5 min at 1s intervals
    private var processMonitorTimer: Timer?
    #endif

    private let maxLogs = 500
    private let startedAt = Date()
    private var uptimeTimer: Timer?

    private init() {
        log(.info, "EngineService", "TalkieEngine started")
        loadModels()
    }

    /// Configure launch mode (called from main.swift)
    func configure(mode: EngineServiceMode, serviceName: String) {
        self.launchMode = mode
        self.activeServiceName = serviceName
        log(.info, "Config", "Mode: \(mode.displayName), XPC: \(serviceName)")
    }

    // MARK: - Timer Management (only runs when status window visible)

    func startUptimeTimer() {
        guard uptimeTimer == nil else { return }
        uptime = Date().timeIntervalSince(startedAt)  // Immediate update
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.uptime = Date().timeIntervalSince(self?.startedAt ?? Date())
            }
        }
    }

    func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    // MARK: - Process Monitoring (DEBUG only)

    #if DEBUG
    func startProcessMonitor() {
        guard processMonitorTimer == nil else { return }
        sampleProcessStats()  // Immediate sample
        processMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleProcessStats()
            }
        }
    }

    func stopProcessMonitor() {
        processMonitorTimer?.invalidate()
        processMonitorTimer = nil
    }

    private func sampleProcessStats() {
        let memoryMB = getProcessMemoryMB()
        let cpuPercent = getProcessCPUPercent()

        currentMemoryMB = memoryMB
        currentCpuPercent = cpuPercent
        peakMemoryMB = max(peakMemoryMB, memoryMB)

        let snapshot = ProcessSnapshot(
            timestamp: Date(),
            memoryMB: memoryMB,
            cpuPercent: cpuPercent,
            systemCpuPercent: nil  // Could add system CPU later
        )
        processSnapshots.append(snapshot)
        if processSnapshots.count > maxSnapshots {
            processSnapshots.removeFirst(processSnapshots.count - maxSnapshots)
        }
    }

    /// Get current process memory usage in MB
    private func getProcessMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1_000_000  // Convert to MB
        }
        return 0
    }

    /// Get current process CPU usage (rough estimate)
    /// Note: This is a point-in-time sample, not a rolling average
    private func getProcessCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0 }

        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)

            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }

            if infoResult == KERN_SUCCESS {
                let cpuUsage = Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
                totalCPU += cpuUsage
            }
        }

        // Deallocate thread list
        let threadListSize = vm_size_t(MemoryLayout<thread_t>.size * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), threadListSize)

        return totalCPU
    }
    #endif

    func log(_ level: EngineLogEntry.LogLevel, _ category: String, _ message: String) {
        let entry = EngineLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        logs.insert(entry, at: 0)
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
    }

    func clearLogs() {
        logs.removeAll()
        log(.info, "Console", "Logs cleared")
    }

    // MARK: - Latency Metrics

    /// Record a transcription metric (legacy - no trace)
    func recordMetric(elapsed: Double, audioDuration: Double? = nil, wordCount: Int, transcript: String? = nil) {
        recordMetric(
            elapsed: elapsed,
            audioDuration: audioDuration,
            wordCount: wordCount,
            transcript: transcript,
            trace: nil,
            modelId: nil,
            audioFilename: nil,
            audioSamples: nil
        )
    }

    /// Record a transcription metric with full trace
    func recordMetric(
        elapsed: Double,
        audioDuration: Double? = nil,
        wordCount: Int,
        transcript: String? = nil,
        trace: TranscriptionTrace?,
        modelId: String?,
        audioFilename: String?,
        audioSamples: Int?
    ) {
        let preview = transcript.map { String($0.prefix(40)) }
        let metric = TranscriptionMetric(
            timestamp: Date(),
            elapsedSeconds: elapsed,
            audioDurationSeconds: audioDuration,
            wordCount: wordCount,
            transcriptPreview: preview,
            steps: trace?.getSteps() ?? [],
            modelId: modelId,
            audioFilename: audioFilename,
            audioSamples: audioSamples
        )
        recentMetrics.insert(metric, at: 0)
        if recentMetrics.count > maxMetrics {
            recentMetrics = Array(recentMetrics.prefix(maxMetrics))
        }
    }

    /// Average transcription latency in seconds
    var averageLatency: Double? {
        guard !recentMetrics.isEmpty else { return nil }
        return recentMetrics.map(\.elapsedSeconds).reduce(0, +) / Double(recentMetrics.count)
    }

    /// Average realtime multiplier (audioDuration / elapsed)
    /// e.g., 10x means we transcribe 10 seconds of audio in 1 second
    var averageRealtimeMultiplier: Double? {
        let withDuration = recentMetrics.compactMap { m -> Double? in
            guard let dur = m.audioDurationSeconds, dur > 0, m.elapsedSeconds > 0 else { return nil }
            return dur / m.elapsedSeconds
        }
        guard !withDuration.isEmpty else { return nil }
        return withDuration.reduce(0, +) / Double(withDuration.count)
    }

    var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    // MARK: - Model Management

    private func loadModels() {
        // Whisper models
        let whisperModels = [
            ("openai_whisper-tiny", "Tiny", "~75 MB", "Fastest, basic quality"),
            ("openai_whisper-base", "Base", "~150 MB", "Fast, good quality"),
            ("openai_whisper-small", "Small", "~500 MB", "Balanced speed/quality"),
            ("distil-whisper_distil-large-v3", "Distil Large v3", "~1.5 GB", "Best quality, slower")
        ]

        // Parakeet models
        let parakeetModels = [
            ("v2", "Parakeet V2", "~200 MB", "English only, highest accuracy"),
            ("v3", "Parakeet V3", "~250 MB", "25 languages, fast")
        ]

        models = whisperModels.map { model in
            EngineModelInfo(
                id: "whisper:\(model.0)",
                family: "whisper",
                modelId: model.0,
                displayName: "Whisper \(model.1)",
                sizeDescription: model.2,
                description: model.3,
                isDownloaded: checkModelDownloaded(family: "whisper", modelId: model.0),
                isLoaded: false
            )
        } + parakeetModels.map { model in
            EngineModelInfo(
                id: "parakeet:\(model.0)",
                family: "parakeet",
                modelId: model.0,
                displayName: model.1,
                sizeDescription: model.2,
                description: model.3,
                isDownloaded: checkModelDownloaded(family: "parakeet", modelId: model.0),
                isLoaded: false
            )
        }
    }

    private func checkModelDownloaded(family: String, modelId: String) -> Bool {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        if family == "whisper" {
            let path = supportDir
                .appendingPathComponent("Talkie/WhisperModels/models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent(modelId)
            return FileManager.default.fileExists(atPath: path.path)
        } else {
            let markerPath = supportDir
                .appendingPathComponent("Talkie/ParakeetModels")
                .appendingPathComponent(modelId)
                .appendingPathComponent(".marker")
            return FileManager.default.fileExists(atPath: markerPath.path)
        }
    }

    func refreshModels() {
        for i in models.indices {
            models[i].isDownloaded = checkModelDownloaded(family: models[i].family, modelId: models[i].modelId)
            models[i].isLoaded = currentModel == models[i].id
        }
    }

    func updateLoadedModel(_ modelId: String?) {
        currentModel = modelId
        for i in models.indices {
            models[i].isLoaded = models[i].id == modelId
        }
    }
}

// MARK: - Tab Selection

enum EngineTab: String, CaseIterable {
    case console = "Console"
    case models = "Models"
    case performance = "Performance"

    var icon: String {
        switch self {
        case .console: return "terminal"
        case .models: return "square.stack.3d.up"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

// MARK: - Engine Status View

struct EngineStatusView: View {
    @StateObject private var statusManager = EngineStatusManager.shared
    @State private var selectedTab: EngineTab = .console
    @State private var filterLevel: EngineLogEntry.LogLevel? = nil
    @State private var searchQuery = ""
    @State private var autoScroll = true
    @State private var expandedMetricId: UUID? = nil  // For performance drill-down

    private let accentGreen = Color(red: 0.4, green: 0.8, blue: 0.4)
    private let bgColor = Color(red: 0.08, green: 0.08, blue: 0.1)
    private let surfaceColor = Color(red: 0.12, green: 0.12, blue: 0.14)
    private let borderColor = Color(red: 0.2, green: 0.2, blue: 0.22)

    private var filteredLogs: [EngineLogEntry] {
        var result = statusManager.logs

        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }

        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.message.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerView

            Divider()
                .background(borderColor)

            // Stats bar
            statsBar

            Divider()
                .background(borderColor)

            // Tab bar
            tabBar

            Divider()
                .background(borderColor)

            // Content based on selected tab
            switch selectedTab {
            case .console:
                consoleContent
            case .models:
                modelsContent
            case .performance:
                performanceContent
            }

            // Status bar
            statusBar
        }
        .background(bgColor)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            statusManager.startUptimeTimer()
            #if DEBUG
            statusManager.startProcessMonitor()
            #endif
        }
        .onDisappear {
            statusManager.stopUptimeTimer()
            #if DEBUG
            statusManager.stopProcessMonitor()
            #endif
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Engine icon
            Image(systemName: "engine.combustion")
                .font(.system(size: 18))
                .foregroundColor(accentGreen)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("TalkieEngine")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    // Launch mode badge (DEV/DEBUG/PROD)
                    Text(statusManager.launchMode.rawValue)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(statusManager.launchMode.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(statusManager.launchMode.color.opacity(0.2))
                        .cornerRadius(3)
                }

                // XPC service name
                Text(statusManager.activeServiceName.isEmpty ? "Transcription Service" : statusManager.activeServiceName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)

                // Executable path (debug builds only)
                #if DEBUG
                Text(statusManager.executablePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.head)  // Show end of path (most useful part)
                    .help(statusManager.executablePath)  // Full path on hover
                #endif
            }

            Spacer()

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusManager.isTranscribing ? Color.orange : accentGreen)
                    .frame(width: 8, height: 8)
                    .shadow(color: (statusManager.isTranscribing ? Color.orange : accentGreen).opacity(0.5), radius: 4)

                Text(statusManager.isTranscribing ? "TRANSCRIBING" : "READY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(statusManager.isTranscribing ? .orange : accentGreen)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(surfaceColor)
            .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 20) {
            statItem(icon: "clock", label: "UPTIME", value: statusManager.formattedUptime)
            statItem(icon: "waveform", label: "TRANSCRIPTIONS", value: "\(statusManager.totalTranscriptions)")
            statItem(icon: "cpu", label: "MODEL", value: statusManager.currentModel ?? "None")
            statItem(icon: "number", label: "PID", value: "\(ProcessInfo.processInfo.processIdentifier)")

            #if DEBUG
            // Process stats (dev only)
            statItem(icon: "memorychip", label: "MEMORY", value: String(format: "%.0f MB", statusManager.currentMemoryMB))
            statItem(icon: "gauge.with.needle", label: "CPU", value: String(format: "%.1f%%", statusManager.currentCpuPercent))
            #endif

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(surfaceColor.opacity(0.5))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(accentGreen.opacity(0.3)),
            alignment: .top
        )
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(EngineTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))
                        Text(tab.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(selectedTab == tab ? accentGreen : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? accentGreen.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(bgColor)
    }

    // MARK: - Console Content

    private var consoleContent: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Divider()
                .background(borderColor)

            // Log output
            logOutput
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Level filters
            filterChip(nil, label: "ALL")
            filterChip(.debug, label: "DEBUG")
            filterChip(.info, label: "INFO")
            filterChip(.warning, label: "WARN")
            filterChip(.error, label: "ERROR")

            Spacer()

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)

                TextField("Search...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 100)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(surfaceColor)
            .cornerRadius(4)

            // Clear button
            Button(action: { statusManager.clearLogs() }) {
                Text("CLEAR")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(surfaceColor)
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bgColor)
    }

    private func filterChip(_ level: EngineLogEntry.LogLevel?, label: String) -> some View {
        let isSelected = filterLevel == level
        let chipColor = level?.color ?? .white

        return Button(action: { filterLevel = level }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? bgColor : chipColor.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? chipColor : chipColor.opacity(0.1))
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Output

    private var logOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLogs.reversed()) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: statusManager.logs.count) {
                if autoScroll, let newest = filteredLogs.first {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newest.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(bgColor)
    }

    private func logRow(_ entry: EngineLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(formatTime(entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 55, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(entry.level.color)
                .frame(width: 45, alignment: .leading)

            Text(entry.category)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Models Content

    private var modelsContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Whisper section
                modelSection(title: "Whisper Models", family: "whisper")

                // Parakeet section
                modelSection(title: "Parakeet Models", family: "parakeet")
            }
            .padding(12)
        }
        .background(bgColor)
        .onAppear {
            statusManager.refreshModels()
        }
    }

    private func modelSection(title: String, family: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.bottom, 4)

            ForEach(statusManager.models.filter { $0.family == family }) { model in
                modelRow(model)
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func modelRow(_ model: EngineModelInfo) -> some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: model.isLoaded ? "checkmark.circle.fill" : (model.isDownloaded ? "arrow.down.circle.fill" : "circle.dashed"))
                .font(.system(size: 16))
                .foregroundColor(model.isLoaded ? accentGreen : (model.isDownloaded ? Color(red: 0.4, green: 0.6, blue: 1.0) : .gray))

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text(model.sizeDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)

                    Text("•")
                        .foregroundColor(.gray)

                    Text(model.description)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Status badge
            if model.isLoaded {
                Text("LOADED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accentGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentGreen.opacity(0.15))
                    .cornerRadius(4)
            } else if model.isDownloaded {
                Text("READY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.15))
                    .cornerRadius(4)
            } else {
                Text("NOT INSTALLED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(bgColor)
        .cornerRadius(6)
    }

    // MARK: - Performance Content

    private var performanceContent: some View {
        VStack(spacing: 0) {
            // Summary stats
            HStack(spacing: 20) {
                performanceStat(
                    label: "TOTAL",
                    value: "\(statusManager.totalTranscriptions)"
                )

                performanceStat(
                    label: "RECENT",
                    value: "\(statusManager.recentMetrics.count)"
                )

                #if DEBUG
                performanceStat(
                    label: "PEAK MEM",
                    value: String(format: "%.0f MB", statusManager.peakMemoryMB)
                )

                performanceStat(
                    label: "SNAPSHOTS",
                    value: "\(statusManager.processSnapshots.count)"
                )
                #endif

                Spacer()
            }
            .padding(12)
            .background(surfaceColor)

            Divider()
                .background(borderColor)

            // Table header
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 40, alignment: .leading)
                Text("TIME")
                    .frame(width: 70, alignment: .leading)
                Text("LATENCY")
                    .frame(width: 70, alignment: .trailing)
                Text("WORDS")
                    .frame(width: 50, alignment: .trailing)
                Text("RTF")
                    .frame(width: 50, alignment: .trailing)
                Text("PREVIEW")
                    .frame(minWidth: 100, alignment: .leading)
                    .padding(.leading, 12)
                Spacer()
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(surfaceColor.opacity(0.5))

            // Table rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(statusManager.recentMetrics.enumerated()), id: \.offset) { index, metric in
                        performanceRow(index: statusManager.totalTranscriptions - index, metric: metric)
                    }
                }
            }
            .background(bgColor)
        }
    }

    private func performanceStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func performanceRow(index: Int, metric: TranscriptionMetric) -> some View {
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()

        let latencyMs = Int(metric.elapsedSeconds * 1000)
        let latencyStr = latencyMs < 1000 ? "\(latencyMs)ms" : String(format: "%.2fs", metric.elapsedSeconds)
        let isExpanded = expandedMetricId == metric.id

        return VStack(spacing: 0) {
            // Main row (clickable)
            HStack(spacing: 0) {
                // Expand indicator
                Image(systemName: metric.hasTrace ? (isExpanded ? "chevron.down" : "chevron.right") : "circle.fill")
                    .font(.system(size: metric.hasTrace ? 9 : 4))
                    .foregroundColor(metric.hasTrace ? .gray : .gray.opacity(0.3))
                    .frame(width: 16)

                Text("#\(index)")
                    .frame(width: 30, alignment: .leading)
                    .foregroundColor(.gray)

                Text(timeFormatter.string(from: metric.timestamp))
                    .frame(width: 70, alignment: .leading)
                    .foregroundColor(.white)

                Text(latencyStr)
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(latencyMs < 500 ? accentGreen : (latencyMs < 2000 ? .orange : .red))

                Text("\(metric.wordCount)")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundColor(.white)

                if let audioDuration = metric.audioDurationSeconds, audioDuration > 0 {
                    let rtf = metric.elapsedSeconds / audioDuration
                    Text(String(format: "%.1f%%", rtf * 100))
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(rtf < 0.02 ? accentGreen : (rtf < 0.05 ? .white : .orange))
                } else {
                    Text("-")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.gray)
                }

                // Transcript preview
                Text(metric.transcriptPreview ?? "-")
                    .frame(minWidth: 100, alignment: .leading)
                    .padding(.leading, 12)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(index % 2 == 0 ? Color.clear : surfaceColor.opacity(0.3))
            .contentShape(Rectangle())
            .onTapGesture {
                if metric.hasTrace {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedMetricId = isExpanded ? nil : metric.id
                    }
                }
            }

            // Expanded step breakdown
            if isExpanded && metric.hasTrace {
                performanceStepBreakdown(metric: metric)
            }
        }
    }

    /// Step breakdown view for expanded metric row
    private func performanceStepBreakdown(metric: TranscriptionMetric) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("STEP BREAKDOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer()

                if let bottleneck = metric.bottleneck {
                    Text("Bottleneck: \(bottleneck.name) (\(bottleneck.durationMs)ms)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(surfaceColor.opacity(0.8))

            // Visual timeline
            performanceTimeline(steps: metric.steps, totalMs: Int(metric.elapsedSeconds * 1000))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Step list
            ForEach(metric.steps) { step in
                performanceStepRow(step: step, totalMs: Int(metric.elapsedSeconds * 1000))
            }

            // Metadata footer
            if metric.modelId != nil || metric.audioFilename != nil || metric.audioSamples != nil {
                Divider().background(borderColor)
                HStack(spacing: 16) {
                    if let model = metric.modelId {
                        Text("Model: \(model)")
                    }
                    if let filename = metric.audioFilename {
                        Text("File: \(filename)")
                    }
                    if let samples = metric.audioSamples {
                        Text("Samples: \(samples)")
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(surfaceColor.opacity(0.5))
        .overlay(
            Rectangle()
                .fill(accentGreen.opacity(0.3))
                .frame(width: 2),
            alignment: .leading
        )
    }

    /// Visual timeline bar for steps
    private func performanceTimeline(steps: [TranscriptionStep], totalMs: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(borderColor)
                    .frame(height: 16)

                // Steps as colored segments
                ForEach(steps) { step in
                    if step.durationMs > 0 && totalMs > 0 {
                        let width = CGFloat(step.durationMs) / CGFloat(totalMs) * geometry.size.width
                        let offset = CGFloat(step.startMs) / CGFloat(totalMs) * geometry.size.width

                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForStep(step.name))
                            .frame(width: max(width, 2), height: 14)
                            .offset(x: offset)
                            .help("\(step.name): \(step.durationMs)ms")
                    }
                }
            }
        }
        .frame(height: 16)
    }

    /// Single step row in breakdown
    private func performanceStepRow(step: TranscriptionStep, totalMs: Int) -> some View {
        let percentage = totalMs > 0 ? Double(step.durationMs) / Double(totalMs) * 100 : 0

        return HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(colorForStep(step.name))
                .frame(width: 8, height: 8)

            // Step name
            Text(step.name)
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.white)

            // Timing
            Text("@\(step.startMs)ms")
                .frame(width: 70, alignment: .trailing)
                .foregroundColor(.gray)

            Text("\(step.durationMs)ms")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(step.durationMs > 1000 ? .orange : (step.durationMs > 100 ? .white : accentGreen))

            // Percentage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(borderColor)
                    Rectangle()
                        .fill(colorForStep(step.name))
                        .frame(width: geometry.size.width * CGFloat(percentage / 100))
                }
            }
            .frame(width: 60, height: 8)
            .cornerRadius(2)

            Text(String(format: "%.1f%%", percentage))
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.gray)

            // Metadata
            if let metadata = step.metadata {
                Text(metadata)
                    .foregroundColor(.gray.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    /// Color for step type
    private func colorForStep(_ name: String) -> Color {
        switch name {
        case "file_check": return .blue
        case "model_check": return .purple
        case "model_load": return .orange
        case "audio_load": return .cyan
        case "audio_pad": return .teal
        case "inference": return accentGreen
        case "post_process": return .yellow
        case "start", "complete": return .gray
        case "error": return .red
        default: return .gray
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            switch selectedTab {
            case .console:
                Text("\(filteredLogs.count) entries")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            case .models:
                let downloaded = statusManager.models.filter { $0.isDownloaded }.count
                let total = statusManager.models.count
                Text("\(downloaded)/\(total) models installed")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            case .performance:
                if !statusManager.recentMetrics.isEmpty {
                    let latencies = statusManager.recentMetrics.map { $0.elapsedSeconds * 1000 }
                    let min = latencies.min() ?? 0
                    let max = latencies.max() ?? 0
                    Text("Range: \(String(format: "%.0f", min))–\(String(format: "%.0f", max))ms • \(statusManager.recentMetrics.count) samples")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                } else {
                    Text("No metrics yet")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if selectedTab == .console {
                // Auto-scroll toggle
                Button(action: { autoScroll.toggle() }) {
                    HStack(spacing: 3) {
                        Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("AUTO")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(autoScroll ? accentGreen : .gray)
                }
                .buttonStyle(.plain)
            } else {
                // Refresh button
                Button(action: { statusManager.refreshModels() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("REFRESH")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(borderColor),
            alignment: .top
        )
    }
}

// MARK: - Preview

#Preview {
    EngineStatusView()
        .frame(width: 700, height: 500)
}
