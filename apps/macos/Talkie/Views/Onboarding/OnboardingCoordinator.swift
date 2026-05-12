//
//  OnboardingCoordinator.swift
//  Talkie macOS
//
//  Manages onboarding flow state and progression
//  Ports patterns from TalkieAgent onboarding with Talkie-specific steps
//

import SwiftUI
import AVFoundation
import ApplicationServices
import TalkieKit

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1      // Permissions - Agent mode always enabled
    case modelInstall = 2     // Transcription Model
    case statusCheck = 3      // System Check
    case complete = 4
    // Note: Services are transparent implementation details, not user-facing setup
}

enum PermissionType {
    case microphone
    case accessibility
    case agentMicrophone
    case agentAccessibility
}

// MARK: - Status Check Types

enum StatusCheck: String, CaseIterable, Hashable {
    case modelSelection = "Model Selection"
    case modelDownload = "AI Model Download"
    case engineConnection = "Engine Connection"
    case engineReady = "Engine Ready"
    case liveService = "Agent Service"

    func isRequired(enableLiveMode: Bool) -> Bool {
        // Agent service only required if Agent mode enabled
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
    var hasAgentMicrophonePermission = false
    var hasAccessibilityPermission = false
    var hasAgentAccessibilityPermission = false
    var isRequestingPermission = false
    var isRequestingAgentMicrophonePermission = false
    var isRequestingAgentAccessibilityPermission = false

    // Service setup state
    var isTalkieAgentRunning = false
    var isTalkieEngineRunning = false
    var isCheckingServices = false
    var isLaunchingServices = false

    // Model installation state
    var isModelDownloaded = false
    var isDownloadingModel = false
    var downloadProgress: Double = 0
    var downloadStatus: String = ""
    var selectedModelType: String = ""  // "parakeet", "whisper", or "" for none

    // Resource download state (fonts, presets, workflows - downloaded in parallel with model)
    var isResourcesDownloaded = false
    var isDownloadingResources = false
    var resourcesDownloadProgress: Double = 0

    // Status check state
    var checkStatuses: [StatusCheck: CheckStatus] = [:]
    var allChecksComplete = false

    // Live mode configuration (default ON - all users get Live mode)
    var enableLiveMode: Bool = true

    // First recording celebration
    var hasCompletedFirstRecording: Bool = false

    // Error handling
    var errorMessage: String?

    private var accessibilityCheckTimer: Timer?
    private var agentAccessibilityCheckTimer: Timer?

    // Computed property: permissions to show based on Live mode
    var permissionsToShow: [PermissionType] {
        enableLiveMode ? [.microphone, .accessibility, .agentMicrophone, .agentAccessibility] : [.microphone, .accessibility]
    }

    private init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        checkInitialPermissions()
    }

