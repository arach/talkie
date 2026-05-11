import Foundation
import Network
import TalkieKit

/// HTTP server for Bridge API communication
/// Runs on port 8767, accepts connections from any interface (auth-protected)
@available(macOS 14.0, *)
actor BridgeServer {
    static let shared = BridgeServer()

    private let log = Log(.system)
    private let port: UInt16 = 8767
    private var listener: NWListener?
    private var isRunning = false

    // MARK: - Server Lifecycle

    func start() async throws {
        guard !isRunning else {
            log.info("BridgeServer already running")
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "0.0.0.0", port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: parameters)

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.log.info("BridgeServer listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.log.error("BridgeServer failed: \(error)")
                case .cancelled:
                    self?.log.info("BridgeServer cancelled")
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        self.isRunning = true
        log.info("BridgeServer started on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        log.info("BridgeServer stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) async {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                self.log.error("Connection failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.log.error("Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            Task {
                await self.routeRequest(data, connection: connection)
            }
        }
    }

    // MARK: - Request Routing

    private func routeRequest(_ data: Data, connection: NWConnection) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Parse the raw HTTP data
        guard let request = BridgeRouter.parse(data: data) else {
            let ctx = RequestContext.generate()
            BridgeResponse.sendError(connection, code: .badRequest, message: "Malformed HTTP request", context: ctx)
            return
        }

        let ctx = request.context

        // Reject unsupported API versions
        if request.version == -1 {
            log.warning("[\(ctx.requestId)] Unsupported API version in path: \(request.rawPath)")
            BridgeResponse.sendError(connection, code: .versionUnsupported, message: "Unsupported API version. Use /v1/", context: ctx)
            return
        }

        // Dispatch to namespace
        let (namespace, subpath) = BridgeRouter.extractNamespace(from: request.path)

        switch namespace {
        case .agent:
            await AgentRoutes.handle(request, subpath: subpath, connection: connection)

        case .talkie:
            await TalkieRoutes.handle(request, subpath: subpath, connection: connection)

        case .engine:
            // TODO: Phase 3 — engine routes
            BridgeResponse.sendError(connection, code: .serviceUnavailable, message: "Engine routes not yet implemented", context: ctx)

        case nil:
            BridgeResponse.sendError(connection, code: .notFound, message: "Unknown path: \(request.rawPath)", context: ctx)
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        log.info("[\(ctx.requestId)] \(request.method) \(request.rawPath) → dispatched (\(durationMs)ms) client=\(ctx.clientId)")
    }
}
