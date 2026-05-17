//
//  OnboardingView.swift
//  Talkie iOS
//
//  First-launch onboarding experience.
//  Theme-aware: every surface, accent, and chrome detail reads from the
//  active theme. Scope users see cream paper + amber chrome; tactical users
//  see gunmetal + orange; ghost sees frost + indigo; midnight sees jet + blue.
//

import SwiftUI
import CloudKit
import UIKit
import TalkieMobileKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasSeenOnboarding: Bool
    var onStartRecording: (() -> Void)? = nil

    @State private var currentPage = 0
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @ObservedObject private var theme = ThemeManager.shared

    private let totalPages = 4

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: completeOnboarding) {
                        Text("SKIP")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(theme.colors.textTertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                TabView(selection: $currentPage) {
                    WelcomePage().tag(0)
                    CapturePage().tag(1)
                    SyncPage().tag(2)
                    GetStartedPage(
                        iCloudStatus: iCloudStatus,
                        onComplete: completeOnboarding,
                        onTryRecord: {
                            completeOnboarding()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onStartRecording?()
                            }
                        }
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Page indicator + navigation
                HStack(spacing: Spacing.lg) {
                    Button(action: { currentPage -= 1 }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(theme.colors.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .opacity(currentPage > 0 ? 1 : 0)
                    .disabled(currentPage == 0)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? chrome.accent : chrome.edge)
                                .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    Spacer()

                    Button(action: {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        Image(systemName: currentPage < totalPages - 1 ? "chevron.right" : "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(chrome.panelInk)
                            .frame(width: 44, height: 44)
                            .background(chrome.accent)
                            .clipShape(Circle())
                            .talkieAccentGlow()
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
        }
        .onAppear {
            checkiCloudStatus()
        }
    }

    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }

    private func checkiCloudStatus() {
        #if targetEnvironment(simulator)
        iCloudStatus = .couldNotDetermine
        return
        #else
        CKContainer(identifier: TalkieMobileRuntimeIdentifiers.cloudKitContainerIdentifier).accountStatus { status, _ in
            DispatchQueue.main.async {
                self.iCloudStatus = status
            }
        }
        #endif
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            GridPatternView(color: chrome.edgeSubtle)
                .opacity(0.6)

            CornerBrackets(color: chrome.edge)

            VStack(spacing: Spacing.xs) {
                Spacer()
                Spacer()

                // Logo with ribbon
                ZStack(alignment: .topTrailing) {
                    Image("TalkieLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(chrome.edge, lineWidth: 1)
                        )

                    TalkieLogoRibbon()
                        .offset(x: 48, y: -28)
                }

                // VOICE + AI
                HStack(spacing: 8) {
                    Text("VOICE")
                        .font(.system(size: 36, weight: .black, design: .default))
                        .foregroundColor(theme.colors.textPrimary)

                    Text("+ AI")
                        .font(.system(size: 36, weight: .black, design: .default))
                        .foregroundColor(chrome.accent)
                        .talkieAccentGlow()
                }
                .padding(.top, Spacing.sm)

                // Tagline
                VStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        TaglineWord("Record")
                        TaglineSeparator()
                        TaglineWord("Dictate")
                        TaglineSeparator()
                        TaglineWord("Transcribe")
                    }

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(theme.colors.textTertiary)

                        Text("On-device. Private. Yours.")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.colors.textTertiary)
                    }
                }
                .padding(.top, Spacing.md)

                Spacer()
                Spacer()

                VStack(spacing: 4) {
                    Text("usetalkie.com")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.colors.textTertiary)

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.colors.textTertiary.opacity(0.7))
                }
                .padding(.bottom, Spacing.xl)
            }
        }
    }
}

private struct TaglineWord: View {
    @ObservedObject private var theme = ThemeManager.shared
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundColor(theme.colors.textSecondary)
    }
}

private struct TaglineSeparator: View {
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        Text(theme.chrome.eyebrowLeader)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(theme.colors.textTertiary)
    }
}

// MARK: - Pattern + Frame Components

private struct GridPatternView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let gridSize: CGFloat = 40
            for x in stride(from: 0, to: size.width, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            for y in stride(from: 0, to: size.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
    }
}

private struct CornerBrackets: View {
    let color: Color
    private let bracketSize: CGFloat = 40
    private let strokeWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            BracketShape(corner: .topLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: bracketSize / 2 + 60)

            BracketShape(corner: .topRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: bracketSize / 2 + 60)

