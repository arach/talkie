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
    /// Posted when recording starts (for onboarding celebration - immediate feedback)
    static let recordingDidStart = Notification.Name("recordingDidStart")
    /// Posted when transcription completes (for dismissing onboarding after first use)
    static let transcriptionDidComplete = Notification.Name("transcriptionDidComplete")
    /// Posted to switch to Recent view (after first transcription)
    static let switchToRecent = Notification.Name("switchToRecent")
}

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case engineSetup = 1      // Introduce Talkie Live as menu bar app
    case modelDownload = 2    // Choose model (Parakeet vs Whisper)
    case engineWarmup = 3     // Engine connection + model warmup
    case ready = 4            // Try your hotkey
}

// MARK: - Onboarding Manager

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var currentStep: OnboardingStep = .welcome
    @Published var isEngineConnected = false
    @Published var isModelDownloaded = false
    @Published var isModelWarmedUp = false
    @Published var isCheckingEngine = false
    @Published var isWarmingUp = false
    @Published var warmupStatusMessage = ""
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

    func cancelDownload() async {
        await engineClient.cancelDownload()
        downloadProgress = 0
        downloadStatus = ""
    }

    /// Perform warmup - checks engine connection and model status
    /// Only runs if not already warmed up
    func performWarmup() async {
        // Skip if already warmed up
        guard !isModelWarmedUp else {
            warmupStatusMessage = "Ready to transcribe"
            return
        }

        // Step 1: Check engine connection
        warmupStatusMessage = "Connecting to TalkieEngine..."
        isCheckingEngine = true

        await checkEngineConnection()
        isCheckingEngine = false

        guard isEngineConnected else {
            warmupStatusMessage = "Could not connect to engine"
            return
        }

        // Step 2: Check if model is loaded
        warmupStatusMessage = "Checking model status..."
        isWarmingUp = true

        engineClient.refreshStatus()
        if let status = engineClient.status, status.loadedModelId != nil {
            isModelWarmedUp = true
            warmupStatusMessage = "Ready to transcribe"
        } else {
            warmupStatusMessage = "Model not loaded - download required"
        }

        isWarmingUp = false
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        isEngineConnected = false
        isModelDownloaded = false
        isModelWarmedUp = false
        isCheckingEngine = false
        isWarmingUp = false
        warmupStatusMessage = ""
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
                // Top bar - fixed height for consistent layout
                HStack {
                    Spacer()
                    Button(action: {
                        manager.completeOnboarding()
                        dismiss()
                    }) {
                        Text("SKIP ONBOARDING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .frame(height: 44)
                .padding(.horizontal, Spacing.lg)

                // Step content - fixed frame for consistent positioning
                Group {
                    switch manager.currentStep {
                    case .welcome:
                        WelcomeStepView(
                            colors: colors,
                            onNext: { manager.currentStep = .engineSetup }
                        )
                    case .engineSetup:
                        EngineSetupStepView(colors: colors, onNext: { manager.currentStep = .modelDownload })
                    case .modelDownload:
                        ModelDownloadStepView(colors: colors, onNext: { manager.currentStep = .engineWarmup })
                    case .engineWarmup:
                        EngineWarmupStepView(colors: colors, onNext: { manager.currentStep = .ready })
                    case .ready:
                        ReadyStepView(colors: colors, onComplete: {
                            manager.completeOnboarding()
                            dismiss()
                            // Navigate to Recent view after first transcription
                            NotificationCenter.default.post(name: .switchToRecent, object: nil)
                        })
                    }
                }
                .frame(maxHeight: .infinity)

                // Navigation - always present for consistent layout, but content hidden on welcome
                HStack(spacing: Spacing.lg) {
                    // Back button
                    Button(action: { manager.currentStep = OnboardingStep(rawValue: manager.currentStep.rawValue - 1) ?? .welcome }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .opacity(manager.currentStep != .welcome ? 1 : 0)

                    Spacer()

                    // Page dots with pulsation on current step
                    HStack(spacing: Spacing.xs) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                            Circle()
                                .fill(step.rawValue <= manager.currentStep.rawValue ? colors.accent : colors.border)
                                .frame(width: step == manager.currentStep ? 8 : 6, height: step == manager.currentStep ? 8 : 6)
                                .modifier(PulseModifier(isPulsing: step == manager.currentStep))
                                .animation(.spring(response: 0.3), value: manager.currentStep)
                        }
                    }
                    .opacity(manager.currentStep != .welcome ? 1 : 0)

                    Spacer()

                    // Forward button (visual placeholder for alignment)
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .frame(height: 40)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(width: 680, height: 520)
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

// MARK: - Onboarding CTA Button (Consistent sizing across all steps)

private struct OnboardingCTAButton: View {
    let colors: OnboardingColors
    let title: String
    var icon: String = "arrow.right"
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(CircularProgressViewStyle(tint: colors.textTertiary))
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                if !isLoading && !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundColor(isEnabled && !isLoading ? colors.background : colors.textTertiary)
            .frame(width: 200, height: 44)
            .background(isEnabled && !isLoading ? colors.accent : colors.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isEnabled && !isLoading ? Color.clear : colors.border, lineWidth: 1)
            )
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Onboarding Step Layout (Consistent scaffold for all steps)

private struct OnboardingStepLayout<Illustration: View, Content: View, CTA: View>: View {
    let colors: OnboardingColors
    let title: String
    let subtitle: String?
    let caption: String?
    @ViewBuilder let illustration: () -> Illustration
    @ViewBuilder let content: () -> Content
    @ViewBuilder let cta: () -> CTA

    init(
        colors: OnboardingColors,
        title: String,
        subtitle: String? = nil,
        caption: String? = nil,
        @ViewBuilder illustration: @escaping () -> Illustration,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.colors = colors
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
        self.illustration = illustration
        self.content = content
        self.cta = cta
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Illustration - fixed position from top
            illustration()
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

            // Title - fixed position from top
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.system(size: 24, weight: .black))
                    .tracking(1)
                    .foregroundColor(colors.textPrimary)
                    .multilineTextAlignment(.center)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let caption = caption {
                    Text(caption)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 130)

            // Content - fixed position from top
            content()
                .frame(maxWidth: .infinity)
                .padding(.top, 210)

            // CTA - fixed position from bottom
            VStack {
                Spacer()
                cta()
                    .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Onboarding CTA Footer (Anchored position) - DEPRECATED, use OnboardingStepLayout

private struct OnboardingCTAFooter<Content: View>: View {
    let colors: OnboardingColors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: Spacing.sm) {
            content()
        }
        .frame(height: 80) // Fixed height ensures consistent positioning
        .frame(maxWidth: .infinity)
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
        OnboardingStepLayout(
            colors: colors,
            title: "TALKIE LIVE",
            subtitle: "Voice to text anywhere on your Mac",
            illustration: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
            },
            content: {
                // Features - 3 column layout
                HStack(spacing: Spacing.lg) {
                    FeatureColumn(colors: colors, icon: "mic.fill", title: "Record", description: "Press hotkey\nin any app")
                    FeatureColumn(colors: colors, icon: "text.cursor", title: "Auto-paste", description: "Text appears\ninstantly")
                    FeatureColumn(colors: colors, icon: "cpu", title: "On-device", description: "Private, fast,\nno internet")
                }
            },
            cta: {
                OnboardingCTAButton(colors: colors, title: "GET STARTED", action: onNext)
            }
        )
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
        OnboardingStepLayout(
            colors: colors,
            title: "WORKS IN ANY APP",
            subtitle: "Global hotkey triggers recording anywhere",
            illustration: {
                // Menu bar illustration - offset down 5px due to different geometry
                MenuBarIllustration(colors: colors)
                    .padding(.top, 5)
            },
            content: {
                // Feature highlights - 3 column layout with better descriptions
                HStack(spacing: Spacing.xl) {
                    FeatureColumn(colors: colors, icon: "command", title: "Global Hotkeys", description: "Works in\nany app")
                    FeatureColumn(colors: colors, icon: "waveform", title: "No Latency", description: "On-device\nAI models")
                    FeatureColumn(colors: colors, icon: "doc.on.clipboard", title: "Smart Paste", description: "Text appears\ninstantly")
                }
            },
            cta: {
                OnboardingCTAButton(colors: colors, title: "CONTINUE", action: onNext)
            }
        )
    }
}

// MARK: - Menu Bar Illustration

private struct MenuBarIllustration: View {
    let colors: OnboardingColors

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Simulated menu bar
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
                        .fixedSize()
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
        OnboardingStepLayout(
            colors: colors,
            title: "POWERFUL AI MODELS",
            subtitle: "Your voice stays on your Mac",
            illustration: {
                // CPU/chip icon - represents on-device AI
                Image(systemName: "cpu")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(colors.accent)
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colors.accent.opacity(0.15))
                    )
            },
            content: {
                VStack(spacing: Spacing.md) {
                    // Model cards
                    HStack(alignment: .top, spacing: Spacing.md) {
                        ModelCard(
                            colors: colors,
                            isSelected: selectedModel == .parakeet,
                            logoName: "nvidia",
                            modelName: "Parakeet",
                            version: "v3",
                            size: "~200 MB",
                            specs: [
                                ("Speed", "Ultra-fast"),
                                ("Languages", "English")
                            ],
                            badge: "RECOMMENDED",
                            badgeColor: colors.accent,
                            isDownloaded: manager.isModelDownloaded && selectedModel == .parakeet,
                            learnMoreURL: "https://huggingface.co/nvidia/parakeet-tdt-1.1b"
                        ) {
                            selectedModel = .parakeet
                        }

                        ModelCard(
                            colors: colors,
                            isSelected: selectedModel == .whisper,
                            logoName: "openai",
                            modelName: "Whisper",
                            version: "large-v3",
                            size: "~1.5 GB",
                            specs: [
                                ("Speed", "Fast"),
                                ("Languages", "99+")
                            ],
                            badge: "MULTILINGUAL",
                            badgeColor: SemanticColor.info,
                            isDownloaded: false,
                            learnMoreURL: "https://openai.com/research/whisper"
                        ) {
                            selectedModel = .whisper
                        }
                    }

                    // Error message if any
                    if let error = manager.errorMessage {
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(SemanticColor.error)
                            .frame(height: 20)
                    } else {
                        Spacer().frame(height: 20)
                    }
                }
            },
            cta: {
                DownloadProgressButton(
                    colors: colors,
                    isDownloading: isDownloading,
                    progress: manager.downloadProgress,
                    accentColor: selectedModel == .parakeet ? colors.accent : SemanticColor.info,
                    onDownload: startDownload,
                    onCancel: cancelDownload
                )
            }
        )
    }

    private func startDownload() {
        isDownloading = true
        Task {
            await manager.downloadDefaultModel()
            isDownloading = false
            // Auto-advance to next screen when download completes
            if manager.isModelDownloaded {
                onNext()
            }
        }
    }

    private func cancelDownload() {
        Task {
            await manager.cancelDownload()
            isDownloading = false
        }
    }
}

