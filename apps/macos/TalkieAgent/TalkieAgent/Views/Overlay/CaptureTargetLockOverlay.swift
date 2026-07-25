//
//  CaptureTargetLockOverlay.swift
//  TalkieAgent
//
//  Transient "Destination Token" confirmation that a screenshot destination
//  is locked. A Talkie-owned routing instrument, not a generic toast.
//

import AppKit
import SwiftUI
import TalkieKit

private let captureTargetOverlayLog = Log(.ui)

/// Geometry and motion tokens from NOTES.md / Destination Token Studio study.
private enum CaptureTargetLockMetrics {
    static let height: CGFloat = 40
    static let bodyHeight: CGFloat = 36
    static let tailHeight: CGFloat = height - bodyHeight
    static let minWidth: CGFloat = 140
    static let maxWidth: CGFloat = 260
    static let cornerRadius: CGFloat = 7
    static let padX: CGFloat = 10
    static let talkieMarkSize: CGFloat = 20
    static let routeWidth: CGFloat = 18
    static let receiverWidth: CGFloat = 7
    static let gapFromInput: CGFloat = 7
    static let edgeWidth: CGFloat = 0.75
    /// Transparent margin around the card so the contact shadow (radius 12, y 6)
    /// renders instead of clipping against the borderless panel edge.
    static let shadowCanvas: CGFloat = 16
    static let enterDuration: CGFloat = 0.15
    static let dwellMilliseconds = 1_000
    static let exitDuration: CGFloat = 0.17
    static let enterRiseY: CGFloat = 2
    static func toastSurfaceOpacity(for tone: LiveGlassTone) -> Double {
        switch tone {
        case .graphite: 0.86
        case .pearl: 0.90
        }
    }

    static func bottomLipOpacity(for tone: LiveGlassTone) -> Double {
        switch tone {
        case .graphite: 0.30
        case .pearl: 0.10
        }
    }

}

@MainActor
final class CaptureTargetLockOverlayController {
    static let shared = CaptureTargetLockOverlayController()

    private var panel: NSPanel?
    private var animationTask: Task<Void, Never>?

    private init() {}