    deinit {
        // Clean up all timers to prevent memory leaks
        Task { @MainActor in
            stopAccessibilityPolling()
            stopAgentAccessibilityPolling()
            stopMicrophonePolling()
            stopAgentMicrophonePolling()
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
        hasAgentMicrophonePermission = false
        hasAccessibilityPermission = false
        hasAgentAccessibilityPermission = false
        isTalkieAgentRunning = false
        isTalkieEngineRunning = false
        isModelDownloaded = false
        isDownloadingModel = false
        downloadProgress = 0
        downloadStatus = ""
        selectedModelType = ""
        errorMessage = nil
    }

    // MARK: - Permissions

    private func checkInitialPermissions() {
        checkMicrophonePermission()
        checkAgentMicrophonePermission()
        checkAccessibilityPermission()
        checkAgentAccessibilityPermission()
    }

    func checkMicrophonePermission() {
        hasMicrophonePermission = MicrophonePermission.isGranted
    }

    func checkAgentMicrophonePermission() {
        hasAgentMicrophonePermission = ServiceManager.shared.live.hasMicrophonePermission == true
    }

    func refreshAgentMicrophonePermission() async {
        if let permissions = await ServiceManager.shared.live.checkPermissions() {
            hasAgentMicrophonePermission = permissions.microphone
            hasAgentAccessibilityPermission = permissions.accessibility
        } else {
            checkAgentMicrophonePermission()
            checkAgentAccessibilityPermission()
        }
    }

    func requestAgentMicrophonePermission() async {
        guard !isRequestingAgentMicrophonePermission else { return }

        isRequestingAgentMicrophonePermission = true
        let granted = await ServiceManager.shared.requestAgentMicrophonePermission()
        hasAgentMicrophonePermission = granted == true
        isRequestingAgentMicrophonePermission = false

        if granted != true {
            PermissionsManager.shared.openMicrophoneSettings()
            startAgentMicrophonePolling()
        }
    }

    func requestMicrophonePermission() async {
        isRequestingPermission = true

        // Check current status first
        let currentStatus = MicrophonePermission.status

        if currentStatus == .denied {
            // Permission was denied - need to open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            startMicrophonePolling()
            isRequestingPermission = false
        } else {
            let granted = await MicrophonePermission.request()
            hasMicrophonePermission = granted
            isRequestingPermission = false

            if !granted {
                startMicrophonePolling()
            }
        }
    }

    private var microphoneCheckTimer: Timer?
    private var agentMicrophoneCheckTimer: Timer?

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

    private func startAgentMicrophonePolling() {
        agentMicrophoneCheckTimer?.invalidate()
        agentMicrophoneCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAgentMicrophonePermission()
                if self?.hasAgentMicrophonePermission == true {
                    self?.stopAgentMicrophonePolling()
                }
            }
        }
        RunLoop.main.add(agentMicrophoneCheckTimer!, forMode: .common)
    }

    private func stopAgentMicrophonePolling() {
        agentMicrophoneCheckTimer?.invalidate()
        agentMicrophoneCheckTimer = nil
    }

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func checkAgentAccessibilityPermission() {
        hasAgentAccessibilityPermission = ServiceManager.shared.live.hasAccessibilityPermission == true
    }

    func refreshAgentAccessibilityPermission() async {
        if let permissions = await ServiceManager.shared.live.checkPermissions() {
            hasAgentAccessibilityPermission = permissions.accessibility
            hasAgentMicrophonePermission = permissions.microphone
        } else {
            checkAgentAccessibilityPermission()
        }
    }

    func requestAccessibilityPermission() {
        // Use system prompt — shows a dialog explaining which app needs access
        // and pre-adds it to the Accessibility list in System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        PermissionsManager.shared.openAccessibilitySettings()
        startAccessibilityPolling()
    }

    func requestAgentAccessibilityPermission() async {
        guard !isRequestingAgentAccessibilityPermission else { return }

        isRequestingAgentAccessibilityPermission = true
        let granted = await ServiceManager.shared.requestAgentAccessibilityPermission()
        hasAgentAccessibilityPermission = granted == true
        isRequestingAgentAccessibilityPermission = false

        if granted != true {
            PermissionsManager.shared.openAccessibilitySettings()
            startAgentAccessibilityPolling()
        }
    }

    func startPermissionPolling() {
        if !hasMicrophonePermission {
            startMicrophonePolling()
        }
        if !hasAccessibilityPermission {
            startAccessibilityPolling()
        }
        if enableLiveMode {
            if !hasAgentMicrophonePermission {
                startAgentMicrophonePolling()
            }
            if !hasAgentAccessibilityPermission {
                startAgentAccessibilityPolling()
            }
        }
    }

    private func startAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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

    private func startAgentAccessibilityPolling() {
        agentAccessibilityCheckTimer?.invalidate()
        agentAccessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAgentAccessibilityPermission()
                if self?.hasAgentAccessibilityPermission == true {
                    self?.stopAgentAccessibilityPolling()
                }
            }
        }
        RunLoop.main.add(agentAccessibilityCheckTimer!, forMode: .common)
    }

    private func stopAgentAccessibilityPolling() {
        agentAccessibilityCheckTimer?.invalidate()
        agentAccessibilityCheckTimer = nil
    }

    // MARK: - Service Setup

    func checkServices() async {
        isCheckingServices = true

        // Check if TalkieAgent is running (production or dev)
        let liveBundleIds = ["to.talkie.app.agent", "to.talkie.app.agent.dev"]
        let liveRunning = NSWorkspace.shared.runningApplications.contains {
            liveBundleIds.contains($0.bundleIdentifier ?? "")
        }
        isTalkieAgentRunning = liveRunning

        // Engine is embedded in TalkieAgent now, so it is available when Agent is running.
        isTalkieEngineRunning = liveRunning

        isCheckingServices = false
    }

    func launchServices() async {
        isLaunchingServices = true
        errorMessage = nil

        do {
            // Launch TalkieAgent
            if !isTalkieAgentRunning {
                if let liveURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "to.talkie.app.agent") {
                    try NSWorkspace.shared.launchApplication(at: liveURL, options: [], configuration: [:])
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

        // Start resource download in parallel (fonts, presets, workflows)
        Task {
            await downloadResourcesIfNeeded()
        }

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

    // MARK: - Resource Download

    /// Download optional resources (fonts, presets, workflows) if not already present
    func downloadResourcesIfNeeded() async {
        let downloader = ResourceDownloader.shared

        // Skip if already downloaded or downloading
        guard downloader.needsResourceDownload else {
            isResourcesDownloaded = true
            return
        }

        guard !isDownloadingResources else { return }

        isDownloadingResources = true
        resourcesDownloadProgress = 0

        do {
            try await downloader.downloadResources()
            isResourcesDownloaded = true
        } catch {
            // Resource download failure is non-fatal - app works without them
            print("Resource download failed (non-fatal): \(error)")
        }

        isDownloadingResources = false
    }

    // MARK: - Status Checks

    var visibleChecks: [StatusCheck] {
        StatusCheck.allCases.filter { $0.isRequired(enableLiveMode: enableLiveMode) }
    }

    func performStatusChecks() async {
        allChecksComplete = false

        // 0. Pre-flight: Verify Talkie microphone permission (required for all modes).
        checkMicrophonePermission()
        if !hasMicrophonePermission {
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
                // Monitor ongoing download with timeout (5 minutes max)
                let downloadStart = Date()
                let downloadTimeout: TimeInterval = 300  // 5 minutes
                var elapsedSeconds = 0

                while isDownloadingModel {
                    let elapsed = Date().timeIntervalSince(downloadStart)
                    elapsedSeconds = Int(elapsed)

                    // Check for timeout
                    if elapsed > downloadTimeout {
                        await updateCheck(.modelDownload, status: .error("Download timed out"))
                        return
                    }

                    // Show progress or elapsed time (since libraries don't report %)
                    let percentage = Int(downloadProgress * 100)
                    if percentage > 0 && percentage < 100 {
                        await updateCheck(.modelDownload, status: .inProgress("\(percentage)%"))
                    } else {
                        // Show elapsed time when no progress available
                        let minutes = elapsedSeconds / 60
                        let seconds = elapsedSeconds % 60
                        let timeStr = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
                        await updateCheck(.modelDownload, status: .inProgress("Downloading... \(timeStr)"))
                    }
                    try? await Task.sleep(for: .milliseconds(500))
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

        // 3. Engine Connection (with timeout)
        await updateCheck(.engineConnection, status: .inProgress("Connecting..."))
        await checkServices()

        if isTalkieEngineRunning {
            await updateCheck(.engineConnection, status: .complete)
        } else {
            await updateCheck(.engineConnection, status: .inProgress("Starting Agent..."))
            await launchServices()

            // Wait for Agent/embedded engine with timeout (30 seconds)
            let engineTimeout: TimeInterval = 30
            let engineStart = Date()
            while !isTalkieEngineRunning && Date().timeIntervalSince(engineStart) < engineTimeout {
                try? await Task.sleep(for: .milliseconds(500))
                await checkServices()
            }

            if isTalkieEngineRunning {
                await updateCheck(.engineConnection, status: .complete)
            } else {
                await updateCheck(.engineConnection, status: .error("Agent startup timed out"))
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
                await updateCheck(.engineReady, status: .error("Embedded engine not responding"))
                return
            }
        }

        // 5. Live Service (conditional, with timeout)
        if enableLiveMode {
            await updateCheck(.liveService, status: .inProgress("Starting..."))

            // Ensure Agent is running first
            if !isTalkieAgentRunning {
                await updateCheck(.liveService, status: .inProgress("Starting Agent..."))
                await launchServices()

                // Wait for Agent with timeout (20 seconds)
                let agentTimeout: TimeInterval = 20
                let agentStart = Date()
                while !isTalkieAgentRunning && Date().timeIntervalSince(agentStart) < agentTimeout {
                    try? await Task.sleep(for: .milliseconds(500))
                    await checkServices()
                }

                if !isTalkieAgentRunning {
                    await updateCheck(.liveService, status: .error("Agent startup timed out"))
                    return
                }
            }

            // Agent is running — verify its permissions via XPC
            await updateCheck(.liveService, status: .inProgress("Checking permissions..."))
            try? await Task.sleep(for: .milliseconds(500))

            if let permissions = await ServiceManager.shared.live.checkPermissions() {
                if !permissions.microphone {
                    await updateCheck(.liveService, status: .inProgress("Requesting microphone..."))
                    await requestAgentMicrophonePermission()
                    if let refreshed = await ServiceManager.shared.live.checkPermissions(), refreshed.microphone {
                        hasAgentMicrophonePermission = true
                    } else {
                        await updateCheck(.liveService, status: .error("Grant Agent Microphone permission"))
                        return
                    }
                }
                if !permissions.accessibility {
                    await updateCheck(.liveService, status: .inProgress("Requesting Accessibility..."))
                    await requestAgentAccessibilityPermission()
                    if let refreshed = await ServiceManager.shared.live.checkPermissions(), refreshed.accessibility {
                        hasAgentAccessibilityPermission = true
                    } else {
                        await updateCheck(.liveService, status: .error("Grant Agent Accessibility permission"))
                        return
                    }
                }
                await updateCheck(.liveService, status: .complete)
            } else {
                // XPC not connected yet — mark complete, Agent will prompt on first use
                await updateCheck(.liveService, status: .complete)
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
        guard isTalkieEngineRunning else { return false }
        return await EngineClient.shared.ensureConnected()
    }

}
