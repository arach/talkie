import Foundation
import Network
import TalkieKit

private extension NWError {
    var isAddressAlreadyInUse: Bool {
        if case .posix(let code) = self {
            return code == .EADDRINUSE
        }
        return false
    }
}

/// HTTP server for Bridge API communication
/// Runs on port 8767, accepts connections from any interface (auth-protected)
@available(macOS 14.0, *)
actor BridgeServer {
    static let shared = BridgeServer()

    private let log = Log(.system)
    private let port: UInt16 = 8767
    private static let maxRequestBytes = 25 * 1024 * 1024
    private static let headerTerminator = Data([13, 10, 13, 10])
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

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch let error as NWError where error.isAddressAlreadyInUse {
            log.info("BridgeServer port \(port) already owned by another process; this instance will not bind")
            isRunning = false
            return
        } catch {
            throw error
        }

        listener.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleListenerState(state)
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

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("BridgeServer listening on port \(port)")
        case .failed(let error):
            if error.isAddressAlreadyInUse {
                log.info("BridgeServer port \(port) already owned by another process; this instance will not bind")
            } else {
                log.error("BridgeServer failed: \(error)")
            }
            listener?.cancel()
            listener = nil
            isRunning = false
        case .cancelled:
            log.info("BridgeServer cancelled")
            listener = nil
            isRunning = false
        default:
            break
        }
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

        receiveRequest(connection, accumulated: Data())
    }

    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.log.error("Receive error: \(error)")
                connection.cancel()
                return
            }

            var requestData = accumulated
            if let data, !data.isEmpty {
                requestData.append(data)
            }

            guard !requestData.isEmpty else {
                connection.cancel()
                return
            }

            if requestData.count > Self.maxRequestBytes {
                let context = RequestContext.generate(clientId: "unknown", apiVersion: 1)
                BridgeResponse.sendError(
                    connection,
                    code: .badRequest,
                    message: "Request body too large",
                    context: context
                )
                return
            }

            guard Self.hasCompleteHTTPRequest(requestData) || isComplete else {
                Task {
                    await self.receiveRequest(connection, accumulated: requestData)
                }
                return
            }

            Task {
                await self.routeRequest(requestData, connection: connection)
            }
        }
    }

    private static func hasCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let headerRange = data.range(of: headerTerminator) else {
            return false
        }

        let headerData = data[..<headerRange.lowerBound]
        let expectedBodyLength = contentLength(in: headerData) ?? 0
        let actualBodyLength = data.distance(from: headerRange.upperBound, to: data.endIndex)
        return actualBodyLength >= expectedBodyLength
    }

    private static func contentLength(in headerData: Data.SubSequence) -> Int? {
        guard let headerString = String(data: Data(headerData), encoding: .utf8) else {
            return nil
        }

        for line in headerString.split(separator: "\r\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.compare("content-length", options: .caseInsensitive) == .orderedSame else { continue }

            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value)
        }

        return nil
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
