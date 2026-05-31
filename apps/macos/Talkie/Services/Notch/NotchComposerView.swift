//
//  NotchComposerView.swift
//  Talkie
//
//  Root SwiftUI view for the notch overlay.
//  Recording layout matches Agent's NotchOverlayView minimal style exactly.
//
//  Architecture:
//  - Recording: unified shape covers wings + optional tray as one surface.
//  - Idle/other: notch wings + optional pills below (camera, screen recording).
//

import SwiftUI
import Observation
import TalkieKit

/// Shape used for `.contentShape` on the notch overlay.
/// When restricted, creates a small centered rectangle at the top (hover zone).
/// When unrestricted, fills the entire rect (normal interactive area).
struct HoverZoneShape: Shape {
    var restrictedWidth: CGFloat?
    var restrictedHeight: CGFloat?

    func path(in rect: CGRect) -> Path {
        guard let w = restrictedWidth, let h = restrictedHeight else {
            return Path(rect)
        }
        let zoneRect = CGRect(
            x: rect.midX - w / 2,
            y: rect.minY,
            width: w,
            height: min(h, rect.height)
        )
        return Path(zoneRect)
    }
}

enum NotchVirtualDisplayStyle: String, CaseIterable, Identifiable {
    case auto
    case island
    case notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .island:
            return "Island"
        case .notch:
            return "Notch"
        }
    }

    var subtitle: String {
        switch self {
        case .auto:
            return "Notch shape on camera displays, island shape on external displays."
        case .island:
            return "Detached rounded rectangle with external curves, floating below the top edge."
        case .notch:
            return "Attached to the top edge with inward curves, no gap — same shape as camera displays."
        }
    }
}

private let notchDebugLog = Log(.ui)

private struct NotchInteractiveContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct NotchComposerView: View {
    let composer: NotchComposer
    let notchInfo: NotchInfo

    @Bindable private var tuning = NotchTuning.shared
    @State private var trayItemsSnapshot: [TrayItem] = []
    private var trayBadgeHoverActive: Bool { composer.trayBadgeHoverActive }
    // MARK: - Settings (read from NotchSettings singleton)
    private var ns: NotchSettings { .shared }
    private var notchAggressiveDebugLogging: Bool { ns.aggressiveDebugLogging }
    private var notchCommunicationDemoEnabled: Bool { ns.communicationDemoEnabled }
    private var notchAnimationInspectorEnabled: Bool { ns.inspectorEnabled }
    private var notchAnimationInspectorScrubEnabled: Bool { ns.inspectorScrubEnabled }
    private var notchAnimationInspectorProgress: Double { ns.inspectorProgress }
    private var notchAnimationInspectorExtensionWidthDelta: Double { ns.inspectorExtensionWidthDelta }
    private var notchAnimationInspectorExtensionWidthMatch: Double { ns.inspectorExtensionWidthMatch }
    private var notchAnimationInspectorExtensionWidthReference: String { ns.inspectorExtensionWidthReferenceRaw }
    private var notchAnimationInspectorExtensionYOffset: Double { ns.inspectorExtensionYOffset }
    private var notchAnimationInspectorExtensionDropDistance: Double { ns.inspectorExtensionDropDistance }
    private var notchAnimationInspectorExpansionStart: Double { ns.inspectorExpansionStart }
    private var notchAnimationInspectorBarAttachStart: Double { ns.inspectorBarAttachStart }
    private var notchAnimationInspectorBarAttachDuration: Double { ns.inspectorBarAttachDuration }
    private var notchAnimationInspectorRecordingExtensionPreview: String { ns.inspectorRecordingExtensionPreviewRaw }
    private var notchTrayIndicatorShowDots: Bool { ns.trayStripShowDots }
    private var notchTrayIndicatorWidth: Double { ns.trayStripWidth }
    private var notchTrayIndicatorHeight: Double { ns.trayStripHeight }
    private var notchTrayIndicatorDotSize: Double { ns.trayStripDotSize }
    private var notchTrayIndicatorMaxDots: Int { ns.trayStripMaxDots }
    private var notchTrayIndicatorBorderOpacity: Double { ns.trayStripBorderOpacity }
    private var notchTrayIndicatorYOffset: Double { ns.trayStripYOffset }
    private var notchTrayPreviewWhileRecordingEnabled: Bool { ns.trayPreviewWhileRecordingEnabled }
    private var notchVirtualDisplayStyleRaw: String { ns.shellStyleRaw }
    @State private var isHovered: Bool = false
    @State private var isCommunicationIndicatorHovered: Bool = false
    @State private var isTrayWingHovered: Bool = false
    @State private var idleTrayDismissTask: Task<Void, Never>?
    @State private var hoverExitTask: Task<Void, Never>?
    @State private var isRecordingExpanded: Bool = false
    @State private var showRecordingLayout: Bool = false
    @State private var renderPokeOut: CGFloat = 0
    @State private var transitionPhase: TransitionPhase = .stable(.rest)
    @State private var transitionSerial: Int = 0
    @State private var transitionTask: Task<Void, Never>?
    @State private var shouldHideRecordingLayoutAfterCollapse = false
    @State private var communicationDismissedByGesture = false
    @State private var liveSurfaceReveal: CGFloat = 0
    @State private var recordingDismissedByGesture = false
    @State private var notchMinimized = false
    /// When true, hover-reveal is temporary (re-minimizes on exit). Swipe down locks it open.
    @State private var notchMinimizedAutoHide = false
    /// Horizontal drag offset for the minimized nub (temporary repositioning).
    @State private var nubDragOffset: CGFloat = 0
    @State private var nubDragAccumulated: CGFloat = 0
    /// Tracks whether the mouse is hovering close to the nub (for zone visibility).
    @State private var nubProximityHovered = false

    // Match Agent exactly
    private let cornerRadius: CGFloat = 12

    private var resolvedVirtualDisplayStyle: NotchVirtualDisplayStyle {
        ns.resolvedShellStyle(for: notchInfo)
    }

    /// Unified layout: no center gap, unified particles, single surface.
    /// True on all virtual/external displays. False only on physical-notch displays.
    private var unified: Bool {
        notchInfo.isVirtual
    }

    /// Within unified layout, whether the shape is a rounded rectangle (island)
    /// or wing curves attached to the top edge (notch).
    private var unifiedUsesIslandShape: Bool {
        unified && resolvedVirtualDisplayStyle == .island
    }

    private var islandSurfaceCornerRadius: CGFloat {
        max(10, min(18, bottomRadius + 2))
    }

    // Keep core geometry stable; styles change behavior and ornamentation.
    private var notchWidth: CGFloat {
        max(notchInfo.notchWidth - 4, 172)
    }

    /// Effective gap between wings. Zero on unified displays (no physical notch).
    private var effectiveNotchGap: CGFloat {
        unified ? 0 : notchWidth
    }

    // Three-tier expansion (same as Agent)
    private enum ExpansionState: Equatable {
        case rest
        case hover
        case active
    }

    private enum TransitionPhase: Equatable {
        case stable(ExpansionState)
        case transitioning(from: ExpansionState, to: ExpansionState, serial: Int)
    }

    private enum ExtensionWidthReference: String {
        case core
        case full
    }

    private enum RecordingExtensionPreviewMode: String {
        case live
        case collapsed
        case expanded
    }

    private var recordingIntentActive: Bool {
        if case .recording = composer.resolvedIntent {
            return true
        }
        return false
    }

    // Only recording drives the "active" expansion. Pills don't expand wings.
    private var desiredExpansionState: ExpansionState {
        if recordingDismissedByGesture {
            return .rest
        }
        if recordingIntentActive || isRecordingExpanded {
            return .active
        } else if trayBadgeHoverActive && !notchCommunicationDemoEnabled {
            return .rest
        } else if isHovered || ns.alwaysVisible {
            return .hover
        } else {
            return .rest
        }
    }

    // Dynamic wing poke out.
    // Preserve master geometry for notch shells on virtual displays; island keeps
    // a separate detached profile.
    private var virtualWidthBonus: CGFloat {
        guard unified else { return 0 }
        return unifiedUsesIslandShape ? 28 : 40
    }

    private func pokeOut(for state: ExpansionState) -> CGFloat {
        switch state {
        case .rest: return 0
        case .hover: return CGFloat(max(0, tuning.hoverPokeOut)) + virtualWidthBonus
        case .active:
            let base = CGFloat(max(0, tuning.activePokeOut))
            return base + 48 + virtualWidthBonus
        }
    }

    private var targetPokeOut: CGFloat {
        pokeOut(for: desiredExpansionState)
    }

    private var transitionTargetState: ExpansionState {
        switch transitionPhase {
        case .stable(let state):
            state
        case .transitioning(_, let to, _):
            to
        }
    }

