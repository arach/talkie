//
//  OnboardingView.swift
//  Talkie iOS
//
//  First-launch onboarding experience
//

import SwiftUI
import CloudKit
import UIKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasSeenOnboarding: Bool

    @State private var currentPage = 0
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Dark tactical background for all pages
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: completeOnboarding) {
                        Text("SKIP")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(Color(hex: "6A6A6A"))
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
                let accentGreen = Color(hex: "22C55E")
                HStack(spacing: Spacing.lg) {
                    // Back button (hidden on first page)
                    Button(action: { currentPage -= 1 }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "6A6A6A"))
                            .frame(width: 44, height: 44)
                    }
                    .opacity(currentPage > 0 ? 1 : 0)
                    .disabled(currentPage == 0)

                    Spacer()

                    // Page dots - green accent throughout
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? accentGreen : Color(hex: "3A3A3A"))
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
                            .foregroundColor(Color(hex: "0A0A0A"))
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

                // Footer
                VStack(spacing: 4) {
                    Text("usetalkie.com")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "5A5A5A"))

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "3A3A3A"))
                }
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
    @State private var isRecordingPulse = false

    var body: some View {
        ZStack {
            // Dark background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Subtle grid
            GridPatternView()
                .opacity(0.15)

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Illustration - dark themed
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color(hex: "151515"))
                        .frame(width: 200, height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1)
                        )

                    VStack(spacing: Spacing.md) {
                        // Phone icon with mic
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "3A3A3A"), lineWidth: 2)
                                .frame(width: 60, height: 100)

                            // Pulsing glow
                            Circle()
                                .fill(Color(hex: "22C55E").opacity(0.2))
                                .frame(width: 40, height: 40)
                                .scaleEffect(isRecordingPulse ? 1.3 : 1.0)
                                .opacity(isRecordingPulse ? 0.1 : 0.3)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "22C55E"))
                        }

                        // Recording indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "22C55E"))
                                .frame(width: 6, height: 6)
                                .scaleEffect(isRecordingPulse ? 1.2 : 0.8)
                            Text("REC")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "22C55E"))
                        }
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isRecordingPulse = true
                    }
                }

                VStack(spacing: Spacing.sm) {
                    Text("Capture Anywhere")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("Record voice memos instantly.\nWorks offline, always ready.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "8A8A8A"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
        }
    }
}

// MARK: - Sync Page (Simple with optional deep dive)

private struct SyncPage: View {
    @State private var animateSync = false
    @State private var showArchitectureDetail = false

    var body: some View {
        ZStack {
            // Dark background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Subtle grid
            GridPatternView()
                .opacity(0.15)

            VStack(spacing: Spacing.lg) {
                Spacer()

                // USER OWNED DATA header
                UserOwnedDataHeader()

                // Simple diagram container
                VStack(spacing: 12) {
                    // Icons row with arrows
                    HStack(spacing: 0) {
                        // iPhone
                        VStack(spacing: 6) {
                            Image(systemName: "iphone")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            Text("iPhone")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(hex: "6A6A6A"))
                            Text("Capture")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "22C55E"))
                        }
                        .frame(maxWidth: .infinity)

                        // Arrows left
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.right")
                            Image(systemName: "arrow.left")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "22C55E"))
                        .opacity(animateSync ? 0.8 : 0.3)

