//
//  ScreenshotsScreen.swift
//  Talkie macOS
//
//  Visual grid of all screenshots — tray captures + saved on recordings.
//  Click to select, resizable detail pane on the right.
//

import AppKit
import ImageIO
import SwiftUI
import TalkieKit
import UserNotifications

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

// MARK: - View Mode

/// How the gallery lays out captures. Grid = thumbnail wall; List = dense
/// rows with metadata (sibling to the dictations ScopeLibraryView list).
private enum ScreenshotsViewMode: String { case grid, list }

// MARK: - Screenshots Screen

struct ScreenshotsScreen: View {
    private let repository = TalkieObjectRepository()
    private let actionRepository = LocalRepository()
    private let workflowService = WorkflowService.shared
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

    // Grid (thumbnail wall) vs list (dense metadata rows). Persisted so the
    // choice sticks across launches.
    @AppStorage("screenshotsViewMode") private var viewMode: ScreenshotsViewMode = .grid

    // ── Preview (Quick Look) takeover ────────────────────────────
    // When set, the whole screen swaps to a clean read-only preview of
    // this item (image-forward, no inspector), with a Markup escalation.
    // Mirrors macOS Quick Look → Markup; see the /mac-screenshots studio.
    @State private var previewItemID: String?

    // ── Visible window ───────────────────────────────────────────
    // Render only the first `visibleCount` items so 200+ thumbnails
    // don't all decode at once on view-appear. The bottom sentinel
    // bumps the count by `pageSize` as the user scrolls in. This is
    // the "simple protection" referenced in the perf brief — image
    // decoding on 200 cards concurrently was the main source of
    // Screenshots-page hitches.
    @State private var visibleCount: Int = 10
    private static let pageSize: Int = 10

    // Layout — inspector width persists across launches so a user who wants
    // the richer metadata pane wider doesn't have to re-drag every session.
    @AppStorage("screenshotsInspectorWidth") private var detailWidth: Double = 380
    private let detailMinWidth: CGFloat = 300
    private let detailMaxWidth: CGFloat = 600
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

    private var previewItem: ScreenshotItem? {
        guard let previewItemID else { return nil }
        return allItems.first { $0.id == previewItemID }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            galleryBody
                .opacity(previewItem == nil ? 1 : 0)

            if let item = previewItem {
                ScreenshotPreviewOverlay(
                    item: item,
                    sourceLabel: sourceLabel(item),
                    dimensions: imageDimensions(item),
                    byteLabel: fileBytes(item),
                    layerCount: layerCount(for: item),
                    canMarkup: canAnnotate(item),
                    onMarkup: { annotateItem(item) },
                    onShare: { shareFile(item.fileURL) },
                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) },
                    onClose: { previewItemID = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: previewItemID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadLibrary() }
        .onChange(of: allItems.map(\.id)) { _, visibleIDs in
            pruneSelection(visibleIDs: visibleIDs)
        }
    }

    private var galleryBody: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < compactThreshold
            let showInspector = !compact && selectedItem != nil
            // Header degrades on the grid pane's own width (inspector open or
            // small window), not raw window width.
            let inspectorSpace: CGFloat = showInspector ? CGFloat(detailWidth) + 9 : 0
            let gridWidth = max(geometry.size.width - inspectorSpace, 1)

            HStack(spacing: 0) {
                gridPane(width: gridWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector, let item = selectedItem {
                    // Drag handle
                    Rectangle()
                        .fill(ScopePalette.rule)
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
                                            let newWidth = CGFloat(detailWidth) - value.translation.width
                                            let clamped = min(max(newWidth, detailMinWidth), min(detailMaxWidth, geometry.size.width * 0.7))
                                            detailWidth = Double(clamped)
                                        }
                                )
                        )

                    inspectorPane(item)
                        .frame(width: CGFloat(detailWidth))
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid Pane

    private func gridPane(width: CGFloat) -> some View {
        let headerCompact = width < 820
        return VStack(alignment: .leading, spacing: 0) {
            // Canonical header — baseline-locked to the sidebar wordmark and
            // the TALKIE pill, same as Models. Controls ride the trailing slot;
            // the count chrome drops when the pane is tight.
            ScopeTopBand(
                title: "Screenshots",
                chrome: headerCompact ? nil : headerCountLine,
                trailing: { headerControls(compact: headerCompact) }
            )

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .grid: gridContent
                case .list: listContent
                }
            }

