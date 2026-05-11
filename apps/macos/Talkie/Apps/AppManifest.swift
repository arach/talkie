//
//  AppManifest.swift
//  Talkie
//
//  Model for app manifest.json (follows Chrome extension conventions).
//  Each app has a manifest that describes its metadata, permissions, and entry points.
//

import Foundation

// MARK: - App Manifest

struct AppManifest: Codable, Identifiable {
    // MARK: - Required Fields

    let manifestVersion: Int
    let name: String
    let version: String

    // MARK: - Optional Metadata

    var description: String?
    var author: String?
    var homepageUrl: String?

    // MARK: - Permissions

    var permissions: [Permission]?

    // MARK: - Entry Points

    var background: BackgroundScript?
    var settingsPanel: String?  // Relative path to settings HTML

    // MARK: - Widget

    var widget: WidgetConfig?  // Inline widget rendered on Home page

    // MARK: - Icons

    var icons: [String: String]?  // Size -> path, e.g. "32": "icons/icon-32.png"

    // MARK: - Identifiable

    var id: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name, version, description, author
        case homepageUrl = "homepage_url"
        case permissions, background, widget
        case settingsPanel = "settings_panel"
        case icons
    }
}

// MARK: - Background Script

struct BackgroundScript: Codable {
    let script: String  // Relative path to background.js
}

// MARK: - Widget Config

struct WidgetConfig: Codable {
    let html: String              // Relative path to widget HTML file
    let size: WidgetSize          // Widget size on home page

    enum WidgetSize: String, Codable {
        case half
        case full
    }
}

// MARK: - Permissions

enum Permission: String, Codable, CaseIterable {
    case storage           // talkie.storage.* API
    case notifications     // talkie.notifications.* API
    case state             // talkie.state.* API (read app state)
    case clipboard         // talkie.clipboard.* API

    var description: String {
        switch self {
        case .storage: return "Store and retrieve data"
        case .notifications: return "Show toast notifications"
        case .state: return "Read app statistics"
        case .clipboard: return "Access clipboard"
        }
    }
}

// MARK: - Loaded App

/// Represents a loaded app with its manifest and runtime state
struct LoadedApp: Identifiable {
    let id: String
    let manifest: AppManifest
    let directory: URL
    let isBundled: Bool

    var backgroundScriptURL: URL? {
        guard let bg = manifest.background else { return nil }
        return directory.appendingPathComponent(bg.script)
    }

    var settingsPanelURL: URL? {
        guard let panel = manifest.settingsPanel else { return nil }
        return directory.appendingPathComponent(panel)
    }

    var widgetURL: URL? {
        guard let widget = manifest.widget else { return nil }
        return directory.appendingPathComponent(widget.html)
    }

    var widgetSize: WidgetConfig.WidgetSize? {
        manifest.widget?.size
    }

    func iconURL(size: Int) -> URL? {
        let sizeKey = "\(size)"
        guard let iconPath = manifest.icons?[sizeKey] else { return nil }
        return directory.appendingPathComponent(iconPath)
    }

    // Status
    var isEnabled: Bool = true
    var isLoaded: Bool = false
    var loadError: String?
    var loadedAt: Date?
}

// MARK: - Manifest Parsing

extension AppManifest {
    /// Load manifest from a directory
    static func load(from directory: URL) throws -> AppManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AppManifest.self, from: data)
    }

    /// Validate manifest
    func validate() throws {
        if manifestVersion != 1 {
            throw ManifestError.unsupportedVersion(manifestVersion)
        }
        if name.isEmpty {
            throw ManifestError.missingField("name")
        }
        if version.isEmpty {
            throw ManifestError.missingField("version")
        }
        // An app needs at least a background script or a widget
        if background == nil && widget == nil {
            throw ManifestError.missingField("background.script or widget")
        }
    }
}

// MARK: - Manifest Errors

enum ManifestError: LocalizedError {
    case unsupportedVersion(Int)
    case missingField(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Unsupported manifest version: \(v). Expected 1."
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}
