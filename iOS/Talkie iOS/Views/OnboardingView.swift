//
//  OnboardingView.swift
//  Talkie iOS
//
//  First-launch onboarding experience
//

import SwiftUI
import CloudKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasSeenOnboarding: Bool

    @State private var currentPage = 0
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background adapts per page (Welcome & GetStarted are dark, middle pages are light)
            Group {
                if currentPage == 0 || currentPage == 3 {
                    Color(hex: "0A0A0A")
                } else {
                    Color.surfacePrimary
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            VStack(spacing: 0) {
                // Skip button - adapts color based on page (dark pages: 0, 3)
                let isDarkPage = currentPage == 0 || currentPage == 3
                HStack {
                    Spacer()
                    Button(action: completeOnboarding) {
                        Text("SKIP")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(isDarkPage ? Color(hex: "6A6A6A") : .textTertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // Page content
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    CapturePage()
                        .tag(1)

                    SyncPage()
                        .tag(2)

                    GetStartedPage(iCloudStatus: iCloudStatus, onComplete: completeOnboarding)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Custom page indicator + navigation
                let isDarkNavPage = currentPage == 0 || currentPage == 3
                let accentGreen = Color(hex: "22C55E")
                HStack(spacing: Spacing.lg) {
                    // Back button (hidden on first page)
                    Button(action: { currentPage -= 1 }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isDarkNavPage ? Color(hex: "6A6A6A") : .textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .opacity(currentPage > 0 ? 1 : 0)
                    .disabled(currentPage == 0)

                    Spacer()

                    // Page dots - green accent throughout
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage
                                    ? accentGreen
                                    : (isDarkNavPage ? Color(hex: "3A3A3A") : Color.textTertiary.opacity(0.3)))
                                .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    Spacer()

                    // Next/Done button - green throughout
                    Button(action: {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        Image(systemName: currentPage < totalPages - 1 ? "chevron.right" : "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isDarkNavPage ? Color(hex: "0A0A0A") : .white)
                            .frame(width: 44, height: 44)
                            .background(accentGreen)
                            .clipShape(Circle())
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
        CKContainer(identifier: "iCloud.com.jdi.talkie").accountStatus { status, _ in
            DispatchQueue.main.async {
                self.iCloudStatus = status
            }
        }
    }
}

// MARK: - Welcome Page (OG Image Style)

private struct WelcomePage: View {
    var body: some View {
        ZStack {
            // Dark tactical background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Grid pattern overlay
            GridPatternView()
                .opacity(0.4)

            // Corner brackets
            CornerBrackets()

            // Content
            VStack(spacing: Spacing.lg) {
                Spacer()
                Spacer()

                // ";) Talkie" logo - centered above headline
                TalkieLogo()
                    .padding(.bottom, Spacing.lg)

                // Main headline
                VStack(spacing: 0) {
                    Text("VOICE MEMOS")
                        .font(.system(size: 36, weight: .black, design: .default))
                        .tracking(-1)
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("+")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(hex: "4A4A4A"))

                        Text("AI.")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(Color(hex: "22C55E"))
                    }
                }

                // Tagline
                VStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text("CAPTURE ON iPHONE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "9A9A9A"))

                        Text("|")
                            .foregroundColor(Color(hex: "4A4A4A"))

                        Text("PROCESS ON MAC")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "9A9A9A"))
                    }

                    // iCloud sync line
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "6A6A6A"))

                        Text("synced via")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "6A6A6A"))

                        Text("your")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "9A9A9A"))

                        Text("iCloud")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "6A6A6A"))

                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "6A6A6A"))
                    }
                }
                .padding(.top, Spacing.md)

                Spacer()
                Spacer()

                // Footer - just website
                Text("usetalkie.com")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "5A5A5A"))
                    .padding(.bottom, Spacing.xl)
            }
        }
    }
}

// MARK: - Tactical UI Components

