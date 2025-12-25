//
//  Router.swift
//  Talkie
//
//  Central URL routing infrastructure for Talkie.
//  Provides structured, self-documenting, observable routing.
//
//  Replaces XPC-based TalkieLive communication with clean URL notifications.
//
//  Usage:
//    Router.shared.route(url)           // Route incoming URL
//    Router.shared.printAllRoutes()     // Debug: dump all routes
//    Router.shared.routes(for: .live)   // Query routes by scope
//

import Foundation
import AppKit
import os.signpost

// MARK: - Route Definition

/// A single route definition with metadata and handler
struct Route {
    let path: String
    let description: String
    let isInternal: Bool  // Internal sync vs public API
    let handler: @MainActor (URL, [String: String]) -> Void

    init(
        path: String,
        description: String,
        isInternal: Bool = true,
        handler: @escaping @MainActor (URL, [String: String]) -> Void
    ) {
        self.path = path
        self.description = description
        self.isInternal = isInternal
        self.handler = handler
    }
}

// MARK: - Route Scope

/// Logical grouping of routes by purpose
enum RouteScope: String, CaseIterable {
    case app      // External app shortcuts (Shortcuts.app, Alfred, etc.)
    case live     // TalkieLive → Talkie internal sync
    case system   // Navigation, lifecycle, UI commands

    var displayName: String {
        switch self {
        case .app: return "App Shortcuts"
        case .live: return "Live Sync"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .app: return "🔌"
        case .live: return "🎙️"
        case .system: return "⚙️"
        }
    }
}

// MARK: - Route Group Protocol

/// Protocol for grouped route definitions
@MainActor
protocol RouteGroup {
    static var scope: RouteScope { get }
    static var groupName: String { get }
    var routes: [Route] { get }
}

extension RouteGroup {
    /// Print all routes in this group (for debugging)
    func printRoutes() {
        let scope = Self.scope
        print("\(scope.icon) [\(Self.groupName)] Routes (\(scope.displayName)):")
        for route in routes {
            let visibility = route.isInternal ? "internal" : "public"
            print("  • \(route.path) [\(visibility)]")
            print("    └─ \(route.description)")
        }
    }
}

// MARK: - Router Log Level

enum RouterLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

// MARK: - Router Metrics

/// Metrics for route handling
struct RouteMetrics {
    var totalRouted: Int = 0
    var totalUnknown: Int = 0
    var routeCounts: [String: Int] = [:]
    var lastRouteTime: Date?
    var averageHandleTimeMs: Double = 0
    private var handleTimeSamples: [Double] = []

    mutating func recordRoute(_ path: String, handleTimeMs: Double) {
        totalRouted += 1
        routeCounts[path, default: 0] += 1
        lastRouteTime = Date()

        handleTimeSamples.append(handleTimeMs)
        if handleTimeSamples.count > 100 {
            handleTimeSamples.removeFirst()
        }
        averageHandleTimeMs = handleTimeSamples.reduce(0, +) / Double(handleTimeSamples.count)
    }

    mutating func recordUnknown() {
        totalUnknown += 1
    }
}

// MARK: - Central Router

@MainActor
final class Router {
    static let shared = Router()

    // Route lookup
    private var routeMap: [String: Route] = [:]
    private let groups: [any RouteGroup]

    // Observability
    private(set) var metrics = RouteMetrics()
    var isLoggingEnabled = true

    // Signpost integration for Instruments profiling
    private let signpostLog = OSLog(subsystem: "com.jdi.talkie", category: "Router")
    private let signposter: OSSignposter

    // Gating (for feature flags, debug modes)
    var disabledRoutes: Set<String> = []

    private init() {
        signposter = OSSignposter(logHandle: signpostLog)

        groups = [
            LiveRoutes.shared,
            AppRoutes.shared,
            SystemRoutes.shared,
        ]

        // Build lookup map with collision detection
        for group in groups {
            for route in group.routes {
                if routeMap[route.path] != nil {
                    log(.warning, "Route collision detected: '\(route.path)' - overwriting")
                    #if DEBUG
                    assertionFailure("Route collision: \(route.path)")
                    #endif
                }
                routeMap[route.path] = route
            }
        }

        log(.info, "Router initialized with \(routeMap.count) routes")
    }

    // MARK: - Routing

