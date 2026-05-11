//
//  FeatureFlags.swift
//  Talkie iOS
//
//  Runtime feature flags for gating functionality.
//  Set flags to false to hide features before App Store submission.
//

import Foundation

/// Feature flags for controlling app functionality
/// Toggle these to show/hide features without recompiling
enum FeatureFlags {
    private static let launchArguments = ProcessInfo.processInfo.arguments

    // MARK: - Connectivity

    /// Show Connection Center in Settings (Mac Mini bridge, etc.)
    /// Set to `false` for App Store builds
    static var showConnectionCenter: Bool {
        launchArguments.contains("--enableConnectionCenter")
    }

    // MARK: - Future Flags

    // Add new feature flags here as needed
    // static let showExperimentalUI = false
    // static let enableBetaFeatures = false
}