                        // iCloud
                        VStack(spacing: 6) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            Text("iCloud")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(hex: "6A6A6A"))
                            Text("Sync")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "22C55E"))
                        }
                        .frame(maxWidth: .infinity)

                        // Arrows right
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.right")
                            Image(systemName: "arrow.left")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "22C55E"))
                        .opacity(animateSync ? 0.8 : 0.3)

                        // Mac
                        VStack(spacing: 6) {
                            Image(systemName: "macbook")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            Text("Mac")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(hex: "6A6A6A"))
                            Text("Process")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "22C55E"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 20)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "0D0D0D"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .foregroundColor(Color(hex: "2A2A2A"))
                )
                .padding(.horizontal, Spacing.md)

                // Title and description
                VStack(spacing: Spacing.sm) {
                    Text("The Magic of Sync")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("Your data syncs through your iCloud.\niOS captures, Mac processes with AI—\nall encrypted, all yours.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "8A8A8A"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // "How it works" button
                Button(action: { showArchitectureDetail = true }) {
                    HStack(spacing: 6) {
                        Text("SEE HOW IT WORKS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "22C55E"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .strokeBorder(Color(hex: "22C55E").opacity(0.4), lineWidth: 1)
                    )
                }

                // Note
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Works perfectly fine locally without iCloud")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(Color(hex: "4A4A4A"))

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

// MARK: - Architecture Walkthrough (Full Screen Detail View)

private struct ArchitectureWalkthrough: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    private let totalSteps = 4

    private let steps: [(title: String, subtitle: String, description: String)] = [
        ("Instant Capture", "LOCAL-FIRST SPEED", "Capture audio immediately with zero latency. Recordings are secured locally on your device, ensuring you never miss a moment."),
        ("Seamless Sync", "END-TO-END ENCRYPTED", "Memos sync silently via your personal iCloud. No third-party servers, no data mining. You hold the only encryption keys."),
        ("Desktop Engine", "INTELLIGENT PROCESSING", "Your Mac acts as the powerhouse—handling heavy AI tasks, transcribing audio, and generating summaries securely in the background."),
        ("The Full Picture", "PRIVACY BY DESIGN", "Your voice, your devices, your iCloud. No middlemen, no third-party servers. Just a seamless flow from capture to insight—all under your control.")
    ]

    var body: some View {
        ZStack {
            // Dark background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Subtle grid
            GridPatternView()
                .opacity(0.15)

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "6A6A6A"))
                            .frame(width: 32, height: 32)
                            .background(Color(hex: "1A1A1A"))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                Spacer()
                    .frame(height: 12)

                // Architecture Diagram
                ArchitectureDiagram(currentStep: currentStep)
                    .padding(.horizontal, Spacing.md)

                Spacer()
                    .frame(height: 24)

                // Step info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", currentStep + 1))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "22C55E"))

                        Text("//")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "3A3A3A"))

                        Text(steps[currentStep].title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color(hex: "22C55E"))
                            .frame(width: 2, height: 12)

                        Text(steps[currentStep].subtitle)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Color(hex: "6A6A6A"))
                    }

                    Text(steps[currentStep].description)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8A8A8A"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)

                Spacer()
                    .frame(height: 24)

                // Step dots + action
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color(hex: "22C55E") : Color(hex: "3A3A3A"))
                            .frame(width: index == currentStep ? 8 : 6, height: index == currentStep ? 8 : 6)
                    }

                    Spacer()

                    if currentStep < totalSteps - 1 {
                        Text("TAP TO CONTINUE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "4A4A4A"))
                    } else {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 4) {
                                Text("DONE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "22C55E"))
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Spacer()
                    .frame(height: 40)
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
    }
}

// MARK: - Architecture Diagram

private struct ArchitectureDiagram: View {
    let currentStep: Int

    private let accentGreen = Color(hex: "22C55E")
    private let dimColor = Color(hex: "3A3A3A")
    private let bgColor = Color(hex: "111111")

    var body: some View {
        VStack(spacing: 12) {
            // USER OWNED DATA header
            UserOwnedDataHeader()

            // Main container with dashed border
            VStack(spacing: 12) {
                // iCloud panel
                iCloudPanel(isActive: currentStep == 1 || currentStep == 3)

                // Device panels row
                HStack(spacing: 12) {
                    // iPhone panel
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

                    // Mac panel
                    DevicePanel(
                        icon: "macbook",
                        title: "MAC",
                        subtitle: "Orchestrate",
                        steps: [
                            ("Download", "arrow.down"),
                            ("Privacy", "lock"),
                            ("Think", "sparkles")
                        ],
                        isActive: currentStep == 2 || currentStep == 3
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "0D0D0D"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .foregroundColor(Color(hex: "2A2A2A"))
            )
        }
    }
}

// MARK: - User Owned Data Header

private struct UserOwnedDataHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
            Text("USER OWNED DATA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
        }
        .foregroundColor(Color(hex: "22C55E"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .foregroundColor(Color(hex: "22C55E").opacity(0.5))
        )
    }
}

// MARK: - iCloud Panel

private struct iCloudPanel: View {
    let isActive: Bool

    private var opacity: Double { isActive ? 1.0 : 0.3 }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "icloud")
                    .font(.system(size: 12, weight: .medium))
                Text("ICLOUD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("–")
                    .foregroundColor(Color(hex: "3A3A3A"))
                Text("Sync")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "6A6A6A"))
            }
            .foregroundColor(.white)

            // Properties row
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
                .fill(Color(hex: "151515"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: isActive ? "22C55E" : "2A2A2A").opacity(isActive ? 0.5 : 1), lineWidth: 1)
        )
        .opacity(opacity)
    }

    private func iCloudProperty(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(Color(hex: "22C55E"))
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "6A6A6A"))
        }
    }
}

