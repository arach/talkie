//
//  CaptureMarkupCoordinator.swift
//  Talkie
//
//  Ephemeral markup bay lifecycle: open web session, accept/cancel, discard.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import TalkieKit

private let log = Log(.ui)

@MainActor
final class CaptureMarkupCoordinator: NSObject, CaptureMarkupPanelChromeDelegate {
    static let shared = CaptureMarkupCoordinator()

    private var panel: NSPanel?
    private var rootView: CaptureMarkupPanelRootView?
    private var webSession: CaptureMarkupWebSession?
    private var imageURL: URL?
    private var onComplete: ((Result<CaptureMarkupDocument?, Error>) -> Void)?
    private var layerCount = 0
    private var passCount = 0
    private var currentSelection: CaptureMarkupLayerSelection?
    private var currentDocument: CaptureMarkupDocument?
    private var dragExportURLs: [URL] = []

    private override init() {
        super.init()
    }

    func openSession(
        imageURL: URL,
        document: CaptureMarkupDocument? = nil,
        instruction: String? = nil,
        onComplete: ((Result<CaptureMarkupDocument?, Error>) -> Void)? = nil
    ) {
        closeSession(discard: false)

        self.imageURL = imageURL
        self.onComplete = onComplete

        let doc = document ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? emptyDocument(for: imageURL)
        currentDocument = doc

        let panel = makePanel()
        let root = CaptureMarkupPanelRootView(frame: panel.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(root)
        rootView = root
        root.setDragPayloadProvider { [weak self] in
            self?.makeDragPayload()
        }

        root.inputBar.delegate = self
        if let instruction, !instruction.isEmpty {
            root.inputBar.promptText = instruction
        }
        syncChrome(layerCount: doc.layers.count, selection: nil)

        let session = CaptureMarkupWebSession()
        session.onMessage = { [weak self] message in
            self?.handleBridge(message: message)
        }
        session.attach(to: root.webHost)
        webSession = session
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        session.start(imageURL: imageURL, document: doc, instruction: instruction)
        SettingsManager.shared.isMarkupSessionActive = true
        log.info("Capture markup session opened", detail: imageURL.lastPathComponent)
    }

    /// Build the markup chrome for hosting inside a normal in-app view
    /// (vs. the floating `NSPanel`). The caller owns the returned view and
    /// places it in its own hierarchy; the coordinator drives the session
    /// exactly as the panel does (autosave on every edit, AI run, drag-out).
    /// There is no Accept/Cancel commit gate — edits autosave; the host's
    /// back button just calls `endEmbeddedSession()` to tear down.
    func beginEmbeddedSession(
        imageURL: URL,
        document: CaptureMarkupDocument? = nil,
        instruction: String? = nil
    ) -> CaptureMarkupPanelRootView {
        closeSession(discard: false)

        self.imageURL = imageURL
        self.onComplete = nil

        let doc = document ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? emptyDocument(for: imageURL)
        currentDocument = doc

        let root = CaptureMarkupPanelRootView(frame: NSRect(x: 0, y: 0, width: 1180, height: 720))
        rootView = root
        root.setDragPayloadProvider { [weak self] in
            self?.makeDragPayload()
        }
        root.inputBar.delegate = self
        if let instruction, !instruction.isEmpty {
            root.inputBar.promptText = instruction
        }
        syncChrome(layerCount: doc.layers.count, selection: nil)

        let session = CaptureMarkupWebSession()
        session.onMessage = { [weak self] message in
            self?.handleBridge(message: message)
        }
        session.attach(to: root.webHost)
        webSession = session

        session.start(imageURL: imageURL, document: doc, instruction: instruction)
        SettingsManager.shared.isMarkupSessionActive = true
        log.info("Capture markup embedded session opened", detail: imageURL.lastPathComponent)
        return root
    }

    /// Tear down an embedded session. Idempotent — safe to call from the
    /// host's `onDisappear` even after the session already ended. Edits are
    /// already persisted via autosave, so this only releases the web view.
    func endEmbeddedSession() {
        guard webSession != nil || rootView != nil else { return }
        closeSession(discard: false)
    }

    func openSessionIfNeeded(imageURL: URL, instruction: String? = nil) {
        Task {
            let runsAgentImmediately = instruction?.isEmpty == false
            do {
                if let instruction, !instruction.isEmpty {
                    _ = try await CaptureMarkupAgentService.shared.runInstruction(
                        imageURL: imageURL,
                        instruction: instruction,
                        openWebBay: true
                    )
                } else {
                    openSession(imageURL: imageURL)
                }
            } catch {
                log.error("Failed to open markup session", detail: error.localizedDescription)
                if !runsAgentImmediately {
                    presentAgentError(error)
                }
            }
        }
    }

    // MARK: - CaptureMarkupPanelChromeDelegate

    func captureMarkupPanelDidAccept() {
        Task {
            guard let doc = await webSession?.fetchDocument() else {
                finish(with: .success(nil))
                return
            }
            if let imageURL {
                try? CaptureMarkupStorage.save(doc, forImageURL: imageURL)
            }
            finish(with: .success(doc))
        }
    }

    func captureMarkupPanelDidSave() {
        // Explicit Save — persist the current canvas document to the sidecar
        // now, then confirm on the button. Distinct from Accept: the panel
        // stays open. Autosave on `markup.update` may already have written
        // the same bytes; this path exists for explicit, user-confirmed save.
        Task {
            guard let imageURL else { return }
            let doc = await webSession?.fetchDocument() ?? currentDocument
            guard let doc else { return }
            currentDocument = doc
            do {
                try CaptureMarkupStorage.save(doc, forImageURL: imageURL)
                rootView?.inputBar.flashSaved()
            } catch {
                log.error("Capture markup explicit save failed", detail: error.localizedDescription)
                captureMarkupPanelDidReportError("Could not save the markup: \(error.localizedDescription)")
            }
        }
    }

    func captureMarkupPanelDidCancel() {
        if let imageURL {
            CaptureMarkupStorage.deleteSidecar(forImageURL: imageURL)
        }
        finish(with: .success(nil))
    }

    func captureMarkupPanelDidRun(instruction: String, providerId: String?, modelId: String?) {
        guard let imageURL else { return }
        rootView?.inputBar.setRunning(true)
        let started = Date()
        passCount += 1
        let pass = passCount
        Task {
            defer {
                rootView?.inputBar.setRunning(false)
            }
            let includedLayers = await webSession?.fetchMessageLayers() ?? []
            webSession?.clearSelection()
            webSession?.beginThread(
                instruction: instruction,
                pass: pass,
                attachmentCount: includedLayers.count
            )
            var runModelLabel = await CaptureMarkupAgentService.shared.currentModelLabel(
                providerId: providerId,
                modelId: modelId
            )
            if let runModelLabel {
                webSession?.updateThreadModel(
                    runModelLabel,
                    elapsed: Date().timeIntervalSince(started)
                )
            }
            var planSummary: String?
            do {
                let existing = await webSession?.fetchDocument()
                let beforeLayers = Dictionary(
                    uniqueKeysWithValues: (existing?.layers ?? []).map { ($0.id, $0) }
                )
                let beforeIDs = Set(beforeLayers.keys)
                var doc = try await CaptureMarkupAgentService.shared.runInstruction(
                    imageURL: imageURL,
                    instruction: instruction,
                    includedLayers: includedLayers,
                    existing: existing,
                    openWebBay: false,
                    providerId: providerId,
                    modelId: modelId,
                    onPhase: { [weak self] phase in
                        if case .planning(let model) = phase {
                            runModelLabel = model
                        }
                        if case .planned(let detail) = phase {
                            planSummary = detail
                        }
                        self?.webSession?.handlePhase(
                            phase,
                            elapsed: Date().timeIntervalSince(started)
                        )
                    }
                )
                let elapsed = Date().timeIntervalSince(started)
                let changedIDs = Set(doc.layers.filter { beforeLayers[$0.id] != $0 }.map(\.id))
                annotateTurn(
                    in: &doc,
                    changedLayerIDs: changedIDs,
                    pass: pass,
                    instruction: instruction,
                    model: runModelLabel,
                    summary: planSummary,
                    elapsed: elapsed
                )
                currentDocument = doc
                if !changedIDs.isEmpty {
                    try? CaptureMarkupStorage.save(doc, forImageURL: imageURL)
                }
                webSession?.push(document: doc)
                let added = doc.layers.filter { !beforeIDs.contains($0.id) }
                await webSession?.finishThread(
                    added: added,
                    elapsed: elapsed,
                    pass: pass
                )
                webSession?.clearMessageLayers()
                syncChrome(layerCount: doc.layers.count, selection: nil)
                rootView?.inputBar.clearPrompt()
            } catch {
                webSession?.failThread(elapsed: Date().timeIntervalSince(started))
                log.error("Markup run failed", detail: error.localizedDescription)
                presentAgentError(error)
            }
        }
    }

    func captureMarkupPanelDidClearSelection() {
        webSession?.clearSelection()
    }

    func captureMarkupPanelDidRemoveAttachment(id: String) {
        webSession?.removeMessageLayer(id: id)
    }

    func captureMarkupPanelTryExampleSelected(_ text: String) {
        rootView?.inputBar.promptText = text
    }

    func captureMarkupPanelDidReportError(_ message: String) {
        presentUserMessage(message, preferAlert: panel == nil, opensAISettings: false)
    }

    func presentAgentError(_ error: Error) {
        presentUserMessage(
            Self.userFacingMessage(for: error),
            preferAlert: panel == nil || Self.opensAISettings(for: error),
            opensAISettings: Self.opensAISettings(for: error)
        )
    }

    private func presentUserMessage(
        _ message: String,
        preferAlert: Bool,
        opensAISettings: Bool
    ) {
        guard preferAlert else { return }

        let alert = NSAlert()
        alert.messageText = "Capture Markup"
        alert.informativeText = message
        alert.alertStyle = .warning
        if opensAISettings {
            alert.addButton(withTitle: "Open AI Providers")
            alert.addButton(withTitle: "OK")
        } else {
            alert.addButton(withTitle: "OK")
        }

        if alert.runModal() == .alertFirstButtonReturn, opensAISettings {
            openAIProviderSettings()
        }
    }

    private func handleBridge(message: CaptureMarkupBridgeMessage) {
        switch message.type {
        case "markup.ready":
            if let error = message.error {
                captureMarkupPanelDidReportError("Capture canvas could not load: \(error)")
            }
        case "markup.update":
            if let doc = message.document, let imageURL {
                currentDocument = doc
                try? CaptureMarkupStorage.save(doc, forImageURL: imageURL)
            }
            syncChrome(
                layerCount: message.layerCount ?? message.document?.layers.count ?? layerCount,
                selection: message.selection
            )
        case "markup.save":
            // Explicit Save via ⌘S while the canvas (WKWebView) has key
            // focus. The button's own ⌘S keyEquivalent + saveTapped covers
            // the prompt-focused case; both end here. Persist now and
            // confirm on the button. Stays open — distinct from Accept.
            if let doc = message.document, let imageURL {
                currentDocument = doc
                do {
                    try CaptureMarkupStorage.save(doc, forImageURL: imageURL)
                    rootView?.inputBar.flashSaved()
                } catch {
                    log.error("Capture markup explicit save failed", detail: error.localizedDescription)
                    captureMarkupPanelDidReportError("Could not save the markup: \(error.localizedDescription)")
                }
            }
        case "markup.stats":
            syncChrome(
                layerCount: message.layerCount ?? layerCount,
                selection: currentSelection
            )
        case "markup.selection":
            syncChrome(
                layerCount: message.layerCount ?? layerCount,
                selection: message.selection
            )
        case "markup.attachments":
            rootView?.inputBar.setAttachments(message.selections)
        case "markup.attach":
            // Explicit user gesture from the layers sidebar (clicked
            // the ⠿ grip on a layer row). This is the ONLY path that
            // populates the attachments row — selection alone no
            // longer auto-attaches. See TLK-022 / markup chrome notes.
            if let selection = message.selection {
                rootView?.inputBar.setAttachments([selection])
            }
        default:
            break
        }
    }

    private func syncChrome(layerCount: Int, selection: CaptureMarkupLayerSelection?) {
        self.layerCount = layerCount
        currentSelection = selection
        let touchUp = layerCount > 0
        // Drag-out is always offered while a session is open — the payload
        // renders the current PNG (annotated or not), so there's always
        // something to drag. Keeps the centered handle present at the
        // bottom instead of only appearing after the first annotation.
        rootView?.setDragOutAvailable(true)
        rootView?.inputBar.setTouchUpMode(touchUp)
        // Selection no longer auto-attaches — the attachments row only
        // populates from an explicit user gesture (drag from the
            // layers sidebar). Selection still updates the canvas
            // highlight + inspector panel on the JS side; Swift just
            // doesn't drag the chip into the composer anymore.
    }

    private func annotateTurn(
        in document: inout CaptureMarkupDocument,
        changedLayerIDs: Set<String>,
        pass: Int,
        instruction: String,
        model: String?,
        summary: String?,
        elapsed: TimeInterval
    ) {
        guard !changedLayerIDs.isEmpty else { return }
        let cleanModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in document.layers.indices where changedLayerIDs.contains(document.layers[index].id) {
            document.layers[index].turnPass = pass
            document.layers[index].turnInstruction = instruction
            document.layers[index].turnModel = cleanModel?.isEmpty == false ? cleanModel : nil
            document.layers[index].turnSummary = cleanSummary?.isEmpty == false ? cleanSummary : nil
            document.layers[index].turnElapsed = elapsed
        }
    }

    private func finish(with result: Result<CaptureMarkupDocument?, Error>) {
        let callback = onComplete
        closeSession(discard: false)
        callback?(result)
    }

    private func closeSession(discard: Bool) {
        SettingsManager.shared.isMarkupSessionActive = false
        if discard, let imageURL {
            CaptureMarkupStorage.deleteSidecar(forImageURL: imageURL)
        }
        webSession?.teardown()
        webSession = nil
        rootView = nil
        panel?.orderOut(nil)
        panel = nil
        imageURL = nil
        onComplete = nil
        layerCount = 0
        passCount = 0
        currentSelection = nil
        currentDocument = nil
        cleanupDragExports()
    }

    private func makeDragPayload() -> (fileURL: URL, dragImage: NSImage)? {
        guard let imageURL else { return nil }
        let document = currentDocument
            ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? emptyDocument(for: imageURL)

        do {
            let data = try CaptureMarkupAgentService.shared.renderPNG(
                imageURL: imageURL,
                document: document
            )
            let fileURL = FileManager.default.temporaryDirectory
                .appending(path: "talkie-markup-drag-\(UUID().uuidString).png")
            try data.write(to: fileURL, options: .atomic)
            dragExportURLs.append(fileURL)

            let image = NSImage(data: data) ?? NSWorkspace.shared.icon(forFile: fileURL.path)
            return (fileURL: fileURL, dragImage: image)
        } catch {
            log.error("Capture markup drag export failed", detail: error.localizedDescription)
            presentUserMessage(
                "Could not prepare the annotated screenshot for dragging.",
                preferAlert: false,
                opensAISettings: false
            )
            return nil
        }
    }

    private func cleanupDragExports() {
        let urls = dragExportURLs
        dragExportURLs = []
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Talkie · Capture Markup"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()
        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView?.wantsLayer = true
        return panel
    }

    private func emptyDocument(for imageURL: URL) -> CaptureMarkupDocument {
        if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return CaptureMarkupDocument(
                imageWidth: Double(image.width),
                imageHeight: Double(image.height)
            )
        }
        return CaptureMarkupDocument(imageWidth: 1, imageHeight: 1)
    }

