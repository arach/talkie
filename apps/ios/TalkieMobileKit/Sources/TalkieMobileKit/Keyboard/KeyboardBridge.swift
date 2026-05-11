//
//  KeyboardBridge.swift
//  TalkieMobileKit (iOS)
//
//  Shared data contract for keyboard extension <-> main app communication.
//
//  Flow:
//  1. Keyboard sets `pendingDictation = true` and opens talkie://dictate
//  2. Main app records, transcribes, sets `dictationResult`
//  3. Keyboard reads `dictationResult` when becoming active
//  4. Keyboard clears the result after inserting text
//

import Foundation

/// Keys for UserDefaults stored in App Group
public enum KeyboardBridgeKey: String {
    case pendingDictation = "keyboard.pendingDictation"
    case dictationResult = "keyboard.dictationResult"
    case dictationTimestamp = "keyboard.dictationTimestamp"
    case dictationError = "keyboard.dictationError"
    // Background recording coordination
    case isRecording = "keyboard.isRecording"
    case stopRequested = "keyboard.stopRequested"
    // Background-first flow (no app switch after initial setup)
    case appReady = "keyboard.appReady"
    case appReadyTimestamp = "keyboard.appReadyTimestamp"
    case startRequested = "keyboard.startRequested"
    // Voice emoji mode - keyboard handles its own UI
    case voiceEmojiMode = "keyboard.voiceEmojiMode"
    // Audio level for visualizations (0.0-1.0)
    case audioLevel = "keyboard.audioLevel"
    // Keyboard mode persistence
    case lastSelectedModeId = "keyboard.lastSelectedModeId"
    case lastSelectedModeAt = "keyboard.lastSelectedModeAt"
    // Grid density preset
    case gridPreset = "keyboard.gridPreset"
    // Keyboard haptic preference
    case hapticFeedbackEnabled = "keyboard.hapticFeedbackEnabled"
    // Keyboard mode enabled preference (separate from transient appReady)
    case keyboardModeEnabled = "keyboard.modeEnabled"
}

/// Result of a dictation session
public struct DictationResult: Codable {
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double?

    public init(text: String, timestamp: Date = Date(), durationSeconds: Double? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
    }
}

/// Bridge for keyboard extension <-> main app communication via App Group
public final class KeyboardBridge {

    public static let shared = KeyboardBridge()

    private let defaults: UserDefaults?
    private let log = Log(.keyboard)

    /// Whether the App Group is accessible
    public var isAppGroupAccessible: Bool {
        return defaults != nil
    }

    private init() {
        defaults = UserDefaults(suiteName: kTalkieAppGroup)
        if defaults == nil {
            log.error("❌ Failed to access App Group: \(kTalkieAppGroup)")
            log.error("❌ Make sure App Group is configured in Apple Developer Portal")
            log.error("❌ And provisioning profiles are regenerated")
        } else {
            // Test write to verify access
            let testKey = "keyboard.accessTest"
            defaults?.set(Date().timeIntervalSince1970, forKey: testKey)
            defaults?.synchronize()
            if defaults?.double(forKey: testKey) != nil {
                log.info("✅ App Group accessible: \(kTalkieAppGroup)")
            } else {
                log.warning("⚠️ App Group write test failed")
            }
        }
    }

    /// Diagnostic method to check App Group status
    public func diagnose() -> String {
        var report = "=== KeyboardBridge Diagnostics ===\n"
        report += "App Group ID: \(kTalkieAppGroup)\n"
        report += "UserDefaults created: \(defaults != nil)\n"

        if let defaults = defaults {
            // Try to write and read
            let testKey = "keyboard.diagnoseTest"
            let testValue = Date().timeIntervalSince1970
            defaults.set(testValue, forKey: testKey)
            defaults.synchronize()

            if let readValue = defaults.double(forKey: testKey) as Double?, readValue == testValue {
                report += "Write/Read test: ✅ PASSED\n"
            } else {
                report += "Write/Read test: ❌ FAILED\n"
            }

            // Check current state
            report += "isRecording: \(defaults.bool(forKey: KeyboardBridgeKey.isRecording.rawValue))\n"
            report += "stopRequested: \(defaults.bool(forKey: KeyboardBridgeKey.stopRequested.rawValue))\n"
            report += "hasDictationResult: \(defaults.data(forKey: KeyboardBridgeKey.dictationResult.rawValue) != nil)\n"
        } else {
            report += "❌ Cannot run tests - UserDefaults is nil\n"
            report += "Check: Apple Developer Portal → App Group capability\n"
            report += "Check: Provisioning profiles include App Group\n"
        }

        return report
    }

