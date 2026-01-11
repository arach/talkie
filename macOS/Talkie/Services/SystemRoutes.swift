//
//  SystemRoutes.swift
//  Talkie
//
//  Routes for system-level navigation and UI commands.
//  These handle internal app navigation and lifecycle events.
//

import Foundation
import AppKit

@MainActor
final class SystemRoutes: RouteGroup {
    static let scope: RouteScope = .system
    static let groupName = "System"
    static let shared = SystemRoutes()

    private init() {}

    lazy var routes: [Route] = [
        // MARK: - Navigation

        Route(
            path: "settings",
            description: "Open settings window",
            isInternal: false
        ) { _, params in
            let tab = params["tab"]
            NSLog("[SystemRoutes] Open settings, tab: \(tab ?? "default")")
            NotificationCenter.default.post(name: .openSettings, object: tab)
        },

        Route(
            path: "home",
            description: "Navigate to home view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate home")
            NotificationCenter.default.post(name: .navigateHome, object: nil)
        },

        Route(
            path: "live",
            description: "Navigate to live/dictation view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to live")
            NotificationCenter.default.post(name: .navigateLive, object: nil)
        },

        Route(
            path: "memos",
            description: "Navigate to memos view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to memos")
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.allMemos)
        },

        Route(
            path: "dictations",
            description: "Navigate to dictations view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to dictations")
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.liveRecent)
        },

        Route(
            path: "workflows",
            description: "Navigate to workflows view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to workflows")
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.workflows)
        },

        // MARK: - Window Management

        Route(
            path: "show",
            description: "Show main window and bring to front",
            isInternal: false
        ) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        },

        Route(
            path: "hide",
            description: "Hide main window",
            isInternal: false
        ) { _, _ in
            NSApp.hide(nil)
        },

        // MARK: - Debug

        Route(
            path: "debug/routes",
            description: "Print all registered routes",
            isInternal: true
        ) { _, _ in
            Router.shared.printAllRoutes()
        },

        Route(
            path: "debug/metrics",
            description: "Print router metrics",
            isInternal: true
        ) { _, _ in
            Router.shared.printMetrics()
        },
    ]
}

// MARK: - Notification Names

extension Notification.Name {
    static let openSettings = Notification.Name("com.jdi.talkie.openSettings")
    static let navigateHome = Notification.Name("com.jdi.talkie.navigateHome")
    static let navigateLive = Notification.Name("com.jdi.talkie.navigateLive")
}
