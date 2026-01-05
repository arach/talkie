//
//  DebugKit.swift
//  TalkieLive
//
//  Debug toolbar and logging for development
//
//  Uses DebugToolbarPosition from DebugKit package for consistency.
//

import SwiftUI
import os.log
import DebugKit
import TalkieKit

// MARK: - Particle Preset

struct ParticlePreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var baseSpeed: Double
    var speedVariation: Double
    var waveSpeed: Double
    var baseAmplitude: Double
    var audioAmplitude: Double
    var particleCount: Int
    var baseSize: Double
    var baseOpacity: Double
    var smoothingFactor: Double

    static let defaultPreset = ParticlePreset(
        id: "default",
        name: "Default",
        baseSpeed: 0.10,
        speedVariation: 0.08,
        waveSpeed: 2.0,
        baseAmplitude: 0.4,
        audioAmplitude: 0.35,
        particleCount: 80,
        baseSize: 2.0,
        baseOpacity: 0.45,
        smoothingFactor: 0.18
    )

    static let builtInPresets: [ParticlePreset] = [
        defaultPreset,
        ParticlePreset(
            id: "calm",
            name: "Calm",
            baseSpeed: 0.05,
            speedVariation: 0.03,
            waveSpeed: 1.2,
            baseAmplitude: 0.25,
            audioAmplitude: 0.2,
            particleCount: 60,
            baseSize: 2.5,
            baseOpacity: 0.35,
            smoothingFactor: 0.25
        ),
        ParticlePreset(
            id: "energetic",
            name: "Energetic",
            baseSpeed: 0.18,
            speedVariation: 0.12,
            waveSpeed: 3.5,
            baseAmplitude: 0.6,
            audioAmplitude: 0.5,
            particleCount: 120,
            baseSize: 1.8,
            baseOpacity: 0.55,
            smoothingFactor: 0.12
        ),
        ParticlePreset(
            id: "subtle",
            name: "Subtle",
            baseSpeed: 0.06,
            speedVariation: 0.04,
            waveSpeed: 1.5,
            baseAmplitude: 0.2,
            audioAmplitude: 0.15,
            particleCount: 50,
            baseSize: 1.5,
            baseOpacity: 0.3,
            smoothingFactor: 0.22
        ),
        ParticlePreset(
            id: "dense",
            name: "Dense",
            baseSpeed: 0.08,
            speedVariation: 0.06,
            waveSpeed: 2.2,
            baseAmplitude: 0.35,
            audioAmplitude: 0.3,
            particleCount: 150,
            baseSize: 1.2,
            baseOpacity: 0.4,
            smoothingFactor: 0.15
        )
    ]
}

// MARK: - Waveform Tuning (Debug Controls)

@MainActor
final class WaveformTuning: ObservableObject {
    static let shared = WaveformTuning()

    // Bar appearance
    @Published var barCount: Int = 48 {
        didSet { saveSettings(); log("barCount", Double(barCount)) }
    }
    @Published var barGap: Double = 1.5 {
        didSet { saveSettings(); log("barGap", barGap) }
    }
    @Published var maxHeightRatio: Double = 0.85 {
        didSet { saveSettings(); log("maxHeightRatio", maxHeightRatio) }
    }
    @Published var minBarHeight: Double = 2.0 {
        didSet { saveSettings(); log("minBarHeight", minBarHeight) }
    }
    @Published var cornerRadius: Double = 1.0 {
        didSet { saveSettings(); log("cornerRadius", cornerRadius) }
    }

    // Response
    @Published var smoothingFactor: Double = 0.5 {
        didSet { saveSettings(); log("smoothingFactor", smoothingFactor) }
    }
    @Published var baseOpacity: Double = 0.4 {
        didSet { saveSettings(); log("baseOpacity", baseOpacity) }
    }
    @Published var levelOpacityBoost: Double = 0.5 {
        didSet { saveSettings(); log("levelOpacityBoost", levelOpacityBoost) }
    }
    @Published var variationAmount: Double = 0.3 {
        didSet { saveSettings(); log("variationAmount", variationAmount) }
    }

    // Input sensitivity (how much audio level affects the waveform)
    @Published var inputSensitivity: Double = 1.0 {
        didSet { saveSettings(); log("inputSensitivity", inputSensitivity) }
    }

    private let settingsKey = "WaveformTuningSettings"
    private var isSaving = false

    private init() {
        loadSettings()
    }

    func reset() {
        isSaving = true
        defer {
            isSaving = false
            saveSettings()
        }

        barCount = 48
        barGap = 1.5
        maxHeightRatio = 0.85
        minBarHeight = 2.0
        cornerRadius = 1.0
        smoothingFactor = 0.5
        baseOpacity = 0.4
        levelOpacityBoost = 0.5
        variationAmount = 0.3
        inputSensitivity = 1.0

        AppLogger.shared.log(.ui, "Waveform tuning reset")
    }

    private func saveSettings() {
        guard !isSaving else { return }

        let settings: [String: Any] = [
            "barCount": barCount,
            "barGap": barGap,
            "maxHeightRatio": maxHeightRatio,
            "minBarHeight": minBarHeight,
            "cornerRadius": cornerRadius,
            "smoothingFactor": smoothingFactor,
            "baseOpacity": baseOpacity,
            "levelOpacityBoost": levelOpacityBoost,
            "variationAmount": variationAmount,
            "inputSensitivity": inputSensitivity
        ]

        UserDefaults.standard.set(settings, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: settingsKey) else { return }

        isSaving = true
        defer { isSaving = false }

        if let v = settings["barCount"] as? Int { barCount = v }
        if let v = settings["barGap"] as? Double { barGap = v }
        if let v = settings["maxHeightRatio"] as? Double { maxHeightRatio = v }
        if let v = settings["minBarHeight"] as? Double { minBarHeight = v }
        if let v = settings["cornerRadius"] as? Double { cornerRadius = v }
        if let v = settings["smoothingFactor"] as? Double { smoothingFactor = v }
        if let v = settings["baseOpacity"] as? Double { baseOpacity = v }
        if let v = settings["levelOpacityBoost"] as? Double { levelOpacityBoost = v }
        if let v = settings["variationAmount"] as? Double { variationAmount = v }
        if let v = settings["inputSensitivity"] as? Double { inputSensitivity = v }
    }

    private func log(_ param: String, _ value: Double) {
        #if DEBUG
        print("🔧 Waveform: \(param) = \(String(format: "%.3f", value))")
        #endif
    }
}

// MARK: - Overlay Appearance Tuning

@MainActor
final class OverlayTuning: ObservableObject {
    static let shared = OverlayTuning()

    @Published var cornerRadius: Double = 6.0 {
        didSet { saveSettings(); log("cornerRadius", cornerRadius) }
    }
    @Published var backgroundOpacity: Double = 0.6 {
        didSet { saveSettings(); log("backgroundOpacity", backgroundOpacity) }
    }

    // Dimension controls
    @Published var overlayWidth: Double = 400.0 {
        didSet { saveSettings(); log("overlayWidth", overlayWidth) }
    }
    @Published var overlayHeight: Double = 56.0 {
        didSet { saveSettings(); log("overlayHeight", overlayHeight) }
    }

    private let settingsKey = "OverlayTuningSettings"
    private var isSaving = false

    private init() {
        loadSettings()
    }

    func reset() {
        isSaving = true
        defer {
            isSaving = false
            saveSettings()
        }

        cornerRadius = 6.0
        backgroundOpacity = 0.6
        overlayWidth = 400.0
        overlayHeight = 56.0

        AppLogger.shared.log(.ui, "Overlay tuning reset")
    }

    private func saveSettings() {
        guard !isSaving else { return }

        let settings: [String: Any] = [
            "cornerRadius": cornerRadius,
            "backgroundOpacity": backgroundOpacity,
            "overlayWidth": overlayWidth,
            "overlayHeight": overlayHeight
        ]

        UserDefaults.standard.set(settings, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: settingsKey) else { return }

        isSaving = true
        defer { isSaving = false }

        if let v = settings["cornerRadius"] as? Double { cornerRadius = v }
        if let v = settings["backgroundOpacity"] as? Double { backgroundOpacity = v }
        if let v = settings["overlayWidth"] as? Double { overlayWidth = v }
        if let v = settings["overlayHeight"] as? Double { overlayHeight = v }
    }

    private func log(_ param: String, _ value: Double) {
        #if DEBUG
        print("🔧 Overlay: \(param) = \(String(format: "%.1f", value))")
        #endif
    }
}

// MARK: - Particle Tuning (Debug Controls)

@MainActor
final class ParticleTuning: ObservableObject {
    static let shared = ParticleTuning()

    // Speed controls
    @Published var baseSpeed: Double = 0.10 {
        didSet { saveCurrentSettings(); log("baseSpeed", baseSpeed) }
    }
    @Published var speedVariation: Double = 0.08 {
        didSet { saveCurrentSettings(); log("speedVariation", speedVariation) }
    }

    // Wave controls
    @Published var waveSpeed: Double = 2.5 {
        didSet { saveCurrentSettings(); log("waveSpeed", waveSpeed) }
    }
    @Published var baseAmplitude: Double = 0.35 {
        didSet { saveCurrentSettings(); log("baseAmplitude", baseAmplitude) }
    }
    @Published var audioAmplitude: Double = 0.55 {
        didSet { saveCurrentSettings(); log("audioAmplitude", audioAmplitude) }
    }

    // Particle appearance
    @Published var particleCount: Int = 80 {
        didSet { saveCurrentSettings(); log("particleCount", Double(particleCount)) }
    }
    @Published var baseSize: Double = 2.0 {
        didSet { saveCurrentSettings(); log("baseSize", baseSize) }
    }
    @Published var baseOpacity: Double = 0.45 {
        didSet { saveCurrentSettings(); log("baseOpacity", baseOpacity) }
    }

    // Smoothing (higher = faster response)
    @Published var smoothingFactor: Double = 0.35 {
        didSet { saveCurrentSettings(); log("smoothingFactor", smoothingFactor) }
    }

    // Input sensitivity (how much audio level affects the animation)
    @Published var inputSensitivity: Double = 2.0 {
        didSet { saveCurrentSettings(); log("inputSensitivity", inputSensitivity) }
    }

    // Presets
    @Published var customPresets: [ParticlePreset] = []
    @Published var activePresetId: String?

