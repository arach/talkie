//
//  XPCServiceManager.swift
//  Talkie
//
//  Unified XPC service connection management with environment-aware discovery
//  Handles connection lifecycle, environment detection, and reconnection logic
//

import Foundation
import Combine
import TalkieKit

private let log = Log(.xpc)

/// Connection state for XPC services
public enum XPCConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case failed
}

/// Atomic connection info - all state changes together
public struct ConnectionInfo: Sendable {
    public let state: XPCConnectionState
    public let environment: TalkieEnvironment?
    public let isConnected: Bool

    public static let disconnected = ConnectionInfo(
        state: .disconnected,
        environment: nil,
        isConnected: false
    )

    public static let connecting = ConnectionInfo(
        state: .connecting,
        environment: nil,
        isConnected: false
    )

    public static let failed = ConnectionInfo(
        state: .failed,
        environment: nil,
        isConnected: false
    )

    public static func connected(to environment: TalkieEnvironment) -> ConnectionInfo {
        ConnectionInfo(
            state: .connected,
            environment: environment,
            isConnected: true
        )
    }
}

/// Generic XPC service manager with environment-aware connection
@MainActor
public class XPCServiceManager<ServiceProtocol> {
    // MARK: - Published State

    @Published public private(set) var connectionInfo: ConnectionInfo = .disconnected

    // Computed properties for backwards compatibility
    public var connectedMode: TalkieEnvironment? { connectionInfo.environment }
    public var connectionState: XPCConnectionState { connectionInfo.state }
    public var isConnected: Bool { connectionInfo.isConnected }

    // MARK: - Configuration

    private let serviceNameProvider: (TalkieEnvironment) -> String
    private let interfaceProvider: () -> NSXPCInterface
    private let exportedInterface: NSXPCInterface?
    private var exportedObject: AnyObject?

    /// Optional endpoint fetcher for services that use anonymous listeners
    /// When set, connection will use the endpoint instead of Mach service name
    public var endpointFetcher: (() async -> NSXPCListenerEndpoint?)?

    // MARK: - Connection State

    private var xpcConnection: NSXPCConnection?
    private var isConnecting = false
    private var retryCount = 0
    private let maxRetries = 3
    private var hasAttemptedAutoLaunch = false

    /// Optional handler to launch the service when connection fails
    /// Called once per connect() attempt before giving up
    public var autoLaunchHandler: (() -> Void)?

    /// Optional verifier to confirm connection liveness after XPC handshake.
    /// Called with the remote proxy — should return true if the service responds.
    /// Without this, connections are assumed live after a brief delay (which can false-positive).
    public var connectionVerifier: ((_ proxy: ServiceProtocol) async -> Bool)?

    /// Environment to try first when opening the Mach service.
    /// Defaults to the current app environment, but callers can point helpers at
    /// an override environment (for example, when a dev app explicitly targets prod helpers).
    public var preferredEnvironmentProvider: () -> TalkieEnvironment = { TalkieEnvironment.current }

    /// Whether failed connections should probe other environments.
    /// Helper clients usually want this off so dev doesn't silently attach to prod.
    public var allowsCrossEnvironmentFallback = true

    // MARK: - Heartbeat & Auto-Reconnect

    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30.0
    private var consecutiveHeartbeatFailures = 0
    private let maxHeartbeatFailures = 2

    /// Enable/disable auto-reconnect on disconnection (default: true)
    public var autoReconnectEnabled = true

    /// Reconnect attempt tracking for graduated backoff
    private var reconnectAttempt = 0
    private var firstAttemptTime: Date?
    private var reconnectTask: Task<Void, Never>?

    /// Track when connection was established (for stable connection detection)
    private var connectionEstablishedAt: Date?
    private let stableConnectionThreshold: TimeInterval = 10.0  // Must be connected 10s to reset backoff

    /// Graduated backoff: aggressive at first, then backs off
    /// - First 10s: retry every 2s
    /// - 10s-40s: retry every 30s
    /// - 40s-2min: retry every 1min
    /// - After 2min: retry every 10min
    private func calculateReconnectDelay() -> TimeInterval {
        guard let firstTime = firstAttemptTime else {
            return 2.0
        }

        let elapsed = Date().timeIntervalSince(firstTime)

        if elapsed < 10 {
            return 2.0       // First 10s: every 2s
        } else if elapsed < 40 {
            return 30.0      // Next 30s: every 30s
        } else if elapsed < 120 {
            return 60.0      // Next ~1.5min: every 1min
        } else {
            return 600.0     // After 2min: every 10min
        }
    }

