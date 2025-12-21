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

        // Try other environments in order
        let envOrder: [TalkieEnvironment] = [.dev, .staging, .production].filter { $0 != currentEnv }
        for env in envOrder {
            if await tryConnect(to: env) {
                isConnecting = false
                return
            }
        }

        // All attempts failed
        isConnecting = false
        connectionInfo = .failed

        NSLog("[XPCServiceManager] ❌ Failed to connect to any environment")
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
                NSLog("[XPCServiceManager] Setting exported object: \(exportedObject != nil ? "✓ Set" : "❌ NIL")")
            }

            let lock = NSLock()
            var completed = false

            // Set up handlers
            conn.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    NSLog("[XPCServiceManager] Connection invalidated: \(serviceName)")
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected
                }
            }

            conn.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    NSLog("[XPCServiceManager] Connection interrupted: \(serviceName)")

                    // Clear connection state to allow reconnection
                    self.xpcConnection = nil
                    self.connectionInfo = .disconnected

                    // Try to reconnect
                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        NSLog("[XPCServiceManager] Retrying... (\(self.retryCount)/\(self.maxRetries))")
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            await self.connect()
                        }
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

                    NSLog("[XPCServiceManager] ✅ Connected to \(serviceName) (\(environment.displayName))")
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
            xpcConnection?.invalidate()
            xpcConnection = nil
            connectionInfo = .disconnected
            retryCount = 0
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