    func showLocked(
        appName: String,
        windowTitle: String?,
        appIcon: NSImage?,
        inputFrame: CGRect?
    ) {
        dismiss()

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // The transient identifies Talkie itself, then names the destination.
            // The target's icon remains unused so the route reads consistently.
            // Parameter retained so call sites stay stable.
            await self.presentLocked(
                appName: appName,
                windowTitle: windowTitle,
                inputFrame: inputFrame
            )
        }
    }

    func dismiss() {
        animationTask?.cancel()
        animationTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func dockingPoint(near sourcePoint: NSPoint?) -> NSPoint {
        let screen = sourcePoint.flatMap { point in
            NSScreen.screens.first(where: { $0.frame.contains(point) })
        }
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        return overlayAnchor(on: screen)
    }

    // MARK: - Presentation

    private func presentLocked(
        appName: String,
        windowTitle: String?,
        inputFrame: CGRect?
    ) async {
        let location = resolvedLocation(for: inputFrame)
        let cardSize = CGSize(
            width: contentWidth(appName: appName),
            height: CaptureTargetLockMetrics.height
        )
        // The panel is a transparent canvas one shadow-margin larger than the card
        // on every side, so the contact shadow renders in full.
        let canvas = CaptureTargetLockMetrics.shadowCanvas
        let canvasSize = CGSize(
            width: cardSize.width + canvas * 2,
            height: cardSize.height + canvas * 2
        )
        // Clamped card origin — the *visible* card sits exactly `gapFromInput`
        // above the input. The panel is offset back by the margin.
        let cardOrigin = cardOrigin(
            above: location.inputFrame,
            cardSize: cardSize,
            on: location.screen
        )
        let panelOrigin = CGPoint(x: cardOrigin.x - canvas, y: cardOrigin.y - canvas)
        // Tone samples the card's own region, not the transparent canvas.
        let sampleRect = CGRect(origin: cardOrigin, size: cardSize)

        // One stable tone from the toast's own destination region. No multi-sample
        // hysteresis and no mid-dwell flip — that settling path stays on the badge.
        let tone = await resolveStableTone(for: sampleRect)
        guard !Task.isCancelled else { return }

        let hostingView = NSHostingView(
            rootView: CaptureTargetLockView(
                appName: appName,
                windowTitle: windowTitle,
                tone: tone,
                cardWidth: cardSize.width,
                canvasSize: canvasSize
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: canvasSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.setFrameOrigin(panelOrigin)
        panel.orderFrontRegardless()
        self.panel = panel

        let announcement = accessibilityAnnouncement(appName: appName, windowTitle: windowTitle)
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )

        // Single opacity timeline on the panel. SwiftUI only owns the optional
        // enter rise (skipped under Reduce Motion).
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = CaptureTargetLockMetrics.enterDuration
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()

        captureTargetOverlayLog.info(
            "Capture target lock overlay shown",
            detail: "app=\(appName) display=\(location.screen.safeDisplayName) tone=\(tone) width=\(Int(cardSize.width))"
        )

        let enterMs = Int(CaptureTargetLockMetrics.enterDuration * 1_000)
        let exitMs = Int(CaptureTargetLockMetrics.exitDuration * 1_000)
        try? await Task.sleep(for: .milliseconds(enterMs + CaptureTargetLockMetrics.dwellMilliseconds))
        guard !Task.isCancelled, panel === self.panel else { return }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = CaptureTargetLockMetrics.exitDuration
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().alphaValue = 0
        NSAnimationContext.endGrouping()

        try? await Task.sleep(for: .milliseconds(exitMs))
        guard !Task.isCancelled, panel === self.panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        self.animationTask = nil
    }

    /// Hugs the app name plus Talkie's route furniture, then clamps to 140…260.
    private func contentWidth(appName: String) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        let titleWidth = (appName as NSString).size(withAttributes: [
            .font: titleFont,
            .kern: -0.10
        ]).width
        let fixedChrome = CaptureTargetLockMetrics.padX * 2
            + CaptureTargetLockMetrics.talkieMarkSize
            + 7
            + CaptureTargetLockMetrics.routeWidth
            + 8
            + 8
            + CaptureTargetLockMetrics.receiverWidth
        let total = ceil(titleWidth + fixedChrome)
        return min(
            CaptureTargetLockMetrics.maxWidth,
            max(CaptureTargetLockMetrics.minWidth, total)
        )
    }

    /// Picks graphite over light content and pearl over dark content.
    /// Mixed / mid-luma holds the system appearance fallback — no shared
    /// `LiveGlassTone` expansion for a short-lived toast.
    private func resolveStableTone(for screenRect: CGRect) async -> LiveGlassTone {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return .graphite
        }

        guard let brightness = await WallpaperLuminanceSampler.sampleBrightness(
            for: screenRect,
            excludingWindowIDs: []
        ) else {
            return ScreenAwareOverlayAppearance.fallbackTone()
        }

        if brightness >= 0.62 {
            return .graphite
        }
        if brightness <= 0.45 {
            return .pearl
        }
        return ScreenAwareOverlayAppearance.fallbackTone()
    }

    private func accessibilityAnnouncement(appName: String, windowTitle: String?) -> String {
        if let windowTitle, !windowTitle.isEmpty {
            return "Capture target locked, \(appName), \(windowTitle)"
        }
        return "Capture target locked, \(appName)"
    }

    // MARK: - Placement

    private struct OverlayLocation {
        let screen: NSScreen
        let inputFrame: CGRect?
    }

    private func resolvedLocation(for inputFrame: CGRect?) -> OverlayLocation {
        let resolvedInput = inputFrame.flatMap(convertAccessibilityFrame)
        let screen = resolvedInput?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        return OverlayLocation(screen: screen, inputFrame: resolvedInput?.frame)
    }

    /// Origin of the *visible card*. Its bottom sits `gapFromInput` above the
    /// input top (AppKit y-up); clamping keeps the card — not the transparent
    /// canvas — inside the screen inset.
    private func cardOrigin(above inputFrame: CGRect?, cardSize: CGSize, on screen: NSScreen) -> CGPoint {
        let insetBounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let proposed: CGPoint
        if let inputFrame {
            proposed = CGPoint(
                x: inputFrame.midX - cardSize.width / 2,
                y: inputFrame.maxY + CaptureTargetLockMetrics.gapFromInput
            )
        } else {
            proposed = CGPoint(
                x: screen.visibleFrame.midX - cardSize.width / 2,
                y: screen.visibleFrame.midY - cardSize.height / 2
            )
        }
        return CGPoint(
            x: min(max(proposed.x, insetBounds.minX), insetBounds.maxX - cardSize.width),
            y: min(max(proposed.y, insetBounds.minY), insetBounds.maxY - cardSize.height)
        )
    }

    private func convertAccessibilityFrame(_ accessibilityFrame: CGRect) -> (screen: NSScreen, frame: CGRect)? {
        let center = accessibilityFrame.center

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let quartzBounds = CGDisplayBounds(displayID)
            guard quartzBounds.contains(center) else { continue }

            let converted = CGRect(
                x: screen.frame.minX + accessibilityFrame.minX - quartzBounds.minX,
                y: screen.frame.maxY - (accessibilityFrame.maxY - quartzBounds.minY),
                width: accessibilityFrame.width,
                height: accessibilityFrame.height
            )
            return (screen, converted)
        }

        return nil
    }

    private func overlayAnchor(on screen: NSScreen) -> CGPoint {
        let settings = LiveSettings.shared
        let placementFrame = screen.overlayPlacementFrame()

        if settings.pillEnabled {
            return settings.pillPlacement.screenAnchorPoint(in: placementFrame)
        }
        if settings.notchOverlayEnabled,
           screen == NSScreen.main,
           NotchInfo.detectCached().hasNotch {
            return CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 12)
        }
        if settings.effectiveOverlayStyle.showsTopOverlay {
            return settings.overlayPlacement.screenAnchorPoint(in: placementFrame)
        }
        return CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 12)
    }
}