    private let settingsKey = "ParticleTuningSettings"
    private let presetsKey = "ParticleTuningPresets"
    private var isSaving = false
    private var isInitializing = true

    private init() {
        loadSettings()
        loadCustomPresets()
        isInitializing = false
    }

    // MARK: - Preset Management

    var allPresets: [ParticlePreset] {
        ParticlePreset.builtInPresets + customPresets
    }

    func apply(preset: ParticlePreset) {
        isSaving = true // Prevent multiple saves during batch update
        defer {
            isSaving = false
            saveCurrentSettings()
        }

        baseSpeed = preset.baseSpeed
        speedVariation = preset.speedVariation
        waveSpeed = preset.waveSpeed
        baseAmplitude = preset.baseAmplitude
        audioAmplitude = preset.audioAmplitude
        particleCount = preset.particleCount
        baseSize = preset.baseSize
        baseOpacity = preset.baseOpacity
        smoothingFactor = preset.smoothingFactor
        inputSensitivity = 1.0  // Reset to default when applying preset
        activePresetId = preset.id

        AppLogger.shared.log(.ui, "Applied preset", detail: preset.name)
    }

    func saveAsPreset(name: String) -> ParticlePreset {
        let preset = ParticlePreset(
            id: UUID().uuidString,
            name: name,
            baseSpeed: baseSpeed,
            speedVariation: speedVariation,
            waveSpeed: waveSpeed,
            baseAmplitude: baseAmplitude,
            audioAmplitude: audioAmplitude,
            particleCount: particleCount,
            baseSize: baseSize,
            baseOpacity: baseOpacity,
            smoothingFactor: smoothingFactor
        )

        customPresets.append(preset)
        activePresetId = preset.id
        saveCustomPresets()

        AppLogger.shared.log(.ui, "Saved preset", detail: name)
        return preset
    }

    func deletePreset(_ preset: ParticlePreset) {
        // Can't delete built-in presets
        guard !ParticlePreset.builtInPresets.contains(where: { $0.id == preset.id }) else { return }

        customPresets.removeAll { $0.id == preset.id }
        if activePresetId == preset.id {
            activePresetId = nil
        }
        saveCustomPresets()

        AppLogger.shared.log(.ui, "Deleted preset", detail: preset.name)
    }

    func reset() {
        apply(preset: .defaultPreset)
        AppLogger.shared.log(.ui, "Particle tuning reset")
    }

    // MARK: - Persistence

    private func saveCurrentSettings() {
        guard !isSaving, !isInitializing else { return }

        let settings: [String: Any] = [
            "baseSpeed": baseSpeed,
            "speedVariation": speedVariation,
            "waveSpeed": waveSpeed,
            "baseAmplitude": baseAmplitude,
            "audioAmplitude": audioAmplitude,
            "particleCount": particleCount,
            "baseSize": baseSize,
            "baseOpacity": baseOpacity,
            "smoothingFactor": smoothingFactor,
            "inputSensitivity": inputSensitivity,
            "activePresetId": activePresetId as Any
        ]

        UserDefaults.standard.set(settings, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: settingsKey) else { return }

        isSaving = true
        defer { isSaving = false }

        if let v = settings["baseSpeed"] as? Double { baseSpeed = v }
        if let v = settings["speedVariation"] as? Double { speedVariation = v }
        if let v = settings["waveSpeed"] as? Double { waveSpeed = v }
        if let v = settings["baseAmplitude"] as? Double { baseAmplitude = v }
        if let v = settings["audioAmplitude"] as? Double { audioAmplitude = v }
        if let v = settings["particleCount"] as? Int { particleCount = v }
        if let v = settings["baseSize"] as? Double { baseSize = v }
        if let v = settings["baseOpacity"] as? Double { baseOpacity = v }
        if let v = settings["smoothingFactor"] as? Double { smoothingFactor = v }
        if let v = settings["inputSensitivity"] as? Double { inputSensitivity = v }
        if let v = settings["activePresetId"] as? String { activePresetId = v }
    }

    private func saveCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    private func loadCustomPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([ParticlePreset].self, from: data) else { return }
        customPresets = presets
    }

    private func log(_ param: String, _ value: Double) {
        if !isSaving && !isInitializing {
            activePresetId = nil
        }
        #if DEBUG
        if !isInitializing {
            print("🔧 Particle: \(param) = \(String(format: "%.3f", value))")
        }
        #endif
    }
}

// MARK: - System Event Logger

@MainActor
final class SystemEventManager: ObservableObject {
    static let shared = SystemEventManager()

    @Published private(set) var events: [SystemEvent] = []
    private let maxEvents = 500

    private init() {}

    func log(_ type: EventType, _ message: String, detail: String? = nil) {
        let event = SystemEvent(type: type, message: message, detail: detail)
        events.insert(event, at: 0)

        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }

        // Also log to os_log
        let logger = Logger(subsystem: "jdi.talkie.live", category: type.rawValue)
        if let detail = detail {
            logger.info("\(message): \(detail)")
        } else {
            logger.info("\(message)")
        }
    }

    func clear() {
        events.removeAll()
    }
}

struct SystemEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp = Date()
    let type: EventType
    let message: String
    let detail: String?
}

enum EventType: String {
    case system = "system"
    case audio = "audio"
    case transcription = "transcription"
    case database = "database"
    case file = "file"
    case error = "error"
    case ui = "ui"
    case performance = "performance"

