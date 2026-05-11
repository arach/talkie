//
//  TrayBadge.swift
//  Talkie
//
//  Floating badge showing tray contents indicator.
//  Three display modes: card (thumbnail fan), pill (glass capsule), minimal (morse dots).
//  All expand to a 3×2 thumbnail grid on hover. Click to open viewer.
//  Right-click to switch display mode.
//
//  Panel is fixed at 320×200 — content animates within it.
//  No panel resize = no hover tracking loop.
//

import AppKit
import SwiftUI
import Observation
import TalkieKit

// MARK: - Display Mode

enum TrayBadgeMode: String, CaseIterable {
    case card
    case pill
    case minimal

    var label: String {
        switch self {
        case .card: "Card"
        case .pill: "Pill"
        case .minimal: "Minimal"
        }
    }
}

@MainActor
final class TrayBadge {
    static let shared = TrayBadge()

    private var panel: NSPanel?

    // Fixed panel size — never resized, avoids hover tracking loops
    // Tall enough for badge + gap + expanded grid stacked vertically
    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 320

    private init() {
        trackTray()
    }

    func refreshVisibility() {
        updateVisibility()
    }

    // MARK: - Observation

    private func trackTray() {
        withObservationTracking {
            let _ = ScreenshotTray.shared.count
            let _ = ClipTray.shared.count
            let _ = SelectionTray.shared.count
            let _ = ServiceManager.shared.live.state
            let _ = TraySettings.shared.externalBadgeEnabled
            let _ = NotchSettings.shared.enabled
            let _ = NotchSettings.shared.trayStripEnabled
            let _ = NotchSettings.shared.trayStripPlacement
            let _ = NotchComposer.shared.isActive
        } onChange: {
            Task { @MainActor in
                self.updateVisibility()
                self.trackTray()
            }
        }
    }

    private func updateVisibility() {
        guard TraySettings.shared.externalBadgeEnabled else {
            dismiss()
            return
        }

        // When notch capability + tray bar are active, the notch owns tray discovery.
        let notchSettings = NotchSettings.shared
        if notchSettings.overlayOwnsTrayDiscovery(isOverlayActive: NotchComposer.shared.isActive) {
            dismiss()
            return
        }

        let hasContent =
            ScreenshotTray.shared.isNotEmpty ||
            ClipTray.shared.isNotEmpty ||
            SelectionTray.shared.isNotEmpty
        if hasContent {
            if panel == nil { show() }
        } else {
            dismiss()
        }
    }

    // MARK: - Show / Dismiss

    private func show() {
        let hostingView = NSHostingView(rootView: BadgeView(
            onTap: { [weak self] in self?.openViewer() },
            onCapture: { [weak self] in self?.capturePanel() }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.autoresizingMask = [.width, .height]

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.contentView?.layer?.masksToBounds = true
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false  // SwiftUI content handles its own shadows
        p.isMovableByWindowBackground = false
        p.sharingType = .none

        positionPanel(p)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        self.panel = p
    }

    private func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        })
    }

    // MARK: - Positioning

    private func positionPanel(_ p: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.midX - panelWidth / 2
        // Top edge flush with top of visible frame (just below menu bar)
        let y = screen.visibleFrame.maxY - panelHeight
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func openViewer() {
        TrayViewer.shared.show()
    }

    private func capturePanel() {
        guard let p = panel else { return }
        capturePanelToClipboard(p)
    }
}

// MARK: - Badge SwiftUI View

private struct BadgeView: View {
    let onTap: () -> Void
    var onCapture: (() -> Void)?

    // MARK: - Settings (read from TraySettings singleton)
    private var ts: TraySettings { .shared }
    private var modeRaw: String { ts.badgeModeRaw }
    private var stripFollowNotchWidth: Bool { ts.badgeFollowNotchWidth }
    private var stripWidthStored: Double { ts.badgeWidth }
    private var stripHeightStored: Double { ts.badgeHeight }
    private var stripDotSizeStored: Double { ts.badgeDotSize }
    private var stripMaxDotsStored: Int { ts.badgeMaxDots }
    private var stripYOffsetStored: Double { ts.badgeYOffset }
    private var stripHoverTargetHeightStored: Double { ts.badgeHoverTargetHeight }
    private var trayBadgeHoverActive: Bool {
        get { NotchComposer.shared.trayBadgeHoverActive }
        nonmutating set { NotchComposer.shared.trayBadgeHoverActive = newValue }
    }
    @State private var isExpanded = false
    @State private var selectedItemID: UUID?
    @State private var clickOutsideMonitor: Any?
    @State private var escapeMonitor: Any?
    @State private var collapseTask: Task<Void, Never>?
    @State private var hoverSuppressionTask: Task<Void, Never>?
    @State private var expandIntentTask: Task<Void, Never>?
    @State private var compactBadgeHovered = false

