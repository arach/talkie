//
//  AgentCaptureMarkupController.swift
//  TalkieAgent
//
//  Lightweight in-place screenshot markup for Agent-owned captures. This reuses
//  the live recording markup overlay, then bakes the resulting layers into the
//  captured PNG so the drag-out artifact is immediately shareable.
//

import AppKit
import ImageIO
import TalkieKit

@MainActor
final class AgentCaptureMarkupController {
    static let shared = AgentCaptureMarkupController()

    private let log = Log(.ui)
    private var overlay: LiveCaptureMarkupOverlayController?
    private var backgroundPanel: NSPanel?
    private var resizeHandlePanels: [AgentCaptureMarkupResizeHandlePanel] = []
    private var dragHandlePanel: NSPanel?
    private var dragExportURLs: [URL] = []
    private var currentPlacement: AgentCaptureMarkupPlacement?
    private var activeImageSize: CGSize?

    private init() {}

    @discardableResult
    func open(fileURL: URL, captureRect: CGRect? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            log.warning("Agent capture markup skipped: screenshot file missing", detail: fileURL.path)
            return false
        }
        guard let sourceImage = Self.loadCGImage(at: fileURL) else {
            log.error("Agent capture markup skipped: unable to load image", detail: fileURL.path)
            return false
        }