// MARK: - Download Progress Button

private struct DownloadProgressButton: View {
    let colors: OnboardingColors
    let isDownloading: Bool
    let progress: Double
    let accentColor: Color
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if isDownloading {
            // Downloading state - progress bar button with cancel
            HStack(spacing: 12) {
                // Progress button
                Button(action: {}) {
                    ZStack {
                        // Background track
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(colors.surfaceCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(colors.border, lineWidth: 1)
                            )

                        // Progress fill from left
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(accentColor.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(progress))
                        }

                        // Text overlay
                        HStack(spacing: 6) {
                            Text("DOWNLOADING")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(accentColor)
                        }
                        .foregroundColor(colors.textPrimary)
                    }
                    .frame(width: 200, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(true)

                // Cancel button
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colors.textTertiary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(colors.surfaceCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(colors.border, lineWidth: 1)
                                )
                        )
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
        } else {
            // Ready to download state
            OnboardingCTAButton(
                colors: colors,
                title: "DOWNLOAD",
                icon: "arrow.down",
                isEnabled: true,
                isLoading: false,
                action: onDownload
            )
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

    @State private var isHovered = false

    var body: some View {
        // Card with badge at top and learn more on hover at bottom
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Logo + Model name (version on hover)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    if logoName == "nvidia" {
                        NvidiaLogo()
                            .frame(width: 26, height: 18)
                            .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                    } else {
                        OpenAILogo()
                            .frame(width: 20, height: 20)
                            .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                    }

                    Text(modelName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    if isHovered {
                        Text(version)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                            .transition(.opacity)
                    }
                }

                Divider()
                    .background(colors.border)

                // Specs (Size is first, then the rest)
                VStack(alignment: .leading, spacing: 4) {
                    // Size row
                    HStack {
                        Text("Size")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                        Spacer()
                        Text(size)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textSecondary)
                    }
                    ForEach(specs, id: \.0) { spec in
                        HStack {
                            Text(spec.0)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(colors.textTertiary)
                            Spacer()
                            Text(spec.1)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .padding(.top, 6)  // Extra top padding for badge
            .frame(width: 170)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
                    )
            )
            .overlay(alignment: .top) {
                // Badge floating on top edge (half in, half out)
                Text(badge)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colors.surfaceCard)
                            .overlay(
                                Capsule()
                                    .strokeBorder(badgeColor.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .offset(y: -8)
            }
            .overlay(alignment: .bottom) {
                // Learn more floating on bottom edge (half in, half out) - only on hover
                if isHovered {
                    Button(action: {
                        if let url = URL(string: learnMoreURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Learn more")
                                .font(.system(size: 10, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(colors.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(y: 8)
                    .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Engine Warmup Step

private struct EngineWarmupStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared

    private var isLoading: Bool {
        manager.isCheckingEngine || manager.isWarmingUp
    }

    private var statusSubtitle: String {
        if manager.isModelWarmedUp {
            return "All checks passed"
        } else if manager.isWarmingUp {
            return "Warming up engine..."
        } else if manager.isCheckingEngine {
            return "Connecting to engine..."
        } else {
            return "Verifying setup..."
        }
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "APP STATUS CHECK",
            subtitle: statusSubtitle,
            illustration: {
                // App icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
            },
            content: {
                // System check - label on left, value + checkmark on right
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    StatusCheckRowRight(
                        colors: colors,
                        label: "Model Selection",
                        value: "Parakeet v3",
                        isChecked: true,
                        isLoading: false
                    )
                    StatusCheckRowRight(
                        colors: colors,
                        label: "Engine Connection",
                        value: manager.isEngineConnected ? "Connected" : "Connecting...",
                        isChecked: manager.isEngineConnected,
                        isLoading: manager.isCheckingEngine
                    )
                    StatusCheckRowRight(
                        colors: colors,
                        label: "File Download",
                        value: manager.isModelDownloaded ? "Complete" : "Downloading...",
                        isChecked: manager.isModelDownloaded,
                        isLoading: false
                    )
                    StatusCheckRowRight(
                        colors: colors,
                        label: "Engine Status",
                        value: manager.isModelWarmedUp ? "Warmed up" : "Warming up...",
                        isChecked: manager.isModelWarmedUp,
                        isLoading: manager.isWarmingUp
                    )
                }
                .padding(Spacing.md)
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .strokeBorder(colors.border, lineWidth: 1)
                        )
                )
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "CONTINUE",
                    isEnabled: manager.isModelWarmedUp,
                    action: onNext
                )
            }
        )
        .onAppear {
            Task {
                await manager.performWarmup()
            }
        }
    }
}

// Simple spinning animation modifier
private struct SpinningModifier: ViewModifier {
    let isAnimating: Bool
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// Pulse animation modifier for current step indicator
private struct PulseModifier: ViewModifier {
    let isPulsing: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.3
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }
            }
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.3
                    }
                }
            }
    }
}

// MARK: - Status Check Row (Checkmark on right)

private struct StatusCheckRowRight: View {
    let colors: OnboardingColors
    let label: String
    let value: String
    let isChecked: Bool
    let isLoading: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(colors.textTertiary)

            Spacer()

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isChecked ? colors.textPrimary : colors.textSecondary)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if isChecked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            } else {
                Circle()
                    .strokeBorder(colors.textTertiary, lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
        }
    }
}