            if !selectedIDs.isEmpty {
                selectionStatusBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TalkieTheme.surface)
    }


    // Right-side controls. Condense as the pane narrows: search shrinks and
    // Tray Viewer collapses to an icon.
    @ViewBuilder
    private func headerControls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                viewModeButton(.grid, "square.grid.2x2")
                viewModeButton(.list, "list.bullet")
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.current.foreground.opacity(0.06))
            )

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
            .frame(maxWidth: compact ? 120 : 180)

            if !trayScreenshotItems.isEmpty {
                Button {
                    TrayViewer.shared.show()
                } label: {
                    if compact {
                        Image(systemName: "tray.full")
                    } else {
                        Text("Tray Viewer")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Tray Viewer")
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
    }

    private var headerCountLine: String {
        let total = allItems.count
        let today = allItems.filter { Calendar.current.isDateInToday($0.date) }.count
        var parts = ["\(total) capture\(total == 1 ? "" : "s")"]
        if today > 0 { parts.append("\(today) today") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func viewModeButton(_ mode: ScreenshotsViewMode, _ icon: String) -> some View {
        let active = viewMode == mode
        Button {
            viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? ScopeAmber.solid : Theme.current.foregroundMuted)
                .frame(width: 26, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? ScopeAmber.tintSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(mode == .grid ? "Grid view" : "List view")
    }

    // Shared infinite-scroll sentinel: bump the visible window as it appears.
    @ViewBuilder
    private var loadMoreSentinel: some View {
        if visibleCount < allItems.count {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    visibleCount = min(visibleCount + Self.pageSize, allItems.count)
                }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)],
                spacing: 8
            ) {
                ForEach(visibleItems) { item in
                    screenshotCard(item, allItems: visibleItems)
                }
                loadMoreSentinel
            }
            .padding(PageLayout.horizontalPadding)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background {
            TalkieTheme.surface
                .contentShape(Rectangle())
                .onTapGesture { selectAllVisibleItems() }
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            ScreenshotListHeader()
            ScopeRule(.subtle)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        screenshotListRow(item, allItems: visibleItems)
                        ScopeRule(.subtle)
                    }
                    loadMoreSentinel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background {
            TalkieTheme.surface
                .contentShape(Rectangle())
                .onTapGesture { selectAllVisibleItems() }
        }
    }

    // MARK: - Selection Status Bar

    private var selectionStatusBar: some View {
        let count = selectedIDs.count
        let anchor = selectedItem
        return HStack(spacing: 10) {
            if count == 1, let anchor {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                Text("1 selected")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.amberDeep)
                ScopeRule(.subtle, axis: .vertical).frame(height: 12)
                Text(anchor.fileURL.lastPathComponent)
                    .font(ScopeType.mono(size: 9))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                StatusVerb(label: "preview", tone: .neutral) { openPreview(anchor) }
                if canAnnotate(anchor) {
                    StatusVerb(label: "markup", tone: .primary) { annotateItem(anchor) }
                }
                StatusVerb(label: "reveal", tone: .neutral) {
                    NSWorkspace.shared.activateFileViewerSelecting([anchor.fileURL])
                }
                StatusVerb(label: "delete", tone: .alert) { deleteItem(anchor) }
                StatusVerb(label: "clear", tone: .ghost) { clearSelection() }
            } else {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                Text("\(count) selected")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.amberDeep)
                ScopeRule(.subtle, axis: .vertical).frame(height: 12)
                Text("bulk action")
                    .font(ScopeType.mono(size: 9))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.amberDeep.opacity(0.7))

                Spacer(minLength: 8)

                StatusVerb(label: "share", tone: .neutral) { shareSelected() }
                StatusVerb(label: "delete", tone: .alert) { deleteSelected() }
                StatusVerb(label: "clear", tone: .ghost) { clearSelection() }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(count > 1 ? ScopePalette.amberFaint : ScopePalette.bg)
        .overlay(alignment: .top) { ScopeRule(.subtle) }
    }

    // MARK: - Inspector Pane

    private func inspectorPane(_ item: ScreenshotItem) -> some View {
        ScreenshotInspector(
            item: item,
            multiCount: selectedIDs.count,
            sourceLabel: sourceLabel(item),
            dimensions: imageDimensions(item),
            byteLabel: fileBytes(item),
            layerCount: layerCount(for: item),
            ageLabel: relativeAge(item.date),
            absoluteDate: absoluteDate(item.date),
            appName: appBundleLine(item),
            windowTitle: windowTitleLine(item),
            displayName: displayLine(item),
            recordingOffset: recordingOffsetLine(item),
            trayOCRText: trayOCRText(item),
            canMarkup: canAnnotate(item),
            showRecording: canShowRecording(item),
            onOpenPreview: { openPreview(item) },
            onOpenMarkup: { annotateItem(item) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) },
            onCopy: { copyItem(item) },
            onShowRecording: { showRecording(item) }
        )
        .id(item.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopePalette.bgRaised)
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

    // MARK: - Screenshot List Row

    /// A dense metadata row for list view. Reuses the same click / drag /
    /// context-menu wiring as the grid cards so selection and behavior match.
    private func screenshotListRow(_ item: ScreenshotItem, allItems: [ScreenshotItem]) -> some View {
        let selected = selectedIDs.contains(item.id)
        let row = ScreenshotRowView(
            item: item,
            isSelected: selected,
            title: rowTitle(item),
            columns: rowColumns(item),
            ageLabel: relativeAge(item.date)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .screenshotGridDrag(
            itemID: item.id,
            payloads: dragPayloads(from: allItems),
            selectedIDs: selectedIDs,
            onClick: { event in
                handleItemClick(item, allItems: allItems, modifiers: event.modifierFlags)
            }
        )

        return Group {
            if let trayItem = item.trayItem {
                row.contextMenu { trayContextMenu(item, trayItem: trayItem) }
            } else {
                row.contextMenu { libraryContextMenu(item) }
            }
        }
    }

    /// Title for a list row — prefers the human label, else the app name.
    private func rowTitle(_ item: ScreenshotItem) -> String {
        if let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let app = item.screenshot?.appName, !app.isEmpty {
            return app
        }
        return "Screenshot"
    }

    /// Aligned column values for a list row. STRICTLY in-memory metadata —
    /// `RecordingScreenshot` / `TrayScreenshot` fields plus `item.date`. No
    /// file-header decode, no sidecar load, no markup-layer load (those are
    /// per-row disk reads that would tank scroll perf on hundreds of rows).
    private func rowColumns(_ item: ScreenshotItem) -> ScreenshotRowColumns {
        // App / window context — already carried on both models.
        let app = item.screenshot?.appName
            ?? item.trayItem?.appName
            ?? item.screenshot?.windowTitle
            ?? item.trayItem?.windowTitle

        // Dimensions — width/height live on both record types in memory.
        var dimensions: String?
        if let ss = item.screenshot, let w = ss.width, let h = ss.height {
            dimensions = "\(w)×\(h)"
        } else if let trayItem = item.trayItem, trayItem.width > 0 {
            dimensions = "\(trayItem.width)×\(trayItem.height)"
        }

        return ScreenshotRowColumns(
            app: app?.trimmingCharacters(in: .whitespaces).screenshotActionNilIfEmpty,
            source: sourceLabel(item).uppercased(),
            dimensions: dimensions
        )
    }

    // MARK: - Screenshot Card

    private func trayCard(_ item: ScreenshotItem, trayItem: TrayItem, allItems: [ScreenshotItem]) -> some View {
        let selected = selectedIDs.contains(item.id)
        return AdaptiveCardView(
            item: trayItem,
            isSelected: selected,
            fontSize: 7
        )
        .aspectRatio(1, contentMode: .fit)
        .overlay(selectionOverlay(isSelected: selected))
        .contentShape(Rectangle())
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
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

            workflowContextMenuItems(for: item)

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

        Button("Open in Preview") { openPreview(item) }
        Button("Open in Preview.app") { NSWorkspace.shared.open(item.fileURL) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

        Divider()

        Button("Delete", role: .destructive) { deleteItem(item) }
    }

    private func libraryCard(_ item: ScreenshotItem, allItems: [ScreenshotItem]) -> some View {
        let selected = selectedIDs.contains(item.id)
        return LibraryCardView(
            item: item,
            isSelected: selected
        )
        .overlay(selectionOverlay(isSelected: selected))
        .contentShape(Rectangle())
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    /// A prominent selection ring placed on top of the card. Pairs with the
    /// inner card's subtle accent border so multi-select is unmissable.
    @ViewBuilder
    private func selectionOverlay(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func libraryContextMenu(_ item: ScreenshotItem) -> some View {
        Button("Copy Image") { copyItem(item) }
        Button("Annotate…") { annotateItem(item) }

        workflowContextMenuItems(for: item)

        if let parent = item.parent, let text = parent.text, !text.isEmpty {
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        Divider()

        if canShowRecording(item) {
            Button("Show Recording") { showRecording(item) }
        }

        Button("Open in Preview") { openPreview(item) }
        Button("Open in Preview.app") { NSWorkspace.shared.open(item.fileURL) }

        Button("Share…") { shareFile(item.fileURL) }

        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

        Divider()

        Button("Remove", role: .destructive) { deleteItem(item) }
    }

    // MARK: - Actions

    @ViewBuilder
    private func workflowContextMenuItems(for item: ScreenshotItem) -> some View {
        let workflows = imageWorkflows(for: item)
        if !workflows.isEmpty {
            Divider()
            ForEach(workflows) { workflow in
                Button(workflow.name) {
                    runWorkflow(workflow, on: item)
                }
            }
        }
    }

    private func imageWorkflows(for item: ScreenshotItem) -> [Workflow] {
        let objectType = item.parent?.type ?? TalkieObjectType.capture
        return workflowService.workflowsAccepting(
            objectType,
            assetKind: .screenshot,
            surface: .captureContextMenu
        )
    }

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

    // MARK: - Preview / Inspector actions

    /// Anchor on the item and swap the screen into the read-only Quick Look
    /// preview. Markup is the escalation from there.
    private func openPreview(_ item: ScreenshotItem) {
        selectedID = item.id
        if !selectedIDs.contains(item.id) {
            selectedIDs = [item.id]
            selectionAnchorID = item.id
        }
        previewItemID = item.id
    }

    private func clearSelection() {
        selectedIDs.removeAll()
        selectedID = nil
        selectionAnchorID = nil
    }

    private func shareSelected() {
        let urls = allItems.filter { selectedIDs.contains($0.id) }.map(\.fileURL)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func deleteSelected() {
        let items = allItems.filter { selectedIDs.contains($0.id) }
        for item in items { deleteItem(item) }
    }

    private func canShowRecording(_ item: ScreenshotItem) -> Bool {
        guard let parent = item.parent else { return false }
        let t = parent.type.rawValue.lowercased()
        return t == "memo" || t == "dictation"
    }

    private func showRecording(_ item: ScreenshotItem) {
        guard let parent = item.parent else { return }
        if parent.type.rawValue.lowercased() == "dictation" {
            NavigationState.shared.navigateToDictation(parent.id)
        } else {
            NavigationState.shared.navigateToMemo(parent.id)
        }
    }

    // MARK: - Item metadata formatters

    private func sourceLabel(_ item: ScreenshotItem) -> String {
        if let mode = item.screenshot?.captureMode, !mode.isEmpty { return mode }
        if let trayItem = item.trayItem {
            switch trayItem {
            case .screenshot: return "screenshot"
            case .clip:       return "clip"
            case .selection:  return "selection"
            }
        }
        return "screenshot"
    }

    private func imageDimensions(_ item: ScreenshotItem) -> String? {
        if let ss = item.screenshot, let w = ss.width, let h = ss.height {
            return "\(w) × \(h)"
        }
        // Tray items have no stored metadata; read true pixel dims from the
        // file header (cheap) rather than the small in-memory thumbnail.
        if let (w, h) = pixelSize(of: item.fileURL) {
            return "\(w) × \(h)"
        }
        if let img = item.trayItem?.image, img.size.width > 0 {
            return "\(Int(img.size.width)) × \(Int(img.size.height))"
        }
        return nil
    }

    private func pixelSize(of url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    private func fileBytes(_ item: ScreenshotItem) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.fileURL.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func layerCount(for item: ScreenshotItem) -> Int {
        CaptureMarkupStorage.load(forImageURL: item.fileURL)?.layers.count ?? 0
    }

    private func relativeAge(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }

    /// Absolute capture date for the inspector (e.g. "May 28, 2026 · 3:14 PM").
    private func absoluteDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// In-memory (no disk) source/app/window/display facts. Cheap — safe for
    /// the inspector header and also for the recording-attached library row,
    /// which already carries the `RecordingScreenshot`.
    private func appBundleLine(_ item: ScreenshotItem) -> String? {
        item.screenshot?.appName ?? item.trayItem?.appName
    }

    private func windowTitleLine(_ item: ScreenshotItem) -> String? {
        let title = item.screenshot?.windowTitle ?? item.trayItem?.windowTitle
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return title
    }

    private func displayLine(_ item: ScreenshotItem) -> String? {
        item.screenshot?.displayName ?? item.trayItem?.displayName
    }

    /// Inline OCR text for tray items (stored on the model, not the sidecar).
    private func trayOCRText(_ item: ScreenshotItem) -> String? {
        if let trayItem = item.trayItem, case .screenshot(let ts) = trayItem {
            return ts.ocrText
        }
        return nil
    }

    /// Recording-offset for library captures — the `timestampMs` field records
    /// how far into the parent recording the shot was taken.
    private func recordingOffsetLine(_ item: ScreenshotItem) -> String? {
        guard item.parent != nil, let ms = item.screenshot?.timestampMs, ms > 0 else { return nil }
        let totalSeconds = ms / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "+%d:%02d into recording", m, s)
    }

    private func runWorkflow(_ workflow: Workflow, on item: ScreenshotItem) {
        Task { @MainActor in
            let actionRunId = UUID()
            let inputPackageId = UUID()

            do {
                try await startScreenshotActionRun(
                    id: actionRunId,
                    inputPackageId: inputPackageId,
                    workflow: workflow,
                    item: item
                )

                try await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .stepStarted,
                    message: "Resolving screenshot input"
                )
                let target = try await workflowTargetObject(for: item)
                try await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .inputResolved,
                    message: "Input resolved",
                    payloadJSON: actionJSON([
                        "recordId": target.id.uuidString,
                        "recordType": target.type.rawValue,
                        "screenshotCount": target.screenshots.count
                    ])
                )
                try await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .stepStarted,
                    message: "Running \(workflow.name)"
                )

                let outputs = try await WorkflowExecutor.shared.executeWorkflow(workflow.definition, for: target)
                let result = primaryOutput(from: outputs, workflow: workflow.definition)
                let summary = actionSummary(from: result, fallback: "\(workflow.name) completed")

                try await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .artifactCreated,
                    message: "Result captured",
                    payloadJSON: actionJSON([
                        "kind": "text",
                        "preview": summary
                    ])
                )
                try await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .runCompleted,
                    message: "\(workflow.name) completed"
                )
                try await actionRepository.updateActionRun(
                    id: actionRunId,
                    status: .completed,
                    summary: summary,
                    primaryResult: result,
                    completedAt: Date()
                )

                await loadLibrary()
                if item.trayItem != nil {
                    selectedID = target.screenshots.first.map { "lib-\($0.filename)" }
                }
                await notifyScreenshotActionReady(
                    workflowName: workflow.name,
                    actionRunId: actionRunId,
                    status: .completed,
                    message: summary
                )
            } catch {
                Log(.workflow).error("Failed to run workflow from screenshot: \(error.localizedDescription)")
                try? await actionRepository.appendActionEvent(
                    actionRunId: actionRunId,
                    kind: .runFailed,
                    level: .error,
                    message: error.localizedDescription,
                    payloadJSON: actionJSON([
                        "error": error.localizedDescription,
                        "type": String(describing: type(of: error))
                    ])
                )
                try? await actionRepository.updateActionRun(
                    id: actionRunId,
                    status: .failed,
                    summary: error.localizedDescription,
                    errorMessage: error.localizedDescription,
                    errorDetails: String(describing: error),
                    completedAt: Date()
                )
                await notifyScreenshotActionReady(
                    workflowName: workflow.name,
                    actionRunId: actionRunId,
                    status: .failed,
                    message: error.localizedDescription
                )
                await SystemEventManager.shared.log(
                    .error,
                    "Workflow failed: \(workflow.name)",
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func notifyScreenshotActionReady(
        workflowName: String,
        actionRunId: UUID,
        status: ActionRunModel.Status,
        message: String
    ) async {
        let content = UNMutableNotificationContent()
        switch status {
        case .completed:
            content.title = "\(workflowName) is ready"
            content.body = clippedNotificationBody(message, fallback: "Open Actions to review the result.")
            content.sound = .default
        case .failed:
            content.title = "\(workflowName) failed"
            content.body = clippedNotificationBody(message, fallback: "Open Actions to inspect the error.")
            content.sound = .default
        case .queued, .running, .cancelled:
            return
        }

        content.userInfo = [
            "talkieRoute": "aiResults",
            "actionRunId": actionRunId.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "talkie-action-\(actionRunId.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log(.workflow).warning("Failed to show action notification: \(error.localizedDescription)")
        }
    }

    private func clippedNotificationBody(_ message: String, fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.count <= 180 {
            return trimmed
        }
        return "\(trimmed.prefix(180))..."
    }

    private func workflowTargetObject(for item: ScreenshotItem) async throws -> TalkieObject {
        if let parent = item.parent {
            return parent
        }

        if let trayItem = item.trayItem,
           case .screenshot(let screenshot) = trayItem,
           let capture = await TrayActionService.shared.saveTrayScreenshotAsCapture(
            screenshot,
            runOCR: false,
            removeFromTrayOnSuccess: false
           ) {
            return capture
        }

        throw WorkflowError.executionFailed("This item cannot be used as workflow input.")
    }

    private func startScreenshotActionRun(
        id actionRunId: UUID,
        inputPackageId: UUID,
        workflow: Workflow,
        item: ScreenshotItem
    ) async throws {
        let now = Date()
        let run = ActionRunModel(
            id: actionRunId,
            actionId: workflow.id.uuidString,
            actionKind: .workflow,
            title: workflow.name,
            inputPackageId: inputPackageId,
            status: .running,
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            summary: "Running \(workflow.name)"
        )

        let inputPackage = ActionInputPackage(
            id: inputPackageId,
            actionRunId: actionRunId,
            parametersJSON: actionJSON([
                "workflowId": workflow.id.uuidString,
                "workflowName": workflow.name,
                "surface": "captureContextMenu"
            ]),
            derivedContextRefsJSON: actionJSON([
                "assetURL": item.fileURL.path
            ]),
            renderedSnapshot: item.label ?? item.fileURL.lastPathComponent,
            createdAt: now
        )

        let subject = ActionSubjectRef(
            actionRunId: actionRunId,
            kind: .screenshot,
            recordId: item.parent?.id,
            assetURLString: item.fileURL.path,
            titleSnapshot: actionSubjectTitle(for: item),
            createdAt: now
        )

        let events = [
            ActionEventModel(
                actionRunId: actionRunId,
                kind: .runQueued,
                message: "\(workflow.name) queued"
            ),
            ActionEventModel(
                actionRunId: actionRunId,
                kind: .runStarted,
                message: "\(workflow.name) started"
            )
        ]

        try await actionRepository.createActionRun(
            run,
            inputPackage: inputPackage,
            subjectRefs: [subject],
            events: events
        )
    }

    private func actionSubjectTitle(for item: ScreenshotItem) -> String {
        if let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let parent = item.parent {
            if let title = parent.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).screenshotActionNilIfEmpty {
                return title
            }
        }
        if let screenshot = item.screenshot {
            if let windowTitle = screenshot.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).screenshotActionNilIfEmpty {
                return windowTitle
            }
            if let appName = screenshot.appName?.trimmingCharacters(in: .whitespacesAndNewlines).screenshotActionNilIfEmpty {
                return appName
            }
        }
        return item.fileURL.lastPathComponent
    }

    private func primaryOutput(from outputs: [String: String], workflow: WorkflowDefinition) -> String {
        if let outputKey = workflow.steps.last?.outputKey,
           let output = outputs[outputKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }

        let preferredKeys = ["RESULT", "OUTPUT", "SUMMARY", "SCREENSHOT_DESCRIPTION", "uiDescription"]
        for key in preferredKeys {
            if let output = outputs[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        }

        return outputs.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func actionSummary(from output: String, fallback: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }
        if cleaned.count <= 220 { return cleaned }
        return "\(cleaned.prefix(220))..."
    }

    private func actionJSON(_ dictionary: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
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
        // Selected-state stroke intentionally omitted — the prominent outer
        // `selectionOverlay` handles selection; an inner accent stroke would
        // produce a faint double-ring.
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
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

// MARK: - Framed Screenshot (shared image + faux titlebar)

/// The screenshot rendered inside a faux captured-app window frame —
/// traffic lights + app name strip on top, the image below. Shared by
/// the inspector LargePreview and the full Quick Look overlay so both
/// read as "the actual screenshot," not a stretched thumbnail.
private struct FramedScreenshot: View {
    let item: ScreenshotItem
    let appLabel: String
    let annotated: Bool
    var fullResolution: Bool = false
    /// When true, wrap the image in a faux captured-app titlebar (traffic
    /// lights + app name). The small inspector preview uses this so a tile
    /// reads as "a screenshot"; the full Quick Look overlay turns it off and
    /// shows the raw image, the way real Quick Look does.
    var showsChrome: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showsChrome {
                HStack(spacing: 4) {
                    trafficDot
                    trafficDot
                    trafficDot
                    Spacer()
                    Text(appLabel.uppercased())
                        .font(ScopeType.mono(size: 7))
                        .tracking(1.2)
                        .foregroundStyle(ScopePalette.inkFainter)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Color.hex("ECEAE6"))
            }

            ScreenshotImageView(item: item, maxSize: 1400, fullResolution: fullResolution)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ScopePalette.bg)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5).stroke(ScopeEdge.normal, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            if annotated {
                Text("MARKUP")
                    .font(ScopeType.mono(size: 7))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(ScopeBrass.deep)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                    .padding(8)
            }
        }
    }

    private var trafficDot: some View {
        Circle().fill(Color.hex("DDDDDD")).frame(width: 5, height: 5)
    }
}

/// Loads the screenshot image — tray items carry an in-memory NSImage;
/// library items decode a thumbnail off the main thread (same pattern as
/// LibraryCardView).
private struct ScreenshotImageView: View {
    let item: ScreenshotItem
    let maxSize: CGFloat
    /// When true, decode the original file at full resolution instead of a
    /// downscaled thumbnail. Used by the Quick Look preview so zooming
    /// reveals real pixels, not an upscaled thumbnail.
    var fullResolution: Bool = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(ScopePalette.inkSubtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) { image = await load() }
    }

    private func load() async -> NSImage? {
        let url = item.fileURL
        // Full-res (Quick Look preview): always decode the original file.
        // The tray's in-memory `image` is a small thumbnail, so using it
        // here would show a blurry upscale even though the file is full-res.
        if fullResolution {
            if let full = await Task.detached(operation: { NSImage(contentsOf: url) }).value {
                return full
            }
            return item.trayItem?.image
        }
        // Thumbnail path (grid / small inspector preview): fast in-memory
        // image for tray items, else a downscaled decode from disk.
        if let img = item.trayItem?.image { return img }
        let size = maxSize
        return await Task.detached {
            ScreenshotTray.generateThumbnail(for: url, maxSize: size)
        }.value
    }
}

// MARK: - List Row

/// In-memory column values for a list row. Built on the screen side from
/// `RecordingScreenshot` / `TrayScreenshot` fields only — never a disk read.
private struct ScreenshotRowColumns {
    let app: String?
    let source: String
    let dimensions: String?
}

/// Fixed widths so the header and every row line up as a table. The title
/// column is flexible (`.infinity`); the rest are right- or left-aligned
/// fixed columns.
private enum ScreenshotListLayout {
    static let thumb: CGFloat = 48
    static let source: CGFloat = 96
    static let dimensions: CGFloat = 84
    static let age: CGFloat = 60
    static let columnSpacing: CGFloat = 12
}

/// Header row above the list — labels the table columns. Static, so it
/// never reads disk.
private struct ScreenshotListHeader: View {
    var body: some View {
        HStack(spacing: ScreenshotListLayout.columnSpacing) {
            Color.clear.frame(width: ScreenshotListLayout.thumb, height: 1)
            headerCell("NAME · APP", width: nil, alignment: .leading)
            headerCell("SOURCE", width: ScreenshotListLayout.source, alignment: .leading)
            headerCell("DIMENSIONS", width: ScreenshotListLayout.dimensions, alignment: .trailing)
            headerCell("AGE", width: ScreenshotListLayout.age, alignment: .trailing)
        }
        .padding(.horizontal, PageLayout.horizontalPadding)
        .padding(.vertical, 6)
        .background(ScopePalette.bgSunk)
    }

    @ViewBuilder
    private func headerCell(_ label: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(label)
            .font(ScopeType.mono(size: 8.5))
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(ScopePalette.inkFainter)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// Dense, table-aligned row for list view — thumbnail + name/app + source +
/// dimensions + age, all from in-memory metadata. Selection styling mirrors
/// the dictations ScopeLibraryView rows (amber tint + 2pt leading rail).
private struct ScreenshotRowView: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let title: String
    let columns: ScreenshotRowColumns
    let ageLabel: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: ScreenshotListLayout.columnSpacing) {
            ScreenshotImageView(item: item, maxSize: 120)
                .frame(width: ScreenshotListLayout.thumb, height: 34)
                .background(ScopePalette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ScopeEdge.subtle, lineWidth: 0.5))

            // Name + app (flexible column)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let app = columns.app, app != title {
                    Text(app)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(columns.source)
                .font(ScopeType.mono(size: 9))
                .tracking(ScopeType.Tracking.normal)
                .foregroundStyle(ScopeInk.subtle)
                .lineLimit(1)
                .frame(width: ScreenshotListLayout.source, alignment: .leading)

            Text(columns.dimensions ?? "—")
                .font(ScopeType.mono(size: 10))
                .foregroundStyle(columns.dimensions == nil ? ScopeInk.faint : ScopeInk.subtle)
                .lineLimit(1)
                .frame(width: ScreenshotListLayout.dimensions, alignment: .trailing)

            Text(ageLabel)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
                .frame(width: ScreenshotListLayout.age, alignment: .trailing)
        }
        .padding(.horizontal, PageLayout.horizontalPadding)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                ScopeAmber.tintSubtle
            } else if hovered {
                ScopeCanvas.canvasOverlay
            }
        }
        .overlay(alignment: .leading) {
            if isSelected || hovered {
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : ScopeAmber.solid.opacity(0.4))
                    .frame(width: 2)
            }
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Inspector Disk Metadata

