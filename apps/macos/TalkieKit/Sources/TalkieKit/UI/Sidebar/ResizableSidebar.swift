//
//  ResizableSidebar.swift
//  TalkieKit
//
//  The drag-to-resize / collapse / expand HOST layer for `Sidebar`.
//
//  `Sidebar` (the OG component) is deliberately a pure painter: it takes
//  `progress` (0 expanded → 1 compact) and `labelWidth` and renders the
//  rail + label column + selection underlay. It owns NO state, NO drag,
//  NO persistence.
//
//  All of that behavior used to live privately inside the Talkie app's
//  `AppNavigation` (the edge handle, the live preview width, the cursor
//  management, the collapse/expand gesture detection, the width clamp).
//  That meant "reuse the main nav bar" only ever reused the painter —
//  every host had to re-implement resize. This file lifts the whole
//  interaction layer into TalkieKit so the main app AND TalkieAgent share
//  one nav behavior, not just the look.
//
//  Two entry points:
//    • `ResizableSidebar` — callback-based. The host owns `progress`,
//      `isCompact`, the committed width, and the commit callbacks. Used
//      by the main app, whose chrome bar + detail column also read the
//      derived width/transition, so the host must keep owning that state.
//    • `ManagedResizableSidebar` — binding-based. Hand it `@AppStorage`
//      bindings for `isCompact` + `labelWidth` and it synthesizes the
//      whole collapse/expand/commit state machine internally. Used by
//      lean hosts (TalkieAgent) that just want drag-to-resize for free.
//
//  App dependencies are threaded out as plain values so the kit carries
//  no app-target coupling: theme colors arrive as `accent` / `handleTint`,
//  and the Scope chrome tweak as `isScopeTheme: Bool` (same pattern the
//  `Sidebar` painter already uses).
//

import SwiftUI
import QuartzCore
#if canImport(AppKit)
import AppKit
#endif

private let sidebarResizeLog = Log(.ui)

// MARK: - Callback-based host

/// Wraps the `Sidebar` painter with a draggable trailing edge handle and
/// a live resize preview. The host owns the committed width + compact
/// flag and receives commit callbacks; this view owns only the transient
/// drag-preview width so a drag tick never has to write root state.
public struct ResizableSidebar<Selection: Hashable, RailHeader: View, LabelHeader: View, Footer: View>: View {
    @Binding var selection: Selection?
    let entries: [SidebarEntry<Selection>]
    let progress: Double
    let accent: Color
    let allCaps: Bool
    /// Scope-theme chrome tweak, forwarded to the inner `Sidebar`.
    let isScopeTheme: Bool
    /// Color of the resize pill + its glow (was `Theme.current.foreground`
    /// in the app). Threaded so the kit stays theme-agnostic.
    let handleTint: Color
    let committedLabelWidth: Double
    let isCompact: Bool
    let activationDistance: CGFloat
    let minWidth: Double
    let maxWidth: Double
    let collapseWidth: Double
    @Binding var isDragging: Bool
    let onToggle: () -> Void
    let onResizeEnded: (Double) -> Void
    let onCollapse: (Double) -> Void
    let onExpand: (Double) -> Void
    @ViewBuilder let railHeader: () -> RailHeader
    @ViewBuilder let labelHeader: () -> LabelHeader
    @ViewBuilder let footer: () -> Footer

    public init(
        selection: Binding<Selection?>,
        entries: [SidebarEntry<Selection>],
        progress: Double,
        accent: Color = .accentColor,
        allCaps: Bool = false,
        isScopeTheme: Bool = false,
        handleTint: Color = .primary,
        committedLabelWidth: Double,
        isCompact: Bool,
        activationDistance: CGFloat,
        minWidth: Double,
        maxWidth: Double,
        collapseWidth: Double,
        isDragging: Binding<Bool>,
        onToggle: @escaping () -> Void,
        onResizeEnded: @escaping (Double) -> Void,
        onCollapse: @escaping (Double) -> Void,
        onExpand: @escaping (Double) -> Void,
        @ViewBuilder railHeader: @escaping () -> RailHeader,
        @ViewBuilder labelHeader: @escaping () -> LabelHeader,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self._selection = selection
        self.entries = entries
        self.progress = progress
        self.accent = accent
        self.allCaps = allCaps
        self.isScopeTheme = isScopeTheme
        self.handleTint = handleTint
        self.committedLabelWidth = committedLabelWidth
        self.isCompact = isCompact
        self.activationDistance = activationDistance
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.collapseWidth = collapseWidth
        self._isDragging = isDragging
        self.onToggle = onToggle
        self.onResizeEnded = onResizeEnded
        self.onCollapse = onCollapse
        self.onExpand = onExpand
        self.railHeader = railHeader
        self.labelHeader = labelHeader
        self.footer = footer
    }