// MARK: - Status Check Row (Legacy - checkmark on left)

private struct StatusCheckRow: View {
    let colors: OnboardingColors
    let label: String
    let value: String
    let isChecked: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if isChecked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            } else {
                Circle()
                    .strokeBorder(colors.textTertiary, lineWidth: 1)
                    .frame(width: 14, height: 14)
            }

            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isChecked ? colors.textPrimary : colors.textSecondary)
        }
    }
}

// MARK: - Warmup Check Row (Legacy - keeping for compatibility)

private struct WarmupCheckRow: View {
    let colors: OnboardingColors
    let label: String
    let isChecked: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if isChecked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            } else {
                Circle()
                    .strokeBorder(colors.textTertiary, lineWidth: 1)
                    .frame(width: 14, height: 14)
            }

            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isChecked ? colors.textPrimary : colors.textTertiary)
        }
    }
}

// MARK: - Logo Views

private struct NvidiaLogo: View {
    var body: some View {
        Image("NvidiaLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

private struct OpenAILogo: View {
    var body: some View {
        Image("OpenAILogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
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
    @ObservedObject private var pillController = FloatingPillController.shared
    @State private var showCelebration = false
    @State private var celebrationMessage = "Recording..."
    @State private var demoState: OnboardingPillDemoState = .thinLine

    var body: some View {
        Group {
            if showCelebration {
                celebrationView
            } else {
                readyView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingDidStart)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showCelebration = true
                celebrationMessage = "Recording..."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDidComplete)) { _ in
            celebrationMessage = "You just transcribed your first recording!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }

    private var readyView: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "YOU'RE ALL SET",
            subtitle: "Two ways to start recording",
            illustration: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(colors.accent)
            },
            content: {
                // Two options: Hotkey and Always-on pill
                HStack(alignment: .top, spacing: Spacing.xl) {
                    // Hotkey option
                    VStack(spacing: Spacing.sm) {
                        Text("KEYBOARD SHORTCUT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)

                        Text(settings.hotkey.displayString)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(colors.accent)
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
                            .frame(height: 44)

                        Text("Press to toggle recording")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                    }
                    .frame(width: 160)

                    // Always-on pill option - interactive demo
                    VStack(spacing: Spacing.sm) {
                        Text("ALWAYS-ON PILL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)

                        // Interactive pill demo - hover to expand, click to record
                        OnboardingPillDemo(colors: colors)
                            .frame(height: 44)

                        Text("Bottom center of screen")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                    }
                    .frame(width: 160)
                }
            },
            cta: {
                OnboardingCTAButton(colors: colors, title: "START USING TALKIE", icon: "", action: onComplete)
            }
        )
    }

    private var celebrationView: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "NICE!",
            subtitle: celebrationMessage,
            illustration: {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 72))
                    .foregroundColor(colors.accent)
                    .symbolEffect(.bounce, value: showCelebration)
            },
            content: {
                EmptyView()
            },
            cta: {
                EmptyView()
            }
        )
    }
}

// MARK: - Onboarding Pill Demo State

private enum OnboardingPillDemoState {
    case thinLine
    case expanded
    case recording
}

// MARK: - Onboarding Pill Demo (Interactive demonstration of the always-on pill)

private struct OnboardingPillDemo: View {
    let colors: OnboardingColors
    @State private var state: OnboardingPillDemoState = .thinLine
    @State private var isHovered = false
    @State private var pulsePhase: CGFloat = 0
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var showDemoTooltip = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                switch state {
                case .thinLine:
                    // Thin sliver (collapsed state) - matches FloatingPillView
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colors.textTertiary.opacity(isHovered ? 0.5 : 0.3))
                        .frame(width: 24, height: 2)
                        .scaleEffect(isHovered ? 1.1 : 1.0)

