//
//  NotchOverlay.swift
//  TalkieAgent
//
//  Dynamic Island-style overlay that EXTENDS FROM the notch itself.
//  Positioned at the very top of the screen, appearing to grow out of the notch.
//

import SwiftUI
import AppKit
import TalkieKit
import Combine

private let notchParticleFrameInterval: TimeInterval = 1.0 / 30.0

// MARK: - Notch Detection

struct NotchInfo {
    static let defaultMenuBarHeight: CGFloat = 24
    static let defaultNotchWidth: CGFloat = 180

    /// Cached default-screen detection for hot paths (every recording state
    /// transition runs it). Invalidated when screen parameters change.
    @MainActor private static var cachedDetection: NotchInfo?
    @MainActor private static var screenObserverInstalled = false

    @MainActor
    static func detectCached() -> NotchInfo {
        if !screenObserverInstalled {
            screenObserverInstalled = true
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    cachedDetection = nil
                }
            }
        }

        if let cachedDetection { return cachedDetection }
        let info = detect()
        cachedDetection = info
        return info
    }

    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat  // Height of menu bar / notch area
    let screenFrame: CGRect
    let screenCenter: CGFloat  // X center of screen

    static func detect(for screen: NSScreen? = preferredScreen()) -> NotchInfo {
        guard let screen = screen else {
            return NotchInfo(
                hasNotch: false,
                notchWidth: 0,
                notchHeight: defaultMenuBarHeight,
                screenFrame: .zero,
                screenCenter: 0
            )
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let resolvedDisplayID = displayID(for: screen) ?? 0

        // Menu bar height (includes notch on notched displays)
        // Notched MacBooks: ~37pt, Non-notched: ~24pt
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        var hasNotch = false
        var notchWidth: CGFloat = 0
        var notchCenter: CGFloat = screenFrame.midX

        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea,
               left.width > 0,
               right.width > 0 {
                var leftMaxX = left.maxX
                var rightMinX = right.minX
                let rawCenter = (leftMaxX + rightMinX) / 2

                if abs(rawCenter - screenFrame.midX) > (screenFrame.width / 2) {
                    leftMaxX += screenFrame.minX
                    rightMinX += screenFrame.minX
                }

                let measuredWidth = rightMinX - leftMaxX
                if measuredWidth > 80, measuredWidth < (screenFrame.width * 0.55) {
                    hasNotch = true
                    notchWidth = measuredWidth
                    notchCenter = (leftMaxX + rightMinX) / 2
                }
            }
        }

        if !hasNotch, CGDisplayIsBuiltin(resolvedDisplayID) != 0, menuBarHeight > 30 {
            hasNotch = true
            notchWidth = defaultNotchWidth
            notchCenter = screenFrame.midX
        }

        return NotchInfo(
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: max(menuBarHeight, defaultMenuBarHeight),
            screenFrame: screenFrame,
            screenCenter: notchCenter
        )
    }

    static func preferredScreen(startingWith screen: NSScreen? = NSScreen.main) -> NSScreen? {
        let orderedScreens = orderedScreens(startingWith: screen)
        return orderedScreens.first(where: { detect(for: $0).hasNotch }) ?? orderedScreens.first
    }

    private static func orderedScreens(startingWith preferred: NSScreen?) -> [NSScreen] {
        let allScreens = NSScreen.screens
        guard let preferred else { return allScreens }
        let preferredID = displayID(for: preferred)

        return [preferred] + allScreens.filter { candidate in
            displayID(for: candidate) != preferredID
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

// MARK: - Notch Style

enum NotchOverlayStyle: String, CaseIterable {
    case asymmetric  // Particles left, timer right
    case symmetric   // Particles both sides, timer on right
    case minimal     // Particles both sides, single pulsating line below notch (no timer)
}

// MARK: - CGEventTap Callback (must be global C-style function)

/// Callback for intercepting keyboard events - consumes Right Option + . and Right Option + /
private func notchKeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Pass through if not a key event
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    // Get controller from refcon
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<NotchOverlayController>.fromOpaque(refcon).takeUnretainedValue()

    // Only intercept when actively listening (thread-safe check)
    guard controller.isListeningForShortcuts else {
        return Unmanaged.passUnretained(event)
    }

    // Check for Right Option modifier (device-specific flag)
    let flags = event.flags.rawValue
    let rightOptionMask: UInt64 = 0x00000040
    guard (flags & rightOptionMask) != 0 else {
        return Unmanaged.passUnretained(event)
    }

    // Check key code
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    switch keyCode {
    case 47:  // Right Option + . (period) - cancel recording
        Task { @MainActor in
            controller.requestCancel()
        }
        return nil  // Consume the event

    case 44:  // Right Option + / (slash) - stop and capture
        Task { @MainActor in
            controller.requestStop()
        }
        return nil  // Consume the event

    default:
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Notch Overlay Controller

@MainActor
final class NotchOverlayController: ObservableObject {
    static let shared = NotchOverlayController()

    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?
    private var isHideAnimating: Bool = false

    // Thread-safe flag for keyboard shortcut callback (can be read from any thread)
    private nonisolated(unsafe) let shortcutsLock = NSLock()
    private nonisolated(unsafe) var _isListeningForShortcuts: Bool = false
    nonisolated var isListeningForShortcuts: Bool {
        get { shortcutsLock.withLock { _isListeningForShortcuts } }
        set { shortcutsLock.withLock { _isListeningForShortcuts = newValue } }
    }

    // State
    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var isExpanded: Bool = false
    @Published var captureIntent: String = "Paste"
    @Published var style: NotchOverlayStyle = .minimal  // Default to minimal
    @Published var isScreenRecordingActive: Bool = false
    @Published var screenRecordingElapsedTime: TimeInterval = 0

    // Notch info
    @Published var notchInfo: NotchInfo = NotchInfo(hasNotch: false, notchWidth: 0, notchHeight: 24, screenFrame: .zero, screenCenter: 0)

    private var recordingStartTime: Date?
    private var screenRecordingStartTime: Date?
    private var timer: Timer?

    private init() {
        // Detect notch on init
        notchInfo = NotchInfo.detect()

        // Listen for screen changes (store observer for cleanup)
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.notchInfo = NotchInfo.detect()
            if self.window != nil {
                self.updateWindowPosition()
            }
        }

        // Observe audio level (throttled)
        AudioLevelMonitor.shared.$level
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)
    }

    deinit {
        // Clean up notification observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Clean up cancellables
        cancellables.removeAll()
    }

    // MARK: - Keyboard Shortcuts for Quick Stop (CGEventTap to consume keys)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private func startKeyMonitoring() {
        guard eventTap == nil else { return }

        // Event mask for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Store weak reference to self for the callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: notchKeyEventCallback,
            userInfo: refcon
        ) else {
            AgentConsole.info("[NotchOverlay] Failed to create event tap - check accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopKeyMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
    }

    // MARK: - Window Management

    func show() {
        // Only show on notched displays for now
        notchInfo = NotchInfo.detect()
        guard notchInfo.hasNotch else { return }

        // Prevent race with hide animation
        guard window == nil && !isHideAnimating else {
            window?.orderFront(nil)
            return
        }

        let overlayView = NotchOverlayView()
        let hostingView = NSHostingView(rootView: overlayView.environmentObject(self))

        // Size: wider than notch (max expanded state), height = notch + click zone below
        let initialSize = NSSize(width: 300, height: notchInfo.notchHeight + 8)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Use screenSaver level to appear ABOVE the menu bar, in the notch area
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false  // No shadow - blend with notch
        panel.ignoresMouseEvents = false

        // Position AT the notch - top of screen, centered
        updateWindowPosition(panel: panel)

        // Animate: scale up from notch
        panel.alphaValue = 0
        panel.orderFront(nil)

        // Animate in quickly (configurable via NotchTuning)
        let animDuration = NotchTuning.shared.showAnimationDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.window = panel
        ensureTimer()
    }

    func hide() {
        stopTimer()
        isListeningForShortcuts = false
        stopKeyMonitoring()
        recordingStartTime = nil
        screenRecordingStartTime = nil
        elapsedTime = 0
        screenRecordingElapsedTime = 0

        guard let panel = window else { return }
        guard !isHideAnimating else { return }

        isHideAnimating = true

        // Animate out quickly (configurable via NotchTuning)
        let animDuration = NotchTuning.shared.showAnimationDuration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.isHideAnimating = false
        })
    }

    private func updateWindowPosition(panel: NSPanel? = nil) {
        let targetPanel = panel ?? window
        guard let panel = targetPanel else { return }

        notchInfo = NotchInfo.detect()

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        // Center horizontally behind the notch
        let x = notchInfo.screenCenter - panelWidth / 2
        // Flush with the very top of the screen
        let y = notchInfo.screenFrame.maxY - panelHeight

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Initialization

    func initialize() {
        // Show the overlay immediately for hover detection
        // This should be called at app startup
        notchInfo = NotchInfo.detect()
        if notchInfo.hasNotch {
            show()
        }
    }

    // MARK: - State Updates

    func updateState(_ state: LiveState) {
        let previousState = self.state
        self.state = state

        // Always show the notch overlay (hover detection via SwiftUI onHover)
        show()

        if state == .listening {
            if previousState != .listening {
                recordingStartTime = Date()
                elapsedTime = 0
                ensureTimer()
            }
            if !isListeningForShortcuts {
                isListeningForShortcuts = true
                startKeyMonitoring()  // Enable Right Option + . / shortcuts
            }
        } else if isListeningForShortcuts {
            isListeningForShortcuts = false
            stopKeyMonitoring()
        }

        // Entering idle state
        if state == .idle && previousState != .idle {
            recordingStartTime = nil
            elapsedTime = 0
            stopTimerIfIdle()
        }

        // Expand during active recording, collapse during processing
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = (state == .listening || isScreenRecordingActive)
        }
    }

    func activateScreenRecording(startedAt: Date) {
        screenRecordingStartTime = startedAt
        screenRecordingElapsedTime = max(0, Date().timeIntervalSince(startedAt))
        isScreenRecordingActive = true
        show()
        ensureTimer()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = true
        }
    }

    func deactivateScreenRecording() {
        isScreenRecordingActive = false
        screenRecordingStartTime = nil
        screenRecordingElapsedTime = 0
        stopTimerIfIdle()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = (state == .listening)
        }
    }

    // MARK: - Timer

    private func ensureTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let start = self.recordingStartTime {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
                if let start = self.screenRecordingStartTime {
                    self.screenRecordingElapsedTime = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopTimerIfIdle() {
        if recordingStartTime == nil && screenRecordingStartTime == nil {
            stopTimer()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStopScreenRecording: (() -> Void)?

    func requestStop() {
        onStop?()
    }

    func requestCancel() {
        onCancel?()
    }

    func requestStopScreenRecording() {
        onStopScreenRecording?()
    }
}

// MARK: - Notch Overlay View

struct NotchOverlayView: View {
    @EnvironmentObject var controller: NotchOverlayController
    @ObservedObject private var tuning = NotchTuning.shared
    @State private var isHovered: Bool = false

    // Layout constants
    private let cornerRadius: CGFloat = 12
    private let maxWindowWidth: CGFloat = 300    // Fixed window width for centering

    // Use detected notch width (slightly smaller to hide behind notch)
    private var notchWidth: CGFloat {
        max(controller.notchInfo.notchWidth - 4, 172)  // Slightly narrower, but show more wings
    }

    // Three-tier expansion states
    private enum ExpansionState: Equatable {
        case rest       // Hidden behind notch
        case hover      // Thin expansion with pulsing lines
        case active     // Full expansion with particles/indicators
    }

    private var isScreenRecordingVisible: Bool {
        controller.state == .idle && controller.isScreenRecordingActive
    }

    private var hasActiveIntent: Bool {
        controller.state != .idle || controller.isScreenRecordingActive
    }

    private var expansionState: ExpansionState {
        if hasActiveIntent {
            return .active  // Recording/transcribing/routing/screen recording
        } else if isHovered {
            return .hover   // Hovering over notch area
        } else {
            return .rest    // Idle, not hovering
        }
    }

    // Dynamic dimensions based on state
    private var pokeOutAmount: CGFloat {
        switch expansionState {
        case .rest:
            return 0  // Completely hidden behind notch
        case .hover:
            return 25 // Visible expansion for hover - enough to see the pulsing lines
        case .active:
            return 40 // Full expansion for recording
        }
    }

    // Legacy compatibility
    private var isExpanded: Bool {
        expansionState != .rest
    }

    private var totalWidth: CGFloat { notchWidth + (pokeOutAmount * 2) }

    // Clickable width - narrower at rest to avoid catching menu bar clicks
    private var clickableWidth: CGFloat {
        switch expansionState {
        case .rest:
            return 100  // Very narrow - only center of notch is clickable
        case .hover:
            return totalWidth - 20  // Slightly narrower than visual
        case .active:
            return totalWidth  // Full width when recording
        }
    }

    // Dynamic height - smaller when at rest to hide completely behind notch
    private var overlayHeight: CGFloat {
        switch expansionState {
        case .rest:
            return controller.notchInfo.notchHeight - 3  // Fully hidden behind notch
        case .hover, .active:
            return controller.notchInfo.notchHeight - 1  // Visible, aligned with notch bottom
        }
    }

    // Dark overlay that blends with notch
    private let overlayColor = Color(white: 0.05)

    // Extra click zone below the notch
    private let clickZoneBelow: CGFloat = 8

    // Slightly darker zone for particles
    private let particleZoneColor = Color(white: 0.03)

    var body: some View {
        // Fixed-width container to ensure centering
        VStack(spacing: 0) {
            // Main notch-aligned content
            Group {
                switch tuning.style {
                case .asymmetric:
                    asymmetricLayout
                case .symmetric:
                    symmetricLayout
                case .minimal:
                    minimalLayout
                }
            }
            // Dynamic height - hidden at rest, visible when expanded
            .frame(width: totalWidth, height: overlayHeight)
            .background(
                // Notch-matching shape with subtle tint
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: 0
                )
                .fill(overlayColor)
            )

            // Centered status line below the notch (for minimal style - shows for active states)
            if tuning.style == .minimal && expansionState == .active {
                centeredStatusLine
                    .padding(.top, 3)
            } else {
                // Invisible click zone below the notch
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: notchWidth, height: clickZoneBelow)
                    .contentShape(Rectangle())
            }
        }
        .frame(width: maxWindowWidth)  // Center within fixed window width
        // Smooth ease-out animation - fast start, smooth deceleration
        .animation(.easeOut(duration: 0.2), value: pokeOutAmount)
        .animation(.easeOut(duration: 0.2), value: overlayHeight)
        // Disable hit-testing on the full container - let the overlay handle it
        .allowsHitTesting(false)
        .brightness(isHovered ? 0.05 : 0)  // Subtle brightening on hover
        // Overlay a hit-testing layer - narrow at rest, expands when active
        .overlay(alignment: .top) {
            notchHitLayer
                .frame(width: clickableWidth, height: overlayHeight + clickZoneBelow)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }

    @ViewBuilder
    private var notchHitLayer: some View {
        if isScreenRecordingVisible {
            notchHitButton(action: { controller.requestStopScreenRecording() })
                .help("Stop screen recording")
        } else {
            switch controller.state {
            case .listening:
                HStack(spacing: 0) {
                    notchHitButton(action: { controller.requestCancel() })
                        .help("Cancel recording")
                    notchHitButton(action: { controller.requestStop() })
                        .help("Stop and send")
                }
            case .idle:
                notchHitButton(action: { controller.requestStop() })
                    .help("Start recording")
            case .transcribing, .routing, .refining:
                Color.clear
                    .contentShape(Rectangle())
            }
        }
    }

    private func notchHitButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Asymmetric Layout (particles left, timer right)

    private var asymmetricLayout: some View {
        HStack(spacing: 0) {
            // LEFT poke-out
            leftContent
                .frame(width: pokeOutAmount)

            // CENTER: hidden behind notch (fixed width)
            Color.clear
                .frame(width: notchWidth)

            // RIGHT poke-out
            rightContent
                .frame(width: pokeOutAmount)
        }
    }

    // MARK: - Symmetric Layout (particles both sides, centered indicator)

    private var symmetricLayout: some View {
        HStack(spacing: 0) {
            // LEFT poke-out: particles (mirrored)
            ZStack {
                if isExpanded {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 0
                    )
                    .fill(particleZoneColor)
                    .padding(.trailing, 4)
                }

                if isScreenRecordingVisible {
                    screenRecordingBadge
                } else if controller.state == .listening {
                    // Particles flowing RIGHT (toward notch)
                    NotchParticles(audioLevel: controller.audioLevel, flowDirection: .right)
                        .frame(width: 45, height: 20)
                } else if isExpanded {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: pokeOutAmount)

            // CENTER: hidden behind notch (fixed width)
            Color.clear
                .frame(width: notchWidth)

            // RIGHT poke-out: particles (mirrored) + timer overlay
            ZStack {
                if isExpanded {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 0
                    )
                    .fill(particleZoneColor)
                    .padding(.leading, 4)
                }

                if isScreenRecordingVisible {
                    if isHovered {
                        screenRecordingStopGlyph
                    } else {
                        Text(formatTime(controller.screenRecordingElapsedTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                } else if controller.state == .listening {
                    // Particles flowing LEFT (toward notch)
                    NotchParticles(audioLevel: controller.audioLevel, flowDirection: .left)
                        .frame(width: 45, height: 20)

                    // Timer overlay in center-right
                    VStack(spacing: 1) {
                        pulsatingLine
                        Text(formatTime(controller.elapsedTime))
                            .font(.system(size: 9, weight: .light, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.leading, 4)
                } else if controller.state == .transcribing {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 20, height: 2)
                        .opacity(0.8)
                } else if controller.state == .routing {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green.opacity(0.9))
                } else if isExpanded {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: pokeOutAmount)
        }
    }

    // MARK: - Minimal Layout (particles both sides, centered pill on hover)

    private var minimalLayout: some View {
        ZStack {
            // Main HStack with wings
            HStack(spacing: 0) {
                // LEFT wing
                ZStack {
                    NotchWingShape(side: .left, cornerRadius: 14, topOuterRadius: 10)
                        .fill(particleZoneColor)

                    // Active state content only (hover shows centered pill instead)
                    if expansionState == .active {
                        if isScreenRecordingVisible {
                            screenRecordingBadge
                                .offset(x: -3, y: -3)
                        } else {
                            switch controller.state {
                            case .listening:
                                ZStack {
                                    NotchParticles(audioLevel: controller.audioLevel, flowDirection: .right)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    if isHovered {
                                        ZStack {
                                            Capsule()
                                                .fill(Color.white.opacity(0.15))
                                                .frame(width: 20, height: 20)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        .offset(x: -6, y: -3)
                                        .contentShape(Circle())
                                        .onTapGesture { controller.requestCancel() }
                                    }
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
                    }
                }
                .frame(width: pokeOutAmount)
                .clipped()

                // CENTER: hidden behind notch
                Color.clear
                    .frame(width: notchWidth)

                // RIGHT wing
                ZStack {
                    NotchWingShape(side: .right, cornerRadius: 14, topOuterRadius: 10)
                        .fill(particleZoneColor)

                    // Active state content only (hover shows centered pill instead)
                    if expansionState == .active {
                        if isScreenRecordingVisible {
                            ZStack {
                                if isHovered {
                                    screenRecordingStopGlyph
                                } else {
                                    Text(formatTime(controller.screenRecordingElapsedTime))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .offset(x: 4, y: -3)
                        } else {
                            switch controller.state {
                            case .listening:
                                ZStack {
                                    NotchParticles(audioLevel: controller.audioLevel, flowDirection: .left)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    if isHovered {
                                        ZStack {
                                            Capsule()
                                                .fill(Color.white.opacity(0.15))
                                                .frame(width: 20, height: 20)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color(red: 1.0, green: 0.35, blue: 0.35))
                                                .frame(width: 8, height: 8)
                                        }
                                        .offset(x: 6, y: -3)
                                        .contentShape(Circle())
                                        .onTapGesture { controller.requestStop() }
                                    }
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
                    }
                }
                .frame(width: pokeOutAmount)
                .clipped()
            }

            // Centered hover pill - white handlebar that pulsates vertically
            if expansionState == .hover {
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 32, height: 5)
                    .modifier(VerticalPulseModifier(isAnimating: true, speed: 0.8))
                    .offset(y: 8)  // Position below the notch edge
            }
        }
    }

    // MARK: - Centered Pulsating Line (below notch)

    private var centeredPulsatingLine: some View {
        Rectangle()
            .fill(stateColor)
            .frame(width: 60, height: 2)
            .modifier(LinePulseModifier(isAnimating: controller.state == .listening))
    }

    private var screenRecordingColor: Color {
        Color(red: 1.0, green: 0.24, blue: 0.22)
    }

    private var screenRecordingBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(screenRecordingColor)
                .frame(width: 6, height: 6)
            Image(systemName: "video.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.13))
        )
    }

    private var screenRecordingStopGlyph: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 20, height: 20)
            RoundedRectangle(cornerRadius: 2)
                .fill(screenRecordingColor)
                .frame(width: 8, height: 8)
        }
        .contentShape(Circle())
        .onTapGesture { controller.requestStopScreenRecording() }
    }

    // MARK: - Centered Status Line (below notch, adapts to state)

    @ViewBuilder
    private var centeredStatusLine: some View {
        let lineW = CGFloat(tuning.lineWidth)
        let lineH = CGFloat(tuning.lineHeight)

        if isScreenRecordingVisible {
            Rectangle()
                .fill(screenRecordingColor)
                .frame(width: lineW * 0.8, height: lineH)
                .modifier(LinePulseModifier(isAnimating: true, speed: tuning.pulseSpeed))
        } else {
        switch controller.state {
        case .listening:
            // Red pulsating line
            Rectangle()
                .fill(stateColor)
                .frame(width: lineW, height: lineH)
                .modifier(LinePulseModifier(isAnimating: true, speed: tuning.pulseSpeed))
        case .transcribing:
            // Orange pulsating line
            Rectangle()
                .fill(Color.orange)
                .frame(width: lineW * 0.85, height: lineH)
                .modifier(LinePulseModifier(isAnimating: true, speed: tuning.pulseSpeed))
        case .routing:
            // Green solid line
            Rectangle()
                .fill(Color.green)
                .frame(width: lineW * 0.7, height: lineH)
        case .refining:
            // Purple solid line
            Rectangle()
                .fill(Color.purple)
                .frame(width: lineW * 0.7, height: lineH)
        case .idle:
            EmptyView()
        }
        }
    }

    // MARK: - Left Content (Particles / Indicator)

    private var leftContent: some View {
        ZStack {
            // Background for expanded state
            if isExpanded {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 8,
                    topTrailingRadius: 0
                )
                .fill(particleZoneColor)
                .padding(.trailing, 4)
            }

            // Content
            if isScreenRecordingVisible {
                screenRecordingBadge
            } else if controller.state == .listening {
                // Particles when recording
                NotchParticles(audioLevel: controller.audioLevel)
                    .frame(width: 45, height: 20)
            } else if isExpanded {
                // Ready state - subtle dot
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            } else {
                // Collapsed idle - tiny indicator
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Right Content (Timer / Status)

    private var rightContent: some View {
        ZStack {
            // Background for expanded state
            if isExpanded {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 8,
                    topTrailingRadius: 0
                )
                .fill(particleZoneColor)
                .padding(.leading, 4)
            }

            // Content
            VStack(spacing: 2) {
                if isScreenRecordingVisible {
                    if isHovered {
                        screenRecordingStopGlyph
                    } else {
                        Text(formatTime(controller.screenRecordingElapsedTime))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                } else if controller.state == .listening {
                    // Pulsating red line + timer
                    pulsatingLine
                    Text(formatTime(controller.elapsedTime))
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                } else if controller.state == .transcribing {
                    // Orange processing indicator
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 20, height: 2)
                        .opacity(0.8)
                    Text("...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                } else if controller.state == .routing {
                    // Green done indicator
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 16, height: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green.opacity(0.9))
                } else if isExpanded {
                    // Hover/ready state
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 14, height: 1.5)
                    Text("Ready")
                        .font(.system(size: 9, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    // Collapsed idle - tiny indicator
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    // MARK: - Pulsating Line

    private var pulsatingLine: some View {
        Rectangle()
            .fill(stateColor)
            .frame(width: 24, height: 2)
            .modifier(LinePulseModifier(isAnimating: controller.state == .listening))
    }

    // MARK: - Breathing Dot

    private var breathingDot: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 6, height: 6)
            .modifier(NotchPulseModifier(isAnimating: controller.state == .listening))
    }

    private var stateColor: Color {
        if isScreenRecordingVisible {
            return screenRecordingColor
        }

        switch controller.state {
        case .listening:
            return Color(red: 1.0, green: 0.35, blue: 0.35)  // Soft red
        case .transcribing:
            return Color.orange
        case .routing:
            return Color(red: 0.4, green: 0.9, blue: 0.5)  // Soft green
        case .refining:
            return Color.purple
        case .idle:
            return Color.white
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Processing Dots (animated ellipsis for transcribing state)

struct ProcessingDots: View {
    let color: Color
    @State private var phase: Int = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let currentPhase = Int(t * 2.8) % 4

            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotFill(for: i, phase: currentPhase))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    private func dotFill(for index: Int, phase: Int) -> Color {
        index == (phase - 1) ? color : Color.white
    }
}

// MARK: - Notch Wing Shape (extends from notch with rounded corners)

struct NotchWingShape: Shape {
    let side: NotchSide
    let cornerRadius: CGFloat    // Radius for bottom rounded corners
    let topOuterRadius: CGFloat  // Radius for outer top corner (away from notch)

    enum NotchSide {
        case left   // Wing extends from left of notch
        case right  // Wing extends from right of notch
    }

    init(side: NotchSide, cornerRadius: CGFloat, topOuterRadius: CGFloat = 8) {
        self.side = side
        self.cornerRadius = cornerRadius
        self.topOuterRadius = topOuterRadius
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cr = min(cornerRadius, min(w, h) / 2)  // Bottom corner radius
        let tr = min(topOuterRadius, min(w, h) / 3)  // Top outer corner radius


        switch side {
        case .right:
            // Right wing:
            // - Top-left: flush with notch (no radius)
            // - Top-right: rounded (outer corner)
            // - Bottom corners: rounded

            // Start at top-left (flush with notch)
            path.move(to: CGPoint(x: 0, y: 0))

            // Top edge to top-right corner (leaving room for outer curve)
            path.addLine(to: CGPoint(x: w - tr, y: 0))

            // Top-right corner - rounded outward curve
            path.addQuadCurve(
                to: CGPoint(x: w, y: tr),
                control: CGPoint(x: w, y: 0)
            )

            // Right edge down to bottom-right corner
            path.addLine(to: CGPoint(x: w, y: h - cr))

            // Bottom-right corner (rounded)
            path.addQuadCurve(
                to: CGPoint(x: w - cr, y: h),
                control: CGPoint(x: w, y: h)
            )

            // Bottom edge
            path.addLine(to: CGPoint(x: cr, y: h))

            // Bottom-left corner (rounded)
            path.addQuadCurve(
                to: CGPoint(x: 0, y: h - cr),
                control: CGPoint(x: 0, y: h)
            )

            // Left edge (inner, toward notch) - straight up
            path.addLine(to: CGPoint(x: 0, y: 0))

            path.closeSubpath()

        case .left:
            // Left wing:
            // - Top-left: rounded (outer corner)
            // - Top-right: flush with notch (no radius)
            // - Bottom corners: rounded

            // Start at top-left corner curve start
            path.move(to: CGPoint(x: 0, y: tr))

            // Top-left corner - rounded outward curve
            path.addQuadCurve(
                to: CGPoint(x: tr, y: 0),
                control: CGPoint(x: 0, y: 0)
            )

            // Top edge to top-right (flush with notch)
            path.addLine(to: CGPoint(x: w, y: 0))

            // Right edge (inner, toward notch) - straight down
            path.addLine(to: CGPoint(x: w, y: h - cr))

            // Bottom-right corner (rounded)
            path.addQuadCurve(
                to: CGPoint(x: w - cr, y: h),
                control: CGPoint(x: w, y: h)
            )

            // Bottom edge
            path.addLine(to: CGPoint(x: cr, y: h))

            // Bottom-left corner (rounded)
            path.addQuadCurve(
                to: CGPoint(x: 0, y: h - cr),
                control: CGPoint(x: 0, y: h)
            )

            // Left edge up to start
            path.closeSubpath()
        }

        return path
    }
}

// Legacy alias for compatibility
typealias NotchHuggingShape = NotchWingShape

// MARK: - Particle Flow Direction

enum ParticleFlowDirection {
    case left   // Flow from right to left (toward left edge)
    case right  // Flow from left to right (toward right edge)
}

// MARK: - Notch Particles (tiny flowing dots)

struct NotchParticles: View {
    let audioLevel: Float
    var flowDirection: ParticleFlowDirection = .right

    // Access tuning for configurable particles
    @ObservedObject private var tuning = NotchTuning.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: notchParticleFrameInterval)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let particleCount = max(6, min(12, tuning.particleCount))
                let baseSpeed = tuning.particleSpeed
                let baseSize = CGFloat(tuning.particleSize)

                // Target level from audio (amplified for responsiveness)
                let level = max(0.15, min(1.0, CGFloat(audioLevel) * 2.0))

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749

                    // X: faster flow (1.5x speed boost)
                    let speedVar = (seed.truncatingRemainder(dividingBy: 1.0)) * 0.02
                    let speed = (baseSpeed + speedVar) * 1.5
                    let xProgress = (time * speed + seed).truncatingRemainder(dividingBy: 1.0)

                    // Direction
                    let x: CGFloat
                    switch flowDirection {
                    case .right:
                        x = CGFloat(xProgress) * size.width
                    case .left:
                        x = size.width - CGFloat(xProgress) * size.width
                    }

                    // Y: dual wave motion (like WavyParticlesView)
                    // Waves dance on their own, audio just scales the amplitude
                    let waveSpeed = 1.6  // Faster wave motion
                    let primaryWave = sin(time * waveSpeed + seed * 4)
                    let secondaryWave = sin(time * waveSpeed * 0.6 + seed * 6) * 0.3

                    // Base amplitude (tight when quiet) + audio amplitude (expands with voice)
                    let baseAmp = 0.12  // Slightly larger base for more vertical coverage
                    let audioAmp = 0.40  // More expansion with audio
                    let waveAmplitude = baseAmp + Double(level) * audioAmp

                    // Lane offset for variety - spread across full height
                    let laneOffset = (Double(i % 10) / 10.0 - 0.5) * 0.25
                    // Shift center up slightly to use top space better
                    let adjustedCenterY = centerY - size.height * 0.05
                    let y = adjustedCenterY + CGFloat((primaryWave + secondaryWave + laneOffset) * waveAmplitude * Double(size.height) * 0.5)

                    // Particle size grows slightly with audio
                    let levelBonus = level * 1.5
                    let sizeVariation = CGFloat(0.7 + sin(seed * 5) * 0.3)
                    let particleSize = baseSize + levelBonus * sizeVariation

                    let edgeFade: Double
                    switch flowDirection {
                    case .right:
                        edgeFade = min(xProgress * 3, 1.0) * min((1.0 - xProgress) * 2, 1.0)
                    case .left:
                        edgeFade = min((1.0 - xProgress) * 3, 1.0) * min(xProgress * 2, 1.0)
                    }

                    let visibleSize = particleSize * max(0.30, CGFloat(edgeFade))

                    // Draw particle
                    let rect = CGRect(
                        x: x - visibleSize / 2,
                        y: y - visibleSize / 2,
                        width: visibleSize,
                        height: visibleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(.white))
                }
            }
        }
    }
}

// MARK: - Line Pulse Modifier

struct LinePulseModifier: ViewModifier {
    let isAnimating: Bool
    var speed: Double = 1.2  // Duration in seconds (lower = faster)

    @State private var opacity: Double = 1.0
    @State private var scaleX: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(x: scaleX, y: 1.0)
            .onAppear {
                guard isAnimating else { return }
                // Softer, gentler pulse with configurable speed
                withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                    opacity = 0.7
                    scaleX = 0.92
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        opacity = 0.7
                        scaleX = 0.92
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        opacity = 1.0
                        scaleX = 1.0
                    }
                }
            }
    }
}

// MARK: - Vertical Pulse Modifier (for hover pill)

struct VerticalPulseModifier: ViewModifier {
    let isAnimating: Bool
    var speed: Double = 1.0

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0.5

    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                    offsetY = 3
                    opacity = 0.8
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        offsetY = 3
                        opacity = 0.8
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offsetY = 0
                        opacity = 0.5
                    }
                }
            }
    }
}

// MARK: - Notch Pulse Modifier

struct NotchPulseModifier: ViewModifier {
    let isAnimating: Bool
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.15
                    opacity = 0.7
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.15
                        opacity = 0.7
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                        opacity = 1.0
                    }
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        NotchOverlayView()
            .environmentObject(NotchOverlayController.shared)
    }
    .frame(width: 300, height: 60)
    .background(Color.black)
}