            BracketShape(corner: .bottomLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: geo.size.height - bracketSize / 2 - 120)

            BracketShape(corner: .bottomRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: geo.size.height - bracketSize / 2 - 120)
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

private struct TalkieLogoRibbon: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        HStack(spacing: 4) {
            Text(";)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(chrome.accent)

            Text("Talkie")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(theme.colors.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(chrome.accent, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.colors.background)
                )
        )
        .rotationEffect(.degrees(12))
    }
}

// MARK: - Capture Page

private struct CapturePage: View {
    @State private var isRecordingPulse = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            GridPatternView(color: chrome.edgeSubtle)
                .opacity(0.30)

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Phone illustration on embedded panel
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(chrome.panel)
                        .frame(width: 200, height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .strokeBorder(chrome.panelEdge, lineWidth: 1)
                        )

                    VStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(chrome.panelInkFaint.opacity(0.4), lineWidth: 2)
                                .frame(width: 60, height: 100)

                            Circle()
                                .fill(chrome.panelAccent.opacity(0.20))
                                .frame(width: 40, height: 40)
                                .scaleEffect(isRecordingPulse ? 1.3 : 1.0)
                                .opacity(isRecordingPulse ? 0.1 : 0.3)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundColor(chrome.panelAccent)
                                .shadow(color: chrome.panelAccent.opacity(0.5), radius: chrome.glowRadius)
                        }

                        HStack(spacing: 4) {
                            TalkieStatusDot(diameter: 6, pulses: true, color: chrome.panelAccent)
                            Text("REC")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(chrome.panelAccent)
                        }
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isRecordingPulse = true
                    }
                }

                VStack(spacing: Spacing.sm) {
                    Text("Capture Your Voice")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(theme.colors.textPrimary)

                    Text("Record memos, dictate into any app,\nor let the keyboard type as you speak.\nAll on-device. Always ready.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    FeatureHint(icon: "mic.fill", text: "Voice memos with instant transcription")
                    FeatureHint(icon: "keyboard", text: "Talkie keyboard — dictate anywhere you type")
                    FeatureHint(icon: "waveform", text: "On-device speech recognition, no servers")
                }
                .padding(.top, Spacing.md)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
        }
    }
}

private struct FeatureHint: View {
    let icon: String
    let text: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(theme.chrome.accent)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
        }
    }
}

// MARK: - Sync Page

private enum SyncTooltip: String, CaseIterable {
    case iphone = "iphone"
    case icloud = "icloud"
    case mac = "mac"

    var title: String {
        switch self {
        case .iphone: return "Instant Capture"
        case .icloud: return "Seamless Sync"
        case .mac: return "Desktop Engine"
        }
    }

    var subtitle: String {
        switch self {
        case .iphone: return "LOCAL-FIRST"
        case .icloud: return "E2E ENCRYPTED"
        case .mac: return "AI POWERED"
        }
    }

    var description: String {
        switch self {
        case .iphone: return "Capture audio instantly with zero latency. Recordings are secured locally on your device."
        case .icloud: return "Memos sync via your personal iCloud. No third-party servers—you hold the encryption keys."
        case .mac: return "Your Mac handles AI tasks, transcribing audio and generating summaries in the background."
        }
    }
}