/// Metadata that requires a disk read (image-file header + TK sidecar +
/// file attributes). Loaded ASYNC for the single selected item only —
/// NEVER on the per-row list path, which would tank scroll perf.
private struct InspectorDiskMetadata: Equatable {
    var format: String?         // PNG / JPEG …
    var colorModel: String?     // RGB / Gray …
    var hasAlpha: Bool?
    var dpi: Int?
    var pixelSize: String?      // "2880 × 1800" from the file header
    var createdDate: Date?
    var ocrPresent: Bool = false
    var ocrCharacterCount: Int = 0
    var ocrSnippet: String?     // first line(s) of detected text
    var appBundleID: String?
    var backingScale: Double?
    var visionDescribed: Bool = false

    /// Reads the image file header, FileManager attrs, and the TK sidecar
    /// for `url`. Pure (no SwiftUI / main-actor needs) so it runs detached.
    static func load(for url: URL, trayOCRText: String?) -> InspectorDiskMetadata {
        var meta = InspectorDiskMetadata()

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let type = CGImageSourceGetType(source) as String? {
                meta.format = utiToFormatLabel(type)
            }
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                if let w = props[kCGImagePropertyPixelWidth] as? Int,
                   let h = props[kCGImagePropertyPixelHeight] as? Int {
                    meta.pixelSize = "\(w) × \(h)"
                }
                if let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool {
                    meta.hasAlpha = hasAlpha
                }
                // DPI: prefer the explicit DPI keys, then per-format dicts.
                if let dpi = (props[kCGImagePropertyDPIWidth] as? Double) {
                    meta.dpi = Int(dpi.rounded())
                }
                meta.colorModel = colorModelLabel(props)
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let created = attrs[.creationDate] as? Date {
            meta.createdDate = created
        }

        // TK sidecar — OCR text + window-meta + vision description presence.
        if let sidecar = try? TKSidecarStore.read(forAsset: url) {
            if let ocr = sidecar.entry(of: .ocr),
               let geometry = try? ocr.data.decode(OCRGeometryResult.self) {
                meta.ocrPresent = true
                applyOCR(geometry.fullText, to: &meta)
            }
            if let win = sidecar.entry(of: .windowMeta),
               let payload = try? win.data.decode(WindowMetaAugmenter.Payload.self) {
                meta.appBundleID = payload.appBundleID
                meta.backingScale = payload.backingScale
            }
            meta.visionDescribed = sidecar.entry(of: .visionDescription) != nil
        }

        // Tray items keep OCR inline on the model (no sidecar), so fall back
        // to that when the sidecar didn't carry text.
        if !meta.ocrPresent, let trayOCRText, !trayOCRText.isEmpty {
            meta.ocrPresent = true
            applyOCR(trayOCRText, to: &meta)
        }

        return meta
    }