    /// Expanded-mode drag preview width. This intentionally lives below
    /// the host: drag ticks can resize the sidebar locally without
    /// writing the host's committed width state that also drives the
    /// detail column and global chrome.
    @State private var dragPreviewLabelWidth: Double?

    private var effectiveLabelWidth: Double {
        dragPreviewLabelWidth ?? committedLabelWidth
    }

    /// Width reported to the parent layout. Tracks the live preview width
    /// so the actual sidebar→detail boundary moves with the cursor during
    /// a resize.
    private var layoutWidth: CGFloat {
        sidebarWidth(labelWidth: effectiveLabelWidth)
    }

    public var body: some View {
        // Overlay with an alignment guide — NOT an HStack sibling and NOT
        // `.offset`. The HStack approach gave the handle real layout
        // width, which pushed everything rightward and made the handle
        // look like a floating tab in a gap. `.offset` is render-only and
        // breaks hit-testing.
        //
        // The trick: `.alignmentGuide(.trailing) { d in d[.trailing] - W/2 }`
        // shifts the overlay's actual frame (and therefore its hit zone)
        // outward by half its width, so the handle's CENTER sits exactly
        // on the sidebar's trailing edge.
        sidebarList
            .overlay(alignment: .trailing) {
                sidebarEdgeHandle
                    .alignmentGuide(.trailing) { d in
                        d[.trailing] - SidebarEdgeHandle.hitWidth / 2
                    }
            }
            .padding(.leading, SidebarLayout.leadingInset)
            .frame(width: layoutWidth, alignment: .leading)
            .overlay(alignment: .trailing) {
                // Permanent trailing separator — the structural divider
                // between the nav rail and the content body. Renders on
                // top of the handle so the resize pill never hides it.
                // Starts at the bottom of the header band so it never
                // slices through the masthead.
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 0.5)
                    .padding(.top, SidebarLayout.headerHeight + SidebarLayout.headerTopPadding)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                // Active-edge highlight during a resize drag. Sits on top
                // of the permanent separator so it visually replaces it
                // while dragging.
                Rectangle()
                    .fill(accent.opacity(isDragging ? 0.42 : 0))
                    .frame(width: 1)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: isDragging)
            }
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    dragPreviewLabelWidth = nil
                }
            }
            .onChange(of: isCompact) { _, _ in
                if !isDragging {
                    dragPreviewLabelWidth = nil
                }
            }
    }

    private var sidebarList: some View {
        Sidebar(
            selection: $selection,
            entries: entries,
            progress: progress,
            accent: accent,
            allCaps: allCaps,
            labelWidth: CGFloat(effectiveLabelWidth),
            onHeaderTap: onToggle,
            isScopeTheme: isScopeTheme,
            railHeader: railHeader,
            labelHeader: labelHeader,
            footer: footer
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sidebarEdgeHandle: some View {
        SidebarEdgeHandle(
            isCompact: isCompact,
            activationDistance: activationDistance,
            currentWidth: effectiveLabelWidth,
            minWidth: minWidth,
            maxWidth: maxWidth,
            collapseWidth: collapseWidth,
            handleTint: handleTint,
            isDragging: $isDragging,
            onToggle: onToggle,
            onResize: { width in
                dragPreviewLabelWidth = clampedPreviewWidth(width)
            },
            onResizeEnded: { width in
                dragPreviewLabelWidth = clampedPreviewWidth(width)
                onResizeEnded(width)
            },
            onCollapse: { restoreWidth in
                dragPreviewLabelWidth = nil
                onCollapse(restoreWidth)
            },
            onExpand: { width in
                dragPreviewLabelWidth = nil
                onExpand(width)
            }
        )
    }

    private func clampedPreviewWidth(_ width: Double) -> Double {
        min(maxWidth, max(0, width))
    }

    private func sidebarWidth(labelWidth: Double) -> CGFloat {
        SidebarLayout.leadingInset
            + SidebarLayout.railWidth
            + CGFloat(labelWidth) * CGFloat(1 - progress)
    }
}

// MARK: - Binding-based managed host

/// Self-managing variant for lean hosts: bind `isCompact` + `labelWidth`
/// (typically `@AppStorage`) and this view owns the entire resize/collapse/
/// expand state machine internally — clamp, persist (via the bindings),
/// and the spring transitions. The host writes zero resize code.
///
/// `progress` is binary (`isCompact ? 1 : 0`); flipping `isCompact` inside
/// a spring transaction animates the label column open/closed.
public struct ManagedResizableSidebar<Selection: Hashable, RailHeader: View, LabelHeader: View, Footer: View>: View {
    @Binding var isCompact: Bool
    @Binding var labelWidth: Double
    let selection: Binding<Selection?>
    let entries: [SidebarEntry<Selection>]
    let accent: Color
    let allCaps: Bool
    let isScopeTheme: Bool
    let handleTint: Color
    let minWidth: Double
    let maxWidth: Double
    let collapseWidth: Double
    let activationDistance: CGFloat
    /// Optional side-effect hook fired whenever compact mode changes
    /// (e.g. a frame-rate / instrumentation probe). Pure observation —
    /// the binding is already updated when this fires.
    let onModeChange: ((Bool) -> Void)?
    @ViewBuilder let railHeader: () -> RailHeader
    @ViewBuilder let labelHeader: () -> LabelHeader
    @ViewBuilder let footer: () -> Footer

    @State private var isDragging = false

    public init(
        isCompact: Binding<Bool>,
        labelWidth: Binding<Double>,
        selection: Binding<Selection?>,
        entries: [SidebarEntry<Selection>],
        accent: Color = .accentColor,
        allCaps: Bool = false,
        isScopeTheme: Bool = false,
        handleTint: Color = .primary,
        minWidth: Double = 100,
        maxWidth: Double = 220,
        collapseWidth: Double = 44,
        activationDistance: CGFloat = 6,
        onModeChange: ((Bool) -> Void)? = nil,
        @ViewBuilder railHeader: @escaping () -> RailHeader,
        @ViewBuilder labelHeader: @escaping () -> LabelHeader,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self._isCompact = isCompact
        self._labelWidth = labelWidth
        self.selection = selection
        self.entries = entries
        self.accent = accent
        self.allCaps = allCaps
        self.isScopeTheme = isScopeTheme
        self.handleTint = handleTint
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.collapseWidth = collapseWidth
        self.activationDistance = activationDistance
        self.onModeChange = onModeChange
        self.railHeader = railHeader
        self.labelHeader = labelHeader
        self.footer = footer
    }

    public var body: some View {
        ResizableSidebar(
            selection: selection,
            entries: entries,
            progress: isCompact ? 1 : 0,
            accent: accent,
            allCaps: allCaps,
            isScopeTheme: isScopeTheme,
            handleTint: handleTint,
            committedLabelWidth: clamped(labelWidth),
            isCompact: isCompact,
            activationDistance: activationDistance,
            minWidth: minWidth,
            maxWidth: maxWidth,
            collapseWidth: collapseWidth,
            isDragging: $isDragging,
            onToggle: {
                withAnimation(SidebarMotion.defaultSpring) { isCompact.toggle() }
                onModeChange?(isCompact)
            },
            onResizeEnded: { width in
                labelWidth = clamped(width)
            },
            onCollapse: { restoreWidth in
                labelWidth = clamped(restoreWidth)
                withAnimation(SidebarMotion.defaultSpring) { isCompact = true }
                onModeChange?(true)
            },
            onExpand: { width in
                labelWidth = clamped(width)
                withAnimation(SidebarMotion.defaultSpring) { isCompact = false }
                onModeChange?(false)
            },
            railHeader: railHeader,
            labelHeader: labelHeader,
            footer: footer
        )
    }

    private func clamped(_ width: Double) -> Double {
        min(maxWidth, max(minWidth, width))
    }
}

// MARK: - Edge handle

/// Hit shape for the resize handle: a full-height narrow band (precise
/// edge) plus a wider center bulge (forgiving where the user reaches for
/// the visible pill).
private struct EdgeHandleHitShape: Shape {
    let narrowWidth: CGFloat
    let wideWidth: CGFloat
    let wideHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Full-height narrow band.
        path.addRect(CGRect(
            x: (rect.width - narrowWidth) / 2,
            y: 0,
            width: narrowWidth,
            height: rect.height
        ))
        // Center wide bulge (clamped so it never overflows the frame).
        let h = min(wideHeight, rect.height)
        path.addRect(CGRect(
            x: (rect.width - wideWidth) / 2,
            y: (rect.height - h) / 2,
            width: wideWidth,
            height: h
        ))
        return path
    }
}

