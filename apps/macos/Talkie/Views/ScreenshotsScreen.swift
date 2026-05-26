//
//  ScreenshotsScreen.swift
//  Talkie macOS
//
//  Visual grid of all screenshots — tray captures + saved on recordings.
//  Click to select, resizable detail pane on the right.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - Unified Screenshot Item

/// A single screenshot from any source, normalized for display.
private struct ScreenshotItem: Identifiable {
    let id: String
    let fileURL: URL
    let date: Date
    let label: String?
    let pinned: Bool

    // Source tracking
    let trayItem: TrayItem?
    let parent: TalkieObject?
    let screenshot: RecordingScreenshot?
}

// MARK: - Screenshots Screen

struct ScreenshotsScreen: View {
    private let repository = TalkieObjectRepository()
    @Bindable private var screenshotTray = ScreenshotTray.shared
    @Bindable private var clipTray = ClipTray.shared
    @Bindable private var selectionTray = SelectionTray.shared

    @State private var objectsWithScreenshots: [TalkieObject] = []
    @State private var libraryItems: [ScreenshotItem] = []
    @State private var selectedID: String?
    @State private var selectedIDs: Set<String> = []
    @State private var selectionAnchorID: String?
    @State private var isLoading = true
    @State private var searchText = ""

    // ── Visible window ───────────────────────────────────────────
    // Render only the first `visibleCount` items so 200+ thumbnails
    // don't all decode at once on view-appear. The bottom sentinel
    // bumps the count by `pageSize` as the user scrolls in. This is
    // the "simple protection" referenced in the perf brief — image
    // decoding on 200 cards concurrently was the main source of
    // Screenshots-page hitches.
    @State private var visibleCount: Int = 10
    private static let pageSize: Int = 10

    // Layout
    @State private var detailWidth: CGFloat = 420
    private let detailMinWidth: CGFloat = 300
    private let detailMaxWidth: CGFloat = 700
    private let compactThreshold: CGFloat = 800

    // MARK: - Derived

    private var trayScreenshotItems: [ScreenshotItem] {
        let screenshots: [TrayItem] = screenshotTray.items.map { .screenshot($0) }
        let clips: [TrayItem] = clipTray.items.map { .clip($0) }
        let selections: [TrayItem] = selectionTray.items.map { .selection($0) }

        return (screenshots + clips + selections)
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { item in
                ScreenshotItem(
                    id: "tray-\(item.id.uuidString)",
                    fileURL: item.tempURL,
                    date: item.capturedAt,
                    label: item.contextLabel,
                    pinned: item.pinned,
                    trayItem: item,
                    parent: nil,
                    screenshot: nil
                )
            }
    }

    private var allItems: [ScreenshotItem] {
        let tray = trayScreenshotItems
        let combined = tray + libraryItems

        guard !searchText.isEmpty else { return combined }
        let query = searchText.lowercased()
        return combined.filter { item in
            if let label = item.label, label.lowercased().contains(query) { return true }
            if let parent = item.parent {
                if let title = parent.title, title.lowercased().contains(query) { return true }
                if let text = parent.text, text.lowercased().contains(query) { return true }
                if parent.type.rawValue.lowercased().contains(query) { return true }
            }
            if let ss = item.screenshot {
                if let app = ss.appName, app.lowercased().contains(query) { return true }
                if let win = ss.windowTitle, win.lowercased().contains(query) { return true }
            }
            return false
        }
    }

    /// Window into `allItems` — the only slice that actually renders.
    private var visibleItems: [ScreenshotItem] {
        Array(allItems.prefix(visibleCount))
    }

    private var selectedItem: ScreenshotItem? {
        guard let selectedID else { return nil }
        return allItems.first { $0.id == selectedID }
    }

    private var selectedObject: TalkieObject? {
        selectedItem?.parent
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < compactThreshold
            let showDetail = !compact && selectedObject != nil

            HStack(spacing: 0) {
                gridPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showDetail {
                    // Drag handle
                    Rectangle()
                        .fill(TalkieTheme.borderSubtle)
                        .frame(width: 1)
                        .overlay(
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 8)
                                .contentShape(Rectangle())
                                .cursor(.resizeLeftRight)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            let newWidth = detailWidth - value.translation.width
                                            detailWidth = min(max(newWidth, detailMinWidth), min(detailMaxWidth, geometry.size.width * 0.6))
                                        }
                                )
                        )