    var color: Color {
        switch self {
        case .system: return .secondary
        case .audio: return .cyan
        case .transcription: return .orange
        case .database: return .blue
        case .file: return .purple
        case .error: return .red
        case .ui: return .green
        case .performance: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .system: return "gearshape"
        case .audio: return "waveform"
        case .transcription: return "text.bubble"
        case .database: return "cylinder"
        case .file: return "doc"
        case .error: return "exclamationmark.triangle"
        case .ui: return "rectangle.3.group"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    /// Short label for console display (consistent abbreviations)
    var shortLabel: String {
        switch self {
        case .system: return "SYS"
        case .audio: return "AUDIO"
        case .transcription: return "TRANS"
        case .database: return "DB"
        case .file: return "FILE"
        case .error: return "ERR"
        case .ui: return "UI"
        case .performance: return "PERF"
        }
    }
}

/// MARK: - Milestone Types for Status Bar

enum MilestoneType: String, Equatable {
    case recordingStarted = "Recording"
    case recordingStopped = "Stopped"
    case fileSaved = "Saved"
    case transcribing = "Transcribing"
    case transcriptionComplete = "Transcribed"
    case dbSaved = "Stored"
    case routingText = "Pasting"
    case success = "Done"
}

struct Milestone: Identifiable, Equatable {
    let id = UUID()
    let type: MilestoneType
    let timestamp: Date
    var detail: String?

    var icon: String {
        switch type {
        case .recordingStarted: return "mic.fill"
        case .recordingStopped: return "stop.fill"
        case .fileSaved: return "checkmark"
        case .transcribing: return "waveform"
        case .transcriptionComplete: return "text.badge.checkmark"
        case .dbSaved: return "cylinder.fill"
        case .routingText: return "doc.on.clipboard"
        case .success: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch type {
        case .recordingStarted, .recordingStopped: return .red
        case .fileSaved: return .green
        case .transcribing: return .orange
        case .transcriptionComplete: return .blue
        case .dbSaved: return .purple
        case .routingText: return .cyan
        case .success: return .green
        }
    }

    /// Human-readable tooltip text for hover
    var tooltipText: String {
        let baseText: String
        switch type {
        case .recordingStarted: baseText = "Recording started"
        case .recordingStopped: baseText = "Recording stopped"
        case .fileSaved: baseText = "Audio file saved"
        case .transcribing: baseText = "Transcribing audio..."
        case .transcriptionComplete: baseText = "Transcription complete"
        case .dbSaved: baseText = "Saved to database"
        case .routingText: baseText = "Pasting text..."
        case .success: baseText = "Pipeline complete"
        }

        if let detail = detail {
            return "\(baseText) (\(detail))"
        }
        return baseText
    }
}

// MARK: - Processing Milestone Tracker

@MainActor
final class ProcessingMilestones: ObservableObject {
    static let shared = ProcessingMilestones()

    @Published var milestones: [Milestone] = []
    @Published var fileSaved: Bool = false
    @Published var savedFilename: String?
    @Published var transcriptionComplete: Bool = false
    @Published var dbRecordStored: Bool = false

    var latestMilestone: Milestone? {
        milestones.last
    }

    private init() {}

    func reset() {
        milestones = []
        fileSaved = false
        savedFilename = nil
        transcriptionComplete = false
        dbRecordStored = false
    }

    func addMilestone(_ type: MilestoneType, detail: String? = nil) {
        let milestone = Milestone(type: type, timestamp: Date(), detail: detail)
        milestones.append(milestone)
    }

    func markRecordingStarted() {
        addMilestone(.recordingStarted)
    }

    func markRecordingStopped() {
        addMilestone(.recordingStopped)
    }

    func markFileSaved(filename: String) {
        fileSaved = true
        savedFilename = filename
        addMilestone(.fileSaved)
    }

    func markTranscribing() {
        addMilestone(.transcribing)
    }

    func markTranscriptionComplete(wordCount: Int? = nil) {
        transcriptionComplete = true
        let detail = wordCount.map { "\($0)w" }
        addMilestone(.transcriptionComplete, detail: detail)
    }

    func markDbRecordStored() {
        dbRecordStored = true
        addMilestone(.dbSaved)
    }

    func markRouting() {
        addMilestone(.routingText)
    }

    func markSuccess() {
        addMilestone(.success)
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @ObservedObject private var events = SystemEventManager.shared
    @ObservedObject private var controller = RecordingOverlayController.shared
    @ObservedObject private var milestones = ProcessingMilestones.shared
    @ObservedObject private var whisperService = WhisperService.shared
    @ObservedObject private var engineClient = EngineClient.shared
    @State private var recordingDuration: TimeInterval = 0
    @State private var processingDuration: TimeInterval = 0
    @State private var warmupDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @State private var warmupTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    @State private var showSuccess: Bool = false
    @State private var successTimer: Timer?

    // PID display state
    @State private var isHovered = false
    @State private var showPID = false
    @State private var pidCopied = false
    private let pid = ProcessInfo.processInfo.processIdentifier

    private var errorCount: Int {
        events.events.filter { $0.type == .error }.count
    }

    private var warningCount: Int {
        events.events.filter { $0.type == .audio || $0.type == .database || $0.type == .file }.count
    }

    private var infoCount: Int {
        events.events.filter { $0.type == .system || $0.type == .transcription || $0.type == .ui }.count
    }

    /// Estimated warmup time based on model size
    private var estimatedWarmupTime: String {
        let (family, modelId) = ModelInfo.parseModelId(LiveSettings.shared.selectedModelId)
        if family == "parakeet" {
            return "~5s"  // Parakeet models load faster
        }
        // Whisper models
        switch modelId {
        case "openai_whisper-tiny": return "~10s"
        case "openai_whisper-base": return "~15s"
        case "openai_whisper-small": return "~25s"
        case "distil-whisper_distil-large-v3": return "~45s"
        default: return "~20s"
        }
    }

    /// Get a display name for the current model
    private var currentModelDisplayName: String {
        let (family, modelId) = ModelInfo.parseModelId(LiveSettings.shared.selectedModelId)
        if let modelFamily = ModelFamily(rawValue: family) {
            return "\(modelFamily.displayName) \(modelId)"
        }
        return modelId
    }

    /// Get a short name for the current model
    private var currentModelShortName: String {
        let (family, modelId) = ModelInfo.parseModelId(LiveSettings.shared.selectedModelId)
        if family == "parakeet" {
            return "Parakeet"
        }
        // Return just the base model name for whisper
        return modelId.replacingOccurrences(of: "openai_whisper-", with: "")
                      .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
    }

    private var statusText: String {
        // Warmup takes priority
        if whisperService.isWarmingUp { return "Warming up" }
        if showSuccess { return "Done" }
        switch controller.state {
        case .idle: return "Ready"
        case .listening: return "Recording"
        case .transcribing: return "Processing"
        case .routing: return "Routing"
        }
    }

    private var statusColor: Color {
        if whisperService.isWarmingUp { return SemanticColor.info }
        if showSuccess { return SemanticColor.success }
        switch controller.state {
        case .idle: return TalkieTheme.textMuted
        case .listening: return .red  // Keep red for the indicator, but not alarming
        case .transcribing: return SemanticColor.warning
        case .routing: return SemanticColor.success
        }
    }

    /// Background stays neutral - pill handles state colors
    private var barBackgroundColor: Color {
        // Only subtle tint during warmup, otherwise stay neutral
        if whisperService.isWarmingUp { return SemanticColor.info.opacity(0.08) }
        return TalkieTheme.surfaceElevated
    }

    private var isActive: Bool {
        whisperService.isWarmingUp || controller.state != .idle || showSuccess
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)

            ZStack {
                // Center - LivePill with optional PID display
                HStack(spacing: 8) {
                    LivePill(
                        state: controller.state,
                        isWarmingUp: whisperService.isWarmingUp,
                        showSuccess: showSuccess,
                        recordingDuration: recordingDuration,
                        processingDuration: processingDuration,
                        isEngineConnected: engineClient.isConnected,
                        pendingQueueCount: LiveDatabase.countNeedsRetry(),
                        micDeviceName: AudioDeviceManager.shared.selectedDeviceName,
                        audioLevel: AudioLevelMonitor.shared.level,
                        identifier: "debug",
                        onTap: toggleRecording
                    )

                    // PID appears next to pill on Control+hover
                    if showPID {
                        Button(action: copyPID) {
                            Text("\(pid)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(pidCopied ? SemanticColor.success : TalkieTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(TalkieTheme.hover)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy PID")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .fixedSize()

                // Left/Right content (won't affect pill centering)
                HStack(spacing: Spacing.sm) {
                    // Left - Hotkey hints (always visible since pill is independently centered)
                    ShortcutHint(
                        label: "Record",
                        shortcut: LiveSettings.shared.hotkey.displayString
                    )
                    ShortcutHint(
                        label: "Queue",
                        shortcut: "⌥⌘V"
                    )

                    Spacer()

                    // Right side - status icons: Mic → Engine → Model → Logs
                    MicStatusIcon()
                    EngineStatusIcon()
                    ModelStatusIcon()
                    LogStatusIcon(
                        errorCount: errorCount,
                        warningCount: warningCount,
                        infoCount: infoCount
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 32)
        .background(barBackgroundColor)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: showPID)
        .drawingGroup()
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Control modifier while hovering
                let controlHeld = NSEvent.modifierFlags.contains(.control)
                if controlHeld != showPID {
                    withAnimation { showPID = controlHeld }
                }
            case .ended:
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onChange(of: controller.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onChange(of: whisperService.isWarmingUp) { _, isWarmingUp in
            if isWarmingUp {
                startWarmupTimer()
            } else {
                stopWarmupTimer()
            }
        }
    }

    private func copyPID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
        }
    }

    private func handleStateChange(from oldState: LiveState, to newState: LiveState) {
        // Recording timer
        if newState == .listening {
            startRecordingTimer()
            milestones.reset()
        } else if oldState == .listening {
            stopRecordingTimer()
        }

        // Processing timer
        if newState == .transcribing {
            startProcessingTimer()
        } else if oldState == .transcribing {
            stopProcessingTimer()
        }

        // Show success state when we return to idle after routing
        if newState == .idle && oldState == .routing {
            showSuccessState()
        }
    }

    private func showSuccessState() {
        showSuccess = true
        successTimer?.invalidate()
        successTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    showSuccess = false
                }
            }
        }
    }

    /// Status indicator - embedded pill style (matches FloatingPill exactly)
    @ViewBuilder
    private var statusIndicator: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 4) {
                // State indicator dot
                statusDot

                // Content varies by state
                statusContent
            }
            .frame(minWidth: 70, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.white.opacity(0.15)),
                alignment: .top
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusDot: some View {
        let dotColor: Color = {
            if whisperService.isWarmingUp { return SemanticColor.info }
            if showSuccess { return SemanticColor.success }
            switch controller.state {
            case .idle: return TalkieTheme.textMuted
            case .listening: return .red
            case .transcribing: return SemanticColor.warning
            case .routing: return SemanticColor.success
            }
        }()

        Circle()
            .fill(dotColor)
            .frame(width: 6, height: 6)
            .scaleEffect(controller.state == .listening ? 1.0 + pulseScale * 0.4 : 1.0)
            .opacity(controller.state == .listening ? 0.7 + pulseScale * 0.3 : 1.0)
            .shadow(color: controller.state == .listening ? dotColor.opacity(0.5) : .clear, radius: 3)
    }

    @ViewBuilder
    private var statusContent: some View {
        if whisperService.isWarmingUp {
            Text("Warming up")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SemanticColor.info)
        } else if showSuccess {
            // Success: green checkmark icon
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(SemanticColor.success)
        } else {
            switch controller.state {
            case .idle:
                Text("Ready")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
            case .listening:
                // Timer + audio level (like pill)
                HStack(spacing: 3) {
                    Text(formatRecordingTime(recordingDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textSecondary)
                    verticalAudioLevel
                }
            case .transcribing:
                // Processing dots (ellipsis)
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SemanticColor.warning)
            case .routing:
                // Green checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(SemanticColor.success)
            }
        }
    }

    private func toggleRecording() {
        // Post notification to toggle recording (AppDelegate handles this)
        NotificationCenter.default.post(name: .toggleRecording, object: nil)
    }

    /// Concise recording pill: matches FloatingPill design exactly
    private var recordingPill: some View {
        HStack(spacing: 4) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(1.0 + (pulseScale - 1.0) * 0.4)

            // Timer - simple seconds format
            Text(formatRecordingTime(recordingDuration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TalkieTheme.textSecondary)

            // Vertical audio level indicator
            verticalAudioLevel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
        )
    }

    /// Vertical audio level indicator - bar grows upward from the bottom
    private var verticalAudioLevel: some View {
        let level = CGFloat(AudioLevelMonitor.shared.level)
        let barHeight = max(2, 12 * level)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(TalkieTheme.textTertiary.opacity(0.5 + Double(level) * 0.4))
                .frame(width: 3, height: barHeight)
                .animation(.easeOut(duration: 0.08), value: level)
        }
        .frame(width: 3, height: 12)
    }