private struct SyncPage: View {
    @State private var animateSync = false
    @State private var showArchitectureDetail = false
    @State private var activeTooltip: SyncTooltip? = nil
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            GridPatternView(color: chrome.edgeSubtle)
                .opacity(0.30)

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Diagram container with overlayed USER OWNED DATA label
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        SyncIconButton(
                            icon: "iphone",
                            label: "iPhone",
                            action: "Capture",
                            isSelected: activeTooltip == .iphone
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                activeTooltip = activeTooltip == .iphone ? nil : .iphone
                            }
                        }

                        SyncArrows(animateSync: animateSync)

                        SyncIconButton(
                            icon: "icloud.fill",
                            label: "iCloud",
                            action: "Sync",
                            isSelected: activeTooltip == .icloud
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                activeTooltip = activeTooltip == .icloud ? nil : .icloud
                            }
                        }

                        SyncArrows(animateSync: animateSync)

                        SyncIconButton(
                            icon: "macbook",
                            label: "Mac",
                            action: "Process",
                            isSelected: activeTooltip == .mac
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                activeTooltip = activeTooltip == .mac ? nil : .mac
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .padding(16)
                .padding(.top, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .foregroundColor(chrome.accent.opacity(0.5))
                )
                .overlay(alignment: .top) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                        Text("USER OWNED DATA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(chrome.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(theme.colors.background)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                            .foregroundColor(chrome.accent.opacity(0.5))
                    )
                    .clipShape(Capsule())
                    .offset(y: -12)
                }
                .padding(.horizontal, Spacing.md)

                if let tooltip = activeTooltip {
                    SyncTooltipCard(tooltip: tooltip) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeTooltip = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    VStack(spacing: Spacing.sm) {
                        Text("The Magic of Sync")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(theme.colors.textPrimary)

                        Text("Record anywhere on your iPhone.\nSync locally, via iCloud, or direct to Mac.\nMac processes with on-device AI.\nAll encrypted, all yours.")
                            .font(.system(size: 14))
                            .foregroundColor(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .transition(.opacity)
                }

                Button(action: { showArchitectureDetail = true }) {
                    HStack(spacing: 6) {
                        Text("SEE HOW IT WORKS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(chrome.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .strokeBorder(chrome.accent.opacity(0.4), lineWidth: 1)
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Works perfectly fine locally without iCloud")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(theme.colors.textTertiary)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animateSync = true
            }
        }
        .fullScreenCover(isPresented: $showArchitectureDetail) {
            ArchitectureWalkthrough()
        }
    }
}

private struct SyncArrows: View {
    let animateSync: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
            Image(systemName: "arrow.left")
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(theme.chrome.accent)
        .opacity(animateSync ? 0.8 : 0.3)
    }
}

private struct SyncIconButton: View {
    let icon: String
    let label: String
    let action: String
    let isSelected: Bool
    let onTap: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? chrome.accent : theme.colors.textPrimary)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? chrome.accent : theme.colors.textTertiary)
                Text(action)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? chrome.accentTint : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SyncTooltipCard: View {
    let tooltip: SyncTooltip
    let onDismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    TalkieStatusDot(diameter: 6)
                    Text(tooltip.subtitle)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(chrome.accent)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.colors.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(chrome.edge.opacity(0.6))
                        .clipShape(Circle())
                }
            }

            Text(tooltip.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(theme.colors.textPrimary)

            Text(tooltip.description)
                .font(.system(size: 12))
                .foregroundColor(theme.colors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(chrome.accent.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Architecture Walkthrough

private struct ArchitectureWalkthrough: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var pulseComplete = false
    @ObservedObject private var theme = ThemeManager.shared
    private let totalSteps = 4

    private let steps: [(title: String, subtitle: String, description: String)] = [
        ("Your Voice", "LOCAL-FIRST CAPTURE", "Capture audio immediately with zero latency. Recordings are secured locally on your device, ensuring you never miss a moment."),
        ("Your Cloud", "END-TO-END ENCRYPTED", "Memos sync silently via your personal iCloud. No third-party servers, no data mining. You hold the only encryption keys."),
        ("Your Workstation", "ORCHESTRATE", "Your Mac acts as the powerhouse—handling heavy AI tasks, transcribing audio, and generating summaries securely in the background."),
        ("Your Data", "PRIVACY BY DESIGN", "Your voice, your devices, your iCloud. No middlemen, no third-party servers. Just a seamless flow from capture to insight—all under your control.")
    ]

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            GridPatternView(color: chrome.edgeSubtle)
                .opacity(0.30)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.colors.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(chrome.edge.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                Spacer().frame(height: 12)

                ArchitectureDiagram(currentStep: currentStep)
                    .padding(.horizontal, Spacing.md)

                Spacer().frame(height: 24)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", currentStep + 1))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(chrome.accent)

                        Text("//")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.colors.textTertiary)

                        Text(steps[currentStep].title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(theme.colors.textPrimary)
                    }

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(chrome.accent)
                            .frame(width: 2, height: 12)

                        Text(steps[currentStep].subtitle)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(theme.colors.textTertiary)
                    }

                    Text(steps[currentStep].description)
                        .font(.system(size: 13))
                        .foregroundColor(theme.colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)

                Spacer().frame(height: 24)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.colors.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .opacity(currentStep > 0 ? 1 : 0)
                    .disabled(currentStep == 0)

                    Spacer()

                    HStack(spacing: 8) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? chrome.accent : chrome.edge)
                                .frame(width: index == currentStep ? 8 : 6, height: index == currentStep ? 8 : 6)
                        }
                    }

                    Spacer()

                    if currentStep < totalSteps - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(chrome.panelInk)
                                .frame(width: 44, height: 44)
                                .background(chrome.accent)
                                .clipShape(Circle())
                                .talkieAccentGlow()
                        }
                    } else {
                        Button(action: { dismiss() }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(chrome.panelInk)
                                .frame(width: 44, height: 44)
                                .background(chrome.accent)
                                .clipShape(Circle())
                                .talkieAccentGlow()
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Spacer().frame(height: 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                if currentStep < totalSteps - 1 {
                    currentStep += 1
                }
            }
        }
        .onChange(of: currentStep) { _, newStep in
            if newStep == totalSteps - 1 {
                pulseComplete = true
            }
        }
    }
}

