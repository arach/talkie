//
//  OnboardingView.swift
//  TalkieLive
//
//  First-run onboarding flow: Engine setup + Model download
//  Design aligned with iOS onboarding (tactical dark theme with light/dark awareness)
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
    let bracketColor: Color

    static func forScheme(_ colorScheme: ColorScheme) -> OnboardingColors {
        if colorScheme == .dark {
            return OnboardingColors(
                background: Color(hex: "0A0A0A"),
                surfaceCard: Color(hex: "151515"),
                textPrimary: .white,
                textSecondary: Color(hex: "9A9A9A"),
                textTertiary: Color(hex: "6A6A6A"),
                accent: Color(hex: "22C55E"),
                border: Color(hex: "2A2A2A"),
                gridLine: Color(hex: "2A2A2A"),
                bracketColor: Color(hex: "4A4A4A")
            )
        } else {
            return OnboardingColors(
                background: Color(hex: "FAFAFA"),
                surfaceCard: .white,
                textPrimary: Color(hex: "0A0A0A"),
                textSecondary: Color(hex: "6A6A6A"),
                textTertiary: Color(hex: "9A9A9A"),
                accent: Color(hex: "22C55E"),
                border: Color(hex: "E5E5E5"),
                gridLine: Color(hex: "E8E8E8"),
                bracketColor: Color(hex: "BABABA")
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

            // Corner brackets
            CornerBrackets(color: colors.bracketColor)

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
                    .buttonStyle(.plain)
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

                // Navigation
                HStack(spacing: Spacing.lg) {
                    // Back button
                    Button(action: { manager.currentStep = OnboardingStep(rawValue: manager.currentStep.rawValue - 1) ?? .welcome }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .opacity(manager.currentStep.rawValue > 0 ? 1 : 0)
                    .disabled(manager.currentStep == .welcome)

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
        .frame(width: 680, height: 580)
    }
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
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }

            // Horizontal lines
            for y in stride(from: 0, to: size.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
        }
    }
}

// MARK: - Corner Brackets

private struct CornerBrackets: View {
    let color: Color
    private let bracketSize: CGFloat = 32
    private let strokeWidth: CGFloat = 2
    private let inset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            // Top-left
            BracketShape(corner: .topLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + inset, y: bracketSize / 2 + inset)

            // Top-right
            BracketShape(corner: .topRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - inset, y: bracketSize / 2 + inset)

            // Bottom-left
            BracketShape(corner: .bottomLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + inset, y: geo.size.height - bracketSize / 2 - inset)

            // Bottom-right
            BracketShape(corner: .bottomRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - inset, y: geo.size.height - bracketSize / 2 - inset)
        }
    }
}

private enum BracketCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

private struct BracketShape: Shape {
    let corner: BracketCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = min(rect.width, rect.height)

        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        case .topRight:
            path.move(to: CGPoint(x: rect.width - length, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: length))
        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: rect.height - length))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: length, y: rect.height))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.width, y: rect.height - length))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width - length, y: rect.height))
        }

        return path
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
        VStack(spacing: 0) {
            // App icon - using actual high-res icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
                .padding(.bottom, Spacing.xxl)

            // Title bundle: headline + subtitle + tagline (closer together)
            VStack(spacing: Spacing.xs) {
                Text("TALKIE LIVE")
                    .font(.system(size: 36, weight: .black))
                    .tracking(-1)
                    .foregroundColor(colors.textPrimary)

                HStack(spacing: 10) {
                    Text("VOICE")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colors.textSecondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colors.textTertiary)

                    Text("TEXT")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(colors.accent)
                }

                Text("Instantly anywhere on your Mac")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .padding(.top, Spacing.xxs)
            }

            // Features
            VStack(alignment: .leading, spacing: Spacing.md) {
                FeatureRow(colors: colors, icon: "mic.fill", title: "Record anywhere", description: "Press hotkey in any app")
                FeatureRow(colors: colors, icon: "text.cursor", title: "Auto-paste", description: "Transcription appears instantly")
                FeatureRow(colors: colors, icon: "cpu", title: "100% on-device", description: "Private, fast, no internet needed")
            }
            .padding(.top, Spacing.xl)

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
            .padding(.top, Spacing.xxl)
        }
        .padding(Spacing.xxl)
    }
}

