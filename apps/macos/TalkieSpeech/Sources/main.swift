import Foundation
import FluidAudio
import Network

final class SpeechServer: @unchecked Sendable {
    private let port: UInt16
    private let host: String
    private let authToken: String?
    private let idleTimeoutSeconds: TimeInterval
    private var listener: NWListener?
    private var ttsManager: KokoroTtsManager?
    private var idleTimer: DispatchSourceTimer?
    private var lastRequestAt = Date()
    private var isLoading = false
    private var requestCount = 0
    private let lock = NSLock()

    init(port: UInt16 = 8780, host: String = "0.0.0.0", authToken: String? = nil, idleTimeoutSeconds: TimeInterval = 3600) {
        self.port = port
        self.host = host
        self.authToken = authToken ?? ProcessInfo.processInfo.environment["TALKIE_SPEECH_TOKEN"]
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }

    func run() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[TalkieSpeech] Listening on http://\(self.host):\(self.port)")
            case .failed(let error):
                print("[TalkieSpeech] Listener failed: \(error)")
                exit(1)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
        startIdleTimer()

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let sigSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigSrc.setEventHandler { [weak self] in
            print("[TalkieSpeech] SIGTERM received, shutting down")
            self?.listener?.cancel()
            exit(0)
        }
        sigSrc.resume()
        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in
            print("[TalkieSpeech] SIGINT received, shutting down")
            self?.listener?.cancel()
            exit(0)
        }
        intSrc.resume()

        while true {
            try await Task.sleep(for: .seconds(86400))
        }
    }

    // MARK: - TTS Lifecycle

    private func ensureTTS() async throws -> KokoroTtsManager {
        if let manager = ttsManager {
            return manager
        }

        guard !isLoading else {
            while isLoading { try await Task.sleep(for: .milliseconds(100)) }
            if let manager = ttsManager { return manager }
            throw SpeechError.loadFailed("TTS failed to initialize")
        }

        isLoading = true
        defer { isLoading = false }

        print("[TalkieSpeech] Loading Kokoro models...")
        let start = CFAbsoluteTimeGetCurrent()
        let manager = KokoroTtsManager()
        try await manager.initialize()
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        print("[TalkieSpeech] Kokoro ready (\(elapsed)ms)")

        ttsManager = manager
        return manager
    }

    private func unloadTTS() {
        guard ttsManager != nil else { return }
        ttsManager = nil
        print("[TalkieSpeech] Kokoro unloaded (idle timeout)")
    }

    private func touchActivity() {
        lastRequestAt = Date()
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldUnload = self.ttsManager != nil &&
                Date().timeIntervalSince(self.lastRequestAt) >= self.idleTimeoutSeconds
            self.lock.unlock()
            if shouldUnload {
                self.unloadTTS()
            }
        }
        timer.resume()
        idleTimer = timer
    }

    // MARK: - HTTP

    private func handleConnection(_ connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            Task {
                await self.route(data, connection: connection)
            }
        }
    }

    private func route(_ data: Data, connection: NWConnection) async {
        guard let request = parseHTTP(data) else {
            sendError(connection, status: 400, message: "Malformed request")
            return
        }

        // Health is always open; everything else requires auth
        if request.path != "/health", let token = authToken, !token.isEmpty {
            guard request.header("Authorization") == "Bearer \(token)" else {
                sendError(connection, status: 401, message: "Unauthorized")
                return
            }
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            handleHealth(connection)

        case ("GET", "/voices"):
            handleVoices(connection)

        case ("POST", "/synthesize"):
            await handleSynthesize(request.body, connection: connection)

        case ("POST", "/unload"):
            unloadTTS()
            sendJSON(connection, dict: ["status": "unloaded"])

        default:
            sendError(connection, status: 404, message: "Not found: \(request.path)")
        }
    }

    // MARK: - Handlers

    private func handleHealth(_ connection: NWConnection) {
        sendJSON(connection, dict: [
            "status": "ok",
            "service": "TalkieSpeech",
            "port": Int(port),
            "loaded": ttsManager != nil,
            "requests": requestCount,
        ] as [String: Any])
    }

    private func handleVoices(_ connection: NWConnection) {
        let voices: [[String: String]] = TtsConstants.availableVoices.map { voiceId in
            [
                "id": voiceId,
                "name": voiceId,
                "language": voiceLanguage(voiceId),
            ]
        }
        sendJSON(connection, dict: [
            "default": TtsConstants.recommendedVoice,
            "voices": voices,
        ] as [String: Any])
    }

    private func handleSynthesize(_ body: Data?, connection: NWConnection) async {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let text = json["text"] as? String, !text.isEmpty else {
            sendError(connection, status: 400, message: "Missing 'text' in JSON body")
            return
        }

        let voice = json["voice"] as? String
        let speed = (json["speed"] as? NSNumber)?.floatValue ?? 1.0

        touchActivity()
        requestCount += 1
        let requestNum = requestCount

        do {
            let manager = try await ensureTTS()
            let start = CFAbsoluteTimeGetCurrent()
            let audioData = try await manager.synthesize(text: text, voice: voice, voiceSpeed: speed)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            print("[TalkieSpeech] #\(requestNum) synthesized \(text.prefix(40))... → \(audioData.count) bytes (\(elapsed)ms)")

            sendAudio(connection, data: audioData)
        } catch {
            sendError(connection, status: 500, message: "Synthesis failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Response Helpers

    private func sendJSON(_ connection: NWConnection, dict: [String: Any], status: Int = 200) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            sendError(connection, status: 500, message: "JSON encoding error")
            return
        }
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(jsonData)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendAudio(_ connection: NWConnection, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendError(_ connection: NWConnection, status: Int, message: String) {
        sendJSON(connection, dict: ["error": message], status: status)
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Unknown"
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?

        func header(_ name: String) -> String? {
            headers[name.lowercased()]
        }
    }

    private func parseHTTP(_ data: Data) -> HTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let parts = str.split(separator: "\r\n\r\n", maxSplits: 1)
        let headerSection = String(parts[0])
        let body = parts.count > 1 ? Data(String(parts[1]).utf8) : nil

        let lines = headerSection.split(separator: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else { return nil }

        let method = String(tokens[0])
        let rawPath = String(tokens[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                headers[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                    String(pair[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Helpers

    private func voiceLanguage(_ id: String) -> String {
        guard id.count >= 2 else { return "unknown" }
        let prefix = String(id.prefix(1))
        switch prefix {
        case "a": return "en-US"
        case "b": return "en-GB"
        case "e": return "es"
        case "f": return "fr"
        case "h": return "hi"
        case "i": return "it"
        case "j": return "ja"
        case "p": return "pt-BR"
        case "z": return "zh"
        default: return "unknown"
        }
    }
}

enum SpeechError: LocalizedError {
    case loadFailed(String)
    var errorDescription: String? {
        switch self { case .loadFailed(let msg): return msg }
    }
}

let args = CommandLine.arguments
var port: UInt16 = 8780
var host = "0.0.0.0"

for (i, arg) in args.enumerated() {
    if arg == "--port", i + 1 < args.count, let p = UInt16(args[i + 1]) { port = p }
    if arg == "--host", i + 1 < args.count { host = args[i + 1] }
}

let server = SpeechServer(port: port, host: host)
try await server.run()
