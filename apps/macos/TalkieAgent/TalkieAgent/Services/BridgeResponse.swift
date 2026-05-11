import Foundation
import Network
import TalkieKit

// MARK: - Error Codes

enum BridgeErrorCode: String, Sendable, Encodable {
    case badRequest = "bad_request"
    case notFound = "not_found"
    case methodNotAllowed = "method_not_allowed"
    case conflict = "conflict"
    case internalError = "internal_error"
    case serviceUnavailable = "service_unavailable"
    case versionUnsupported = "version_unsupported"

    var httpStatus: Int {
        switch self {
        case .badRequest, .versionUnsupported: return 400
        case .notFound: return 404
        case .methodNotAllowed: return 405
        case .conflict: return 409
        case .internalError: return 500
        case .serviceUnavailable: return 503
        }
    }

    var retriable: Bool {
        switch self {
        case .serviceUnavailable: return true
        default: return false
        }
    }
}

// MARK: - Error Envelope

struct BridgeErrorEnvelope: Encodable {
    struct ErrorBody: Encodable {
        let code: String
        let message: String
        let retriable: Bool
        let details: [String: String]?
        let requestId: String
    }

    let error: ErrorBody
}

// MARK: - Paginated Response

struct PaginatedResponse<T: Encodable>: Encodable {
    let items: [T]
    let cursor: String?
    let total: Int?
}

// MARK: - Pagination Params

struct PaginationParams {
    let limit: Int
    let cursor: String?
    let offset: Int?

    static let defaultLimit = 50
    static let maxLimit = 200

    init(from queryParams: [String: String]) {
        let rawLimit = queryParams["limit"].flatMap(Int.init) ?? Self.defaultLimit
        self.limit = min(max(rawLimit, 1), Self.maxLimit)
        self.cursor = queryParams["cursor"]
        self.offset = queryParams["offset"].flatMap(Int.init)
    }
}

// MARK: - Cursor Encoding

enum CursorCodec {
    struct CursorPayload: Codable {
        let createdAt: String
        let id: String
    }

    static func encode(createdAt: String, id: String) -> String {
        let payload = CursorPayload(createdAt: createdAt, id: id)
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        return data.base64EncodedString()
    }

    static func decode(_ cursor: String) -> CursorPayload? {
        guard let data = Data(base64Encoded: cursor) else { return nil }
        return try? JSONDecoder().decode(CursorPayload.self, from: data)
    }
}

// MARK: - Response Helpers

@available(macOS 14.0, *)
enum BridgeResponse {

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    // MARK: JSON Success

    static func sendJSON(
        _ connection: NWConnection,
        data: some Encodable,
        status: Int = 200,
        context: RequestContext
    ) {
        guard let jsonData = try? encoder.encode(data) else {
            sendError(connection, code: .internalError, message: "JSON encoding error", context: context)
            return
        }

        let statusText = httpStatusText(status)
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(jsonData.count)",
            "X-Request-ID: \(context.requestId)",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(jsonData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Send a dictionary-based JSON response (for legacy handlers using [String: Any])
    static func sendJSONDict(
        _ connection: NWConnection,
        data: [String: Any],
        status: Int = 200,
        context: RequestContext
    ) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else {
            sendError(connection, code: .internalError, message: "JSON encoding error", context: context)
            return
        }

        let statusText = httpStatusText(status)
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(jsonData.count)",
            "X-Request-ID: \(context.requestId)",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(jsonData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: Error

    static func sendError(
        _ connection: NWConnection,
        code: BridgeErrorCode,
        message: String,
        context: RequestContext,
        details: [String: String]? = nil
    ) {
        let envelope = BridgeErrorEnvelope(error: .init(
            code: code.rawValue,
            message: message,
            retriable: code.retriable,
            details: details,
            requestId: context.requestId
        ))

        guard let jsonData = try? encoder.encode(envelope) else {
            // Last resort: hand-build error JSON
            let fallback = "{\"error\":{\"code\":\"\(code.rawValue)\",\"message\":\"Internal error\",\"retriable\":false,\"requestId\":\"\(context.requestId)\"}}"
            let fallbackData = Data(fallback.utf8)
            let headers = "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: \(fallbackData.count)\r\nX-Request-ID: \(context.requestId)\r\nConnection: close\r\n\r\n"
            var response = Data(headers.utf8)
            response.append(fallbackData)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        let status = code.httpStatus
        let statusText = httpStatusText(status)
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(jsonData.count)",
            "X-Request-ID: \(context.requestId)",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(jsonData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: Image

    static func sendImage(
        _ connection: NWConnection,
        data: Data,
        contentType: String,
        context: RequestContext
    ) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(data.count)",
            "X-Request-ID: \(context.requestId)",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(data)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: SSE (Server-Sent Events)

    static func sendSSEHeaders(
        _ connection: NWConnection,
        context: RequestContext
    ) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "X-Request-ID: \(context.requestId)",
            "Connection: keep-alive",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
    }

    static func sendSSEEvent(
        _ connection: NWConnection,
        event: String,
        data: some Encodable
    ) {
        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let sseFrame = "event: \(event)\ndata: \(jsonString)\n\n"
        connection.send(content: Data(sseFrame.utf8), completion: .contentProcessed { _ in })
    }

    // MARK: - Private

    private static func httpStatusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
