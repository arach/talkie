//
//  FloatingPill.swift
//  TalkieLive
//
//  Always-visible floating indicator pill - appears on all screens
//

import SwiftUI
import AppKit
import Combine
import os

private let pillLogger = Logger(subsystem: "jdi.talkie.live", category: "FloatingPill")

// MARK: - Floating Pill Controller

@MainActor
final class FloatingPillController: ObservableObject {
    static let shared = FloatingPillController()

    private var windows: [NSWindow] = []
    private var homePositions: [NSWindow: NSPoint] = [:]  // Store original positions
    private var mouseMonitor: Any?
    private var magneticTimer: Timer?
    private var recordingStartTime: Date?
    private var processingStartTime: Date?
    private var settingsCancellables = Set<AnyCancellable>()

    // Proximity detection settings (for expansion trigger)
    private let proximityRadius: CGFloat = 80   // Distance at which pill expands
    private let maxBounce: CGFloat = 3  // Tiny bounce amount (very subtle)
    private let bounceSmoothness: CGFloat = 0.12  // Smooth return

    // Performance: threshold to avoid publishing tiny proximity changes
    private let proximityPublishThreshold: CGFloat = 0.05

    @Published var state: LiveState = .idle
    @Published var isVisible: Bool = true
    @Published var proximity: CGFloat = 0  // 0 = far, 1 = very close (for view to react)
    @Published var elapsedTime: TimeInterval = 0
    @Published var processingTime: TimeInterval = 0

    // Engine & queue status
    @Published var isEngineConnected: Bool = false
    @Published var isWrongEngineBuild: Bool = false
    @Published var pendingQueueCount: Int = 0

    // Track last published proximity to avoid redundant updates
    private var lastPublishedProximity: CGFloat = 0

