//
//  SplashView.swift
//  Talkie iOS
//
//  Splash screen shown during app initialization.
//  Theme-aware: adopts the active theme's canvas + chrome (cream/amber for
//  scope, jet/blue for midnight, gunmetal/orange for tactical, frost/indigo
//  for ghost) so the handoff into the app feels continuous.
//

import SwiftUI

struct SplashView: View {
    private static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")

    @State private var showContent = isScreenshotMode
    @State private var showTagline = isScreenshotMode
    @ObservedObject private var theme = ThemeManager.shared

    private var taglineSegments: [String] { ["Record", "Dictate", "Transcribe"] }

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            SplashGridPattern(color: chrome.edgeSubtle)
                .opacity(0.6)

            SplashCornerBrackets(color: chrome.edge)

            VStack(spacing: 24) {
                Spacer()
                Spacer()

                SplashLogo(stroke: chrome.edge)
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.8)

                // Main headline — VOICE + AI
                HStack(spacing: 8) {
                    Text("VOICE")
                        .font(.system(size: 36, weight: .black, design: .default))
                        .foregroundColor(theme.colors.textPrimary)

                    Text("+ AI")
                        .font(.system(size: 36, weight: .black, design: .default))
                        .foregroundColor(chrome.accent)
                        .talkieAccentGlow()
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Tagline — theme-aware separator + status dot
                HStack(spacing: 10) {
                    TalkieStatusDot(diameter: 5, pulses: true)
                    ForEach(Array(taglineSegments.enumerated()), id: \.offset) { index, segment in
                        Text(segment.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(theme.colors.textSecondary)
                        if index < taglineSegments.count - 1 {
                            Text(chrome.eyebrowLeader)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.colors.textTertiary)
                        }
                    }
                }
                .opacity(showTagline ? 1 : 0)
                .offset(y: showTagline ? 0 : 10)

                Spacer()
                Spacer()

                // Footer
                VStack(spacing: 4) {
                    Text("usetalkie.com")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.colors.textTertiary)

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.colors.textTertiary.opacity(0.7))
                }
                .opacity(showTagline ? 1 : 0)
                .padding(.bottom, 60)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("splash.screen")
        .onAppear {
            guard !Self.isScreenshotMode else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                showTagline = true
            }
        }
    }
}

// MARK: - Splash Components

private struct SplashGridPattern: View {
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

private struct SplashCornerBrackets: View {
    let color: Color
    private let bracketSize: CGFloat = 40
    private let strokeWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            SplashBracketShape(corner: .topLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: bracketSize / 2 + 60)

            SplashBracketShape(corner: .topRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: bracketSize / 2 + 60)

            SplashBracketShape(corner: .bottomLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: geo.size.height - bracketSize / 2 - 120)

            SplashBracketShape(corner: .bottomRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: geo.size.height - bracketSize / 2 - 120)
        }
    }
}

private enum SplashBracketCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

private struct SplashBracketShape: Shape {
    let corner: SplashBracketCorner

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

private struct SplashLogo: View {
    let stroke: Color

    var body: some View {
        Image("TalkieLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

#Preview {
    SplashView()
}