/// Draggable trailing-edge handle: resize in expanded mode, drag-left-past-
/// minimum to collapse, drag-right in compact mode to expand, double-click
/// to toggle. Throttles live resize to display refresh and manages the
/// resize cursor with paired push/pop.
private struct SidebarEdgeHandle: View {
    let isCompact: Bool
    let activationDistance: CGFloat
    let currentWidth: Double
    let minWidth: Double
    let maxWidth: Double
    let collapseWidth: Double
    let handleTint: Color
    @Binding var isDragging: Bool
    let onToggle: () -> Void
    let onResize: (Double) -> Void
    let onResizeEnded: (Double) -> Void
    let onCollapse: (Double) -> Void
    /// Called when the user drags the handle right while the sidebar is
    /// compact, past the activation distance. The argument is the final
    /// label-column width to commit when leaving compact mode.
    let onExpand: (Double) -> Void

    @State private var isHovered = false
    /// Whether we currently have an `NSCursor.resizeLeftRight` pushed.
    /// Pushed when either hover or drag activates; popped only when both
    /// are inactive. Prevents a stale resize cursor after a drag release
    /// lands outside the hit zone.
    @State private var cursorPushed = false
    /// Media time of the last drag-tick commit. Used to throttle drag
    /// updates to ~60Hz — mouse events can fire at 200–1000Hz, and without
    /// throttling each event invalidates the sidebar layout and forces a
    /// relayout cascade through the detail column.
    @State private var lastDragCommitTime: CFTimeInterval = 0
    private static let dragCommitInterval: CFTimeInterval = 1.0 / 60.0
    @State private var dragStartWidth: Double?
    @State private var latestResizeWidth: Double?
    @State private var latestRawWidth: Double?
    @State private var lastLoggedResizeWidth: Double?
    @State private var lastLoggedRawWidth: Double?
    @State private var dragSequence = 0
    @State private var didCommitResize = false
    /// Timestamp of the last click on the handle. Used to detect a
    /// double-click toggle so a single accidental brush past the pill
    /// doesn't flip the whole sidebar mode.
    @State private var lastClickTime: Date?
    /// 350ms window for double-click detection — close enough to the
    /// AppKit default that the gesture feels native without round-tripping
    /// through AppKit.
    private static let doubleClickInterval: TimeInterval = 0.35