    private static func applyOCR(_ text: String, to meta: inout InspectorDiskMetadata) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meta.ocrCharacterCount = trimmed.count
        let firstLines = trimmed
            .split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: true)
            .prefix(2)
            .joined(separator: " · ")
        meta.ocrSnippet = firstLines.count > 140 ? String(firstLines.prefix(140)) + "…" : firstLines
    }

    private static func utiToFormatLabel(_ uti: String) -> String {
        switch uti {
        case "public.png": return "PNG"
        case "public.jpeg": return "JPEG"
        case "public.heic", "public.heif": return "HEIC"
        case "com.compuserve.gif": return "GIF"
        case "public.tiff": return "TIFF"
        default:
            return uti.split(separator: ".").last.map(String.init)?.uppercased() ?? uti
        }
    }

    private static func colorModelLabel(_ props: [CFString: Any]) -> String? {
        guard let model = props[kCGImagePropertyColorModel] as? String else { return nil }
        switch model as CFString {
        case kCGImagePropertyColorModelRGB: return "RGB"
        case kCGImagePropertyColorModelGray: return "Grayscale"
        case kCGImagePropertyColorModelCMYK: return "CMYK"
        default: return model
        }
    }
}

// MARK: - Inspector

/// Lightweight metadata + actions rail that replaced the full TalkieView
/// detail pane. Shows for any selected item (tray or library) and offers
/// the two open destinations — Preview (read-only) and Markup (annotate).
private struct ScreenshotInspector: View {
    let item: ScreenshotItem
    let multiCount: Int
    let sourceLabel: String
    let dimensions: String?
    let byteLabel: String?
    let layerCount: Int
    let ageLabel: String
    let absoluteDate: String
    let appName: String?
    let windowTitle: String?
    let displayName: String?
    let recordingOffset: String?
    let trayOCRText: String?
    let canMarkup: Bool
    let showRecording: Bool
    let onOpenPreview: () -> Void
    let onOpenMarkup: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void
    let onShowRecording: () -> Void