    private func openAIProviderSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NavigationState.shared.navigateToSettings(.aiProviders)
    }

    private static func userFacingMessage(for error: Error) -> String {
        let base = error.localizedDescription
        guard let suggestion = (error as? LocalizedError)?.recoverySuggestion,
              !suggestion.isEmpty else {
            return base
        }
        return "\(base) \(suggestion)"
    }

    private static func opensAISettings(for error: Error) -> Bool {
        if let markupError = error as? CaptureMarkupAgentError,
           case .providerUnavailable = markupError {
            return true
        }

        if let llmError = error as? LLMError {
            switch llmError {
            case .providerNotAvailable, .configurationError, .notConfigured:
                return true
            case .modelNotFound, .generationFailed:
                return false
            }
        }

        return false
    }
}

struct CaptureMarkupLayerSelection: Equatable {
    let id: String
    let label: String
    let kind: String
}

struct CaptureMarkupBridgeMessage {
    let type: String
    let sessionId: String?
    let document: CaptureMarkupDocument?
    let instruction: String?
    let layerCount: Int?
    let selection: CaptureMarkupLayerSelection?
    let selections: [CaptureMarkupLayerSelection]
    let error: String?

    static func parse(_ body: Any) -> CaptureMarkupBridgeMessage? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else { return nil }