    private let maxFan = 3
    private let hoverExpandDelay: Duration = .milliseconds(180)

    private var mode: TrayBadgeMode {
        TrayBadgeMode(rawValue: modeRaw) ?? .pill
    }

    private var notchBaselineWidth: CGFloat {
        max(NotchInfo.effective().notchWidth - 4, 172)
    }

    private var stripWidth: CGFloat {
        if stripFollowNotchWidth {
            return notchBaselineWidth
        }
        return CGFloat(max(120, min(stripWidthStored, 420)))
    }

    private var stripHeight: CGFloat {
        CGFloat(max(2, min(stripHeightStored, 12)))
    }

    private var stripDotSize: CGFloat {
        CGFloat(max(1, min(stripDotSizeStored, 8)))
    }

    private var stripMaxDots: Int {
        max(1, min(stripMaxDotsStored, 12))
    }

    private var stripYOffset: CGFloat {
        CGFloat(max(0, min(stripYOffsetStored, 24)))
    }

    private var stripHoverTargetHeight: CGFloat {
        CGFloat(max(0, min(stripHoverTargetHeightStored, 24)))
    }

    private var traySurfaceColor: Color {
        Color(red: 0.07, green: 0.072, blue: 0.078)
    }

    private var liveState: LiveState {
        ServiceManager.shared.live.state
    }

    private var suppressHoverExpansion: Bool {
        liveState == .listening
    }

    var body: some View {
        let allItems = TrayItem.allItems()
        let count = allItems.count

        ZStack(alignment: .top) {
            // Invisible spacer keeps the panel-sized frame stable
            Color.clear
                .frame(width: 320, height: 320)
                .allowsHitTesting(false)

            // Vertical stack: badge at top, expanded grid below
            VStack(spacing: mode == .pill ? 0 : 6) {
                // Badge — always present, hover opens expanded, click opens viewer
                compactBody(allItems: allItems, count: count)
                    .frame(width: mode == .pill ? stripWidth : nil)
                    .opacity(mode == .pill ? 1 : (isExpanded ? 0.5 : 1))
                    .scaleEffect(mode == .pill ? 1 : (isExpanded ? 0.95 : 1.0))
                    .padding(.top, mode == .pill ? stripYOffset : 0)
                    .padding(.bottom, mode == .pill ? stripHoverTargetHeight : 0)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                    .onHover { over in
                        compactBadgeHovered = over
                        if over {
                            if suppressHoverExpansion {
                                if isExpanded { collapse() }
                            } else if !isExpanded {
                                scheduleHoverExpand()
                            }
                        } else if !isExpanded {
                            expandIntentTask?.cancel()
                            expandIntentTask = nil
                            setTrayHoverSuppression(false)
                        }
                    }
                    .onTapGesture { onTap() }
                    .contextMenu {
                        ForEach(TrayBadgeMode.allCases, id: \.self) { m in
                            Button {
                                TraySettings.shared.badgeModeRaw = m.rawValue
                            } label: {
                                HStack {
                                    Text(m.label)
                                    if mode == m {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                // Expanded preview — auto-collapses when cursor leaves, click opens viewer
                if mode == .pill {
                    expandedGridBody(allItems: allItems, count: count)
                        .frame(height: isExpanded ? pillExpandedHeight(for: count) : 0, alignment: .top)
                        .clipped()
                        .offset(y: -stripHoverTargetHeight)
                        .allowsHitTesting(isExpanded)
                } else if isExpanded {
                    expandedGridBody(allItems: allItems, count: count)
                        .onTapGesture {
                            collapse()
                            Task {
                                try? await Task.sleep(for: .milliseconds(120))
                                onTap()
                            }
                        }
                }
            }
            .onHover { over in
                if over {
                    setTrayHoverSuppression(true)
                    collapseTask?.cancel()
                    collapseTask = nil
                } else if isExpanded {
                    collapseTask?.cancel()
                    collapseTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        collapse()
                    }
                } else {
                    setTrayHoverSuppression(false)
                }
            }
        }
        .frame(width: 320, height: 320)
        .clipped()
        .onDisappear {
            collapseTask?.cancel()
            collapseTask = nil
            hoverSuppressionTask?.cancel()
            hoverSuppressionTask = nil
            expandIntentTask?.cancel()
            expandIntentTask = nil
            trayBadgeHoverActive = false
            collapse()
        }
        .onChange(of: liveState) { _, newState in
            if newState == .listening, isExpanded {
                collapse()
            }
        }
    }

    // MARK: - Expand / Collapse

    private func expand() {
        expandIntentTask?.cancel()
        expandIntentTask = nil
        setTrayHoverSuppression(true)
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.06)) {
            isExpanded = true
        }

        // Dismiss on click outside the panel
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [self] _ in
            collapse()
        }

        // Dismiss on Escape
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if event.keyCode == 53 {
                collapse()
                return nil
            }
            return event
        }
    }