private struct ArchitectureDiagram: View {
    let currentStep: Int
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        VStack(spacing: 12) {
            UserOwnedDataHeader()

            VStack(spacing: 12) {
                iCloudPanel(isActive: currentStep == 1 || currentStep == 3)

                HStack(spacing: 12) {
                    DevicePanel(
                        icon: "iphone",
                        title: "IPHONE",
                        subtitle: "Capture",
                        steps: [
                            ("Record", "arrow.up"),
                            ("Secure", "lock"),
                            ("Upload", "arrow.up.arrow.down")
                        ],
                        isActive: currentStep == 0 || currentStep == 3
                    )

                    DevicePanel(
                        icon: "macbook",
                        title: "MAC",
                        subtitle: "Orchestrate",
                        steps: [
                            ("Backup", "arrow.down.doc"),
                            ("Automate", "gearshape.2"),
                            ("On-Device AI", "cpu")
                        ],
                        isActive: currentStep == 2 || currentStep == 3
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .foregroundColor(chrome.edge)
            )
        }
    }
}

private struct UserOwnedDataHeader: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
            Text("USER OWNED DATA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
        }
        .foregroundColor(chrome.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .foregroundColor(chrome.accent.opacity(0.5))
        )
    }
}

private struct iCloudPanel: View {
    let isActive: Bool
    @ObservedObject private var theme = ThemeManager.shared

    private var opacity: Double { isActive ? 1.0 : 0.3 }

    var body: some View {
        let chrome = theme.chrome
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "icloud")
                    .font(.system(size: 12, weight: .medium))
                Text("ICLOUD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("–")
                    .foregroundColor(theme.colors.textTertiary)
                Text("Sync")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.colors.textTertiary)
            }
            .foregroundColor(theme.colors.textPrimary)

            HStack(spacing: 16) {
                iCloudProperty(icon: "server.rack", label: "PRIVATE DB")
                iCloudProperty(icon: "key", label: "USER KEYS")
                iCloudProperty(icon: "arrow.triangle.2.circlepath", label: "E2E SYNC")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? chrome.accent.opacity(0.5) : chrome.edge, lineWidth: 1)
        )
        .opacity(opacity)
    }

    private func iCloudProperty(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(theme.chrome.accent)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(theme.colors.textTertiary)
        }
    }
}

private struct DevicePanel: View {
    let icon: String
    let title: String
    let subtitle: String
    let steps: [(label: String, icon: String)]
    let isActive: Bool

    @ObservedObject private var theme = ThemeManager.shared

    private var opacity: Double { isActive ? 1.0 : 0.3 }

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("–")
                    .foregroundColor(theme.colors.textTertiary)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.colors.textTertiary)
            }
            .foregroundColor(theme.colors.textPrimary)

            VStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(number: index + 1, label: step.label, icon: step.icon, isActive: isActive)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? chrome.accent.opacity(0.5) : chrome.edge, lineWidth: 1)
        )
        .opacity(opacity)
    }
}

private struct StepRow: View {
    let number: Int
    let label: String
    let icon: String
    let isActive: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Text("\(number).")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.colors.textTertiary)
                .frame(width: 16, alignment: .leading)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(isActive ? theme.chrome.accent : theme.colors.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.colors.searchBackground.opacity(0.6))
        )
    }
}

// MARK: - Get Started Page

private struct GetStartedPage: View {
    let iCloudStatus: CKAccountStatus
    let onComplete: () -> Void
    var onTryRecord: (() -> Void)? = nil
    @State private var pulseRecord = false

    @State private var showHeader = false
    @State private var statusChecks: [Bool] = [false, false, false, false]
    @State private var showRecordButton = false

    @ObservedObject private var theme = ThemeManager.shared

    private var deviceName: String { UIDevice.current.name }

    private var allChecksComplete: Bool { statusChecks.allSatisfy { $0 } }

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            GridPatternView(color: chrome.edgeSubtle)
                .opacity(0.40)

