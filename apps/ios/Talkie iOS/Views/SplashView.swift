//
//  SplashView.swift
//  Talkie iOS
//
//  Splash screen shown during app initialization.
//  Brand-first and theme-aware so the handoff into the app feels
//  continuous without reintroducing the older pitch-style launch screen.
//

import SwiftUI

struct SplashView: View {
    private static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")

    @State private var showContent = isScreenshotMode
    @State private var showStatus = isScreenshotMode
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            SplashSurface(chrome: chrome)
                .opacity(showContent ? 1 : 0)

            VStack(spacing: 18) {
                SplashLogo(stroke: chrome.edgeFaint)
                    .scaleEffect(showContent ? 1 : 0.94)

                VStack(spacing: 8) {
                    Text("Talkie")
                        .talkieType(.splashWordmark)
                        .foregroundStyle(theme.colors.textPrimary)

                    HStack(spacing: 8) {
                        TalkieStatusDot(diameter: 5, pulses: true)
                        Text("Preparing workspace")
                            .talkieType(.splashStatus)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .opacity(showStatus ? 1 : 0)
                    .offset(y: showStatus ? 0 : 6)
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Talkie is starting")
        .accessibilityIdentifier("splash.screen")
        .onAppear {
            guard !Self.isScreenshotMode else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.32).delay(0.14)) {
                showStatus = true
            }
        }
    }
}

// MARK: - Splash Components

private struct SplashSurface: View {
    let chrome: ChromeTokens

    var body: some View {
        VStack {
            Rectangle()
                .fill(chrome.edgeSubtle)
                .frame(height: chrome.hairlineWidth)

            Spacer()

            Rectangle()
                .fill(chrome.edgeSubtle)
                .frame(height: chrome.hairlineWidth)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 80)
        .ignoresSafeArea()
    }
}

private struct SplashLogo: View {
    let stroke: Color

    var body: some View {
        Image("TalkieLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

#Preview {
    SplashView()
}