    private var transitionSourceState: ExpansionState {
        switch transitionPhase {
        case .stable(let state):
            state
        case .transitioning(let from, _, _):
            from
        }
    }

    private var notchAnimatorAttachmentProgress: CGFloat {
        guard notchAnimatorActive else { return 1 }
        guard notchAnimatorProgressClamped > notchAnimatorBarAttachStartClamped else { return 0 }
        let attachSpan = max(0.001, notchAnimatorBarAttachDurationClamped)
        return min(1, max(0, (notchAnimatorProgressClamped - notchAnimatorBarAttachStartClamped) / attachSpan))
    }

    private var notchAnimatorPokeOut: CGFloat {
        guard notchAnimatorActive else { return renderPokeOut }

        let rest = pokeOut(for: .rest)
        let hover = pokeOut(for: .hover)
        let active = pokeOut(for: .active)
        let attachProgress = notchAnimatorAttachmentProgress
        let split: CGFloat = 0.45

        if attachProgress <= split {
            let local = split > 0 ? attachProgress / split : 0
            return interpolate(rest, hover, local)
        }

        let trailingSpan = max(0.001, 1 - split)
        let local = min(1, max(0, (attachProgress - split) / trailingSpan))
        return interpolate(hover, active, local)
    }

    private var wingRenderWidth: CGFloat {
        max(0, notchAnimatorPokeOut)
    }

    private var leftOuterShoulder: CGFloat {
        guard wingRenderWidth > 0 else { return 0 }
        // Match the clamped radius the shape actually uses at this wing width,
        // so the shoulder grows continuously with the wing — no pop.
        let maxR = min(wingRenderWidth, overlayHeight) / 2
        return min(max(0, leftTopOuterRadius), maxR)
    }

    private var rightOuterShoulder: CGFloat {
        guard wingRenderWidth > 0 else { return 0 }
        let maxR = min(wingRenderWidth, overlayHeight) / 2
        return min(max(0, rightTopOuterRadius), maxR)
    }

    private var visibleLeftWingWidth: CGFloat {
        wingRenderWidth + leftOuterShoulder
    }

    private var visibleRightWingWidth: CGFloat {
        wingRenderWidth + rightOuterShoulder
    }

    private var renderedTotalWidth: CGFloat {
        effectiveNotchGap + (wingRenderWidth * 2) + leftOuterShoulder + rightOuterShoulder
    }

    private var totalWidth: CGFloat { effectiveNotchGap + visibleLeftWingWidth + visibleRightWingWidth }

    private var renderedCoreWidth: CGFloat {
        effectiveNotchGap + (wingRenderWidth * 2)
    }

    // Dynamic height matching menu bar (same as Agent)
    private var overlayHeight: CGFloat {
        // Keep retract purely horizontal (x-axis) with no intermediate y-shrink state.
        notchInfo.notchHeight - CGFloat(tuning.heightInset)
    }

    // Colors — match the physical notch as closely as possible.
    // Opacity lerps from user setting toward 1.0 as tray extension emerges.
    private var effectiveOverlayOpacity: Double {
        let base = ns.overlayOpacity
        let progress = Double(communicationSurfaceProgress)
        return base + (1.0 - base) * progress
    }
    private var overlayColor: Color { Color(white: 0.05).opacity(effectiveOverlayOpacity) }
    private var particleZoneColor: Color { Color(white: 0.03).opacity(effectiveOverlayOpacity) }

    private var islandWingFillColor: Color {
        unifiedUsesIslandShape ? overlayColor : particleZoneColor
    }

    private let trayHeight: CGFloat = 22

    private var leftTopOuterRadius: CGFloat {
        CGFloat(tuning.leftTopOuterRadius)
    }

    private var rightTopOuterRadius: CGFloat {
        CGFloat(tuning.rightTopOuterRadius)
    }

    private var topInnerRadius: CGFloat {
        CGFloat(max(0, tuning.topInnerRadius))
    }

    private var bottomRadius: CGFloat {
        CGFloat(max(0, tuning.bottomRadius))
    }

    private var notchOverlap: CGFloat {
        CGFloat(max(0, tuning.notchOverlap))
    }

    private var minimumNotchOverlap: CGFloat {
        // Dimension-driven floor so the physical notch bottom corners remain covered
        // during collapse without requiring aggressive user overlap values.
        let fromNotchHeight = ceil(notchInfo.notchHeight * 0.22)
        // Ensure wing width at rest can support the full configured bottom radius:
        // br = min(bottomRadius, wing / 2) -> need wing >= 2 * bottomRadius.
        let fromWingBottomRadius = ceil((bottomRadius * 2) + 1)
        let fromOuterTopArc = ceil(max(leftTopOuterRadius, rightTopOuterRadius) * 0.25)
        let required = max(6, fromNotchHeight, fromWingBottomRadius, fromOuterTopArc)

        // Keep the floor bounded so it doesn't over-expand under very wide notches.
        // Bound must still permit full corner coverage on large bottom radii.
        let upperBound = max(fromWingBottomRadius, min(42, floor(notchWidth * 0.22)))
        return min(required, upperBound)
    }

    private var innerCurveMode: NotchInnerCurveMode {
        tuning.innerCurveMode
    }

    private var isTrayExpanded: Bool {
        isTrayWingHovered
    }

    private var shouldOpenTrayFromIdleTap: Bool {
        !unified && ns.trayDotsInside && trayItemCount > 0 && isHovered && isTrayWingHovered
    }

    private let expandDurationSeconds: Double = 0.12
    private let collapseDurationSeconds: Double = 0.08
    private let notchAnimatorFullThreshold: CGFloat = 0.72

    private var notchAnimatorActive: Bool {
        notchAnimationInspectorEnabled && notchAnimationInspectorScrubEnabled
    }

