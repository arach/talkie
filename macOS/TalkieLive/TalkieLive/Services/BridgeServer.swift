import Foundation
import Network
import TalkieKit

/// Lightweight HTTP server for Bridge communication
/// Runs on localhost:8766, only accepts local connections
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

        // Only accept local connections
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

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

        // Read the HTTP request
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
                await self.handleRequest(data, connection: connection)
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            await sendError(connection, status: 400, message: "Invalid request")
            return
        }

        // Parse HTTP request line
        let lines = requestString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else {
            await sendError(connection, status: 400, message: "Empty request")
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            await sendError(connection, status: 400, message: "Invalid request line")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        log.info("BridgeServer: \(method) \(path)")

        // Route the request
        switch (method, path) {
        case ("GET", "/health"):
            await handleHealth(connection)

        case ("GET", "/screenshot/terminals"):
            await handleTerminalScreenshots(connection)

        case ("GET", let p) where p.hasPrefix("/screenshot/window/"):
            let windowIdStr = String(p.dropFirst("/screenshot/window/".count))
            if let windowId = UInt32(windowIdStr) {
                await handleWindowScreenshot(connection, windowID: windowId)
            } else {
                await sendError(connection, status: 400, message: "Invalid window ID")
            }

        case ("GET", "/windows"):
            await handleListWindows(connection)

        case ("GET", "/windows/claude"):
            await handleClaudeWindows(connection)

        default:
            await sendError(connection, status: 404, message: "Not found")
        }
    }

    // MARK: - Route Handlers

    private func handleHealth(_ connection: NWConnection) async {
        let response: [String: Any] = [
            "status": "ok",
            "service": "TalkieLive",
            "port": port,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        await sendJSON(connection, data: response)
    }

    private func handleListWindows(_ connection: NWConnection) async {
        let windows = await ScreenshotService.shared.listWindows()
        let response: [String: Any] = [
            "windows": windows.map { windowToDict($0) }
        ]
        await sendJSON(connection, data: response)
    }

    private func handleClaudeWindows(_ connection: NWConnection) async {
        let windows = await ScreenshotService.shared.findClaudeWindows()
        let response: [String: Any] = [
            "windows": windows.map { windowToDict($0) }
        ]
        await sendJSON(connection, data: response)
    }

    private func handleWindowScreenshot(_ connection: NWConnection, windowID: CGWindowID) async {
        guard let image = await ScreenshotService.shared.captureWindow(windowID: windowID),
              let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: 0.85) else {
            await sendError(connection, status: 500, message: "Failed to capture window")
            return
        }

        await sendImage(connection, data: jpegData, contentType: "image/jpeg")
    }

    private func handleTerminalScreenshots(_ connection: NWConnection) async {
        let terminals = await ScreenshotService.shared.captureTerminalWindows()

        if terminals.isEmpty {
            await sendJSON(connection, data: ["screenshots": [], "count": 0])
            return
        }

        // Return metadata with base64-encoded images
        var screenshots: [[String: Any]] = []
        for terminal in terminals {
            if let jpegData = await ScreenshotService.shared.encodeAsJPEG(terminal.image, quality: 0.75) {
                screenshots.append([
                    "windowID": terminal.windowID,
                    "bundleId": terminal.bundleId,
                    "title": terminal.title,
                    "imageBase64": jpegData.base64EncodedString()
                ])
            }
        }

        let response: [String: Any] = [
            "screenshots": screenshots,
            "count": screenshots.count
        ]
        await sendJSON(connection, data: response)
    }

    // MARK: - Response Helpers

    private func windowToDict(_ window: WindowInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "windowID": window.windowID,
            "pid": window.pid,
            "appName": window.appName,
            "layer": window.layer,
            "isOnScreen": window.isOnScreen
        ]
        if let bundleId = window.bundleId {
            dict["bundleId"] = bundleId
        }
        if let title = window.title {
            dict["title"] = title
        }
        if let bounds = window.bounds {
            dict["bounds"] = [
                "x": bounds.origin.x,
                "y": bounds.origin.y,
                "width": bounds.width,
                "height": bounds.height
            ]
        }
        return dict
    }

    private func sendJSON(_ connection: NWConnection, data: [String: Any], status: Int = 200) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else {
            await sendError(connection, status: 500, message: "JSON encoding error")
            return
        }

        let statusText = status == 200 ? "OK" : "Error"
        let headers = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        \r

        """

        var response = Data(headers.utf8)
        response.append(jsonData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendImage(_ connection: NWConnection, data: Data, contentType: String) async {
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r

        """

        var response = Data(headers.utf8)
        response.append(data)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendError(_ connection: NWConnection, status: Int, message: String) async {
        await sendJSON(connection, data: ["error": message], status: status)
    }
}