    /// Format recording time - simple seconds (no leading zeros)
    private func formatRecordingTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let tenths = Int((time * 10).truncatingRemainder(dividingBy: 10))
        if totalSeconds < 60 {
            return "\(totalSeconds).\(tenths)"
        } else {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes):\(String(format: "%02d", seconds)).\(tenths)"
        }
    }

    private var pulsingDot: some View {
        ZStack {
            // Outer pulsing ring - subtle animation
            if controller.state == .listening || controller.state == .transcribing {
                Circle()
                    .stroke(statusColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulseScale)
                    .opacity(1.5 - pulseScale * 0.5)
            }

            // Inner filled circle - very subtle pulse
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .scaleEffect(controller.state == .listening ? (0.95 + (pulseScale - 1.0) * 0.1) : 1.0)
        }
        .onChange(of: controller.state) { _, newState in
            if newState == .listening || newState == .transcribing {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }

    private func startPulseAnimation() {
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            pulseScale = 1.0
        }
    }

    // Model info now shown in engine status indicator, not here

    @ViewBuilder
    private var rightSideContent: some View {
        // Warmup takes priority
        if whisperService.isWarmingUp {
            HStack(spacing: 6) {
                // Model name
                Text(currentModelShortName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(statusColor.opacity(0.6))

                // Timer and estimate
                HStack(spacing: 4) {
                    Text(formatDuration(warmupDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(statusColor.opacity(0.7))

                    Text("(expect \(estimatedWarmupTime))")
                        .font(.system(size: 9))
                        .foregroundColor(statusColor.opacity(0.4))
                }
            }
            .padding(.trailing, 4)
        } else {
            regularRightContent
        }
    }

    @ViewBuilder
    private var regularRightContent: some View {
        switch controller.state {
        case .listening:
            // Timer now on left side - nothing here
            EmptyView()

        case .transcribing:
            // Milestone trail on the right - shows checkpoints as they happen
            HStack(spacing: 4) {
                // Show completed milestones as small icons with tooltips
                ForEach(milestones.milestones.suffix(3)) { milestone in
                    HStack(spacing: 2) {
                        Image(systemName: milestone.icon)
                            .font(.system(size: 8))
                            .foregroundColor(milestone.color.opacity(0.7))

                        if let detail = milestone.detail {
                            Text(detail)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(milestone.color.opacity(0.6))
                        }
                    }
                    .help(milestone.tooltipText)
                }

                // Processing timer
                Text(formatProcessingDuration(processingDuration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(statusColor.opacity(0.5))
            }
            .padding(.trailing, 4)

        case .routing:
            // Show milestone trail during routing too
            HStack(spacing: 4) {
                ForEach(milestones.milestones.suffix(3)) { milestone in
                    Image(systemName: milestone.icon)
                        .font(.system(size: 8))
                        .foregroundColor(milestone.color.opacity(0.6))
                        .help(milestone.tooltipText)
                }
            }
            .padding(.trailing, 4)

        case .idle:
            // During success state, show the final milestone trail briefly
            if showSuccess {
                HStack(spacing: 4) {
                    ForEach(milestones.milestones.suffix(4)) { milestone in
                        Image(systemName: milestone.icon)
                            .font(.system(size: 8))
                            .foregroundColor(milestone.color.opacity(0.5))
                            .help(milestone.tooltipText)
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                recordingDuration += 0.1
            }
        }
    }

    private func stopRecordingTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
    }

    private func startProcessingTimer() {
        processingDuration = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                processingDuration += 0.1
            }
        }
    }

    private func stopProcessingTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        processingDuration = 0
    }

    private func startWarmupTimer() {
        warmupDuration = 0
        warmupTimer?.invalidate()
        warmupTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                warmupDuration += 0.1
            }
        }
    }

    private func stopWarmupTimer() {
        warmupTimer?.invalidate()
        warmupTimer = nil
        warmupDuration = 0
    }

    // MARK: - Engine Status Indicator

    @ViewBuilder
    private var engineStatusIndicator: some View {
        Button(action: openTalkieEngine) {
            HStack(spacing: 4) {
                // Connection status dot
                Circle()
                    .fill(engineStatusColor)
                    .frame(width: 5, height: 5)

                // Engine label with model
                if let status = engineClient.status {
                    if let model = status.loadedModelId {
                        // Model loaded - show in green
                        Text(formatModelName(model))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(SemanticColor.success)
                    } else {
                        // Connected but no model
                        Text("Engine")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(TalkieTheme.textMuted.opacity(0.8))
                    }

                    // DEV badge only
                    if let isDebug = status.isDebugBuild, isDebug {
                        Text("DEV")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(2)
                    }
                } else {
                    Text("Engine")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textMuted.opacity(0.5))

                    Text("offline")
                        .font(.system(size: 9))
                        .foregroundColor(.red.opacity(0.6))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(TalkieTheme.surfaceCard.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .help("Click to open TalkieEngine")
    }

    private var engineStatusColor: Color {
        switch engineClient.connectionState {
        case .connected:
            return .green
        case .connectedWrongBuild:
            return .yellow
        case .connecting:
            return .orange
        case .disconnected, .error:
            return .red
        }
    }

    private func formatModelName(_ modelId: String) -> String {
        // Extract just the model name without family prefix
        if modelId.contains(":") {
            let parts = modelId.split(separator: ":")
            if parts.count == 2 {
                let family = String(parts[0])
                let model = String(parts[1])
                if family == "parakeet" {
                    return "Parakeet"
                }
                return model.replacingOccurrences(of: "openai_whisper-", with: "")
                           .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
            }
        }
        return modelId
    }

    private func openTalkieEngine() {
        // Try to open TalkieEngine app
        let engineBundleIds = [
            "jdi.talkie.engine",       // Production
            "jdi.talkie.engine.dev"    // Debug
        ]

        for bundleId in engineBundleIds {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }

        // Fallback: try opening by path
        let possiblePaths = [
            "/Applications/TalkieEngine.app",
            "\(NSHomeDirectory())/Applications/TalkieEngine.app"
        ]

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let tenths = Int((duration - Double(seconds)) * 10)
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        } else {
            return String(format: "%d.%d", secs, tenths)
        }
    }

    private func formatProcessingDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let tenths = Int((duration - Double(seconds)) * 10)
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d", mins, secs)
        } else {
            return String(format: "%d.%ds", seconds, tenths)
        }
    }
}

// MARK: - Status Icons (Mic → Engine → Model)

/// Unified status icon style - icon with color, always shows label
struct StatusIcon: View {
    let icon: String
    let color: Color
    let label: String
    let detail: String?
    var badge: String? = nil
    var badgeColor: Color = .orange
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .lineLimit(1)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.2))
                        .cornerRadius(2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(detail ?? label)
    }
}

/// Mic input status
struct MicStatusIcon: View {
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    private var selectedDevice: AudioInputDevice? {
        audioDevices.inputDevices.first { $0.id == audioDevices.selectedDeviceID }
    }

    private var deviceName: String {
        guard let device = selectedDevice else { return "No Input" }
        let name = device.name
        if name.contains("MacBook") { return "Built-in" }
        if name.contains("AirPods") { return "AirPods" }
        if name.lowercased().contains("microphone") {
            return name.replacingOccurrences(of: " Microphone", with: "", options: .caseInsensitive)
        }
        return name.count > 12 ? String(name.prefix(10)) + "…" : name
    }

    private var statusColor: Color {
        if selectedDevice == nil { return SemanticColor.error }
        if audioMonitor.isSilent { return SemanticColor.warning }
        return SemanticColor.success
    }

    var body: some View {
        StatusIcon(
            icon: selectedDevice == nil ? "mic.slash" : "mic",
            color: statusColor,
            label: deviceName,
            detail: selectedDevice?.name ?? "No audio input - Click to open Audio settings",
            action: navigateToAudioSettings
        )
    }

    private func navigateToAudioSettings() {
        NotificationCenter.default.post(name: .switchToSettingsAudio, object: nil)
    }
}

/// Engine connection status
struct EngineStatusIcon: View {
    @ObservedObject private var engineClient = EngineClient.shared
    @State private var isHovered = false
    @State private var showPID = false
    @State private var pidCopied = false

    private var statusColor: Color {
        switch engineClient.connectionState {
        case .connected: return SemanticColor.success
        case .connectedWrongBuild: return SemanticColor.warning
        case .connecting: return SemanticColor.info
        case .disconnected, .error: return SemanticColor.error
        }
    }

    private var label: String {
        switch engineClient.connectionState {
        case .connected, .connectedWrongBuild:
            // Show which XPC service we're connected to
            if let mode = engineClient.connectedMode {
                return mode.shortName
            }
            return "Engine"
        case .connecting: return "Connecting"
        case .disconnected, .error: return "Offline"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusIcon(
                icon: "cpu",
                color: statusColor,
                label: label,
                detail: "TalkieEngine - Click: Settings, Shift+Click: Reconnect",
                action: handleClick
            )

            // PID appears on Ctrl+hover
            if showPID, let pid = engineClient.status?.pid {
                Button(action: { copyPID(pid) }) {
                    Text("\(pid)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(pidCopied ? SemanticColor.success : TalkieTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TalkieTheme.hover)
                        )
                }
                .buttonStyle(.plain)
                .help("Click to copy PID")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Control modifier while hovering
                let controlHeld = NSEvent.modifierFlags.contains(.control)
                if controlHeld != showPID {
                    withAnimation { showPID = controlHeld }
                }
            case .ended:
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
    }

    private func copyPID(_ pid: Int32) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
        }
    }

    private func handleClick() {
        // Check for Shift modifier
        if NSEvent.modifierFlags.contains(.shift) {
            // Shift+Click: Reconnect engine
            AppLogger.shared.log(.system, "Manual engine reconnect", detail: "User triggered via Shift+Click")
            engineClient.reconnect()
        } else {
            // Normal click: Navigate to settings
            navigateToEngineSettings()
        }
    }

    private func navigateToEngineSettings() {
        NotificationCenter.default.post(name: .switchToSettingsEngine, object: nil)
    }
}

/// Model status
struct ModelStatusIcon: View {
    @ObservedObject private var engineClient = EngineClient.shared

    private var modelName: String {
        guard let status = engineClient.status, let modelId = status.loadedModelId else {
            return "No Model"
        }
        // Format model name
        if modelId.contains(":") {
            let parts = modelId.split(separator: ":")
            if parts.count == 2 {
                let family = String(parts[0])
                if family == "parakeet" { return "Parakeet" }
                return String(parts[1])
                    .replacingOccurrences(of: "openai_whisper-", with: "")
                    .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
            }
        }
        return modelId
    }

    private var statusColor: Color {
        guard let status = engineClient.status else { return TalkieTheme.textMuted }
        if status.loadedModelId != nil { return SemanticColor.success }
        return SemanticColor.warning
    }

    private var hasModel: Bool {
        engineClient.status?.loadedModelId != nil
    }

    var body: some View {
        StatusIcon(
            icon: hasModel ? "waveform" : "waveform.slash",
            color: statusColor,
            label: modelName,
            detail: (engineClient.status?.loadedModelId ?? "No model loaded") + " - Click to open Transcription settings",
            action: navigateToEngineSettings
        )
    }

    private func navigateToEngineSettings() {
        NotificationCenter.default.post(name: .switchToSettingsEngine, object: nil)
    }
}

/// Log/Console status - shows error/warning/info counts
struct LogStatusIcon: View {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int

    @State private var isHovered = false
    @State private var showConsolePopover = false

    private var statusColor: Color {
        if errorCount > 0 { return SemanticColor.error }
        if warningCount > 0 { return SemanticColor.warning }
        return SemanticColor.success
    }

    private var icon: String {
        if errorCount > 0 { return "xmark.circle" }
        if warningCount > 0 { return "exclamationmark.triangle" }
        return "checkmark.circle"
    }

    var body: some View {
        Button(action: { showConsolePopover.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(statusColor)

                // Always show counts
                if errorCount > 0 {
                    Text("\(errorCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SemanticColor.error)
                }
                if warningCount > 0 {
                    Text("\(warningCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SemanticColor.warning)
                }
                Text("\(infoCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Console - \(errorCount) errors, \(warningCount) warnings, \(infoCount) info")
        .popover(isPresented: $showConsolePopover, arrowEdge: .bottom) {
            ConsolePopover()
        }
    }
}

// MARK: - Shortcut Hint (label + keyboard shortcut)

struct ShortcutHint: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.7))

            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)  // Subtle letter spacing
                .foregroundColor(TalkieTheme.textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .offset(y: -1)  // Move up 1 pixel
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .offset(y: -1)  // Background moves with content
        )
    }
}