    // MARK: - Keyboard Side (Write pending, Read result)

    /// Signal that keyboard is requesting dictation
    public func requestDictation() {
        defaults?.set(true, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
        defaults?.set(Date().timeIntervalSince1970, forKey: KeyboardBridgeKey.dictationTimestamp.rawValue)
        // Skip synchronize() - URL scheme will trigger app launch anyway
        log.info("Dictation requested")
    }

    /// Check if there's a dictation result available
    public func hasDictationResult() -> Bool {
        guard let resultData = defaults?.data(forKey: KeyboardBridgeKey.dictationResult.rawValue) else {
            return false
        }
        return !resultData.isEmpty
    }

    /// Get the dictation result (returns nil if none available)
    public func getDictationResult() -> DictationResult? {
        // Force sync to get fresh values from App Group (cross-process communication)
        defaults?.synchronize()

        guard let data = defaults?.data(forKey: KeyboardBridgeKey.dictationResult.rawValue) else {
            return nil
        }

        do {
            let result = try JSONDecoder().decode(DictationResult.self, from: data)
            log.info("Retrieved dictation result", detail: "\(result.text.count) chars")
            return result
        } catch {
            log.error("Failed to decode dictation result", error: error)
            return nil
        }
    }

    /// Get any error message from the last dictation attempt
    public func getDictationError() -> String? {
        // Force sync to get fresh values from App Group (cross-process communication)
        defaults?.synchronize()
        return defaults?.string(forKey: KeyboardBridgeKey.dictationError.rawValue)
    }

    /// Clear the dictation result after consuming it
    public func clearDictationResult() {
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationResult.rawValue)
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationError.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
        defaults?.synchronize()
        log.info("Dictation result cleared")
    }

    // MARK: - Main App Side (Read pending, Write result)

    /// Check if keyboard has requested dictation
    public func isPendingDictation() -> Bool {
        return defaults?.bool(forKey: KeyboardBridgeKey.pendingDictation.rawValue) ?? false
    }

