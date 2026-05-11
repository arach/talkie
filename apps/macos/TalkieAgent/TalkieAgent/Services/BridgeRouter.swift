import Foundation
import TalkieKit

// MARK: - Request Context

struct RequestContext: Sendable {
    let requestId: String
    let clientId: String
    let apiVersion: Int

    static func generate(clientId: String = "unknown", apiVersion: Int = 1) -> RequestContext {
        let hex = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return RequestContext(
            requestId: "req_\(hex)",
            clientId: clientId,
            apiVersion: apiVersion
        )
    }
}

// MARK: - Parsed Request

struct ParsedRequest: Sendable {
    let method: String
    let path: String                    // without /v1 prefix
    let rawPath: String                 // original path
    let version: Int                    // 1
    let queryParams: [String: String]
    let headers: [String: String]
    let body: Data?
    let context: RequestContext
}

// MARK: - Route Namespace

enum RouteNamespace: String {
    case agent
    case talkie
    case engine
}

// MARK: - Router

@available(macOS 14.0, *)
enum BridgeRouter {

    private static let log = Log(.system)

    /// Legacy paths that alias to versioned routes
    private static let legacyAliases: [String: String] = [
        "/health": "/agent/health",
        "/windows": "/agent/windows",
        "/windows/claude": "/agent/windows/claude",
        "/screenshot/display": "/agent/screenshot/display",
        "/screenshot/terminals": "/agent/screenshot/terminals",
    ]

    // MARK: - Parse

    /// Parse raw HTTP data into a structured request.
    /// Returns nil if the data is malformed.
    static func parse(data: Data) -> ParsedRequest? {
        guard let requestString = String(data: data, encoding: .utf8) else { return nil }

        let lines = requestString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else { return nil }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let rawURI = String(parts[1])

        // Split path and query string
        let (rawPath, queryParams) = splitPathAndQuery(rawURI)

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Parse body (after blank line)
        var body: Data?
        if let blankIndex = lines.firstIndex(where: { $0.isEmpty }) {
            let bodyLines = lines[(lines.index(after: blankIndex))...]
            let bodyString = bodyLines.joined(separator: "\r\n")
            if !bodyString.isEmpty {
                body = Data(bodyString.utf8)
            }
        }

        // Determine API version and strip prefix
        let (version, strippedPath) = extractVersion(from: rawPath)

        // Client identity
        let clientId = headers["x-talkie-client"] ?? "unknown"

        // Request ID (client-provided or generated)
        let requestId: String
        if let provided = headers["x-request-id"], !provided.isEmpty {
            requestId = provided
        } else {
            let hex = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            requestId = "req_\(hex)"
        }

        let context = RequestContext(
            requestId: requestId,
            clientId: clientId,
            apiVersion: version
        )

        return ParsedRequest(
            method: method,
            path: strippedPath,
            rawPath: rawPath,
            version: version,
            queryParams: queryParams,
            headers: headers,
            body: body,
            context: context
        )
    }

    // MARK: - Version Extraction

    /// Extract version from path. Returns (version, pathWithoutPrefix).
    /// `/v1/agent/health` → (1, "/agent/health")
    /// `/health` → (1, "/health")  (legacy, default to v1)
    /// `/v2/agent/health` → (-1, "/agent/health")  (unsupported)
    private static func extractVersion(from path: String) -> (Int, String) {
        // Check for /v{N} prefix
        if path.hasPrefix("/v") {
            let afterV = path.dropFirst(2) // drop "/v"
            // Find the next slash or end
            if let slashIndex = afterV.firstIndex(of: "/") {
                let versionStr = String(afterV[afterV.startIndex..<slashIndex])
                if let version = Int(versionStr) {
                    let remainder = String(afterV[slashIndex...])
                    if version == 1 {
                        return (1, remainder)
                    } else {
                        return (-1, remainder) // unsupported version
                    }
                }
            } else {
                // Path is just "/v1" with nothing after
                if let version = Int(String(afterV)) {
                    if version == 1 {
                        return (1, "/")
                    } else {
                        return (-1, "/")
                    }
                }
            }
        }

        // No version prefix — check legacy aliases
        if let aliased = legacyAliases[path] {
            return (1, aliased)
        }

        // Legacy path with params (e.g. /screenshot/window/123)
        if path.hasPrefix("/screenshot/window/") {
            return (1, "/agent\(path)")
        }

        // Default: treat as v1
        return (1, path)
    }

    // MARK: - Query Parsing

    private static func splitPathAndQuery(_ uri: String) -> (String, [String: String]) {
        guard let qIndex = uri.firstIndex(of: "?") else {
            return (uri, [:])
        }

        let path = String(uri[uri.startIndex..<qIndex])
        let queryString = String(uri[uri.index(after: qIndex)...])
        var params: [String: String] = [:]

        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                params[key] = value
            } else if kv.count == 1 {
                params[String(kv[0])] = ""
            }
        }

        return (path, params)
    }

    // MARK: - Namespace Dispatch

    /// Extract namespace from path. `/agent/health` → (.agent, "/health")
    static func extractNamespace(from path: String) -> (RouteNamespace?, String) {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = trimmed.split(separator: "/", maxSplits: 1)

        guard let first = segments.first,
              let namespace = RouteNamespace(rawValue: String(first)) else {
            return (nil, path)
        }

        let remainder = segments.count > 1 ? "/\(segments[1])" : "/"
        return (namespace, remainder)
    }
}