// MARK: - Log Preview (clickable with popover - just icons with counts)

struct LogPreview: View {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int

    @State private var isHovered = false
    @State private var showConsolePopover = false

    var body: some View {
        Button(action: { showConsolePopover.toggle() }) {
            HStack(spacing: 5) {
                // Color-coded counts only - compact
                // Errors (red)
                if errorCount > 0 {
                    LogCountBadge(count: errorCount, color: .red, icon: "xmark.circle.fill")
                }

                // Warnings (yellow/orange)
                if warningCount > 0 {
                    LogCountBadge(count: warningCount, color: .orange, icon: "exclamationmark.triangle.fill")
                }

                // Info (green) - always show
                LogCountBadge(count: infoCount, color: .green, icon: "checkmark.circle.fill")

                // Small chevron indicator
                Image(systemName: "chevron.up")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(TalkieTheme.textMuted.opacity(0.6))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? TalkieTheme.surfaceCard : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showConsolePopover, arrowEdge: .bottom) {
            ConsolePopover()
        }
    }
}

// MARK: - Console Popover

struct ConsolePopover: View {
    @ObservedObject private var events = SystemEventManager.shared
    @Environment(\.dismiss) private var dismiss

    private var recentEvents: [SystemEvent] {
        Array(events.events.prefix(15))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("CONSOLE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                // Expand to full logs view (arrows icon)
                Button(action: openFullLogs) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Open full logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.1))

            Divider()

            // Events list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if recentEvents.isEmpty {
                        Text("No events")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(12)
                    } else {
                        ForEach(recentEvents) { event in
                            ConsolePopoverRow(event: event)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)

            Divider()

            // Footer with Clear button
            HStack {
                Text("\(events.events.count) total events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))

                Spacer()

                Button("Clear") {
                    events.clear()
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.1))
        }
        .frame(width: 400)
        .background(Color(white: 0.08))
    }

    private func openFullLogs() {
        dismiss()
        // Post notification to switch to logs section
        NotificationCenter.default.post(name: .switchToLogs, object: nil)
    }
}

extension Notification.Name {
    static let switchToLogs = Notification.Name("switchToLogs")
    static let switchToSettings = Notification.Name("switchToSettings")
    static let switchToSettingsAudio = Notification.Name("switchToSettingsAudio")
    static let switchToSettingsEngine = Notification.Name("switchToSettingsEngine")
    static let toggleRecording = Notification.Name("toggleRecording")
}

struct ConsolePopoverRow: View {
    let event: SystemEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 50, alignment: .leading)

            // Type indicator
            Circle()
                .fill(event.type.color)
                .frame(width: 6, height: 6)
                .padding(.top, 3)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)

                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(event.type == .error ? Color.red.opacity(0.1) : Color.clear)
    }
}

struct LogCountBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundColor(color.opacity(0.8))
    }
}

// MARK: - Console View

