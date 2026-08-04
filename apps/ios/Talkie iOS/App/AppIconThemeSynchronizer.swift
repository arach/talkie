//
//  AppIconThemeSynchronizer.swift
//  Talkie iOS
//
//  Keeps the Home Screen icon aligned with Talkie's selected visual theme.
//

import UIKit

extension AppTheme {
    /// Porcelain is the primary AppIcon asset. Every other theme resolves to
    /// an alternate app-icon set compiled from the same Talkie glyph geometry.
    var alternateAppIconName: String? {
        switch self {
        case .porcelain: nil
        case .scope: "AppIconScope"
        case .mineral: "AppIconMineral"
        case .midnight: "AppIconMidnight"
        case .tactical: "AppIconTactical"
        case .ghost: "AppIconGhost"
        case .lift: "AppIconLift"
        case .graphite: "AppIconGraphite"
        case .carbon: "AppIconCarbon"
        case .ember: "AppIconEmber"
        }
    }
}

@MainActor
enum AppIconThemeSynchronizer {
    static func synchronize(with theme: AppTheme) async {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return }

        let desiredIconName = theme.alternateAppIconName
        guard application.alternateIconName != desiredIconName else { return }

        do {
            try await application.setAlternateIconName(desiredIconName)
            AppLogger.app.info("App icon synchronized with theme: \(theme.rawValue)")
        } catch {
            AppLogger.app.warning(
                "App icon theme synchronization failed: \(error.localizedDescription)"
            )
        }
    }
}
