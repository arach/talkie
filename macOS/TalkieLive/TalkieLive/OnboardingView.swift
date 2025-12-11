//
//  OnboardingView.swift
//  TalkieLive
//
//  First-run onboarding flow: Engine setup + Model download
//

import SwiftUI

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case engineSetup = 1
    case modelDownload = 2
    case ready = 3
}

// MARK: - Onboarding Manager

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var currentStep: OnboardingStep = .welcome
    @Published var isEngineConnected = false
    @Published var isModelDownloaded = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    @Published var errorMessage: String?

    private let engineClient = EngineClient.shared

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding
    }

    func checkEngineConnection() async {
        let connected = await engineClient.ensureConnected()
        isEngineConnected = connected

        if connected {
            // Check if model is already loaded
            engineClient.refreshStatus()
            if let status = engineClient.status, status.loadedModelId != nil {
                isModelDownloaded = true
            }
        }
    }

    func downloadDefaultModel() async {
        downloadStatus = "Connecting to engine..."
        errorMessage = nil

        // Ensure engine is connected
        let connected = await engineClient.ensureConnected()
        guard connected else {
            errorMessage = "Could not connect to TalkieEngine"
            return
        }

        downloadStatus = "Downloading Parakeet model..."

        // Subscribe to download progress
        let progressTask = Task {
            for await progress in engineClient.$downloadProgress.values {
                if let progress = progress {
                    self.downloadProgress = progress.progress
                    self.downloadStatus = progress.isDownloading
                        ? "Downloading: \(progress.progressFormatted)"
                        : "Preparing..."
                }
            }
        }

        // Request model preload (Parakeet v3 is the default)
        let modelId = "parakeet:v3"
        do {
            try await engineClient.preloadModel(modelId)
            isModelDownloaded = true
            downloadStatus = "Model ready!"
            downloadProgress = 1.0
        } catch {
            errorMessage = error.localizedDescription
            downloadStatus = "Download failed"
        }

        progressTask.cancel()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        isEngineConnected = false
        isModelDownloaded = false
        downloadProgress = 0
        downloadStatus = ""
        errorMessage = nil
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= manager.currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch manager.currentStep {
                case .welcome:
                    WelcomeStepView(onNext: { manager.currentStep = .engineSetup })
                case .engineSetup:
                    EngineSetupStepView(onNext: { manager.currentStep = .modelDownload })
                case .modelDownload:
                    ModelDownloadStepView(onNext: { manager.currentStep = .ready })
                case .ready:
                    ReadyStepView(onComplete: {
                        manager.completeOnboarding()
                        dismiss()
                    })
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: manager.currentStep)

            Spacer()
        }
        .frame(width: 500, height: 400)
        .background(TalkieTheme.surface)
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // App icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Welcome to Talkie Live")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Voice-to-text, instantly anywhere on your Mac")
                    .font(.system(size: 14))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "mic.fill", title: "Record anywhere", description: "Press hotkey in any app")
                FeatureRow(icon: "text.cursor", title: "Auto-paste", description: "Transcription appears instantly")
                FeatureRow(icon: "cpu", title: "100% on-device", description: "Private, fast, no internet needed")
            }
            .padding(.top, 8)

            Button(action: onNext) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 40)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(32)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }
        }
    }
}

// MARK: - Engine Setup Step

struct EngineSetupStepView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("TalkieEngine Setup")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Talkie Live uses TalkieEngine for fast on-device transcription")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Status
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Circle()
                            .fill(manager.isEngineConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }

                    Text(isChecking ? "Checking connection..." : (manager.isEngineConnected ? "Engine connected" : "Engine not running"))
                        .font(.system(size: 13))
                        .foregroundColor(TalkieTheme.textSecondary)
                }

                if !manager.isEngineConnected && !isChecking {
                    Text("Please ensure TalkieEngine is installed and running")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(TalkieTheme.secondaryBackground)
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button(action: checkConnection) {
                    Text(isChecking ? "Checking..." : "Check Connection")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TalkieTheme.textPrimary)
                        .frame(width: 140, height: 36)
                        .background(TalkieTheme.secondaryBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isChecking)

                if manager.isEngineConnected {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 140, height: 36)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .onAppear {
            checkConnection()
        }
    }

    private func checkConnection() {
        isChecking = true
        Task {
            await manager.checkEngineConnection()
            isChecking = false
        }
    }
}

// MARK: - Model Download Step

struct ModelDownloadStepView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isDownloading = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan)

            VStack(spacing: 8) {
                Text("Download Speech Model")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Parakeet is a fast, accurate speech recognition model that runs entirely on your Mac")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Download progress
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parakeet v3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)
                        Text("~200 MB download")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }

                    Spacer()

                    if manager.isModelDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if isDownloading || manager.downloadProgress > 0 {
                    VStack(spacing: 6) {
                        ProgressView(value: manager.downloadProgress)
                            .tint(.cyan)

                        Text(manager.downloadStatus)
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(16)
            .background(TalkieTheme.secondaryBackground)
            .cornerRadius(8)

            HStack(spacing: 12) {
                if !manager.isModelDownloaded {
                    Button(action: startDownload) {
                        Text(isDownloading ? "Downloading..." : "Download Model")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 160, height: 36)
                            .background(isDownloading ? Color.gray : Color.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloading)
                } else {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 160, height: 36)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .onAppear {
            // Auto-check if model is already downloaded
            if manager.isModelDownloaded {
                // Already done
            }
        }
    }

    private func startDownload() {
        isDownloading = true
        Task {
            await manager.downloadDefaultModel()
            isDownloading = false
        }
    }
}

// MARK: - Ready Step

struct ReadyStepView: View {
    let onComplete: () -> Void
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Talkie Live is ready to use")
                    .font(.system(size: 14))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            // Hotkey reminder
            VStack(spacing: 8) {
                Text("Your recording hotkey:")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)

                Text(settings.hotkey.displayString)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(TalkieTheme.secondaryBackground)
                    .cornerRadius(8)

                Text("Press once to start, again to stop")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
            .padding(.vertical, 16)

            Button(action: onComplete) {
                Text("Start Using Talkie Live")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 220, height: 40)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
