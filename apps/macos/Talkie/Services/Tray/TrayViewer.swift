//
//  TrayViewer.swift
//  Talkie
//
//  Floating mini gallery for the capture tray.
//  Triggered by W key in the chord HUD or clicking the badge.
//

import AppKit
import AVKit
import Observation
import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Viewer Controller

@MainActor
final class TrayViewer {
    static let shared = TrayViewer()

    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    private var globalEscapeMonitor: Any?

    var isVisible: Bool { panel != nil }

    private init() {}

    static func saveAllTrayContentToNote() async {
        await drainTrayToSingleNote(
            tray: ScreenshotTray.shared,
            clipTray: ClipTray.shared,
            selectionTray: SelectionTray.shared
        )
    }

    /// Save only the latest (most recent) selection to a note.
    /// Does NOT drain screenshots, clips, or older selections.
    static func saveLatestSelectionToNote() async {
        let selectionTray = SelectionTray.shared
        guard let latest = selectionTray.items.last,
              let text = latest.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            log.warning("Save selection: no selection available")
            return
        }

        let rawContext = [latest.appName, latest.windowTitle, latest.displayName]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return nil }
                return trimmed
            }

        var seenContext = Set<String>()
        let context = rawContext.filter { seenContext.insert($0).inserted }
        let heading = context.isEmpty ? "Selection" : "Selection • " + context.joined(separator: " • ")
        let noteBody = "\(heading)\n\(text)"

        let noteId = UUID()
        let note = TalkieObject.newNote(id: noteId, text: noteBody)

        do {
            let repository = TalkieObjectRepository()
            try await repository.saveRecording(note)
            await RecordingsViewModel.shared.loadRecordings()

            selectionTray.clearItems(ids: [latest.id])
            NotificationCenter.default.post(name: .init("NotesDidChange"), object: nil)
            log.info("Saved selection to note: \(noteId.uuidString.prefix(8)) (\(text.count) chars)")
        } catch {
            log.error("Failed to save selection note: \(error)")
        }
    }

    func show() {
        if TrayShelf.shared.isVisible {
            TrayShelf.shared.dismiss()
        }

        let width: CGFloat = 480
        let height: CGFloat = 400
        let screen = targetScreenForPresentation()
        let (startOrigin, finalOrigin) = presentationOrigins(
            on: screen,
            width: width,
            height: height
        )

        log.info("TrayViewer.show requested (items=\(TrayItem.allItems().count))")

        // Reuse existing panel if possible and hard-reset it into a visible state.
        if let existing = panel {
            if existing.isVisible {
                existing.animator().alphaValue = 1
                existing.setFrameOrigin(startOrigin)
                existing.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    existing.animator().setFrameOrigin(finalOrigin)
                    existing.animator().alphaValue = 1
                }
                SurfaceCoordinator.shared.openViewer()
                log.info("TrayViewer.show reused existing panel")
                return
            } else {
                existing.orderOut(nil)
                panel = nil
            }
        }

        let hostingView = NSHostingView(rootView: TrayViewerView(
            dismiss: { [weak self] in self?.dismiss() },
            capture: { [weak self] in
                guard let p = self?.panel else { return }
                capturePanelToClipboard(p)
            }
        ))

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.sharingType = .none
        p.isReleasedWhenClosed = false

        if let contentView = p.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }

        p.setFrameOrigin(startOrigin)

        installEventMonitors()

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrameOrigin(finalOrigin)
            p.animator().alphaValue = 1
        }

        self.panel = p
        SurfaceCoordinator.shared.openViewer()
        log.info("TrayViewer.show created panel")
    }

    func dismiss() {
        guard let p = panel else { return }

        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = globalEscapeMonitor { NSEvent.removeMonitor(m) }
        localKeyMonitor = nil
        globalEscapeMonitor = nil

        let slideUpY = p.frame.origin.y + p.frame.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrameOrigin(NSPoint(x: p.frame.origin.x, y: slideUpY))
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                p.orderOut(nil)
                self?.panel = nil
                TraySelection.shared.reset()
                SurfaceCoordinator.shared.dismiss()
            }
        })
    }

    private func installEventMonitors() {
        if localKeyMonitor != nil || globalEscapeMonitor != nil {
            return
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }

        let selection = TraySelection.shared
        let items = TrayItem.allItems()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // Escape
            if selection.isEmpty {
                dismiss()
            } else {
                selection.clearSelection()
            }
            return true

        case 51, 117: // Delete / Forward delete
            let ids = selection.selectedIDs
            guard !ids.isEmpty else { return false }
            _ = TrayActionService.shared.deleteSelected(ids: ids, in: items)
            return true

        case 8: // C
            if modifiers.contains([.command, .shift]) {
                capturePanel()
                return true
            }
            if modifiers.contains(.command) {
                return TrayActionService.shared.copySelected(ids: selection.selectedIDs, in: items)
            }

        case 0: // A
            if modifiers.contains(.command) {
                selection.selectAll(items)
                return true
            }

        case 126: // Up
            if modifiers.contains(.command) {
                selection.moveFocus(direction: .first, in: items)
            } else {
                selection.moveFocus(direction: .up, in: items)
            }
            return true

        case 125: // Down
            if modifiers.contains(.command) {
                selection.moveFocus(direction: .last, in: items)
            } else {
                selection.moveFocus(direction: .down, in: items)
            }
            return true

        case 123: // Left
            selection.moveFocus(direction: .left, in: items)
            return true

        case 124: // Right
            selection.moveFocus(direction: .right, in: items)
            return true

        case 36: // Return
            if let focusedID = selection.focusedID {
                selection.select(focusedID)
                return true
            }

        case 49: // Space
            if let focusedID = selection.focusedID {
                selection.toggle(focusedID)
                return true
            }

        default:
            break
        }

        return false
    }

    private func targetScreenForPresentation() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let cursorScreen = NSScreen.screens.first(where: { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }) {
            return cursorScreen
        }
        if let panelScreen = panel?.screen {
            return panelScreen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func presentationOrigins(on screen: NSScreen, width: CGFloat, height: CGFloat) -> (start: NSPoint, final: NSPoint) {
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - width / 2
        let finalY = visibleFrame.midY - height / 2
        let startY = finalY + 80
        return (NSPoint(x: x, y: startY), NSPoint(x: x, y: finalY))
    }

    private func capturePanel() {
        guard let panel else { return }
        capturePanelToClipboard(panel)
    }

    @MainActor
    private static func drainTrayToSingleNote(
        tray: ScreenshotTray,
        clipTray: ClipTray,
        selectionTray: SelectionTray
    ) async {
        let noteId = UUID()
        var screenshots: [RecordingScreenshot] = []
        var clips: [RecordingClip] = []
        var visualContexts: [RecordingVisualContext] = []
        var selectionSections: [String] = []

        if tray.isNotEmpty {
            let baseTime = tray.items.first!.capturedAt
            for (index, item) in tray.items.enumerated() {
                let timestampMs = index == 0 ? 0 : Int(item.capturedAt.timeIntervalSince(baseTime) * 1000)
                guard let data = item.loadData(),
                      let savedURL = ScreenshotStorage.save(
                        data,
                        recordingId: noteId,
                        timestampMs: timestampMs,
                        index: index,
                        capturedAt: item.capturedAt,
                        captureMode: item.mode.rawValue,
                        width: item.width,
                        height: item.height,
                        windowTitle: item.windowTitle,
                        appName: item.appName,
                        displayName: item.displayName
                      ) else {
                    continue
                }
                screenshots.append(RecordingScreenshot(
                    filename: savedURL.lastPathComponent,
                    timestampMs: timestampMs,
                    captureMode: item.mode.rawValue,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                ))
            }
        }

        if clipTray.isNotEmpty {
            let baseTime = clipTray.items.first!.capturedAt
            for (index, item) in clipTray.items.enumerated() {
                let timestampMs = index == 0 ? 0 : Int(item.capturedAt.timeIntervalSince(baseTime) * 1000)
                guard let savedURL = VideoClipStorage.save(
                    item.tempURL,
                    recordingId: noteId,
                    timestampMs: timestampMs,
                    index: index,
                    capturedAt: item.capturedAt,
                    captureMode: item.captureMode,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                ) else {
                    continue
                }
                clips.append(RecordingClip(
                    filename: savedURL.lastPathComponent,
                    timestampMs: timestampMs,
                    durationMs: item.durationMs,
                    width: item.width,
                    height: item.height,
                    captureMode: item.captureMode,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                ))

                if let visualContext = VisualContextStorage.createBundle(
                    sourceClipURL: savedURL,
                    recordingId: noteId,
                    timestampMs: timestampMs,
                    capturedAt: item.capturedAt,
                    durationMs: item.durationMs,
                    captureMode: item.captureMode,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName,
                    metadataEvents: item.metadataEvents
                ) {
                    visualContexts.append(visualContext)
                }
            }
        }

        for item in selectionTray.items {
            guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }

            let rawContext = [item.appName, item.windowTitle, item.displayName]
                .compactMap { value -> String? in
                    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !trimmed.isEmpty else { return nil }
                    return trimmed
                }

            var seenContext = Set<String>()
            let context = rawContext.filter { seenContext.insert($0).inserted }
            let heading = context.isEmpty ? "Selection" : "Selection • " + context.joined(separator: " • ")
            selectionSections.append("\(heading)\n\(text)")
        }

        guard !screenshots.isEmpty || !clips.isEmpty || !selectionSections.isEmpty else { return }

        let parts = [
            screenshots.isEmpty ? nil : "\(screenshots.count) screenshot\(screenshots.count == 1 ? "" : "s")",
            clips.isEmpty ? nil : "\(clips.count) clip\(clips.count == 1 ? "" : "s")",
            selectionSections.isEmpty ? nil : "\(selectionSections.count) selection\(selectionSections.count == 1 ? "" : "s")",
        ].compactMap { $0 }

        let noteBody = [
            parts.isEmpty ? nil : parts.joined(separator: ", "),
            selectionSections.isEmpty ? nil : selectionSections.joined(separator: "\n\n")
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        var note = TalkieObject.newNote(id: noteId, text: noteBody)
        var assets = TalkieObjectAssets()
        if !screenshots.isEmpty { assets.screenshots = screenshots }
        if !clips.isEmpty { assets.clips = clips }
        if !visualContexts.isEmpty { assets.visualContexts = visualContexts }
        if !assets.isEmpty {
            note.assetsJSON = assets.toJSON()
        }
        if !screenshots.isEmpty {
            note.notes = screenshots
                .map { "![\($0.captureMode) screenshot](\($0.filename))" }
                .joined(separator: "\n\n")
        }

        do {
            let repository = TalkieObjectRepository()
            try await repository.saveRecording(note)
            await RecordingsViewModel.shared.loadRecordings()

            tray.clear()
            clipTray.clear()
            selectionTray.clear()
            NotificationCenter.default.post(name: .init("NotesDidChange"), object: nil)
            log.info("Created combined note: \(noteId.uuidString.prefix(8)) (\(parts.joined(separator: ", ")))")
        } catch {
            log.error("Failed to save combined note: \(error)")
        }
    }
}

