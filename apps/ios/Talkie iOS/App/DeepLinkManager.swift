//
//  DeepLinkManager.swift
//  Talkie iOS
//
//  Handles URL deep links for widget and Siri integration
//  Supports x-callback-url for inter-app communication
//

import Foundation
import SwiftUI
import UIKit
import TalkieMobileKit

enum DeepLinkAction: Equatable {
    case none
    case record
    case dictate          // Keyboard-initiated dictation (records and returns)
    case keyboardActivate
    case keyboardDeactivate
    case keyboardView  // Open keyboard view
    case openMemo(id: UUID)
    case openMemoActivity(id: UUID)  // Open memo and scroll to activity section
    case playLastMemo
    case search(query: String)
    case openSearch      // Just open search UI
    case openAllMemos    // Open main memo list
    case openSettings    // Open settings view
    case openSSHTerminal
    case importAudio(url: URL)  // Import audio file from share sheet
    case importURL(url: URL, title: String?)  // Import web content from URL
    case processShare(id: String)             // Process queued share from Share Extension
}

/// x-callback-url parameters for returning to the calling app
struct CallbackURLs {
    let success: URL?      // Called on successful transcription
    let cancel: URL?       // Called if user cancels
    let error: URL?        // Called on error
    let source: String?    // Source app name for display
    let sourceBundleId: String?

    var hasCallbacks: Bool {
        success != nil || cancel != nil || error != nil
    }
}

class DeepLinkManager: ObservableObject {
    struct PendingSSHImport: Equatable {
        let payload: SSHPrivateKeyQRCodePayload
        let sourceDescription: String
    }

    enum AISetupStatus: Equatable {
        case success(providerName: String, modelId: String)
        case failure(message: String)
    }

    static let shared = DeepLinkManager()

    @Published var pendingAction: DeepLinkAction = .none
    @Published var lastDeepLinkURL: String?
    @Published var lastKeyboardDebug: String?
    @Published var keyboardAutoStartRequested: Bool = false
    @Published var pendingSSHImport: PendingSSHImport?
    @Published var aiSetupStatus: AISetupStatus?

    /// Callback URLs from the last x-callback-url request
    var callbackURLs: CallbackURLs?

    private init() {}