    /// Disk-loaded extras (file header + sidecar). Loaded async per selection.
    @State private var disk: InspectorDiskMetadata?
    @State private var showDetectedText = false
    @State private var ocrCopied = false

    private var appLabel: String { appName ?? sourceLabel }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip
            HStack {
                Text("· inspector")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopePalette.inkFaint)
                Spacer()
                if multiCount > 1 {
                    Text("\(multiCount) selected")
                        .font(ScopeType.mono(size: 8.5, weight: .semibold))
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopePalette.amberDeep)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(ScopePalette.bgSunk)
            .overlay(alignment: .bottom) { ScopeRule(.subtle) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FramedScreenshot(item: item, appLabel: appLabel, annotated: layerCount > 0)
                        .frame(height: 172)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileURL.lastPathComponent)
                            .font(ScopeType.mono(size: 10, weight: .semibold))
                            .foregroundStyle(ScopePalette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(appLabel) · captured \(ageLabel) ago")
                            .font(.system(size: 12))
                            .foregroundStyle(ScopePalette.inkFaint)
                            .lineLimit(1)
                    }

                    // ── Source group ─────────────────────────────────
                    MetaGroup(title: "source") {
                        MetaRow(label: "capture", value: sourceLabel)
                        if let appName { MetaRow(label: "app", value: appName) }
                        if let bundle = disk?.appBundleID { MetaRow(label: "bundle", value: bundle) }
                        if let windowTitle { MetaRow(label: "window", value: windowTitle) }
                        if let displayName { MetaRow(label: "display", value: displayName) }
                    }

