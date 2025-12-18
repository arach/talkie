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
    case permissions = 1
    case serviceSetup = 2
    case modelInstall = 3
    case llmConfig = 4
    case complete = 5
}

// MARK: - Onboarding Manager

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var currentStep: OnboardingStep = .welcome
    @Published var shouldShowOnboarding: Bool

    // Permissions state
    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false
    @Published var hasScreenRecordingPermission = false
    @Published var isRequestingPermission = false

    // Service setup state
    @Published var isTalkieLiveRunning = false
    @Published var isTalkieEngineRunning = false
    @Published var isCheckingServices = false
    @Published var isLaunchingServices = false

    // Model installation state
    @Published var isModelDownloaded = false
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    @Published var selectedModelType: String = "parakeet"  // "parakeet" or "whisper"

    // LLM configuration state
    @Published var llmProvider: String? = nil  // "openai" or "anthropic"
    @Published var hasConfiguredLLM = false

    // Error handling
    @Published var errorMessage: String?

    private var accessibilityCheckTimer: Timer?

    private init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        checkInitialPermissions()
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
        selectedModelType = "parakeet"
        llmProvider = nil
        hasConfiguredLLM = false
        errorMessage = nil
    }

    // MARK: - Permissions

    private func checkInitialPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }

    func checkMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.hasMicrophonePermission = granted
            }
        }
    }

    func requestMicrophonePermission() async {
        isRequestingPermission = true
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = granted
                    self.isRequestingPermission = false
                    continuation.resume()
                }
            }
        }
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
            hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        } else {
            hasScreenRecordingPermission = true
        }
    }

    func requestScreenRecordingPermission() {
        if #available(macOS 10.15, *) {
            // This will trigger the system permission dialog
            CGRequestScreenCaptureAccess()
            // Wait a moment then check again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.checkScreenRecordingPermission()
            }
        }
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
    }

    private func stopAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    // MARK: - Service Setup

    func checkServices() async {
        isCheckingServices = true

        // Check if TalkieLive is running
        let liveRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "jdi.talkie.live"
        }
        isTalkieLiveRunning = liveRunning

        // Check if TalkieEngine is running
        let engineRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "jdi.talkie.engine"
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

    var selectedModelId: String {
        selectedModelType == "parakeet" ? "parakeet:v3" : "whisper:large-v3-turbo"
    }

    var selectedModelDisplayName: String {
        selectedModelType == "parakeet" ? "Parakeet v3" : "Whisper Large v3"
    }

    func checkModelInstalled() async {
        // Check if the selected model is already downloaded
        // This would integrate with TalkieEngine's model management
        // For now, we'll simulate the check
        isModelDownloaded = false
    }

    func downloadModel() async {
        isDownloadingModel = true
        downloadStatus = "Downloading \(selectedModelDisplayName)..."
        errorMessage = nil

        // Simulate download progress
        // In production, this would connect to TalkieEngine's download API
        for i in 0...100 {
            downloadProgress = Double(i) / 100.0
            downloadStatus = "Downloading: \(i)%"
            try? await Task.sleep(for: .milliseconds(50))
        }

        isModelDownloaded = true
        downloadStatus = "Model ready!"
        isDownloadingModel = false
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
