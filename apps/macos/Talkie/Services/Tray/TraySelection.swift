//
//  TraySelection.swift
//  Talkie
//
//  Shared selection/focus system used by every tray surface (viewer, shelf, badge, drawer).
//

import AppKit
import Observation
import TalkieKit

private let log = Log(.ui)

// MARK: - Selection

@MainActor
@Observable
final class TraySelection {
    static let shared = TraySelection()

    enum FocusDirection {
        case up
        case down
        case left
        case right
        case first
        case last
    }

    var selectedIDs: Set<UUID> = []
    var anchorID: UUID?
    var focusedID: UUID?

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }

    private init() {
        trackTrayChanges()
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    func isFocused(_ id: UUID) -> Bool {
        focusedID == id
    }

    func select(_ id: UUID) {
        selectedIDs = [id]
        anchorID = id
        focusedID = id
    }

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
        focusedID = id
    }

    func rangeSelect(to id: UUID, in items: [TrayItem]) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else {
            select(id)
            return
        }

        let base = anchorID ?? focusedID ?? selectedIDs.first ?? id
        guard let start = ids.firstIndex(of: base),
              let end = ids.firstIndex(of: id) else {
            select(id)
            return
        }

        let lower = min(start, end)
        let upper = max(start, end)
        selectedIDs = Set(ids[lower...upper])
        anchorID = base
        focusedID = id
    }

    func selectAll(_ items: [TrayItem]) {
        let ids = items.map(\.id)
        selectedIDs = Set(ids)
        anchorID = ids.first
        if let focusedID, ids.contains(focusedID) {
            // Keep current focus.
        } else {
            focusedID = ids.last
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        anchorID = nil
    }

    func moveFocus(direction: FocusDirection, in items: [TrayItem]) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else {
            focusedID = nil
            return
        }

        switch direction {
        case .first:
            focusedID = ids.first
            return
        case .last:
            focusedID = ids.last
            return
        case .up, .left, .down, .right:
            break
        }

        guard let current = focusedID,
              let index = ids.firstIndex(of: current) else {
            focusedID = ids.last
            return
        }

        let target: UUID
        switch direction {
        case .up, .left:
            target = ids[max(index - 1, 0)]
        case .down, .right:
            target = ids[min(index + 1, ids.count - 1)]
        case .first, .last:
            target = current
        }

        focusedID = target
    }

    func reset() {
        selectedIDs.removeAll()
        anchorID = nil
        focusedID = nil
    }

    func pruneStaleIDs() {
        let items = TrayItem.allItems()
        let validIDs = Set(items.map(\.id))

        selectedIDs = selectedIDs.intersection(validIDs)

        if let anchorID, !validIDs.contains(anchorID) {
            self.anchorID = nil
        }

        if let focusedID, !validIDs.contains(focusedID) {
            self.focusedID = items.last?.id
        }

        if items.isEmpty { reset() }
    }

    private func trackTrayChanges() {
        withObservationTracking {
            _ = ScreenshotTray.shared.items.count
            _ = ClipTray.shared.items.count
        } onChange: {
            Task { @MainActor in
                self.pruneStaleIDs()
                self.trackTrayChanges()
            }
        }
    }
}

// MARK: - Batch Actions

@MainActor
final class TrayActionService {
    static let shared = TrayActionService()

    private init() {}

