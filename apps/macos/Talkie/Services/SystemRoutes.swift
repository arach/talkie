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

    lazy var routes: [Route] = {
        var routes: [Route] = [
        // MARK: - Navigation

        Route(
            path: "settings",
            description: "Open settings window",
            isInternal: false
        ) { url, params in
            let pathTab = url.pathComponents.dropFirst().first
            let tab = params["tab"] ?? pathTab
            NSLog("[SystemRoutes] Open settings, tab: \(tab ?? "default")")
            if let tab,
               let section = SettingsSection(rawValue: tab) ?? SettingsSection.from(path: tab) {
                NavigationState.shared.navigateToSettings(section)
            } else {
                NavigationState.shared.navigate(to: .settings)
            }
        },

        Route(
            path: "home",
            description: "Navigate to home view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate home")
            NavigationState.shared.navigateToHome()
        },

        Route(
            path: "live",
            description: "Navigate to agent view (legacy live alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to live")
            NavigationState.shared.navigateToAgent()
        },

        Route(
            path: "agent",
            description: "Navigate to agent dashboard",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to agent")
            NavigationState.shared.navigateToAgent()
        },

        Route(
            path: "a",
            description: "Navigate to agent dashboard (short alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to agent (short alias)")
            NavigationState.shared.navigateToAgent()
        },

        Route(
            path: "memos",
            description: "Navigate to memos view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to memos")
            NavigationState.shared.navigateToAllMemos()
        },

        Route(
            path: "recordings",
            description: "Navigate to unified library",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to recordings")
            NavigationState.shared.navigate(to: .recordings)
        },

        Route(
            path: "library",
            description: "Navigate to unified library",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to library")
            NavigationState.shared.navigate(to: .recordings)
        },

        Route(
            path: "dictations",
            description: "Navigate to dictations view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to dictations")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "live/recent",
            description: "Navigate to recent agent dictations (legacy live alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to live/recent")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "agent/recent",
            description: "Navigate to recent agent dictations",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to agent/recent")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "a/recent",
            description: "Navigate to recent agent dictations (short alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to a/recent")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "live/history",
            description: "Navigate to agent history (legacy live alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to live/history")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "agent/history",
            description: "Navigate to agent history",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to agent/history")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "a/history",
            description: "Navigate to agent history (short alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to a/history")
            NavigationState.shared.navigateToDictations()
        },

        Route(
            path: "settings/live",
            description: "Open agent settings tab (legacy live alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Open settings/live")
            NavigationState.shared.navigateToSettings(.dictationCapture)
        },

        Route(
            path: "settings/agent",
            description: "Open agent settings tab",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Open settings/agent")
            NavigationState.shared.navigateToSettings(.dictationCapture)
        },

        Route(
            path: "settings/a",
            description: "Open agent settings tab (short alias)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Open settings/a")
            NavigationState.shared.navigateToSettings(.dictationCapture)
        },

        Route(
            path: "workflows",
            description: "Navigate to workflows view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to workflows")
            NavigationState.shared.navigateToWorkflows()
        },

        Route(
            path: "compose",
            description: "Navigate to compose view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to compose")
            NavigationState.shared.navigateToCompose()
        },

        Route(
            path: "notes",
            description: "Navigate to notes view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to notes")
            NavigationState.shared.navigate(to: .notes)
        },

        Route(
            path: "screenshots",
            description: "Navigate to screenshots view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to screenshots")
            NavigationState.shared.navigate(to: .screenshots)
        },

        Route(
            path: "capture/markup",
            description: "Open ephemeral capture markup bay for a screenshot file",
            isInternal: false
        ) { _, params in
            guard let path = params["path"], !path.isEmpty else {
                NSLog("[SystemRoutes] capture/markup missing path param")
                return
            }
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            let instruction = params["instruction"]
            CaptureMarkupCoordinator.shared.openSessionIfNeeded(
                imageURL: url,
                instruction: instruction?.isEmpty == true ? nil : instruction
            )
        },

        Route(
            path: "models",
            description: "Navigate to models view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to models")
            NavigationState.shared.navigate(to: .models)
        },

        Route(
            path: "console",
            description: "Navigate to system console",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to console")
            NavigationState.shared.navigateToConsole()
        },

        Route(
            path: "stats",
            description: "Navigate to stats view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to stats")
            NavigationState.shared.navigate(to: .liveDashboard)
        },

        Route(
            path: "pending",
            description: "Navigate to pending actions",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to pending actions")
            NavigationState.shared.navigate(to: .pendingActions)
        },

        Route(
            path: "ai-results",
            description: "Navigate to AI results",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to AI results")
            NavigationState.shared.navigate(to: .aiResults)
        },

        Route(
            path: "context",
            description: "Navigate to context rules view",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to context")
            NavigationState.shared.navigate(to: .contextRules)
        },

        Route(
            path: "feedback",
            description: "Open feedback form for quick report submission",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to feedback")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NavigationState.shared.navigateToSettings(.feedback)
        },

        Route(
            path: "report",
            description: "Open feedback form (alias for feedback)",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Navigate to report (feedback alias)")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NavigationState.shared.navigateToSettings(.feedback)
        },

        // MARK: - Onboarding

        Route(
            path: "onboarding/pro",
            description: "Launch Pro Tools onboarding",
            isInternal: false
        ) { _, _ in
            NSLog("[SystemRoutes] Launch Pro Tools onboarding")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            ProOnboardingManager.shared.shouldShowProOnboarding = true
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

        #if DEBUG
        routes += [
            Route(
                path: "design",
                description: "Navigate to design mode home",
                isInternal: false
            ) { _, _ in
                NSLog("[SystemRoutes] Navigate to design home")
                DesignModeManager.shared.isEnabled = true
                NavigationState.shared.navigate(to: .designHome)
            },

            Route(
                path: "design/audit",
                description: "Navigate to design audit",
                isInternal: false
            ) { _, _ in
                NSLog("[SystemRoutes] Navigate to design audit")
                DesignModeManager.shared.isEnabled = true
                NavigationState.shared.navigate(to: .designAudit)
            },

            Route(
                path: "design/components",
                description: "Navigate to design components",
                isInternal: false
            ) { _, _ in
                NSLog("[SystemRoutes] Navigate to design components")
                DesignModeManager.shared.isEnabled = true
                NavigationState.shared.navigate(to: .designComponents)
            },
        ]
        #endif

        return routes
    }()
}

// MARK: - Notification Names

extension Notification.Name {
    static let openSettings = Notification.Name("to.talkie.app.openSettings")
    static let navigateHome = Notification.Name("to.talkie.app.navigateHome")
    static let navigateAgent = Notification.Name("to.talkie.app.navigateAgent")
    /// Posted by the `Find…` menu item (⌘F). ScopeLibraryView listens and
    /// focuses its search field; nav to .recordings happens alongside the
    /// post so it works from anywhere in the app.
    static let focusLibrarySearch = Notification.Name("to.talkie.app.focusLibrarySearch")
    @available(*, deprecated, renamed: "navigateAgent")
    static let navigateLive = navigateAgent
}
