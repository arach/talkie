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
public enum XPCConnectionState {
    case disconnected
    case connecting
    case connected
    case failed
}

/// Atomic connection info - all state changes together
public struct ConnectionInfo {
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

    // MARK: - Connection State

    private var xpcConnection: NSXPCConnection?
    private var isConnecting = false
    private var retryCount = 0
    private let maxRetries = 3
    private var hasAttemptedAutoLaunch = false

    /// Optional handler to launch the service when connection fails
    /// Called once per connect() attempt before giving up
    public var autoLaunchHandler: (() -> Void)?

    // MARK: - Heartbeat & Auto-Reconnect

    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30.0
    private var consecutiveHeartbeatFailures = 0
    private let maxHeartbeatFailures = 2

    /// Enable/disable auto-reconnect on disconnection (default: true)
    public var autoReconnectEnabled = true

    /// Current reconnect delay (exponential backoff)
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 60.0

    /// Track when connection was established (for stable connection detection)
    private var connectionEstablishedAt: Date?
    private let stableConnectionThreshold: TimeInterval = 10.0  // Must be connected 10s to reset backoff

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

    /// Connect to XPC service, trying environments in order: current → dev → staging → production
    public func connect() async {
        guard !isConnecting, xpcConnection == nil else { return }

        isConnecting = true
        connectionInfo = .connecting

        // Try current environment first
        let currentEnv = TalkieEnvironment.current
        if await tryConnect(to: currentEnv) {
            isConnecting = false
            return
        }

        // Try other environments in order (prefer production for stability)
        let envOrder: [TalkieEnvironment] = [.production, .staging, .dev].filter { $0 != currentEnv }
        for env in envOrder {
            if await tryConnect(to: env) {
                isConnecting = false
                return
            }
        }

        // All attempts failed - try auto-launching the service once
        if !hasAttemptedAutoLaunch, let launchHandler = autoLaunchHandler {
            hasAttemptedAutoLaunch = true
            log.info(" 🚀 Auto-launching service and retrying...")
            launchHandler()

            // Wait for service to start (up to 3 seconds)
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Retry connection to current environment
            if await tryConnect(to: TalkieEnvironment.current) {
                isConnecting = false
                hasAttemptedAutoLaunch = false  // Reset for future reconnects
                return
            }
        }

        isConnecting = false
        connectionInfo = .failed
        hasAttemptedAutoLaunch = false  // Reset for manual retry

        log.info(" ❌ Failed to connect to any environment")
    }

    /// Try connecting to a specific environment
    private func tryConnect(to environment: TalkieEnvironment) async -> Bool {
        let serviceName = serviceNameProvider(environment)

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

                    // Only reset backoff if connection was stable
                    if wasStable {
                        self.reconnectDelay = 1.0
                    } else {
                        // Increase backoff for unstable connections
                        self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
                    }

                    // Auto-reconnect on invalidation
                    if self.autoReconnectEnabled {
                        await self.scheduleReconnect()
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
                        await self.scheduleReconnect()
                    }
                }
            }

            conn.resume()

            // Quick ping to verify service is available
            let _ = conn.remoteObjectProxyWithErrorHandler { error in
                lock.lock()
                defer { lock.unlock() }
                if !completed {
                    completed = true
                    conn.invalidate()
                    continuation.resume(returning: false)
                }
            } as AnyObject

            // If we got here without error, connection succeeded
            lock.lock()
            if !completed {
                completed = true
                lock.unlock()  // Unlock before async work

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.xpcConnection = conn
                    self.connectionInfo = .connected(to: environment)
                    self.retryCount = 0
                    self.consecutiveHeartbeatFailures = 0
                    self.connectionEstablishedAt = Date()  // Track when connection started

                    log.info(" ✅ Connected to \(serviceName) (\(environment.displayName))")

                    // Start heartbeat monitoring
                    self.startHeartbeat()
                }

                continuation.resume(returning: true)
            } else {
                lock.unlock()  // Unlock if already completed by error handler
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
            reconnectDelay = 1.0
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

    /// Check if connection is still healthy
    private func checkHeartbeat() async {
        guard let connection = xpcConnection else {
            // Connection lost, try to reconnect
            log.info(" 💔 Heartbeat: no connection")
            await scheduleReconnect()
            return
        }

        // Attempt to get proxy - if this fails, connection is dead
        let semaphore = DispatchSemaphore(value: 0)
        var isHealthy = false

        let _ = connection.remoteObjectProxyWithErrorHandler { error in
            log.info(" 💔 Heartbeat failed: \(error.localizedDescription)")
            semaphore.signal()
        } as AnyObject

        // Give a short time for error handler to fire
        let result = semaphore.wait(timeout: .now() + 0.5)
        if result == .timedOut {
            // No error within timeout = connection is healthy
            isHealthy = true
        }

        if isHealthy {
            consecutiveHeartbeatFailures = 0
            reconnectDelay = 1.0  // Reset backoff on healthy connection
        } else {
            consecutiveHeartbeatFailures += 1
            log.info(" 💔 Heartbeat failure \(consecutiveHeartbeatFailures)/\(maxHeartbeatFailures)")

            if consecutiveHeartbeatFailures >= maxHeartbeatFailures {
                log.info(" 💔 Too many heartbeat failures, reconnecting...")
                xpcConnection?.invalidate()
                xpcConnection = nil
                connectionInfo = .disconnected
                await scheduleReconnect()
            }
        }
    }

    /// Schedule a reconnection attempt with exponential backoff
    private func scheduleReconnect() async {
        guard autoReconnectEnabled else {
            log.info(" Auto-reconnect disabled")
            return
        }

        guard !isConnecting else {
            log.info(" Already connecting, skipping reconnect")
            return
        }

        let delay = reconnectDelay
        log.info(" 🔄 Scheduling reconnect in \(delay)s")
        stopHeartbeat()

        try? await Task.sleep(for: .seconds(delay))

        // Note: backoff is increased in invalidation handler based on connection stability
        await connect()
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