        var document: CaptureMarkupDocument?
        if let docObj = dict["document"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: docObj),
           let decoded = try? JSONDecoder().decode(CaptureMarkupDocument.self, from: data) {
            document = decoded
        } else if let docString = dict["document"] as? String,
                  let data = docString.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(CaptureMarkupDocument.self, from: data) {
            document = decoded
        }

        var selection: CaptureMarkupLayerSelection?
        if let sel = dict["selection"] as? [String: Any],
           let id = sel["id"] as? String,
           let kind = sel["kind"] as? String {
            selection = CaptureMarkupLayerSelection(
                id: id,
                label: sel["label"] as? String ?? kind,
                kind: kind
            )
        }

        let selections: [CaptureMarkupLayerSelection]
        if let array = dict["selections"] as? [[String: Any]] {
            selections = array.compactMap { item in
                guard let id = item["id"] as? String,
                      let kind = item["kind"] as? String else { return nil }
                return CaptureMarkupLayerSelection(
                    id: id,
                    label: item["label"] as? String ?? kind,
                    kind: kind
                )
            }
        } else if let selection {
            selections = [selection]
        } else {
            selections = []
        }

        return CaptureMarkupBridgeMessage(
            type: type,
            sessionId: dict["sessionId"] as? String,
            document: document,
            instruction: dict["instruction"] as? String,
            layerCount: intValue(dict["layerCount"]),
            selection: selection,
            selections: selections,
            error: dict["error"] as? String
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
