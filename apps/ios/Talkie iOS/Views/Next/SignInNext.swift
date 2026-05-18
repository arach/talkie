//
//  SignInNext.swift
//  Talkie iOS
//
//  Faithful port of SignInView (apps/ios/Talkie iOS/Views/
//  SignInView.swift, 255 lines). Single-provider sign-in (Apple)
//  framed as iPhone↔Mac sync. Structure matches the donor:
//
//  - Close X top-right
//  - link.circle hero icon in success ring + glow
//  - "· CONNECT YOUR DEVICES" eyebrow + "Sync across iPhone and Mac"
//  - Value-prop sub-copy
//  - "What's included?" info disclosure with 4 rows
//  - Auth steps progress (S01/S02/S03 channel labels + status)
//  - Error row when surfaced
//  - "Continue with Apple" full-width button
//  - Privacy footer
//

import SwiftUI

@MainActor
final class SignInStore: ObservableObject {
    @Published var isSigningIn: Bool = false
    @Published var errorMessage: String?
    @Published var showInfo: Bool = false
    @Published var authSteps: [AuthStepDisplay] = []

    struct AuthStepDisplay: Identifiable {
        let id = UUID()
        let name: String
        let detail: String?
        let status: Status

        enum Status { case pending, inProgress, completed, failed }
    }

    // Codex wires against AuthManager.shared. For paint, no steps
    // surfaced by default. Codex populates from authManager.authSteps.
}

struct SignInNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = SignInStore()

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                closeButton

                Spacer()

                heroIcon
                    .padding(.bottom, 18)

                Text("· CONNECT YOUR DEVICES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.bottom, 6)

                Text("Sync across iPhone and Mac")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.bottom, 10)

                Text("Create a free account to sync memos\nbetween your iPhone and Mac.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 14)

                infoDisclosure
                    .padding(.bottom, store.showInfo ? 10 : 28)

                if store.showInfo {
                    infoRows
                        .padding(.horizontal, 32)
                        .padding(.bottom, 28)
                }

                if !store.authSteps.isEmpty {
                    authStepsBlock
                        .padding(.horizontal, 32)
                        .padding(.bottom, 22)
                }

                if let err = store.errorMessage {
                    errorRow(err)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                appleButton
                    .padding(.horizontal, 24)

                Spacer()

                privacyFooter
                    .padding(.bottom, 22)
            }
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        HStack {
            Spacer()
            Button(action: { AppShellRouter.shared.openHome() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Hero icon (link.circle in success ring with glow)

    private var heroIcon: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.colors.success.opacity(0.3), lineWidth: 1)
                .frame(width: 88, height: 88)
            Image(systemName: "link.circle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(theme.colors.success)
                .shadow(color: theme.colors.success.opacity(0.3),
                        radius: theme.currentTheme.chrome.glowRadius)
        }
    }

    // MARK: - Info disclosure

    private var infoDisclosure: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.showInfo.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .light))
                Text("What's included?")
                    .font(.system(size: 13, weight: .light))
                Image(systemName: store.showInfo ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .light))
            }
            .foregroundStyle(theme.colors.textTertiary)
        }
        .buttonStyle(.plain)
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "checkmark.circle",            text: "Completely free — no payment required")
            infoRow(icon: "arrow.triangle.2.circlepath", text: "Memos sync between iPhone and Mac")
            infoRow(icon: "bolt",                         text: "Cloud transcription and AI features")
            infoRow(icon: "lock.shield",                  text: "We never listen to your recordings")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(theme.colors.success)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // MARK: - Auth steps (S01 / S02 channel-labelled rows)

    private var authStepsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(store.authSteps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 10) {
                    Text(String(format: "S%02d", idx + 1))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(stepIsActive(step) ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .strokeBorder(stepIsActive(step) ? theme.currentTheme.chrome.accentStrong : theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )

                    stepIcon(step.status)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(stepColor(step.status))
                        if let detail = step.detail {
                            Text(detail)
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ status: SignInStore.AuthStepDisplay.Status) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                .frame(width: 16, height: 16)
        case .inProgress:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.currentTheme.chrome.accent))
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
        }
    }

    private func stepIsActive(_ step: SignInStore.AuthStepDisplay) -> Bool {
        step.status == .inProgress || step.status == .completed
    }

    private func stepColor(_ status: SignInStore.AuthStepDisplay.Status) -> Color {
        switch status {
        case .pending:    return theme.colors.textTertiary.opacity(0.6)
        case .inProgress: return theme.colors.textPrimary
        case .completed:  return theme.colors.textSecondary
        case .failed:     return .red
        }
    }

    // MARK: - Error

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Apple button (single provider, matches donor)

    private var appleButton: some View {
        Button(action: {
            // TODO M3+ wire: AuthManager.shared.signIn() task
        }) {
            HStack(spacing: 10) {
                if store.isSigningIn {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.cardBackground))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .medium))
                }
                Text(store.isSigningIn ? "CONNECTING..." : "CONTINUE WITH APPLE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
            }
            .foregroundStyle(theme.colors.cardBackground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.success)
                    .shadow(color: theme.colors.success.opacity(0.4),
                            radius: theme.currentTheme.chrome.glowRadius)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isSigningIn)
    }

    // MARK: - Privacy footer

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
            Text("Your data stays on your devices and your iCloud.")
                .font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(theme.colors.textTertiary.opacity(0.7))
    }
}
