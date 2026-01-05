//
//  SplashView.swift
//  Talkie iOS
//
//  Splash screen shown during app initialization
//  Uses the same tactical design language as onboarding
//

import SwiftUI

struct SplashView: View {
    @State private var showContent = false
    @State private var showTagline = false

    var body: some View {
        ZStack {
            // Dark tactical background
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            // Grid pattern overlay
            SplashGridPattern()
                .opacity(0.4)

            // Corner brackets
            SplashCornerBrackets()

            // Content
            VStack(spacing: 24) {
                Spacer()
                Spacer()

                // ";) Talkie" logo badge
                SplashLogo()
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.8)

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
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Tagline
                HStack(spacing: 8) {
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
                .opacity(showTagline ? 1 : 0)
                .offset(y: showTagline ? 0 : 10)

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
                .opacity(showTagline ? 1 : 0)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
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

private struct SplashCornerBrackets: View {
    private let bracketSize: CGFloat = 40
    private let strokeWidth: CGFloat = 2
    private let color = Color(hex: "3A3A3A")

    var body: some View {
        GeometryReader { geo in
            // Top-left
            SplashBracketShape(corner: .topLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: bracketSize / 2 + 60)

            // Top-right
            SplashBracketShape(corner: .topRight)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: geo.size.width - bracketSize / 2 - 20, y: bracketSize / 2 + 60)

            // Bottom-left
            SplashBracketShape(corner: .bottomLeft)
                .stroke(color, lineWidth: strokeWidth)
                .frame(width: bracketSize, height: bracketSize)
                .position(x: bracketSize / 2 + 20, y: geo.size.height - bracketSize / 2 - 120)

            // Bottom-right
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
    var body: some View {
        HStack(spacing: 4) {
            Text(";)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "22C55E"))

            Text("Talkie")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(hex: "22C55E"), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "0A0A0A"))
                )
        )
        .rotationEffect(.degrees(-3))
    }
}

#Preview {
    SplashView()
}