            VStack(spacing: Spacing.lg) {
                Spacer()

                TalkieEyebrow(text: "System Status", showLeader: false)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : 10)

                // Status panel
                VStack(spacing: Spacing.md) {
                    AnimatedStatusRow(
                        label: "App",
                        value: "Ready",
                        isActive: true,
                        isChecked: statusChecks[0]
                    )
                    AnimatedStatusRow(
                        label: "Storage",
                        value: "Local",
                        isActive: true,
                        isChecked: statusChecks[1]
                    )
                    AnimatedStatusRow(
                        label: "Encryption",
                        value: "On-Device",
                        isActive: true,
                        isChecked: statusChecks[2]
                    )
                    AnimatedStatusRow(
                        label: "iCloud",
                        value: iCloudStatus == .available ? "Connected" : "Offline",
                        isHighlight: true,
                        isActive: iCloudStatus == .available,
                        isChecked: statusChecks[3]
                    )
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(chrome.edge, lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.xl)
                .opacity(showHeader ? 1 : 0)

                // Record preview button
                Button(action: { onTryRecord?() ?? onComplete() }) {
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .stroke(chrome.accentStrong.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 52, height: 52)
                                .scaleEffect(pulseRecord ? 1.35 : 1.0)
                                .opacity(pulseRecord ? 0 : 0.6)
                                .animation(
                                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                    value: pulseRecord
                                )

                            Circle()
                                .fill(chrome.accent)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(chrome.panelInk)
                                )
                                .talkieAccentGlow()
                        }

                        Text("TAP TO TRY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(theme.colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.md)
                .opacity(showRecordButton ? 1 : 0)
                .scaleEffect(showRecordButton ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showRecordButton)

                Spacer()

                if iCloudStatus != .available {
                    Button(action: openSettings) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "icloud.slash")
                                .font(.system(size: 10))
                            Text("Enable iCloud for sync")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(theme.colors.textTertiary)
                    }
                }

                Button(action: onComplete) {
                    HStack(spacing: Spacing.sm) {
                        Text("GET STARTED")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(chrome.panelInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(chrome.accent)
                    .cornerRadius(8)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .opacity(showRecordButton ? 1 : 0)
                .offset(y: showRecordButton ? 0 : 20)

                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                    Text(deviceName)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(theme.colors.textTertiary.opacity(0.6))
                .padding(.top, Spacing.sm)
                .opacity(showRecordButton ? 1 : 0)

                Spacer().frame(height: Spacing.lg)
            }
        }
        .onAppear {
            startStatusAnimation()
        }
    }

    private func startStatusAnimation() {
        withAnimation(.easeOut(duration: 0.4)) {
            showHeader = true
        }

        let checkDelays: [Double] = [0.5, 0.9, 1.3, 1.7]
        for (index, delay) in checkDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    statusChecks[index] = true
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            showRecordButton = true
            pulseRecord = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct AnimatedStatusRow: View {
    let label: String
    let value: String
    var isHighlight: Bool = false
    var isActive: Bool = true
    var isChecked: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        HStack {
            Circle()
                .fill(isChecked ? (isActive ? chrome.accent : theme.colors.textTertiary) : chrome.edge)
                .frame(width: 6, height: 6)
                .animation(.easeOut(duration: 0.3), value: isChecked)
                .shadow(color: isChecked && isActive ? chrome.accentGlow : .clear, radius: chrome.glowRadius)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(theme.colors.textTertiary)

            Spacer()

            ZStack(alignment: .trailing) {
                Text("CHECKING...")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(theme.colors.textTertiary.opacity(0.6))
                    .opacity(isChecked ? 0 : 1)
                    .offset(x: isChecked ? 10 : 0)

                Text(value.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(isHighlight && isActive ? chrome.accent : theme.colors.textSecondary)
                    .opacity(isChecked ? 1 : 0)
                    .offset(x: isChecked ? 0 : -10)
            }
            .animation(.easeOut(duration: 0.3), value: isChecked)
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(hasSeenOnboarding: .constant(false))
}

#Preview("Welcome") {
    WelcomePage()
}

#Preview("Capture") {
    CapturePage()
}

#Preview("Sync") {
    SyncPage()
}

#Preview("Get Started — Connected") {
    GetStartedPage(iCloudStatus: .available, onComplete: {})
}

#Preview("Get Started — No Account") {
    GetStartedPage(iCloudStatus: .noAccount, onComplete: {})
}
