//
//  LiveRoutes.swift
//  Talkie
//
//  Routes for TalkieLive → Talkie communication.
//  These are internal sync routes, replacing XPC-based state monitoring.
//
//  Live sends URL notifications like:
//    talkie://recording/started
//    talkie://transcribing
//    talkie://dictation/new
//
//  This replaces TalkieLiveStateMonitor's XPC callbacks.
//

import Foundation
import TalkieKit

@MainActor
final class LiveRoutes: RouteGroup {
    static let scope: RouteScope = .live
    static let groupName = "Live"
    static let shared = LiveRoutes()

    private init() {}

    lazy var routes: [Route] = [
        // MARK: - Recording Lifecycle

        Route(
            path: "recording/started",
            description: "Live started recording - update state",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.updateFromNotification(
                state: .listening,
                elapsedTime: 0
            )
        },

        Route(
            path: "recording/stopped",
            description: "Live stopped recording - return to idle",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.updateFromNotification(
                state: .idle,
                elapsedTime: 0
            )
        },

        Route(
            path: "recording/cancelled",
            description: "Recording was cancelled/aborted",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.updateFromNotification(
                state: .idle,
                elapsedTime: 0
            )
        },

        // MARK: - Processing States

        Route(
            path: "transcribing",
            description: "Transcription in progress",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.updateFromNotification(
                state: .transcribing,
                elapsedTime: 0
            )
        },

        Route(
            path: "routing",
            description: "Output routing in progress (pasting, etc.)",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.updateFromNotification(
                state: .routing,
                elapsedTime: 0
            )
        },

        // MARK: - Data Events

        Route(
            path: "dictation/new",
            description: "New dictation stored - refresh data",
            isInternal: true
        ) { _, _ in
            DictationStore.shared.refresh()
        },

        Route(
            path: "memo",
            description: "New memo available",
            isInternal: true
        ) { _, params in
            if let id = params["id"] {
                NSLog("[LiveRoutes] New memo: \(id)")
            }
            DictationStore.shared.refresh()
        },

        Route(
            path: "queue/updated",
            description: "Pending queue count changed",
            isInternal: true
        ) { _, params in
            if let countStr = params["count"], let count = Int(countStr) {
                NSLog("[LiveRoutes] Queue updated: \(count) items")
            }
        },

        // MARK: - Live Lifecycle

        Route(
            path: "live/ready",
            description: "TalkieLive is ready and running",
            isInternal: true
        ) { _, _ in
            TalkieLiveStateMonitor.shared.refreshProcessId()
            NSLog("[LiveRoutes] Live service ready")
        },

        // MARK: - Errors

        Route(
            path: "error",
            description: "Live reported an error",
            isInternal: true
        ) { _, params in
            let message = params["msg"] ?? "Unknown error"
            NSLog("[LiveRoutes] Live error: \(message)")
        },
    ]
}