    /// Supported audio file extensions for import
    private static let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "mp4", "3gp"]

    func handle(url: URL) {
        lastDeepLinkURL = url.absoluteString
        // Handle file:// URLs for audio import
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if Self.audioExtensions.contains(ext) {
                AppLogger.app.info("Deep link: import audio from \(url.lastPathComponent)")
                pendingAction = .importAudio(url: url)
            } else {
                AppLogger.app.warning("Unsupported file type: \(ext)")
            }
            return
        }

        guard url.scheme == "talkie" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "record":
            AppLogger.app.info("Deep link: record action triggered")
            pendingAction = .record

        case "dictate":
            AppLogger.app.info("Deep link: keyboard dictation requested")

            // Parse x-callback-url parameters
            parseCallbackURLs(from: components)

            pendingAction = .dictate
        case "keyboard":
            let path = components?.path ?? ""
            if path == "/activate" {
                AppLogger.app.info("Deep link: keyboard mode activate")
                parseCallbackURLs(from: components)
                pendingAction = .keyboardActivate
            } else if path == "/deactivate" {
                AppLogger.app.info("Deep link: keyboard mode deactivate")
                parseCallbackURLs(from: components)
                pendingAction = .keyboardDeactivate
            } else if path.isEmpty || path == "/" {
                // talkie://keyboard opens the keyboard view
                AppLogger.app.info("Deep link: open keyboard view")
                pendingAction = .keyboardView
            } else {
                AppLogger.app.warning("Unknown keyboard deep link path: \(path)")
            }

        case "memo":
            // Handle talkie://memo?id=<uuid>
            if let idString = components?.queryItems?.first(where: { $0.name == "id" })?.value,
               let id = UUID(uuidString: idString) {
                AppLogger.app.info("Deep link: open memo \(id)")
                pendingAction = .openMemo(id: id)
            }

        case "play-last":
            AppLogger.app.info("Deep link: play last memo")
            pendingAction = .playLastMemo

        case "search":
            // Handle talkie://search or talkie://search?q=<query>
            if let query = components?.queryItems?.first(where: { $0.name == "q" })?.value {
                AppLogger.app.info("Deep link: search for '\(query)'")
                pendingAction = .search(query: query)
            } else {
                AppLogger.app.info("Deep link: open search")
                pendingAction = .openSearch
            }

        case "memos":
            AppLogger.app.info("Deep link: open all memos")
            pendingAction = .openAllMemos

        case "settings":
            AppLogger.app.info("Deep link: open settings")
            pendingAction = .openSettings

        case "ssh":
            let path = components?.path ?? ""
            if path == "/import-key" {
                handleSSHImport(from: components)
            } else {
                AppLogger.app.info("Deep link: open SSH terminal")
                pendingAction = .openSSHTerminal
            }

        case "ai":
            handleAISetup(from: url, components: components)

        case "share":
            // Handle talkie://share?id=<uuid> from Share Extension
            if let shareId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                AppLogger.app.info("Deep link: process share \(shareId)")
                pendingAction = .processShare(id: shareId)
            } else {
                AppLogger.app.warning("Deep link: share missing id parameter")
            }

        case "import-content":
            // Handle talkie://import-content?url=<encoded>&title=<optional>
            if let urlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
               let contentURL = URL(string: urlString) {
                let title = components?.queryItems?.first(where: { $0.name == "title" })?.value
                AppLogger.app.info("Deep link: import URL content from \(contentURL.absoluteString)")
                pendingAction = .importURL(url: contentURL, title: title)
            } else {
                AppLogger.app.warning("Deep link: import-content missing or invalid url parameter")
            }

        case "auth":
            // ClerkKit handles OAuth callbacks internally; this is a no-op
            AppLogger.app.info("Deep link: auth callback (handled by ClerkKit)")

        default:
            AppLogger.app.warning("Unknown deep link: \(url.absoluteString)")
        }
    }

    func clearAction() {
        pendingAction = .none
        keyboardAutoStartRequested = false
    }

    func queueSSHImport(
        payload: SSHPrivateKeyQRCodePayload,
        sourceDescription: String
    ) {
        pendingSSHImport = PendingSSHImport(
            payload: payload,
            sourceDescription: sourceDescription
        )
    }

    func consumePendingSSHImport() -> PendingSSHImport? {
        defer { pendingSSHImport = nil }
        return pendingSSHImport
    }

    // MARK: - x-callback-url Support

    /// Call the success callback URL (after successful transcription)
    /// Returns true if a callback was opened, false otherwise
    @discardableResult
    func callSuccessCallback(text: String? = nil) -> Bool {
        guard let successURL = callbackURLs?.success else {
            // Don't log - this is expected when keyboard triggers dictation
            // (host apps don't provide x-callback URLs)
            return false
        }

        // Optionally append the text as a query param
        var urlToOpen = successURL
        if let text = text, var components = URLComponents(url: successURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "text", value: text))
            components.queryItems = queryItems
            if let modifiedURL = components.url {
                urlToOpen = modifiedURL
            }
        }

        AppLogger.app.info("Opening x-success callback: \(urlToOpen.absoluteString)")
        openURL(urlToOpen)
        clearCallbacks()
        return true
    }

    /// Best-effort return to source app when no callback is available
    @discardableResult
    func returnToSourceBestEffort() -> Bool {
        if callSuccessCallback() {
            return true
        }

        guard let bundleId = callbackURLs?.sourceBundleId else {
            // Don't log - expected when keyboard triggers without source info
            return false
        }

        if bundleId == "com.apple.mobilenotes" {
            let notesURL = URL(string: "mobilenotes://")!
            AppLogger.app.info("Best-effort return: opening Notes via \(notesURL.absoluteString)")
            openURL(notesURL)
            return true
        }

        AppLogger.app.info("Best-effort return: no handler for bundle \(bundleId)")
        return false
    }

    /// Call the cancel callback URL
    @discardableResult
    func callCancelCallback() -> Bool {
        guard let cancelURL = callbackURLs?.cancel else {
            return false
        }

        AppLogger.app.info("Opening x-cancel callback: \(cancelURL.absoluteString)")
        openURL(cancelURL)
        clearCallbacks()
        return true
    }

    /// Call the error callback URL
    @discardableResult
    func callErrorCallback(message: String? = nil) -> Bool {
        guard let errorURL = callbackURLs?.error else {
            return false
        }

        var urlToOpen = errorURL
        if let message = message, var components = URLComponents(url: errorURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "error", value: message))
            components.queryItems = queryItems
            if let modifiedURL = components.url {
                urlToOpen = modifiedURL
            }
        }

        AppLogger.app.info("Opening x-error callback: \(urlToOpen.absoluteString)")
        openURL(urlToOpen)
        clearCallbacks()
        return true
    }

    /// Clear stored callback URLs
    func clearCallbacks() {
        callbackURLs = nil
    }

    /// Get the source app name for display (e.g., "Tap Back to Notes")
    var sourceAppName: String? {
        callbackURLs?.source
    }

    /// Check if we have a callback to return to
    var hasReturnCallback: Bool {
        callbackURLs?.success != nil
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                AppLogger.app.error("Failed to open callback URL: \(url.absoluteString)")
            }
        }
    }

    private func parseCallbackURLs(from components: URLComponents?) {
        let queryItems = components?.queryItems ?? []
        let xSuccess = queryItems.first(where: { $0.name == "x-success" })?.value.flatMap { URL(string: $0) }
        let xCancel = queryItems.first(where: { $0.name == "x-cancel" })?.value.flatMap { URL(string: $0) }
        let xError = queryItems.first(where: { $0.name == "x-error" })?.value.flatMap { URL(string: $0) }
        let source = queryItems.first(where: { $0.name == "source" })?.value
        let sourceBundleId = queryItems.first(where: { $0.name == "sourceBundle" })?.value
        let autoStart = queryItems.first(where: { $0.name == "autoStart" })?.value == "1"

        callbackURLs = CallbackURLs(
            success: xSuccess,
            cancel: xCancel,
            error: xError,
            source: source,
            sourceBundleId: sourceBundleId
        )

        keyboardAutoStartRequested = autoStart

        lastKeyboardDebug = [
            "source=\(source ?? "nil")",
            "bundle=\(sourceBundleId ?? "nil")",
            "x-success=\(xSuccess?.absoluteString ?? "nil")",
            "x-cancel=\(xCancel?.absoluteString ?? "nil")",
            "x-error=\(xError?.absoluteString ?? "nil")",
            "autoStart=\(autoStart)"
        ].joined(separator: "\n")

        AppLogger.app.info("Keyboard deep link params:\n\(lastKeyboardDebug ?? "none")")

        // TODO: Add setLastSource to KeyboardBridge if source tracking is needed
        // if source != nil || sourceBundleId != nil {
        //     KeyboardBridge.shared.setLastSource(name: source, bundleId: sourceBundleId)
        // }
    }

    private func handleSSHImport(from components: URLComponents?) {
        guard let payloadString = components?.queryItems?.first(where: { $0.name == "payload" })?.value else {
            AppLogger.app.warning("SSH import deep link missing payload")
            pendingAction = .openSSHTerminal
            return
        }

        Task { @MainActor in
            do {
                let payload = try await SSHPrivateKeyQRCodePayload.decode(from: payloadString)
                let privateKey = payload.normalizedPrivateKey
                _ = try SSHPrivateKeyParser.parse(privateKey)
                let label = payload.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceDescription = if let label, !label.isEmpty {
                    "Review \(label) from pairing link before importing."
                } else {
                    "Review the SSH import from pairing link before saving anything."
                }

                queueSSHImport(
                    payload: payload,
                    sourceDescription: sourceDescription
                )

                AppLogger.app.info("Deep link: queued SSH import review and opening SSH terminal")
                pendingAction = .openSSHTerminal
            } catch {
                AppLogger.app.error("SSH import deep link failed: \(error.localizedDescription)")
                pendingAction = .openSSHTerminal
            }
        }
    }

    private func handleAISetup(from url: URL, components: URLComponents?) {
        let scannedCode = components?.queryItems?.first(where: { $0.name == "payload" })?.value
            ?? url.absoluteString

        Task { @MainActor in
            do {
                let route = try await TalkieQRCodeRouter.route(scannedCode: scannedCode)

                let input: TalkieAIProviderCredentialIngestor.InputRoute
                switch route {
                case .aiProviderCredential(let payload):
                    input = .directCredential(payload)
                case .aiProviderCredentialSetup(let invite):
                    input = .setupInvite(invite)
                default:
                    AppLogger.app.warning("Deep link: AI setup payload had unexpected route")
                    aiSetupStatus = .failure(message: "This QR isn't an iPhone AI setup code.")
                    return
                }

                let result = try await TalkieAIProviderCredentialIngestor.shared.ingest(input)
                AppLogger.app.info(
                    "Deep link: imported iPhone AI credentials",
                    detail: "provider=\(result.providerId) model=\(result.modelId) handshake=\(result.viaSetupHandshake)"
                )
                aiSetupStatus = .success(providerName: result.providerName, modelId: result.modelId)
            } catch {
                AppLogger.app.error("Deep link: AI setup failed: \(error.localizedDescription)")
                aiSetupStatus = .failure(message: error.localizedDescription)
            }
        }
    }
}
