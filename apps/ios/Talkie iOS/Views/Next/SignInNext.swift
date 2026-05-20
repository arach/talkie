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

import AuthenticationServices
import CloudKit
import Security
import SwiftUI

@MainActor
final class SignInStore: NSObject, ObservableObject {
    @Published var isSigningIn: Bool = false
    @Published var errorMessage: String?
    @Published var showInfo: Bool = false
    @Published var authSteps: [AuthStepDisplay] = []

    static let signedInDefaultsKey = "nativeAppleSignInCompleted"

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    struct AuthStepDisplay: Identifiable {
        let id = UUID()
        let name: String
        var detail: String?
        var status: Status

        enum Status { case pending, inProgress, completed, failed }
    }

    func signInWithApple() {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        authSteps = [
            AuthStepDisplay(name: "Request credentials", detail: "Sign in with Apple", status: .inProgress),
            AuthStepDisplay(name: "Validate", detail: "Verify Apple identity", status: .pending),
            AuthStepDisplay(name: "Provision iCloud sync", detail: "Check CloudKit account", status: .pending)
        ]

        Task { @MainActor in
            do {
                let credential = try await requestAppleCredential()
                updateStep(0, status: .completed)
                updateStep(1, status: .inProgress)

                try saveCredential(credential)
                updateStep(1, status: .completed, detail: "Credential saved")
                updateStep(2, status: .inProgress)

                _ = try? await CKContainer.default().accountStatus()
                UserDefaults.standard.set(true, forKey: Self.signedInDefaultsKey)
                updateStep(2, status: .completed, detail: "Ready for iCloud sync")

                AppLogger.app.info("[Auth] Native Sign in with Apple complete")
                AppShellRouter.shared.openHome()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                authSteps = []
            } catch {
                markCurrentStepFailed()
                errorMessage = error.localizedDescription
                AppLogger.app.error("[Auth] Native Sign in with Apple failed: \(error)")
            }

            isSigningIn = false
        }
    }

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func updateStep(_ index: Int, status: AuthStepDisplay.Status, detail: String? = nil) {
        guard authSteps.indices.contains(index) else { return }
        authSteps[index].status = status
        if let detail {
            authSteps[index].detail = detail
        }
    }

    private func markCurrentStepFailed() {
        guard let index = authSteps.firstIndex(where: { $0.status == .inProgress }) else { return }
        updateStep(index, status: .failed, detail: "Failed")
    }

    private func saveCredential(_ credential: ASAuthorizationAppleIDCredential) throws {
        let payload = NativeAppleCredential(
            userIdentifier: credential.user,
            email: credential.email,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            identityToken: credential.identityToken?.base64EncodedString(),
            authorizationCode: credential.authorizationCode?.base64EncodedString(),
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "to.talkie.native-apple-auth",
            kSecAttrAccount: credential.user
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(query as CFDictionary)
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NativeSignInError.keychainSaveFailed(addStatus)
        }
    }

    private struct NativeAppleCredential: Codable {
        let userIdentifier: String
        let email: String?
        let givenName: String?
        let familyName: String?
        let identityToken: String?
        let authorizationCode: String?
        let updatedAt: Date
    }

    private enum NativeSignInError: LocalizedError {
        case missingCredential
        case keychainSaveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingCredential:
                return "Apple did not return a usable credential."
            case .keychainSaveFailed(let status):
                return "Could not save Apple credential (status \(status))."
            }
        }
    }
}

extension SignInStore: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: NativeSignInError.missingCredential)
                continuation = nil
                return
            }

            continuation?.resume(returning: credential)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
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
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.bottom, 6)

                Text("Sync across iPhone and Mac")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.bottom, 10)

                Text("Create a free account to sync memos\nbetween your iPhone and Mac.")
                    .talkieType(.listTitle)
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
                    .talkieType(.preview)
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
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // MARK: - Auth steps (S01 / S02 channel-labelled rows)

    private var authStepsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(store.authSteps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 10) {
                    Text(String(format: "S%02d", idx + 1))
                        .talkieType(.channelLabelTiny)
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
                            .talkieType(.preview)
                            .foregroundStyle(stepColor(step.status))
                        if let detail = step.detail {
                            Text(detail)
                                .talkieType(.hint)
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
                .talkieType(.preview)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Apple button (single provider, matches donor)

    private var appleButton: some View {
        Button(action: store.signInWithApple) {
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
                    .talkieType(.preview)
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
                .talkieType(.timestamp)
        }
        .foregroundStyle(theme.colors.textTertiary.opacity(0.7))
    }
}
