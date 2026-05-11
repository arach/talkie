import Foundation
import Network
import TalkieKit

/// Route handlers for `/v1/agent/*` endpoints
@available(macOS 14.0, *)
enum AgentRoutes {

    private static let log = Log(.system)

    static func handle(_ request: ParsedRequest, subpath: String, connection: NWConnection) async {
        switch (request.method, subpath) {
        case ("GET", "/health"):
            await handleHealth(connection, context: request.context)

        case ("GET", "/windows"):
            await handleListWindows(connection, context: request.context)

        case ("GET", "/windows/claude"):
            await handleClaudeWindows(connection, context: request.context)

        case ("GET", "/screenshot/display"):
            await handleDisplayScreenshot(connection, request: request)

        case ("GET", "/screenshot/terminals"):
            await handleTerminalScreenshots(connection, context: request.context)

        case ("GET", let p) where p.hasPrefix("/screenshot/window/"):
            let windowIdStr = String(p.dropFirst("/screenshot/window/".count))
            if let windowId = UInt32(windowIdStr) {
                await handleWindowScreenshot(connection, windowID: windowId, context: request.context)
            } else {
                BridgeResponse.sendError(connection, code: .badRequest, message: "Invalid window ID", context: request.context)
            }

        case ("POST", "/companion/trigger"):
            await handleCompanionTrigger(connection, body: request.body, context: request.context)

        case ("GET", "/companion/runtime-state"):
            await handleCompanionRuntimeState(connection, context: request.context)

        default:
            BridgeResponse.sendError(connection, code: .notFound, message: "Unknown agent route: \(subpath)", context: request.context)
        }
    }

    // MARK: - Handlers

    private static func handleHealth(_ connection: NWConnection, context: RequestContext) async {
        struct HealthResponse: Encodable {
            let status: String
            let service: String
            let port: Int
            let timestamp: String
            let version: Int
        }

        let response = HealthResponse(
            status: "ok",
            service: "TalkieAgent",
            port: 8767,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            version: 1
        )
        BridgeResponse.sendJSON(connection, data: response, context: context)
    }

    private static func handleListWindows(_ connection: NWConnection, context: RequestContext) async {
        let windows = await ScreenshotService.shared.listWindows()
        let dicts: [[String: Any]] = windows.map { windowToDict($0) }
        BridgeResponse.sendJSONDict(connection, data: ["windows": dicts], context: context)
    }

    private static func handleClaudeWindows(_ connection: NWConnection, context: RequestContext) async {
        let windows = await ScreenshotService.shared.findClaudeWindows()
        let dicts: [[String: Any]] = windows.map { windowToDict($0) }
        BridgeResponse.sendJSONDict(connection, data: ["windows": dicts], context: context)
    }

    private static func handleWindowScreenshot(_ connection: NWConnection, windowID: CGWindowID, context: RequestContext) async {
        guard let image = await ScreenshotService.shared.captureWindow(windowID: windowID),
              let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: 0.85) else {
            BridgeResponse.sendError(connection, code: .internalError, message: "Failed to capture window", context: context)
            return
        }

