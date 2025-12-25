//
//  AppRoutes.swift
//  Talkie
//
//  Routes for external app integration (Shortcuts.app, Alfred, etc.)
//  These are public API routes that external apps can invoke.
//

import Foundation

@MainActor
final class AppRoutes: RouteGroup {
    static let scope: RouteScope = .app
    static let groupName = "App"
    static let shared = AppRoutes()

    private init() {}

    lazy var routes: [Route] = [
        // MARK: - Recording Control

        Route(
            path: "start",
            description: "Start a new recording",
            isInternal: false
        ) { _, _ in
            ServiceManager.shared.live.toggleRecording()
        },

        Route(
            path: "stop",
            description: "Stop current recording",
            isInternal: false
        ) { _, _ in
            ServiceManager.shared.live.toggleRecording()
        },

        Route(
            path: "toggle",
            description: "Toggle recording state",
            isInternal: false
        ) { _, _ in
            ServiceManager.shared.live.toggleRecording()
        },

        // MARK: - Quick Actions

        Route(
            path: "capture",
            description: "Quick capture - start recording immediately",
            isInternal: false
        ) { _, _ in
            // Only start if not already recording
            if !ServiceManager.shared.live.isRecording {
                ServiceManager.shared.live.toggleRecording()
            }
        },
    ]
}