        let item = AgentLiveTrayItem(
            id: UUID(),
            kind: .screenshot,
            capturedAt: Date(),
            filename: fileURL.lastPathComponent,
            width: sourceImage.width,
            height: sourceImage.height,
            captureMode: "markup",
            fileURL: fileURL
        )
        open(item: item, captureRect: captureRect, updatesLibrary: false)
        return true
    }

    func open(item: AgentLiveTrayItem, captureRect: CGRect? = nil) {
        open(item: item, captureRect: captureRect, updatesLibrary: true)
    }

    private func open(item: AgentLiveTrayItem, captureRect: CGRect?, updatesLibrary: Bool) {
        guard item.isScreenshot else { return }
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            log.warning("Agent capture markup skipped: screenshot file missing", detail: item.fileURL.path)
            return
        }
        guard let sourceImage = Self.loadCGImage(at: item.fileURL) else {
            log.error("Agent capture markup skipped: unable to load image", detail: item.fileURL.path)
            return
        }
        guard let placement = Self.placement(for: item, captureRect: captureRect) else {
            log.error("Agent capture markup skipped: no screen available")
            return
        }

        dismiss()
        currentPlacement = placement
        activeImageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        showBackground(
            title: Self.markupTitle(for: item),
            image: sourceImage,
            placement: placement,
            onDone: { [weak self] in
                guard let self else { return }
                finish(
                    item: item,
                    sourceImage: sourceImage,
                    layers: self.overlay?.layers ?? [],
                    updatesLibrary: updatesLibrary
                )
            },
            onCancel: { [weak self] in
                self?.cancel(item: item)
            },
            onDelete: { [weak self] in
                self?.delete(item: item, updatesLibrary: updatesLibrary)
            },
            onOpenInTalkie: { [weak self] in
                self?.openInTalkie(item: item, sourceImage: sourceImage)
            }
        )

        let overlay = LiveCaptureMarkupOverlayController()
        overlay.passthrough = false
        overlay.persistsLayersOnDone = false
        overlay.isVisibleInScreenCapture = true
        overlay.showsCaptureAction = false
        overlay.showsDock = true
        overlay.showsWindowChrome = false
        overlay.usesCompactDock = true
        overlay.supportsAutoBlurText = true
        overlay.setSourceImage(sourceImage)
        overlay.onDone = { [weak self] layers in
            self?.finish(item: item, sourceImage: sourceImage, layers: layers, updatesLibrary: updatesLibrary)
        }
        overlay.onCancel = { [weak self] in
            self?.cancel(item: item)
        }
        overlay.onDismissRequest = { [weak self] in
            self?.dismiss()
        }
        overlay.onAutoBlurText = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            self.autoBlurText(in: sourceImage, overlay: overlay)
        }
        overlay.additionalMousePassthroughScreenRects = { [weak self] in
            guard let placement = self?.currentPlacement else { return [] }
            return Self.nativeControlPassthroughRects(for: placement)
        }
        overlay.show(on: placement.screen, targetRect: Self.overlayRect(for: placement))
        overlay.setDrawableRect(Self.overlayDrawableRect(for: placement))
        overlay.setTool("ink")
        showResizeHandles(for: placement)
        showDragHandle(
            item: item,
            sourceImage: sourceImage,
            placement: placement
        )

        self.overlay = overlay
        log.info(
            "Agent quick markup opened",
            detail: "file=\(item.fileURL.lastPathComponent) imageRect=\(Int(placement.imageRect.width))x\(Int(placement.imageRect.height))"
        )
    }

    func dismiss() {
        overlay?.dismiss(discardLayers: true)
        overlay = nil
        currentPlacement = nil
        activeImageSize = nil
        hideResizeHandles()
        hideDragHandle()
        hideBackground()
        cleanupDragExports()
    }

    private func finish(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        layers: [CaptureMarkupLayer],
        updatesLibrary: Bool
    ) {
        overlay?.dismiss(discardLayers: false)
        hideBackground()
        hideResizeHandles()
        hideDragHandle()
        overlay = nil
        currentPlacement = nil
        activeImageSize = nil

        Task { @MainActor in
            await bakeIfNeeded(
                item: item,
                sourceImage: sourceImage,
                layers: layers,
                updatesLibrary: updatesLibrary
            )
        }
    }

    private func cancel(item: AgentLiveTrayItem) {
        overlay?.dismiss(discardLayers: true)
        hideBackground()
        hideResizeHandles()
        hideDragHandle()
        overlay = nil
        currentPlacement = nil
        activeImageSize = nil
        log.info("Agent quick markup cancelled", detail: item.fileURL.lastPathComponent)
    }

    private func delete(item: AgentLiveTrayItem, updatesLibrary: Bool) {
        overlay?.dismiss(discardLayers: true)
        hideBackground()
        hideResizeHandles()
        hideDragHandle()
        overlay = nil
        currentPlacement = nil
        activeImageSize = nil

        Task {
            let removedTrayItem = await AgentLiveTrayAssetStore.shared.deleteItem(item)
            if updatesLibrary {
                AgentCaptureLibraryWriter.deleteCaptureReference(id: item.id, fileURL: item.fileURL)
            } else if !removedTrayItem {
                Self.deleteLooseFile(item.fileURL)
            }
        }
        log.info("Agent quick markup deleted", detail: item.fileURL.lastPathComponent)
    }

    private func openInTalkie(item: AgentLiveTrayItem, sourceImage: CGImage) {
        let document = CaptureMarkupDocument(
            imageWidth: Double(sourceImage.width),
            imageHeight: Double(sourceImage.height),
            layers: overlay?.layers ?? []
        )

        do {
            try CaptureMarkupStorage.save(document, forImageURL: item.fileURL)
        } catch {
            log.error(
                "Agent quick markup handoff save failed: \(error.localizedDescription)",
                detail: item.fileURL.path
            )
            return
        }

        var components = URLComponents()
        components.scheme = TalkieEnvironment.current.talkieURLScheme
        components.host = "capture"
        components.path = "/markup"
        components.queryItems = [URLQueryItem(name: "path", value: item.fileURL.path)]
        guard let url = components.url, NSWorkspace.shared.open(url) else {
            log.error("Agent quick markup handoff failed to open Talkie", detail: item.fileURL.path)
            return
        }

        log.info("Agent quick markup handed off to Talkie", detail: item.fileURL.lastPathComponent)
        dismiss()
    }

    private func autoBlurText(
        in sourceImage: CGImage,
        overlay requestedOverlay: LiveCaptureMarkupOverlayController
    ) {
        requestedOverlay.setAutoBlurTextRunning(true)
        Task { @MainActor [weak self, weak requestedOverlay] in
            guard let self, let requestedOverlay, self.overlay === requestedOverlay else { return }
            do {
                let result = try await VisionOCRService.shared.recognizeTextWithGeometry(in: sourceImage)
                let blurLayers = CaptureMarkupAutoBlur.layers(for: result)
                guard self.overlay === requestedOverlay else { return }
                requestedOverlay.replaceAutoBlurTextLayers(blurLayers)
                requestedOverlay.setAutoBlurTextRunning(false)
                log.info("Agent quick markup auto-blurred text", detail: "regions=\(blurLayers.count)")
            } catch VisionOCRError.noTextFound {
                guard self.overlay === requestedOverlay else { return }
                requestedOverlay.replaceAutoBlurTextLayers([])
                requestedOverlay.setAutoBlurTextRunning(false)
                log.info("Agent quick markup auto-blur found no text")
            } catch {
                guard self.overlay === requestedOverlay else { return }
                requestedOverlay.setAutoBlurTextRunning(false)
                log.error("Agent quick markup auto-blur failed: \(error.localizedDescription)")
            }
        }
    }

    private func bakeIfNeeded(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        layers: [CaptureMarkupLayer],
        updatesLibrary: Bool
    ) async {
        guard !layers.isEmpty else {
            log.info("Agent quick markup finished without layers", detail: item.fileURL.lastPathComponent)
            return
        }

        let document = CaptureMarkupDocument(
            imageWidth: Double(sourceImage.width),
            imageHeight: Double(sourceImage.height),
            layers: layers
        )

        let data = await Task.detached(priority: .userInitiated) {
            CaptureMarkupRenderer.encodedData(
                image: sourceImage,
                document: document,
                format: .png,
                scale: 1
            )
        }.value

        guard let data else {
            log.error("Agent quick markup bake failed", detail: item.fileURL.lastPathComponent)
            return
        }

        do {
            try data.write(to: item.fileURL, options: .atomic)
            CaptureMarkupStorage.deleteSidecar(forImageURL: item.fileURL)
            if updatesLibrary {
                AgentCaptureLibraryWriter.persistScreenshotReference(
                    fileURL: item.fileURL,
                    id: item.id,
                    capturedAt: item.capturedAt,
                    captureMode: item.captureMode,
                    width: sourceImage.width,
                    height: sourceImage.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    appBundleID: item.appBundleID,
                    displayName: item.displayName,
                    ocrText: item.ocrText
                )
                Self.postAssetsDidChange()
            }
            log.info(
                "Agent quick markup saved",
                detail: "file=\(item.fileURL.lastPathComponent) layers=\(layers.count)"
            )
        } catch {
            log.error("Agent quick markup save failed: \(error.localizedDescription)", detail: item.fileURL.path)
        }
    }

    private func showBackground(
        title: String,
        image: CGImage,
        placement: AgentCaptureMarkupPlacement,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenInTalkie: @escaping () -> Void
    ) {
        let view = AgentCaptureMarkupBackgroundView(
            title: title,
            image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            imageRect: Self.relativeImageRect(for: placement),
            onDragDelta: { [weak self] delta in
                self?.moveSurface(by: delta)
            },
            onResizeDelta: { [weak self] edges, delta in
                self?.resizeSurface(edges: edges, by: delta)
            },
            onZoom: { [weak self] factor in
                self?.zoomSurface(by: factor)
            },
            onDone: onDone,
            onCancel: onCancel,
            onDelete: onDelete,
            onOpenInTalkie: onOpenInTalkie
        )
        view.frame = NSRect(origin: .zero, size: placement.surfaceRect.size)

        let panel = AgentCaptureMarkupBackgroundPanel(
            contentRect: placement.surfaceRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.sharingType = .readOnly
        panel.setFrameOrigin(placement.surfaceRect.origin)
        panel.orderFrontRegardless()
        backgroundPanel = panel
    }

    private func moveSurface(by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        Self.move(backgroundPanel, by: delta)
        overlay?.moveBy(delta)
        resizeHandlePanels.forEach { Self.move($0, by: delta) }
        Self.move(dragHandlePanel, by: delta)
        if let placement = currentPlacement {
            currentPlacement = placement.offsetBy(delta)
        }
    }

    private static func move(_ panel: NSPanel?, by delta: CGSize) {
        guard let panel else { return }
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + delta.width,
            y: panel.frame.minY + delta.height
        ))
    }

    private func hideBackground() {
        backgroundPanel?.orderOut(nil)
        backgroundPanel?.contentView = nil
        backgroundPanel = nil
    }

    private func zoomSurface(by factor: CGFloat) {
        guard let placement = currentPlacement,
              let imageSize = activeImageSize else {
            return
        }

        applyPlacement(Self.zoomedPlacement(
            from: placement,
            imageSize: imageSize,
            factor: factor
        ))
    }

    private func resizeSurface(edges: AgentCaptureMarkupResizeEdges, by delta: CGSize) {
        guard !edges.isEmpty,
              let placement = currentPlacement,
              let imageSize = activeImageSize else {
            return
        }

        applyPlacement(Self.resizedPlacement(
            from: placement,
            imageSize: imageSize,
            edges: edges,
            delta: delta
        ))
    }

    private func applyPlacement(_ placement: AgentCaptureMarkupPlacement) {
        currentPlacement = placement

        backgroundPanel?.setFrame(placement.surfaceRect, display: true)
        if let backgroundView = backgroundPanel?.contentView as? AgentCaptureMarkupBackgroundView {
            backgroundView.frame = NSRect(origin: .zero, size: placement.surfaceRect.size)
            backgroundView.updateImageRect(Self.relativeImageRect(for: placement))
        }

        overlay?.setFrame(Self.overlayRect(for: placement))
        overlay?.setDrawableRect(Self.overlayDrawableRect(for: placement))
        updateResizeHandleFrames(for: placement)
        dragHandlePanel?.setFrame(Self.dragHandleFrame(for: placement), display: true)
    }

    private func showResizeHandles(for placement: AgentCaptureMarkupPlacement) {
        hideResizeHandles()
        resizeHandlePanels = Self.resizeHandleFrames(for: placement).map { frame, edges in
            let view = AgentCaptureMarkupResizeHandleView(
                edges: edges,
                onResizeDelta: { [weak self] delta in
                    self?.resizeSurface(edges: edges, by: delta)
                }
            )
            view.frame = NSRect(origin: .zero, size: frame.size)
            view.wantsLayer = true
            // WindowServer can omit a fully transparent auxiliary window from
            // mouse hit testing. Keep an imperceptible surface so these native
            // edge zones consistently own both cursor and drag events.
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor

            let panel = AgentCaptureMarkupResizeHandlePanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = view
            panel.level = .screenSaver + 3
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.canHide = false
            panel.acceptsMouseMovedEvents = true
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.sharingType = .readOnly
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func updateResizeHandleFrames(for placement: AgentCaptureMarkupPlacement) {
        let frames = Self.resizeHandleFrames(for: placement)
        guard frames.count == resizeHandlePanels.count else {
            showResizeHandles(for: placement)
            return
        }
        for (panel, handle) in zip(resizeHandlePanels, frames) {
            panel.setFrame(handle.frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: handle.frame.size)
        }
    }

    private func hideResizeHandles() {
        resizeHandlePanels.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        resizeHandlePanels.removeAll()
    }

    private func showDragHandle(
        item: AgentLiveTrayItem,
        sourceImage: CGImage,
        placement: AgentCaptureMarkupPlacement
    ) {
        hideDragHandle()

        let size = Self.dragHandleSize
        let handleFrame = Self.dragHandleFrame(for: placement)
        let view = AgentCaptureMarkupDragHandleView(
            fileURLProvider: { [weak self] in
                self?.dragURL(item: item, sourceImage: sourceImage)
            }
        )
        view.frame = NSRect(origin: .zero, size: size)

        let panel = AgentCaptureMarkupDragHandlePanel(
            contentRect: handleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .readOnly
        panel.orderFrontRegardless()
        dragHandlePanel = panel
    }

    private static var dragHandleSize: NSSize {
        NSSize(width: 112, height: 28)
    }

    private static func dragHandleFrame(for placement: AgentCaptureMarkupPlacement) -> NSRect {
        let size = dragHandleSize
        let frame = placement.surfaceRect
        let visible = placement.screen.visibleFrame.insetBy(dx: 4, dy: 4)
        let x = clamp(
            frame.midX - size.width / 2,
            min: visible.minX,
            max: visible.maxX - size.width
        )
        let preferredY = frame.minY - size.height + AgentCaptureMarkupLayout.dragHandleOverlap
        let fallbackY = frame.minY + 6
        let y = clamp(
            preferredY >= visible.minY ? preferredY : fallbackY,
            min: visible.minY,
            max: visible.maxY - size.height
        )
        return NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func hideDragHandle() {
        dragHandlePanel?.orderOut(nil)
        dragHandlePanel?.contentView = nil
        dragHandlePanel = nil
    }

    private func dragURL(item: AgentLiveTrayItem, sourceImage: CGImage) -> URL? {
        let layers = overlay?.layers ?? []
        guard !layers.isEmpty else { return item.fileURL }

        let document = CaptureMarkupDocument(
            imageWidth: Double(sourceImage.width),
            imageHeight: Double(sourceImage.height),
            layers: layers
        )
        guard let data = CaptureMarkupRenderer.encodedData(
            image: sourceImage,
            document: document,
            format: .png,
            scale: 1
        ) else {
            log.error("Agent quick markup drag render failed", detail: item.fileURL.lastPathComponent)
            return item.fileURL
        }

        let base = item.fileURL.deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-markup-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            dragExportURLs.append(url)
            return url
        } catch {
            log.error("Agent quick markup drag write failed: \(error.localizedDescription)", detail: url.path)
            return item.fileURL
        }
    }

    private func cleanupDragExports() {
        for url in dragExportURLs {
            try? FileManager.default.removeItem(at: url)
        }
        dragExportURLs.removeAll(keepingCapacity: false)
    }

    private static func placement(
        for item: AgentLiveTrayItem,
        captureRect: CGRect?
    ) -> AgentCaptureMarkupPlacement? {
        let screen = screen(for: captureRect)
            ?? screen(containing: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let imageSize = CGSize(width: max(1, item.width), height: max(1, item.height))
        if let rect = usableInPlaceRect(captureRect, on: screen),
           let exactPlacement = exactInPlacePlacement(imageRect: rect, on: screen) {
            return exactPlacement
        }

        let preferredCenter = captureRect.map { NSPoint(x: $0.midX, y: $0.midY) }
        let surfaceRect = fittedPreviewRect(
            imageSize: imageSize,
            on: screen,
            preferredCenter: preferredCenter
        )
        let imageRect = aspectFitRect(
            imageSize: imageSize,
            in: contentRect(in: surfaceRect)
        )
        return AgentCaptureMarkupPlacement(screen: screen, surfaceRect: surfaceRect, imageRect: imageRect)
    }

    private static func usableInPlaceRect(_ rect: CGRect?, on screen: NSScreen) -> CGRect? {
        guard let rect = rect?.standardized,
              rect.width >= 420,
              rect.height >= 260 else {
            return nil
        }
        let clipped = rect.intersection(screen.frame)
        guard !clipped.isNull, clipped.width >= 420, clipped.height >= 260 else { return nil }
        return clipped
    }

    private static func exactInPlacePlacement(
        imageRect: CGRect,
        on screen: NSScreen
    ) -> AgentCaptureMarkupPlacement? {
        let safe = screen.frame.insetBy(dx: 4, dy: 4)
        let surfaceRect = CGRect(
            x: imageRect.minX - AgentCaptureMarkupLayout.edgePadding,
            y: imageRect.minY - AgentCaptureMarkupLayout.edgePadding - AgentCaptureMarkupLayout.bottomToolbarHeight,
            width: imageRect.width + AgentCaptureMarkupLayout.edgePadding * 2,
            height: imageRect.height + AgentCaptureMarkupLayout.edgePadding * 2
                + AgentCaptureMarkupLayout.titlebarHeight
                + AgentCaptureMarkupLayout.bottomToolbarHeight
        )

        guard safe.contains(surfaceRect) else { return nil }
        return AgentCaptureMarkupPlacement(
            screen: screen,
            surfaceRect: surfaceRect,
            imageRect: imageRect
        )
    }

    private static func fittedPreviewRect(
        imageSize: CGSize,
        on screen: NSScreen,
        preferredCenter: NSPoint?
    ) -> CGRect {
        let visible = screen.visibleFrame.insetBy(dx: 22, dy: 44)
        let ratio = max(0.05, imageSize.width / max(1, imageSize.height))
        let maxWidth = min(1100, visible.width)
        let maxHeight = min(760, visible.height)

        let chromeWidth = AgentCaptureMarkupLayout.edgePadding * 2
        let chromeHeight = AgentCaptureMarkupLayout.edgePadding * 2
            + AgentCaptureMarkupLayout.titlebarHeight
            + AgentCaptureMarkupLayout.bottomToolbarHeight
        let maxImageWidth = max(1, maxWidth - chromeWidth)
        let maxImageHeight = max(1, maxHeight - chromeHeight)
        var imageWidth = maxImageWidth
        var imageHeight = imageWidth / ratio
        if imageHeight > maxImageHeight {
            imageHeight = maxImageHeight
            imageWidth = imageHeight * ratio
        }

        imageWidth = min(max(imageWidth, min(420, maxImageWidth)), maxImageWidth)
        imageHeight = min(max(imageHeight, min(260, maxImageHeight)), maxImageHeight)

        let width = min(maxWidth, imageWidth + chromeWidth)
        let height = min(maxHeight, imageHeight + chromeHeight)

        let center = preferredCenter ?? NSPoint(x: visible.midX, y: visible.midY)
        let x = clamp(center.x - width / 2, min: visible.minX, max: visible.maxX - width)
        let y = clamp(center.y - height / 2, min: visible.minY, max: visible.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    private static func contentRect(in surfaceRect: CGRect) -> CGRect {
        CGRect(
            x: surfaceRect.minX + AgentCaptureMarkupLayout.edgePadding,
            y: surfaceRect.minY + AgentCaptureMarkupLayout.edgePadding + AgentCaptureMarkupLayout.bottomToolbarHeight,
            width: max(1, surfaceRect.width - AgentCaptureMarkupLayout.edgePadding * 2),
            height: max(
                1,
                surfaceRect.height
                    - AgentCaptureMarkupLayout.edgePadding * 2
                    - AgentCaptureMarkupLayout.titlebarHeight
                    - AgentCaptureMarkupLayout.bottomToolbarHeight
            )
        )
    }

    private static func overlayRect(for placement: AgentCaptureMarkupPlacement) -> CGRect {
        let drawingWellMaxY = placement.surfaceRect.maxY - AgentCaptureMarkupLayout.titlebarHeight
        return CGRect(
            x: placement.surfaceRect.minX,
            y: placement.surfaceRect.minY,
            width: placement.surfaceRect.width,
            height: max(1, drawingWellMaxY - placement.surfaceRect.minY)
        )
    }

    private static func overlayDrawableRect(for placement: AgentCaptureMarkupPlacement) -> CGRect {
        let overlay = overlayRect(for: placement)
        return CGRect(
            x: placement.imageRect.minX - overlay.minX,
            y: overlay.maxY - placement.imageRect.maxY,
            width: placement.imageRect.width,
            height: placement.imageRect.height
        )
    }

    private static func resizeHandleFrames(
        for placement: AgentCaptureMarkupPlacement
    ) -> [(frame: CGRect, edges: AgentCaptureMarkupResizeEdges)] {
        let surface = placement.surfaceRect.standardized
        let thickness = min(
            AgentCaptureMarkupLayout.resizeHandleThickness,
            surface.width / 3,
            surface.height / 3
        )
        let horizontalLength = max(1, surface.width - thickness * 2)
        let verticalLength = max(1, surface.height - thickness * 2)
        return [
            (CGRect(x: surface.minX, y: surface.maxY - thickness, width: thickness, height: thickness), [.top, .left]),
            (CGRect(x: surface.maxX - thickness, y: surface.maxY - thickness, width: thickness, height: thickness), [.top, .right]),
            (CGRect(x: surface.minX, y: surface.minY, width: thickness, height: thickness), [.bottom, .left]),
            (CGRect(x: surface.maxX - thickness, y: surface.minY, width: thickness, height: thickness), [.bottom, .right]),
            (CGRect(x: surface.minX + thickness, y: surface.maxY - thickness, width: horizontalLength, height: thickness), [.top]),
            (CGRect(x: surface.minX + thickness, y: surface.minY, width: horizontalLength, height: thickness), [.bottom]),
            (CGRect(x: surface.minX, y: surface.minY + thickness, width: thickness, height: verticalLength), [.left]),
            (CGRect(x: surface.maxX - thickness, y: surface.minY + thickness, width: thickness, height: verticalLength), [.right]),
        ]
    }

    private static func nativeControlPassthroughRects(for placement: AgentCaptureMarkupPlacement) -> [CGRect] {
        let surface = placement.surfaceRect.standardized
        let toolbarHeight = AgentCaptureMarkupLayout.bottomToolbarHeight
        let buttonY = surface.minY + (toolbarHeight / 2) - 11
        let deleteRect = CGRect(
            x: surface.minX + 12,
            y: buttonY,
            width: 94,
            height: 22
        )
        let openInTalkieRect = CGRect(
            x: surface.midX - 42,
            y: surface.maxY - AgentCaptureMarkupLayout.titlebarHeight + 3.5,
            width: 84,
            height: 22
        )
        return [deleteRect, openInTalkieRect]
    }

    private static func relativeImageRect(for placement: AgentCaptureMarkupPlacement) -> NSRect {
        NSRect(
            x: placement.imageRect.minX - placement.surfaceRect.minX,
            y: placement.imageRect.minY - placement.surfaceRect.minY,
            width: placement.imageRect.width,
            height: placement.imageRect.height
        )
    }

    private static func zoomedPlacement(
        from placement: AgentCaptureMarkupPlacement,
        imageSize: CGSize,
        factor: CGFloat
    ) -> AgentCaptureMarkupPlacement {
        let visible = placement.screen.visibleFrame.insetBy(dx: 18, dy: 36)
        let chromeWidth = AgentCaptureMarkupLayout.edgePadding * 2
        let chromeHeight = AgentCaptureMarkupLayout.edgePadding * 2
            + AgentCaptureMarkupLayout.titlebarHeight
            + AgentCaptureMarkupLayout.bottomToolbarHeight
        let maxImageWidth = max(1, visible.width - chromeWidth)
        let maxImageHeight = max(1, visible.height - chromeHeight)
        let maxScale = max(0.01, min(maxImageWidth / max(1, imageSize.width), maxImageHeight / max(1, imageSize.height)))
        let minScale = min(
            maxScale,
            max(220 / max(1, imageSize.width), 150 / max(1, imageSize.height))
        )
        let currentScale = placement.imageRect.width / max(1, imageSize.width)
        let nextScale = clamp(currentScale * factor, min: minScale, max: maxScale)
        let imageWidth = imageSize.width * nextScale
        let imageHeight = imageSize.height * nextScale
        let width = imageWidth + chromeWidth
        let height = imageHeight + chromeHeight
        let center = NSPoint(x: placement.surfaceRect.midX, y: placement.surfaceRect.midY)
        let x = clamp(center.x - width / 2, min: visible.minX, max: visible.maxX - width)
        let y = clamp(center.y - height / 2, min: visible.minY, max: visible.maxY - height)
        let surfaceRect = CGRect(
            x: x.rounded(),
            y: y.rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
        let imageRect = aspectFitRect(imageSize: imageSize, in: contentRect(in: surfaceRect))
        return AgentCaptureMarkupPlacement(
            screen: placement.screen,
            surfaceRect: surfaceRect,
            imageRect: imageRect
        )
    }

    private static func resizedPlacement(
        from placement: AgentCaptureMarkupPlacement,
        imageSize: CGSize,
        edges: AgentCaptureMarkupResizeEdges,
        delta: CGSize
    ) -> AgentCaptureMarkupPlacement {
        let bounds = placement.screen.frame.insetBy(dx: 4, dy: 4)
        let minimum = minimumSurfaceSize(in: bounds)
        let old = placement.surfaceRect.standardized

        var minX = old.minX
        var maxX = old.maxX
        var minY = old.minY
        var maxY = old.maxY

        if edges.contains(.left) {
            minX = clamp(old.minX + delta.width, min: bounds.minX, max: old.maxX - minimum.width)
        }
        if edges.contains(.right) {
            maxX = clamp(old.maxX + delta.width, min: old.minX + minimum.width, max: bounds.maxX)
        }
        if edges.contains(.bottom) {
            minY = clamp(old.minY + delta.height, min: bounds.minY, max: old.maxY - minimum.height)
        }
        if edges.contains(.top) {
            maxY = clamp(old.maxY + delta.height, min: old.minY + minimum.height, max: bounds.maxY)
        }

        let surfaceRect = CGRect(
            x: minX.rounded(),
            y: minY.rounded(),
            width: max(minimum.width, maxX - minX).rounded(),
            height: max(minimum.height, maxY - minY).rounded()
        )
        let imageRect = aspectFitRect(imageSize: imageSize, in: contentRect(in: surfaceRect))
        return AgentCaptureMarkupPlacement(
            screen: placement.screen,
            surfaceRect: surfaceRect,
            imageRect: imageRect
        )
    }

    private static func minimumSurfaceSize(in bounds: CGRect) -> CGSize {
        let chromeWidth = AgentCaptureMarkupLayout.edgePadding * 2
        let chromeHeight = AgentCaptureMarkupLayout.edgePadding * 2
            + AgentCaptureMarkupLayout.titlebarHeight
            + AgentCaptureMarkupLayout.bottomToolbarHeight
        return CGSize(
            width: min(bounds.width, AgentCaptureMarkupLayout.minimumImageWidth + chromeWidth),
            height: min(bounds.height, AgentCaptureMarkupLayout.minimumImageHeight + chromeHeight)
        )
    }

    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        let ratio = max(0.05, imageSize.width / max(1, imageSize.height))
        var width = rect.width
        var height = width / ratio
        if height > rect.height {
            height = rect.height
            width = height * ratio
        }
        return CGRect(
            x: (rect.midX - width / 2).rounded(),
            y: (rect.midY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private static func screen(for rect: CGRect?) -> NSScreen? {
        guard let rect, rect.width > 1, rect.height > 1 else { return nil }
        let midpoint = NSPoint(x: rect.midX, y: rect.midY)
        return screen(containing: midpoint)
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func loadCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private static func markupTitle(for item: AgentLiveTrayItem) -> String {
        let rawName = normalizedTitle(item.fileURL.lastPathComponent)
            ?? normalizedTitle(item.filename)
        return rawName ?? "Screenshot"
    }

    private static func normalizedTitle(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func postAssetsDidChange() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(LiveTrayNotifications.assetsDidChange),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func deleteLooseFile(_ fileURL: URL) {
        CaptureMarkupStorage.deleteSidecar(forImageURL: fileURL)
        TKSidecarStore.delete(forAsset: fileURL)
        try? FileManager.default.removeItem(at: fileURL)
        postAssetsDidChange()
    }
}

private final class AgentCaptureMarkupBackgroundPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AgentCaptureMarkupPlacement {
    let screen: NSScreen
    let surfaceRect: CGRect
    let imageRect: CGRect

    func offsetBy(_ delta: CGSize) -> AgentCaptureMarkupPlacement {
        AgentCaptureMarkupPlacement(
            screen: screen,
            surfaceRect: surfaceRect.offsetBy(dx: delta.width, dy: delta.height),
            imageRect: imageRect.offsetBy(dx: delta.width, dy: delta.height)
        )
    }
}

private enum AgentCaptureMarkupLayout {
    static let titlebarHeight: CGFloat = 29
    static let bottomToolbarHeight: CGFloat = 34
    static let edgePadding: CGFloat = 5
    static let resizeHitSlop: CGFloat = 12
    static let resizeHandleThickness: CGFloat = 8
    static let resizeGripSize: CGFloat = 18
    static let minimumImageWidth: CGFloat = 220
    static let minimumImageHeight: CGFloat = 150
    static let dragHandleOverlap: CGFloat = 2
    static let zoomStep: CGFloat = 1.08
    static let chromeRadius: CGFloat = 7
    static let imageRadius: CGFloat = 3
    static let controlRadius: CGFloat = 4
}

private enum AgentCaptureMarkupChrome {
    // Mirrors ScopeCanvas / ScopeInk so the Agent-owned editor reads as the
    // same Talkie window as Library and Markup, rather than a separate dark
    // utility. These stay local because this AppKit surface cannot import the
    // Talkie app target's SwiftUI-only theme state.
    static let shell = adaptive(light: 0xF8F8F7, dark: 0x0E1012)
    static let titleRail = adaptive(light: 0xF8F8F7, dark: 0x181B1E)
    static let bottomRail = adaptive(light: 0xECECEB, dark: 0x181B1E)
    static let imageWell = adaptive(light: 0x0E1012, dark: 0x07090A)
    static let accent = color(0xC47D1C)
    static let pillFill = adaptive(light: 0x0F1112, dark: 0xF0EDE6)
    static let pillLabel = adaptive(light: 0xF8F8F7, dark: 0x0E1012)
    static let label = adaptive(light: 0x0F1112, dark: 0xF0EDE6)
    static let secondaryLabel = adaptive(light: 0x737878, dark: 0x938C7E)
    static let controlFill = adaptive(light: 0xECECEB, dark: 0x20252A)
    static let hairline = adaptive(light: 0x0F1112, dark: 0xD3C4A8).withAlphaComponent(0.14)
    static let strongHairline = adaptive(light: 0x0F1112, dark: 0xD3C4A8).withAlphaComponent(0.24)

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light
            return color(value)
        })
    }

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private struct AgentCaptureMarkupResizeEdges: OptionSet {
    let rawValue: Int

    static let left = AgentCaptureMarkupResizeEdges(rawValue: 1 << 0)
    static let right = AgentCaptureMarkupResizeEdges(rawValue: 1 << 1)
    static let bottom = AgentCaptureMarkupResizeEdges(rawValue: 1 << 2)
    static let top = AgentCaptureMarkupResizeEdges(rawValue: 1 << 3)
}

private enum AgentCaptureMarkupResizeCursor {
    static func cursor(for edges: AgentCaptureMarkupResizeEdges) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch edges {
        case [.top, .left]:
            position = .topLeft
        case [.top, .right]:
            position = .topRight
        case [.bottom, .left]:
            position = .bottomLeft
        case [.bottom, .right]:
            position = .bottomRight
        case .top:
            position = .top
        case .bottom:
            position = .bottom
        case .left:
            position = .left
        case .right:
            position = .right
        default:
            return .arrow
        }
        return .frameResize(position: position, directions: .all)
    }
}

private final class AgentCaptureMarkupResizeHandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class AgentCaptureMarkupResizeHandleView: NSView {
    private let edges: AgentCaptureMarkupResizeEdges
    private let onResizeDelta: (CGSize) -> Void
    private var lastDragScreenPoint: NSPoint?

    init(
        edges: AgentCaptureMarkupResizeEdges,
        onResizeDelta: @escaping (CGSize) -> Void
    ) {
        self.edges = edges
        self.onResizeDelta = onResizeDelta
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: AgentCaptureMarkupResizeCursor.cursor(for: edges))
    }

    override func cursorUpdate(with event: NSEvent) {
        AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
    }

    override func mouseDown(with event: NSEvent) {
        lastDragScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastDragScreenPoint,
              let currentPoint = window?.convertPoint(toScreen: event.locationInWindow) else {
            return
        }
        self.lastDragScreenPoint = currentPoint
        onResizeDelta(CGSize(
            width: currentPoint.x - lastDragScreenPoint.x,
            height: currentPoint.y - lastDragScreenPoint.y
        ))
        AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
    }

    override func mouseUp(with event: NSEvent) {
        lastDragScreenPoint = nil
        AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
    }
}

private final class AgentCaptureMarkupDragHandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class AgentCaptureMarkupBackgroundView: NSView {
    private enum DragMode {
        case move
        case resize(AgentCaptureMarkupResizeEdges)
    }

    private let title: String
    private let image: NSImage
    private var imageRect: NSRect
    private let onDragDelta: (CGSize) -> Void
    private let onResizeDelta: (AgentCaptureMarkupResizeEdges, CGSize) -> Void
    private let onZoom: (CGFloat) -> Void
    private let onDone: () -> Void
    private let onCancel: () -> Void
    private let onDelete: () -> Void
    private let onOpenInTalkie: () -> Void
    private var lastDragScreenPoint: NSPoint?
    private var activeDragMode: DragMode?

    init(
        title: String,
        image: NSImage,
        imageRect: NSRect,
        onDragDelta: @escaping (CGSize) -> Void,
        onResizeDelta: @escaping (AgentCaptureMarkupResizeEdges, CGSize) -> Void,
        onZoom: @escaping (CGFloat) -> Void,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenInTalkie: @escaping () -> Void
    ) {
        self.title = title
        self.image = image
        self.imageRect = imageRect
        self.onDragDelta = onDragDelta
        self.onResizeDelta = onResizeDelta
        self.onZoom = onZoom
        self.onDone = onDone
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onOpenInTalkie = onOpenInTalkie
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(
            topLeftResizeRect,
            cursor: AgentCaptureMarkupResizeCursor.cursor(for: [.top, .left])
        )
        addCursorRect(
            topRightResizeRect,
            cursor: AgentCaptureMarkupResizeCursor.cursor(for: [.top, .right])
        )
        addCursorRect(
            bottomLeftResizeRect,
            cursor: AgentCaptureMarkupResizeCursor.cursor(for: [.bottom, .left])
        )
        addCursorRect(
            bottomRightResizeRect,
            cursor: AgentCaptureMarkupResizeCursor.cursor(for: [.bottom, .right])
        )
        addCursorRect(topEdgeResizeRect, cursor: .resizeUpDown)
        addCursorRect(bottomEdgeResizeRect, cursor: .resizeUpDown)
        addCursorRect(leftEdgeResizeRect, cursor: .resizeLeftRight)
        addCursorRect(rightEdgeResizeRect, cursor: .resizeLeftRight)
        addCursorRect(dragRegion, cursor: .openHand)
        addCursorRect(cancelButtonRect, cursor: .pointingHand)
        addCursorRect(deleteButtonRect, cursor: .pointingHand)
        addCursorRect(openInTalkieButtonRect, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let edges = resizeEdges(at: point) {
            AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if cancelButtonRect.contains(point) {
            onCancel()
            return
        }
        if deleteButtonRect.contains(point) {
            onDelete()
            return
        }
        if openInTalkieButtonRect.contains(point) {
            onOpenInTalkie()
            return
        }
        if let edges = resizeEdges(at: point) {
            activeDragMode = .resize(edges)
            lastDragScreenPoint = screenPoint(for: event)
            AgentCaptureMarkupResizeCursor.cursor(for: edges).set()
            return
        }
        guard dragRegion.contains(point) else {
            activeDragMode = nil
            lastDragScreenPoint = nil
            return
        }
        activeDragMode = .move
        lastDragScreenPoint = screenPoint(for: event)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragScreenPoint,
              let current = screenPoint(for: event) else {
            return
        }
        lastDragScreenPoint = current
        let delta = CGSize(width: current.x - last.x, height: current.y - last.y)
        switch activeDragMode {
        case .move:
            onDragDelta(delta)
        case .resize(let edges):
            onResizeDelta(edges, delta)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        lastDragScreenPoint = nil
        activeDragMode = nil
        window?.invalidateCursorRects(for: self)
    }

    func updateImageRect(_ imageRect: NSRect) {
        self.imageRect = imageRect
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let shell = NSBezierPath(
            roundedRect: bounds,
            xRadius: AgentCaptureMarkupLayout.chromeRadius,
            yRadius: AgentCaptureMarkupLayout.chromeRadius
        )
        AgentCaptureMarkupChrome.shell.setFill()
        shell.fill()

        let titleRect = NSRect(
            x: 0,
            y: bounds.maxY - AgentCaptureMarkupLayout.titlebarHeight,
            width: bounds.width,
            height: AgentCaptureMarkupLayout.titlebarHeight
        )
        let imageWellRect = NSRect(
            x: AgentCaptureMarkupLayout.edgePadding,
            y: AgentCaptureMarkupLayout.bottomToolbarHeight,
            width: bounds.width - AgentCaptureMarkupLayout.edgePadding * 2,
            height: titleRect.minY - AgentCaptureMarkupLayout.bottomToolbarHeight
        )
        NSGraphicsContext.saveGraphicsState()
        shell.addClip()
        AgentCaptureMarkupChrome.imageWell.setFill()
        NSBezierPath(
            roundedRect: imageWellRect,
            xRadius: AgentCaptureMarkupLayout.imageRadius,
            yRadius: AgentCaptureMarkupLayout.imageRadius
        ).fill()

        AgentCaptureMarkupChrome.titleRail.setFill()
        titleRect.fill()

        AgentCaptureMarkupChrome.bottomRail.setFill()
        bottomToolbarRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        AgentCaptureMarkupChrome.hairline.setFill()
        NSRect(x: 1, y: bounds.maxY - 1, width: bounds.width - 2, height: 1).fill()
        NSRect(x: 1, y: 0, width: bounds.width - 2, height: 1).fill()
        AgentCaptureMarkupChrome.strongHairline.setFill()
        NSRect(x: 0, y: titleRect.minY - 1, width: bounds.width, height: 1).fill()
        AgentCaptureMarkupChrome.hairline.setFill()
        NSRect(x: 0, y: bottomToolbarRect.maxY + 1, width: bounds.width, height: 1).fill()

        drawTitle(in: titleRect)
        drawChromeButtons()
        drawDeleteControl()
        drawOpenInTalkieControl()
        drawResizeGrip()

        let imageClip = NSBezierPath(
            roundedRect: imageRect,
            xRadius: AgentCaptureMarkupLayout.imageRadius,
            yRadius: AgentCaptureMarkupLayout.imageRadius
        )
        NSGraphicsContext.saveGraphicsState()
        imageClip.addClip()
        NSColor.black.setFill()
        imageRect.fill()
        image.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        AgentCaptureMarkupChrome.strongHairline.setStroke()
        let imageBorder = NSBezierPath(
            roundedRect: imageRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: AgentCaptureMarkupLayout.imageRadius,
            yRadius: AgentCaptureMarkupLayout.imageRadius
        )
        imageBorder.lineWidth = 1
        imageBorder.stroke()

        AgentCaptureMarkupChrome.strongHairline.setStroke()
        let shellBorder = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: AgentCaptureMarkupLayout.chromeRadius,
            yRadius: AgentCaptureMarkupLayout.chromeRadius
        )
        shellBorder.lineWidth = 1
        shellBorder.stroke()
    }

    private func drawResizeGrip() {
        let corner = resizeGripRect
        guard corner.width >= 10, corner.height >= 10 else { return }

        AgentCaptureMarkupChrome.secondaryLabel.withAlphaComponent(0.38).setStroke()
        for offset in stride(from: CGFloat(0), through: CGFloat(8), by: CGFloat(4)) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: corner.maxX - 4 - offset, y: corner.minY + 4))
            path.line(to: NSPoint(x: corner.maxX - 4, y: corner.minY + 4 + offset))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawTitle(in rect: NSRect) {
        let textRect = NSRect(
            x: cancelButtonRect.maxX + 10,
            y: rect.midY - 7,
            width: max(20, openInTalkieButtonRect.minX - cancelButtonRect.maxX - 24),
            height: 14
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: AgentCaptureMarkupChrome.secondaryLabel,
            .kern: 0.65,
            .paragraphStyle: paragraph,
        ]
        ("MARKUP  ·  \(title)" as NSString).draw(
            in: textRect,
            withAttributes: attrs
        )
    }

    private func drawChromeButtons() {
        drawButton(
            rect: cancelButtonRect,
            title: "×",
            foreground: AgentCaptureMarkupChrome.label,
            fill: AgentCaptureMarkupChrome.controlFill,
            border: AgentCaptureMarkupChrome.hairline
        )
    }

    private func drawDeleteControl() {
        drawButton(
            rect: deleteButtonRect,
            title: "Delete Capture",
            foreground: NSColor.systemRed.withAlphaComponent(0.92),
            fill: NSColor.systemRed.withAlphaComponent(0.12),
            border: NSColor.systemRed.withAlphaComponent(0.42)
        )
    }

    private func drawOpenInTalkieControl() {
        let rect = openInTalkieButtonRect
        let pill = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        AgentCaptureMarkupChrome.pillFill.setFill()
        pill.fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        shadow.set()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()

        AgentCaptureMarkupChrome.accent.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: rect.minX + 12, y: rect.midY - 2.5, width: 5, height: 5)
        ).fill()

        let label = "TALKIE"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: AgentCaptureMarkupChrome.pillLabel,
            .kern: 2.0,
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(
            at: NSPoint(x: rect.minX + 25, y: rect.midY - labelSize.height / 2),
            withAttributes: labelAttributes
        )

    }

    private func drawZoomControl() {
        let controlRect = zoomControlRect
        guard controlRect.width > 72 else { return }

        let path = NSBezierPath(
            roundedRect: controlRect,
            xRadius: AgentCaptureMarkupLayout.controlRadius,
            yRadius: AgentCaptureMarkupLayout.controlRadius
        )
        NSColor(calibratedWhite: 0.045, alpha: 0.82).setFill()
        path.fill()
        NSColor(calibratedRed: 0.55, green: 0.63, blue: 1.0, alpha: 0.26).setStroke()
        path.lineWidth = 1
        path.stroke()

        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: controlRect.minX + 1, y: controlRect.maxY - 1, width: controlRect.width - 2, height: 1).fill()

        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: zoomOutButtonRect.maxX, y: controlRect.minY + 4, width: 1, height: controlRect.height - 8).fill()
        NSRect(x: zoomInButtonRect.minX - 1, y: controlRect.minY + 4, width: 1, height: controlRect.height - 8).fill()

        drawZoomGlyph(minus: true, in: zoomOutButtonRect)
        drawZoomGlyph(minus: false, in: zoomInButtonRect)

        let label = zoomPercentLabel
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.66),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(
            at: NSPoint(
                x: zoomValueRect.midX - size.width / 2,
                y: zoomValueRect.midY - size.height / 2
            ),
            withAttributes: attrs
        )
    }

    private func drawZoomGlyph(minus: Bool, in rect: NSRect) {
        let color = NSColor.white.withAlphaComponent(minus ? 0.76 : 0.86)
        color.setStroke()
        color.setFill()

        let center = NSPoint(x: rect.midX - 1, y: rect.midY + 1)
        let lens = NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        lens.lineWidth = 1
        lens.stroke()

        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: center.x + 3, y: center.y - 3))
        handle.line(to: NSPoint(x: center.x + 7, y: center.y - 7))
        handle.lineWidth = 1.2
        handle.stroke()

        let sign = NSBezierPath()
        sign.move(to: NSPoint(x: center.x - 2.4, y: center.y))
        sign.line(to: NSPoint(x: center.x + 2.4, y: center.y))
        if !minus {
            sign.move(to: NSPoint(x: center.x, y: center.y - 2.4))
            sign.line(to: NSPoint(x: center.x, y: center.y + 2.4))
        }
        sign.lineWidth = 1.2
        sign.stroke()
    }

    private var zoomPercentLabel: String {
        let scale = imageRect.width / max(1, image.size.width)
        let percent = max(1, Int((scale * 100).rounded()))
        return "\(percent)%"
    }

    private func drawButton(
        rect: NSRect,
        title: String,
        foreground: NSColor,
        fill: NSColor,
        border: NSColor
    ) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: AgentCaptureMarkupLayout.controlRadius,
            yRadius: AgentCaptureMarkupLayout.controlRadius
        )
        fill.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.05).setFill()
        NSRect(x: rect.minX + 1, y: rect.maxY - 1, width: rect.width - 2, height: 1).fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: foreground,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private var dragRegion: NSRect {
        let title = titleRect
        let left = cancelButtonRect.maxX + 4
        return NSRect(
            x: left,
            y: title.minY,
            width: max(1, title.maxX - left - AgentCaptureMarkupLayout.resizeHitSlop - 8),
            height: max(1, title.height - AgentCaptureMarkupLayout.resizeHitSlop)
        )
    }

    private var topLeftResizeRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.maxY - AgentCaptureMarkupLayout.resizeHitSlop,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var topRightResizeRect: NSRect {
        NSRect(
            x: bounds.maxX - AgentCaptureMarkupLayout.resizeHitSlop,
            y: bounds.maxY - AgentCaptureMarkupLayout.resizeHitSlop,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var bottomLeftResizeRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var bottomRightResizeRect: NSRect {
        NSRect(
            x: bounds.maxX - AgentCaptureMarkupLayout.resizeHitSlop,
            y: bounds.minY,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var topEdgeResizeRect: NSRect {
        NSRect(
            x: bounds.minX + AgentCaptureMarkupLayout.resizeHitSlop,
            y: bounds.maxY - AgentCaptureMarkupLayout.resizeHitSlop,
            width: max(1, bounds.width - AgentCaptureMarkupLayout.resizeHitSlop * 2),
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var bottomEdgeResizeRect: NSRect {
        NSRect(
            x: bounds.minX + AgentCaptureMarkupLayout.resizeHitSlop,
            y: bounds.minY,
            width: max(1, bounds.width - AgentCaptureMarkupLayout.resizeHitSlop * 2),
            height: AgentCaptureMarkupLayout.resizeHitSlop
        )
    }

    private var leftEdgeResizeRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.minY + AgentCaptureMarkupLayout.resizeHitSlop,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: max(1, bounds.height - AgentCaptureMarkupLayout.resizeHitSlop * 2)
        )
    }

    private var rightEdgeResizeRect: NSRect {
        NSRect(
            x: bounds.maxX - AgentCaptureMarkupLayout.resizeHitSlop,
            y: bounds.minY + AgentCaptureMarkupLayout.resizeHitSlop,
            width: AgentCaptureMarkupLayout.resizeHitSlop,
            height: max(1, bounds.height - AgentCaptureMarkupLayout.resizeHitSlop * 2)
        )
    }

    private var resizeGripRect: NSRect {
        NSRect(
            x: bounds.maxX - AgentCaptureMarkupLayout.resizeGripSize,
            y: 0,
            width: AgentCaptureMarkupLayout.resizeGripSize,
            height: AgentCaptureMarkupLayout.resizeGripSize
        )
    }

    private func resizeEdges(at point: NSPoint) -> AgentCaptureMarkupResizeEdges? {
        var edges: AgentCaptureMarkupResizeEdges = []

        if point.x <= bounds.minX + AgentCaptureMarkupLayout.resizeHitSlop {
            edges.insert(.left)
        } else if point.x >= bounds.maxX - AgentCaptureMarkupLayout.resizeHitSlop {
            edges.insert(.right)
        }

        if point.y <= bounds.minY + AgentCaptureMarkupLayout.resizeHitSlop {
            edges.insert(.bottom)
        } else if point.y >= bounds.maxY - AgentCaptureMarkupLayout.resizeHitSlop {
            edges.insert(.top)
        }

        return edges.isEmpty ? nil : edges
    }

    private var titleRect: NSRect {
        NSRect(
            x: 0,
            y: bounds.maxY - AgentCaptureMarkupLayout.titlebarHeight,
            width: bounds.width,
            height: AgentCaptureMarkupLayout.titlebarHeight
        )
    }

    private var doneButtonRect: NSRect {
        NSRect(
            x: max(112, bounds.maxX - 70),
            y: bottomToolbarRect.midY - 11,
            width: 56,
            height: 22
        )
    }

    private var deleteButtonRect: NSRect {
        NSRect(
            x: bottomToolbarRect.minX + 12,
            y: bottomToolbarRect.midY - 11,
            width: 94,
            height: 22
        )
    }

    private var cancelButtonRect: NSRect {
        let title = titleRect
        return NSRect(
            x: 7,
            y: title.midY - 9,
            width: 18,
            height: 18
        )
    }

    private var openInTalkieButtonRect: NSRect {
        NSRect(
            x: titleRect.midX - 42,
            y: titleRect.minY + 3.5,
            width: 84,
            height: 22
        )
    }

    private var zoomControlRect: NSRect {
        NSRect(
            x: max(bottomToolbarRect.minX + 12, doneButtonRect.minX - 122),
            y: bottomToolbarRect.midY - 11,
            width: min(108, max(78, doneButtonRect.minX - bottomToolbarRect.minX - 24)),
            height: 22
        )
    }

    private var zoomOutButtonRect: NSRect {
        NSRect(
            x: zoomControlRect.minX,
            y: zoomControlRect.minY,
            width: 28,
            height: 22
        )
    }

    private var zoomValueRect: NSRect {
        NSRect(
            x: zoomOutButtonRect.maxX + 1,
            y: zoomControlRect.minY,
            width: max(22, zoomInButtonRect.minX - zoomOutButtonRect.maxX - 2),
            height: zoomControlRect.height
        )
    }

    private var zoomInButtonRect: NSRect {
        NSRect(
            x: zoomControlRect.maxX - 28,
            y: zoomControlRect.minY,
            width: 28,
            height: 22
        )
    }

    private var bottomToolbarRect: NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: AgentCaptureMarkupLayout.bottomToolbarHeight
        )
    }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }

}