    func selectedItems(ids: Set<UUID>, in allItems: [TrayItem]? = nil) -> [TrayItem] {
        let resolvedItems = allItems ?? TrayItem.allItems()
        return resolvedItems
            .filter { ids.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    @discardableResult
    func clearAll() -> Bool {
        let hasItems =
            ScreenshotTray.shared.isNotEmpty ||
            ClipTray.shared.isNotEmpty ||
            SelectionTray.shared.isNotEmpty
        guard hasItems else { return false }

        ScreenshotTray.shared.clear()
        ClipTray.shared.clear()
        SelectionTray.shared.clear()
        TraySelection.shared.pruneStaleIDs()
        return true
    }

    @discardableResult
    func clearUnpinned() -> Bool {
        let hasUnpinnedItems =
            ScreenshotTray.shared.hasUnpinnedItems ||
            ClipTray.shared.hasUnpinnedItems ||
            SelectionTray.shared.hasUnpinnedItems
        guard hasUnpinnedItems else { return false }

        ScreenshotTray.shared.clearUnpinned()
        ClipTray.shared.clearUnpinned()
        SelectionTray.shared.clearUnpinned()
        TraySelection.shared.pruneStaleIDs()
        return true
    }

    @discardableResult
    func copySelected(ids: Set<UUID>, in allItems: [TrayItem]? = nil) -> Bool {
        let items = selectedItems(ids: ids, in: allItems)
        guard !items.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if items.count == 1, case .screenshot(let screenshot) = items[0], let data = screenshot.loadData() {
            pasteboard.setData(data, forType: .png)
            return true
        }

        if items.count == 1, case .selection(let selection) = items[0], let text = selection.text {
            pasteboard.setString(text, forType: .string)
            return true
        }

        let urls = items.map(\.tempURL)
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    @discardableResult
    func deleteSelected(ids: Set<UUID>, in allItems: [TrayItem]? = nil) -> Bool {
        let items = selectedItems(ids: ids, in: allItems)
        guard !items.isEmpty else { return false }

        let screenshotIDs = Set(items.compactMap { item -> UUID? in
            if case .screenshot(let screenshot) = item { return screenshot.id }
            return nil
        })

        let clipIDs = Set(items.compactMap { item -> UUID? in
            if case .clip(let clip) = item { return clip.id }
            return nil
        })

        let selectionIDs = Set(items.compactMap { item -> UUID? in
            if case .selection(let selection) = item { return selection.id }
            return nil
        })

        if !screenshotIDs.isEmpty {
            ScreenshotTray.shared.clearItems(ids: screenshotIDs)
        }
        if !clipIDs.isEmpty {
            ClipTray.shared.clearItems(ids: clipIDs)
        }
        if !selectionIDs.isEmpty {
            SelectionTray.shared.clearItems(ids: selectionIDs)
        }

        TraySelection.shared.pruneStaleIDs()
        return true
    }

    @discardableResult
    func togglePinSelected(ids: Set<UUID>, in allItems: [TrayItem]? = nil) -> Bool {
        let items = selectedItems(ids: ids, in: allItems)
        guard !items.isEmpty else { return false }

        for item in items {
            switch item {
            case .screenshot(let screenshot):
                ScreenshotTray.shared.togglePinned(id: screenshot.id)
            case .clip(let clip):
                ClipTray.shared.togglePinned(id: clip.id)
            case .selection(let selection):
                SelectionTray.shared.togglePinned(id: selection.id)
            }
        }

        return true
    }

    @discardableResult
    func copyDetectedText(ids: Set<UUID>, in allItems: [TrayItem]? = nil) async -> Bool {
        let screenshots = selectedItems(ids: ids, in: allItems).compactMap { item -> TrayScreenshot? in
            if case .screenshot(let screenshot) = item { return screenshot }
            return nil
        }
        return await copyDetectedText(from: screenshots)
    }

    @discardableResult
    func copyDetectedText(from screenshots: [TrayScreenshot]) async -> Bool {
        guard !screenshots.isEmpty else { return false }

        var sections: [String] = []
        for screenshot in screenshots.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            let cachedText = screenshot.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String

            if let cachedText, !cachedText.isEmpty {
                text = cachedText
            } else {
                let recognized = (try? await VisionOCRService.shared.recognizeText(
                    atURL: screenshot.tempURL,
                    quality: .accurate
                ))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ScreenshotTray.shared.cacheOCRText(recognized, for: screenshot.id)
                text = recognized
            }

            guard !text.isEmpty else { continue }

            if screenshots.count == 1 {
                sections.append(text)
            } else {
                sections.append("\(textSectionTitle(for: screenshot))\n\(text)")
            }
        }

        guard !sections.isEmpty else {
            log.info("Copy detected text: no OCR text found")
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sections.joined(separator: "\n\n"), forType: .string)
        log.info("Copied detected text from \(screenshots.count) screenshot(s)")
        return true
    }

    @discardableResult
    func saveScreenshotsAsCaptures(
        _ screenshots: [TrayScreenshot],
        runOCR: Bool,
        removeFromTrayOnSuccess: Bool
    ) async -> Int {
        var savedCount = 0
        for screenshot in screenshots.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            if await saveTrayScreenshotAsCapture(
                screenshot,
                runOCR: runOCR,
                removeFromTrayOnSuccess: removeFromTrayOnSuccess
            ) != nil {
                savedCount += 1
            }
        }
        return savedCount
    }

    func openInPreview(_ item: TrayItem) {
        NSWorkspace.shared.open(item.tempURL)
    }

    func revealInFinder(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.tempURL])
    }

    private func textSectionTitle(for screenshot: TrayScreenshot) -> String {
        let context = [screenshot.appName, screenshot.windowTitle, screenshot.displayName]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return nil }
                return trimmed
            }
        var seen = Set<String>()
        let uniqueContext = context.filter { seen.insert($0).inserted }
        if let label = uniqueContext.first {
            return label
        }
        return screenshot.filename
    }

    // MARK: - Promote Tray Screenshot to Capture

    /// Standalone captures (Hyper+S, HUD, agent bay) auto-save to the library
    /// while staying available in the tray for drag/drop and island affordances.
    ///
    /// This is intentionally copy semantics, not promotion semantics: the tray item
    /// remains a live handoff surface after the capture is saved to the library.
    func persistStandaloneScreenshotToLibrary(_ ts: TrayScreenshot, runOCR: Bool = false) {
        promoteTrayToCapture(ts, runOCR: runOCR, removeFromTrayOnSuccess: false)
    }

    /// Move a tray screenshot into the library as a .capture TalkieObject.
    /// If `runOCR` is true, attach OCR text as a ProvenanceSegment.
    /// Uses pre-computed background OCR when available; falls back to on-demand accurate scan.
    func promoteTrayToCapture(_ ts: TrayScreenshot, runOCR: Bool, completion: (() -> Void)? = nil) {
        promoteTrayToCapture(ts, runOCR: runOCR, removeFromTrayOnSuccess: true, completion: completion)
    }

    /// Save a tray screenshot as a .capture TalkieObject and return the persisted object.
    @discardableResult
    func saveTrayScreenshotAsCapture(
        _ ts: TrayScreenshot,
        runOCR: Bool,
        removeFromTrayOnSuccess: Bool
    ) async -> TalkieObject? {
        let captureId = UUID()
        guard let data = ts.loadData() else {
            Log(.ui).error("promoteTrayToCapture: could not load screenshot data")
            return nil
        }

        guard let savedURL = ScreenshotStorage.save(
            data,
            recordingId: captureId,
            timestampMs: 0,
            index: 0,
            capturedAt: ts.capturedAt,
            captureMode: ts.mode.rawValue,
            width: ts.width,
            height: ts.height,
            windowTitle: ts.windowTitle,
            appName: ts.appName,
            displayName: ts.displayName
        ) else {
            Log(.ui).error("promoteTrayToCapture: could not save screenshot")
            return nil
        }

        let screenshot = RecordingScreenshot(
            filename: savedURL.lastPathComponent,
            timestampMs: 0,
            captureMode: ts.mode.rawValue,
            width: ts.width,
            height: ts.height,
            windowTitle: ts.windowTitle,
            appName: ts.appName,
            displayName: ts.displayName
        )

        var capture = TalkieObject.newCapture(id: captureId)
        var assets = TalkieObjectAssets(screenshots: [screenshot])

        if runOCR {
            // Use pre-computed OCR from background scan if available
            let ocrText: String?
            if let precomputed = ts.ocrText, !precomputed.isEmpty {
                ocrText = precomputed
                Log(.ui).info("Using pre-computed OCR for tray capture")
            } else {
                // Fall back to on-demand accurate scan
                let fileURL = ScreenshotStorage.screenshotsDirectory.appendingPathComponent(savedURL.lastPathComponent)
                ocrText = try? await VisionOCRService.shared.recognizeText(atURL: fileURL, quality: .accurate)
            }

            if let text = ocrText, !text.isEmpty {
                assets.textProvenance = [ProvenanceSegment(
                    source: .ocr,
                    originalText: text,
                    sourceAssetId: savedURL.lastPathComponent,
                    sourceDetail: "Vision"
                )]
            } else {
                Log(.ui).info("OCR: no text found for tray capture")
            }
        }

        capture.assetsJSON = assets.toJSON()

        do {
            let repository = TalkieObjectRepository()
            try await repository.saveRecording(capture)
            await RecordingsViewModel.shared.loadRecordings()
            if removeFromTrayOnSuccess {
                ScreenshotTray.shared.remove(id: ts.id)
            }
            let action = removeFromTrayOnSuccess ? "Promoted" : "Saved"
            Log(.ui).info("\(action) tray screenshot to capture: \(captureId.uuidString.prefix(8))")
            return capture
        } catch {
            Log(.ui).error("Failed to promote tray to capture: \(error.localizedDescription)")
            return nil
        }
    }

    private func promoteTrayToCapture(
        _ ts: TrayScreenshot,
        runOCR: Bool,
        removeFromTrayOnSuccess: Bool,
        completion: (() -> Void)? = nil
    ) {
        Task { @MainActor in
            if await saveTrayScreenshotAsCapture(ts, runOCR: runOCR, removeFromTrayOnSuccess: removeFromTrayOnSuccess) != nil {
                completion?()
            }
        }
    }
}
