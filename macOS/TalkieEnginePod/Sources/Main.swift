//
//  Main.swift
//  TalkieEnginePod
//
//  Generic execution pod shell. Loads a capability and handles requests.
//  Designed to run as a subprocess that can be killed to free memory.
//
//  Usage: TalkieEnginePod <capability> [config-json]
//  Example: TalkieEnginePod tts '{"model":"kokoro"}'
//
//  Protocol: JSON-lines on stdin/stdout
//  - Input:  {"id":"uuid","action":"synthesize","payload":{"text":"Hello"}}
//  - Output: {"id":"uuid","success":true,"result":{"audioPath":"/tmp/..."}}
//

import Foundation

// Set process name visible in Activity Monitor
@_silgen_name("setprogname")
func setprogname(_ name: UnsafePointer<CChar>)

// MARK: - Capability Registry

/// Registry of available capabilities
enum CapabilityRegistry {
    static func create(_ name: String) -> (any PodCapability)? {
        switch name.lowercased() {
        case "tts":
            return TTSCapability()
        case "streaming-asr":
            return StreamingASRCapability()
        // Future: case "llm": return LLMCapability()
        default:
            return nil
        }
    }

    static var available: [String] {
        ["tts", "streaming-asr"]
    }
}

// MARK: - Pod Shell

@main
struct PodShell {
    static func main() async {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printError("Usage: TalkieEnginePod <capability> [config-json]")
            printError("Available capabilities: \(CapabilityRegistry.available.joined(separator: ", "))")
            exit(1)
        }

        let capabilityName = args[1]
        let configJson = args.count >= 3 ? args[2] : "{}"

        // Set friendly process name for Activity Monitor
        let friendlyName: String
        switch capabilityName.lowercased() {
        case "tts":
            friendlyName = "Talkie Speech Engine"
        case "streaming-asr":
            friendlyName = "Talkie Streaming Engine"
        default:
            friendlyName = "Talkie \(capabilityName.capitalized) Engine"
        }
        friendlyName.withCString { setprogname($0) }

        // Create capability
        guard let capability = CapabilityRegistry.create(capabilityName) else {
            printError("Unknown capability: \(capabilityName)")
            printError("Available: \(CapabilityRegistry.available.joined(separator: ", "))")
            exit(1)
        }

        // Parse config
        let config: PodConfig
        do {
            let data = configJson.data(using: .utf8) ?? Data()
            config = try JSONDecoder().decode(PodConfig.self, from: data)
        } catch {
            printError("Invalid config JSON: \(error.localizedDescription)")
            exit(1)
        }

        // Load capability
        log("Loading capability: \(capabilityName)")
        do {
            try await capability.load(config: config)
            log("Capability loaded. Memory: \(capability.memoryUsageMB)MB")
        } catch {
            printError("Failed to load capability: \(error.localizedDescription)")
            exit(1)
        }

        // Signal ready
        sendReady(capability: capabilityName, memoryMB: capability.memoryUsageMB)

        // Setup signal handlers for graceful shutdown
        setupSignalHandlers(capability: capability)

        // Request loop
        await runRequestLoop(capability: capability)
    }

    /// Read requests from stdin, process, write responses to stdout
    static func runRequestLoop(capability: any PodCapability) async {
        let stdin = FileHandle.standardInput
        var buffer = Data()

        while true {
            // Read available data
            let chunk = stdin.availableData
            if chunk.isEmpty {
                // EOF - parent closed pipe, exit gracefully
                log("EOF received, shutting down")
                await capability.unload()
                exit(0)
            }

            buffer.append(chunk)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = buffer[(newlineIndex + 1)...]

                guard !lineData.isEmpty else { continue }

                // Parse request
                do {
                    let request = try JSONDecoder().decode(PodRequest.self, from: lineData)

                    // Handle special commands
                    if request.action == "_status" {
                        sendStatus(capability: capability, requestId: request.id)
                        continue
                    }

                    if request.action == "_unload" {
                        log("Unload requested")
                        await capability.unload()
                        sendResponse(PodResponse.success(id: request.id, result: ["status": "unloaded"]))
                        exit(0)
                    }

                    // Handle capability request
                    let startTime = Date()
                    let response = try await capability.handle(request)
                    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

                    // Add duration if not already set
                    if response.durationMs == nil {
                        sendResponse(PodResponse(
                            id: response.id,
                            success: response.success,
                            result: response.result,
                            error: response.error,
                            durationMs: durationMs
                        ))
                    } else {
                        sendResponse(response)
                    }

                } catch let error as DecodingError {
                    let errorResponse = PodResponse.failure(
                        id: "unknown",
                        error: "Invalid request JSON: \(error.localizedDescription)"
                    )
                    sendResponse(errorResponse)
                } catch {
                    let errorResponse = PodResponse.failure(
                        id: "unknown",
                        error: "Request failed: \(error.localizedDescription)"
                    )
                    sendResponse(errorResponse)
                }
            }
        }
    }

    // MARK: - Output Helpers

    static func sendResponse(_ response: PodResponse) {
        guard let data = try? JSONEncoder().encode(response),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        print(json)
        fflush(stdout)
    }

    static func sendReady(capability: String, memoryMB: Int) {
        let ready: [String: Any] = [
            "type": "ready",
            "capability": capability,
            "memoryMB": memoryMB,
            "pid": ProcessInfo.processInfo.processIdentifier
        ]
        if let data = try? JSONSerialization.data(withJSONObject: ready),
           let json = String(data: data, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }
    }

    static func sendStatus(capability: any PodCapability, requestId: String) {
        let status = PodStatus(
            capability: type(of: capability).name,
            loaded: capability.isLoaded,
            memoryMB: capability.memoryUsageMB,
            requestsHandled: 0  // Could track this
        )
        let response = PodResponse.success(id: requestId, result: [
            "loaded": String(status.loaded),
            "memoryMB": String(status.memoryMB)
        ])
        sendResponse(response)
    }

    static func log(_ message: String) {
        let logEntry: [String: Any] = [
            "type": "log",
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: logEntry),
           let json = String(data: data, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    }

    // MARK: - Signal Handling

    static func setupSignalHandlers(capability: any PodCapability) {
        // Handle SIGTERM gracefully
        signal(SIGTERM) { _ in
            Task {
                // Note: Can't easily access capability here due to signal handler limitations
                // The process will exit, and macOS will clean up memory
                exit(0)
            }
        }

        // Ignore SIGPIPE (broken pipe when parent dies)
        signal(SIGPIPE, SIG_IGN)
    }
}