    private var notchAnimatorProgressClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorProgress, 0), 1))
    }

    private var notchAnimatorExpansionStartClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorExpansionStart, 0), 0.95))
    }

    private var notchAnimatorBarAttachStartClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorBarAttachStart, 0), 0.90))
    }

    private var notchAnimatorBarAttachDurationClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorBarAttachDuration, 0.06), 0.50))
    }

    private var notchAnimatorExtensionWidthMatchClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorExtensionWidthMatch, 0.75), 1.25))
    }

    private var notchAnimatorExtensionWidthReference: ExtensionWidthReference {
        ExtensionWidthReference(rawValue: notchAnimationInspectorExtensionWidthReference) ?? .full
    }

    private var recordingExtensionPreviewMode: RecordingExtensionPreviewMode {
        RecordingExtensionPreviewMode(rawValue: notchAnimationInspectorRecordingExtensionPreview) ?? .live
    }

    private var effectiveRecordingExtensionPreviewMode: RecordingExtensionPreviewMode {
        notchAnimatorActive ? recordingExtensionPreviewMode : .live
    }

    private var notchAnimatorDropDistanceClamped: CGFloat {
        CGFloat(min(max(notchAnimationInspectorExtensionDropDistance, 0), 24))
    }

    private var liveFrameProgress: CGFloat {
        let rest = pokeOut(for: .rest)
        let active = pokeOut(for: .active)
        let span = max(0.001, active - rest)
        return min(1, max(0, (renderPokeOut - rest) / span))
    }

    private var animationFrameProgress: CGFloat {
        notchAnimatorActive ? notchAnimatorProgressClamped : liveFrameProgress
    }

    private var notchAnimatorSurfaceProgress: CGFloat {
        guard notchAnimatorActive else { return 1 }
        let start = notchAnimatorExpansionStartClamped
        let progress = notchAnimatorProgressClamped
        guard progress > start else { return 0 }
        let span = max(0.001, 1 - start)
        return min(1, max(0, (progress - start) / span))
    }

    private var communicationInteractivelyRequested: Bool {
        if showRecordingLayout && !notchTrayPreviewWhileRecordingEnabled {
            return false
        }
        // Outside strip: only strip hover triggers reveal.
        if ns.trayDotsOutside {
            return isCommunicationIndicatorHovered || isTrayExpanded || trayBadgeHoverActive
        }
        // Inside dots during idle: require explicit tray engagement, not just notch hover.
        // Keep this explicit during recording too to avoid auto-loading tray preview while
        // record UI is active.
        if !showRecordingLayout {
            return isCommunicationIndicatorHovered || isTrayExpanded || trayBadgeHoverActive
        }
        return isCommunicationIndicatorHovered || isTrayExpanded || trayBadgeHoverActive
    }

    private func communicationReferenceWidth(for pokeOut: CGFloat) -> CGFloat {
        let coreWidth = effectiveNotchGap + (pokeOut * 2)
        let shoulders = pokeOut > 0 ? max(0, leftTopOuterRadius) + max(0, rightTopOuterRadius) : 0
        if unifiedUsesIslandShape {
            // Island visual style should match full outer span, not the inner core.
            return coreWidth + shoulders
        }
        // Physical notch displays: always use core width. The shoulders are
        // decorative curves that hug the notch — not usable content area.
        // Using the full span makes the tray preview overshoot the wings.
        if !unified {
            return coreWidth
        }
        switch notchAnimatorExtensionWidthReference {
        case .core:
            return coreWidth
        case .full:
            return coreWidth + shoulders
        }
    }

    private var communicationDockStartWidth: CGFloat {
        let rest = pokeOut(for: .rest)
        let active = pokeOut(for: .active)
        let startPokeOut = interpolate(rest, active, notchAnimatorBarAttachStartClamped)
        let base = communicationReferenceWidth(for: startPokeOut)
        let scaled = base * notchAnimatorExtensionWidthMatchClamped
        return max(120, scaled + CGFloat(notchAnimationInspectorExtensionWidthDelta))
    }

    private var communicationDockTargetWidth: CGFloat {
        let base = communicationReferenceWidth(for: notchAnimatorPokeOut)
        let scaled = base * notchAnimatorExtensionWidthMatchClamped
        return max(120, scaled + CGFloat(notchAnimationInspectorExtensionWidthDelta))
    }

    private var communicationAttachProgress: CGFloat {
        if !notchAnimatorActive {
            return communicationRevealActive ? 1 : 0
        }
        let start = notchAnimatorBarAttachStartClamped
        let progress = animationFrameProgress
        guard progress > start else { return 0 }
        let span = max(0.001, notchAnimatorBarAttachDurationClamped)
        return min(1, max(0, (progress - start) / span))
    }

    private var communicationDockWidth: CGFloat {
        interpolate(communicationDockStartWidth, communicationDockTargetWidth, communicationAttachProgress)
    }

    private var communicationRevealActive: Bool {
        if showRecordingLayout && !notchTrayPreviewWhileRecordingEnabled {
            return false
        }
        if communicationDismissedByGesture {
            return false
        }
        if showRecordingLayout {
            switch effectiveRecordingExtensionPreviewMode {
            case .collapsed:
                return false
            case .expanded:
                return true
            case .live:
                if notchAnimatorActive {
                    return true
                }
                return communicationInteractivelyRequested
            }
        }
        if notchAnimatorActive {
            return true
        }
        return communicationInteractivelyRequested
    }

    private var recordingCommunicationPresentationVisible: Bool {
        if !notchTrayPreviewWhileRecordingEnabled {
            return false
        }
        switch effectiveRecordingExtensionPreviewMode {
        case .collapsed:
            return false
        case .expanded:
            return true
        case .live:
            return notchAnimatorActive || communicationInteractivelyRequested
        }
    }

    private var communicationStripOpacity: Double {
        if showRecordingLayout {
            return Double(max(0, 1 - (communicationSurfaceProgress * 1.6)))
        }
        return 1
    }

    private var trayIndicatorWidthClamped: CGFloat {
        let requested = CGFloat(max(24, notchTrayIndicatorWidth))
        let maxWidth = max(24, communicationDockWidth - 14)
        return min(requested, maxWidth)
    }

    private var trayIndicatorHeightClamped: CGFloat {
        CGFloat(min(max(notchTrayIndicatorHeight, 4), 16))
    }

    private var trayIndicatorDotSizeClamped: CGFloat {
        CGFloat(min(max(notchTrayIndicatorDotSize, 1.5), 4.5))
    }

    private var trayIndicatorBorderOpacityClamped: CGFloat {
        CGFloat(min(max(notchTrayIndicatorBorderOpacity, 0), 0.8))
    }

    private var trayItems: [TrayItem] {
        trayItemsSnapshot
    }

    private var trayItemCount: Int {
        trayItems.count
    }

    private var shouldShowCommunicationFramework: Bool {
        true
    }

    private var shouldShowCommunicationStrip: Bool {
        ns.trayDotsOutside
    }

    private var communicationDockYOffset: CGFloat {
        // Keep the attachment tucked into the notch bottom edge, then settle slightly lower as it expands.
        let baseOffset = -1.9 + (communicationAttachProgress * 0.7)
        let revealTravel = (1 - communicationSurfaceProgress) * notchAnimatorDropDistanceClamped * 0.45
        return baseOffset + CGFloat(notchAnimationInspectorExtensionYOffset) - revealTravel
    }

    private var liveSurfaceProgress: CGFloat {
        liveSurfaceReveal
    }

    private var communicationSurfaceProgress: CGFloat {
        guard communicationRevealActive else { return 0 }
        return notchAnimatorActive ? notchAnimatorSurfaceProgress : liveSurfaceProgress
    }

    private var shouldShowCommunicationSurface: Bool {
        communicationSurfaceProgress > 0.001
    }

    private var communicationRows: Int {
        communicationSurfaceProgress >= notchAnimatorFullThreshold ? 2 : 1
    }

    private var communicationSurfaceOverlapBuffer: CGFloat {
        guard unifiedUsesIslandShape else { return 2.0 }
        return showRecordingLayout ? 6.5 : 15.5
    }

    private var communicationSurfaceContentInset: CGFloat {
        guard unifiedUsesIslandShape else { return 0 }
        return showRecordingLayout ? 6.0 : 8.0
    }

    private var unifiedRecordingControlHorizontalInset: CGFloat {
        // Align cancel/stop buttons with the tray dock header edges:
        // left edge of cancel ≈ left edge of "Tray" label,
        // right edge of stop ≈ right edge of "Open" button.
        let dockInset = (totalWidth - communicationDockTargetWidth) / 2 + 10
        if unifiedUsesIslandShape {
            return max(dockInset, islandSurfaceCornerRadius - 2)
        }
        return max(dockInset, max(leftTopOuterRadius, rightTopOuterRadius) + 2)
    }

    private var unifiedRecordingControlTopInset: CGFloat {
        if unifiedUsesIslandShape {
            return max(5, (overlayHeight - 24) / 2)
        }
        return max(7, max(leftTopOuterRadius, rightTopOuterRadius) * 0.45)
    }

    var body: some View {
        // Non-interactive filler fills the panel; actual content overlaid on top.
        // This ensures hover tracking and click handling are confined to the
        // visible content area and don't leak into the surrounding panel region.
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                if notchMinimized {
                    // Minimized nub — tiny pill that restores on hover
                    notchMinimizedNub
                } else {
                VStack(spacing: 0) {
                    if showRecordingLayout {
                        // Unified: wings + optional tray, one continuous background
                        recordingUnit
                            .zIndex(2)

                        if shouldShowCommunicationFramework && recordingCommunicationPresentationVisible {
                            communicationPresentation
                                .padding(.top, 0)
                                .zIndex(1)
                        }
                    } else {
                        // Idle/other: notch wings + optional pill below
                        ZStack(alignment: .top) {
                            idleLayout
                                .frame(width: totalWidth, height: overlayHeight)
                                .background(wingPairSurfaceBackground)

                            // Rest indicator — shows a subtle handle when wings are retracted
                            // so the user can see where to hover. Only on virtual/external
                            // displays — physical notch Macs have the hardware cutout as landmark.
                            if unified && !isHovered && !ns.alwaysVisible && wingRenderWidth < 1 {
                                restIndicator
                                    .transition(.opacity)
                            }
                        }
                        .zIndex(2)

                        belowNotchContent
                            .zIndex(1)
                    }
                }
                .padding(.top, unifiedUsesIslandShape ? 2 : 0)
                .fixedSize()
                .contentShape(hoverContentShape, eoFill: false)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: NotchInteractiveContentSizeKey.self, value: proxy.size)
                    }
                }
                .onHover { hovering in
                    // onHover still fires for expanded state interaction (drag, dismiss gestures).
                    // But initial hover trigger is driven by composer.mouseInHitZone from NotchPanel.
                    if notchAnimatorActive {
                        isHovered = false
                        SurfaceCoordinator.shared.exitHover()
                        return
                    }
                    if !hovering {
                        communicationDismissedByGesture = false
                        recordingDismissedByGesture = false
                        isCommunicationIndicatorHovered = false
                        if notchMinimizedAutoHide {
                            minimizeNotch()
                        }
                    }
                    if communicationDismissedByGesture || recordingDismissedByGesture {
                        isHovered = false
                        SurfaceCoordinator.shared.exitHover()
                        return
                    }
                    // When already expanded, onHover tracks normally.
                    // When at rest, defer to mouseInHitZone (which respects hover zone settings).
                    if isHovered || !hovering {
                        handleHoverChange(hovering)
                    }
                }
                .onChange(of: composer.mouseInHitZone) { _, inZone in
                    // Panel-level hit zone detection — respects hover zone settings.
                    // This is the authoritative trigger for entering hover from rest.
                    if notchAnimatorActive { return }
                    if communicationDismissedByGesture || recordingDismissedByGesture { return }
                    handleHoverChange(inZone)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onEnded { value in
                            let vertical = value.translation.height
                            let horizontal = abs(value.translation.width)

                            // Swipe down: lock notch open (exit auto-hide)
                            if vertical > 16, abs(vertical) > horizontal, notchMinimizedAutoHide {
                                notchMinimizedAutoHide = false
                                return
                            }

                            guard vertical < -16, abs(vertical) > horizontal else { return }

                            // Swipe up: minimize or dismiss
                            if ns.alwaysVisible {
                                minimizeNotch()
                            } else if showRecordingLayout {
                                dismissNotchByGesture()
                            } else {
                                dismissCommunicationByGesture()
                            }
                        }
                )
                }
            }
        .onPreferenceChange(NotchInteractiveContentSizeKey.self) { size in
            composer.updateInteractiveContentSize(size)
        }
        .onChange(of: trayBadgeHoverActive) { _, isActive in
            if isActive && !notchCommunicationDemoEnabled {
                isHovered = false
                SurfaceCoordinator.shared.exitHover()
            }
            logTransition("trayBadgeHoverActive=\(isActive)")
        }
        .onAppear {
            refreshTrayItemsSnapshot()
            observeTrayChanges()
            isRecordingExpanded = false
            showRecordingLayout = recordingIntentActive
            shouldHideRecordingLayoutAfterCollapse = false
            let initialState = desiredExpansionState
            renderPokeOut = pokeOut(for: initialState)
            transitionPhase = .stable(initialState)
            updateRestState(initialState)
            logTransition("onAppear")
        }
        .onChange(of: desiredExpansionState) { oldState, newState in
            updateRestState(newState)
            startTransition(to: newState, reason: "desiredState \(stateLabel(oldState))->\(stateLabel(newState))")
        }
        .onChange(of: targetPokeOut) { oldPoke, newPoke in
            guard oldPoke != newPoke else { return }
            startTransition(
                to: desiredExpansionState,
                reason: "targetPokeOut \(fmt(oldPoke))->\(fmt(newPoke))",
                forceRetarget: true
            )
        }
        .onChange(of: recordingIntentActive) { _, isActive in
            if isActive {
                if notchMinimized { restoreNotch(locked: true) }
                communicationDismissedByGesture = false
                recordingDismissedByGesture = false
                if !notchTrayPreviewWhileRecordingEnabled {
                    isCommunicationIndicatorHovered = false
                    isTrayWingHovered = false
                }
                showRecordingLayout = true
                isRecordingExpanded = false
                shouldHideRecordingLayoutAfterCollapse = false
                logTransition("recordingIntentActive=true")
            } else {
                recordingDismissedByGesture = false
                isRecordingExpanded = false
                shouldHideRecordingLayoutAfterCollapse = desiredExpansionState == .rest
                if !shouldHideRecordingLayoutAfterCollapse {
                    showRecordingLayout = false
                    logTransition("recordingIntentActive=false (immediate hide)")
                }
                logTransition("recordingIntentActive=false")
            }
        }
        .onChange(of: notchAnimationInspectorEnabled) { _, _ in
            if notchAnimatorActive {
                isHovered = false
                SurfaceCoordinator.shared.exitHover()
            }
        }
        .onChange(of: notchAnimationInspectorScrubEnabled) { _, _ in
            if notchAnimatorActive {
                isHovered = false
                SurfaceCoordinator.shared.exitHover()
            }
        }
        .onChange(of: communicationRevealActive) { _, revealed in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                liveSurfaceReveal = revealed ? 1 : 0
            }
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
            logTransition("onDisappear")
        }
    }

    // MARK: - Particle Flow

    /// Physical notch: particles converge inward (symmetry around the hardware obstacle).
    /// Virtual notch (external monitors): single unified stream flowing in the system
    /// layout direction (LTR → .right, RTL → .left) across both wings as one surface.
    private var uniformFlowDirection: ParticleFlowDirection {
        NSApp.userInterfaceLayoutDirection == .rightToLeft ? .left : .right
    }

    // MARK: - Recording Layout (same wing structure as idle, with recording content)

    private var recordingUnit: some View {
        let payload = recordingPayload
        let trayCount = trayItemCount
        // In-body dots: show when placement is "inside" or "both"
        let hasTray = ns.trayDotsInside && trayCount > 0
        let useUnifiedParticles = unified
        let unifiedRecordingControlsVisible = unified && isHovered && payload.state == .listening

        return ZStack {
            HStack(spacing: 0) {
                // LEFT wing — tray badge when items exist, otherwise recording content
                ZStack {
                    if unified {
                        // Unified: plain fill — wing pair shape handles the contour
                        Rectangle()
                            .fill(unified ? overlayColor : particleZoneColor)
                    } else {
                        NotchWingShape(side: .left, cornerRadius: 14, topOuterRadius: leftTopOuterRadius, topInnerRadius: topInnerRadius, innerCurveMode: innerCurveMode)
                            .fill(particleZoneColor)
                    }

                    if hasTray && !unified && payload.state == .idle {
                        // Physical notch: show tray dots in left wing when lifecycle is idle
                        NotchTrayDotBar(count: trayCount)
                    } else if !useUnifiedParticles {
                        // Per-wing particles: converge toward physical notch
                        switch payload.state {
                        case .listening:
                            if unifiedUsesIslandShape {
                                NotchParticles(audioLevel: payload.audioLevel, flowDirection: .right)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                NotchParticles(audioLevel: payload.audioLevel, flowDirection: .right)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipShape(NotchWingShape(side: .left, cornerRadius: 14, topOuterRadius: leftTopOuterRadius, topInnerRadius: topInnerRadius, innerCurveMode: innerCurveMode))
                                    .drawingGroup()
                            }
                        case .transcribing:
                            ProcessingDots(color: .orange)
                                .frame(width: 24, height: 8)
                        case .routing:
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        case .refining:
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.purple)
                        case .idle:
                            EmptyView()
                        }
                    }

                    // Cancel button — leading edge of left wing on hover (physical notch only)
                    if isHovered && payload.state == .listening && !unified {
                        HStack {
                            recordingCancelButton
                            Spacer()
                        }
                        .padding(8)
                    }

                }
                .frame(width: unified ? (totalWidth / 2) : wingRenderWidth, alignment: .trailing)
                .frame(width: unified ? (totalWidth / 2) : visibleLeftWingWidth, alignment: .trailing)
                .clipped()
                .applyTapTarget(enabled: !isHovered || payload.state != .listening) {
                    if unified {
                        ServiceManager.shared.live.toggleRecording()
                    } else if hasTray {
                        openTrayViewerFromNotch()
                    } else {
                        ServiceManager.shared.live.toggleRecording()
                    }
                }

                // CENTER: hidden behind notch (zero on virtual displays — no physical notch to wrap)
                Color.clear
                    .frame(width: unified ? 0 : notchWidth)

                // RIGHT wing — always recording content + hover controls
                ZStack {
                    if unified {
                        Rectangle()
                            .fill(unified ? overlayColor : particleZoneColor)
                    } else {
                        NotchWingShape(side: .right, cornerRadius: 14, topOuterRadius: rightTopOuterRadius, topInnerRadius: topInnerRadius, innerCurveMode: innerCurveMode)
                            .fill(particleZoneColor)
                    }

                    if !useUnifiedParticles {
                        // Per-wing particles: converge toward physical notch
                        switch payload.state {
                        case .listening:
                            if unifiedUsesIslandShape {
                                NotchParticles(audioLevel: payload.audioLevel, flowDirection: .left)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                NotchParticles(audioLevel: payload.audioLevel, flowDirection: .left)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipShape(NotchWingShape(side: .right, cornerRadius: 14, topOuterRadius: rightTopOuterRadius, topInnerRadius: topInnerRadius, innerCurveMode: innerCurveMode))
                                    .drawingGroup()
                            }
                        case .transcribing:
                            ProcessingDots(color: .orange)
                                .frame(width: 24, height: 8)
                        case .routing:
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        case .refining:
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.purple)
                        case .idle:
                            EmptyView()
                        }
                    }

                    // Stop button — trailing edge of right wing on hover (physical notch only)
                    if isHovered && payload.state == .listening && !unified {
                        HStack {
                            Spacer()
                            recordingStopButton
                        }
                        .padding(8)
                    }

                }
                .frame(width: unified ? (totalWidth / 2) : wingRenderWidth, alignment: .leading)
                .frame(width: unified ? (totalWidth / 2) : visibleRightWingWidth, alignment: .leading)
                .clipped()
                .applyTapTarget(enabled: !isHovered || payload.state != .listening) {
                    ServiceManager.shared.live.toggleRecording()
                }
            }

            // Virtual notch: single unified particle stream spanning both wings
            if useUnifiedParticles {
                switch payload.state {
                case .listening:
                    if unifiedUsesIslandShape {
                        NotchParticles(audioLevel: payload.audioLevel, flowDirection: uniformFlowDirection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: islandSurfaceCornerRadius, style: .continuous))
                            .drawingGroup()
                            .allowsHitTesting(false)
                    } else {
                        NotchParticles(audioLevel: payload.audioLevel, flowDirection: uniformFlowDirection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(wingPairClipShape)
                            .drawingGroup()
                            .allowsHitTesting(false)
                    }
                case .transcribing:
                    ProcessingDots(color: .orange)
                        .frame(width: 24, height: 8)
                case .routing:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                case .refining:
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.purple)
                case .idle:
                    EmptyView()
                }
            }

            // Virtual display: center tray dots — hidden when lifecycle indicators are active
            if hasTray && unified && payload.state == .idle {
                NotchTrayDotBar(count: trayCount)
            }

            // Make the hidden center notch span interactive.
            Rectangle()
                .fill(Color.clear)
                .frame(width: unified ? totalWidth : notchWidth, height: overlayHeight)
                .applyTapTarget(enabled: !isHovered || payload.state != .listening) {
                    if unified {
                        ServiceManager.shared.live.toggleRecording()
                    } else if hasTray {
                        openTrayViewerFromNotch()
                    } else {
                        ServiceManager.shared.live.toggleRecording()
                    }
                }

            if unifiedRecordingControlsVisible {
                HStack {
                    recordingCancelButton
                    Spacer()
                    recordingStopButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, unifiedRecordingControlHorizontalInset)
                .padding(.top, unifiedRecordingControlTopInset)
            }
        }
        .frame(width: totalWidth, height: overlayHeight)
        .background(wingPairSurfaceBackground)
        .mask {
            if unifiedUsesIslandShape {
                RoundedRectangle(cornerRadius: islandSurfaceCornerRadius, style: .continuous)
            } else if unified {
                // Notch profile on virtual display — use the wing pair shape (gap=0, outer curves)
                wingPairClipShape
            } else {
                // Physical notch — no mask needed, wings are already shaped
                Rectangle()
            }
        }
    }

    private var recordingStopButton: some View {
        Button {
            ServiceManager.shared.live.toggleRecording()
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(
                        width: unifiedUsesIslandShape ? 24 : 20,
                        height: unifiedUsesIslandShape ? 24 : 20
                    )
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var recordingCancelButton: some View {
        Button {
            ServiceManager.shared.live.toggleRecording()
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(
                        width: unifiedUsesIslandShape ? 24 : 20,
                        height: unifiedUsesIslandShape ? 24 : 20
                    )
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var wingPairClipShape: NotchWingPairSurfaceShape {
        NotchWingPairSurfaceShape(
            pokeOut: wingRenderWidth,
            notchGap: effectiveNotchGap,
            leftTopOuterRadius: leftTopOuterRadius,
            rightTopOuterRadius: rightTopOuterRadius,
            topInnerRadius: topInnerRadius,
            bottomRadius: bottomRadius,
            notchOverlap: notchOverlap,
            minimumNotchOverlap: minimumNotchOverlap,
            innerCurveMode: innerCurveMode,
            debugLoggingEnabled: false,
            debugContext: "clip"
        )
    }

    private var wingPairSurfaceBackground: AnyView {
        if unifiedUsesIslandShape {
            return AnyView(
                RoundedRectangle(cornerRadius: islandSurfaceCornerRadius, style: .continuous)
                    .fill(overlayColor)
                    .frame(width: totalWidth, height: overlayHeight)
            )
        }

        return AnyView(
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: leftOuterShoulder, height: overlayHeight)

                NotchWingPairSurfaceShape(
                    pokeOut: wingRenderWidth,
                    notchGap: effectiveNotchGap,
                    leftTopOuterRadius: leftTopOuterRadius,
                    rightTopOuterRadius: rightTopOuterRadius,
                    topInnerRadius: topInnerRadius,
                    bottomRadius: bottomRadius,
                    notchOverlap: notchOverlap,
                    minimumNotchOverlap: minimumNotchOverlap,
                    innerCurveMode: innerCurveMode,
                    debugLoggingEnabled: notchAggressiveDebugLogging,
                    debugContext: showRecordingLayout ? "recording" : "idle"
                )
                .fill(overlayColor)
                .frame(width: renderedCoreWidth, height: overlayHeight)

                Color.clear
                    .frame(width: rightOuterShoulder, height: overlayHeight)
            }
            .frame(width: renderedTotalWidth, height: overlayHeight)
            .frame(width: totalWidth, height: overlayHeight, alignment: .center)
            .clipped()
            .drawingGroup()
        )
    }

    // MARK: - Below-Notch Content (pills for non-recording intents)

    @ViewBuilder
    private var belowNotchContent: some View {
        switch composer.resolvedIntent {
        case .cameraLoading:
            pillView(icon: "video.fill", text: "loading camera")
                .padding(.top, 4)

        case .screenRecording:
            if case .screenRecording(let startTime) = composer.resolvedPayload {
                ScreenRecordingNotchPillView(
                    startTime: startTime,
                    onStop: {
                        Task { @MainActor in
                            await ScreenRecordingController.shared.stopRecording()
                        }
                    }
                )
                .padding(.top, 4)
            }

        default:
            if shouldShowCommunicationFramework {
                communicationPresentation
                    .padding(.top, 0)
            } else {
                // Invisible click zone for hover detection
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: unified ? totalWidth : notchWidth, height: 8)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var communicationPresentation: some View {
        communicationDock
            .offset(y: communicationDockYOffset)
    }

    private var communicationDock: some View {
        let revealProgress = communicationSurfaceProgress

        return VStack(spacing: 0) {
            if shouldShowCommunicationStrip && communicationStripOpacity > 0.01 {
                if trayItemCount > 0 {
                    Button {
                        openTrayViewerFromNotch()
                    } label: {
                        NotchTrayDotBar(
                            count: trayItemCount,
                            maxDots: max(1, notchTrayIndicatorMaxDots),
                            dotSize: trayIndicatorDotSizeClamped,
                            dotSpacing: trayIndicatorDotSizeClamped + 0.6,
                            horizontalPadding: 6,
                            barHeight: trayIndicatorHeightClamped,
                            fillOpacity: 0.10,
                            borderOpacity: trayIndicatorBorderOpacityClamped,
                            dotOpacity: notchTrayIndicatorShowDots ? 0.92 : 0
                        )
                        .frame(width: trayIndicatorWidthClamped, height: trayIndicatorHeightClamped)
                        .opacity(communicationStripOpacity)
                    }
                    .buttonStyle(.plain)
                    // Use padding instead of offset so hit area moves with the visual
                    .padding(.top, CGFloat(notchTrayIndicatorYOffset))
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if notchAnimatorActive {
                            isCommunicationIndicatorHovered = false
                            return
                        }
                        isCommunicationIndicatorHovered = hovering
                    }
                } else {
                    Button {
                        openTrayViewerFromNotch()
                    } label: {
                        Capsule()
                            .fill(overlayColor)
                            .frame(width: communicationDockWidth, height: 3)
                            .contentShape(Rectangle())
                            .opacity(communicationStripOpacity)
                    }
                    .buttonStyle(.plain)
                }
            }

            if shouldShowCommunicationSurface {
                NotchTrayExtensionSurface(
                    trayItems: trayItems,
                    baselineWidth: communicationDockWidth,
                    rows: communicationRows,
                    bottomCornerRadius: bottomRadius,
                    surfaceColor: overlayColor,
                    extraTopInset: communicationSurfaceContentInset,
                    onOpenTray: {
                        openTrayViewerFromNotch()
                    }
                )
                .scaleEffect(x: 1, y: max(0.01, revealProgress), anchor: .top)
                .opacity(Double(revealProgress))
                .offset(y: -1 - communicationSurfaceOverlapBuffer - ((1 - revealProgress) * notchAnimatorDropDistanceClamped))
                .transition(.opacity)
                .onHover { hovering in
                    if hovering {
                        // Keep tray preview open while mouse is over it
                        idleTrayDismissTask?.cancel()
                        isCommunicationIndicatorHovered = true
                    } else if !showRecordingLayout {
                        isCommunicationIndicatorHovered = false
                    }
                }
            }
        }
        .frame(width: communicationDockWidth, alignment: .top)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    guard vertical < -16, abs(vertical) > horizontal else { return }
                    if showRecordingLayout {
                        dismissNotchByGesture()
                    } else {
                        dismissCommunicationByGesture()
                    }
                }
        )
    }

    // MARK: - Idle Layout (hover detection + click to start recording — same as Agent)

    private struct IdleNotchButton: View {
        let icon: String
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.6))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isHovered ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private var idleRecordTarget: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(isHovered ? 0.7 : 0))
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(.white.opacity(isHovered ? 0.12 : 0))
            )
            .animation(.easeInOut(duration: 0.25), value: isHovered)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var idleTrayIndicator: some View {
        if trayItemCount > 0 && isHovered {
            IdleNotchButton(icon: "tray.full.fill") {
                openTrayViewerFromNotch()
            }
            .onHover { hovering in
                if hovering {
                    idleTrayDismissTask?.cancel()
                    isCommunicationIndicatorHovered = true
                } else {
                    // Delay dismiss so the mouse can travel to the preview surface
                    idleTrayDismissTask?.cancel()
                    idleTrayDismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        isCommunicationIndicatorHovered = false
                    }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var idleCaptureIndicator: some View {
        if isHovered {
            IdleNotchButton(icon: "camera.viewfinder") {
                Task {
                    await captureRegionToTrayFromNotch()
                }
            }
            .transition(.opacity)
        }
    }

    private func captureRegionToTrayFromNotch() async {
        guard let result = await ScreenshotCaptureService.shared.captureStandalone(mode: .region) else {
            return
        }

        let previewID = ScreenshotPreviewPanel.shared.show(
            thumbnail: result.previewImage,
            sourceWidth: result.width,
            sourceHeight: result.height
        )

        guard let item = await ScreenshotTray.shared.addReturningItem(
            data: result.data,
            width: result.width,
            height: result.height,
            mode: .region,
            windowTitle: result.windowTitle,
            appName: result.appName,
            displayName: result.displayName,
            initialThumbnail: result.previewImage
        ) else {
            return
        }

        ScreenshotPreviewPanel.shared.attachFileURL(item.tempURL, to: previewID)
        TrayActionService.shared.persistStandaloneScreenshotToLibrary(item)
    }

    private var idleLayout: some View {
        Group {
            if unified {
                // Virtual display: tray · mic · capture — flanking the center.
                ZStack {
                    Color.clear
                        .frame(width: totalWidth, height: overlayHeight)
                    HStack(spacing: 10) {
                        idleTrayIndicator
                        idleRecordTarget
                        idleCaptureIndicator
                    }
                }
            } else {
                // Physical notch: two wings flanking the camera cutout.
                let hasInsideTray = ns.trayDotsInside && trayItemCount > 0
                ZStack {
                    HStack(spacing: 0) {
                        // Left wing — background pair shape provides the visual fill;
                        // foreground only carries interactive content (no shape fill needed).
                        ZStack {
                            if hasInsideTray && isHovered {
                                // Tray indicator dots in left wing — hover here to pull tray
                                NotchTrayDotBar(count: trayItemCount)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        guard isHovered else {
                                            if !hovering { isTrayWingHovered = false }
                                            return
                                        }
                                        if hovering {
                                            idleTrayDismissTask?.cancel()
                                            isTrayWingHovered = true
                                            isCommunicationIndicatorHovered = true
                                        } else {
                                            idleTrayDismissTask?.cancel()
                                            idleTrayDismissTask = Task { @MainActor in
                                                try? await Task.sleep(for: .milliseconds(320))
                                                guard !Task.isCancelled else { return }
                                                isTrayWingHovered = false
                                                if !showRecordingLayout {
                                                    isCommunicationIndicatorHovered = false
                                                }
                                            }
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(width: wingRenderWidth, alignment: .trailing)
                        .frame(width: visibleLeftWingWidth, alignment: .trailing)

                        Color.clear
                            .frame(width: notchWidth)

                        // Right wing — same: background provides fill, foreground carries content.
                        ZStack {
                            idleRecordTarget
                        }
                        .frame(width: wingRenderWidth, alignment: .leading)
                        .frame(width: visibleRightWingWidth, alignment: .leading)
                        .clipped()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if shouldOpenTrayFromIdleTap {
                openTrayViewerFromNotch()
            } else {
                // Click behind notch starts recording (same as Agent)
                ServiceManager.shared.live.toggleRecording()
            }
        }
    }

    // MARK: - Pill Views

    private func pillView(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Helpers

    private struct RecordingData {
        let state: LiveState
        let audioLevel: Float
        let elapsedTime: TimeInterval
    }

    private var recordingPayload: RecordingData {
        if case .recording(let state, let audioLevel, let elapsedTime) = composer.resolvedPayload {
            return RecordingData(state: state, audioLevel: audioLevel, elapsedTime: elapsedTime)
        }
        return RecordingData(state: .idle, audioLevel: 0, elapsedTime: 0)
    }

    private func dismissCommunicationByGesture() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        communicationDismissedByGesture = true
        isCommunicationIndicatorHovered = false
        isHovered = false
        SurfaceCoordinator.shared.exitHover()
    }

    private func openTrayViewerFromNotch() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        communicationDismissedByGesture = false
        recordingDismissedByGesture = false
        isCommunicationIndicatorHovered = false
        isTrayWingHovered = false
        isHovered = false
        SurfaceCoordinator.shared.exitHover()
        TrayViewer.shared.show()
    }

    private func observeTrayChanges() {
        withObservationTracking {
            _ = ScreenshotTray.shared.items.count
            _ = ClipTray.shared.items.count
            _ = SelectionTray.shared.items.count
        } onChange: {
            Task { @MainActor in
                refreshTrayItemsSnapshot()
                observeTrayChanges()
            }
        }
    }

    private func refreshTrayItemsSnapshot() {
        trayItemsSnapshot = TrayItem.allItems()
    }

    private func dismissNotchByGesture() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        recordingDismissedByGesture = true
        communicationDismissedByGesture = true
        isCommunicationIndicatorHovered = false
        isTrayWingHovered = false
        isHovered = false
        SurfaceCoordinator.shared.exitHover()
    }

    private func handleHoverChange(_ hovering: Bool) {
        let effectiveHover = (trayBadgeHoverActive && !notchCommunicationDemoEnabled) ? false : hovering

        if effectiveHover {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            isHovered = true
            SurfaceCoordinator.shared.enterHover()
        } else {
            hoverExitTask?.cancel()
            hoverExitTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                isHovered = false
                SurfaceCoordinator.shared.exitHover()
            }
        }
    }

    private func updateRestState(_ state: ExpansionState) {
        composer.updateRestState(state == .rest)
    }

    /// Shape for the hover content area.
    /// At rest on idle virtual displays: a small centered rect matching the hover zone settings.
    /// Active below-notch pills need the full content shape so their controls receive clicks.
    /// Otherwise: full rectangle.
    private var hoverContentShape: HoverZoneShape {
        let atRest = !isHovered && !isRecordingExpanded && wingRenderWidth < 1
        if atRest && unified && composer.resolvedIntent == .idle {
            let config = NotchSettings.shared.hoverZoneConfig(for: notchInfo.displayID)
            let w = CGFloat(config.width) + CGFloat(config.paddingX) * 2
            let h = CGFloat(config.height) + CGFloat(config.paddingY) * 2
            return HoverZoneShape(restrictedWidth: w, restrictedHeight: h)
        }
        return HoverZoneShape(restrictedWidth: nil, restrictedHeight: nil)
    }

    // MARK: - Rest Indicator

    /// Subtle handle visible when the notch is at rest (wings fully retracted).
    /// Shows the user where to hover to reveal the notch.
    private var restIndicator: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, unified ? 6 : max(4, overlayHeight - 6))
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }

    // MARK: - Debug Hit Zone

    /// Fixed dotted rectangle showing the hover trigger zone at rest.
    /// Only visible when the notch is idle (not hovered, not expanded).
    /// This is the area where moving the mouse will cause the notch to expand.
    @ViewBuilder
    private var debugHitZoneOverlay: some View {
        let isRest = !isHovered && !isRecordingExpanded && !notchMinimized && wingRenderWidth < 1
        if isRest {
            let config = NotchSettings.shared.hoverZoneConfig(for: notchInfo.displayID)
            let zoneWidth = CGFloat(unified ? config.width : NotchSettings.shared.hoverZoneWidthNotch)
            let zoneHeight = CGFloat(config.height)
            VStack(spacing: 4) {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.cyan.opacity(0.6))
                    .frame(width: zoneWidth, height: zoneHeight)

                Text("\(Int(zoneWidth))×\(Int(zoneHeight))  \(unified ? "virtual" : "notch")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.6))
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Minimize / Restore

    private func minimizeNotch() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            notchMinimized = true
        }
        notchMinimizedAutoHide = false
        isHovered = false
        communicationDismissedByGesture = false
        recordingDismissedByGesture = false
        SurfaceCoordinator.shared.exitHover()
    }

    private func restoreNotch(locked: Bool = false) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            notchMinimized = false
            nubDragOffset = 0
            nubDragAccumulated = 0
        }
        notchMinimizedAutoHide = false
    }

    private var notchMinimizedNub: some View {
        let trayCount = trayItemCount
        let hasTrayItems = trayCount > 0

        return HStack(spacing: 0) {
            if hasTrayItems {
                // Tray dots inside the nub
                NotchTrayDotBar(
                    count: trayCount,
                    maxDots: 4,
                    dotSize: 2.4,
                    dotSpacing: 2.4,
                    horizontalPadding: 6,
                    barHeight: 10,
                    fillOpacity: 0,
                    borderOpacity: 0,
                    dotOpacity: 0.7
                )
            } else {
                // Grip line — visible enough to locate
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(nubProximityHovered ? 0.6 : 0.4))
                    .frame(width: 28, height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(nubProximityHovered ? 0.25 : 0.15), radius: nubProximityHovered ? 6 : 4, y: 1)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(nubProximityHovered ? 0.3 : 0.18),
                            Color.white.opacity(nubProximityHovered ? 0.12 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: nubProximityHovered ? 0.75 : 0.5
                )
        )
        .scaleEffect(nubProximityHovered ? 1.08 : 1.0, anchor: .top)
        .padding(.top, unifiedUsesIslandShape ? 4 : 0)
        .offset(x: nubDragAccumulated + nubDragOffset)
        .contentShape(Capsule().inset(by: -12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                nubProximityHovered = hovering
            }
        }
        .onTapGesture {
            restoreNotch(locked: true)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    nubDragOffset = value.translation.width
                }
                .onEnded { value in
                    nubDragAccumulated += value.translation.width
                    nubDragOffset = 0
                    // Clamp to reasonable range
                    let maxOffset: CGFloat = 300
                    nubDragAccumulated = min(maxOffset, max(-maxOffset, nubDragAccumulated))
                }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top)))
    }

    private func stateLabel(_ state: ExpansionState) -> String {
        switch state {
        case .rest: return "rest"
        case .hover: return "hover"
        case .active: return "active"
        }
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, progress))
        return from + ((to - from) * clamped)
    }

    private func phaseLabel(_ phase: TransitionPhase) -> String {
        switch phase {
        case .stable(let state):
            "stable(\(stateLabel(state)))"
        case .transitioning(let from, let to, let serial):
            "transitioning(\(stateLabel(from))->\(stateLabel(to))#\(serial))"
        }
    }

    private func transitionDurationSeconds(to target: ExpansionState) -> Double {
        target == .rest ? collapseDurationSeconds : expandDurationSeconds
    }

    private func startTransition(
        to target: ExpansionState,
        reason: String,
        forceRetarget: Bool = false
    ) {
        if !forceRetarget {
            switch transitionPhase {
            case .stable(let state) where state == target:
                return
            case .transitioning(_, let to, _) where to == target:
                return
            default:
                break
            }
        }

        transitionTask?.cancel()
        transitionSerial += 1
        let serial = transitionSerial
        let fromState = transitionSourceState
        transitionPhase = .transitioning(from: fromState, to: target, serial: serial)

        if target != .rest, shouldHideRecordingLayoutAfterCollapse {
            shouldHideRecordingLayoutAfterCollapse = false
            if !recordingIntentActive, showRecordingLayout {
                showRecordingLayout = false
                logTransition("cancelCollapseHideForNonRestTarget")
            }
        }

        let duration = transitionDurationSeconds(to: target)
        withAnimation(.easeOut(duration: duration)) {
            renderPokeOut = pokeOut(for: target)
        }

        logTransition(
            "\(reason) begin \(stateLabel(fromState))->\(stateLabel(target)) duration=\(duration.formatted(.number.precision(.fractionLength(2))))"
        )

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            guard case .transitioning(_, let to, let activeSerial) = transitionPhase else { return }
            guard activeSerial == serial else { return }

            transitionPhase = .stable(to)
            logTransition("transitionComplete \(stateLabel(to))")

            if shouldHideRecordingLayoutAfterCollapse, to == .rest, !recordingIntentActive {
                showRecordingLayout = false
                shouldHideRecordingLayoutAfterCollapse = false
                logTransition("recordingLayoutHiddenAfterCollapse")
            }
        }
    }

    private func logTransition(_ reason: String) {
        guard notchAggressiveDebugLogging else { return }
        notchDebugLog.info(
            "[NotchTransition] \(reason) phase=\(phaseLabel(transitionPhase)) desired=\(stateLabel(desiredExpansionState)) transitionTarget=\(stateLabel(transitionTargetState)) hover=\(isHovered) recordingExpanded=\(isRecordingExpanded) showRecordingLayout=\(showRecordingLayout) renderPokeOut=\(fmt(renderPokeOut)) targetPokeOut=\(fmt(targetPokeOut)) wingRenderWidth=\(fmt(wingRenderWidth)) notchWidth=\(fmt(notchWidth)) overlayHeight=\(fmt(overlayHeight)) bottomRadius=\(fmt(bottomRadius)) notchOverlap=\(fmt(notchOverlap)) minOverlap=\(fmt(minimumNotchOverlap))"
        )
    }

    private func fmt(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }
}