struct ConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var events = SystemEventManager.shared
    @State private var filterType: EventType? = nil
    @State private var searchText = ""

    private var filteredEvents: [SystemEvent] {
        var result = events.events

        if let type = filterType {
            result = result.filter { $0.type == type }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                ($0.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CONSOLE")
                    .font(.techLabel)
                    .tracking(Tracking.wide)

                Spacer()

                // Filter pills
                HStack(spacing: 4) {
                    filterPill(nil, "All")
                    filterPill(.error, "Errors")
                    filterPill(.transcription, "Transcription")
                    filterPill(.database, "DB")
                }

                Spacer()

                Button("Clear") {
                    events.clear()
                }
                .font(.labelSmall)
                .buttonStyle(.tiny)

                Button("Close") {
                    dismiss()
                }
                .font(.labelSmall)
            }
            .padding(Spacing.md)
            .background(TalkieTheme.surfaceElevated)

            Divider()

            // Search
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.monoXSmall)
                    .foregroundColor(TalkieTheme.textMuted)

                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.monoSmall)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(TalkieTheme.surfaceCard)

            Divider()

            // Log list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEvents) { event in
                        ConsoleEventRow(event: event)
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
        .background(TalkieTheme.surface)
    }

    private func filterPill(_ type: EventType?, _ label: String) -> some View {
        Button(action: { filterType = type }) {
            Text(label)
                .font(.monoXSmall)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(filterType == type ? TalkieTheme.accent.opacity(0.2) : Color.clear)
                )
                .foregroundColor(filterType == type ? TalkieTheme.accent : TalkieTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct ConsoleEventRow: View {
    let event: SystemEvent
    @State private var isExpanded = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                // Timestamp
                Text(timeString)
                    .font(.monoXSmall)
                    .foregroundColor(TalkieTheme.textMuted)
                    .frame(width: 80, alignment: .leading)

                // Type badge
                HStack(spacing: 2) {
                    Image(systemName: event.type.icon)
                        .font(.system(size: 8))
                    Text(event.type.rawValue.uppercased())
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundColor(event.type.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(event.type.color.opacity(0.15))
                .cornerRadius(3)

                // Message
                Text(event.message)
                    .font(.monoSmall)
                    .foregroundColor(TalkieTheme.textPrimary)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()

                // Expand button if has detail
                if event.detail != nil {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)

            // Detail (expanded)
            if isExpanded, let detail = event.detail {
                Text(detail)
                    .font(.monoXSmall)
                    .foregroundColor(TalkieTheme.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.leading, 90) // Align with message
                    .padding(.bottom, Spacing.xs)
            }

            Divider()
                .opacity(0.5)
        }
        .background(event.type == .error ? SemanticColor.error.opacity(0.05) : Color.clear)
    }
}

// MARK: - Embedded Console View (matches Settings styling)

struct EmbeddedConsoleView: View {
    @ObservedObject private var events = SystemEventManager.shared
    @State private var filterType: EventType? = nil
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var selectedEvents: Set<UUID> = []
    @State private var isSelectionMode = false

    // Column widths for consistent alignment
    private let checkboxWidth: CGFloat = 24
    private let timestampWidth: CGFloat = 85
    private let typeWidth: CGFloat = 75
    private let messageMinWidth: CGFloat = 150

    private var filteredEvents: [SystemEvent] {
        var result = events.events

        if let type = filterType {
            result = result.filter { $0.type == type }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                ($0.detail?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row: filters + search + clear
            consoleToolbar

            Rectangle()
                .fill(MidnightSurface.divider)
                .frame(height: 0.5)

            // Column headers
            columnHeaders

            Rectangle()
                .fill(MidnightSurface.divider)
                .frame(height: 0.5)

            // Log output - full bleed
            consoleOutput

            Rectangle()
                .fill(MidnightSurface.divider)
                .frame(height: 0.5)

            // Status bar
            statusBar
        }
        .background(MidnightSurface.content)
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: Spacing.sm) {
            // Filter chips with category colors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterChip(nil, label: "All", color: .white)
                    filterChip(.error, label: "Errors", color: EventType.error.color)
                    filterChip(.audio, label: "Audio", color: EventType.audio.color)
                    filterChip(.transcription, label: "Trans", color: EventType.transcription.color)
                    filterChip(.database, label: "DB", color: EventType.database.color)
                    filterChip(.file, label: "File", color: EventType.file.color)
                    filterChip(.ui, label: "UI", color: EventType.ui.color)
                    filterChip(.system, label: "Sys", color: EventType.system.color)
                }
            }

            Spacer()

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(MidnightSurface.Text.tertiary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(MidnightSurface.Text.primary)
                    .frame(width: 120)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(MidnightSurface.Text.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background(MidnightSurface.elevated)
            .cornerRadius(CornerRadius.xs)

            // Selection mode toggle
            Button(action: {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedEvents.removeAll()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 9))
                    Text("Select")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(isSelectionMode ? .accentColor : MidnightSurface.Text.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(isSelectionMode ? Color.accentColor.opacity(0.15) : MidnightSurface.elevated)
                .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)

            // Copy selected button (only shown when in selection mode with items selected)
            if isSelectionMode && !selectedEvents.isEmpty {
                Button(action: copySelectedEvents) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy (\(selectedEvents.count))")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }

            // Clear button
            Button(action: { events.clear() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(MidnightSurface.Text.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(MidnightSurface.elevated)
                .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(MidnightSurface.sidebar)
    }

    // MARK: - Copy Events

    private func copySelectedEvents() {
        let eventsToFormat = events.events.filter { selectedEvents.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }

        var lines: [Swift.String] = []
        for event in eventsToFormat {
            let timestamp = ConsoleEventRowStyled.timeFormatter.string(from: event.timestamp)
            let detail: Swift.String = event.detail.map { " | \($0)" } ?? ""
            let line: Swift.String = "[\(timestamp)] [\(event.type.shortLabel)] \(event.message)\(detail)"
            lines.append(line)
        }
        let copyText: Swift.String = lines.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text"))

        // Clear selection after copy
        selectedEvents.removeAll()
        isSelectionMode = false
    }

    private func filterChip(_ type: EventType?, label: String, color: Color) -> some View {
        let isSelected = filterType == type

        return Button(action: { filterType = type }) {
            Text(label)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : color.opacity(0.8))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? color.opacity(0.8) : color.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(alignment: .center, spacing: 0) {
            // Select all checkbox (only in selection mode)
            if isSelectionMode {
                Button(action: toggleSelectAll) {
                    Image(systemName: allFilteredSelected ? "checkmark.square.fill" : (selectedEvents.isEmpty ? "square" : "minus.square"))
                        .font(.system(size: 10))
                        .foregroundColor(selectedEvents.isEmpty ? MidnightSurface.Text.quaternary : .accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: checkboxWidth, alignment: .center)
            }

            Text("TIME")
                .frame(width: timestampWidth, alignment: .leading)

            Text("TYPE")
                .frame(width: typeWidth, alignment: .leading)

            Text("MESSAGE")
                .frame(minWidth: messageMinWidth, alignment: .leading)

            Spacer(minLength: Spacing.sm)

            Text("DETAILS")
                .frame(alignment: .leading)

            Spacer(minLength: Spacing.md)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .tracking(0.5)
        .foregroundColor(MidnightSurface.Text.quaternary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(MidnightSurface.sidebar.opacity(0.5))
    }

    private var allFilteredSelected: Bool {
        let filteredIds = Set(filteredEvents.map { $0.id })
        return !filteredIds.isEmpty && filteredIds.isSubset(of: selectedEvents)
    }

    private func toggleSelectAll() {
        let filteredIds = Set(filteredEvents.map { $0.id })
        if allFilteredSelected {
            selectedEvents.subtract(filteredIds)
        } else {
            selectedEvents.formUnion(filteredIds)
        }
    }

    // MARK: - Console Output

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEvents.reversed()) { event in
                        ConsoleEventRowStyled(
                            event: event,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedEvents.contains(event.id),
                            checkboxWidth: checkboxWidth,
                            timestampWidth: timestampWidth,
                            typeWidth: typeWidth,
                            messageMinWidth: messageMinWidth,
                            onToggleSelection: { toggleSelection(for: event.id) }
                        )
                        .id(event.id)
                    }
                }
            }
            .onChange(of: events.events.count) { _, _ in
                if autoScroll, let newestEvent = filteredEvents.first {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newestEvent.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if autoScroll, let newestEvent = filteredEvents.first {
                    proxy.scrollTo(newestEvent.id, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MidnightSurface.content)
    }

    private func toggleSelection(for id: UUID) {
        if selectedEvents.contains(id) {
            selectedEvents.remove(id)
        } else {
            selectedEvents.insert(id)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: Spacing.md) {
            // Event count
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 9))
                    .foregroundColor(MidnightSurface.Text.quaternary)
                Text("\(filteredEvents.count) events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(MidnightSurface.Text.tertiary)
            }

            Spacer()

            // Error count
            let errorCount = events.events.filter { $0.type == .error }.count
            if errorCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(SemanticColor.error)
                        .frame(width: 5, height: 5)
                    Text("\(errorCount) errors")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(SemanticColor.error.opacity(0.8))
                }
            }

            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("Auto-scroll")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(autoScroll ? .accentColor : MidnightSurface.Text.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(MidnightSurface.sidebar)
    }
}

// MARK: - Console Event Row (styled to match settings)

struct ConsoleEventRowStyled: View {
    let event: SystemEvent
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var checkboxWidth: CGFloat = 24
    let timestampWidth: CGFloat
    let typeWidth: CGFloat
    let messageMinWidth: CGFloat
    var onToggleSelection: (() -> Void)? = nil

    @State private var isHovered = false

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Checkbox (only in selection mode)
            if isSelectionMode {
                Button(action: { onToggleSelection?() }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .accentColor : MidnightSurface.Text.quaternary)
                }
                .buttonStyle(.plain)
                .frame(width: checkboxWidth, alignment: .center)
            }

            // Timestamp
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(MidnightSurface.Text.quaternary)
                .frame(width: timestampWidth, alignment: .leading)

            // Type badge
            HStack(spacing: 3) {
                Image(systemName: event.type.icon)
                    .font(.system(size: 8))
                Text(event.type.shortLabel)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(event.type.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(event.type.color.opacity(0.15))
            .cornerRadius(3)
            .frame(width: typeWidth, alignment: .leading)

            // Message - left aligned
            Text(event.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(MidnightSurface.Text.primary)
                .lineLimit(1)
                .frame(minWidth: messageMinWidth, alignment: .leading)

            Spacer(minLength: Spacing.sm)

            // Detail - left aligned (not right)
            if let detail = event.detail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(MidnightSurface.Text.tertiary)
                    .lineLimit(1)
                    .frame(alignment: .leading)
            }

            Spacer(minLength: Spacing.md)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection?()
            }
        }
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return MidnightSurface.elevated
        } else if event.type == .error {
            return SemanticColor.error.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Tactical Event Row

struct TacticalEventRow: View {
    let event: SystemEvent
    @State private var isHovering = false

    private let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timestamp column - fixed width
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 75, alignment: .leading)
                .padding(.trailing, 8)

            // Type badge column - fixed width with icon
            HStack(spacing: 4) {
                Image(systemName: event.type.icon)
                    .font(.system(size: 8))
                    .foregroundColor(event.type.color.opacity(0.7))

                Text(event.type.shortLabel.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(event.type.color)
            }
            .frame(width: 65, alignment: .leading)
            .padding(.trailing, 8)

            // Message column - flexible
            Text(event.message)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .frame(minWidth: 120, maxWidth: 180, alignment: .leading)
                .padding(.trailing, 8)

            // Detail column - takes remaining space
            if let detail = event.detail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(rowBackground)
        .onHover { hovering in isHovering = hovering }
    }

    private var rowBackground: Color {
        if isHovering {
            return Color.white.opacity(0.03)
        } else if event.type == .error {
            return Color.red.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Debug Toolbar Overlay (wrapper pattern from macOS app)

#if DEBUG

// Using DebugToolbarPosition from DebugKit package

/// Floating debug toolbar with expandable panel - wraps any content
/// Usage: DebugToolbarOverlay { YourMainContent() }
struct DebugToolbarOverlay<Content: View>: View {
    @State private var showToolbar = false
    @State private var showingConsole = false
    @State private var showParticleTuning = false
    @State private var showWaveformTuning = false
    @State private var showOverlayTuning = false
    @State private var showCopiedFeedback = false
    @State private var showObjectInspector = false
    @ObservedObject private var events = SystemEventManager.shared

    // Persisted settings
    @AppStorage("debugToolbar.isHidden") private var isHidden = false
    @AppStorage("debugToolbar.position") private var positionRaw = DebugToolbarPosition.bottomTrailing.rawValue

    private var position: DebugToolbarPosition {
        get { DebugToolbarPosition(rawValue: positionRaw) ?? .bottomTrailing }
        nonmutating set { positionRaw = newValue.rawValue }
    }

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // Main content
            content()

            // Debug overlay (position based on setting)
            if !isHidden {
                debugOverlay
            }
        }
        .sheet(isPresented: $showingConsole) {
            DebugConsoleSheet()
        }
        // ⌘D to toggle debug toolbar visibility
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d" {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHidden.toggle()
                    }
                    return nil // Consume the event
                }
                return event
            }
        }
    }

    private var debugOverlay: some View {
        let isTop = position == .topTrailing || position == .topLeading
        let isLeading = position == .bottomLeading || position == .topLeading
        let horizontalAlignment: HorizontalAlignment = isLeading ? .leading : .trailing
        let slideEdge: Edge = isLeading ? .leading : .trailing
        let _: UnitPoint = isTop
            ? (isLeading ? .topLeading : .topTrailing)
            : (isLeading ? .bottomLeading : .bottomTrailing)

        return ZStack(alignment: position.alignment) {
            Color.clear // Expand to full size

            VStack(alignment: horizontalAlignment, spacing: 8) {
                // For top positions, button comes first
                if isTop {
                    toggleButton
                }

                // Expanded panel - use simple opacity to avoid competing with button rotation
                if showToolbar {
                    debugPanel
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }

                // Tuning panels (slides in from edge) - capped height with scroll
                if showParticleTuning {
                    ParticleTuningPanel(isShowing: $showParticleTuning)
                        .transition(.move(edge: slideEdge).combined(with: .opacity))
                }

                if showWaveformTuning {
                    WaveformTuningPanel(isShowing: $showWaveformTuning)
                        .transition(.move(edge: slideEdge).combined(with: .opacity))
                }

                if showOverlayTuning {
                    OverlayTuningPanel(isShowing: $showOverlayTuning)
                        .transition(.move(edge: slideEdge).combined(with: .opacity))
                }

                // For bottom positions, button comes last
                if !isTop {
                    toggleButton
                }
            }
            .padding(16)
            .frame(maxHeight: 600, alignment: isTop ? .top : .bottom)
            .clipped()
        }
    }

    private var toggleButton: some View {
        Button(action: {
            // Use separate transactions: fast for rotation, normal for layout
            var transaction = Transaction(animation: .spring(response: 0.25, dampingFraction: 0.8))
            transaction.disablesAnimations = false
            withTransaction(transaction) {
                showToolbar.toggle()
            }
        }) {
            // Isolate the rotating icon into its own composited layer
            Image(systemName: "ant.fill")
                .font(.system(size: 14))
                .foregroundColor(showToolbar ? .orange : .secondary)
                .rotationEffect(.degrees(showToolbar ? 180 : 0))
                .drawingGroup() // Rasterize icon before animating - prevents layout recalc
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showToolbar)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color(white: 0.15))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("DEV")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Position toggle button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        positionRaw = position.next.rawValue
                    }
                }) {
                    Image(systemName: position.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Move toolbar (\(position.next.rawValue))")

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showToolbar = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.12))

            Divider().background(Color.white.opacity(0.1))

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Stats section
                DebugSection(title: "STATE") {
                    VStack(spacing: 0) {
                        debugInfoRow("Echoes", "\(LiveDatabase.count())")
                        debugInfoRow("Events", "\(events.events.count)")
                        debugInfoRow("Errors", "\(events.events.filter { $0.type == .error }.count)")
                    }
                    .background(Color(white: 0.08))
                    .cornerRadius(4)
                }

                // Debug Actions
                DebugSection(title: "TUNING") {
                    VStack(spacing: 4) {
                        DebugActionButton(icon: "sparkles", label: "Particle Tuning") {
                            withAnimation {
                                showParticleTuning.toggle()
                                showWaveformTuning = false
                                showOverlayTuning = false
                                showToolbar = false
                            }
                        }

                        DebugActionButton(icon: "waveform", label: "Waveform Tuning") {
                            withAnimation {
                                showWaveformTuning.toggle()
                                showParticleTuning = false
                                showOverlayTuning = false
                                showToolbar = false
                            }
                        }

                        DebugActionButton(icon: "rectangle.roundedtop", label: "Overlay Appearance") {
                            withAnimation {
                                showOverlayTuning.toggle()
                                showParticleTuning = false
                                showWaveformTuning = false
                                showToolbar = false
                            }
                        }
                    }
                }

                // LivePill State Preview
                DebugSection(title: "LIVE PILL STATES") {
                    VStack(spacing: 6) {
                        // Idle
                        livePillPreviewRow("Idle") {
                            LivePill(
                                state: .idle,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: "MacBook Pro Microphone",
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Idle with queue
                        livePillPreviewRow("Idle + Queue") {
                            LivePill(
                                state: .idle,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 3,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Listening
                        livePillPreviewRow("Listening") {
                            LivePill(
                                state: .listening,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 4.2,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0.6,
                                forceExpanded: true
                            )
                        }

                        // Transcribing
                        livePillPreviewRow("Transcribing") {
                            LivePill(
                                state: .transcribing,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 1.5,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Routing
                        livePillPreviewRow("Routing") {
                            LivePill(
                                state: .routing,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Success
                        livePillPreviewRow("Success") {
                            LivePill(
                                state: .idle,
                                isWarmingUp: false,
                                showSuccess: true,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Warming Up
                        livePillPreviewRow("Warming Up") {
                            LivePill(
                                state: .idle,
                                isWarmingUp: true,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: true,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }

                        // Offline
                        livePillPreviewRow("Offline") {
                            LivePill(
                                state: .idle,
                                isWarmingUp: false,
                                showSuccess: false,
                                recordingDuration: 0,
                                processingDuration: 0,
                                isEngineConnected: false,
                                pendingQueueCount: 0,
                                micDeviceName: nil,
                                audioLevel: 0,
                                forceExpanded: true
                            )
                        }
                    }
                }

                // Nano Waveform Preview
                DebugSection(title: "NANO WAVEFORM") {
                    VStack(spacing: 6) {
                        ForEach(NanoWaveformStyle.allCases) { style in
                            HStack(spacing: 8) {
                                NanoWaveform(color: SemanticColor.warning, style: style)
                                    .frame(width: 14)
                                Text(style.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(white: 0.08))
                            .cornerRadius(4)
                        }
                    }
                }

                // System Actions
                DebugSection(title: "SYSTEM") {
                    VStack(spacing: 4) {
                        DebugActionButton(icon: "terminal", label: "View Console") {
                            showingConsole = true
                        }

                        DebugActionButton(
                            icon: showCopiedFeedback ? "checkmark" : "doc.on.clipboard",
                            label: showCopiedFeedback ? "Copied!" : "Copy Debug Info"
                        ) {
                            copyDebugInfo()
                        }

                        DebugActionButton(icon: "trash", label: "Prune Old Data") {
                            let hours = LiveSettings.shared.dictationTTLHours
                            LiveDatabase.prune(olderThanHours: hours)
                            AppLogger.shared.log(.database, "Pruned data", detail: "Older than \(hours)h")
                        }

                        DebugActionButton(icon: "xmark.circle", label: "Clear Events") {
                            events.clear()
                        }

                        DebugActionButton(icon: "text.bubble", label: "Test Log") {
                            AppLogger.shared.log(.system, "Test event", detail: "This is a test log entry")
                        }

                        DebugActionButton(icon: "arrow.counterclockwise", label: "Reset Onboarding") {
                            OnboardingManager.shared.resetOnboarding()
                            AppLogger.shared.log(.system, "Onboarding reset", detail: "Will show on next app launch")
                        }

                        DebugActionButton(icon: "arrow.down.circle", label: "Simulate No Model") {
                            OnboardingManager.shared.isModelDownloaded = false
                            OnboardingManager.shared.downloadProgress = 0
                            OnboardingManager.shared.downloadStatus = ""
                            OnboardingManager.shared.currentStep = .modelDownload
                            AppLogger.shared.log(.system, "Model state reset", detail: "Simulating no model installed")
                        }

                        DebugActionButton(icon: "sparkles", label: "Test Interstitial") {
                            testInterstitialFlow()
                        }
                    }
                }

                // Database section
                DebugSection(title: "DATABASE") {
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(LiveDatabase.count()) records")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        DebugActionButton(icon: "eye", label: "Inspect Latest") {
                            showObjectInspector = true
                        }

                        DebugActionButton(icon: "folder", label: "Reveal Database") {
                            NSWorkspace.shared.selectFile(
                                LiveDatabase.databaseURL.path,
                                inFileViewerRootedAtPath: LiveDatabase.databaseURL.deletingLastPathComponent().path
                            )
                        }
                    }
                }
                .sheet(isPresented: $showObjectInspector) {
                    ObjectInspectorView()
                }

                // Bridge section
                DebugSection(title: "BRIDGE") {
                    VStack(spacing: 4) {
                        let contexts = BridgeContextMapper.shared.getAllMappedSessions()
                        HStack {
                            Text("\(contexts.count) session(s) mapped")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        DebugActionButton(icon: "terminal", label: "Scan Terminals") {
                            Task { @MainActor in
                                let result = TerminalScanner.shared.scanAllTerminals()
                                let json = TerminalScanner.shared.dumpAsJSON()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(json, forType: .string)
                                print("Terminal scan (\(result.terminals.count) windows) copied to clipboard")
                            }
                        }

                        DebugActionButton(icon: "doc.text", label: "Dump Context Map") {
                            let json = BridgeContextMapper.shared.dumpAsJSON()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                            print("Session context map copied to clipboard")
                        }

                        DebugActionButton(icon: "arrow.clockwise", label: "Refresh from Scan") {
                            Task { @MainActor in
                                BridgeContextMapper.shared.refreshFromScan()
                            }
                        }
                    }
                }
            }
            .padding(10)
            .padding(.bottom, 6)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.1))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func debugInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func livePillPreviewRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)

            content()

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
        .cornerRadius(4)
    }

    private func copyDebugInfo() {
        var lines: [String] = []

        // App info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("TalkieLive \(appVersion) (\(buildNumber))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        // State
        lines.append("State:")
        lines.append("  Echoes: \(LiveDatabase.count())")
        lines.append("  Events: \(events.events.count)")
        lines.append("  Errors: \(events.events.filter { $0.type == .error }.count)")
        lines.append("")

        // Recent events
        let recentEvents = Array(events.events.prefix(5))
        if !recentEvents.isEmpty {
            lines.append("Recent Events:")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for event in recentEvents {
                let time = formatter.string(from: event.timestamp)
                lines.append("  [\(time)] \(event.type.rawValue): \(event.message)")
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    /// Test interstitial flow: creates a test dictation and opens Talkie Core's interstitial editor
    private func testInterstitialFlow() {
        NSLog("[DEBUG] Testing interstitial flow")
        NSLog("[DEBUG] Database path: \(LiveDatabase.databaseURL.path)")
        NSLog("[DEBUG] Database count: \(LiveDatabase.count())")
        AppLogger.shared.log(.system, "Testing interstitial", detail: "Creating test dictation")

        // Create a test dictation in the database
        let testText = "This is a test dictation for interstitial debugging at \(Date())"

        let utterance = LiveDictation(
            id: nil,
            createdAt: Date(),
            text: testText,
            mode: "interstitial",
            appBundleID: "com.debug.test",
            appName: "Debug Test",
            windowTitle: "Test Window",
            durationSeconds: 1.5,
            wordCount: testText.split(separator: " ").count,
            transcriptionModel: "debug-test",
            perfEngineMs: 100,
            perfEndToEndMs: 200,
            perfInAppMs: 100,
            sessionID: nil,
            metadata: nil,
            audioFilename: nil,
            transcriptionStatus: .success,
            transcriptionError: nil,
            promotionStatus: .none,
            talkieMemoID: nil,
            commandID: nil,
            createdInTalkieView: false,
            pasteTimestamp: nil
        )

        // Store test record and get its ID
        guard let utteranceId = LiveDatabase.store(utterance) else {
            NSLog("[DEBUG] Failed to create test dictation")
            AppLogger.shared.log(.error, "Interstitial test failed", detail: "Could not create dictation")
            return
        }

        NSLog("[DEBUG] Created test dictation ID: \(utteranceId)")
        AppLogger.shared.log(.system, "Test dictation created", detail: "ID: \(utteranceId)")

        // Open the interstitial URL
        let urlString = "\(TalkieEnvironment.current.talkieURLScheme)://interstitial/\(utteranceId)"
        guard let url = URL(string: urlString) else {
            NSLog("[DEBUG] Invalid URL: \(urlString)")
            return
        }

        NSLog("[DEBUG] Opening URL: \(urlString)")
        AppLogger.shared.log(.system, "Opening interstitial", detail: urlString)

        NSWorkspace.shared.open(url)
    }
}

// MARK: - Debug Console Sheet

struct DebugConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("System Logs")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(white: 0.1))

            Divider()

            // OSLogStore-based console view
            LogViewerConsole()
        }
        .frame(width: 800, height: 550)
        .background(Color(white: 0.08))
    }
}

// MARK: - Reusable Debug Components

/// Section header for debug toolbar content
struct DebugSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.4))

            content()
        }
    }
}