                    // ── Image group ──────────────────────────────────
                    MetaGroup(title: "image") {
                        if let dims = dimensions ?? disk?.pixelSize {
                            MetaRow(label: "dimensions", value: dims)
                        }
                        if let format = disk?.format { MetaRow(label: "format", value: format) }
                        if let color = disk?.colorModel { MetaRow(label: "color", value: color) }
                        if let dpi = disk?.dpi { MetaRow(label: "dpi", value: "\(dpi)") }
                        if let scale = disk?.backingScale { MetaRow(label: "scale", value: "\(formatScale(scale))×") }
                        if let hasAlpha = disk?.hasAlpha { MetaRow(label: "alpha", value: hasAlpha ? "yes" : "no") }
                        if let byteLabel { MetaRow(label: "size", value: byteLabel) }
                    }

                    // ── Captured group ───────────────────────────────
                    MetaGroup(title: "captured") {
                        MetaRow(label: "when", value: absoluteDate)
                        MetaRow(label: "ago", value: ageLabel)
                        if let recordingOffset { MetaRow(label: "offset", value: recordingOffset) }
                    }

                    // ── Detected text + layers group ─────────────────
                    MetaGroup(title: "analysis") {
                        MetaRow(
                            label: "layers",
                            value: layerCount > 0 ? "\(layerCount) · markup" : "—",
                            accent: layerCount > 0
                        )
                        if let disk {
                            MetaRow(
                                label: "ocr",
                                value: disk.ocrPresent
                                    ? (disk.ocrCharacterCount > 0 ? "\(disk.ocrCharacterCount) chars" : "no text")
                                    : "—",
                                accent: disk.ocrCharacterCount > 0,
                                actionSystemImage: "doc.on.clipboard",
                                actionHelp: "Copy OCR text",
                                actionFeedback: ocrCopied,
                                action: disk.ocrCharacterCount > 0 ? copyOCRText : nil
                            )
                            if disk.visionDescribed {
                                MetaRow(label: "vision", value: "described", accent: true)
                            }
                        }
                    }

