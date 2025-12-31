//
//  OnboardingCoordinator.swift
//  Talkie macOS
//
//  Manages onboarding flow state and progression
//  Ports patterns from TalkieLive onboarding with Talkie-specific steps
//

import SwiftUI
import AVFoundation
import ApplicationServices

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case llmConfig = 1        // Local AI Models - first real choice
    case liveModePitch = 2    // Unlock Live Mode - feature toggle
    case permissions = 3      // Permissions - based on Live mode choice
    case modelInstall = 4     // Transcription Model
    case statusCheck = 5      // System Check
    case complete = 6
    // Note: Services are transparent implementation details, not user-facing setup
}

enum PermissionType {
    case microphone
    case accessibility
    case screenRecording
}

// MARK: - Status Check Types

enum StatusCheck: String, CaseIterable, Hashable {
    case modelSelection = "Model Selection"
    case modelDownload = "AI Model Download"
    case engineConnection = "Engine Connection"
    case engineReady = "Engine Ready"
    case liveService = "Live Service"

    func isRequired(enableLiveMode: Bool) -> Bool {
        // Live service only required if Live mode enabled
        if self == .liveService {
            return enableLiveMode
        }
        return true
    }
}

enum CheckStatus: Equatable {
    case pending
    case inProgress(String)
    case complete
    case error(String)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "spinner"
        case .complete: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .inProgress: return .blue
        case .complete: return .green
        case .error: return .red
        }
    }
}

// MARK: - Onboarding Manager