    /// Get timestamp of pending dictation request
    public func getPendingTimestamp() -> Date? {
        guard let timestamp = defaults?.double(forKey: KeyboardBridgeKey.dictationTimestamp.rawValue),
              timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Store the dictation result for keyboard to pick up
    public func setDictationResult(_ result: DictationResult) {
        do {
            let data = try JSONEncoder().encode(result)
            defaults?.set(data, forKey: KeyboardBridgeKey.dictationResult.rawValue)
            defaults?.set(false, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
            defaults?.removeObject(forKey: KeyboardBridgeKey.dictationError.rawValue)
            defaults?.synchronize()
            log.info("Dictation result stored", detail: "\(result.text.count) chars")
        } catch {
            log.error("Failed to encode dictation result", error: error)
        }
    }

    /// Store an error message if dictation failed
    public func setDictationError(_ message: String) {
        defaults?.set(message, forKey: KeyboardBridgeKey.dictationError.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationResult.rawValue)
        defaults?.synchronize()
        log.warning("Dictation error stored", detail: message)
    }

    /// Clear any stored error
    public func clearDictationError() {
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationError.rawValue)
        defaults?.synchronize()
    }

    /// Clear pending state (called when main app handles the request)
    public func clearPendingDictation() {
        defaults?.set(false, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
        defaults?.synchronize()
    }

    // MARK: - Background Recording Coordination

    /// Check if the main app is currently recording (for keyboard to show recording state)
    /// Note: No synchronize() needed - we accept eventual consistency for reads
    public func isRecordingInProgress() -> Bool {
        // Force sync to get fresh values from App Group (cross-process communication)
        defaults?.synchronize()
        return defaults?.bool(forKey: KeyboardBridgeKey.isRecording.rawValue) ?? false
    }

    /// Set recording state (called by main app)
    public func setRecordingInProgress(_ recording: Bool) {
        defaults?.set(recording, forKey: KeyboardBridgeKey.isRecording.rawValue)
        if !recording {
            // Clear stop request when recording ends
            defaults?.set(false, forKey: KeyboardBridgeKey.stopRequested.rawValue)
        }
        // Only sync on state changes - this is important for keyboard to see
        defaults?.synchronize()
        log.info(recording ? "Recording started (background)" : "Recording stopped")
    }

    /// Request the main app to stop recording (called by keyboard)
    public func requestStopRecording() {
        defaults?.set(true, forKey: KeyboardBridgeKey.stopRequested.rawValue)
        // Must sync - main app polls this
        defaults?.synchronize()
        log.info("Stop recording requested")
    }

    /// Check if stop was requested (called by main app)
    /// Called frequently in timer - skip synchronize for speed
    public func isStopRequested() -> Bool {
        return defaults?.bool(forKey: KeyboardBridgeKey.stopRequested.rawValue) ?? false
    }

    /// Clear the stop request flag
    public func clearStopRequest() {
        defaults?.set(false, forKey: KeyboardBridgeKey.stopRequested.rawValue)
        // No sync needed - not time-critical
    }

    // MARK: - Voice Emoji Mode

    /// Set voice emoji mode (keyboard handles its own recording UI)
    public func setVoiceEmojiMode(_ active: Bool) {
        defaults?.set(active, forKey: KeyboardBridgeKey.voiceEmojiMode.rawValue)
        defaults?.synchronize()
        log.info(active ? "Voice emoji mode active" : "Voice emoji mode inactive")
    }

    /// Check if voice emoji mode is active
    public func isVoiceEmojiMode() -> Bool {
        return defaults?.bool(forKey: KeyboardBridgeKey.voiceEmojiMode.rawValue) ?? false
    }

    // MARK: - Audio Level (for visualizations)

    /// Set current audio level (called by main app during recording)
    /// Value should be normalized 0.0-1.0
    public func setAudioLevel(_ level: Float) {
        defaults?.set(level, forKey: KeyboardBridgeKey.audioLevel.rawValue)
        // No sync - high frequency updates, eventual consistency OK
    }

    /// Get current audio level (called by keyboard for visualization)
    public func getAudioLevel() -> Float {
        return defaults?.float(forKey: KeyboardBridgeKey.audioLevel.rawValue) ?? 0.0
    }

    // MARK: - Background-First Flow (No App Switch)

    /// Check if the main app is ready and listening in background
    /// App is considered ready if it signaled readiness within the last 30 seconds
    public func isAppReady() -> Bool {
        // Force sync to get fresh values from App Group (cross-process communication)
        defaults?.synchronize()

        guard defaults?.bool(forKey: KeyboardBridgeKey.appReady.rawValue) == true else {
            return false
        }
        // Check if ready signal is fresh (within 30 seconds)
        let timestamp = defaults?.double(forKey: KeyboardBridgeKey.appReadyTimestamp.rawValue) ?? 0
        let age = Date().timeIntervalSince1970 - timestamp
        return age < 30.0
    }

    /// Signal that app is ready and listening for start requests (called by main app)
    public func setAppReady(_ ready: Bool) {
        defaults?.set(ready, forKey: KeyboardBridgeKey.appReady.rawValue)
        if ready {
            defaults?.set(Date().timeIntervalSince1970, forKey: KeyboardBridgeKey.appReadyTimestamp.rawValue)
        }
        defaults?.synchronize()
        log.info(ready ? "App signaled ready for background dictation" : "App no longer ready")
    }

    /// Refresh the ready timestamp (called periodically by main app to stay "fresh")
    public func refreshAppReady() {
        if defaults?.bool(forKey: KeyboardBridgeKey.appReady.rawValue) == true {
            defaults?.set(Date().timeIntervalSince1970, forKey: KeyboardBridgeKey.appReadyTimestamp.rawValue)
            // No sync needed - timestamp refresh is not critical
        }
    }

    /// Request the main app to start recording (called by keyboard when app is ready)
    public func requestStartRecording() {
        defaults?.set(true, forKey: KeyboardBridgeKey.startRequested.rawValue)
        defaults?.synchronize()
        log.info("Start recording requested (background)")
    }

    /// Check if start was requested (called by main app polling in background)
    public func isStartRequested() -> Bool {
        return defaults?.bool(forKey: KeyboardBridgeKey.startRequested.rawValue) ?? false
    }

    /// Clear the start request flag
    public func clearStartRequest() {
        defaults?.set(false, forKey: KeyboardBridgeKey.startRequested.rawValue)
    }

    /// Emergency reset - clears all state when app is unresponsive
    /// Only call this after timeout when app isn't responding
    public func forceReset() {
        log.warning("Force reset - clearing all bridge state")
        defaults?.set(false, forKey: KeyboardBridgeKey.isRecording.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.stopRequested.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.startRequested.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.appReady.rawValue)
        defaults?.set(false, forKey: KeyboardBridgeKey.pendingDictation.rawValue)
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationResult.rawValue)
        defaults?.removeObject(forKey: KeyboardBridgeKey.dictationError.rawValue)
        defaults?.synchronize()
    }

    // MARK: - Active Layout Persistence

    /// Get the persisted active layout ID
    public func getActiveLayout() -> String? {
        return defaults?.string(forKey: "keyboard.activeLayout")
    }

    /// Persist the active layout ID
    public func setActiveLayout(_ layoutId: String) {
        defaults?.set(layoutId, forKey: "keyboard.activeLayout")
        defaults?.synchronize()
        log.info("Active layout persisted: \(layoutId)")
    }

    // MARK: - Model Warmth & Transcription Readiness

    /// Whether the transcription model (Parakeet/Whisper) is loaded and warmed up
    public func isModelWarm() -> Bool {
        defaults?.synchronize()
        return defaults?.bool(forKey: "keyboard.modelWarm") ?? false
    }

    /// Set model warmth status (called by main app when model warmup completes)
    public func setModelWarm(_ warm: Bool) {
        defaults?.set(warm, forKey: "keyboard.modelWarm")
        defaults?.synchronize()
        log.debug("Model warm: \(warm)")
    }

    /// Timestamp of the last successful dictation
    public func getLastDictationCompletedAt() -> Date? {
        guard let interval = defaults?.object(forKey: "keyboard.lastDictationCompletedAt") as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// Record when a dictation was successfully completed
    public func setLastDictationCompletedAt(_ date: Date = Date()) {
        defaults?.set(date.timeIntervalSince1970, forKey: "keyboard.lastDictationCompletedAt")
        defaults?.synchronize()
    }

    // MARK: - Slot Configuration (User Customizable)

    private func slotKey(_ slot: Int, forApp appId: String? = nil) -> String {
        if let appId = appId {
            return "keyboard.slot.\(slot).app.\(appId)"
        }
        return "keyboard.slot.\(slot)"
    }

    /// Get slot configuration (JSON data)
    /// - Parameters:
    ///   - slot: Slot number (1-12)
    ///   - appId: Optional app bundle ID for app-specific config
    /// - Returns: JSON data of SlotConfig, or nil if not configured
    public func getSlotConfig(_ slot: Int, forApp appId: String? = nil) -> Data? {
        return defaults?.data(forKey: slotKey(slot, forApp: appId))
    }

    /// Set slot configuration
    /// - Parameters:
    ///   - slot: Slot number (1-12)
    ///   - config: JSON-encoded SlotConfig data
    ///   - appId: Optional app bundle ID for app-specific config
    public func setSlotConfig(_ slot: Int, config: Data, forApp appId: String? = nil) {
        defaults?.set(config, forKey: slotKey(slot, forApp: appId))
        defaults?.synchronize()
        log.info("Slot \(slot) config updated\(appId != nil ? " for \(appId!)" : "")")
    }

    /// Clear slot configuration (revert to default)
    public func clearSlotConfig(_ slot: Int, forApp appId: String? = nil) {
        defaults?.removeObject(forKey: slotKey(slot, forApp: appId))
        defaults?.synchronize()
    }

    /// Get all configured app IDs that have custom slot configs
    public func getAppsWithCustomSlots() -> [String] {
        guard let defaults = defaults else { return [] }
        let allKeys = defaults.dictionaryRepresentation().keys
        var appIds = Set<String>()

        for key in allKeys where key.hasPrefix("keyboard.slot.") && key.contains(".app.") {
            // Extract app ID from key like "keyboard.slot.9.app.com.apple.mobilenotes"
            if let range = key.range(of: ".app.") {
                let appId = String(key[range.upperBound...])
                appIds.insert(appId)
            }
        }

        return Array(appIds).sorted()
    }

    // MARK: - Mode-Specific Slot Configuration

    private func modeSlotKey(_ slot: Int, forMode modeId: String) -> String {
        return "keyboard.mode.\(modeId).slot.\(slot)"
    }

    /// Get slot configuration for a specific mode (JSON data)
    /// - Parameters:
    ///   - slot: Slot number (1-12)
    ///   - modeId: Mode identifier (e.g., "shortcuts", "numbers", "symbols")
    /// - Returns: JSON data of SlotConfig, or nil if not configured
    public func getSlotConfig(_ slot: Int, forMode modeId: String) -> Data? {
        return defaults?.data(forKey: modeSlotKey(slot, forMode: modeId))
    }

    /// Set slot configuration for a specific mode
    /// - Parameters:
    ///   - slot: Slot number (1-12)
    ///   - config: JSON-encoded SlotConfig data
    ///   - modeId: Mode identifier (e.g., "shortcuts", "numbers", "symbols")
    public func setSlotConfig(_ slot: Int, config: Data, forMode modeId: String) {
        defaults?.set(config, forKey: modeSlotKey(slot, forMode: modeId))
        defaults?.synchronize()
        log.info("Slot \(slot) config updated for mode: \(modeId)")
    }

    /// Clear slot configuration for a specific mode (revert to default)
    public func clearSlotConfig(_ slot: Int, forMode modeId: String) {
        defaults?.removeObject(forKey: modeSlotKey(slot, forMode: modeId))
        defaults?.synchronize()
        log.info("Slot \(slot) config cleared for mode: \(modeId)")
    }

    /// Clear all custom slot configurations for a mode (reset to defaults)
    /// - Parameter modeId: Mode identifier to reset
    public func resetModeToDefaults(_ modeId: String) {
        for slot in 1...12 {
            defaults?.removeObject(forKey: modeSlotKey(slot, forMode: modeId))
        }
        defaults?.synchronize()
        log.info("Mode '\(modeId)' reset to defaults")
    }

    /// Get all custom slot configurations for a mode
    /// - Parameter modeId: Mode identifier
    /// - Returns: Dictionary of slot number to JSON-encoded SlotConfig
    public func getAllSlotConfigs(forMode modeId: String) -> [Int: Data] {
        var configs: [Int: Data] = [:]
        for slot in 1...12 {
            if let data = getSlotConfig(slot, forMode: modeId) {
                configs[slot] = data
            }
        }
        return configs
    }

    /// Check if a mode has any custom configurations
    public func hasModeCustomizations(_ modeId: String) -> Bool {
        for slot in 1...12 {
            if getSlotConfig(slot, forMode: modeId) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Keyboard Mode Persistence

    /// Persist the last mode selected in TalkieKeys.
    public func setLastSelectedModeId(_ modeId: String) {
        defaults?.set(modeId, forKey: KeyboardBridgeKey.lastSelectedModeId.rawValue)
        defaults?.set(Date().timeIntervalSince1970, forKey: KeyboardBridgeKey.lastSelectedModeAt.rawValue)
        defaults?.synchronize()
    }

    /// Read the last selected mode id.
    /// - Parameter maxAge: Optional age limit in seconds.
    /// - Returns: Mode id if present (and fresh when maxAge is provided).
    public func getLastSelectedModeId(maxAge: TimeInterval? = nil) -> String? {
        guard let modeId = defaults?.string(forKey: KeyboardBridgeKey.lastSelectedModeId.rawValue),
              !modeId.isEmpty else {
            return nil
        }

        if let maxAge {
            let savedAt = defaults?.double(forKey: KeyboardBridgeKey.lastSelectedModeAt.rawValue) ?? 0
            guard savedAt > 0 else { return nil }
            let age = Date().timeIntervalSince1970 - savedAt
            guard age <= maxAge else { return nil }
        }

        return modeId
    }

    // MARK: - Grid Density Preset

    public func getGridPreset() -> KeyboardGridPreset {
        guard let raw = defaults?.string(forKey: KeyboardBridgeKey.gridPreset.rawValue),
              let preset = KeyboardGridPreset(rawValue: raw) else {
            return .sixteen
        }
        return preset
    }

    public func setGridPreset(_ preset: KeyboardGridPreset) {
        defaults?.set(preset.rawValue, forKey: KeyboardBridgeKey.gridPreset.rawValue)
        defaults?.synchronize()
        log.info("Grid preset updated: \(preset.rawValue)")
    }

    // MARK: - Keyboard Preferences

    public func getKeyboardModeEnabled() -> Bool {
        defaults?.bool(forKey: KeyboardBridgeKey.keyboardModeEnabled.rawValue) ?? false
    }

    public func setKeyboardModeEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: KeyboardBridgeKey.keyboardModeEnabled.rawValue)
        defaults?.synchronize()
        log.info("Keyboard mode preference updated: \(enabled)")
    }

    public func getHapticFeedbackEnabled() -> Bool {
        guard let defaults else { return true }
        if defaults.object(forKey: KeyboardBridgeKey.hapticFeedbackEnabled.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: KeyboardBridgeKey.hapticFeedbackEnabled.rawValue)
    }

    public func setHapticFeedbackEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: KeyboardBridgeKey.hapticFeedbackEnabled.rawValue)
        defaults?.synchronize()
        log.info("Haptic feedback updated: \(enabled)")
    }
}