                    // Detected-text disclosure — surfaces the OCR snippet that
                    // was previously only reachable via the context menu.
                    if let snippet = disk?.ocrSnippet, !snippet.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                showDetectedText.toggle()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: showDetectedText ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text("detected text")
                                        .font(ScopeType.mono(size: 8.5))
                                        .tracking(ScopeType.Tracking.wide)
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                                .foregroundStyle(ScopePalette.inkFainter)
                            }
                            .buttonStyle(.plain)

                            Text(showDetectedText ? (fullOCRText ?? snippet) : snippet)
                                .font(ScopeType.mono(size: 10))
                                .foregroundStyle(ScopePalette.inkFaint)
                                .lineLimit(showDetectedText ? nil : 2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 3).fill(ScopePalette.bgSunk))
                        }
                    }

                    // Open destinations
                    VStack(alignment: .leading, spacing: 8) {
                        Text("open")
                            .font(ScopeType.mono(size: 8.5))
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopePalette.inkFainter)
                        HStack(spacing: 6) {
                            OpenDestButton(label: "Preview", systemImage: "eye", action: onOpenPreview)
                            OpenDestButton(
                                label: "Markup",
                                systemImage: "pencil.tip.crop.circle",
                                primary: true,
                                disabled: !canMarkup,
                                action: onOpenMarkup
                            )
                        }
                        InspectorSecondary(label: "Reveal in Finder", systemImage: "folder", action: onReveal)
                        InspectorSecondary(label: "Copy to clipboard", systemImage: "doc.on.doc", action: onCopy)
                        if showRecording {
                            InspectorSecondary(label: "Show Recording", systemImage: "arrow.up.right.square", action: onShowRecording)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(14)
            }
            .task(id: item.id) {
                // Single-item disk read — header + sidecar + attrs — off the
                // main actor. This is the ONLY disk read tied to selection;
                // list rows never hit this path.
                disk = nil
                showDetectedText = false
                ocrCopied = false
                let url = item.fileURL
                let trayText = trayOCRText
                disk = await Task.detached {
                    InspectorDiskMetadata.load(for: url, trayOCRText: trayText)
                }.value
            }
        }
    }

    private func copyOCRText() {
        guard let text = fullOCRText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ocrCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            ocrCopied = false
        }
    }

    /// Full OCR text for the expanded disclosure — re-read from the sidecar
    /// (or the tray model) only when the user expands it.
    private var fullOCRText: String? {
        if let trayOCRText, !trayOCRText.isEmpty { return trayOCRText }
        guard let sidecar = try? TKSidecarStore.read(forAsset: item.fileURL),
              let entry = sidecar.entry(of: .ocr),
              let geometry = try? entry.data.decode(OCRGeometryResult.self),
              !geometry.fullText.isEmpty else { return nil }
        return geometry.fullText
    }

    private func formatScale(_ scale: Double) -> String {
        scale == scale.rounded() ? "\(Int(scale))" : String(format: "%.1f", scale)
    }
}

/// A titled cluster of MetaRows. Renders nothing if it has no rows (the
/// `@ViewBuilder` content collapses), but in practice each group always
/// has at least one row.
private struct MetaGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ScopeType.mono(size: 8.5))
                .tracking(ScopeType.Tracking.wide)
                .textCase(.uppercase)
                .foregroundStyle(ScopePalette.inkFainter)
            VStack(spacing: 6) { content }
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String
    var accent: Bool = false
    var actionSystemImage: String = "doc.on.clipboard"
    var actionHelp: String = "Copy"
    var actionFeedback: Bool = false
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(ScopeType.mono(size: 9))
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePalette.inkFainter)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: actionFeedback ? "checkmark" : actionSystemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(actionFeedback ? ScopePalette.amberDeep : ScopePalette.inkFainter)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(actionFeedback ? ScopePalette.amberFaint : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(actionFeedback ? "Copied" : actionHelp)
                .accessibilityLabel(actionFeedback ? "Copied" : actionHelp)
            }
            Text(value)
                .font(ScopeType.mono(size: 11))
                .foregroundStyle(accent ? ScopePalette.amberDeep : ScopePalette.ink)
        }
    }
}

private struct OpenDestButton: View {
    let label: String
    let systemImage: String
    var primary: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(ScopeType.mono(size: 10, weight: .semibold))
                    .tracking(ScopeType.Tracking.normal)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .foregroundStyle(primary ? Color.white : ScopePalette.ink)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(primary ? ScopeAmber.solid : ScopePalette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(primary ? Color.clear : ScopePalette.rule, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }
}

private struct InspectorSecondary: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(label)
                    .font(ScopeType.mono(size: 10, weight: .medium))
                    .tracking(ScopeType.Tracking.normal)
                    .textCase(.uppercase)
                Spacer()
            }
            .frame(height: 30)
            .padding(.horizontal, 10)
            .foregroundStyle(ScopePalette.inkFaint)
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(ScopePalette.rule, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selection status-bar verb

private struct StatusVerb: View {
    enum Tone { case neutral, primary, alert, ghost }
    let label: String
    let tone: Tone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(ScopeType.Tracking.normal)
                .textCase(.uppercase)
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 2).fill(background))
                .overlay(
                    RoundedRectangle(cornerRadius: 2).stroke(border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return ScopePalette.ink
        case .primary: return ScopePalette.amberDeep
        case .alert:   return Color.hex("C43A1C")
        case .ghost:   return ScopePalette.inkFainter
        }
    }
    private var background: Color {
        tone == .primary ? ScopePalette.amberFaint : Color.clear
    }
    private var border: Color {
        switch tone {
        case .primary: return ScopePalette.amberSoft
        case .alert:   return Color.hex("C43A1C").opacity(0.30)
        case .ghost:   return Color.clear
        case .neutral: return ScopePalette.rule
        }
    }
}

