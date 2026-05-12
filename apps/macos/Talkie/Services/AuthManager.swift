//
//  AuthManager.swift
//  Talkie
//
//  Manages user authentication via Clerk
//  Uses OAuth 2.0 with PKCE via ASWebAuthenticationSession
//

import Foundation
import AuthenticationServices
import CryptoKit
import TalkieKit

private let log = Log(.system)

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

    // MARK: - OAuth Configuration

    /// Clerk OAuth client ID (from Clerk Dashboard → OAuth Applications)
    /// Different client IDs for production vs dev environments
    private var clientId: String {
        switch TalkieEnvironment.current {
        case .production:
            return "d8RRsRnH4u7UonCj"
        case .dev:
            return "7k1bKqLDQR4pzSqT"
        }
    }

    /// Clerk domain for OAuth endpoints
    private var clerkDomain: String { TalkieEnvironment.current.authDomain }

    /// Callback URL scheme (must be registered in Info.plist)
    private let callbackScheme = "talkie"
    private var redirectURI: String { "\(callbackScheme)://auth/callback" }

    /// API base URL (from TalkieEnvironment)
    private var apiBaseURL: String { TalkieEnvironment.current.apiBaseURL }

    /// OAuth endpoints
    private var authorizeURL: String { "\(clerkDomain)/oauth/authorize" }
    private var tokenURL: String { "\(clerkDomain)/oauth/token" }

    // MARK: - State

    private(set) var isSignedIn: Bool = false
    private(set) var user: TalkieUser?
    private(set) var isLoading: Bool = false
    var error: String?
    private(set) var authSteps: [AuthStep] = []

    @ObservationIgnored
    private var webAuthSession: ASWebAuthenticationSession?

    @ObservationIgnored
    private var codeVerifier: String?

    // MARK: - Init

    private init() {
        // Check for existing session on launch
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Public API

    /// Sign in using OAuth 2.0 with PKCE
    func signIn() async throws {
        isLoading = true
        error = nil

        // Initialize steps
        authSteps = [
            AuthStep(name: "Preparing", status: .inProgress),
            AuthStep(name: "Opening browser", status: .pending),
            AuthStep(name: "Waiting for browser", status: .pending, detail: "Complete sign-in →"),
            AuthStep(name: "Exchanging tokens", status: .pending),
            AuthStep(name: "Fetching account", status: .pending)
        ]

        defer {
            isLoading = false
            // Clear steps after a delay if successful
            if error == nil && isSignedIn {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    authSteps = []
                }
            }
        }

        log.info("=== Starting OAuth Sign-In ===", detail: "[Auth]")
        log.debug("Client ID: \(clientId)", detail: "[Auth]")
        log.debug("Redirect URI: \(redirectURI)", detail: "[Auth]")
        log.debug("Authorize URL: \(authorizeURL)", detail: "[Auth]")
        log.debug("Token URL: \(tokenURL)", detail: "[Auth]")

        // Generate PKCE code verifier and challenge
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        self.codeVerifier = verifier
        log.debug("Generated PKCE verifier (length: \(verifier.count))", detail: "[Auth]")
        log.debug("Generated PKCE challenge: \(challenge)", detail: "[Auth]")

        updateStep(0, status: .completed)
        updateStep(1, status: .inProgress)

        // Build OAuth authorize URL
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: "profile email offline_access")
        ]

        guard let authURL = components.url else {
            log.error("Failed to build auth URL", detail: "[Auth]")
            throw AuthError.invalidURL
        }

        log.info("Opening auth URL: \(authURL.absoluteString)", detail: "[Auth]")

        updateStep(1, status: .completed)
        updateStep(2, status: .inProgress)

        // Create and start web auth session
        log.info("Creating ASWebAuthenticationSession...", detail: "[Auth]")
        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                log.debug("ASWebAuthenticationSession callback received", detail: "[Auth]")

                if let error = error {
                    log.error("Auth session error: \(error.localizedDescription)", detail: "[Auth]")
                    log.error("Error code: \((error as NSError).code)", detail: "[Auth]")
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.webAuthFailed(error.localizedDescription))
                    }
                    return
                }

                if let callbackURL = callbackURL {
                    log.debug("Callback URL: \(callbackURL.absoluteString)", detail: "[Auth]")
                } else {
                    log.error("Callback URL is nil", detail: "[Auth]")
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    // Log all query items for debugging
                    if let url = callbackURL, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        log.debug("Query items: \(comps.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" } ?? [])", detail: "[Auth]")
                    }
                    // Check for error in callback
                    if let url = callbackURL,
                       let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let errorDesc = comps.queryItems?.first(where: { $0.name == "error_description" })?.value {
                        log.error("OAuth error: \(errorDesc)", detail: "[Auth]")
                        continuation.resume(throwing: AuthError.webAuthFailed(errorDesc))
                    } else {
                        log.error("No code in callback URL", detail: "[Auth]")
                        continuation.resume(throwing: AuthError.noCodeReceived)
                    }
                    return
                }

                log.info("Received authorization code (length: \(code.count))", detail: "[Auth]")
                continuation.resume(returning: code)
            }

            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session
            log.info("Starting auth session...", detail: "[Auth]")
            session.start()
        }

        log.info("=== Code received, starting token exchange ===", detail: "[Auth]")

        updateStep(2, status: .completed)
        updateStep(3, status: .inProgress)

        // Exchange code for tokens
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await exchangeCodeForToken(code: code)
        } catch {
            updateStep(3, status: .failed, detail: "Failed")
            throw error
        }

        // Save access token
        let saved = KeychainManager.shared.save(tokenResponse.accessToken, for: .authSessionToken)
        guard saved else {
            updateStep(3, status: .failed, detail: "Save failed")
            throw AuthError.keychainSaveFailed
        }

        updateStep(3, status: .completed)
        updateStep(4, status: .inProgress)

        log.info("Token saved, fetching user...", detail: "[Auth]")

        // Fetch user info from our API
        do {
            try await fetchUser()
        } catch {
            updateStep(4, status: .failed, detail: "Failed")
            throw error
        }

        updateStep(4, status: .completed)
        log.info("Signed in as \(user?.email ?? "unknown")", detail: "[Auth]")
    }

    /// Sign out and clear session
    func signOut() {
        KeychainManager.shared.delete(.authSessionToken)
        isSignedIn = false
        user = nil
        error = nil
        codeVerifier = nil
        NotificationCenter.default.post(name: .talkieAuthStateDidChange, object: nil)
        log.info("Signed out", detail: "[Auth]")
    }

    /// Refresh user info from API
    func refreshUser() async throws {
        try await fetchUser()
    }

    /// Get current auth token (for API calls)
    var authToken: String? {
        KeychainManager.shared.retrieve(for: .authSessionToken)
    }

    // MARK: - Step Tracking

    private func updateStep(_ index: Int, status: AuthStep.Status, detail: String? = nil) {
        guard index < authSteps.count else { return }
        authSteps[index].status = status
        if let detail = detail {
            authSteps[index].detail = detail
        }
    }

    // MARK: - PKCE Helpers

    /// Generate a random code verifier (43-128 characters)
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Generate code challenge from verifier using SHA256
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Token Exchange

    private struct TokenResponse: Codable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        guard let verifier = codeVerifier else {
            log.error("No code verifier available", detail: "[Auth]")
            throw AuthError.noCodeVerifier
        }

        log.debug("Token URL: \(tokenURL)", detail: "[Auth]")
        log.debug("Code verifier length: \(verifier.count)", detail: "[Auth]")

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        log.debug("Token request params: grant_type=authorization_code, client_id=\(clientId), redirect_uri=\(redirectURI)", detail: "[Auth]")

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        log.info("Sending token exchange request...", detail: "[Auth]")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("Invalid response type", detail: "[Auth]")
            throw AuthError.invalidResponse
        }

        log.debug("Token response status: \(httpResponse.statusCode)", detail: "[Auth]")

        if httpResponse.statusCode != 200 {
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                log.error("Token error response: \(responseString)", detail: "[Auth]")
            }
            // Try to parse error
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDesc = errorJson["error_description"] as? String {
                log.error("Token exchange error: \(errorDesc)", detail: "[Auth]")
                throw AuthError.tokenExchangeFailed(errorDesc)
            }
            throw AuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        log.info("Token exchange successful", detail: "[Auth]")
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Session Management

    private func checkExistingSession() async {
        guard let token = KeychainManager.shared.retrieve(for: .authSessionToken) else {
            log.debug("No existing session", detail: "[Auth]")
            return
        }

        log.debug("Found existing token, validating...", detail: "[Auth]")

        do {
            try await fetchUser()
            log.info("Session restored for \(user?.email ?? "unknown")", detail: "[Auth]")
        } catch {
            log.warning("Existing session invalid: \(error)", detail: "[Auth]")
            // Clear invalid token
            signOut()
        }
    }

    private func fetchUser() async throws {
        guard let token = authToken else {
            throw AuthError.notSignedIn
        }

        // Use Clerk's OAuth userinfo endpoint directly
        let userinfoURL = "\(clerkDomain)/oauth/userinfo"
        log.info("Fetching user info from: \(userinfoURL)", detail: "[Auth]")

        var request = URLRequest(url: URL(string: userinfoURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        log.debug("Userinfo response status: \(httpResponse.statusCode)", detail: "[Auth]")

        if httpResponse.statusCode == 401 {
            throw AuthError.tokenExpired
        }

        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                log.error("Userinfo error response: \(responseString)", detail: "[Auth]")
            }
            throw AuthError.apiError(httpResponse.statusCode)
        }

        // Clerk userinfo response format
        struct ClerkUserInfo: Codable {
            let sub: String           // User ID
            let email: String?
            let emailVerified: Bool?
            let name: String?
            let picture: String?

            enum CodingKeys: String, CodingKey {
                case sub
                case email
                case emailVerified = "email_verified"
                case name
                case picture
            }
        }

        let userInfo = try JSONDecoder().decode(ClerkUserInfo.self, from: data)
        log.info("User info received: \(userInfo.email ?? "no email")", detail: "[Auth]")

        // Create TalkieUser from Clerk userinfo
        // For now, everyone is free plan - entitlements would come from your backend later
        self.user = TalkieUser(
            userId: userInfo.sub,
            email: userInfo.email,
            plan: .free,
            features: []
        )
        self.isSignedIn = true
        NotificationCenter.default.post(name: .talkieAuthStateDidChange, object: nil)
    }
}

extension Notification.Name {
    static let talkieAuthStateDidChange = Notification.Name("TalkieAuthStateDidChange")
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case cancelled
    case invalidURL
    case webAuthFailed(String)
    case noCodeReceived
    case noCodeVerifier
    case noTokenReceived
    case tokenExchangeFailed(String)
    case keychainSaveFailed
    case notSignedIn
    case tokenExpired
    case invalidResponse
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled"
        case .invalidURL:
            return "Invalid authentication URL"
        case .webAuthFailed(let message):
            return "Authentication failed: \(message)"
        case .noCodeReceived:
            return "No authorization code received"
        case .noCodeVerifier:
            return "Missing code verifier"
        case .noTokenReceived:
            return "No authentication token received"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .keychainSaveFailed:
            return "Failed to save credentials"
        case .notSignedIn:
            return "Not signed in"
        case .tokenExpired:
            return "Session expired, please sign in again"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code):
            return "Server error (code: \(code))"
        }
    }
}

// MARK: - Presentation Context

private class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window for macOS
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Base64URL Encoding

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