private final class AgentCaptureMarkupDragHandleView: NSView {
    private let fileURLProvider: () -> URL?
    private let dragSource = FileDragSourceDelegate()

    init(fileURLProvider: @escaping () -> URL?) {
        self.fileURLProvider = fileURLProvider
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "Drag a copy"
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCopyChip()
        drawGrip()

        let text = "DRAG COPY"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.055, alpha: 0.92),
            .kern: 0.5,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: chipRect.minX + 33,
            y: (chipRect.midY - size.height / 2).rounded()
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private var chipRect: NSRect {
        NSRect(
            x: 4,
            y: 2,
            width: bounds.width - 8,
            height: 22
        )
    }

    private var copyFill: NSColor {
        NSColor(calibratedRed: 0.92, green: 0.61, blue: 0.22, alpha: 0.98)
    }

    private var copyBorder: NSColor {
        NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.40, alpha: 0.50)
    }

    private func drawCopyChip() {
        let chip = chipRect
        let path = NSBezierPath(
            roundedRect: chip,
            xRadius: 5,
            yRadius: 5
        )
        copyFill.setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.24).setFill()
        NSRect(x: chip.minX + 1, y: chip.maxY - 1, width: chip.width - 2, height: 1).fill()
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSRect(x: chip.minX + 1, y: chip.minY, width: chip.width - 2, height: 1).fill()

        copyBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawGrip() {
        NSColor.black.withAlphaComponent(0.42).setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                let dot = NSRect(
                    x: chipRect.minX + 13 + CGFloat(column) * 5,
                    y: chipRect.midY - 6 + CGFloat(row) * 5,
                    width: 2,
                    height: 2
                )
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let url = fileURLProvider(),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let dragImage = Self.thumbnail(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        let draggingItem = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: url))
        draggingItem.setDraggingFrame(
            NSRect(origin: .zero, size: dragImage.size),
            contents: dragImage
        )
        beginDraggingSession(with: [draggingItem], event: event, source: dragSource)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    private static func thumbnail(for url: URL, maxSize: CGFloat = 180) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
