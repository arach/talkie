//
//  SignInNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — auth landing. Three providers (Apple,
//  Google, Email) + skip-for-now. Donor is SignInView (255 lines)
//  using Clerk; full auth flow lives there.
//

import SwiftUI

struct SignInNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    brand
                        .padding(.top, 48)

                    headline

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)

            providers
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
    }

    private var brand: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("TALKIE")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(3.2)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            Spacer()
            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("Skip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to sync your voice everywhere.")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(theme.colors.textPrimary)
                .lineSpacing(2)
                .padding(.top, 24)

            Text("Memos, dictations, and AI history follow your account across iPhone, iPad, Mac, and Web. End-to-end encrypted.")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var providers: some View {
        VStack(spacing: 10) {
            providerButton(systemImage: "apple.logo", label: "Continue with Apple",
                           isPrimary: true) { /* TODO */ }
            providerButton(systemImage: "g.circle", label: "Continue with Google",
                           isPrimary: false) { /* TODO */ }
            providerButton(systemImage: "envelope", label: "Continue with email",
                           isPrimary: false) { /* TODO */ }

            Text("By continuing you accept our terms · privacy")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.top, 6)
        }
    }

    private func providerButton(systemImage: String, label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isPrimary
                ? theme.colors.cardBackground
                : theme.colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(isPrimary ? theme.colors.textPrimary : Color.clear)
                    .overlay(Capsule().strokeBorder(
                        isPrimary ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    ))
            )
        }
        .buttonStyle(.plain)
    }
}