        BridgeResponse.sendImage(connection, data: jpegData, contentType: "image/jpeg", context: context)
    }

    private static func handleDisplayScreenshot(_ connection: NWConnection, request: ParsedRequest) async {
        let maxDimension = request.queryParams["maxDimension"].flatMap(Int.init)
        let quality = request.queryParams["quality"]
            .flatMap(Double.init)
            .map { min(max($0, 0.1), 0.95) }
            ?? 0.6

        guard let image = await ScreenshotService.shared.captureMainDisplay(maxDimension: maxDimension),
              let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: CGFloat(quality)) else {
            BridgeResponse.sendError(connection, code: .internalError, message: "Failed to capture display", context: request.context)
            return
        }

        BridgeResponse.sendImage(connection, data: jpegData, contentType: "image/jpeg", context: request.context)
    }

    private static func handleTerminalScreenshots(_ connection: NWConnection, context: RequestContext) async {
        let terminals = await ScreenshotService.shared.captureTerminalWindows()

        if terminals.isEmpty {
            BridgeResponse.sendJSONDict(connection, data: ["screenshots": [] as [Any], "count": 0], context: context)
            return
        }

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

        BridgeResponse.sendJSONDict(connection, data: [
            "screenshots": screenshots,
            "count": screenshots.count
        ], context: context)
    }

    // MARK: - Companion

    private struct CompanionTriggerRequest: Decodable {
        let shortcutId: String
    }

    private struct CompanionTriggerResponse: Encodable {
        let ok: Bool
        let handledShortcutId: String?
        let message: String?
        let error: String?
    }

    private struct CompanionShortcutRuntimeState: Encodable {
        let shortcutId: String
        let phase: String
        let canStop: Bool
        let detail: String?
        let elapsedSeconds: Double?
        let signalLevel: Double?
    }

    private struct CompanionShortcutRecentResult: Encodable {
        let shortcutId: String
        let resultText: String
        let completedAt: String
    }

    private struct CompanionAppSwitcherApp: Encodable {}

    private struct CompanionRuntimeStateResponse: Encodable {
        let shortcutStates: [CompanionShortcutRuntimeState]
        let recentResults: [CompanionShortcutRecentResult]
        let appSwitcherApps: [CompanionAppSwitcherApp]
    }

    private static func handleCompanionTrigger(_ connection: NWConnection, body: Data?, context: RequestContext) async {
        guard let body, !body.isEmpty else {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Missing request body", context: context)
            return
        }

        let request: CompanionTriggerRequest
        do {
            request = try JSONDecoder().decode(CompanionTriggerRequest.self, from: body)
        } catch {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Invalid JSON body", context: context)
            return
        }

        let shortcutId = request.shortcutId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcutId.isEmpty else {
            BridgeResponse.sendError(connection, code: .badRequest, message: "shortcutId is required", context: context)
            return
        }

        switch shortcutId {
        case "talkie-dictate":
            await dispatchDictationToggle(shortcutId: shortcutId, connection: connection, context: context)

        default:
            BridgeResponse.sendError(
                connection,
                code: .notFound,
                message: "Shortcut not handled by agent: \(shortcutId)",
                context: context
            )
        }
    }

    private static func dispatchDictationToggle(shortcutId: String, connection: NWConnection, context: RequestContext) async {
        let agentController = await MainActor.run { TalkieAgentXPCService.shared.agentController }
        guard let agentController else {
            BridgeResponse.sendError(
                connection,
                code: .serviceUnavailable,
                message: "Agent not ready",
                context: context
            )
            return
        }

        let state = await MainActor.run { agentController.state }

        let response: CompanionTriggerResponse
        switch state {
        case .idle:
            await AgentCompanionRuntimeStore.shared.markStarted(shortcutId: shortcutId)
            Task { @MainActor in await agentController.toggleListening(interstitial: false) }
            response = CompanionTriggerResponse(ok: true, handledShortcutId: shortcutId, message: "Dictation started", error: nil)

        case .listening:
            Task { @MainActor in await agentController.toggleListening(interstitial: false) }
            response = CompanionTriggerResponse(ok: true, handledShortcutId: shortcutId, message: "Dictation stopped", error: nil)

        case .transcribing, .routing, .refining:
            response = CompanionTriggerResponse(ok: true, handledShortcutId: shortcutId, message: "Dictation is finishing", error: nil)
        }

        BridgeResponse.sendJSON(connection, data: response, context: context)
    }

    private static func handleCompanionRuntimeState(_ connection: NWConnection, context: RequestContext) async {
        let snapshot = await AgentCompanionRuntimeStore.shared.snapshot()
        let agentController = await MainActor.run { TalkieAgentXPCService.shared.agentController }

        guard let agentController else {
            BridgeResponse.sendJSON(
                connection,
                data: CompanionRuntimeStateResponse(shortcutStates: [], recentResults: [], appSwitcherApps: []),
                context: context
            )
            return
        }

        let state = await MainActor.run { agentController.state }
        var shortcutStates: [CompanionShortcutRuntimeState] = []

        if let shortcutId = snapshot.activeShortcutId {
            switch state {
            case .listening:
                shortcutStates.append(
                    CompanionShortcutRuntimeState(
                        shortcutId: shortcutId,
                        phase: "recording",
                        canStop: true,
                        detail: "Listening on your Mac",
                        elapsedSeconds: elapsedSince(snapshot.lastStartedAt),
                        signalLevel: await MainActor.run { Double(AudioLevelMonitor.shared.level) }
                    )
                )

            case .transcribing, .routing, .refining:
                shortcutStates.append(
                    CompanionShortcutRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Finishing dictation on your Mac",
                        elapsedSeconds: elapsedSince(snapshot.lastStartedAt),
                        signalLevel: nil
                    )
                )

            case .idle:
                await AgentCompanionRuntimeStore.shared.markInactive()
            }
        }

        let activeShortcutIDs = Set(shortcutStates.map(\.shortcutId))
        let recentResults = await currentCompanionRecentResults(
            snapshot: snapshot,
            state: state,
            activeShortcutIDs: activeShortcutIDs
        )

        if !shortcutStates.isEmpty || !recentResults.isEmpty {
            log.debug(
                "Agent companion runtime state",
                detail: "state=\(state.rawValue) active=\(shortcutStates.count) recent=\(recentResults.count)"
            )
        }

        BridgeResponse.sendJSON(
            connection,
            data: CompanionRuntimeStateResponse(
                shortcutStates: shortcutStates,
                recentResults: recentResults,
                appSwitcherApps: []
            ),
            context: context
        )
    }

    private static func currentCompanionRecentResults(
        snapshot: AgentCompanionRuntimeSnapshot,
        state: LiveState,
        activeShortcutIDs: Set<String>
    ) async -> [CompanionShortcutRecentResult] {
        guard state == .idle,
              let shortcutId = snapshot.lastShortcutId,
              let startedAt = snapshot.lastStartedAt,
              !activeShortcutIDs.contains(shortcutId) else {
            return []
        }

        let recentDictations = UnifiedDatabase.recentDictations(limit: 5)
        guard let latestDictation = recentDictations.first(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return []
        }

        let completionDate = latestDictation.createdAt
        let elapsedSinceCompletion = Date().timeIntervalSince(completionDate)
        guard elapsedSinceCompletion >= 0,
              elapsedSinceCompletion <= 120,
              completionDate >= startedAt.addingTimeInterval(-5) else {
            return []
        }

        let resultText = latestDictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resultText.isEmpty else { return [] }

        return [
            CompanionShortcutRecentResult(
                shortcutId: shortcutId,
                resultText: resultText,
                completedAt: ISO8601DateFormatter().string(from: completionDate)
            )
        ]
    }

    private static func elapsedSince(_ date: Date?) -> Double? {
        guard let date else { return nil }
        return max(0, Date().timeIntervalSince(date))
    }

    // MARK: - Helpers

    private static func windowToDict(_ window: WindowInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "windowID": window.windowID,
            "pid": window.pid,
            "appName": window.appName,
            "layer": window.layer,
            "isOnScreen": window.isOnScreen
        ]
        if let bundleId = window.bundleId { dict["bundleId"] = bundleId }
        if let title = window.title { dict["title"] = title }
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
}

private struct AgentCompanionRuntimeSnapshot: Sendable {
    let activeShortcutId: String?
    let lastShortcutId: String?
    let lastStartedAt: Date?
}

private actor AgentCompanionRuntimeStore {
    static let shared = AgentCompanionRuntimeStore()

    private var activeShortcutId: String?
    private var lastShortcutId: String?
    private var lastStartedAt: Date?

    func markStarted(shortcutId: String) {
        activeShortcutId = shortcutId
        lastShortcutId = shortcutId
        lastStartedAt = Date()
    }

    func markInactive() {
        activeShortcutId = nil
    }

    func snapshot() -> AgentCompanionRuntimeSnapshot {
        AgentCompanionRuntimeSnapshot(
            activeShortcutId: activeShortcutId,
            lastShortcutId: lastShortcutId,
            lastStartedAt: lastStartedAt
        )
    }
}