struct NotchWingPairSurfaceShape: Shape {
    var pokeOut: CGFloat
    let notchGap: CGFloat
    let leftTopOuterRadius: CGFloat
    let rightTopOuterRadius: CGFloat
    let topInnerRadius: CGFloat
    let bottomRadius: CGFloat
    let notchOverlap: CGFloat
    let minimumNotchOverlap: CGFloat
    let innerCurveMode: NotchInnerCurveMode
    let debugLoggingEnabled: Bool
    let debugContext: String

    var animatableData: CGFloat {
        get { pokeOut }
        set { pokeOut = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let baseWing = max(0, min(pokeOut, w / 2))
        let baseGap = max(0, min(notchGap, w - (baseWing * 2)))
        let coreWidth = (baseWing * 2) + baseGap
        let rawOriginX = max(0, (w - coreWidth) / 2)
        // Keep transition edges pixel-stable to avoid 1px seam flashes while collapsing.
        let originX = snapToPixel(rawOriginX)
        // Match the mastered live-notch geometry from master: preserve a minimum
        // under-notch overlap so the hardware notch bottom corners stay covered
        // throughout the wing animation.
        let desiredOverlap = max(minimumNotchOverlap, notchOverlap)
        let overlap = max(0, min(desiredOverlap, baseGap / 2))

        let wing = baseWing + overlap
        let gap = max(0, baseGap - (overlap * 2))

        let maxTor = min(wing, h) / 2
        let leftTor = max(-maxTor, min(leftTopOuterRadius, maxTor))
        let rightTor = max(-maxTor, min(rightTopOuterRadius, maxTor))
        let br = min(bottomRadius, min(wing, h) / 2)
        let leftIr = max(0, min(topInnerRadius, max(0, wing - abs(leftTor)), h / 2))
        let rightIr = max(0, min(topInnerRadius, max(0, wing - abs(rightTor)), h / 2))

        if debugLoggingEnabled {
            notchDebugLog.info(
                "[NotchGeom:\(debugContext)] rect=(\(fmt(w))x\(fmt(h))) coreWidth=\(fmt(coreWidth)) originX=\(fmt(originX)) rawOriginX=\(fmt(rawOriginX)) poke=\(fmt(pokeOut)) baseWing=\(fmt(baseWing)) baseGap=\(fmt(baseGap)) desiredOverlap=\(fmt(desiredOverlap)) overlap=\(fmt(overlap)) wing=\(fmt(wing)) gap=\(fmt(gap)) torL=\(fmt(leftTor)) torR=\(fmt(rightTor)) br=\(fmt(br)) irL=\(fmt(leftIr)) irR=\(fmt(rightIr))"
            )
        }

        var p = Path()
        addLeftWing(path: &p, wing: wing, height: h, tor: leftTor, br: br, ir: leftIr)
        addRightWing(path: &p, wing: wing, gap: gap, height: h, tor: rightTor, br: br, ir: rightIr)
        if originX > 0 {
            return p.applying(CGAffineTransform(translationX: originX, y: 0))
        }
        return p
    }

    private func fmt(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }

    private func snapToPixel(_ value: CGFloat) -> CGFloat {
        // Menubar notch rendering is effectively Retina-only in practice; half-point
        // snapping aligns to a physical pixel on 2x displays and removes shimmer.
        let pixel: CGFloat = 0.5
        return (value / pixel).rounded() * pixel
    }

    private func addLeftWing(
        path: inout Path,
        wing: CGFloat,
        height: CGFloat,
        tor: CGFloat,
        br: CGFloat,
        ir: CGFloat
    ) {
        let cornerDrop = abs(tor)
        if cornerDrop > 0 {
            let shoulderX = -tor
            path.move(to: CGPoint(x: 0, y: cornerDrop))
            let center = CGPoint(x: shoulderX, y: cornerDrop)
            if tor >= 0 {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(0),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            } else {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(180),
                    endAngle: .degrees(-90),
                    clockwise: false
                )
            }
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
        }

        if ir > 0, innerCurveMode != .hardCorner {
            path.addLine(to: CGPoint(x: wing - ir, y: 0))
            let control: CGPoint = {
                switch innerCurveMode {
                case .canonicalDownward:
                    return CGPoint(x: wing, y: 0)
                case .mirroredUpward:
                    return CGPoint(x: wing - ir, y: ir)
                case .hardCorner:
                    return CGPoint(x: wing, y: 0)
                }
            }()
            path.addQuadCurve(
                to: CGPoint(x: wing, y: ir),
                control: control
            )
        } else {
            path.addLine(to: CGPoint(x: wing, y: 0))
        }

        // Inner bottom-right stays square; outer bottom-left rounds.
        path.addLine(to: CGPoint(x: wing, y: height))
        path.addLine(to: CGPoint(x: br, y: height))
        path.addQuadCurve(to: CGPoint(x: 0, y: height - br), control: CGPoint(x: 0, y: height))
        path.closeSubpath()
    }