    /// Total hit-zone frame width. The parent positions this so the
    /// handle's CENTER sits at the sidebar's trailing edge — half straddles
    /// inside the rail, half outside.
    static let hitWidth: CGFloat = 14

    var body: some View {
        let isActive = isHovered || isDragging

        let handleVisualWidth: CGFloat = 3
        let pillHeight: CGFloat = isActive ? 64 : 56

        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.hitWidth)
            // Hit shape: ±3pt around the trailing edge for the full height
            // (precise edge), with a wider bulge in the middle (lenient
            // around the visible handle area).
            .contentShape(EdgeHandleHitShape(
                narrowWidth: 6,
                wideWidth: Self.hitWidth,
                wideHeight: 88
            ))
            .overlay {
                // Pill is hidden at rest — the separator line is the only
                // resting affordance. Appears on hover/drag, then fades.
                //
                // The 0.25pt leftward offset centers the pill on the
                // *visible separator line* rather than the geometric
                // trailing edge.
                ZStack {
                    if isActive {
                        // Soft outer glow only when active.
                        RoundedRectangle(cornerRadius: 6)
                            .fill(handleTint.opacity(0.08))
                            .frame(width: handleVisualWidth + 8, height: pillHeight + 12)
                            .blur(radius: 6)
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(handleTint.opacity(isActive ? 0.42 : 0))
                        .frame(width: handleVisualWidth, height: pillHeight)
                }
                .offset(x: -0.25)
                .animation(.easeOut(duration: 0.14), value: isActive)
            }
            // Cursor + hover via continuous-hover with paired push/pop.
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if !isHovered { isHovered = true }
                    acquireResizeCursor()
                case .ended:
                    isHovered = false
                    releaseResizeCursorIfIdle()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged(handleDragChanged)
                    .onEnded(handleDragEnded)
            )
            .help(isCompact
                  ? "Double-click to expand; drag right to size"
                  : "Drag to resize; drag left past minimum to collapse")
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if dragStartWidth == nil {
            dragSequence += 1
            // In compact mode the label column has zero width — treat that
            // as the drag origin so rightward dragging measures the
            // emerging width directly.
            let startWidth = isCompact ? 0.0 : currentWidth
            dragStartWidth = startWidth
            latestResizeWidth = nil
            latestRawWidth = nil
            lastLoggedResizeWidth = startWidth
            lastLoggedRawWidth = startWidth
            didCommitResize = false
            logResize(
                "begin",
                detail: "id=\(dragSequence) compact=\(isCompact) start=\(rounded(startWidth)) min=\(rounded(minWidth)) max=\(rounded(maxWidth)) collapse=\(rounded(collapseWidth))"
            )
        }