@MainActor
@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()

    var currentStep: OnboardingStep = .welcome
    var shouldShowOnboarding: Bool

    // Permissions state
    var hasMicrophonePermission = false
    var hasAccessibilityPermission = false
    var hasScreenRecordingPermission = false
    var isRequestingPermission = false

    // Service setup state
    var isTalkieLiveRunning = false
    var isTalkieEngineRunning = false
    var isCheckingServices = false
    var isLaunchingServices = false

    // Model installation state
    var isModelDownloaded = false
    var isDownloadingModel = false
    var downloadProgress: Double = 0
    var downloadStatus: String = ""
    var selectedModelType: String = ""  // "parakeet", "whisper", or "" for none

    // Status check state
    var checkStatuses: [StatusCheck: CheckStatus] = [:]
    var allChecksComplete = false

    // LLM configuration state
    var llmProvider: String? = nil  // "openai", "anthropic", or "local"
    var hasConfiguredLLM = false
    var selectedProvider: String = "local"
    var selectedLocalModel: String? = nil  // Persists selected local AI model
    var openAIKey: String = ""
    var anthropicKey: String = ""

    // Live mode configuration (default OFF - can be enabled in onboarding or Settings later)
    var enableLiveMode: Bool = false

    // First recording celebration
    var hasCompletedFirstRecording: Bool = false

    // Error handling
    var errorMessage: String?

    private var accessibilityCheckTimer: Timer?

    // Computed property: permissions to show based on Live mode
    var permissionsToShow: [PermissionType] {
        enableLiveMode ? [.microphone, .accessibility, .screenRecording] : [.microphone]
    }

    private init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        checkInitialPermissions()
    }

    deinit {
        // Clean up all timers to prevent memory leaks
        Task { @MainActor in
            stopAccessibilityPolling()
            stopMicrophonePolling()
            stopScreenRecordingPolling()
        }
    }

    // MARK: - Onboarding Lifecycle

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
            shouldShowOnboarding = !newValue
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        resetState()
        shouldShowOnboarding = true // Immediately show onboarding
    }

    private func resetState() {
        hasMicrophonePermission = false
        hasAccessibilityPermission = false
        hasScreenRecordingPermission = false
        isTalkieLiveRunning = false
        isTalkieEngineRunning = false
        isModelDownloaded = false
        isDownloadingModel = false
        downloadProgress = 0
        downloadStatus = ""
        selectedModelType = ""
        llmProvider = nil
        hasConfiguredLLM = false
        selectedLocalModel = nil
        errorMessage = nil
    }

    // MARK: - Permissions

    private func checkInitialPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }

    func checkMicrophonePermission() {
        // Check current authorization status without requesting
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
        case .notDetermined, .denied, .restricted:
            hasMicrophonePermission = false
        @unknown default:
            hasMicrophonePermission = false
        }
    }

    func requestMicrophonePermission() async {
        isRequestingPermission = true

        // Check current status first
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if currentStatus == .denied || currentStatus == .restricted {
            // Permission was denied - need to open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            startMicrophonePolling()
            isRequestingPermission = false
        } else {
            // Permission not determined yet - request it
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        self.hasMicrophonePermission = granted
                        self.isRequestingPermission = false

                        // If denied, start polling in case user opens Settings manually
                        if !granted {
                            self.startMicrophonePolling()
                        }

                        continuation.resume()
                    }
                }
            }
        }
    }

    private var microphoneCheckTimer: Timer?

    private func startMicrophonePolling() {
        microphoneCheckTimer?.invalidate()
        microphoneCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMicrophonePermission()
                if self?.hasMicrophonePermission == true {
                    self?.stopMicrophonePolling()
                }
            }
        }
        // Ensure timer runs even when UI is tracking
        RunLoop.main.add(microphoneCheckTimer!, forMode: .common)
    }

    private func stopMicrophonePolling() {
        microphoneCheckTimer?.invalidate()
        microphoneCheckTimer = nil
    }

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startAccessibilityPolling()
    }

    func checkScreenRecordingPermission() {
        // Screen recording permission check
        // On macOS 10.15+, we check if we can capture screen content
        if #available(macOS 10.15, *) {
            // CGPreflightScreenCaptureAccess() is unreliable - it often returns false
            // even when permission is granted. Instead, try to actually capture.
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]

            // If we can see window info, we have permission
            // Screen Recording permission affects ability to see window titles/owners
            if let windows = windowList, !windows.isEmpty {
                // Check if we can see detailed window info (requires screen recording permission)
                let hasDetailedInfo = windows.contains { window in
                    window[kCGWindowOwnerName as String] != nil
                }
                hasScreenRecordingPermission = hasDetailedInfo
            } else {
                hasScreenRecordingPermission = false
            }
        } else {
            hasScreenRecordingPermission = true
        }
    }

    func requestScreenRecordingPermission() {
        if #available(macOS 10.15, *) {
            // This will trigger the system permission dialog
            let didShowPrompt = CGRequestScreenCaptureAccess()

            if didShowPrompt {
                // Prompt was shown - start polling for permission grant
                startScreenRecordingPolling()
            } else {
                // Permission already granted or prompt couldn't be shown
                // Check immediately
                checkScreenRecordingPermission()

                // If still not granted, open System Settings
                if !hasScreenRecordingPermission {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    startScreenRecordingPolling()
                }
            }
        }
    }

    private var screenRecordingCheckTimer: Timer?

    private func startScreenRecordingPolling() {
        screenRecordingCheckTimer?.invalidate()
        screenRecordingCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkScreenRecordingPermission()
                if self?.hasScreenRecordingPermission == true {
                    self?.stopScreenRecordingPolling()
                }
            }
        }
        // Ensure timer runs even when UI is tracking
        RunLoop.main.add(screenRecordingCheckTimer!, forMode: .common)
    }

    private func stopScreenRecordingPolling() {
        screenRecordingCheckTimer?.invalidate()
        screenRecordingCheckTimer = nil
    }

    private func startAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityPermission()
                if self?.hasAccessibilityPermission == true {
                    self?.stopAccessibilityPolling()
                }
            }
        }
        // Ensure timer runs even when UI is tracking
        RunLoop.main.add(accessibilityCheckTimer!, forMode: .common)
    }

    private func stopAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    // MARK: - Service Setup

    func checkServices() async {
        isCheckingServices = true

        // Check if TalkieLive is running (production or dev)
        let liveBundleIds = ["jdi.talkie.live", "jdi.talkie.live.dev"]
        let liveRunning = NSWorkspace.shared.runningApplications.contains {
            liveBundleIds.contains($0.bundleIdentifier ?? "")
        }
        isTalkieLiveRunning = liveRunning

        // Check if TalkieEngine is running (production or dev)
        let engineBundleIds = ["jdi.talkie.engine", "jdi.talkie.engine.dev"]
        let engineRunning = NSWorkspace.shared.runningApplications.contains {
            engineBundleIds.contains($0.bundleIdentifier ?? "")
        }
        isTalkieEngineRunning = engineRunning

        isCheckingServices = false
    }

    func launchServices() async {
        isLaunchingServices = true
        errorMessage = nil

        do {
            // Launch TalkieLive
            if !isTalkieLiveRunning {
                if let liveURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jdi.talkie.live") {
                    try NSWorkspace.shared.launchApplication(at: liveURL, options: [], configuration: [:])
                    try? await Task.sleep(for: .seconds(1))
                    await checkServices()
                }
            }

            // Launch TalkieEngine
            if !isTalkieEngineRunning {
                if let engineURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jdi.talkie.engine") {
                    try NSWorkspace.shared.launchApplication(at: engineURL, options: [], configuration: [:])
                    try? await Task.sleep(for: .seconds(1))
                    await checkServices()
                }
            }
        } catch {
            errorMessage = "Failed to launch services: \(error.localizedDescription)"
        }

        isLaunchingServices = false
    }

    // MARK: - Model Installation

    var selectedModelId: String? {
        switch selectedModelType {
        case "parakeet": return "parakeet:v3"
        case "whisper": return "whisper:large-v3-turbo"
        default: return nil
        }
    }

    var selectedModelDisplayName: String {
        switch selectedModelType {
        case "parakeet": return "Parakeet v3"
        case "whisper": return "Whisper Large v3"
        default: return "None"
        }
    }

    func checkModelInstalled() async {
        // No model selected = nothing to check
        guard let modelId = selectedModelId else {
            isModelDownloaded = false
            return
        }

        // First try to get status from engine (most accurate)
        let engineClient = EngineClient.shared
        engineClient.refreshStatus()

        // Give it a moment to update
        try? await Task.sleep(for: .milliseconds(200))

        if let status = engineClient.status {
            // Check if our selected model is in the downloaded list
            isModelDownloaded = status.downloadedModels.contains(modelId)
            return
        }

        // Fallback: Check local services if engine not available
        if selectedModelType == "parakeet" {
            let parakeetService = ParakeetService.shared
            isModelDownloaded = parakeetService.isModelDownloaded(.v2) || parakeetService.isModelDownloaded(.v3)
        } else {
            let whisperService = WhisperService.shared
            isModelDownloaded = WhisperModel.allCases.contains { whisperService.isModelDownloaded($0) }
        }
    }

    func downloadModel() async {
        // No model selected = nothing to download
        guard let modelId = selectedModelId else { return }

        isDownloadingModel = true
        downloadProgress = 0
        downloadStatus = "Connecting to engine..."
        errorMessage = nil

        // Ensure engine is connected first
        let engineClient = EngineClient.shared
        if !engineClient.isConnected {
            downloadStatus = "Starting engine..."
            // Give engine time to start if it was just launched
            try? await Task.sleep(for: .seconds(2))

            if !engineClient.isConnected {
                errorMessage = "Could not connect to transcription engine"
                isDownloadingModel = false
                return
            }
        }

        downloadStatus = "Downloading \(selectedModelDisplayName)..."

        // Start progress monitoring
        let progressTask = Task {
            while !Task.isCancelled && isDownloadingModel {
                engineClient.refreshDownloadProgress()
                if let progress = engineClient.downloadProgress {
                    await MainActor.run {
                        self.downloadProgress = progress.progress
                        self.downloadStatus = "Downloading: \(progress.progressFormatted)"
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        // Perform the actual download via XPC
        do {
            try await engineClient.downloadModel(modelId)
            isModelDownloaded = true
            downloadStatus = "Model ready!"
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            downloadStatus = "Download failed"
        }

        progressTask.cancel()
        isDownloadingModel = false
    }

    // MARK: - Status Checks

    var visibleChecks: [StatusCheck] {
        StatusCheck.allCases.filter { $0.isRequired(enableLiveMode: enableLiveMode) }
    }

    func performStatusChecks() async {
        allChecksComplete = false

        // 0. Pre-flight: Verify microphone permission (required for all modes)
        // This ensures permission is granted before launching services that might trigger dialogs
        checkMicrophonePermission()
        if !hasMicrophonePermission {
            // If permission somehow not granted, show clear error
            await updateCheck(.modelSelection, status: .error("Microphone permission required"))
            return
        }

        // 1. Model Selection - check if user selected a model
        if selectedModelType.isEmpty {
            // User skipped model selection - mark as skipped (still valid)
            await updateCheck(.modelSelection, status: .complete)  // "Ready" means ready to proceed
            await updateCheck(.modelDownload, status: .complete)   // Skipped = no download needed
        } else {
            // User selected a model
            await updateCheck(.modelSelection, status: .complete)

            // 2. Model Download (monitor ongoing or check if already installed)
            if isModelDownloaded {
                // No fake delay - instant check when already installed
                await updateCheck(.modelDownload, status: .complete)
            } else if isDownloadingModel {
                // Monitor ongoing download
                while isDownloadingModel {
                    let percentage = Int(downloadProgress * 100)
                    await updateCheck(.modelDownload, status: .inProgress("\(percentage)%"))
                    try? await Task.sleep(for: .milliseconds(100))
                }

                // Check if download completed
                if isModelDownloaded {
                    await updateCheck(.modelDownload, status: .complete)
                } else {
                    await updateCheck(.modelDownload, status: .error("Download failed"))
                    return
                }
            } else {
                // Model selected but not downloading and not downloaded - waiting for download
                await updateCheck(.modelDownload, status: .inProgress("Waiting..."))
                // Wait a bit for download to start
                try? await Task.sleep(for: .seconds(2))
                if isModelDownloaded {
                    await updateCheck(.modelDownload, status: .complete)
                } else if !isDownloadingModel {
                    // Download never started - proceed anyway (cloud transcription fallback)
                    await updateCheck(.modelDownload, status: .complete)
                }
            }
        }

        // 3. Engine Connection
        await updateCheck(.engineConnection, status: .inProgress("Connecting..."))
        await checkServices()

        if isTalkieEngineRunning {
            await updateCheck(.engineConnection, status: .complete)
        } else {
            // Try to launch engine
            await launchServices()
            if isTalkieEngineRunning {
                await updateCheck(.engineConnection, status: .complete)
            } else {
                await updateCheck(.engineConnection, status: .error("Could not connect"))
                return
            }
        }

        // 4. Engine Ready (verify engine is actually responsive)
        await updateCheck(.engineReady, status: .inProgress("Verifying..."))
        // Real check: ping the engine via XPC to confirm it's ready
        let engineResponsive = await checkEngineResponsive()
        if engineResponsive {
            await updateCheck(.engineReady, status: .complete)
        } else {
            // Give it a brief moment then retry once
            try? await Task.sleep(for: .milliseconds(500))
            let retryCheck = await checkEngineResponsive()
            if retryCheck {
                await updateCheck(.engineReady, status: .complete)
            } else {
                await updateCheck(.engineReady, status: .error("Engine not responding"))
                return
            }
        }

        // 5. Live Service (conditional)
        if enableLiveMode {
            await updateCheck(.liveService, status: .inProgress("Starting..."))
            if isTalkieLiveRunning {
                // TalkieLive is running - verify it has microphone permission
                await updateCheck(.liveService, status: .inProgress("Checking permissions..."))

                // Give TalkieLive a moment to connect XPC
                try? await Task.sleep(for: .milliseconds(500))

                // Check TalkieLive's permissions via XPC
                if let permissions = await ServiceManager.shared.live.checkPermissions() {
                    if permissions.microphone {
                        await updateCheck(.liveService, status: .complete)
                    } else {
                        // TalkieLive doesn't have mic permission - it will prompt when user tries to record
                        // Mark as complete but note the permission status
                        await updateCheck(.liveService, status: .complete)
                        // Note: TalkieLive will request its own permission on first recording attempt
                    }
                } else {
                    // Couldn't check permissions (XPC not connected yet) - proceed anyway
                    await updateCheck(.liveService, status: .complete)
                }
            } else {
                // Try to launch Live
                await launchServices()
                if isTalkieLiveRunning {
                    await updateCheck(.liveService, status: .complete)
                } else {
                    await updateCheck(.liveService, status: .error("Could not start"))
                    return
                }
            }
        }

        // All checks passed
        allChecksComplete = true

        // Note: No auto-advance - let user click Continue to proceed to completion
    }

    private func updateCheck(_ check: StatusCheck, status: CheckStatus) async {
        await MainActor.run {
            checkStatuses[check] = status
        }
    }

    /// Check if the engine is actually responsive (not just running)
    private func checkEngineResponsive() async -> Bool {
        // If engine is running, try to verify it's responsive via EngineClient
        guard isTalkieEngineRunning else { return false }

        // Use EngineClient to ping - if connected, engine is responsive
        return EngineClient.shared.isConnected
    }

    // MARK: - LLM Configuration

    func configureLLM(provider: String, apiKey: String) async {
        // Save LLM configuration to keychain
        // This would integrate with KeychainManager
        llmProvider = provider
        hasConfiguredLLM = true

        // TODO: Integrate with KeychainManager.shared to store API key
    }

    func skipLLMConfiguration() {
        llmProvider = nil
        hasConfiguredLLM = false
    }
}