    private func collapse() {
        expandIntentTask?.cancel()
        expandIntentTask = nil
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9, blendDuration: 0.04)) {
            isExpanded = false
        }
        setTrayHoverSuppression(false, delayed: true)
        collapseTask?.cancel()
        collapseTask = nil
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m) }
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
        clickOutsideMonitor = nil
        escapeMonitor = nil
    }

    private func setTrayHoverSuppression(_ isActive: Bool, delayed: Bool = false) {
        hoverSuppressionTask?.cancel()
        hoverSuppressionTask = nil

        if isActive {
            trayBadgeHoverActive = true
            return
        }

        guard delayed else {
            trayBadgeHoverActive = false
            return
        }

        hoverSuppressionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            trayBadgeHoverActive = false
        }
    }

    private func scheduleHoverExpand() {
        expandIntentTask?.cancel()
        expandIntentTask = Task { @MainActor in
            try? await Task.sleep(for: hoverExpandDelay)
            guard !Task.isCancelled else { return }
            guard compactBadgeHovered else { return }
            guard !suppressHoverExpansion else { return }
            guard !isExpanded else { return }
            expand()
        }
    }

    // MARK: - Compact Body (mode switch)

    @ViewBuilder
    private func compactBody(allItems: [TrayItem], count: Int) -> some View {
        switch mode {
        case .card:
            compactCardBody(allItems: allItems, count: count)
        case .pill:
            compactPillBody(count: count)
        case .minimal:
            compactMinimalBody(count: count)
        }
    }

    // MARK: - Expanded Grid (shared across all modes)

    private let maxGridItems = 6

    private func pillExpandedHeight(for count: Int) -> CGFloat {
        // Calculate actual content height to prevent overflow
        let cardImageHeight = max(88, stripWidth * 0.34)
        let cardDataStrip: CGFloat = 18
        let headerRow: CGFloat = 20
        let verticalPadding: CGFloat = 16
        let spacing: CGFloat = 8

        if count > 1 {
            // header + card + thumbnail strip + spacing + padding
            let thumbnailStrip: CGFloat = 28
            return headerRow + spacing + (cardImageHeight + cardDataStrip) + spacing + thumbnailStrip + verticalPadding
        }
        // header + card + drag hint + spacing + padding
        let dragHint: CGFloat = 28
        return headerRow + spacing + (cardImageHeight + cardDataStrip) + spacing + dragHint + verticalPadding
    }

    @ViewBuilder
    private func expandedGridBody(allItems: [TrayItem], count: Int) -> some View {
        if mode == .pill {
            expandedBezelViewerBody(allItems: allItems, count: count)
        } else {
            let expandedWidth: CGFloat = 300
            let columnCount: Int = {
                if expandedWidth >= 280 { return 3 }
                if expandedWidth >= 190 { return 2 }
                return 1
            }()
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
            let visible = Array(allItems.suffix(maxGridItems))
            let overflow = count - maxGridItems
            let panelShape = UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12
            )

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Button(action: { onTap() }) {
                        HStack(spacing: 4) {
                            Text("\(count)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(count == 1 ? "item in tray" : "items in tray")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open full tray viewer")
                    Spacer()
                    Button(action: { onCapture?() }) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Screenshot this panel")
                }
                .padding(.horizontal, 14)

                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        gridThumbnail(item: item)
                            .transition(.scale.combined(with: .opacity))
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.7).delay(Double(index) * 0.03),
                                value: isExpanded
                            )
                    }

                    if overflow > 0 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.ultraThinMaterial)
                            Text("+\(overflow)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(height: 72)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 10)
            .frame(width: expandedWidth)
            .background(
                panelShape
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                panelShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }

    @ViewBuilder
    private func expandedBezelViewerBody(allItems: [TrayItem], count: Int) -> some View {
        let expandedWidth = stripWidth
        let panelShape = UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 14,
            topTrailingRadius: 8
        )
        let selected = selectedTrayItem(from: allItems)
        let selectedIndex = selected.flatMap { item in
            allItems.firstIndex(where: { $0.id == item.id })
        } ?? max(0, allItems.count - 1)

        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button(action: { onTap() }) {
                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Text(count == 1 ? "item" : "items")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open full tray viewer")
                Spacer()
                Button(action: { onTap() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.82))
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open full tray viewer")
            }
            .padding(.horizontal, 10)

            if let selected {
                DossierCardView(item: selected, imageHeight: max(88, stripWidth * 0.34), fontSize: 8)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .trayDrag(item: selected)

                if count == 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Drag File")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .trayDrag(item: selected)
                    .help("Drag capture file")
                }
            }

            if count > 1 {
                HStack(spacing: 8) {
                    Button {
                        selectPrevious(allItems: allItems)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIndex <= 0)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(allItems.enumerated()), id: \.element.id) { _, item in
                                thumbnailChip(item: item, isSelected: item.id == selected?.id)
                                    .onTapGesture {
                                        selectedItemID = item.id
                                    }
                            }
                        }
                        .padding(.vertical, 1)
                    }

                    Button {
                        selectNext(allItems: allItems)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIndex >= allItems.count - 1)
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 8)
        .frame(width: expandedWidth)
        .background(
            panelShape
                .fill(traySurfaceColor)
        )
        .overlay(
            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .offset(y: -0.5)
        .onAppear {
            if selectedTrayItem(from: allItems) == nil {
                selectedItemID = allItems.last?.id
            }
        }
        .onChange(of: allItems.map(\.id)) { _, newIDs in
            guard !newIDs.isEmpty else {
                selectedItemID = nil
                return
            }
            if let selectedItemID, newIDs.contains(selectedItemID) {
                return
            }
            selectedItemID = newIDs.last
        }
    }

    // MARK: - Compact: Card Mode

    @ViewBuilder
    private func compactCardBody(allItems: [TrayItem], count: Int) -> some View {
        let behindCount = min(max(count - 1, 0), maxFan)

        ZStack(alignment: .trailing) {
            ForEach(Array(fanCards(from: allItems).enumerated()), id: \.element.id) { index, item in
                let depth = behindCount - index
                let scales: [CGFloat] = [0.97, 0.94, 0.91]
                let opacities: [Double] = [0.7, 0.55, 0.4]
                let s = depth > 0 && depth <= scales.count ? scales[depth - 1] : 1.0
                let o = depth > 0 && depth <= opacities.count ? opacities[depth - 1] : 1.0

                fanThumbnail(item: item, expanded: false)
                    .scaleEffect(s)
                    .opacity(o)
                    .offset(x: -CGFloat(depth) * 8)
                    .transition(.scale.combined(with: .opacity))
            }

            if let latest = allItems.last {
                compactTopCard(item: latest)
                    .transition(.scale.combined(with: .opacity))
            }

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 3, y: 1)
                    )
                    .offset(x: 4, y: 40 / 2 - 4)
            }
        }
        .frame(width: 130, height: 70)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - Compact: Pill Mode

    @ViewBuilder
    private func compactPillBody(count: Int) -> some View {
        let dotCount = min(max(count, 1), stripMaxDots)
        let horizontalPadding = max(3, stripHeight * 0.45)
        let innerWidth = max(1, stripWidth - (horizontalPadding * 2))
        let maxFitDot = (innerWidth - CGFloat(max(0, dotCount - 1))) / CGFloat(max(dotCount, 1))
        let dotSize = max(1, min(stripDotSize, maxFitDot))
        let dotSpacing: CGFloat = dotCount > 1
            ? max(1, (innerWidth - (CGFloat(dotCount) * dotSize)) / CGFloat(dotCount - 1))
            : 0

        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: stripWidth, height: stripHeight)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: stripHeight / 2,
                bottomLeadingRadius: isExpanded ? 0 : stripHeight / 2,
                bottomTrailingRadius: isExpanded ? 0 : stripHeight / 2,
                topTrailingRadius: stripHeight / 2
            )
                .fill(traySurfaceColor)
                .shadow(color: .black.opacity(0.2), radius: isExpanded ? 0 : 3, y: isExpanded ? 0 : 1)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: stripHeight / 2,
                bottomLeadingRadius: isExpanded ? 0 : stripHeight / 2,
                bottomTrailingRadius: isExpanded ? 0 : stripHeight / 2,
                topTrailingRadius: stripHeight / 2
            )
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .drawingGroup(opaque: false)
        .accessibilityLabel("Tray items")
        .accessibilityValue("\(count)")
    }

    // MARK: - Compact: Minimal Mode

    private func compactMinimalBody(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<min(count, 8), id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
    }

    // MARK: - Card Helpers

    private func fanCards(from allItems: [TrayItem]) -> [TrayItem] {
        let count = allItems.count
        guard count > 1 else { return [] }
        let take = min(count - 1, maxFan)
        return Array(allItems.suffix(take + 1).dropLast().reversed())
    }

    @ViewBuilder
    private func compactTopCard(item: TrayItem) -> some View {
        if let nsImage = item.image {
            ZStack(alignment: .bottomLeading) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if item.isClip {
                    Image(systemName: "video.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Circle().fill(Color.red.opacity(0.8)))
                        .offset(x: 3, y: -3)
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 56, height: 40)

                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func gridThumbnail(item: TrayItem) -> some View {
        DossierCardView(item: item, imageHeight: 52, fontSize: 7)
    }

    @ViewBuilder
    private func fanThumbnail(item: TrayItem, expanded: Bool) -> some View {
        let w: CGFloat = expanded ? 80 : 56
        let h: CGFloat = expanded ? 56 : 40
        let r: CGFloat = expanded ? 8 : 6

        if let nsImage = item.image {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color.red.opacity(0.15))
                .frame(width: w, height: h)
                .overlay(
                    Image(systemName: "video.fill")
                        .font(.system(size: expanded ? 16 : 12))
                        .foregroundStyle(.red.opacity(0.5))
                )
        }
    }

    private func selectedTrayItem(from allItems: [TrayItem]) -> TrayItem? {
        if let selectedItemID,
           let selected = allItems.first(where: { $0.id == selectedItemID }) {
            return selected
        }
        return allItems.last
    }

    private func selectPrevious(allItems: [TrayItem]) {
        guard let selected = selectedTrayItem(from: allItems),
              let index = allItems.firstIndex(where: { $0.id == selected.id }),
              index > 0 else { return }
        selectedItemID = allItems[index - 1].id
    }

    private func selectNext(allItems: [TrayItem]) {
        guard let selected = selectedTrayItem(from: allItems),
              let index = allItems.firstIndex(where: { $0.id == selected.id }),
              index < allItems.count - 1 else { return }
        selectedItemID = allItems[index + 1].id
    }

    @ViewBuilder
    private func thumbnailChip(item: TrayItem, isSelected: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let nsImage = item.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 24)
                    .clipped()
            } else {
                Color.white.opacity(0.06)
                    .frame(width: 36, height: 24)
            }

            if item.isClip {
                Image(systemName: "video.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(2)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.16),
                    lineWidth: isSelected ? 1 : 0.5
                )
        )
    }

    private func dragProvider(for item: TrayItem) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: item.tempURL) ?? NSItemProvider()
        provider.suggestedName = item.tempURL.lastPathComponent
        return TalkieInternalDrag.mark(provider)
    }
}