        let horizontalDelta = value.location.x - value.startLocation.x
        let verticalDelta = value.location.y - value.startLocation.y

        guard abs(horizontalDelta) >= activationDistance,
              abs(horizontalDelta) > abs(verticalDelta) * 1.5
        else { return }

        // In compact mode only treat rightward drag as a resize — left
        // drag should fall through to the end handler (no-op / cancel).
        if isCompact && horizontalDelta <= 0 { return }

        if !didCommitResize {
            logResize(
                "activate",
                detail: "id=\(dragSequence) dx=\(rounded(horizontalDelta)) dy=\(rounded(verticalDelta)) threshold=\(rounded(activationDistance))"
            )
            // Pin the resize cursor for the full duration of the drag.
            // Hover may not have fired (drag can start from a click on the
            // visible pill before hover settles), so guarantee a push here
            // too. acquireResizeCursor is idempotent.
            acquireResizeCursor()
        }

        didCommitResize = true
        if !isDragging {
            isDragging = true
        }

        let rawProposed = (dragStartWidth ?? currentWidth) + Double(horizontalDelta)
        let proposed = clampedWidth(rawProposed)
        // Always update the "latest" values — drag-end reads these to
        // commit the final position even if the very last tick is
        // throttled. Cheap state writes.
        latestResizeWidth = proposed
        latestRawWidth = rawProposed
        logResizeUpdateIfNeeded(width: proposed, rawWidth: rawProposed, horizontalDelta: horizontalDelta)

        // Throttle the actual `onResize` write to display refresh rate.
        // The mouse fires events at 200–1000Hz; committing each one
        // invalidates the sidebar layout and triggers a detail-column
        // relayout. Display refresh is 60Hz, so anything faster is
        // invisible anyway.
        let now = CACurrentMediaTime()
        if now - lastDragCommitTime < Self.dragCommitInterval {
            return
        }
        lastDragCommitTime = now