    private func addRightWing(
        path: inout Path,
        wing: CGFloat,
        gap: CGFloat,
        height: CGFloat,
        tor: CGFloat,
        br: CGFloat,
        ir: CGFloat
    ) {
        let x0 = wing + gap
        let x1 = x0 + wing

        if ir > 0, innerCurveMode != .hardCorner {
            path.move(to: CGPoint(x: x0, y: ir))
            let control: CGPoint = {
                switch innerCurveMode {
                case .canonicalDownward:
                    return CGPoint(x: x0, y: 0)
                case .mirroredUpward:
                    return CGPoint(x: x0 + ir, y: ir)
                case .hardCorner:
                    return CGPoint(x: x0, y: 0)
                }
            }()
            path.addQuadCurve(
                to: CGPoint(x: x0 + ir, y: 0),
                control: control
            )
        } else {
            path.move(to: CGPoint(x: x0, y: 0))
        }

        let cornerDrop = abs(tor)
        if cornerDrop > 0 {
            let shoulderX = x1 + tor
            path.addLine(to: CGPoint(x: shoulderX, y: 0))
            let center = CGPoint(x: shoulderX, y: cornerDrop)
            if tor >= 0 {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-180),
                    clockwise: true
                )
            } else {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
        } else {
            path.addLine(to: CGPoint(x: x1, y: 0))
        }
        // Outer bottom-right rounds; inner bottom-left stays square.
        path.addLine(to: CGPoint(x: x1, y: height - br))
        path.addQuadCurve(to: CGPoint(x: x1 - br, y: height), control: CGPoint(x: x1, y: height))
        path.addLine(to: CGPoint(x: x0, y: height))
        path.closeSubpath()
    }

    /// Unified shape for virtual displays (gap=0): a single path with outer curves
    /// at both edges and bottom curves, attached to the top edge.
    private func addUnifiedShape(
        path: inout Path,
        totalWidth: CGFloat,
        height: CGFloat,
        leftTor: CGFloat,
        rightTor: CGFloat,
        br: CGFloat
    ) {
        let leftDrop = abs(leftTor)
        let rightDrop = abs(rightTor)

        // The path traces the OUTLINE of the visible shape.
        // Positive tor: concave shoulder curves cut into the top corners,
        // creating the "attached to top edge" notch look.
        // The shape does NOT extend to (0,0) or (totalWidth,0) — those
        // corners are cut away by the shoulder curves.

        // --- Left shoulder ---
        if leftDrop > 0 && leftTor >= 0 {
            // Start at top of left shoulder curve
            path.move(to: CGPoint(x: leftDrop, y: 0))
            // Arc: concave curve from top down to left edge
            path.addArc(
                center: CGPoint(x: leftDrop, y: leftDrop),
                radius: leftDrop,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        } else if leftDrop > 0 {
            // Negative tor: convex bulge at top-left
            path.move(to: CGPoint(x: 0, y: 0))
            path.addArc(
                center: CGPoint(x: 0, y: leftDrop),
                radius: leftDrop,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
        }

        // --- Left edge down ---
        path.addLine(to: CGPoint(x: 0, y: height - br))

        // --- Bottom-left curve ---
        path.addQuadCurve(to: CGPoint(x: br, y: height), control: CGPoint(x: 0, y: height))

        // --- Bottom edge ---
        path.addLine(to: CGPoint(x: totalWidth - br, y: height))

        // --- Bottom-right curve ---
        path.addQuadCurve(to: CGPoint(x: totalWidth, y: height - br), control: CGPoint(x: totalWidth, y: height))

        // --- Right edge up ---
        if rightDrop > 0 && rightTor >= 0 {
            // Up to bottom of right shoulder curve
            path.addLine(to: CGPoint(x: totalWidth, y: rightDrop))
            // Arc: concave curve from right edge up to top
            path.addArc(
                center: CGPoint(x: totalWidth - rightDrop, y: rightDrop),
                radius: rightDrop,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        } else if rightDrop > 0 {
            // Negative tor: convex bulge at top-right
            path.addLine(to: CGPoint(x: totalWidth, y: 0))
            path.addArc(
                center: CGPoint(x: totalWidth, y: rightDrop),
                radius: rightDrop,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: totalWidth, y: 0))
        }

        path.closeSubpath()
    }
}

struct NotchTrayDotBar: View {
    let count: Int
    var maxDots: Int = 5
    var dotSize: CGFloat = 3
    var dotSpacing: CGFloat = 3
    var horizontalPadding: CGFloat = 5
    var barHeight: CGFloat = 8
    var fillOpacity: CGFloat = 0.08
    var borderOpacity: CGFloat = 0.18
    var dotOpacity: CGFloat = 0.88

    private var clampedCount: Int {
        min(max(count, 1), maxDots)
    }

    private var barWidth: CGFloat {
        (CGFloat(clampedCount) * dotSize)
            + (CGFloat(max(0, clampedCount - 1)) * dotSpacing)
            + (horizontalPadding * 2)
    }

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.5)
            )
            .frame(width: barWidth, height: barHeight)
            .overlay {
                HStack(spacing: dotSpacing) {
                    ForEach(0..<clampedCount, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(dotOpacity))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
            .accessibilityLabel("Tray items")
            .accessibilityValue("\(count)")
    }
}