    /// Route a URL to its handler
    /// - Returns: true if route was handled, false if unknown
    @discardableResult
    func route(_ url: URL) -> Bool {
        let path = extractPath(from: url)
        let params = extractParams(from: url)

        // Check if route exists (exact match first, then prefix match)
        let route: Route?
        if let exactMatch = routeMap[path] {
            route = exactMatch
        } else {
            // Try prefix match for routes with path parameters (e.g., "memo/123" -> "memo")
            let basePath = path.split(separator: "/").first.map(String.init) ?? path
            route = routeMap[basePath]
        }

        guard let route else {
            // Emit signpost event for unknown route
            signposter.emitEvent("Unknown Route", "\(path)")
            log(.warning, "Unknown route: \(path)")
            metrics.recordUnknown()
            return false
        }

        let routePath = route.path  // Use route's canonical path for metrics

        // Check if route is disabled
        if disabledRoutes.contains(routePath) {
            signposter.emitEvent("Disabled Route", "\(routePath)")
            log(.info, "Route disabled: \(path)")
            return false
        }

        // Execute with instrumentation + signpost interval
        log(.info, "→ \(routePath)" + (params.isEmpty ? "" : " \(params)"))

        // Begin signpost interval - shows up in Instruments as a timed region
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Route", id: signpostID, "\(routePath)")

        let start = CFAbsoluteTimeGetCurrent()
        route.handler(url, params)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // End signpost interval with metadata
        signposter.endInterval("Route", state, "\(routePath) completed in \(String(format: "%.2f", elapsedMs))ms")

        metrics.recordRoute(routePath, handleTimeMs: elapsedMs)
        log(.debug, "← \(routePath) (\(String(format: "%.2f", elapsedMs))ms)")

        return true
    }

    /// Check if a URL can be routed
    func canRoute(_ url: URL) -> Bool {
        let path = extractPath(from: url)
        return routeMap[path] != nil && !disabledRoutes.contains(path)
    }

    /// Check if URL is a Talkie route (any scheme starting with "talkie")
    nonisolated static func isTalkieURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return scheme.hasPrefix("talkie")
    }

    // MARK: - Gating

    func enable(_ path: String) {
        disabledRoutes.remove(path)
        log(.info, "Route enabled: \(path)")
    }

    func disable(_ path: String) {
        disabledRoutes.insert(path)
        log(.info, "Route disabled: \(path)")
    }

    func isEnabled(_ path: String) -> Bool {
        !disabledRoutes.contains(path)
    }

    // MARK: - Discovery

    /// Print all registered routes (for debugging)
    func printAllRoutes() {
        print("")
        print("╔══════════════════════════════════════╗")
        print("║       REGISTERED ROUTES              ║")
        print("╚══════════════════════════════════════╝")
        print("")

        for group in groups {
            group.printRoutes()
            print("")
        }

        print("Total: \(routeMap.count) routes")
        print("")
    }

    /// Get all routes for a specific scope
    func routes(for scope: RouteScope) -> [Route] {
        groups.first { type(of: $0).scope == scope }?.routes ?? []
    }

    /// Get all registered paths
    var allPaths: [String] {
        Array(routeMap.keys).sorted()
    }

    /// Get route info by path
    func route(for path: String) -> Route? {
        routeMap[path]
    }

    // MARK: - Metrics

    func printMetrics() {
        print("")
        print("╔══════════════════════════════════════╗")
        print("║       ROUTER METRICS                 ║")
        print("╚══════════════════════════════════════╝")
        print("")
        print("Total routed: \(metrics.totalRouted)")
        print("Total unknown: \(metrics.totalUnknown)")
        print("Avg handle time: \(String(format: "%.2f", metrics.averageHandleTimeMs))ms")
        print("")
        print("Route counts:")
        for (path, count) in metrics.routeCounts.sorted(by: { $0.value > $1.value }) {
            print("  \(path): \(count)")
        }
        print("")
    }

    func resetMetrics() {
        metrics = RouteMetrics()
    }

    // MARK: - URL Parsing

    private func extractPath(from url: URL) -> String {
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.dropFirst()
        let path = pathComponents.joined(separator: "/")
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    private func extractParams(from url: URL) -> [String: String] {
        var params: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                params[item.name] = item.value ?? ""
            }
        }
        return params
    }

    // MARK: - Logging

    private func log(_ level: RouterLogLevel, _ message: String) {
        guard isLoggingEnabled else { return }
        NSLog("[Router:\(level.rawValue)] \(message)")
    }

    // MARK: - Signpost Helpers

    /// Emit a single signpost event (for point-in-time markers)
    func emitSignpost(_ name: StaticString, _ message: String = "") {
        signposter.emitEvent(name, "\(message)")
    }

    /// Execute a block with automatic signpost interval tracking
    func withSignpost<T>(_ name: StaticString, _ message: String = "", _ block: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(message)")
        defer { signposter.endInterval(name, state) }
        return try block()
    }

    /// Execute an async block with automatic signpost interval tracking
    func withSignpost<T>(_ name: StaticString, _ message: String = "", _ block: () async throws -> T) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(message)")
        defer { signposter.endInterval(name, state) }
        return try await block()
    }

    /// Access the underlying signposter for advanced usage
    var instrumentsSignposter: OSSignposter { signposter }
}

// MARK: - Debug Helpers

#if DEBUG
extension Router {
    /// Simulate a route for testing
    func simulateRoute(_ path: String, params: [String: String] = [:]) {
        let scheme = "talkie-dev"
        var urlString = "\(scheme)://\(path)"
        if !params.isEmpty {
            let query = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            urlString += "?\(query)"
        }
        if let url = URL(string: urlString) {
            route(url)
        }
    }
}
#endif