private struct FeatureRow: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text(description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }
}

// MARK: - Engine Setup Step

private struct EngineSetupStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Menu bar illustration
            VStack(spacing: Spacing.xs) {
                // Simulated menu bar
                HStack(spacing: Spacing.sm) {
                    Spacer()

                    // Menu bar icon representation
                    Image("MenuBarIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colors.accent.opacity(0.2))
                        )

                    // Other mock menu bar items
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.textTertiary.opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(colors.border, lineWidth: 1)
                        )
                )
                .frame(width: 180)

                Text("Lives in your menu bar")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }

            VStack(spacing: Spacing.sm) {
                Text("TALKIE ENGINE")
                    .font(.system(size: 24, weight: .black))
                    .tracking(1)
                    .foregroundColor(colors.textPrimary)

                Text("Powers on-device transcription")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Status panel
            VStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Circle()
                            .fill(manager.isEngineConnected ? colors.accent : Color.red)
                            .frame(width: 8, height: 8)
                    }

                    Text(isChecking ? "CHECKING..." : (manager.isEngineConnected ? "CONNECTED" : "OFFLINE"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(isChecking ? colors.textTertiary : (manager.isEngineConnected ? colors.accent : .red))
                }

                if !manager.isEngineConnected && !isChecking {
                    Text("Ensure TalkieEngine is installed and running")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 1)
                    )
            )

            HStack(spacing: Spacing.sm) {
                Button(action: checkConnection) {
                    Text(isChecking ? "CHECKING..." : "CHECK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 120, height: 36)
                        .background(colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .strokeBorder(colors.border, lineWidth: 1)
                        )
                        .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
                .disabled(isChecking)

                if manager.isEngineConnected {
                    Button(action: onNext) {
                        HStack(spacing: 6) {
                            Text("CONTINUE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(colors.background)
                        .frame(width: 140, height: 36)
                        .background(colors.accent)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.xl)
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

private struct ModelDownloadStepView: View {
    let colors: OnboardingColors
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isDownloading = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan)

            VStack(spacing: Spacing.sm) {
                Text("SPEECH MODEL")
                    .font(.system(size: 24, weight: .black))
                    .tracking(1)
                    .foregroundColor(colors.textPrimary)

                Text("Fast, accurate, runs entirely on your Mac")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Download panel
            VStack(spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("PARAKEET V3")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(colors.textPrimary)

                            if manager.isModelDownloaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(colors.accent)
                                    .font(.system(size: 12))
                            }
                        }
                        Text("~200 MB download")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                    }

                    Spacer()
                }

                if isDownloading || manager.downloadProgress > 0 {
                    VStack(spacing: 6) {
                        ProgressView(value: manager.downloadProgress)
                            .tint(.cyan)

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
            }
            .padding(Spacing.md)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 1)
                    )
            )

            if !manager.isModelDownloaded {
                Button(action: startDownload) {
                    HStack(spacing: 6) {
                        Text(isDownloading ? "DOWNLOADING..." : "DOWNLOAD")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                        if !isDownloading {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundColor(isDownloading ? colors.textTertiary : colors.background)
                    .frame(width: 180, height: 40)
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
        .padding(Spacing.xl)
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

private struct ReadyStepView: View {
    let colors: OnboardingColors
    let onComplete: () -> Void
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
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

            // Hotkey display
            VStack(spacing: Spacing.sm) {
                Text("YOUR HOTKEY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(colors.textTertiary)

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
                HStack(spacing: Spacing.sm) {
                    Text("START USING TALKIE LIVE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(colors.background)
                .frame(width: 280, height: 44)
                .background(colors.accent)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.md)
        }
        .padding(Spacing.xl)
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