private struct NotchTrayExtensionSurface: View {
    let trayItems: [TrayItem]
    let baselineWidth: CGFloat
    let rows: Int
    let bottomCornerRadius: CGFloat
    let surfaceColor: Color
    let extraTopInset: CGFloat
    let onOpenTray: () -> Void

    private let spacing: CGFloat = 6
    private let horizontalPadding: CGFloat = 10

    private var activeRows: Int {
        max(1, min(2, rows))
    }

    private var clampedWidth: CGFloat {
        max(172, baselineWidth)
    }

    private var contentWidth: CGFloat {
        max(140, clampedWidth - (horizontalPadding * 2))
    }

    private var maxVisibleItems: Int {
        // Fit items to available width: each card needs at least 64pt to look decent
        let minCardWidth: CGFloat = 64
        let maxByWidth = Int((contentWidth + spacing) / (minCardWidth + spacing))
        let maxByMode = 3
        return max(1, min(maxByMode, maxByWidth))
    }

    private var previewItems: [TrayItem] {
        return Array(trayItems.prefix(maxVisibleItems))
    }

    private var previewCardHeight: CGFloat {
        activeRows == 1 ? 60 : 72
    }

    private var previewCardWidth: CGFloat {
        let count = max(1, previewItems.count)
        let available = contentWidth - (CGFloat(max(0, count - 1)) * spacing)
        return max(52, floor(available / CGFloat(count)))
    }