    /// Reset backoff state (call when connection succeeds)
    private func resetBackoff() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        firstAttemptTime = nil
    }

    // MARK: - Initialization

    /// Create a new XPC service manager
    /// - Parameters:
    ///   - serviceNameProvider: Function that returns XPC service name for each environment
    ///   - interfaceProvider: Function that creates the remote object interface
    ///   - exportedInterface: Optional interface for receiving callbacks
    ///   - exportedObject: Optional object that implements the exported interface
    public init(
        serviceNameProvider: @escaping (TalkieEnvironment) -> String,
        interfaceProvider: @escaping () -> NSXPCInterface,
        exportedInterface: NSXPCInterface? = nil,
        exportedObject: AnyObject? = nil
    ) {
        self.serviceNameProvider = serviceNameProvider
        self.interfaceProvider = interfaceProvider
        self.exportedInterface = exportedInterface
        self.exportedObject = exportedObject
    }

    // MARK: - Configuration Updates

    /// Set the exported object (must be called before connecting if using callbacks)
    public func setExportedObject(_ object: AnyObject) {
        exportedObject = object
    }

    // MARK: - Connection Management

    /// Connect to XPC service, trying the preferred environment first and
    /// optionally falling back to the others.
    public func connect() async {
        guard !isConnecting, xpcConnection == nil else { return }

        isConnecting = true
        connectionInfo = .connecting

        let currentEnv = preferredEnvironmentProvider()
        if await tryConnect(to: currentEnv) {
            isConnecting = false
            return
        }

        if allowsCrossEnvironmentFallback {
            let envOrder: [TalkieEnvironment] = [.production, .dev].filter { $0 != currentEnv }
            for env in envOrder {
                if await tryConnect(to: env) {
                    isConnecting = false
                    return
                }
            }
        }

        // All attempts failed - try auto-launching the service once
        if !hasAttemptedAutoLaunch, let launchHandler = autoLaunchHandler {
            hasAttemptedAutoLaunch = true
            log.info(" 🚀 Auto-launching service and retrying...")
            launchHandler()

            // Wait for service to start (up to 3 seconds)
            try? await Task.sleep(for: .seconds(2))

            if await tryConnect(to: preferredEnvironmentProvider()) {
                isConnecting = false
                hasAttemptedAutoLaunch = false  // Reset for future reconnects
                return
            }
        }

        isConnecting = false
        connectionInfo = .failed
        hasAttemptedAutoLaunch = false  // Reset for manual retry

        log.info(" ❌ Failed to connect to any environment")
        scheduleReconnect()
    }

    /// Try connecting to a specific environment
    private func tryConnect(to environment: TalkieEnvironment) async -> Bool {
        let serviceName = serviceNameProvider(environment)

        // If endpoint fetcher is set, use endpoint-based connection
        if let endpointFetcher = endpointFetcher {
            guard let endpoint = await endpointFetcher() else {
                log.info(" No endpoint available from fetcher")
                return false
            }
            log.info(" Using endpoint from fetcher for \(serviceName)")
            return await tryConnectWithEndpoint(endpoint, environment: environment)
        }

        return await withCheckedContinuation { continuation in
            let conn = NSXPCConnection(machServiceName: serviceName)
            conn.remoteObjectInterface = interfaceProvider()

            if let exportedInterface = exportedInterface {
                conn.exportedInterface = exportedInterface
                conn.exportedObject = exportedObject
                log.info(" Setting exported object: \(exportedObject != nil ? "✓ Set" : "❌ NIL")")
            }

            let lock = NSLock()
            var completed = false

            // Set up handlers
            conn.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Check if connection was stable before resetting backoff
                    let wasStable: Bool
                    if let established = self.connectionEstablishedAt {
                        let duration = Date().timeIntervalSince(established)
                        wasStable = duration >= self.stableConnectionThreshold
                        log.info(" Connection invalidated after \(String(format: "%.1f", duration))s (stable: \(wasStable))")
                    } else {
                        wasStable = false
                        log.info(" Connection invalidated: \(serviceName)")
                    }

                    self.stopHeartbeat()
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected
                    self.connectionEstablishedAt = nil

                    // Reset backoff if connection was stable
                    if wasStable {
                        self.resetBackoff()
                    }
                    // Graduated backoff is time-based, so no need to manually increase

                    // Auto-reconnect on invalidation
                    if self.autoReconnectEnabled {
                        self.scheduleReconnect()
                    }
                }
            }

            conn.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    log.info(" Connection interrupted: \(serviceName)")

                    // Clear connection state to allow reconnection
                    self.stopHeartbeat()
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected

                    // Auto-reconnect with exponential backoff
                    if self.autoReconnectEnabled {
                        self.scheduleReconnect()
                    }
                }
            }

            conn.resume()

            // Get proxy and set up error detection
            let _ = conn.remoteObjectProxyWithErrorHandler { error in
                lock.lock()
                defer { lock.unlock() }
                if !completed {
                    completed = true
                    log.info(" ❌ Connection failed to \(serviceName): \(error.localizedDescription)")
                    conn.invalidate()
                    continuation.resume(returning: false)
                }
            } as AnyObject

            // If we have a verifier, use it to confirm liveness via ping.
            // Otherwise fall back to the brief delay heuristic.
            if let verifier = self.connectionVerifier {
                // Give XPC errors a moment to surface first
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    lock.lock()
                    if completed {
                        lock.unlock()
                        return
                    }
                    lock.unlock()

                    // XPC didn't error — now verify with a real ping
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                            return
                        }

                        // Use error-handling proxy to catch XPC failures during verification
                        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); conn.invalidate(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                        }) as? ServiceProtocol else {
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); conn.invalidate(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                            return
                        }

                        let alive = await verifier(proxy)

                        lock.lock()
                        guard !completed else { lock.unlock(); return }
                        completed = true
                        lock.unlock()

                        if alive {
                            self.xpcConnection = conn
                            self.connectionInfo = .connected(to: environment)
                            self.retryCount = 0
                            self.consecutiveHeartbeatFailures = 0
                            self.connectionEstablishedAt = Date()
                            self.resetBackoff()
                            log.info(" ✅ Connected to \(serviceName) (\(environment.displayName)) — verified")
                            self.startHeartbeat()
                            continuation.resume(returning: true)
                        } else {
                            log.info(" ❌ Connected to \(serviceName) but ping verification failed")
                            conn.invalidate()
                            continuation.resume(returning: false)
                        }
                    }
                }
            } else {
                // No verifier — use brief delay heuristic (legacy behavior)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    lock.lock()
                    if !completed {
                        completed = true
                        lock.unlock()

                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.xpcConnection = conn
                            self.connectionInfo = .connected(to: environment)
                            self.retryCount = 0
                            self.consecutiveHeartbeatFailures = 0
                            self.connectionEstablishedAt = Date()
                            self.resetBackoff()

                            log.info(" ✅ Connected to \(serviceName) (\(environment.displayName))")
                            self.startHeartbeat()
                        }

                        continuation.resume(returning: true)
                    } else {
                        lock.unlock()
                    }
                }
            }
        }
    }

    /// Try connecting using an endpoint (for anonymous listener services)
    private func tryConnectWithEndpoint(_ endpoint: NSXPCListenerEndpoint, environment: TalkieEnvironment) async -> Bool {
        return await withCheckedContinuation { continuation in
            let conn = NSXPCConnection(listenerEndpoint: endpoint)
            conn.remoteObjectInterface = interfaceProvider()

            if let exportedInterface = exportedInterface {
                conn.exportedInterface = exportedInterface
                conn.exportedObject = exportedObject
            }

            let lock = NSLock()
            var completed = false

            conn.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    let wasStable: Bool
                    if let established = self.connectionEstablishedAt {
                        let duration = Date().timeIntervalSince(established)
                        wasStable = duration >= self.stableConnectionThreshold
                        log.info(" Connection (endpoint) invalidated after \(String(format: "%.1f", duration))s")
                    } else {
                        wasStable = false
                        log.info(" Connection (endpoint) invalidated")
                    }

                    self.stopHeartbeat()
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected
                    self.connectionEstablishedAt = nil

                    // Reset backoff if connection was stable
                    if wasStable {
                        self.resetBackoff()
                    }

                    if self.autoReconnectEnabled {
                        self.scheduleReconnect()
                    }
                }
            }

            conn.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    log.info(" Connection (endpoint) interrupted")

                    self.stopHeartbeat()
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected

                    if self.autoReconnectEnabled {
                        self.scheduleReconnect()
                    }
                }
            }

            conn.resume()

            // Get proxy and set up error detection
            let _ = conn.remoteObjectProxyWithErrorHandler { error in
                lock.lock()
                defer { lock.unlock() }
                if !completed {
                    completed = true
                    log.info(" ❌ Endpoint connection failed: \(error.localizedDescription)")
                    conn.invalidate()
                    continuation.resume(returning: false)
                }
            } as AnyObject

            if let verifier = self.connectionVerifier {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    lock.lock()
                    if completed { lock.unlock(); return }
                    lock.unlock()

                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); conn.invalidate(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                            return
                        }

                        // Use error-handling proxy to catch XPC failures during verification
                        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); conn.invalidate(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                        }) as? ServiceProtocol else {
                            lock.lock()
                            if !completed { completed = true; lock.unlock(); conn.invalidate(); continuation.resume(returning: false) }
                            else { lock.unlock() }
                            return
                        }

                        let alive = await verifier(proxy)

                        lock.lock()
                        guard !completed else { lock.unlock(); return }
                        completed = true
                        lock.unlock()

                        if alive {
                            self.xpcConnection = conn
                            self.connectionInfo = .connected(to: environment)
                            self.retryCount = 0
                            self.consecutiveHeartbeatFailures = 0
                            self.connectionEstablishedAt = Date()
                            self.resetBackoff()
                            log.info(" ✅ Connected via endpoint (\(environment.displayName)) — verified")
                            self.startHeartbeat()
                            continuation.resume(returning: true)
                        } else {
                            conn.invalidate()
                            continuation.resume(returning: false)
                        }
                    }
                }
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    lock.lock()
                    if !completed {
                        completed = true
                        lock.unlock()

                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.xpcConnection = conn
                            self.connectionInfo = .connected(to: environment)
                            self.retryCount = 0
                            self.consecutiveHeartbeatFailures = 0
                            self.connectionEstablishedAt = Date()
                            self.resetBackoff()

                            log.info(" ✅ Connected via endpoint (\(environment.displayName))")
                            self.startHeartbeat()
                        }

                        continuation.resume(returning: true)
                    } else {
                        lock.unlock()
                    }
                }
            }
        }
    }

    /// Disconnect from XPC service
    nonisolated public func disconnect() {
        Task { @MainActor in
            stopHeartbeat()
            xpcConnection?.invalidate()
            xpcConnection = nil
            connectionInfo = .disconnected
            retryCount = 0
            resetBackoff()
        }
    }

    // MARK: - Heartbeat Monitoring

    /// Start heartbeat timer to monitor connection health
    private func startHeartbeat() {
        stopHeartbeat()
        consecutiveHeartbeatFailures = 0

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkHeartbeat()
            }
        }
        log.info(" 💓 Heartbeat started (interval: \(heartbeatInterval)s)")
    }

    /// Stop heartbeat timer
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Check if connection is still healthy (non-blocking)
    private func checkHeartbeat() async {
        guard let connection = xpcConnection else {
            // Connection lost, try to reconnect
            log.info(" 💔 Heartbeat: no connection")
            scheduleReconnect()
            return
        }

        // Attempt to get proxy — use async continuation instead of blocking semaphore
        let isHealthy = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let _ = connection.remoteObjectProxyWithErrorHandler { error in
                log.info(" 💔 Heartbeat failed: \(error.localizedDescription)")
                if !resumed {
                    resumed = true
                    continuation.resume(returning: false)
                }
            } as AnyObject

            // If no error fires within 0.5s, connection is healthy
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if !resumed {
                    resumed = true
                    continuation.resume(returning: true)
                }
            }
        }

        if isHealthy {
            consecutiveHeartbeatFailures = 0
            resetBackoff()  // Reset backoff on healthy connection
        } else {
            consecutiveHeartbeatFailures += 1
            log.info(" 💔 Heartbeat failure \(consecutiveHeartbeatFailures)/\(maxHeartbeatFailures)")

            if consecutiveHeartbeatFailures >= maxHeartbeatFailures {
                log.info(" 💔 Too many heartbeat failures, reconnecting...")
                xpcConnection?.invalidate()
                xpcConnection = nil
                connectionInfo = .disconnected
                scheduleReconnect()
            }
        }
    }

    /// Schedule a reconnection attempt with graduated backoff
    private func scheduleReconnect() {
        guard autoReconnectEnabled else {
            log.info(" Auto-reconnect disabled")
            return
        }

        guard !isConnecting else {
            log.info(" Already connecting, skipping reconnect")
            return
        }

        guard reconnectTask == nil else {
            log.info(" Reconnect already scheduled")
            return
        }

        // Start tracking on first attempt
        if firstAttemptTime == nil {
            firstAttemptTime = Date()
        }
        reconnectAttempt += 1

        let delay = calculateReconnectDelay()
        log.info(" 🔄 Reconnect attempt \(reconnectAttempt) in \(delay)s")
        stopHeartbeat()

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconnectTask = nil
            await self?.connect()
        }
    }

    /// Get remote object proxy
    public func remoteObjectProxy() -> ServiceProtocol? {
        guard let connection = xpcConnection else { return nil }
        return connection.remoteObjectProxy as? ServiceProtocol
    }

    /// Get remote object proxy with error handler
    public func remoteObjectProxy(errorHandler: @escaping (Error) -> Void) -> ServiceProtocol? {
        guard let connection = xpcConnection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler) as? ServiceProtocol
    }
}