// MARK: - View

/// Talkie-owned destination token. The app name stays primary while the fused
/// Talkie mark, route trace, receiver bracket, and input pointer explain the event.
private struct CaptureTargetLockView: View {
    let appName: String
    let windowTitle: String?
    let tone: LiveGlassTone
    let cardWidth: CGFloat
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var lockProgress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            lockPlate(tone: tone)

            HStack(spacing: 0) {
                talkieMark

                Spacer().frame(width: 7)

                DestinationRouteTrace(
                    progress: lockProgress,
                    startColor: ScopeAmber.solid,
                    endColor: tone.lockAccent
                )
                .frame(
                    width: CaptureTargetLockMetrics.routeWidth,
                    height: 10
                )

                Spacer().frame(width: 8)

                Text(appName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.10)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(tone.primaryText.opacity(0.98))
                    .shadow(color: textDepthColor, radius: 0, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(width: 8)

                DestinationReceiverBracket()
                    .trim(from: 0, to: receiverProgress)
                    .stroke(
                        tone.lockAccent,
                        style: StrokeStyle(lineWidth: 1.25, lineCap: .square, lineJoin: .miter)
                    )
                    .frame(
                        width: CaptureTargetLockMetrics.receiverWidth,
                        height: 17
                    )
                    .shadow(color: tone.lockAccent.opacity(0.24), radius: 3)
            }
            .padding(.horizontal, CaptureTargetLockMetrics.padX)
            .frame(width: cardWidth, height: CaptureTargetLockMetrics.bodyHeight)

            Circle()
                .fill(tone.lockAccent)
                .frame(width: 3, height: 3)
                .shadow(color: tone.lockAccent.opacity(0.30), radius: 3)
                .offset(y: CaptureTargetLockMetrics.height - 3)
                .opacity(receiverProgress)
        }
            .frame(width: cardWidth, height: CaptureTargetLockMetrics.height)
            // Panel owns opacity enter/exit. View only rises 2→0 when motion is allowed.
            .offset(y: isPresented || reduceMotion ? 0 : -CaptureTargetLockMetrics.enterRiseY)
            .environment(\.colorScheme, tone.colorScheme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
            // Center the card inside the transparent shadow canvas so the contact
            // shadow renders in full instead of clipping at the panel edge.
            .frame(width: canvasSize.width, height: canvasSize.height)
            .onAppear {
                guard !reduceMotion else {
                    isPresented = true
                    lockProgress = 1
                    return
                }
                withAnimation(.easeOut(duration: CaptureTargetLockMetrics.enterDuration)) {
                    isPresented = true
                }
                withAnimation(.timingCurve(0.22, 0.72, 0.24, 1, duration: 0.46)) {
                    lockProgress = 1
                }
            }
    }