        // Compact-mode preview is intentionally skipped for perf — the
        // write on every drag tick invalidated the host root body and
        // caused random column resizes. Keep the actual resize gated to
        // expanded mode; compact-mode drag commits only on drag-end via
        // onExpand.
        if !isCompact {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onResize(proposed)
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let horizontalDelta = value.location.x - value.startLocation.x
        let verticalDelta = value.location.y - value.startLocation.y

        if didCommitResize {
            let finalWidth = latestResizeWidth ?? currentWidth
            let finalRawWidth = latestRawWidth ?? finalWidth
            let startWidth = dragStartWidth ?? currentWidth
            if isCompact {
                // Compact mode → rightward drag commit. Expand to the
                // proposed width (clamped to min so the sidebar always
                // ends up usable, never a vestigial sliver).
                let target = max(finalWidth, minWidth)
                logResize(
                    "expand",
                    detail: "id=\(dragSequence) final=\(rounded(target)) raw=\(rounded(finalRawWidth)) dx=\(rounded(horizontalDelta)) dy=\(rounded(verticalDelta))"
                )
                onExpand(target)
            } else if finalWidth <= collapseWidth, horizontalDelta < 0 {
                logResize(
                    "collapse",
                    detail: "id=\(dragSequence) final=\(rounded(finalWidth)) raw=\(rounded(finalRawWidth)) restore=\(rounded(startWidth)) dx=\(rounded(horizontalDelta)) dy=\(rounded(verticalDelta))"
                )
                onCollapse(startWidth)
            } else {
                logResize(
                    "end",
                    detail: "id=\(dragSequence) final=\(rounded(finalWidth)) raw=\(rounded(finalRawWidth)) change=\(rounded(finalWidth - startWidth)) dx=\(rounded(horizontalDelta)) dy=\(rounded(verticalDelta))"
                )
                onResizeEnded(finalWidth)
            }
        } else if abs(horizontalDelta) < activationDistance,
                  abs(verticalDelta) < activationDistance {
            // Click on the handle. Require a DOUBLE click to toggle — the
            // handle's hit area is wide enough that a single click is easy
            // to fire accidentally when reaching for an icon at the rail
            // edge.
            let now = Date()
            if let last = lastClickTime,
               now.timeIntervalSince(last) <= Self.doubleClickInterval {
                logResize(
                    "double-click-toggle",
                    detail: "id=\(dragSequence) compact=\(isCompact) interval=\(Int(now.timeIntervalSince(last) * 1000))ms"
                )
                lastClickTime = nil
                onToggle()
            } else {
                logResize(
                    "click-ignored",
                    detail: "id=\(dragSequence) compact=\(isCompact) (waiting for second click)"
                )
                lastClickTime = now
            }
        } else {
            logResize(
                "cancel",
                detail: "id=\(dragSequence) dx=\(rounded(horizontalDelta)) dy=\(rounded(verticalDelta))"
            )
        }

        dragStartWidth = nil
        latestResizeWidth = nil
        latestRawWidth = nil
        lastLoggedResizeWidth = nil
        lastLoggedRawWidth = nil
        didCommitResize = false
        isDragging = false
        // Pop only if hover isn't currently holding the cursor — a release
        // that lands inside the hit zone should still show the resize
        // affordance.
        releaseResizeCursorIfIdle()
    }

    /// Push the resize cursor if not already pushed.
    private func acquireResizeCursor() {
        guard !cursorPushed else { return }
        #if canImport(AppKit)
        NSCursor.resizeLeftRight.push()
        #endif
        cursorPushed = true
    }

    /// Pop the resize cursor only if neither hover nor drag wants it.
    private func releaseResizeCursorIfIdle() {
        guard cursorPushed, !isHovered, !isDragging else { return }
        #if canImport(AppKit)
        NSCursor.pop()
        #endif
        cursorPushed = false
    }

    private func logResizeUpdateIfNeeded(width: Double, rawWidth: Double, horizontalDelta: CGFloat) {
        let previousWidth = lastLoggedResizeWidth ?? width
        let previousRawWidth = lastLoggedRawWidth ?? rawWidth

        guard lastLoggedResizeWidth == nil
            || abs(width - previousWidth) >= 8
            || abs(rawWidth - previousRawWidth) >= 24
        else {
            return
        }

        lastLoggedResizeWidth = width
        lastLoggedRawWidth = rawWidth
        logResize(
            "update",
            detail: "id=\(dragSequence) width=\(rounded(width)) raw=\(rounded(rawWidth)) dx=\(rounded(horizontalDelta))"
        )
    }

    private func clampedWidth(_ width: Double) -> Double {
        min(maxWidth, max(0, width))
    }

    private func logResize(_ event: String, detail: String) {
        sidebarResizeLog.info("[SidebarResize] \(event)", detail: detail, section: "SidebarResize")
    }

    private func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private func rounded(_ value: CGFloat) -> Int {
        Int(value.rounded())
    }
}