                    if let object = selectedObject {
                        detailPane(object)
                            .frame(width: detailWidth)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedObject?.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadLibrary() }
        .onChange(of: allItems.map(\.id)) { _, visibleIDs in
            pruneSelection(visibleIDs: visibleIDs)
        }
    }

    // MARK: - Grid Pane

    private var gridPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeaderBar {
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.current.foregroundMuted)
                        .font(.system(size: 11))
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.current.fontSM)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.current.foreground.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 180)

                if !trayScreenshotItems.isEmpty {
                    Button("Tray Viewer") {
                        TrayViewer.shared.show()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    if let item = selectedAnnotatableItem {
                        annotateItem(item)
                    }
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedAnnotatableItem == nil)
                .help("Annotate selected screenshot")

                Button {
                    NSWorkspace.shared.open(ScreenshotStorage.screenshotsDirectory)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(visibleItems) { item in
                            screenshotCard(item, allItems: visibleItems)
                        }

                        // Infinite-scroll sentinel. When this 1pt-tall placeholder
                        // appears in the LazyVGrid viewport, bump the window by
                        // `pageSize`. Cheap: only renders when more items exist.
                        if visibleCount < allItems.count {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    visibleCount = min(visibleCount + Self.pageSize, allItems.count)
                                }
                        }
                    }
                    .padding(PageLayout.horizontalPadding)
                    .padding(.vertical, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background {
                    TalkieTheme.surface
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectAllVisibleItems()
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TalkieTheme.surface)
    }

    // MARK: - Detail Pane

    private func detailPane(_ object: TalkieObject) -> some View {
        TalkieView(
            recording: object,
            onDelete: {
                libraryItems.removeAll { $0.parent?.id == object.id }
                objectsWithScreenshots.removeAll { $0.id == object.id }
                selectedID = nil
            },
            recipeOverride: DetailRecipeOverride.screenshotForward(for: object.type)
        )
        .id(object.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TalkieTheme.surface
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Screenshots", systemImage: "camera.viewfinder")
        } description: {
            Text("Capture screenshots during memos or use Hyper+S to add them to the tray.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Screenshot Card

    private func screenshotCard(_ item: ScreenshotItem, allItems: [ScreenshotItem]) -> some View {
        Group {
            if let trayItem = item.trayItem {
                // Tray items use the battle-tested AdaptiveCardView
                trayCard(item, trayItem: trayItem, allItems: allItems)
            } else {
                // Library items load thumbnail from disk
                libraryCard(item, allItems: allItems)
            }
        }
    }

    private func trayCard(_ item: ScreenshotItem, trayItem: TrayItem, allItems: [ScreenshotItem]) -> some View {
        AdaptiveCardView(
            item: trayItem,
            isSelected: selectedIDs.contains(item.id),
            fontSize: 7
        )
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
        .screenshotGridDrag(
            itemID: item.id,
            payloads: dragPayloads(from: allItems),
            selectedIDs: selectedIDs,
            onClick: { event in
                handleItemClick(item, allItems: allItems, modifiers: event.modifierFlags)
            }
        )
        .contextMenu { trayContextMenu(item, trayItem: trayItem) }
    }

    @ViewBuilder
    private func trayContextMenu(_ item: ScreenshotItem, trayItem: TrayItem) -> some View {
        Button("Copy Image") { copyItem(item) }

        if case .screenshot(let ts) = trayItem {
            Button("Annotate…") { annotateItem(item) }

            if let ocrText = ts.ocrText, !ocrText.isEmpty {
                Button("Copy Detected Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocrText, forType: .string)
                }
            }

            Divider()

            Button("Save as Capture") { promoteItem(item, runOCR: false) }
            Button("Save as Capture with OCR…") { promoteItem(item, runOCR: true) }
        }

        Divider()

        Button(item.pinned ? "Unpin" : "Pin") {
            TrayActionService.shared.togglePinSelected(ids: [trayItem.id], in: [trayItem])
        }

        Button("Open in Preview") { NSWorkspace.shared.open(item.fileURL) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

        Divider()

        Button("Delete", role: .destructive) { deleteItem(item) }
    }

    private func libraryCard(_ item: ScreenshotItem, allItems: [ScreenshotItem]) -> some View {
        LibraryCardView(
            item: item,
            isSelected: selectedIDs.contains(item.id)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
        .screenshotGridDrag(
            itemID: item.id,
            payloads: dragPayloads(from: allItems),
            selectedIDs: selectedIDs,
            onClick: { event in
                handleItemClick(item, allItems: allItems, modifiers: event.modifierFlags)
            }
        )
        .contextMenu { libraryContextMenu(item) }
    }

    @ViewBuilder
    private func libraryContextMenu(_ item: ScreenshotItem) -> some View {
        Button("Copy Image") { copyItem(item) }
        Button("Annotate…") { annotateItem(item) }

        if let parent = item.parent, let text = parent.text, !text.isEmpty {
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        Divider()

        if item.parent != nil {
            Button("Show Recording") {
                selectedID = item.id
            }
        }

        Button("Open in Preview") { NSWorkspace.shared.open(item.fileURL) }

        Button("Share…") { shareFile(item.fileURL) }

        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

        Divider()

        Button("Remove", role: .destructive) { deleteItem(item) }
    }

    // MARK: - Actions

    private var selectedAnnotatableItem: ScreenshotItem? {
        guard let selectedItem, canAnnotate(selectedItem) else { return nil }
        return selectedItem
    }

    private func canAnnotate(_ item: ScreenshotItem) -> Bool {
        guard let trayItem = item.trayItem else { return true }
        if case .screenshot = trayItem { return true }
        return false
    }

    private func annotateItem(_ item: ScreenshotItem) {
        guard canAnnotate(item) else { return }
        CaptureMarkupCoordinator.shared.openSession(imageURL: item.fileURL)
    }

    private func shareFile(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func copyItem(_ item: ScreenshotItem) {
        if let trayItem = item.trayItem {
            _ = TrayActionService.shared.copySelected(ids: [trayItem.id], in: [trayItem])
        } else if let data = try? Data(contentsOf: item.fileURL) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)
        }
    }

    private func deleteItem(_ item: ScreenshotItem) {
        if let trayItem = item.trayItem {
            _ = TrayActionService.shared.deleteSelected(ids: [trayItem.id], in: [trayItem])
        } else if let parent = item.parent, let ss = item.screenshot {
            Task { await removeAttachedScreenshot(ss, from: parent) }
        }
        selectedIDs.remove(item.id)
        if selectedID == item.id { selectedID = selectedIDs.first }
        if selectionAnchorID == item.id { selectionAnchorID = selectedID }
    }

    private func promoteItem(_ item: ScreenshotItem, runOCR: Bool) {
        if let trayItem = item.trayItem, case .screenshot(let ts) = trayItem {
            TrayActionService.shared.promoteTrayToCapture(ts, runOCR: runOCR) {
                Task { await loadLibrary() }
            }
        }
    }

    // MARK: - Selection

    private func handleItemClick(_ item: ScreenshotItem, allItems: [ScreenshotItem], modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let orderedIDs = allItems.map(\.id)

        if flags.contains(.shift),
           let anchor = selectionAnchorID ?? selectedID,
           let start = orderedIDs.firstIndex(of: anchor),
           let end = orderedIDs.firstIndex(of: item.id) {
            let lower = min(start, end)
            let upper = max(start, end)
            selectedIDs = Set(orderedIDs[lower...upper])
            selectedID = item.id
            return
        }

        if flags.contains(.command) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
                selectedID = selectedIDs.first
            } else {
                selectedIDs.insert(item.id)
                selectedID = item.id
                selectionAnchorID = item.id
            }
            if selectedIDs.isEmpty {
                selectionAnchorID = nil
            }
            return
        }

        selectedIDs = [item.id]
        selectedID = item.id
        selectionAnchorID = item.id
    }

    private func selectAllVisibleItems() {
        let ids = allItems.map(\.id)
        guard !ids.isEmpty else { return }
        selectedIDs = Set(ids)
        selectedID = ids.first
        selectionAnchorID = ids.first
    }

    private func pruneSelection(visibleIDs: [String]) {
        let validIDs = Set(visibleIDs)
        selectedIDs = selectedIDs.intersection(validIDs)

        if let selectedID, !validIDs.contains(selectedID) {
            self.selectedID = selectedIDs.first
        }

        if let selectionAnchorID, !validIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedID
        }

        if validIDs.isEmpty {
            selectedID = nil
            selectedIDs.removeAll()
            selectionAnchorID = nil
        }
    }

    private func dragPayloads(from items: [ScreenshotItem]) -> [ScreenshotGridDragPayload] {
        items.map { item in
            ScreenshotGridDragPayload(
                id: item.id,
                url: item.fileURL,
                image: item.trayItem?.image
            )
        }
    }

    private func itemAccessibilityLabel(_ item: ScreenshotItem) -> String {
        let source = item.trayItem == nil ? "Library screenshot" : "Tray capture"
        let context = item.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context, !context.isEmpty {
            return "\(source), \(context)"
        }
        return source
    }

    // MARK: - Data

    private func loadLibrary() async {
        defer { isLoading = false }

        do {
            let objects = try await repository.fetchRecordingsWithSQL(
                whereClause: "assetsJSON IS NOT NULL AND json_array_length(json_extract(assetsJSON, '$.screenshots')) > 0",
                sortBy: .createdAt,
                ascending: false,
                limit: 200,
                requester: "ScreenshotsScreen"
            )

            var items: [ScreenshotItem] = []
            for obj in objects {
                for ss in obj.screenshots {
                    items.append(ScreenshotItem(
                        id: "lib-\(ss.filename)",
                        fileURL: ScreenshotStorage.screenshotsDirectory.appendingPathComponent(ss.filename),
                        date: obj.createdAt,
                        label: ss.windowTitle ?? ss.appName ?? obj.title,
                        pinned: false,
                        trayItem: nil,
                        parent: obj,
                        screenshot: ss
                    ))
                }
            }

            await MainActor.run {
                objectsWithScreenshots = objects
                libraryItems = items
            }
        } catch {
            Log(.ui).error("Failed to load screenshots: \(error)")
        }
    }

    private func removeAttachedScreenshot(_ ss: RecordingScreenshot, from parent: TalkieObject) async {
        do {
            guard let fresh = try await repository.fetchRecording(id: parent.id) else { return }

            var assets = fresh.assets ?? TalkieObjectAssets()
            let remaining = (assets.screenshots ?? []).filter { $0.filename != ss.filename }
            assets.screenshots = remaining.isEmpty ? nil : remaining

            try await repository.updateAssets(id: parent.id, assetsJSON: assets.isEmpty ? nil : assets.toJSON())

            let fileURL = ScreenshotStorage.screenshotsDirectory.appendingPathComponent(ss.filename)
            try? FileManager.default.removeItem(at: fileURL)

            await MainActor.run {
                libraryItems.removeAll { $0.id == "lib-\(ss.filename)" }

                let stillHasScreenshots = libraryItems.contains { $0.parent?.id == parent.id }
                if !stillHasScreenshots {
                    objectsWithScreenshots.removeAll { $0.id == parent.id }
                }
            }
        } catch {
            Log(.ui).error("Failed to remove screenshot: \(error)")
        }
    }
}

// MARK: - Library Card View (loads thumbnail from disk)

private struct LibraryCardView: View {
    let item: ScreenshotItem
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.08)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Data strip matching AdaptiveCardView style
            HStack(spacing: 3) {
                if let ss = item.screenshot {
                    Image(systemName: captureIcon(ss.captureMode))
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    if let w = ss.width, let h = ss.height {
                        Text("\(w)×\(h)")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                Spacer()
                Text(compactTimeAgo(item.date))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Color(white: 0.08))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.1),
                    lineWidth: isSelected ? 1.2 : 0.5
                )
        )
        .task { thumbnail = await loadThumbnail() }
    }

    private func loadThumbnail() async -> NSImage? {
        let url = item.fileURL
        return await Task.detached {
            ScreenshotTray.generateThumbnail(for: url, maxSize: 280)
        }.value
    }

    private func captureIcon(_ mode: String) -> String {
        switch mode {
        case "region": "crop"
        case "fullscreen": "rectangle.dashed"
        case "window": "macwindow"
        default: "photo"
        }
    }

    private func compactTimeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }
}

