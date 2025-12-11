//
//  OnboardingView.swift
//  TalkieLive
//
//  First-run onboarding flow: Engine setup + Model download
//  Design aligned with iOS onboarding (tactical dark theme with light/dark awareness)
//

import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a transcription completes successfully (for onboarding celebration)
    static let transcriptionDidComplete = Notification.Name("transcriptionDidComplete")
}

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
    @Published var shouldShowOnboarding: Bool

    private let engineClient = EngineClient.shared

    private init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
            shouldShowOnboarding = !newValue
        }
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

// MARK: - Onboarding Colors (Light/Dark Aware)

private struct OnboardingColors {
    let background: Color
    let surfaceCard: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let border: Color
    let gridLine: Color

    static func forScheme(_ colorScheme: ColorScheme) -> OnboardingColors {
        if colorScheme == .dark {
            return OnboardingColors(
                background: Color(hex: "0A0A0A"),
                surfaceCard: Color(hex: "151515"),
                textPrimary: .white,
                textSecondary: Color(hex: "9A9A9A"),
                textTertiary: Color(hex: "6A6A6A"),
                accent: Color(hex: "22C55E"),
                border: Color(hex: "3A3A3A"),
                gridLine: Color(hex: "1A1A1A")
            )
        } else {
            return OnboardingColors(
                background: Color(hex: "FAFAFA"),
                surfaceCard: .white,
                textPrimary: Color(hex: "0A0A0A"),
                textSecondary: Color(hex: "6A6A6A"),
                textTertiary: Color(hex: "9A9A9A"),
                accent: Color(hex: "22C55E"),
                border: Color(hex: "D0D0D0"),
                gridLine: Color(hex: "F0F0F0")
            )
        }
    }
}

// MARK: - Color Hex Initializer (for onboarding)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()

            // Grid pattern
            GridPatternView(lineColor: colors.gridLine)
                .opacity(0.5)

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: {
                        manager.completeOnboarding()
                        dismiss()
                    }) {
                        Text("SKIP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                Spacer()

                // Step content
                Group {
                    switch manager.currentStep {
                    case .welcome:
                        WelcomeStepView(colors: colors, onNext: { manager.currentStep = .engineSetup })
                    case .engineSetup:
                        EngineSetupStepView(colors: colors, onNext: { manager.currentStep = .modelDownload })
                    case .modelDownload:
                        ModelDownloadStepView(colors: colors, onNext: { manager.currentStep = .ready })
                    case .ready:
                        ReadyStepView(colors: colors, onComplete: {
                            manager.completeOnboarding()
                            dismiss()
                        })
                    }
                }

                Spacer()

                // Navigation (hidden on welcome screen)
                if manager.currentStep != .welcome {
                    HStack(spacing: Spacing.lg) {
                        // Back button
                        Button(action: { manager.currentStep = OnboardingStep(rawValue: manager.currentStep.rawValue - 1) ?? .welcome }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colors.textTertiary)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Page dots
                        HStack(spacing: Spacing.xs) {
                            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                                Circle()
                                    .fill(step.rawValue <= manager.currentStep.rawValue ? colors.accent : colors.border)
                                    .frame(width: step == manager.currentStep ? 8 : 6, height: step == manager.currentStep ? 8 : 6)
                                    .animation(.spring(response: 0.3), value: manager.currentStep)
                            }
                        }

                        Spacer()

                        // Forward button (visual placeholder for alignment)
                        Color.clear
                            .frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                }
            }
        }
        .frame(width: 680, height: 580)
        .background(WindowAccessor())
    }
}

