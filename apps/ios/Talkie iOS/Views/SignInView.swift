//
//  SignInView.swift
//  Talkie iOS
//
//  Account setup — shown contextually from Settings / Mac Sync.
//  Theme-aware: adopts the active theme's canvas + chrome.
//

import SwiftUI
import TalkieMobileKit

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showInfo = false
    @ObservedObject private var theme = ThemeManager.shared

    private var authManager: AuthManager { AuthManager.shared }

    var body: some View {
        let chrome = theme.chrome

        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.colors.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(chrome.edge.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Spacing.md)
                    .padding(.top, Spacing.sm)
                }

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .stroke(theme.colors.success.opacity(0.3), lineWidth: 1)
                        .frame(width: 88, height: 88)

                    Image(systemName: "link.circle")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundColor(theme.colors.success)
                        .shadow(color: theme.colors.success.opacity(0.3), radius: chrome.glowRadius)
                }
                .padding(.bottom, Spacing.lg)

                // Eyebrow + headline
                TalkieEyebrow(text: "Connect Your Devices", showLeader: false)
                    .padding(.bottom, Spacing.xs)

                Text("Sync across iPhone and Mac")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .padding(.bottom, Spacing.sm)

                // Value prop
                Text("Create a free account to sync memos\nbetween your iPhone and Mac.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, Spacing.md)

                // Info disclosure
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showInfo.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .light))
                        Text("What's included?")
                            .font(.system(size: 13, weight: .light))
                        Image(systemName: showInfo ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .light))
                    }
                    .foregroundColor(theme.colors.textTertiary)
                }
                .padding(.bottom, showInfo ? Spacing.sm : Spacing.xxl)

                if showInfo {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        infoRow(icon: "checkmark.circle", text: "Completely free — no payment required")
                        infoRow(icon: "arrow.triangle.2.circlepath", text: "Memos sync between iPhone and Mac")
                        infoRow(icon: "bolt", text: "Cloud transcription and AI features")
                        infoRow(icon: "lock.shield", text: "We never listen to your recordings")
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.bottom, Spacing.xxl)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Auth steps progress
                if !authManager.authSteps.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Array(authManager.authSteps.enumerated()), id: \.element.id) { index, step in
                            HStack(spacing: Spacing.sm) {
                                TalkieChannelLabel(code: String(format: "S%02d", index + 1), isActive: step.status == .inProgress || step.status == .completed)

                                stepIcon(for: step.status)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(stepColor(for: step.status))

                                    if let detail = step.detail {
                                        Text(detail)
                                            .font(.system(size: 11, weight: .light))
                                            .foregroundColor(theme.colors.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.bottom, Spacing.xl)
                }

                // Error state
                if let errorMessage {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundColor(.recording)

                        Text(errorMessage)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.recording)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.lg)
                }

                // Sign in with Apple button
                Button(action: signIn) {
                    HStack(spacing: Spacing.sm) {
                        if isSigningIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.background))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .medium))
                        }
                        Text(isSigningIn ? "CONNECTING..." : "CONTINUE WITH APPLE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(2)
                    }
                    .foregroundColor(chrome.panelInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.colors.success)
                    .cornerRadius(CornerRadius.md)
                    .shadow(color: theme.colors.success.opacity(0.4), radius: chrome.glowRadius)
                }
                .disabled(isSigningIn)
                .padding(.horizontal, Spacing.xl)

                Spacer()

                // Privacy footer
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10))
                    Text("Your data stays on your devices and your iCloud.")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(theme.colors.textTertiary.opacity(0.7))
                .padding(.bottom, Spacing.xl)
            }
        }
        .onChange(of: authManager.isSignedIn) { _, signedIn in
            if signedIn {
                dismiss()
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task { @MainActor in
            defer { isSigningIn = false }

            do {
                try await authManager.signIn()
            } catch let error as AuthError where error == .cancelled {
                // User cancelled: keep view open without surfacing an error.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func stepIcon(for status: AuthStep.Status) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(theme.chrome.edge, lineWidth: 1)
                .frame(width: 16, height: 16)
        case .inProgress:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.chrome.accent))
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(theme.colors.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.recording)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(theme.colors.success)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(theme.colors.textSecondary)
        }
    }

    private func stepColor(for status: AuthStep.Status) -> Color {
        switch status {
        case .pending: return theme.colors.textTertiary.opacity(0.6)
        case .inProgress: return theme.colors.textPrimary
        case .completed: return theme.colors.textSecondary
        case .failed: return .recording
        }
    }
}