// MARK: - Device Panel

private struct DevicePanel: View {
    let icon: String
    let title: String
    let subtitle: String
    let steps: [(label: String, icon: String)]
    let isActive: Bool

    private var opacity: Double { isActive ? 1.0 : 0.3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("–")
                    .foregroundColor(Color(hex: "3A3A3A"))
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "6A6A6A"))
            }
            .foregroundColor(.white)

            // Steps
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
                .fill(Color(hex: "151515"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: isActive ? "22C55E" : "2A2A2A").opacity(isActive ? 0.5 : 1), lineWidth: 1)
        )
        .opacity(opacity)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let label: String
    let icon: String
    let isActive: Bool

    var body: some View {
        HStack {
            Text("\(number).")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "6A6A6A"))
                .frame(width: 16, alignment: .leading)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(isActive ? Color(hex: "22C55E") : Color(hex: "4A4A4A"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "1A1A1A"))
        )
    }
}

// MARK: - Get Started Page (Tactical Style)

private struct GetStartedPage: View {
    let iCloudStatus: CKAccountStatus
    let onComplete: () -> Void
    @State private var pulseRecord = false

    private var deviceName: String {
        UIDevice.current.name
    }

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
                Text("SYSTEM STATUS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(hex: "6A6A6A"))

                // Status panel
                VStack(spacing: Spacing.md) {
                    StatusRow(label: "App", value: "Ready", isActive: true)
                    StatusRow(label: "Storage", value: "Local", isActive: true)
                    StatusRow(label: "Encryption", value: "On-Device", isActive: true)
                    StatusRow(
                        label: "iCloud",
                        value: iCloudStatus == .available ? "Connected" : "Offline",
                        isHighlight: true,
                        isActive: iCloudStatus == .available
                    )
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

                // Record button preview - tap to complete onboarding
                Button(action: onComplete) {
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            // Subtle pulse ring - green accent
                            Circle()
                                .stroke(Color(hex: "22C55E").opacity(0.5), lineWidth: 2)
                                .frame(width: 52, height: 52)
                                .scaleEffect(pulseRecord ? 1.5 : 1.0)
                                .opacity(pulseRecord ? 0 : 0.8)

                            // Main button
                            Circle()
                                .fill(Color(hex: "22C55E"))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                )
                        }

                        Text("TAP TO TRY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Color(hex: "6A6A6A"))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.md)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        pulseRecord = true
                    }
                }

                Spacer()

                // iCloud note if not connected
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
                        .foregroundColor(Color(hex: "6A6A6A"))
                    }
                }

                // Get started button
                Button(action: onComplete) {
                    HStack(spacing: Spacing.sm) {
                        Text("GET STARTED")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "0A0A0A"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Color(hex: "22C55E"))
                    .cornerRadius(8)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)

                // Device identifier
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                    Text(deviceName)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(Color(hex: "3A3A3A"))
                .padding(.top, Spacing.sm)

                Spacer()
                    .frame(height: Spacing.lg)
            }
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
        .preferredColorScheme(.dark)
}

#Preview("Sync - Architecture") {
    SyncPage()
        .preferredColorScheme(.dark)
}

#Preview("Get Started - Connected") {
    GetStartedPage(iCloudStatus: .available, onComplete: {})
}

#Preview("Get Started - No Account") {
    GetStartedPage(iCloudStatus: .noAccount, onComplete: {})
}
