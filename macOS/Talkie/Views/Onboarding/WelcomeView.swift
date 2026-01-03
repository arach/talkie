//
//  WelcomeView.swift
//  Talkie macOS
//
//  Welcome screen - tactical style ported from iOS
//  Shows ";) Talkie" logo and value proposition
//

import SwiftUI

struct WelcomeView: View {
    let onNext: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            // Dark tactical background
            colors.background
                .ignoresSafeArea()

            // Grid pattern overlay
            GridPatternView(lineColor: Color(hex: "1A1A1A"))
                .opacity(0.4)

            // Corner brackets
            CornerBrackets(colors: colors)

            // Standard layout structure
            VStack(spacing: 0) {
                // HEADER ZONE (48px) - No icon on welcome, clean presentation
                Spacer()
                    .frame(height: OnboardingLayout.headerHeight)

                // CONTENT ZONE (flexible)
                ScrollView {
                    VStack(alignment: .center, spacing: Spacing.lg) {
                        Spacer(minLength: 20)

                        // ";) Talkie" logo - centered above headline
                        TalkieLogo(colors: colors)

                        // Main headline
                        VStack(spacing: 0) {
                            Text("VOICE MEMOS")
                                .font(.system(size: 36, weight: .black, design: .default))
                                .tracking(-1)
                                .foregroundColor(colors.textPrimary)

                            HStack(spacing: 8) {
                                Text("+")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(colors.textTertiary.opacity(0.5))

                                Text("AI.")
                                    .font(.system(size: 36, weight: .black))
                                    .foregroundColor(colors.accent)
                            }
                        }

                        // Tagline
                        VStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                Text("CAPTURE ANYWHERE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(colors.textSecondary)

                                Text("|")
                                    .foregroundColor(colors.textTertiary.opacity(0.5))

                                Text("PROCESS ON-DEVICE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(colors.textSecondary)
                            }

                            // iCloud sync line
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(colors.textTertiary)

                                Text("synced via")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)

                                Text("your")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(colors.textSecondary)

                                Text("iCloud")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)

                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(colors.textTertiary)
                            }
                        }
                        .padding(.top, Spacing.md)

                        Spacer(minLength: 20)

                        // Footer info
                        VStack(spacing: 4) {
                            Text("usetalkie.com")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(colors.textTertiary.opacity(0.7))

                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                                Text("v\(version)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(colors.textTertiary.opacity(0.4))
                            }
                        }
                    }
                    .padding(.top, OnboardingLayout.contentTopPadding)
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)

                // FOOTER ZONE (48px) - Button
                OnboardingCTAButton(
                    colors: colors,
                    title: "GET STARTED",
                    icon: "arrow.right",
                    action: onNext
                )
                .frame(height: OnboardingLayout.buttonHeight)
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
            }
        }
    }
}

// MARK: - Corner Brackets

private struct CornerBrackets: View {
    let colors: OnboardingColors
    private let bracketSize: CGFloat = 40
    private let strokeWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            // Top-left
            BracketShape(corner: .topLeft)
                .stroke(colors.border, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: bracketSize / 2 + 60)

            // Top-right
            BracketShape(corner: .topRight)
                .stroke(colors.border, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: bracketSize / 2 + 60)

            // Bottom-left
            BracketShape(corner: .bottomLeft)
                .stroke(colors.border, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: geo.size.height - bracketSize / 2 - 120)

            // Bottom-right
            BracketShape(corner: .bottomRight)
                .stroke(colors.border, lineWidth: strokeWidth)
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
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(colors.accent, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(colors.background)
                )
        )
        .rotationEffect(.degrees(-3)) // Slight tilt for character
    }
}

#Preview("Light") {
    WelcomeView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WelcomeView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