// MARK: - Window Accessor (for Cmd+Q support in sheet)

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Ensure the app menu remains responsive while sheet is presented
            if let window = view.window {
                window.preventsApplicationTerminationWhenModal = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Grid Pattern

private struct GridPatternView: View {
    let lineColor: Color

    var body: some View {
        Canvas { context, size in
            let gridSize: CGFloat = 60

            // Vertical lines
            for x in stride(from: 0, to: size.width, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }

            // Horizontal lines
            for y in stride(from: 0, to: size.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Talkie Logo

private struct TalkieLogo: View {
    let colors: OnboardingColors

    var body: some View {
        HStack(spacing: 4) {
            Text(";)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(colors.accent)

            Text("Talkie")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(colors.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(colors.accent, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colors.background)
                )
        )
        .rotationEffect(.degrees(-3))
    }
}

// MARK: - Welcome Step

private struct WelcomeStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // App icon - using actual high-res icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            // Title bundle: headline + subtitle + tagline (closer together)
            VStack(spacing: Spacing.xs) {
                Text("TALKIE LIVE")
                    .font(.system(size: 34, weight: .black))
                    .tracking(-1)
                    .foregroundColor(colors.textPrimary)

                HStack(spacing: 10) {
                    Text("VOICE")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colors.textSecondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colors.textTertiary)

                    Text("TEXT")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(colors.accent)
                }

                Text("Instantly anywhere on your Mac")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .padding(.top, 2)
            }

            // Features - 3 column layout
            HStack(spacing: Spacing.lg) {
                FeatureColumn(colors: colors, icon: "mic.fill", title: "Record", description: "Press hotkey\nin any app")
                FeatureColumn(colors: colors, icon: "text.cursor", title: "Auto-paste", description: "Text appears\ninstantly")
                FeatureColumn(colors: colors, icon: "cpu", title: "On-device", description: "Private, fast,\nno internet")
            }

            // Get Started button
            Button(action: onNext) {
                HStack(spacing: Spacing.sm) {
                    Text("GET STARTED")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(2)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(colors.background)
                .frame(width: 220, height: 48)
                .background(colors.accent)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Feature Column (3-column layout)

private struct FeatureColumn: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(colors.accent)
                .frame(width: 32, height: 32)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 100)
    }
}

// MARK: - Talkie Live Intro Step (Menu Bar App)

private struct EngineSetupStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Menu bar illustration - showing TalkieLive's location
            VStack(spacing: Spacing.sm) {
                // Simulated full-width menu bar
                HStack(spacing: 0) {
                    // Left side: Apple logo + app menu
                    HStack(spacing: 16) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textTertiary.opacity(0.8))

                        Text("Cursor")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.textTertiary.opacity(0.8))

                        HStack(spacing: 14) {
                            Text("File")
                            Text("Edit")
                            Text("View")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(colors.textTertiary.opacity(0.6))
                    }

                    Spacer()

                    // Right side: System tray icons
                    HStack(spacing: 12) {
                        // Third-party apps
                        ChatGPTMenuIcon()
                            .frame(width: 14, height: 14)
                            .foregroundColor(colors.textTertiary.opacity(0.7))

                        Image("ClaudeMenuIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundColor(colors.textTertiary.opacity(0.7))

                        // TalkieLive icon (highlighted)
                        Image("MenuBarIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundColor(colors.accent)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colors.accent.opacity(0.2))
                            )

                        // System icons
                        Image(systemName: "wifi")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textTertiary.opacity(0.7))

                        Image(systemName: "battery.75percent")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textTertiary.opacity(0.7))

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textTertiary.opacity(0.7))

                        Text("Thu 9:41 AM")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textTertiary.opacity(0.8))
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colors.surfaceCard.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(colors.border, lineWidth: 1)
                        )
                )
                .frame(width: 560)

                Text("Find it in your menu bar")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }

            VStack(spacing: Spacing.sm) {
                Text("TALKIE LIVE")
                    .font(.system(size: 24, weight: .black))
                    .tracking(1)
                    .foregroundColor(colors.textPrimary)

                Text("Always ready when you need it")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Feature highlights - 3 column layout
            HStack(spacing: Spacing.xl) {
                FeatureColumn(colors: colors, icon: "command", title: "Hotkey", description: "Press anywhere\nto start")
                FeatureColumn(colors: colors, icon: "mic.fill", title: "Speak", description: "Talk naturally\ninto your mic")
                FeatureColumn(colors: colors, icon: "doc.on.clipboard", title: "Paste", description: "Text appears\ninstantly")
            }

            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text("CONTINUE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(colors.background)
                .frame(width: 160, height: 40)
                .background(colors.accent)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Model Download Step

private enum ModelChoice: String, CaseIterable {
    case parakeet
    case whisper
}

private struct ModelDownloadStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isDownloading = false
    @State private var selectedModel: ModelChoice = .parakeet

    var body: some View {
        VStack(spacing: Spacing.md) {
            // TalkieEngine introduction
            HStack(spacing: Spacing.sm) {
                Image(systemName: "engine.combustion")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors.accent.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("POWERED BY TALKIE ENGINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(colors.textTertiary)

                    Text("Runs your model locally")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 1)
                    )
            )

            VStack(spacing: Spacing.xs) {
                Text("CHOOSE YOUR MODEL")
                    .font(.system(size: 22, weight: .black))
                    .tracking(1)
                    .foregroundColor(colors.textPrimary)

                Text("Runs entirely on your Mac")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textSecondary)

                Text("You can always change this later in Settings")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
                    .padding(.top, 2)
            }

            // Model cards
            HStack(alignment: .top, spacing: Spacing.md) {
                // Parakeet card
                ModelCard(
                    colors: colors,
                    isSelected: selectedModel == .parakeet,
                    logoName: "nvidia",
                    modelName: "Parakeet",
                    version: "v3",
                    size: "~200 MB",
                    specs: [
                        ("Speed", "Ultra-fast"),
                        ("Quality", "Excellent"),
                        ("Languages", "English")
                    ],
                    badge: "RECOMMENDED",
                    badgeColor: colors.accent,
                    isDownloaded: manager.isModelDownloaded && selectedModel == .parakeet,
                    learnMoreURL: "https://huggingface.co/nvidia/parakeet-tdt-1.1b"
                ) {
                    selectedModel = .parakeet
                }

                // Whisper card
                ModelCard(
                    colors: colors,
                    isSelected: selectedModel == .whisper,
                    logoName: "openai",
                    modelName: "Whisper",
                    version: "large-v3",
                    size: "~1.5 GB",
                    specs: [
                        ("Speed", "Fast"),
                        ("Quality", "Excellent"),
                        ("Languages", "99+")
                    ],
                    badge: "MULTILINGUAL",
                    badgeColor: .cyan,
                    isDownloaded: false,
                    learnMoreURL: "https://openai.com/research/whisper"
                ) {
                    selectedModel = .whisper
                }
            }

            // Download progress
            if isDownloading || manager.downloadProgress > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: manager.downloadProgress)
                        .tint(selectedModel == .parakeet ? colors.accent : .cyan)
                        .frame(maxWidth: 300)

                    Text(manager.downloadStatus.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(colors.textTertiary)
                }
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }

            // Action button
            if !manager.isModelDownloaded {
                Button(action: startDownload) {
                    HStack(spacing: 6) {
                        Text(isDownloading ? "DOWNLOADING..." : "DOWNLOAD \(selectedModel == .parakeet ? "PARAKEET" : "WHISPER")")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                        if !isDownloading {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundColor(isDownloading ? colors.textTertiary : colors.background)
                    .frame(width: 220, height: 40)
                    .background(isDownloading ? colors.surfaceCard : colors.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isDownloading ? colors.border : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            } else {
                Button(action: onNext) {
                    HStack(spacing: 6) {
                        Text("CONTINUE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(colors.background)
                    .frame(width: 180, height: 40)
                    .background(colors.accent)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
    }

    private func startDownload() {
        isDownloading = true
        Task {
            await manager.downloadDefaultModel()
            isDownloading = false
        }
    }
}

// MARK: - Model Card

private struct ModelCard: View {
    let colors: OnboardingColors
    let isSelected: Bool
    let logoName: String
    let modelName: String
    let version: String
    let size: String
    let specs: [(String, String)]
    let badge: String
    let badgeColor: Color
    let isDownloaded: Bool
    let learnMoreURL: String
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Header with logo
                    HStack {
                        // Logo placeholder (NVIDIA or OpenAI style)
                        if logoName == "nvidia" {
                            NvidiaLogo()
                                .frame(width: 20, height: 20)
                        } else {
                            OpenAILogo()
                                .frame(width: 18, height: 18)
                        }

                        Spacer()

                        // Badge
                        Text(badge)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.15))
                            .cornerRadius(4)
                    }

                    // Model name
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(modelName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(colors.textPrimary)

                        Text(version)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textTertiary)

                        if isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(colors.accent)
                        }
                    }

                    // Size
                    Text(size)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.textTertiary)

                    Divider()
                        .background(colors.border)

                    // Specs
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(specs, id: \.0) { spec in
                            HStack {
                                Text(spec.0)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)
                                Spacer()
                                Text(spec.1)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(colors.textSecondary)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .frame(width: 160)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Learn more link
            Button(action: {
                if let url = URL(string: learnMoreURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 3) {
                    Text("Learn more")
                        .font(.system(size: 9, design: .monospaced))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(colors.textTertiary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

// MARK: - Logo Views

private struct NvidiaLogo: View {
    var body: some View {
        // Simplified NVIDIA eye logo
        ZStack {
            // Green background
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "76B900"))

            // Eye shape
            Path { path in
                path.move(to: CGPoint(x: 4, y: 10))
                path.addQuadCurve(to: CGPoint(x: 16, y: 10), control: CGPoint(x: 10, y: 4))
                path.addQuadCurve(to: CGPoint(x: 4, y: 10), control: CGPoint(x: 10, y: 16))
            }
            .fill(Color.white)
            .scaleEffect(0.8)
        }
    }
}

private struct OpenAILogo: View {
    var body: some View {
        // Simplified OpenAI logo (hexagonal flower)
        ZStack {
            Circle()
                .fill(Color.white)

            // Simple representation
            Image(systemName: "hexagon")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black)
        }
    }
}

// MARK: - ChatGPT Menu Bar Icon

private struct ChatGPTMenuIcon: View {
    var body: some View {
        // ChatGPT's menu bar icon: a simple circle with inner design
        ZStack {
            Circle()
                .strokeBorder(lineWidth: 1.5)

            // Inner dot pattern similar to ChatGPT logo
            Circle()
                .frame(width: 4, height: 4)
        }
    }
}

// MARK: - Ready Step

private struct ReadyStepView: View {
    let colors: OnboardingColors
    let onComplete: () -> Void
    @ObservedObject private var settings = LiveSettings.shared
    @State private var showCelebration = false
    @State private var autoDismissCountdown = 3

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if showCelebration {
                // Celebration state - first transcription success!
                celebrationView
            } else {
                // Ready state - waiting for user to try hotkey
                readyView
            }
        }
        .padding(Spacing.xl)
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDidComplete)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showCelebration = true
            }
            // Auto-dismiss after countdown
            startAutoDismiss()
        }
    }

    private var readyView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(colors.accent)

            VStack(spacing: Spacing.sm) {
                Text("ALL SET")
                    .font(.system(size: 28, weight: .black))
                    .tracking(2)
                    .foregroundColor(colors.textPrimary)

                Text("Talkie Live is ready to use")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
            }

            // Hotkey display with "try it now" encouragement
            VStack(spacing: Spacing.sm) {
                Text("TRY IT NOW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(colors.accent)

                Text(settings.hotkey.displayString)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(colors.accent)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(colors.surfaceCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(colors.accent.opacity(0.3), lineWidth: 1)
                            )
                    )

                Text("Press once to start, again to stop")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }
            .padding(.vertical, Spacing.md)

            Button(action: onComplete) {
                Text("SKIP")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(colors.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sm)
        }
    }

    private var celebrationView: some View {
        VStack(spacing: Spacing.lg) {
            // Celebration icon with animation
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundColor(colors.accent)
                .symbolEffect(.bounce, value: showCelebration)

            VStack(spacing: Spacing.sm) {
                Text("NICE!")
                    .font(.system(size: 32, weight: .black))
                    .tracking(2)
                    .foregroundColor(colors.textPrimary)

                Text("You just transcribed your first recording")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.xs) {
                Text("You're all set to go")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.textTertiary)

                Text("Closing in \(autoDismissCountdown)...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary.opacity(0.7))
            }
            .padding(.top, Spacing.md)

            Button(action: onComplete) {
                HStack(spacing: Spacing.sm) {
                    Text("LET'S GO")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(colors.background)
                .frame(width: 180, height: 44)
                .background(colors.accent)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sm)
        }
    }

    private func startAutoDismiss() {
        autoDismissCountdown = 3
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if autoDismissCountdown > 1 {
                autoDismissCountdown -= 1
            } else {
                timer.invalidate()
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