                case .expanded:
                    // Expanded hover state - matches FloatingPillView
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colors.textPrimary)
                            .frame(width: 6, height: 6)

                        Text("REC")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )

                case .recording:
                    // Recording state with pulsing red dot
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SemanticColor.error)
                            .frame(width: 6, height: 6)
                            .scaleEffect(1.0 + pulsePhase * 0.4)

                        Text(timeString)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: state)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering && state == .thinLine {
                    withAnimation {
                        state = .expanded
                    }
                } else if !hovering && state == .expanded {
                    withAnimation {
                        state = .thinLine
                    }
                }
            }
            .onTapGesture {
                if state == .expanded {
                    // Start recording demo
                    withAnimation {
                        state = .recording
                        recordingTime = 0
                        pulsePhase = 0
                        showDemoTooltip = true
                    }
                    // Start pulse animation
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulsePhase = 1.0
                    }
                    // Start timer
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        recordingTime += 0.1
                    }
                } else if state == .recording {
                    // Stop recording demo
                    recordingTimer?.invalidate()
                    recordingTimer = nil
                    withAnimation {
                        state = .thinLine
                        pulsePhase = 0
                        showDemoTooltip = false
                    }
                }
            }

            // Demo tooltip - appears when "recording"
            if showDemoTooltip {
                VStack(spacing: 2) {
                    Text("This is just a demo!")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(colors.textSecondary)

                    HStack(spacing: 3) {
                        Text("Real pill is below")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(colors.accent)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var timeString: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        let tenths = Int((recordingTime * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
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
