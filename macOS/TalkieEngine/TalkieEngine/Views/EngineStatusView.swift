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

// MARK: - Engine Status Manager

@MainActor
class EngineStatusManager: ObservableObject {
    static let shared = EngineStatusManager()

    @Published var logs: [EngineLogEntry] = []
    @Published var isTranscribing = false
    @Published var currentModel: String?
    @Published var totalTranscriptions = 0
    @Published var uptime: TimeInterval = 0

    // Model management
    @Published var models: [EngineModelInfo] = []

    private let maxLogs = 500
    private let startedAt = Date()
    private var uptimeTimer: Timer?

    private init() {
        log(.info, "EngineService", "TalkieEngine started")
        startUptimeTimer()
        loadModels()
    }

    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.uptime = Date().timeIntervalSince(self?.startedAt ?? Date())
            }
        }
    }

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

    var icon: String {
        switch self {
        case .console: return "terminal"
        case .models: return "square.stack.3d.up"
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
            }

            // Status bar
            statusBar
        }
        .background(bgColor)
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Header

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

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

                    // Dev/Production badge
                    Text(isDebugBuild ? "DEV" : "PROD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(isDebugBuild ? .orange : accentGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isDebugBuild ? Color.orange.opacity(0.2) : accentGreen.opacity(0.2))
                        .cornerRadius(3)
                }

                Text("Transcription Service")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
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
        HStack(spacing: 24) {
            statItem(icon: "clock", label: "UPTIME", value: statusManager.formattedUptime)
            statItem(icon: "waveform", label: "TRANSCRIPTIONS", value: "\(statusManager.totalTranscriptions)")
            statItem(icon: "cpu", label: "MODEL", value: statusManager.currentModel ?? "None")
            statItem(icon: "memorychip", label: "PID", value: "\(ProcessInfo.processInfo.processIdentifier)")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(surfaceColor.opacity(0.5))
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

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if selectedTab == .console {
                Text("\(filteredLogs.count) entries")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                let downloaded = statusManager.models.filter { $0.isDownloaded }.count
                let total = statusManager.models.count
                Text("\(downloaded)/\(total) models installed")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
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