    private func openTray(source: String) {
        notchDebugLog.info("Notch tray open requested from \(source)")
        onOpenTray()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Tray")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(trayItems.count)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )

                Spacer(minLength: 0)

                Button {
                    openTray(source: "header-open-button")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Open")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(minWidth: 60, minHeight: 24)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            if previewItems.isEmpty {
                Button {
                    openTray(source: "empty-state-tap")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Tray is empty")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: spacing) {
                    ForEach(previewItems) { item in
                        DossierCardView(
                            item: item,
                            imageHeight: activeRows == 1 ? 42 : 50,
                            fontSize: activeRows == 1 ? 7 : 7.5
                        )
                        .frame(width: previewCardWidth, height: previewCardHeight)
                        .clipped()
                        .trayDrag(item: item)
                        .onTapGesture {
                            openTray(source: "preview-card")
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .clipped()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 15 + extraTopInset)
        .padding(.bottom, 12)
        .frame(width: clampedWidth)
        .clipped()
        .background(backgroundShape)
    }

    private var backgroundShape: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius,
            topTrailingRadius: 0
        )
            .fill(surfaceColor)
    }
}

private extension View {
    @ViewBuilder
    func applyTapTarget(enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            contentShape(Rectangle())
                .onTapGesture(perform: action)
        } else {
            self
        }
    }
}
