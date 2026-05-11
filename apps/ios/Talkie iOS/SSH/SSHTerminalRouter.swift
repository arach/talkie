//
//  SSHTerminalRouter.swift
//  Talkie iOS
//
//  Hardened routing and crash breadcrumbs for terminal presentation.
//

import Foundation
import Observation

@MainActor
@Observable
final class SSHTerminalRouter {
    enum Route: Equatable {
        case picker
        case editor(savedHostID: UUID?)
        case connecting(savedHostID: UUID?)
        case session(savedHostID: UUID?)
        case error(message: String)

        var name: String {
            switch self {
            case .picker:
                return "picker"
            case .editor:
                return "editor"
            case .connecting:
                return "connecting"
            case .session:
                return "session"
            case .error:
                return "error"
            }
        }
    }

    struct Breadcrumb: Codable, Sendable {
        let timestamp: Date
        let event: String
        let route: String
        let detail: String?
    }

    private struct PersistedState: Codable {
        var armedAt: Date?
        var armedRoute: String?
        var consecutiveUnsafeEntries: Int
        var breadcrumbs: [Breadcrumb]
    }

    static let shared = SSHTerminalRouter()

    private static let defaultsKey = "sshTerminal.routerState"
    private static let safeModeThreshold = 2
    private static let armedTTL: TimeInterval = 15 * 60

    private let defaults: UserDefaults

    private(set) var route: Route = .picker
    private(set) var isSafeMode = false
    private(set) var breadcrumbs: [Breadcrumb] = []

    @ObservationIgnored private var stabilityTask: Task<Void, Never>?
    @ObservationIgnored private var state: PersistedState

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        {
            state = decoded
        } else {
            state = PersistedState(armedAt: nil, armedRoute: nil, consecutiveUnsafeEntries: 0, breadcrumbs: [])
        }

        recoverIfNeeded()
        breadcrumbs = state.breadcrumbs
        isSafeMode = state.consecutiveUnsafeEntries >= Self.safeModeThreshold
    }

    func beginPresentation() {
        transition(to: .picker, detail: isSafeMode ? "safe-mode" : "normal")
    }

    func showEditor(savedHostID: UUID?) {
        transition(to: .editor(savedHostID: savedHostID), detail: nil)
    }

    func showConnecting(savedHostID: UUID?) {
        transition(to: .connecting(savedHostID: savedHostID), detail: nil)
    }

    func showSession(savedHostID: UUID?) {
        transition(to: .session(savedHostID: savedHostID), detail: nil)
    }

    func showError(_ message: String) {
        transition(to: .error(message: message), detail: message)
    }

    func markClosed() {
        stabilityTask?.cancel()
        stabilityTask = nil
        clearArmedEntry(resetUnsafeCount: true)
        appendBreadcrumb(event: "closed", route: route.name, detail: nil)
    }

    func exitSafeMode() {
        isSafeMode = false
        state.consecutiveUnsafeEntries = 0
        route = .picker
        appendBreadcrumb(event: "safe_mode_exited", route: route.name, detail: nil)
        persist()
    }

    private func transition(to route: Route, detail: String?) {
        self.route = route
        appendBreadcrumb(event: "route", route: route.name, detail: detail)
        armCurrentEntry(for: route)
    }

    private func recoverIfNeeded() {
        guard let armedAt = state.armedAt, let armedRoute = state.armedRoute else {
            return
        }

        let age = Date().timeIntervalSince(armedAt)
        guard age < Self.armedTTL else {
            state.armedAt = nil
            state.armedRoute = nil
            persist()
            return
        }

        state.consecutiveUnsafeEntries += 1
        appendBreadcrumb(
            event: "unclean_exit_detected",
            route: armedRoute,
            detail: "count=\(state.consecutiveUnsafeEntries)"
        )
        state.armedAt = nil
        state.armedRoute = nil
        persist()
    }

    private func armCurrentEntry(for route: Route) {
        stabilityTask?.cancel()
        state.armedAt = .now
        state.armedRoute = route.name
        persist()

        stabilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            self.markStable()
        }
    }

    private func markStable() {
        clearArmedEntry(resetUnsafeCount: true)
        appendBreadcrumb(event: "stable", route: route.name, detail: nil)
        if isSafeMode {
            isSafeMode = false
        }
        persist()
    }

    private func clearArmedEntry(resetUnsafeCount: Bool) {
        state.armedAt = nil
        state.armedRoute = nil
        if resetUnsafeCount {
            state.consecutiveUnsafeEntries = 0
        }
        isSafeMode = state.consecutiveUnsafeEntries >= Self.safeModeThreshold
        persist()
    }

    private func appendBreadcrumb(event: String, route: String, detail: String?) {
        let breadcrumb = Breadcrumb(timestamp: .now, event: event, route: route, detail: detail)
        state.breadcrumbs.insert(breadcrumb, at: 0)
        state.breadcrumbs = Array(state.breadcrumbs.prefix(40))
        breadcrumbs = state.breadcrumbs
        AppLogger.ui.info("Terminal breadcrumb: \(event) [\(route)]\(detail.map { " \($0)" } ?? "")")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