/// Tappable debug action button
struct DebugActionButton: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(destructive ? .red : .accentColor)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(destructive ? .red : .white.opacity(0.85))

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Color(white: 0.12))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy Debug Overlay (for backward compatibility)

struct DebugOverlay: View {
    var body: some View {
        DebugToolbarOverlay {
            EmptyView()
        }
    }
}

// MARK: - Particle Tuning Panel

struct ParticleTuningPanel: View {
    @Binding var isShowing: Bool
    @ObservedObject private var tuning = ParticleTuning.shared
    @State private var showSaveSheet = false
    @State private var newPresetName = ""
    @State private var presetToDelete: ParticlePreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)

                Text("PARTICLE TUNING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Button("Reset") {
                    tuning.reset()
                }
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .buttonStyle(.plain)

                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Presets section
                    presetsSection

                    // Speed section
                    TuningSection(title: "SPEED") {
                        TuningSlider(
                            label: "Base Speed",
                            value: $tuning.baseSpeed,
                            range: 0.02...0.25,
                            format: "%.3f"
                        )
                        TuningSlider(
                            label: "Speed Variation",
                            value: $tuning.speedVariation,
                            range: 0...0.15,
                            format: "%.3f"
                        )
                    }

                    // Wave section
                    TuningSection(title: "WAVE") {
                        TuningSlider(
                            label: "Wave Speed",
                            value: $tuning.waveSpeed,
                            range: 0.5...4.0,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Base Amplitude",
                            value: $tuning.baseAmplitude,
                            range: 0.1...0.8,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Audio Amplitude",
                            value: $tuning.audioAmplitude,
                            range: 0...0.6,
                            format: "%.2f"
                        )
                    }

                    // Particles section
                    TuningSection(title: "PARTICLES") {
                        TuningSlider(
                            label: "Count",
                            value: Binding(
                                get: { Double(tuning.particleCount) },
                                set: { tuning.particleCount = Int($0) }
                            ),
                            range: 30...150,
                            format: "%.0f"
                        )
                        TuningSlider(
                            label: "Base Size",
                            value: $tuning.baseSize,
                            range: 1.0...5.0,
                            format: "%.1f"
                        )
                        TuningSlider(
                            label: "Base Opacity",
                            value: $tuning.baseOpacity,
                            range: 0.2...0.8,
                            format: "%.2f"
                        )
                    }

                    // Response section
                    TuningSection(title: "RESPONSE") {
                        TuningSlider(
                            label: "Smoothing",
                            value: $tuning.smoothingFactor,
                            range: 0.05...0.4,
                            format: "%.3f"
                        )
                        TuningSlider(
                            label: "Input Sensitivity",
                            value: $tuning.inputSensitivity,
                            range: 0.2...3.0,
                            format: "%.2fx"
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280, height: 530)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.08))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.bottom, 8)
        .sheet(isPresented: $showSaveSheet) {
            savePresetSheet
        }
        .alert("Delete Preset", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { presetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    tuning.deletePreset(preset)
                }
                presetToDelete = nil
            }
        } message: {
            Text("Delete \"\(presetToDelete?.name ?? "")\"? This cannot be undone.")
        }
    }

    private var presetsSection: some View {
        TuningSection(title: "PRESETS") {
            // Preset chips
            FlowLayout(spacing: 6) {
                ForEach(tuning.allPresets) { preset in
                    PresetChip(
                        preset: preset,
                        isActive: tuning.activePresetId == preset.id,
                        isBuiltIn: ParticlePreset.builtInPresets.contains { $0.id == preset.id },
                        onTap: { tuning.apply(preset: preset) },
                        onDelete: { presetToDelete = preset }
                    )
                }
            }

            // Save button
            Button(action: { showSaveSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text("Save Current as Preset")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.purple)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(.headline)

            TextField("Preset Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack(spacing: 12) {
                Button("Cancel") {
                    newPresetName = ""
                    showSaveSheet = false
                }

                Button("Save") {
                    if !newPresetName.isEmpty {
                        _ = tuning.saveAsPreset(name: newPresetName)
                        newPresetName = ""
                        showSaveSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPresetName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
}

struct PresetChip: View {
    let preset: ParticlePreset
    let isActive: Bool
    let isBuiltIn: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.7))

                // Delete button for custom presets
                if !isBuiltIn && isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.purple : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? Color.purple : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// Simple flow layout for preset chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (frames, y + rowHeight)
    }
}

struct TuningSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            content()
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}

struct TuningSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(String(format: format, value))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentColor)
            }

            Slider(value: $value, in: range)
                .controlSize(.mini)
        }
    }
}

