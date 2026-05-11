import Foundation
import Network
import TalkieKit

/// Route handlers for `/v1/talkie/*` endpoints
/// Placeholder — will be wired to TalkieObjectReader in Phase 2
@available(macOS 14.0, *)
enum TalkieRoutes {

    private static let log = Log(.system)

    static func handle(_ request: ParsedRequest, subpath: String, connection: NWConnection) async {
        switch (request.method, subpath) {
        case ("GET", "/memos"):
            // TODO: Phase 2 — wire to TalkieObjectReader
            BridgeResponse.sendError(
                connection,
                code: .serviceUnavailable,
                message: "Talkie data routes not yet implemented",
                context: request.context
            )

        case ("GET", let p) where p.hasPrefix("/memos/"):
            let id = String(p.dropFirst("/memos/".count))
            // TODO: Phase 2 — wire to TalkieObjectReader
            BridgeResponse.sendError(
                connection,
                code: .serviceUnavailable,
                message: "Talkie data routes not yet implemented (requested: \(id))",
                context: request.context
            )

        default:
            BridgeResponse.sendError(
                connection,
                code: .notFound,
                message: "Unknown talkie route: \(subpath)",
                context: request.context
            )
        }
    }
}