    private var talkieMark: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.black.opacity(0.92))
            .padding(5)
            .frame(
                width: CaptureTargetLockMetrics.talkieMarkSize,
                height: CaptureTargetLockMetrics.talkieMarkSize
            )
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.97))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.75)
                    }
            }
            .shadow(color: ScopeAmber.glow, radius: 5)
    }

    private var receiverProgress: CGFloat {
        min(1, max(0, (lockProgress - 0.46) / 0.54))
    }

    /// Screen-aware instrument material in a shape that physically points at the
    /// selected input. Warm Talkie routing and mint destination state sit above it.
    @ViewBuilder
    private func lockPlate(tone: LiveGlassTone) -> some View {
        let radius = CaptureTargetLockMetrics.cornerRadius
        CaptureDestinationTokenShape(
            cornerRadius: radius,
            tailHeight: CaptureTargetLockMetrics.tailHeight
        )
            .fill(.ultraThinMaterial)
            .overlay {
                CaptureDestinationTokenShape(
                    cornerRadius: radius,
                    tailHeight: CaptureTargetLockMetrics.tailHeight
                )
                    .fill(tone.surface.opacity(CaptureTargetLockMetrics.toastSurfaceOpacity(for: tone)))
            }
            .overlay {
                LinearGradient(
                    colors: [tone.highlight.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.45)
                )
                .clipShape(
                    CaptureDestinationTokenShape(
                        cornerRadius: radius,
                        tailHeight: CaptureTargetLockMetrics.tailHeight
                    )
                )
            }
            .overlay {
                CaptureDestinationTokenShape(
                    cornerRadius: radius,
                    tailHeight: CaptureTargetLockMetrics.tailHeight
                )
                    .strokeBorder(tone.edge, lineWidth: CaptureTargetLockMetrics.edgeWidth)
            }
            .overlay {
                CaptureDestinationTokenShape(
                    cornerRadius: radius,
                    tailHeight: CaptureTargetLockMetrics.tailHeight
                )
                    .strokeBorder(
                        LinearGradient(
                            colors: [tone.highlight.opacity(0.72), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .overlay {
                CaptureDestinationTokenShape(
                    cornerRadius: radius,
                    tailHeight: CaptureTargetLockMetrics.tailHeight
                )
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.black.opacity(
                                    CaptureTargetLockMetrics.bottomLipOpacity(for: tone)
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.13),
                radius: 12,
                x: 0,
                y: 6
            )
            .shadow(color: Color.black.opacity(0.20), radius: 2, x: 0, y: 1)
    }

    private var textDepthColor: Color {
        switch tone {
        case .graphite: Color.black.opacity(0.40)
        case .pearl: Color.white.opacity(0.55)
        }
    }

    private var accessibilityLabelText: String {
        if let windowTitle, !windowTitle.isEmpty {
            return "Capture target locked, \(appName), \(windowTitle)"
        }
        return "Capture target locked, \(appName)"
    }
}

private struct CaptureDestinationTokenShape: InsettableShape {
    let cornerRadius: CGFloat
    let tailHeight: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let bodyHeight = max(0, insetRect.height - tailHeight)
        let bodyRect = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.width,
            height: bodyHeight
        )
        var path = Path(
            roundedRect: bodyRect,
            cornerRadius: max(0, cornerRadius - insetAmount),
            style: .continuous
        )
        var tail = Path()
        tail.move(to: CGPoint(x: insetRect.midX - 5, y: bodyRect.maxY - 0.5))
        tail.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.maxY))
        tail.addLine(to: CGPoint(x: insetRect.midX + 5, y: bodyRect.maxY - 0.5))
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }

    func inset(by amount: CGFloat) -> CaptureDestinationTokenShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct DestinationReceiverBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

private struct DestinationRouteTrace: View {
    let progress: CGFloat
    let startColor: Color
    let endColor: Color

    var body: some View {
        GeometryReader { proxy in
            let lineY = proxy.size.height / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(startColor.opacity(0.20))
                    .frame(height: 1)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(1, proxy.size.width * progress), height: 1)

                Circle()
                    .fill(progress < 0.88 ? startColor : endColor)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(
                        color: (progress < 0.88 ? startColor : endColor).opacity(0.38),
                        radius: 3
                    )
                    .offset(
                        x: max(0, (proxy.size.width - 3.5) * progress),
                        y: lineY - 1.75
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