// MARK: - View Mode

enum TrayViewMode: String {
    case gallery
    case list
    case carousel
}

// MARK: - SwiftUI Viewer

private struct TrayViewerView: View {
    let dismiss: () -> Void
    var capture: (() -> Void)?

    private var viewModeRaw: String { TraySettings.shared.viewerModeRaw }
    @State private var hoveredItem: UUID?
    @State private var selection = TraySelection.shared
    @State private var previewItemID: UUID?

    private var viewMode: TrayViewMode {
        if viewModeRaw == "grid" {
            return .gallery
        }
        return TrayViewMode(rawValue: viewModeRaw) ?? .gallery
    }

    private let panelCornerRadius: CGFloat = 12
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    var body: some View {
        let allItems = TrayItem.allItems()
        let bothEmpty = allItems.isEmpty

        VStack(spacing: 0) {
            header(totalCount: allItems.count)

            Divider().opacity(0.5)

            if bothEmpty {
                emptyState
            } else if viewMode != .carousel, let previewItem = activePreviewItem(in: allItems) {
                detailPreview(item: previewItem)
            } else {
                switch viewMode {
                case .gallery:
                    galleryContent(items: allItems)
                case .list:
                    listContent(items: allItems)
                case .carousel:
                    carouselContent(items: allItems)
                }
            }

            Divider().opacity(0.5)

            bottomBar(allItems: allItems)
        }
        .frame(width: 480, height: 400)
        .background {
            panelShape
                .fill(.ultraThinMaterial)
                .overlay(
                    panelShape
                        .fill(Theme.current.surface2.opacity(0.88))
                )
                .overlay(
                    panelShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.current.surface3.opacity(0.45),
                                    Theme.current.background.opacity(0.28)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .overlay {
            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.current.divider.opacity(0.95),
                            Theme.current.divider.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.34), radius: 24, y: 10)
        .onAppear {
            selection.pruneStaleIDs()
            ensureValidFocus(items: allItems)
        }
        .onChange(of: allItems.map(\.id)) { _, _ in
            selection.pruneStaleIDs()
            let items = TrayItem.allItems()
            ensureValidFocus(items: items)
            if let previewItemID, !items.contains(where: { $0.id == previewItemID }) {
                self.previewItemID = nil
            }
        }
        .onChange(of: selection.selectedIDs) { _, newValue in
            guard let previewItemID else { return }
            if newValue.count != 1 || !newValue.contains(previewItemID) {
                self.previewItemID = nil
            }
        }
        .onChange(of: selection.focusedID) { _, newValue in
            guard let previewItemID else { return }
            if newValue != previewItemID {
                self.previewItemID = nil
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(totalCount: Int) -> some View {
        let totalPinned = ScreenshotTray.shared.pinnedCount + ClipTray.shared.pinnedCount + SelectionTray.shared.pinnedCount

        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Tray")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if totalPinned > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(totalPinned)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .frame(minHeight: 18)
                .background(Capsule().fill(Color.orange.opacity(0.7)))
            }

            HStack(spacing: 2) {
                viewModeButton(icon: "square.grid.3x3", mode: .gallery)
                viewModeButton(icon: "list.bullet", mode: .list)
                viewModeButton(icon: "rectangle.stack", mode: .carousel)
            }

            Button(action: { capture?() }) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Capture tray to clipboard")
            .talkieTooltip("Screenshot", edge: .bottom)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tray viewer")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(WindowDragArea())
        .overlay(alignment: .leading) {
            if selection.count > 0 {
                Text("\(selection.count) selected")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 60)
            }
        }
    }

    @ViewBuilder
    private func viewModeButton(icon: String, mode: TrayViewMode) -> some View {
        let isActive = viewMode == mode
        Button(action: { TraySettings.shared.viewerModeRaw = mode.rawValue }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? .primary : .tertiary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? Theme.current.surfaceHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No captures")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Hyper+S to capture")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Gallery Content

    private static let galleryColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    @ViewBuilder
    private func galleryContent(items: [TrayItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: Self.galleryColumns, spacing: 8) {
                ForEach(items) { item in
                    galleryCard(item: item, allItems: items)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func galleryCard(item: TrayItem, allItems: [TrayItem]) -> some View {
        let isHovered = hoveredItem == item.id
        let isSelected = selection.isSelected(item.id)
        let isFocused = selection.isFocused(item.id)

        ZStack(alignment: .topTrailing) {
            AdaptiveCardView(item: item, isSelected: isSelected, isFocused: isFocused, fontSize: 8)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(itemAccessibilityLabel(item))
                .accessibilityHint("Command-click to add to selection. Double-click to open")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .contentShape(Rectangle())
                .onTapGesture {
                    handleItemClick(item, allItems: allItems)
                }
                .onDrag {
                    dragProvider(for: item)
                }
                .overlay(selectionRing(isSelected: isSelected, isFocused: isFocused))
                .overlay(alignment: .topLeading) {
                    selectionBadge(isSelected: isSelected)
                }
                .trayDrag(
                    item: item,
                    onClick: { event in
                        handleItemClick(item, allItems: allItems, event: event)
                    },
                    onRightClick: { event in
                        showContextMenu(for: item, allItems: allItems, event: event)
                    }
                )

            if isHovered {
                Button(action: {
                    removeItem(item)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.opacity)
                .accessibilityLabel("Remove item")
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { over in hoveredItem = over ? item.id : nil }
        .contextMenu { trayItemContextMenu(item: item, allItems: allItems) }
    }

    // MARK: - List Content

    @ViewBuilder
    private func listContent(items: [TrayItem]) -> some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(items) { item in
                    listRow(item: item, allItems: items)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private func listRow(item: TrayItem, allItems: [TrayItem]) -> some View {
        let isHovered = hoveredItem == item.id
        let isSelected = selection.isSelected(item.id)
        let isFocused = selection.isFocused(item.id)

        ZStack(alignment: .trailing) {
            Button {
                handleItemClick(item, allItems: allItems)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 14)

                    if let nsImage = item.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.isClip ? Color.red.opacity(0.1) : Color.gray.opacity(0.15))
                            .frame(width: 48, height: 36)
                            .overlay(
                                Image(systemName: item.isClip ? "video.fill" : "photo")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundStyle(item.isClip ? .red.opacity(0.5) : .gray.opacity(0.4))
                            )
                    }

                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange.opacity(0.7))
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14)
                    }

                    Image(systemName: item.modeIcon)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)

                    if let app = item.appName {
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 80, alignment: .leading)
                    }

                    Text("\(item.width)×\(item.height)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)

                    if let duration = item.durationLabel {
                        Text(duration)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(timeAgo(item.capturedAt))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, isHovered ? 20 : 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundColor(isSelected: isSelected, isFocused: isFocused, isHovered: isHovered))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor(isSelected: isSelected, isFocused: isFocused), style: borderStyle(isSelected: isSelected, isFocused: isFocused))
                )
                .contentShape(Rectangle())
                .accessibilityLabel(itemAccessibilityLabel(item))
                .accessibilityHint("Command-click to add to selection. Double-click to open")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            .buttonStyle(.plain)
            .trayDrag(
                item: item,
                onClick: { event in
                    handleItemClick(item, allItems: allItems, event: event)
                },
                onRightClick: { event in
                    showContextMenu(for: item, allItems: allItems, event: event)
                }
            )

            if isHovered {
                Button(action: { removeItem(item) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .transition(.opacity)
                .accessibilityLabel("Remove item")
            }
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { over in hoveredItem = over ? item.id : nil }
        .contextMenu { trayItemContextMenu(item: item, allItems: allItems) }
    }

    // MARK: - Carousel

    @ViewBuilder
    private func carouselContent(items: [TrayItem]) -> some View {
        let focusedItem = focusedItem(in: items) ?? items.last

        VStack(spacing: 0) {
            if let focusedItem {
                carouselPreview(item: focusedItem)
                    .frame(maxHeight: .infinity)
            }

            Divider().opacity(0.5)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            carouselThumbnail(item: item, allItems: items)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(height: 104)
                .onAppear {
                    if selection.focusedID == nil {
                        selection.focusedID = items.last?.id
                    }
                    if let focusedID = selection.focusedID {
                        proxy.scrollTo(focusedID, anchor: .center)
                    }
                }
                .onChange(of: selection.focusedID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func carouselPreview(item: TrayItem) -> some View {
        VStack(spacing: 8) {
            switch item {
            case .screenshot(let screenshot):
                if let nsImage = screenshot.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.current.divider, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .onDrag {
                            dragProvider(for: .screenshot(screenshot))
                        }
                }
            case .clip(let clip):
                ClipPlayerView(url: clip.tempURL)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .onDrag {
                        dragProvider(for: .clip(clip))
                    }
            case .selection(let selection):
                selectionPreviewSurface(selection)
                    .onDrag {
                        dragProvider(for: .selection(selection))
                    }
            }

            HStack(spacing: 8) {
                Image(systemName: item.modeIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(metadataLabel(for: item))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if let label = item.contextLabel {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }

                Spacer()

                Text(timeAgo(item.capturedAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func carouselThumbnail(item: TrayItem, allItems: [TrayItem]) -> some View {
        let isSelected = selection.isSelected(item.id)
        let isFocused = selection.isFocused(item.id)
        let thumbHeight: CGFloat = 56
        let thumbWidth = max(40, min(130, thumbHeight * item.aspectRatio))

        Button {
            handleItemClick(item, allItems: allItems)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .background(Theme.current.surface2)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.current.surface2)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .overlay(
                            thumbnailPlaceholder(for: item)
                        )
                }

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(borderColor(isSelected: isSelected, isFocused: isFocused), style: borderStyle(isSelected: isSelected, isFocused: isFocused))
            )
        }
        .buttonStyle(.plain)
        .contextMenu { trayItemContextMenu(item: item, allItems: allItems) }
        .trayDrag(
            item: item,
            onClick: { event in
                handleItemClick(item, allItems: allItems, event: event)
            },
            onRightClick: { event in
                showContextMenu(for: item, allItems: allItems, event: event)
            }
        )
    }

    // MARK: - Detail Preview

    @ViewBuilder
    private func detailPreview(item: TrayItem) -> some View {
        switch item {
        case .screenshot(let screenshot):
            screenshotPreviewView(item: screenshot)
        case .clip(let clip):
            clipPreviewView(clip: clip)
        case .selection(let selection):
            textSelectionPreviewView(selection: selection)
        }
    }

    @ViewBuilder
    private func screenshotPreviewView(item: TrayScreenshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        closeDetailPreview()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Label(modeLabel(item.mode), systemImage: TrayItem.screenshot(item).modeIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text("\(item.width) × \(item.height)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if let appName = item.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if let title = item.windowTitle {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                    if let displayName = item.displayName {
                        Text(displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: {
                    _ = TrayActionService.shared.copySelected(ids: [item.id])
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Open in external edit tool (CleanShot X, ScreenshotX, etc.)
                let editTool = SettingsManager.shared.preferredScreenshotLauncher
                if editTool.isEditTool && editTool.isInstalled {
                    Button(action: {
                        Task {
                            await editTool.openFile(item.tempURL)
                        }
                    }) {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit in \(editTool.label)")
                }

                Button(action: {
                    CaptureMarkupCoordinator.shared.openSession(imageURL: item.tempURL)
                }) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mark up with agent…")

                Button(action: {
                    TrayActionService.shared.promoteTrayToCapture(item, runOCR: false)
                    closeDetailPreview()
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Save as Capture")

                Button(action: {
                    Task {
                        _ = await TrayActionService.shared.copyDetectedText(from: [item])
                    }
                }) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 11))
                        .foregroundStyle(item.ocrText != nil && !item.ocrText!.isEmpty ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.ocrText != nil && !item.ocrText!.isEmpty ? "Copy detected text" : "Detect and copy text")

                Button(action: {
                    _ = withAnimation(.easeOut(duration: 0.15)) {
                        TrayActionService.shared.deleteSelected(ids: [item.id])
                    }
                    selection.clearSelection()
                    if TrayItem.allItems().isEmpty { dismiss() }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if let nsImage = item.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .onDrag {
                        dragProvider(for: .screenshot(item))
                    }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func clipPreviewView(clip: TrayClip) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        closeDetailPreview()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Label(
                        TrayItem.clip(clip).durationLabel ?? "",
                        systemImage: TrayItem.clip(clip).modeIcon
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                    Text("\(clip.width) × \(clip.height)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if let appName = clip.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if let title = clip.windowTitle {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                    if let displayName = clip.displayName {
                        Text(displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: {
                    _ = TrayActionService.shared.copySelected(ids: [clip.id])
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy file URL")

                Button(action: {
                    _ = withAnimation(.easeOut(duration: 0.15)) {
                        TrayActionService.shared.deleteSelected(ids: [clip.id])
                    }
                    selection.clearSelection()
                    if TrayItem.allItems().isEmpty { dismiss() }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ClipPlayerView(url: clip.tempURL)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.current.divider, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .onDrag {
                    dragProvider(for: .clip(clip))
                }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func textSelectionPreviewView(selection item: TraySelectionText) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        closeDetailPreview()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Label("\(item.characterCount) chars", systemImage: "text.quote")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if let appName = item.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if let title = item.windowTitle {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                    if let displayName = item.displayName {
                        Text(displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: {
                    _ = TrayActionService.shared.copySelected(ids: [item.id])
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy text")

                Button(action: {
                    _ = withAnimation(.easeOut(duration: 0.15)) {
                        TrayActionService.shared.deleteSelected(ids: [item.id])
                    }
                    selection.clearSelection()
                    if TrayItem.allItems().isEmpty { dismiss() }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView {
                Text(item.text ?? item.textPreview)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.current.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private func bottomBar(allItems: [TrayItem]) -> some View {
        let bothEmpty = allItems.isEmpty

        if selection.count > 0 {
            let selectedItems = TrayActionService.shared.selectedItems(ids: selection.selectedIDs, in: allItems)
            let selectedScreenshots = screenshots(in: selectedItems)
            let selectedScreenshot = selectedScreenshots.count == 1 ? selectedScreenshots[0] : nil
            let allPinned = !selectedItems.isEmpty && selectedItems.allSatisfy(\.pinned)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("\(selectedItems.count) selected")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if !selectedScreenshots.isEmpty {
                        Text(screenshotActionSummary(for: selectedScreenshots))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: {
                        selection.clearSelection()
                    }) {
                        Text("Clear Selection")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button(action: {
                        _ = TrayActionService.shared.copySelected(ids: selection.selectedIDs, in: allItems)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let selectedScreenshot {
                        Button(action: {
                            CaptureMarkupCoordinator.shared.openSession(imageURL: selectedScreenshot.tempURL)
                        }) {
                            Label("Markup", systemImage: "sparkles.rectangle.stack")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if !selectedScreenshots.isEmpty {
                        Button(action: {
                            copyDetectedText(from: selectedScreenshots)
                        }) {
                            Label("Text", systemImage: "text.viewfinder")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: {
                            saveScreenshotsAsCaptures(selectedScreenshots, runOCR: false)
                        }) {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Menu {
                        selectedItemsMenuItems(
                            selectedItems: selectedItems,
                            selectedScreenshots: selectedScreenshots,
                            selectedScreenshot: selectedScreenshot,
                            allPinned: allPinned
                        )
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .font(.system(size: 12, weight: .medium))
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .help("More actions")

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            _ = TrayActionService.shared.deleteSelected(ids: selection.selectedIDs, in: allItems)
                        }
                        if TrayItem.allItems().isEmpty {
                            dismiss()
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 10) {
                Button(action: {
                    Task {
                        await TrayViewer.saveAllTrayContentToNote()
                        dismiss()
                    }
                }) {
                    Label("Save as Note", systemImage: "note.text.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(bothEmpty)

                Button(action: {
                    MemoRecordingController.shared.startRecording()
                    dismiss()
                    NavigationState.shared.navigate(to: .recordings)
                    NotificationCenter.default.post(name: .init("ShowRecordingView"), object: nil)
                }) {
                    Label("Start Memo", systemImage: "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(bothEmpty)

                Spacer()

                if !bothEmpty {
                    Button(action: {
                        _ = TrayActionService.shared.clearAll()
                        dismiss()
                    }) {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Interaction

    private func handleItemClick(_ item: TrayItem, allItems: [TrayItem], event: NSEvent? = nil) {
        let modifiers = currentModifiers(event: event)
        let isModifiedClick =
            modifiers.contains(.shift) ||
            modifiers.contains(.command) ||
            modifiers.contains(.option) ||
            modifiers.contains(.control)
        let clickCount = event?.clickCount ?? NSApp.currentEvent?.clickCount ?? 1

        if modifiers.contains(.shift) {
            selection.rangeSelect(to: item.id, in: allItems)
        } else if modifiers.contains(.command) {
            selection.toggle(item.id)
        } else {
            selection.select(item.id)
        }

        if clickCount >= 2, !isModifiedClick, viewMode != .carousel {
            openDetailPreview(for: item.id, in: allItems)
        } else if clickCount == 1 {
            previewItemID = nil
        }
    }

    private func showContextMenu(for item: TrayItem, allItems: [TrayItem], event: NSEvent) {
        if selection.isSelected(item.id) {
            selection.focusedID = item.id
        } else {
            selection.select(item.id)
        }
        previewItemID = nil

        guard let view = event.window?.contentView else { return }
        NSMenu.popUpContextMenu(
            appKitContextMenu(for: item, allItems: allItems),
            with: event,
            for: view
        )
    }

    @ViewBuilder
    private func trayItemContextMenu(item: TrayItem, allItems: [TrayItem]) -> some View {
        Button("Copy") {
            _ = TrayActionService.shared.copySelected(ids: [item.id], in: allItems)
        }

        Button(item.pinned ? "Unpin" : "Pin") {
            _ = TrayActionService.shared.togglePinSelected(ids: [item.id], in: allItems)
        }

        if case .screenshot(let ts) = item {
            Divider()

            Button("Save as Capture") {
                TrayActionService.shared.promoteTrayToCapture(ts, runOCR: false)
            }

            let hasOCR = ts.ocrText != nil && !ts.ocrText!.isEmpty
            Button(hasOCR ? "Extract Text (ready)" : "Extract Text\u{2026}") {
                TrayActionService.shared.promoteTrayToCapture(ts, runOCR: true)
            }

            if hasOCR {
                Button("Copy Detected Text") {
                    copyDetectedText(from: [ts])
                }
            } else {
                Button("Detect and Copy Text") {
                    copyDetectedText(from: [ts])
                }
            }

            Button("Annotate…") {
                CaptureMarkupCoordinator.shared.openSession(imageURL: ts.tempURL)
            }

            Button("Open in Preview") {
                TrayActionService.shared.openInPreview(item)
            }

            Button("Reveal in Finder") {
                TrayActionService.shared.revealInFinder(item)
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            removeItem(item)
        }
    }

    private func appKitContextMenu(for item: TrayItem, allItems: [TrayItem]) -> NSMenu {
        let targetIDs = selection.isSelected(item.id) ? selection.selectedIDs : [item.id]
        let targetItems = TrayActionService.shared.selectedItems(ids: targetIDs, in: allItems)
        let targetScreenshots = screenshots(in: targetItems)
        let menu = NSMenu()
        let selectedCount = targetItems.count

        if selectedCount > 1 {
            let title = "\(selectedCount) items selected"
            let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(.separator())
        }

        menu.addItem(TrayContextMenuItem(title: "Copy") {
            _ = TrayActionService.shared.copySelected(ids: targetIDs, in: allItems)
        })

        if selectedCount == 1, let firstItem = targetItems.first {
            menu.addItem(TrayContextMenuItem(title: "Open Detail") {
                openDetailPreview(for: firstItem.id, in: allItems)
            })
        }

        let allPinned = !targetItems.isEmpty && targetItems.allSatisfy(\.pinned)
        menu.addItem(TrayContextMenuItem(title: allPinned ? "Unpin" : "Pin") {
            _ = TrayActionService.shared.togglePinSelected(ids: targetIDs, in: allItems)
        })

        if !targetScreenshots.isEmpty {
            menu.addItem(.separator())

            menu.addItem(TrayContextMenuItem(title: targetScreenshots.count == 1 ? "Save as Capture" : "Save Captures") {
                saveScreenshotsAsCaptures(targetScreenshots, runOCR: false)
            })

            menu.addItem(TrayContextMenuItem(title: targetScreenshots.count == 1 ? "Save Capture with OCR" : "Save Captures with OCR") {
                saveScreenshotsAsCaptures(targetScreenshots, runOCR: true)
            })

            let allTextReady = targetScreenshots.allSatisfy { screenshot in
                guard let text = screenshot.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !text.isEmpty
            }
            menu.addItem(TrayContextMenuItem(title: allTextReady ? "Copy Detected Text" : "Detect and Copy Text") {
                copyDetectedText(from: targetScreenshots)
            })

            if targetScreenshots.count == 1, let screenshot = targetScreenshots.first {
                menu.addItem(TrayContextMenuItem(title: "Annotate…") {
                    CaptureMarkupCoordinator.shared.openSession(imageURL: screenshot.tempURL)
                })

                let screenshotItem = TrayItem.screenshot(screenshot)
                menu.addItem(TrayContextMenuItem(title: "Open in Preview") {
                    TrayActionService.shared.openInPreview(screenshotItem)
                })

                let editTool = SettingsManager.shared.preferredScreenshotLauncher
                if editTool.isEditTool && editTool.isInstalled {
                    menu.addItem(TrayContextMenuItem(title: "Edit in \(editTool.label)") {
                        Task {
                            await editTool.openFile(screenshot.tempURL)
                        }
                    })
                }
            }
        }

        if let firstItem = targetItems.first {
            menu.addItem(TrayContextMenuItem(title: selectedCount == 1 ? "Reveal in Finder" : "Reveal First in Finder") {
                TrayActionService.shared.revealInFinder(firstItem)
            })
        }

        menu.addItem(.separator())
        menu.addItem(TrayContextMenuItem(title: selectedCount == 1 ? "Delete" : "Delete \(selectedCount) Items") {
            withAnimation(.easeOut(duration: 0.15)) {
                _ = TrayActionService.shared.deleteSelected(ids: targetIDs, in: allItems)
            }
            if TrayItem.allItems().isEmpty {
                dismiss()
            }
        })

        return menu
    }

    private func removeItem(_ item: TrayItem) {
        withAnimation(.easeOut(duration: 0.15)) {
            _ = TrayActionService.shared.deleteSelected(ids: [item.id])
        }

        if TrayItem.allItems().isEmpty {
            dismiss()
        }
    }



    private func currentModifiers(event: NSEvent? = nil) -> NSEvent.ModifierFlags {
        (event ?? NSApp.currentEvent)?
            .modifierFlags
            .intersection(.deviceIndependentFlagsMask) ?? []
    }

    // MARK: - Helpers

    @ViewBuilder
    private func selectedItemsMenuItems(
        selectedItems: [TrayItem],
        selectedScreenshots: [TrayScreenshot],
        selectedScreenshot: TrayScreenshot?,
        allPinned: Bool
    ) -> some View {
        Button(allPinned ? "Unpin" : "Pin") {
            _ = TrayActionService.shared.togglePinSelected(ids: selection.selectedIDs)
        }

        if !selectedScreenshots.isEmpty {
            Divider()

            Button(selectedScreenshots.count == 1 ? "Save Capture with OCR" : "Save Captures with OCR") {
                saveScreenshotsAsCaptures(selectedScreenshots, runOCR: true)
            }
        }

        if let selectedScreenshot {
            let screenshotItem = TrayItem.screenshot(selectedScreenshot)
            Button("Open in Preview") {
                TrayActionService.shared.openInPreview(screenshotItem)
            }

            let editTool = SettingsManager.shared.preferredScreenshotLauncher
            if editTool.isEditTool && editTool.isInstalled {
                Button("Edit in \(editTool.label)") {
                    Task {
                        await editTool.openFile(selectedScreenshot.tempURL)
                    }
                }
            }
        }

        if let firstItem = selectedItems.first {
            Button(selectedItems.count == 1 ? "Reveal in Finder" : "Reveal First in Finder") {
                TrayActionService.shared.revealInFinder(firstItem)
            }
        }
    }

    private func screenshots(in items: [TrayItem]) -> [TrayScreenshot] {
        items.compactMap { item in
            if case .screenshot(let screenshot) = item { return screenshot }
            return nil
        }
    }

    private func screenshotActionSummary(for screenshots: [TrayScreenshot]) -> String {
        if screenshots.count == 1 {
            return "Screenshot actions ready"
        }
        return "\(screenshots.count) screenshots"
    }

    private func copyDetectedText(from screenshots: [TrayScreenshot]) {
        Task {
            _ = await TrayActionService.shared.copyDetectedText(from: screenshots)
        }
    }

    private func saveScreenshotsAsCaptures(_ screenshots: [TrayScreenshot], runOCR: Bool) {
        Task {
            let savedCount = await TrayActionService.shared.saveScreenshotsAsCaptures(
                screenshots,
                runOCR: runOCR,
                removeFromTrayOnSuccess: true
            )
            guard savedCount > 0 else { return }
            selection.pruneStaleIDs()
            if TrayItem.allItems().isEmpty {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func selectionRing(isSelected: Bool, isFocused: Bool) -> some View {
        if isSelected || isFocused {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.55),
                    lineWidth: isSelected ? 2 : 1.2
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .padding(-2)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionBadge(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                .padding(5)
                .allowsHitTesting(false)
        }
    }

    private func dragProvider(for item: TrayItem) -> NSItemProvider {
        if case .selection(let selection) = item, let text = selection.text {
            let provider = NSItemProvider(object: text as NSString)
            provider.suggestedName = selection.displayName ?? selection.appName ?? "Selection"
            return TalkieInternalDrag.mark(provider)
        }
        let provider = NSItemProvider(object: item.tempURL as NSURL)
        provider.suggestedName = item.tempURL.lastPathComponent
        return TalkieInternalDrag.mark(provider)
    }

    private func focusedItem(in items: [TrayItem]) -> TrayItem? {
        if let focusedID = selection.focusedID,
           let focused = items.first(where: { $0.id == focusedID }) {
            return focused
        }
        return items.last
    }

    private func activePreviewItem(in items: [TrayItem]) -> TrayItem? {
        guard let previewItemID else { return nil }
        guard selection.selectedIDs.count == 1,
              selection.selectedIDs.contains(previewItemID),
              selection.focusedID == previewItemID else {
            return nil
        }
        return items.first(where: { $0.id == previewItemID })
    }

    private func openDetailPreview(for id: UUID, in items: [TrayItem]) {
        guard items.contains(where: { $0.id == id }) else { return }
        selection.select(id)
        previewItemID = id
    }

    private func closeDetailPreview() {
        previewItemID = nil
    }

    private func ensureValidFocus(items: [TrayItem]) {
        guard !items.isEmpty else {
            selection.focusedID = nil
            return
        }
        if let focusedID = selection.focusedID, items.contains(where: { $0.id == focusedID }) {
            return
        }
        selection.focusedID = items.last?.id
    }

    private func itemAccessibilityLabel(_ item: TrayItem) -> String {
        let type = item.isClip ? "Clip" : (item.isText ? "Selection" : "Screenshot")
        return "\(type), \(metadataLabel(for: item)), \(timeAgo(item.capturedAt))"
    }

    private func metadataLabel(for item: TrayItem) -> String {
        if case .selection(let selection) = item {
            return "\(selection.characterCount) chars"
        }
        return "\(item.width) × \(item.height)"
    }

    @ViewBuilder
    private func thumbnailPlaceholder(for item: TrayItem) -> some View {
        if let previewText = item.previewText {
            VStack(alignment: .leading, spacing: 3) {
                Text("TXT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.current.textTertiary)
                Text(previewText)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.current.textSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Image(systemName: item.isClip ? "video.fill" : "photo")
                .foregroundStyle(.quaternary)
        }
    }

    @ViewBuilder
    private func selectionPreviewSurface(_ selection: TraySelectionText) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.current.surface3)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SELECTION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.current.textTertiary)
                    Text(selection.textPreview)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.current.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(10)
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.current.divider, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func modeLabel(_ mode: CaptureMode) -> String {
        switch mode {
        case .region: "Region"
        case .fullscreen: "Screen"
        case .window: "Window"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    private func backgroundColor(isSelected: Bool, isFocused: Bool, isHovered: Bool) -> Color {
        if isFocused {
            return Color.accentColor.opacity(0.17)
        }
        if isSelected {
            return Color.accentColor.opacity(0.11)
        }
        if isHovered {
            return Theme.current.surfaceHover
        }
        return .clear
    }

    private func borderColor(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return .accentColor.opacity(0.95) }
        if isSelected { return .accentColor.opacity(0.65) }
        return .clear
    }

    private func borderStyle(isSelected: Bool, isFocused: Bool) -> StrokeStyle {
        if isFocused && !isSelected {
            return StrokeStyle(lineWidth: 1.1, dash: [3, 2])
        }
        if isFocused {
            return StrokeStyle(lineWidth: 1.3)
        }
        if isSelected {
            return StrokeStyle(lineWidth: 1.1)
        }
        return StrokeStyle(lineWidth: 0)
    }

}

private final class TrayContextMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction() {
        handler()
    }
}

// MARK: - Waterfall Layout

private struct WaterfallLayout: Layout {
    var columns: Int = 3
    var spacing: CGFloat = 8

    private func frames(in width: CGFloat, subviews: Subviews) -> [CGRect] {
        let safeColumns = max(columns, 1)
        let safeWidth = max(width, 1)
        let totalSpacing = CGFloat(safeColumns - 1) * spacing
        let columnWidth = max((safeWidth - totalSpacing) / CGFloat(safeColumns), 1)

        var columnHeights = Array(repeating: CGFloat.zero, count: safeColumns)
        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)

        for index in subviews.indices {
            let targetColumn = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] }) ?? 0
            let x = CGFloat(targetColumn) * (columnWidth + spacing)
            let proposal = ProposedViewSize(width: columnWidth, height: nil)
            let size = subviews[index].sizeThatFits(proposal)
            let y = columnHeights[targetColumn]
            frames[index] = CGRect(x: x, y: y, width: columnWidth, height: size.height)
            columnHeights[targetColumn] += size.height + spacing
        }

        return frames
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 1
        let placedFrames = frames(in: width, subviews: subviews)
        let maxY = placedFrames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let placedFrames = frames(in: bounds.width, subviews: subviews)

        for index in subviews.indices {
            let frame = placedFrames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

// MARK: - Inline Video Player

private struct ClipPlayerView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loopObserver: NSObjectProtocol?

        deinit {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: url)
        player.isMuted = true

        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false

        context.coordinator.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        nsView.player = nil
        if let observer = coordinator.loopObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.loopObserver = nil
        }
    }
}

// MARK: - Window Drag Area

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// NSPanel subclass that can become key — required for SwiftUI .onDrag to work
/// in a nonactivatingPanel. Without this, drag gestures are silently swallowed.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