private struct GridPatternView: View {
    var body: some View {
        Canvas { context, size in
            let gridSize: CGFloat = 40
            let lineColor = Color(hex: "1A1A1A")

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

private struct CornerBrackets: View {
    private let bracketSize: CGFloat = 40
    private let strokeWidth: CGFloat = 2
    private let color = Color(hex: "3A3A3A")

    var body: some View {
        GeometryReader { geo in
            // Top-left
            BracketShape(corner: .topLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: bracketSize / 2 + 60)

            // Top-right
            BracketShape(corner: .topRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: bracketSize / 2 + 60)

            // Bottom-left
            BracketShape(corner: .bottomLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: geo.size.height - bracketSize / 2 - 120)

            // Bottom-right
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

private struct TalkieLogo: View {
    var body: some View {
        HStack(spacing: 4) {
            Text(";)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "22C55E"))

            Text("Talkie")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(hex: "22C55E"), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "0A0A0A"))
                )
        )
        .rotationEffect(.degrees(-3)) // Slight tilt for character
    }
}

// MARK: - Capture Page

private struct CapturePage: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Illustration
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.surfaceSecondary)
                    .frame(width: 200, height: 160)

                VStack(spacing: Spacing.md) {
                    // Phone icon with mic
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.textTertiary.opacity(0.5), lineWidth: 2)
                            .frame(width: 60, height: 100)

                        Circle()
                            .fill(Color.recording.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.recording)
                    }

                    // Recording indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.recording)
                            .frame(width: 6, height: 6)
                        Text("REC")
                            .font(.techLabelSmall)
                            .foregroundColor(.recording)
                    }
                }
            }

            VStack(spacing: Spacing.sm) {
                Text("Capture Anywhere")
                    .font(.displaySmall)
                    .foregroundColor(.textPrimary)

                Text("Record voice memos instantly.\nWorks offline, always ready.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Sync Page (iCloud Architecture)

private struct SyncPage: View {
    @State private var animateSync = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Architecture diagram - compact and aligned
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.surfaceSecondary)
                    .frame(width: 280, height: 140)

                VStack(spacing: Spacing.sm) {
                    // Icons row
                    HStack(spacing: 0) {
                        Image(systemName: "iphone")
                            .font(.system(size: 28))
                            .frame(width: 60)

                        // Left arrows
                        VStack(spacing: 1) {
                            Image(systemName: "arrow.right")
                            Image(systemName: "arrow.left")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .opacity(animateSync ? 0.6 : 0.2)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: animateSync)
                        .frame(width: 30)

                        Image(systemName: "icloud.fill")
                            .font(.system(size: 28))
                            .frame(width: 60)

                        // Right arrows
                        VStack(spacing: 1) {
                            Image(systemName: "arrow.right")
                            Image(systemName: "arrow.left")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .opacity(animateSync ? 0.6 : 0.2)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: animateSync)
                        .frame(width: 30)

                        Image(systemName: "macbook")
                            .font(.system(size: 28))
                            .frame(width: 60)
                    }
                    .foregroundColor(.textPrimary)

                    // Labels row - perfectly aligned
                    HStack(spacing: 0) {
                        Text("iPhone")
                            .frame(width: 60)

                        Spacer()
                            .frame(width: 30)

                        Text("iCloud")
                            .frame(width: 60)

                        Spacer()
                            .frame(width: 30)

                        Text("Mac")
                            .frame(width: 60)
                    }
                    .font(.techLabelSmall)
                    .foregroundColor(.textSecondary)

                    // Role labels row
                    HStack(spacing: 0) {
                        Text("Capture")
                            .frame(width: 60)

                        Spacer()
                            .frame(width: 30)

                        Text("Sync")
                            .frame(width: 60)

                        Spacer()
                            .frame(width: 30)

                        Text("Process")
                            .frame(width: 60)
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.textTertiary)
                }
            }
            .onAppear { animateSync = true }

            VStack(spacing: Spacing.sm) {
                Text("The Magic & Security of iCloud")
                    .font(.displaySmall)
                    .foregroundColor(.textPrimary)

                Text("Your data syncs through your iCloud.\niOS captures, Mac processes with\nAI transcription and workflows.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Note about working without iCloud
            HStack(spacing: Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("Works perfectly fine locally without iCloud")
                    .font(.labelMedium)
            }
            .foregroundColor(.textTertiary)
            .padding(.top, Spacing.sm)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Get Started Page (Tactical Style with Animation)

private struct GetStartedPage: View {
    let iCloudStatus: CKAccountStatus
    let onComplete: () -> Void

    // Animation states
    @State private var showApp = false
    @State private var showStorage = false
    @State private var showICloud = false
    @State private var showReady = false
    @State private var buttonSpinComplete = false

    var body: some View {
        ZStack {
            // Dark tactical background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Grid pattern (subtle)
            GridPatternView()
                .opacity(0.2)

            VStack(spacing: Spacing.lg) {
                Spacer()

                // System status header
                Text("SYSTEM CHECK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(hex: "6A6A6A"))

                // Status panel with animated rows
                VStack(spacing: Spacing.md) {
                    if showApp {
                        StatusRow(label: "App", value: "Ready", isHighlight: false)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    if showStorage {
                        StatusRow(label: "Storage", value: "Local", isHighlight: false)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    if showICloud {
                        StatusRow(
                            label: "iCloud",
                            value: iCloudStatus == .available ? "Connected" : "Offline",
                            isHighlight: true,
                            isActive: iCloudStatus == .available
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "111111"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: 100)

                // Message - appears after iCloud check
                if showReady {
                    VStack(spacing: Spacing.sm) {
                        if iCloudStatus == .available {
                            Text("All systems go.")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "22C55E"))
                        } else {
                            Text("Running locally.")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "9A9A9A"))

                            Button(action: openSettings) {
                                HStack(spacing: Spacing.xs) {
                                    Text("Enable iCloud Sync")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(Color(hex: "22C55E"))
                            }
                            .padding(.top, Spacing.xxs)
                        }
                    }
                    .transition(.opacity)
                    .padding(.top, Spacing.sm)
                }

                Spacer()

                // Initialize button - appears when ready
                if showReady {
                    Button(action: onComplete) {
                        HStack(spacing: Spacing.sm) {
                            Text("GET STARTED")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(2)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .rotationEffect(.degrees(buttonSpinComplete ? 0 : 360))
                        }
                        .foregroundColor(Color(hex: "0A0A0A"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color(hex: "22C55E"))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
                    .frame(height: Spacing.xl)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Reset states
        showApp = false
        showStorage = false
        showICloud = false
        showReady = false
        buttonSpinComplete = false

        // Staggered animation
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            showApp = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
            showStorage = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(2.0)) {
            showICloud = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(3.0)) {
            showReady = true
        }
        // Arrow spin after button appears
        withAnimation(.easeInOut(duration: 0.5).delay(3.3)) {
            buttonSpinComplete = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String
    var isHighlight: Bool = false
    var isActive: Bool = true

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(isActive ? Color(hex: "22C55E") : Color(hex: "6A6A6A"))
                .frame(width: 6, height: 6)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(Color(hex: "6A6A6A"))

            Spacer()

            Text(value.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(isHighlight && isActive ? Color(hex: "22C55E") : Color(hex: "9A9A9A"))
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

#Preview("Get Started - Connected") {
    GetStartedPage(iCloudStatus: .available, onComplete: {})
}

#Preview("Get Started - No Account") {
    GetStartedPage(iCloudStatus: .noAccount, onComplete: {})
}
