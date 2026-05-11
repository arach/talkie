//
//  AuthManager.swift
//  Talkie iOS
//
//  Manages user authentication via ClerkKit (Sign in with Apple)
//

import Foundation
import ClerkKit
import TalkieMobileKit

// MARK: - Auth Step Model

struct AuthStep: Identifiable {
    let id = UUID()
    let name: String
    var status: Status
    var detail: String?

    enum Status {
        case pending
        case inProgress
        case completed
        case failed
    }
}

// MARK: - User Model

struct TalkieUser: Codable, Equatable {
    let userId: String
    let email: String?
    let plan: Plan
    let features: [Feature]

    enum Plan: String, Codable {
        case free
        case pro
        case team
    }

    enum Feature: String, Codable {
        case cloudSync
        case aiPolish
        case prioritySupport
        case betaFeatures
    }

    var isPro: Bool { plan == .pro || plan == .team }
    var hasCloudSync: Bool { features.contains(.cloudSync) }
}

// MARK: - Auth Manager

@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    // MARK: - State

    var isSignedIn: Bool { Clerk.shared.user != nil }

    var user: TalkieUser? {
        guard let clerkUser = Clerk.shared.user else { return nil }
        return TalkieUser(
            userId: clerkUser.id,
            email: clerkUser.primaryEmailAddress?.emailAddress,
            plan: .free,
            features: []
        )
    }

    private(set) var isLoading: Bool = false
    var error: String?
    private(set) var authSteps: [AuthStep] = []

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Sign in using Apple (native sheet, no browser)
    func signIn() async throws {
        isLoading = true
        error = nil

        authSteps = [
            AuthStep(name: "Authenticating", status: .inProgress),
            AuthStep(name: "Setting up account", status: .pending)
        ]

        defer {
            isLoading = false
            if error == nil && isSignedIn {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    authSteps = []
                }
            }
        }

        AppLogger.app.info("[Auth] Starting Sign in with Apple")

        do {
            let result = try await Clerk.shared.auth.signInWithApple()

            updateStep(0, status: .completed)
            updateStep(1, status: .inProgress)

            switch result {
            case .signIn(let signIn):
                AppLogger.app.info("[Auth] Signed in as \(signIn.identifier ?? "unknown")")
            case .signUp(let signUp):
                AppLogger.app.info("[Auth] New account created for \(signUp.emailAddress ?? "unknown")")
            }

            updateStep(1, status: .completed)
            AppLogger.app.info("[Auth] Auth complete for \(user?.email ?? "unknown")")
        } catch is CancellationError {
            updateStep(0, status: .failed, detail: "Cancelled")
            self.error = nil
            throw AuthError.cancelled
        } catch {
            updateStep(0, status: .failed, detail: "Failed")
            self.error = error.localizedDescription
            AppLogger.app.error("[Auth] Sign in failed: \(error)")
            throw AuthError.authFailed(error.localizedDescription)
        }
    }

    /// Sign out and clear session
    func signOut() {
        self.error = nil
        Task { @MainActor in
            do {
                try await Clerk.shared.auth.signOut()
                self.error = nil
                AppLogger.app.info("[Auth] Signed out")
            } catch {
                self.error = error.localizedDescription
                AppLogger.app.error("[Auth] Sign out error: \(error)")
            }
        }
    }

    /// Get current auth token (JWT)
    var authToken: String? {
        get async {
            try? await Clerk.shared.auth.getToken()
        }
    }

    // MARK: - Step Tracking

    private func updateStep(_ index: Int, status: AuthStep.Status, detail: String? = nil) {
        guard index < authSteps.count else { return }
        authSteps[index].status = status
        if let detail = detail {
            authSteps[index].detail = detail
        }
    }
}

// MARK: - Errors

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case authFailed(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .notSignedIn:
            return "Not signed in"
        }
    }
}
