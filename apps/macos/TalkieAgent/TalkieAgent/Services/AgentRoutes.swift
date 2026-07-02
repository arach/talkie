import AppKit
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

        case ("POST", "/companion/paste-image"):
            await handleCompanionPasteImage(connection, body: request.body, context: request.context)

        case ("POST", "/companion/trackpad"):
            await handleCompanionTrackpad(connection, body: request.body, context: request.context)

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

    private struct CompanionPasteImageRequest: Decodable {
        let imageBase64: String
        let mimeType: String?
        let autoPaste: Bool?
    }

    private struct CompanionTrackpadRequest: Decodable {
        let event: String
        let dx: Double?
        let dy: Double?
    }

    private struct CompanionTrackpadResponse: Encodable {
        let ok: Bool
    }

    private struct CompanionDeckKeyPress {
        let keyCode: UInt16
        let modifiers: CGEventFlags
        let message: String
    }

    private struct CompanionTerminalImagePasteTarget {
        let bundleIdentifier: String
        let displayName: String
    }

    private struct CompanionTerminalImagePastePayload {
        let fileURL: URL
        let pasteText: String
        let pngData: Data
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

        if let keyPress = companionDeckKeyPress(for: shortcutId) {
            let ok = performCompanionShortcutKeyPress(
                keyCode: keyPress.keyCode,
                modifiers: keyPress.modifiers
            )
            BridgeResponse.sendJSON(
                connection,
                data: CompanionTriggerResponse(
                    ok: ok,
                    handledShortcutId: ok ? shortcutId : nil,
                    message: ok ? keyPress.message : nil,
                    error: ok ? nil : "Could not send \(keyPress.message.lowercased())."
                ),
                status: ok ? 200 : 500,
                context: context
            )
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

    private static func companionDeckKeyPress(for shortcutId: String) -> CompanionDeckKeyPress? {
        switch shortcutId {
        case "deck-enter":
            return CompanionDeckKeyPress(keyCode: 36, modifiers: [], message: "Return pressed")
        case "deck-delete":
            return CompanionDeckKeyPress(keyCode: 51, modifiers: [], message: "Delete pressed")
        case "deck-escape":
            return CompanionDeckKeyPress(keyCode: 53, modifiers: [], message: "Escape pressed")
        case "deck-up":
            return CompanionDeckKeyPress(keyCode: 126, modifiers: [], message: "Up arrow pressed")
        case "deck-down":
            return CompanionDeckKeyPress(keyCode: 125, modifiers: [], message: "Down arrow pressed")
        case "deck-left":
            return CompanionDeckKeyPress(keyCode: 123, modifiers: [], message: "Left arrow pressed")
        case "deck-right":
            return CompanionDeckKeyPress(keyCode: 124, modifiers: [], message: "Right arrow pressed")
        case "deck-select-all":
            return CompanionDeckKeyPress(keyCode: 0, modifiers: .maskCommand, message: "Select all sent")
        case "deck-copy":
            return CompanionDeckKeyPress(keyCode: 8, modifiers: .maskCommand, message: "Copy sent")
        case "deck-paste":
            return CompanionDeckKeyPress(keyCode: 9, modifiers: .maskCommand, message: "Paste sent")
        default:
            return nil
        }
    }

    private static func handleCompanionPasteImage(_ connection: NWConnection, body: Data?, context: RequestContext) async {
        guard let body, !body.isEmpty else {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Missing request body", context: context)
            return
        }

        let request: CompanionPasteImageRequest
        do {
            request = try JSONDecoder().decode(CompanionPasteImageRequest.self, from: body)
        } catch {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Invalid JSON body", context: context)
            return
        }

        guard let imageData = Data(base64Encoded: request.imageBase64),
              let image = NSImage(data: imageData) else {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Invalid image payload", context: context)
            return
        }

        let autoPaste = request.autoPaste ?? true

        if let terminalTarget = await MainActor.run(body: { currentCompanionTerminalImagePasteTarget() }),
           let terminalPayload = makeCompanionTerminalImagePastePayload(from: image) {
            let clipboardWritten = await MainActor.run {
                writeCompanionTerminalImagePasteboard(terminalPayload)
            }

            guard clipboardWritten else {
                BridgeResponse.sendJSON(
                    connection,
                    data: CompanionTriggerResponse(
                        ok: false,
                        handledShortcutId: "companion-paste-image",
                        message: nil,
                        error: "Failed to write image path to clipboard"
                    ),
                    status: 500,
                    context: context
                )
                return
            }

            if autoPaste {
                try? await Task.sleep(for: .milliseconds(80))

                let inserted = insertCompanionTerminalImageReference(
                    terminalPayload.pasteText,
                    into: terminalTarget
                ) || performCompanionShortcutKeyPress(keyCode: 9, modifiers: .maskCommand)

                guard inserted else {
                    BridgeResponse.sendJSON(
                        connection,
                        data: CompanionTriggerResponse(
                            ok: false,
                            handledShortcutId: "companion-paste-image",
                            message: nil,
                            error: "Image saved and copied, but paste into \(terminalTarget.displayName) failed"
                        ),
                        status: 500,
                        context: context
                    )
                    return
                }
            }

            BridgeResponse.sendJSON(
                connection,
                data: CompanionTriggerResponse(
                    ok: true,
                    handledShortcutId: "companion-paste-image",
                    message: autoPaste
                        ? "Image path pasted into \(terminalTarget.displayName)"
                        : "Image path copied to clipboard",
                    error: nil
                ),
                context: context
            )
            return
        }

        let clipboardWritten = await MainActor.run { () -> Bool in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.writeObjects([image])
        }

        guard clipboardWritten else {
            BridgeResponse.sendJSON(
                connection,
                data: CompanionTriggerResponse(
                    ok: false,
                    handledShortcutId: "companion-paste-image",
                    message: nil,
                    error: "Failed to write image to clipboard"
                ),
                status: 500,
                context: context
            )
            return
        }

        if autoPaste {
            try? await Task.sleep(for: .milliseconds(80))

            guard performCompanionShortcutKeyPress(keyCode: 9, modifiers: .maskCommand) else {
                BridgeResponse.sendJSON(
                    connection,
                    data: CompanionTriggerResponse(
                        ok: false,
                        handledShortcutId: "companion-paste-image",
                        message: nil,
                        error: "Image copied, but paste failed"
                    ),
                    status: 500,
                    context: context
                )
                return
            }
        }

        BridgeResponse.sendJSON(
            connection,
            data: CompanionTriggerResponse(
                ok: true,
                handledShortcutId: "companion-paste-image",
                message: autoPaste ? "Image pasted" : "Image copied to clipboard",
                error: nil
            ),
            context: context
        )
    }

    private static func handleCompanionTrackpad(_ connection: NWConnection, body: Data?, context: RequestContext) async {
        guard let body, !body.isEmpty else {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Missing request body", context: context)
            return
        }

        let request: CompanionTrackpadRequest
        do {
            request = try JSONDecoder().decode(CompanionTrackpadRequest.self, from: body)
        } catch {
            BridgeResponse.sendError(connection, code: .badRequest, message: "Invalid JSON body", context: context)
            return
        }

        let dx = companionTrackpadDelta(request.dx)
        let dy = companionTrackpadDelta(request.dy)
        let ok: Bool

        switch request.event {
        case "move":
            ok = performCompanionMouseMove(dx: dx, dy: dy)
        case "click":
            ok = performCompanionMouseClick(button: .left)
        case "rightClick":
            ok = performCompanionMouseClick(button: .right)
        case "scroll":
            ok = performCompanionMouseScroll(dx: dx, dy: dy)
        case "mouseDown":
            ok = performCompanionMouseButtonState(button: .left, isDown: true)
        case "mouseUp":
            ok = performCompanionMouseButtonState(button: .left, isDown: false)
        case "drag":
            ok = performCompanionMouseDrag(dx: dx, dy: dy)
        default:
            BridgeResponse.sendError(
                connection,
                code: .badRequest,
                message: "Unknown trackpad event: \(request.event)",
                context: context
            )
            return
        }

        BridgeResponse.sendJSON(connection, data: CompanionTrackpadResponse(ok: ok), context: context)
    }

    private static func companionTrackpadDelta(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, -2_000), 2_000)
    }

    private static func currentCompanionTerminalImagePasteTarget() -> CompanionTerminalImagePasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier?.lowercased() else {
            return nil
        }

        let terminalBundleIdentifiers: Set<String> = [
            "com.googlecode.iterm2",
            "com.apple.terminal",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
            "dev.warp.warp-stable",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "io.alacritty",
        ]

        guard terminalBundleIdentifiers.contains(bundleIdentifier) else {
            return nil
        }

        return CompanionTerminalImagePasteTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "terminal"
        )
    }

    private static func makeCompanionTerminalImagePastePayload(from image: NSImage) -> CompanionTerminalImagePastePayload? {
        guard let pngData = pngData(from: image) else {
            return nil
        }

        let imageSize = companionImagePixelSize(image)
        guard let fileURL = ScreenshotStorage.saveStandalone(
            pngData,
            capturedAt: Date(),
            captureMode: "devices/companion",
            width: imageSize.width,
            height: imageSize.height,
            appName: "iPhone",
            displayName: "Shared Image",
            relativeDirectory: "devices/companion"
        ) else {
            return nil
        }

        return CompanionTerminalImagePastePayload(
            fileURL: fileURL,
            pasteText: fileURL.path,
            pngData: pngData
        )
    }

    private static func writeCompanionTerminalImagePasteboard(
        _ payload: CompanionTerminalImagePastePayload
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let wroteText = pasteboard.setString(payload.pasteText, forType: .string)
        pasteboard.setString(payload.fileURL.absoluteString, forType: .fileURL)
        pasteboard.setData(payload.pngData, forType: .png)
        return wroteText
    }

    private static func insertCompanionTerminalImageReference(
        _ text: String,
        into target: CompanionTerminalImagePasteTarget
    ) -> Bool {
        guard target.bundleIdentifier == "com.googlecode.iterm2" else {
            return false
        }

        guard text.count <= 120_000 else {
            log.info("Companion iTerm image path using clipboard paste", detail: "chars=\(text.count)")
            return false
        }

        let escaped = appleScriptStringLiteral(text)
        let script = """
        tell application id "com.googlecode.iterm2"
            tell current session of current window
                write text "\(escaped)" newline NO
            end tell
        end tell
        """

        return runAppleScript(script, failurePrefix: "Companion iTerm image path paste failed")
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func companionImagePixelSize(_ image: NSImage) -> (width: Int, height: Int) {
        let bestRepresentation = image.representations.max { lhs, rhs in
            (lhs.pixelsWide * lhs.pixelsHigh) < (rhs.pixelsWide * rhs.pixelsHigh)
        }

        if let bestRepresentation,
           bestRepresentation.pixelsWide > 0,
           bestRepresentation.pixelsHigh > 0 {
            return (bestRepresentation.pixelsWide, bestRepresentation.pixelsHigh)
        }

        return (
            max(1, Int(image.size.width.rounded(.up))),
            max(1, Int(image.size.height.rounded(.up)))
        )
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            .replacing("\r", with: " ")
            .replacing("\n", with: " ")
    }

    private static func runAppleScript(
        _ script: String,
        failurePrefix: String = "Companion AppleScript failed"
    ) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else {
            log.warning("\(failurePrefix): could not create script")
            return false
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            log.warning("\(failurePrefix): \(errorInfo)")
            return false
        }

        return true
    }

    private static func performCompanionShortcutKeyPress(
        keyCode: UInt16,
        modifiers: CGEventFlags = []
    ) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Companion shortcut key press failed to create source", detail: "keyCode=\(keyCode)")
            return false
        }

        let modifierEvents = modifierKeyEvents(for: modifiers, source: source)

        for event in modifierEvents.down {
            event.post(tap: .cghidEventTap)
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("Companion shortcut key press failed to create events", detail: "keyCode=\(keyCode)")
            for event in modifierEvents.up {
                event.post(tap: .cghidEventTap)
            }
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        for event in modifierEvents.up {
            event.post(tap: .cghidEventTap)
        }

        log.info("Companion shortcut key press sent", detail: "keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
        return true
    }

    private static func companionMousePosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
    }

    private static func performCompanionMouseMove(dx: Double, dy: Double) -> Bool {
        let current = companionMousePosition()
        let next = CGPoint(x: current.x + dx, y: current.y - dy)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: next,
                mouseButton: .left
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private static func performCompanionMouseClick(button: CGMouseButton) -> Bool {
        let position = companionMousePosition()
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: downType,
                mouseCursorPosition: position,
                mouseButton: button
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: upType,
                mouseCursorPosition: position,
                mouseButton: button
              ) else {
            return false
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func performCompanionMouseButtonState(button: CGMouseButton, isDown: Bool) -> Bool {
        let position = companionMousePosition()
        let eventType: CGEventType

        switch (button, isDown) {
        case (.left, true):
            eventType = .leftMouseDown
        case (.left, false):
            eventType = .leftMouseUp
        case (.right, true):
            eventType = .rightMouseDown
        case (.right, false):
            eventType = .rightMouseUp
        default:
            eventType = .leftMouseDown
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: position,
                mouseButton: button
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private static func performCompanionMouseDrag(dx: Double, dy: Double) -> Bool {
        let current = companionMousePosition()
        let next = CGPoint(x: current.x + dx, y: current.y - dy)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: next,
                mouseButton: .left
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private static func performCompanionMouseScroll(dx: Double, dy: Double) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: companionScrollDelta(dy),
                wheel2: companionScrollDelta(dx),
                wheel3: 0
              ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private static func companionScrollDelta(_ value: Double) -> Int32 {
        let bounded = min(max(value.rounded(), Double(Int32.min)), Double(Int32.max))
        return Int32(bounded)
    }

    private static func modifierKeyEvents(
        for modifiers: CGEventFlags,
        source: CGEventSource
    ) -> (down: [CGEvent], up: [CGEvent]) {
        let modifierKeyCodes: [(flag: CGEventFlags, keyCode: UInt16)] = [
            (.maskCommand, 55),
            (.maskShift, 56),
            (.maskAlternate, 58),
            (.maskControl, 59),
        ]

        let active = modifierKeyCodes.filter { modifiers.contains($0.flag) }
        let down = active.compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: true)
            event?.flags = modifiers
            return event
        }
        let up = active.reversed().compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: false)
            event?.flags = modifiers
            return event
        }

        return (down, up)
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
