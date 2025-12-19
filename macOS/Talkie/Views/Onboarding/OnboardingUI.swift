//
//  OnboardingUI.swift
//  Talkie macOS
//
//  Shared UI components for onboarding flow
//  Ported from TalkieLive onboarding with Talkie-specific adaptations
//

import SwiftUI

// MARK: - Onboarding Colors (Light/Dark Aware)

struct OnboardingColors {
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

// MARK: - Color Hex Initializer

extension Color {
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

// MARK: - Grid Pattern

struct GridPatternView: View {
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

// MARK: - Onboarding CTA Button

struct OnboardingCTAButton: View {
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

// MARK: - Onboarding Step Layout

struct OnboardingStepLayout<Illustration: View, Content: View, CTA: View>: View {
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
        VStack(spacing: 0) {
            // HEADER ZONE (48px) - Icon only (scaled down to fit)
            HStack {
                Spacer()
                illustration()
                    .scaleEffect(0.5) // Scale down large illustrations to fit header
                Spacer()
            }
            .frame(height: OnboardingLayout.headerHeight)

            // CONTENT ZONE (flexible)
            ScrollView {
                VStack(alignment: .center, spacing: Spacing.lg) {
                    // Title
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

                    // Content
                    content()
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, OnboardingLayout.contentTopPadding)
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            // FOOTER ZONE (48px) - Button
            HStack {
                Spacer()
                cta()
            }
            .frame(height: OnboardingLayout.buttonHeight)
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
        }
    }
}

// MARK: - Window Accessor (for Cmd+Q support in sheet)

struct WindowAccessor: NSViewRepresentable {
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