// MARK: - Preview (Quick Look) Overlay

/// Full-screen read-only preview that the gallery swaps to on "Open in
/// Preview." Image-forward on a calm backdrop with a floating action
/// cluster (Markup hero · Share · Reveal). Markup is the escalation.
private struct ScreenshotPreviewOverlay: View {
    let item: ScreenshotItem
    let sourceLabel: String
    let dimensions: String?
    let byteLabel: String?
    let layerCount: Int
    let canMarkup: Bool
    let onMarkup: () -> Void
    let onShare: () -> Void
    let onReveal: () -> Void
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1

    private var appLabel: String { item.screenshot?.appName ?? sourceLabel }

    /// Pixel aspect (w/h) of the capture — drives the fit-to-window base
    /// size so the image fills the backdrop instead of floating small.
    private var aspect: CGFloat {
        if let ss = item.screenshot, let w = ss.width, let h = ss.height, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        if let img = item.trayItem?.image, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        return 4.0 / 3.0
    }

    private var footerLine: String {
        var parts = [item.fileURL.lastPathComponent, sourceLabel]
        if let dimensions { parts.append(dimensions) }
        if let byteLabel { parts.append(byteLabel) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text("back")
                            .font(ScopeType.mono(size: 9))
                            .tracking(ScopeType.Tracking.normal)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(ScopePalette.inkFaint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ScopePalette.rule, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Text("Preview · \(item.fileURL.lastPathComponent)")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(ScopePalette.bgSunk)
            .overlay(alignment: .bottom) { ScopeRule(.subtle) }

            // Backdrop + image + floating cluster
            ZStack {
                Color.hex("DCDCDB")

                PreviewCanvas(
                    item: item,
                    appLabel: appLabel,
                    annotated: layerCount > 0,
                    aspect: aspect,
                    zoom: zoom
                )

                // Zoom cluster — bottom-right, functional.
                ZoomCluster(
                    zoom: zoom,
                    onZoomOut: { zoom = max(0.25, zoom - 0.25) },
                    onZoomIn: { zoom = min(4, zoom + 0.25) },
                    onFit: { zoom = 1 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(16)

                VStack {
                    Spacer()
                    HStack(spacing: 2) {
                        Button(action: onMarkup) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil.tip.crop.circle").font(.system(size: 12, weight: .semibold))
                                Text("markup")
                                    .font(ScopeType.mono(size: 9.5, weight: .semibold))
                                    .tracking(ScopeType.Tracking.normal)
                                    .textCase(.uppercase)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 5).fill(ScopeAmber.solid))
                        }
                        .buttonStyle(.plain)
                        .opacity(canMarkup ? 1 : 0.4)
                        .disabled(!canMarkup)

                        PreviewClusterVerb(label: "share", systemImage: "square.and.arrow.up", action: onShare)
                        PreviewClusterVerb(label: "reveal", systemImage: "folder", action: onReveal)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ScopePalette.rule, lineWidth: 0.5))
                    .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer rail
            HStack(spacing: 10) {
                Text(footerLine)
                    .font(ScopeType.mono(size: 9))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.inkFainter)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: onClose) {
                    Text("done · back to screenshots")
                        .font(ScopeType.mono(size: 9, weight: .semibold))
                        .tracking(ScopeType.Tracking.normal)
                        .textCase(.uppercase)
                        .foregroundStyle(ScopePalette.inkFaint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(ScopePalette.rule, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(ScopePalette.bgSunk)
            .overlay(alignment: .top) { ScopeRule(.subtle) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopePalette.bg)
        .onChange(of: item.id) { _, _ in zoom = 1 }
    }
}

// Fit-to-window canvas with pan-on-zoom. At zoom 1 the framed screenshot
// fits the backdrop; above 1 it grows and the ScrollView lets you pan.
private struct PreviewCanvas: View {
    let item: ScreenshotItem
    let appLabel: String
    let annotated: Bool
    let aspect: CGFloat
    let zoom: CGFloat

    private let pad: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let availW = max(geo.size.width - pad * 2, 1)
            let availH = max(geo.size.height - pad * 2, 1)
            // Fit the raw image (no titlebar) into the available area.
            let widthIfHeightBound = availH * aspect
            let baseW = min(availW, max(widthIfHeightBound, 1))
            let baseH = baseW / aspect
            let w = baseW * zoom
            let h = baseH * zoom

            ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                FramedScreenshot(
                    item: item,
                    appLabel: appLabel,
                    annotated: annotated,
                    fullResolution: true,
                    showsChrome: false
                )
                    .frame(width: w, height: h)
                    .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 14)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    .animation(.easeOut(duration: 0.14), value: zoom)
            }
        }
    }
}

private struct ZoomCluster: View {
    let zoom: CGFloat
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onFit: () -> Void

    var body: some View {
        HStack(spacing: 1) {
            stepButton("minus", action: onZoomOut)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(ScopeType.mono(size: 9.5))
                .foregroundStyle(ScopePalette.inkFaint)
                .frame(minWidth: 38)
                .monospacedDigit()
            stepButton("plus", action: onZoomIn)
            ScopeRule(.subtle, axis: .vertical).frame(height: 14).padding(.horizontal, 2)
            Button(action: onFit) {
                Text("FIT")
                    .font(ScopeType.mono(size: 8.5, weight: .semibold))
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopePalette.inkFaint)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(ScopePalette.rule, lineWidth: 0.5))
    }

    private func stepButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScopePalette.inkFaint)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

private struct PreviewClusterVerb: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(label)
                    .font(ScopeType.mono(size: 9))
                    .tracking(ScopeType.Tracking.normal)
                    .textCase(.uppercase)
            }
            .foregroundStyle(ScopePalette.inkFaint)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
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
        // `point` is in the SUPERVIEW's coordinate system. The previous
        // implementation compared it to `bounds` (our local coords), which
        // only worked when our frame.origin happened to be (0, 0) in the
        // superview. Inside SwiftUI's hosting hierarchy that's not reliable,
        // so we'd silently fail to intercept clicks → cards never selected.
        // Falling through to the default hitTest correctly checks against
        // our frame in superview coords.
        super.hitTest(point)
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

private extension String {
    var screenshotActionNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// Uses View.cursor(_:) extension from WaveformViews.swift