    private init() {
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isVisible == true {
                    self?.repositionAllPills()
                }
            }
        }

        // Listen for pill settings changes
        LiveSettings.shared.$pillPosition
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    if self?.isVisible == true {
                        self?.repositionAllPills()
                    }
                }
            }
            .store(in: &settingsCancellables)

        LiveSettings.shared.$pillShowOnAllScreens
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    if self?.isVisible == true {
                        self?.show()  // Recreate to add/remove pills on screens
                    }
                }
            }
            .store(in: &settingsCancellables)

        // Observe engine connection state
        EngineClient.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                // Connected includes wrong build (still functional, just a warning)
                self?.isEngineConnected = (state == .connected || state == .connectedWrongBuild)
                self?.isWrongEngineBuild = (state == .connectedWrongBuild)
            }
            .store(in: &settingsCancellables)

        // Observe pending queue count
        TranscriptionRetryManager.shared.$pendingCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.pendingQueueCount = count
            }
            .store(in: &settingsCancellables)
    }

    func show() {
        isVisible = true

        // Remove existing windows
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        homePositions.removeAll()

        // Create pills based on settings
        let showOnAllScreens = LiveSettings.shared.pillShowOnAllScreens
        let screens = showOnAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }

        for screen in screens {
            createPill(on: screen)
        }

        // Start magnetic tracking
        startMagneticTracking()
    }

    private func createPill(on screen: NSScreen) {
        let pillView = FloatingPillView()
        let hostingView = NSHostingView(rootView: pillView.environmentObject(self))
        // Frame must be large enough to accommodate expanded state for proper hit testing
        // Expanded pill shows text like "✨ → Edit", timer, etc. - needs ~150px width
        hostingView.frame = NSRect(x: 0, y: 0, width: 160, height: 30)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false  // Fixed position
        panel.hasShadow = false  // We'll handle shadow in SwiftUI
        panel.ignoresMouseEvents = false

        // Position at bottom center of this screen
        let homePosition = calculateHomePosition(for: panel, on: screen)
        panel.setFrameOrigin(homePosition)
        homePositions[panel] = homePosition

        panel.orderFront(nil)
        windows.append(panel)
    }

    private func calculateHomePosition(for panel: NSWindow, on screen: NSScreen) -> NSPoint {
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let margin: CGFloat = 8

        switch LiveSettings.shared.pillPosition {
        case .bottomCenter:
            return NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.minY + 6  // Slight offset from bottom for breathing room
            )
        case .bottomLeft:
            return NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + 6
            )
        case .bottomRight:
            return NSPoint(
                x: screenFrame.maxX - panelSize.width - margin,
                y: screenFrame.minY + 6
            )
        case .topCenter:
            return NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.maxY - panelSize.height - margin
            )
        }
    }

    private func positionPill(_ panel: NSWindow, on screen: NSScreen) {
        let homePosition = calculateHomePosition(for: panel, on: screen)
        panel.setFrameOrigin(homePosition)
        homePositions[panel] = homePosition
    }

    private func repositionAllPills() {
        // Rebuild pills when screen config changes
        if isVisible {
            show()
        }
    }

    // MARK: - Magnetic Effect

    private func startMagneticTracking() {
        stopMagneticTracking()

        // Poll at 15fps for proximity detection - plenty smooth for hover effects
        // Timer updates at higher rate (30fps) only when actively recording to show elapsed time
        let frameRate: Double = (state == .listening || state == .transcribing) ? 30.0 : 15.0
        magneticTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMagneticPositions()
                self?.updateElapsedTime()
            }
        }
    }

    private func stopMagneticTracking() {
        magneticTimer?.invalidate()
        magneticTimer = nil

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func updateElapsedTime() {
        if let start = recordingStartTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
        if let start = processingStartTime {
            processingTime = Date().timeIntervalSince(start)
        }
    }

    private func updateMagneticPositions() {
        let mouseLocation = NSEvent.mouseLocation  // Global screen coordinates

        var closestProximity: CGFloat = 0

        // Pre-calculate squared radius to avoid sqrt in hot loop
        let proximityRadiusSquared = proximityRadius * proximityRadius

        for window in windows {
            guard let homePosition = homePositions[window] else { continue }

            // Calculate distance from mouse to home center
            let homeCenter = NSPoint(
                x: homePosition.x + window.frame.width / 2,
                y: homePosition.y + window.frame.height / 2
            )
            let dx = mouseLocation.x - homeCenter.x
            let dy = mouseLocation.y - homeCenter.y
            let distanceSquared = dx * dx + dy * dy

            // Track proximity for UI expansion (compare squared distances to avoid sqrt)
            if distanceSquared < proximityRadiusSquared && distanceSquared > 0 {
                // Only compute sqrt when we're actually in range
                let distance = sqrt(distanceSquared)
                let pullStrength = 1.0 - (distance / proximityRadius)
                closestProximity = max(closestProximity, pullStrength)
            }

            // Tiny bounce effect - just a subtle lift when close, not following mouse
            let targetY: CGFloat
            if closestProximity > 0.7 {
                // Small bounce up when very close
                targetY = homePosition.y + maxBounce
            } else {
                targetY = homePosition.y
            }

            // Smooth interpolation back to home
            let currentOrigin = window.frame.origin
            let newY = currentOrigin.y + (targetY - currentOrigin.y) * bounceSmoothness

            window.setFrameOrigin(NSPoint(x: homePosition.x, y: newY))
        }

        // Only publish proximity if it changed meaningfully (avoids redundant SwiftUI updates)
        if abs(closestProximity - lastPublishedProximity) > proximityPublishThreshold {
            proximity = closestProximity
            lastPublishedProximity = closestProximity
        }
    }

    func hide() {
        isVisible = false
        stopMagneticTracking()

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        homePositions.removeAll()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func updateState(_ state: LiveState) {
        let previousState = self.state
        self.state = state

        // Track recording time
        if state == .listening {
            recordingStartTime = Date()
            elapsedTime = 0
            processingStartTime = nil
            processingTime = 0
        } else if state == .transcribing {
            // Reset timer for processing phase
            processingStartTime = Date()
            processingTime = 0
        } else if state == .idle {
            recordingStartTime = nil
            elapsedTime = 0
            processingStartTime = nil
            processingTime = 0
        }

        // Restart timer if we transition to/from active recording (changes frame rate)
        let wasActive = previousState == .listening || previousState == .transcribing
        let isActive = state == .listening || state == .transcribing
        if wasActive != isActive && isVisible {
            startMagneticTracking()  // Restarts with appropriate frame rate
        }
    }

    // Control callback - takes Bool indicating if Shift was held (for interstitial mode)
    var onTapWithShift: ((Bool) -> Void)?

    func handleTap() {
        // Check if Shift is held for interstitial mode
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        NSLog("[FloatingPill] handleTap: state=%@, shiftHeld=%d", state.rawValue, shiftHeld ? 1 : 0)

        // If transcribing/routing and stuck, allow pushing to queue for later retry
        if state == .transcribing || state == .routing {
            NSLog("[FloatingPill] → pushing to queue")
            onPushToQueue?()  // Save audio to queue and reset state
        }
        // If there are queued items and we're idle, show the failed queue picker
        else if pendingQueueCount > 0 && state == .idle {
            NSLog("[FloatingPill] → showing failed queue")
            showFailedQueue()
        } else {
            NSLog("[FloatingPill] → calling onTapWithShift(%d)", shiftHeld ? 1 : 0)
            onTapWithShift?(shiftHeld)
        }
    }

    // Push-to-queue callback (for escaping stuck transcription)
    var onPushToQueue: (() -> Void)?

    func showFailedQueue() {
        FailedQueueController.shared.show()
    }
}

// MARK: - Floating Pill View (expands when cursor approaches)

struct FloatingPillView: View {
    @EnvironmentObject var controller: FloatingPillController
    @State private var isHovered = false

    // Expansion threshold - only expand when very close (proximity > 0.7) or hovered
    private let expandThreshold: CGFloat = 0.7

    private var isExpanded: Bool {
        controller.proximity > expandThreshold || isHovered
    }

    var body: some View {
        StatePill(
            state: controller.state,
            isWarmingUp: false,
            showSuccess: false,
            recordingDuration: controller.elapsedTime,
            processingDuration: controller.processingTime,
            isEngineConnected: controller.isEngineConnected,
            pendingQueueCount: controller.pendingQueueCount,
            forceExpanded: isExpanded,
            onTap: { controller.handleTap() },
            onQueueTap: { FailedQueueController.shared.show() }
        )
        // Frame must accommodate expanded state for proper hit testing
        .frame(width: 160, height: 30)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        FloatingPillView()
            .environmentObject(FloatingPillController.shared)
    }
    .padding(40)
    .background(Color.black.opacity(0.8))
}
