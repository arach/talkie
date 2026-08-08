//
//  UpdateChecker.swift
//  Talkie
//
//  Checks Talkie's public update feed for app updates.
//

import Foundation
import SwiftUI
import TalkieKit

// MARK: - Update Info

struct AppUpdateInfo: Codable, Equatable {
    let version: String
    let buildNumber: Int?
    let downloadURL: URL
    let releaseNotes: String
    let publishedAt: Date
    let htmlURL: URL // Link to release page

    var displayVersion: String {
        if let build = buildNumber {
            return "\(version) (\(build))"
        }
        return version
    }
}

// MARK: - Update Checker

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let updateFeedURL = URL(
        string: "https://api.usetalkie.com/api/updates/macos/latest"
    )!

    // State
    @Published private(set) var availableUpdate: AppUpdateInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?

    // Settings
    @AppStorage("updateChecker.autoCheck") var autoCheckEnabled = true
    @AppStorage("updateChecker.lastCheckTime") private var lastCheckTimeInterval: Double = 0
    @AppStorage("updateChecker.skippedVersion") private var skippedVersion: String = ""

    private let log = Log(.system)
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {}

    // MARK: - Public API

    /// Check for updates (respects auto-check interval)
    func checkIfNeeded() async {
        guard autoCheckEnabled else { return }

        let now = Date()
        let lastCheck = Date(timeIntervalSince1970: lastCheckTimeInterval)

        // Skip if checked recently
        if now.timeIntervalSince(lastCheck) < checkInterval {
            log.debug("Skipping update check - last checked \(lastCheck)")
            return
        }

        await check()
    }

    /// Force check for updates (ignores interval)
    func check() async {
        guard !isChecking else { return }

        isChecking = true
        lastError = nil

        defer {
            isChecking = false
            lastChecked = Date()
            lastCheckTimeInterval = Date().timeIntervalSince1970
        }

        do {
            let update = try await fetchLatestRelease()

            if isNewerVersion(update.version) {
                // Skip if user chose to skip this version
                if update.version == skippedVersion {
                    log.info("Update \(update.version) available but user skipped it")
                    return
                }

                availableUpdate = update
                log.info("Update available: \(update.version)")
            } else {
                availableUpdate = nil
                log.info("App is up to date")
            }
        } catch {
            lastError = error.localizedDescription
            log.error("Update check failed: \(error)")
        }
    }

    /// Skip the current available update
    func skipCurrentUpdate() {
        if let update = availableUpdate {
            skippedVersion = update.version
            availableUpdate = nil
            log.info("Skipped update: \(update.version)")
        }
    }

    /// Open the download URL
    func downloadUpdate() {
        if let update = availableUpdate {
            NSWorkspace.shared.open(update.downloadURL)
        }
    }

    /// Open the release page
    func viewReleasePage() {
        if let update = availableUpdate {
            NSWorkspace.shared.open(update.htmlURL)
        }
    }

    // MARK: - Update Feed

    private func fetchLatestRelease() async throws -> AppUpdateInfo {
        var request = URLRequest(url: Self.updateFeedURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Talkie/\(Bundle.main.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppUpdateInfo.self, from: data)
        case 404:
            throw UpdateError.noReleasesFound
        case 429, 503:
            throw UpdateError.temporarilyUnavailable
        default:
            throw UpdateError.httpError(httpResponse.statusCode)
        }
    }

    private func isNewerVersion(_ remoteVersion: String) -> Bool {
        let currentVersion = Bundle.main.appVersion
        return remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case temporarilyUnavailable
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noReleasesFound:
            return "No releases found"
        case .temporarilyUnavailable:
            return "Update service unavailable - try again later"
        case .httpError(let code):
            return "Server error (\(code))"
        }
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var buildNumber: Int {
        guard let buildString = infoDictionary?["CFBundleVersion"] as? String else {
            return 0
        }
        return Int(buildString) ?? 0
    }
}