// MARK: - Screenshot Grid Drag Source

private struct ScreenshotGridDragPayload {
    let id: String
    let url: URL
    let image: NSImage?
}

private extension View {
    func screenshotGridDrag(
        itemID: String,
        payloads: [ScreenshotGridDragPayload],
        selectedIDs: Set<String>,
        onClick: @escaping (NSEvent) -> Void
    ) -> some View {
        overlay(
            ScreenshotGridDragSourceRepresentable(
                itemID: itemID,
                payloads: payloads,
                selectedIDs: selectedIDs,
                onClick: onClick
            )
        )
    }
}

private struct ScreenshotGridDragSourceRepresentable: NSViewRepresentable {
    let itemID: String
    let payloads: [ScreenshotGridDragPayload]
    let selectedIDs: Set<String>
    let onClick: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScreenshotGridDragSourceView {
        let view = ScreenshotGridDragSourceView()
        view.itemID = itemID
        view.payloads = payloads
        view.selectedIDs = selectedIDs
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ScreenshotGridDragSourceView, context: Context) {
        nsView.itemID = itemID
        nsView.payloads = payloads
        nsView.selectedIDs = selectedIDs
        nsView.onClick = onClick
    }
}

@MainActor
private final class ScreenshotGridDragSourceView: NSView, NSDraggingSource {
    var itemID: String = ""
    var payloads: [ScreenshotGridDragPayload] = []
    var selectedIDs: Set<String> = []
    var onClick: ((NSEvent) -> Void)?

    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4
    private var isDragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = dragStartLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance >= dragThreshold else { return }

