//
//  UpdateChecker.swift
//  Talkie
//
//  Checks GitHub releases for app updates (no auth required for public repos).
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

    // Configuration - change these for your repo
    private let owner = "arach"
    private let repo = "talkie"
    private let assetNamePattern = "Talkie" // Looks for assets containing this

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
            let release = try await fetchLatestRelease()

            if let update = parseRelease(release), isNewerVersion(update.version) {
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

    // MARK: - GitHub API

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Talkie/\(Bundle.main.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GitHubRelease.self, from: data)
        case 404:
            throw UpdateError.noReleasesFound
        case 403:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.httpError(httpResponse.statusCode)
        }
    }

    private func parseRelease(_ release: GitHubRelease) -> AppUpdateInfo? {
        // Find the macOS app asset
        let asset = release.assets.first { asset in
            asset.name.contains(assetNamePattern) &&
            (asset.name.hasSuffix(".dmg") || asset.name.hasSuffix(".zip"))
        }

        guard let downloadAsset = asset,
              let downloadURL = URL(string: downloadAsset.browserDownloadUrl),
              let htmlURL = URL(string: release.htmlUrl) else {
            return nil
        }

        // Parse version from tag (e.g., "v2.1.0" -> "2.1.0")
        let version = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        // Try to extract build number from tag or name (e.g., "v2.1.0-42" or "2.1.0 (42)")
        let buildNumber = extractBuildNumber(from: release.tagName) ?? extractBuildNumber(from: release.name)

        return AppUpdateInfo(
            version: version,
            buildNumber: buildNumber,
            downloadURL: downloadURL,
            releaseNotes: release.body ?? "",
            publishedAt: release.publishedAt,
            htmlURL: htmlURL
        )
    }

    private func extractBuildNumber(from string: String) -> Int? {
        // Match patterns like "-42", "(42)", or "build 42"
        let patterns = [
            #"-(\d+)$"#,           // v2.1.0-42
            #"\((\d+)\)"#,         // 2.1.0 (42)
            #"build\s*(\d+)"#      // build 42
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
               let range = Range(match.range(at: 1), in: string) {
                return Int(string[range])
            }
        }
        return nil
    }

    private func isNewerVersion(_ remoteVersion: String) -> Bool {
        let currentVersion = Bundle.main.appVersion
        return remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending
    }
}

// MARK: - GitHub API Types

private struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let publishedAt: Date
    let assets: [GitHubAsset]
    let prerelease: Bool
    let draft: Bool
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
    let downloadCount: Int
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noReleasesFound:
            return "No releases found"
        case .rateLimited:
            return "Rate limited - try again later"
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