// MARK: - Waveform Tuning Panel

struct WaveformTuningPanel: View {
    @Binding var isShowing: Bool
    @ObservedObject private var tuning = WaveformTuning.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)

                Text("WAVEFORM TUNING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Button("Reset") {
                    tuning.reset()
                }
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .buttonStyle(.plain)

                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Bar appearance section
                    TuningSection(title: "BARS") {
                        TuningSlider(
                            label: "Bar Count",
                            value: Binding(
                                get: { Double(tuning.barCount) },
                                set: { tuning.barCount = Int($0) }
                            ),
                            range: 16...80,
                            format: "%.0f"
                        )
                        TuningSlider(
                            label: "Gap Width",
                            value: $tuning.barGap,
                            range: 0.5...4.0,
                            format: "%.1f"
                        )
                        TuningSlider(
                            label: "Max Height",
                            value: $tuning.maxHeightRatio,
                            range: 0.5...1.0,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Min Height",
                            value: $tuning.minBarHeight,
                            range: 1.0...8.0,
                            format: "%.1f"
                        )
                        TuningSlider(
                            label: "Corner Radius",
                            value: $tuning.cornerRadius,
                            range: 0...4.0,
                            format: "%.1f"
                        )
                    }

                    // Response section
                    TuningSection(title: "RESPONSE") {
                        TuningSlider(
                            label: "Smoothing",
                            value: $tuning.smoothingFactor,
                            range: 0.1...0.9,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Variation",
                            value: $tuning.variationAmount,
                            range: 0...0.6,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Input Sensitivity",
                            value: $tuning.inputSensitivity,
                            range: 0.2...3.0,
                            format: "%.2fx"
                        )
                    }

                    // Appearance section
                    TuningSection(title: "APPEARANCE") {
                        TuningSlider(
                            label: "Base Opacity",
                            value: $tuning.baseOpacity,
                            range: 0.2...0.8,
                            format: "%.2f"
                        )
                        TuningSlider(
                            label: "Level Boost",
                            value: $tuning.levelOpacityBoost,
                            range: 0...1.0,
                            format: "%.2f"
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.08))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.bottom, 8)
    }
}

// MARK: - Overlay Tuning Panel

struct OverlayTuningPanel: View {
    @Binding var isShowing: Bool
    @ObservedObject private var tuning = OverlayTuning.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.roundedtop")
                    .font(.system(size: 10))
                    .foregroundColor(.green)

                Text("OVERLAY APPEARANCE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Button("Reset") {
                    tuning.reset()
                }
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .buttonStyle(.plain)

                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))

            VStack(alignment: .leading, spacing: 12) {
                // Dimensions section
                TuningSection(title: "DIMENSIONS") {
                    TuningSlider(
                        label: "Width",
                        value: $tuning.overlayWidth,
                        range: 200...600,
                        format: "%.0f"
                    )
                    TuningSlider(
                        label: "Height",
                        value: $tuning.overlayHeight,
                        range: 32...120,
                        format: "%.0f"
                    )
                }

                // Shape section
                TuningSection(title: "SHAPE") {
                    TuningSlider(
                        label: "Corner Radius",
                        value: $tuning.cornerRadius,
                        range: 0...20.0,
                        format: "%.1f"
                    )
                }

                // Background section
                TuningSection(title: "BACKGROUND") {
                    TuningSlider(
                        label: "Opacity",
                        value: $tuning.backgroundOpacity,
                        range: 0.2...0.9,
                        format: "%.2f"
                    )
                }

                // Preview
                TuningSection(title: "PREVIEW") {
                    RoundedRectangle(cornerRadius: CGFloat(tuning.cornerRadius))
                        .fill(Color(white: 0, opacity: tuning.backgroundOpacity))
                        .frame(width: min(260, CGFloat(tuning.overlayWidth) * 0.65), height: CGFloat(tuning.overlayHeight))
                        .overlay(
                            Text("\(Int(tuning.overlayWidth)) × \(Int(tuning.overlayHeight))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
            }
            .padding(10)
        }
        .frame(width: 280, height: 360)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.08))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.bottom, 8)
    }
}

// MARK: - Object Inspector View

struct ObjectInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0

    private let utterances = LiveDatabase.all()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Object Inspector")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if !utterances.isEmpty {
                    Picker("", selection: $selectedIndex) {
                        ForEach(Array(utterances.prefix(20).enumerated()), id: \.offset) { index, u in
                            Text("ID \(u.id ?? 0) – \(u.appName ?? "Unknown")").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(white: 0.12))

            if utterances.isEmpty {
                Text("No records")
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let u = utterances[min(selectedIndex, utterances.count - 1)]

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Schema columns section
                        inspectorSection("DATABASE COLUMNS") {
                            inspectorRow("id", "\(u.id ?? 0)")
                            inspectorRow("createdAt", dateFormatter.string(from: u.createdAt))
                            inspectorRow("text", String(u.text.prefix(100)) + (u.text.count > 100 ? "..." : ""))
                            inspectorRow("mode", u.mode)
                            inspectorRow("appBundleID", u.appBundleID)
                            inspectorRow("appName", u.appName)
                            inspectorRow("windowTitle", u.windowTitle)
                            inspectorRow("durationSeconds", u.durationSeconds.map { String(format: "%.2f", $0) })
                            inspectorRow("wordCount", u.wordCount.map { String($0) })
                            inspectorRow("transcriptionModel", u.transcriptionModel)
                            inspectorRow("perfEngineMs", u.perfEngineMs.map { String($0) })
                            inspectorRow("perfEndToEndMs", u.perfEndToEndMs.map { String($0) })
                            inspectorRow("perfInAppMs", u.perfInAppMs.map { String($0) })
                            inspectorRow("sessionID", u.sessionID)
                            inspectorRow("audioFilename", u.audioFilename)
                            inspectorRow("transcriptionStatus", u.transcriptionStatus.rawValue)
                            inspectorRow("transcriptionError", u.transcriptionError)
                            inspectorRow("promotionStatus", u.promotionStatus.rawValue)
                            inspectorRow("talkieMemoID", u.talkieMemoID)
                            inspectorRow("commandID", u.commandID)
                            inspectorRow("createdInTalkieView", u.createdInTalkieView ? "true" : "false")
                            inspectorRow("pasteTimestamp", u.pasteTimestamp.map { dateFormatter.string(from: $0) })
                        }

                        // Metadata blob section
                        inspectorSection("METADATA BLOB (JSON)") {
                            if let meta = u.metadata, !meta.isEmpty {
                                ForEach(Array(meta.keys.sorted()), id: \.self) { key in
                                    inspectorRow(key, meta[key], highlight: true)
                                }
                            } else {
                                Text("null")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                        }

                        // Computed properties
                        inspectorSection("COMPUTED") {
                            inspectorRow("hasAudio", u.hasAudio ? "true" : "false")
                            inspectorRow("isQueued", u.isQueued ? "true" : "false")
                            inspectorRow("canPromote", u.canPromote ? "true" : "false")
                            inspectorRow("canRetryTranscription", u.canRetryTranscription ? "true" : "false")
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(white: 0.08))
    }

    @ViewBuilder
    private func inspectorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.8))
                .padding(.top, 12)
                .padding(.bottom, 4)

            content()
        }
    }

    @ViewBuilder
    private func inspectorRow(_ label: String, _ value: String?, highlight: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 160, alignment: .leading)

            Text(value ?? "null")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(value == nil ? .orange : (highlight ? .green : .white.opacity(0.9)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.02))
    }
}
#endif