        isDragging = true
        dragStartLocation = nil
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        dragStartLocation = nil
        isDragging = false

        guard !wasDragging else { return }
        onClick?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    private func startDrag(with event: NSEvent) {
        let items = selectedIDs.contains(itemID) && selectedIDs.count > 1
            ? payloads.filter { selectedIDs.contains($0.id) }
            : payloads.filter { $0.id == itemID }

        guard !items.isEmpty else { return }

        let draggingItems = items.enumerated().map { index, payload -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: payload.url))
            let offset = CGFloat(index) * 4
            let imageSize = NSSize(width: 64, height: 64)
            let dragFrame = NSRect(
                x: bounds.midX - imageSize.width / 2 + offset,
                y: bounds.midY - imageSize.height / 2 - offset,
                width: imageSize.width,
                height: imageSize.height
            )
            item.setDraggingFrame(
                dragFrame,
                contents: dragImage(for: payload, count: items.count, index: index)
            )
            return item
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    private func dragImage(for payload: ScreenshotGridDragPayload, count: Int, index: Int) -> NSImage {
        if index == 0, let image = payload.image {
            return thumbnailDragImage(image, count: count)
        }

        let size = NSSize(width: 48, height: 48)
        let image = NSImage(size: size)
        image.lockFocus()

        let icon = NSWorkspace.shared.icon(forFile: payload.url.path)
        icon.draw(in: NSRect(origin: .zero, size: size))

        if index == 0, count > 1 {
            drawCountBadge(count, in: size)
        }

        image.unlockFocus()
        return image
    }

    private func thumbnailDragImage(_ thumbnail: NSImage, count: Int) -> NSImage {
        let maxDim: CGFloat = 64
        let aspect = thumbnail.size.width / max(thumbnail.size.height, 1)
        let size: NSSize
        if aspect >= 1 {
            size = NSSize(width: maxDim, height: maxDim / aspect)
        } else {
            size = NSSize(width: maxDim * aspect, height: maxDim)
        }

        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.addClip()
        thumbnail.draw(in: rect)

        if count > 1 {
            drawCountBadge(count, in: size)
        }

        image.unlockFocus()
        return image
    }

    private func drawCountBadge(_ count: Int, in size: NSSize) {
        let badgeSize: CGFloat = 18
        let badgeRect = NSRect(
            x: size.width - badgeSize - 2,
            y: size.height - badgeSize - 2,
            width: badgeSize,
            height: badgeSize
        )
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = "\(count)" as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            ),
            withAttributes: attrs
        )
    }
}

// Uses View.cursor(_:) extension from WaveformViews.swift
