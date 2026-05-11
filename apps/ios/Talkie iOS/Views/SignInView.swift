//
//  SignInView.swift
//  Talkie iOS
//
//  Account setup — shown contextually from Settings / Mac Sync
//

import SwiftUI
import TalkieMobileKit

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showInfo = false

    private var authManager: AuthManager { AuthManager.shared }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "6A6A6A"))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Spacing.md)
                    .padding(.top, Spacing.sm)
                }

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .stroke(Color(hex: "22C55E").opacity(0.3), lineWidth: 1)
                        .frame(width: 88, height: 88)

                    Image(systemName: "link.circle")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundColor(Color(hex: "22C55E"))
                }
                .padding(.bottom, Spacing.lg)

                // Headline
                Text("CONNECT YOUR DEVICES")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(3)
                    .foregroundColor(.white)
                    .padding(.bottom, Spacing.sm)

                // Value prop
                Text("Create a free account to sync memos\nbetween your iPhone and Mac.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "8A8A8A"))
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
                    .foregroundColor(Color(hex: "6A6A6A"))
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
                        ForEach(authManager.authSteps) { step in
                            HStack(spacing: Spacing.sm) {
                                stepIcon(for: step.status)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(stepColor(for: step.status))

                                    if let detail = step.detail {
                                        Text(detail)
                                            .font(.system(size: 11, weight: .light))
                                            .foregroundColor(Color(hex: "6A6A6A"))
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
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .medium))
                        }
                        Text(isSigningIn ? "CONNECTING..." : "CONTINUE WITH APPLE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(2)
                    }
                    .foregroundColor(Color(hex: "0A0A0A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "22C55E"))
                    .cornerRadius(CornerRadius.md)
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
                .foregroundColor(Color(hex: "4A4A4A"))
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
                .stroke(Color(hex: "3A3A3A"), lineWidth: 1)
                .frame(width: 16, height: 16)
        case .inProgress:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .active))
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.success)
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
                .foregroundColor(Color(hex: "22C55E"))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(hex: "9A9A9A"))
        }
    }

    private func stepColor(for status: AuthStep.Status) -> Color {
        switch status {
        case .pending: return Color(hex: "4A4A4A")
        case .inProgress: return .white
        case .completed: return Color(hex: "8A8A8A")
        case .failed: return .recording
        }
    }
}
