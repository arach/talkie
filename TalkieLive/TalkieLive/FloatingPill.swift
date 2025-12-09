//
//  FloatingPill.swift
//  TalkieLive
//
//  Always-visible floating indicator pill - appears on all screens
//

import SwiftUI
import AppKit
import Combine

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

    @Published var state: LiveState = .idle
    @Published var isVisible: Bool = true
    @Published var proximity: CGFloat = 0  // 0 = far, 1 = very close (for view to react)
    @Published var elapsedTime: TimeInterval = 0
    @Published var processingTime: TimeInterval = 0

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
        // Larger frame to accommodate expanded state
        hostingView.frame = NSRect(x: 0, y: 0, width: 80, height: 28)

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
                y: screenFrame.minY + 2  // Flush to bottom
            )
        case .bottomLeft:
            return NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + 2
            )
        case .bottomRight:
            return NSPoint(
                x: screenFrame.maxX - panelSize.width - margin,
                y: screenFrame.minY + 2
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

        // Use a timer to poll mouse position (more reliable than event monitor for global tracking)
        magneticTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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

        for window in windows {
            guard let homePosition = homePositions[window] else { continue }

            // Calculate distance from mouse to home center
            let homeCenter = NSPoint(
                x: homePosition.x + window.frame.width / 2,
                y: homePosition.y + window.frame.height / 2
            )
            let dx = mouseLocation.x - homeCenter.x
            let dy = mouseLocation.y - homeCenter.y
            let distance = sqrt(dx * dx + dy * dy)

            // Track proximity for UI expansion (this is the main purpose)
            if distance < proximityRadius && distance > 0 {
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

        // Update proximity for view reactivity
        proximity = closestProximity
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
    }

    // Control callback
    var onTap: (() -> Void)?

    func handleTap() {
        onTap?()
    }
}

// MARK: - Floating Pill View (expands when cursor approaches)

struct FloatingPillView: View {
    @EnvironmentObject var controller: FloatingPillController
    @State private var isHovered = false
    @State private var pulsePhase: CGFloat = 0

    // Expansion threshold - only expand when very close (proximity > 0.7) or hovered
    private let expandThreshold: CGFloat = 0.7

    private var isExpanded: Bool {
        controller.proximity > expandThreshold || isHovered
    }

    private var expansionProgress: CGFloat {
        if isHovered { return 1.0 }
        let progress = (controller.proximity - expandThreshold) / (1.0 - expandThreshold)
        return max(0, min(1, progress))
    }

    var body: some View {
        Button(action: { controller.handleTap() }) {
            ZStack {
                if isExpanded {
                    // Expanded button state with timer
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    // Minimal sliver state
                    sliverContent
                        .transition(.opacity.combined(with: .scale(scale: 1.2)))
                }
            }
            .frame(width: 80, height: 28)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: controller.state) { _, newState in
            pulsePhase = 0
            if newState == .listening {
                startPulseAnimation()
            }
        }
    }

    // Minimal sliver when far from cursor
    private var sliverContent: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(indicatorColor.opacity(sliverOpacity))
            .frame(width: 24, height: 2)
            .scaleEffect(x: controller.state == .listening ? 1.0 + pulsePhase * 0.3 : 1.0, y: 1.0)
    }

    // Expanded button with timer when close to cursor
    private var expandedContent: some View {
        HStack(spacing: 4) {
            // State indicator dot - pulsates when recording
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
                .scaleEffect(controller.state == .listening ? 1.0 + pulsePhase * 0.4 : 1.0)

            // Timer (only when recording/transcribing) - white text, not red
            if controller.state == .listening || controller.state == .transcribing {
                Text(timeString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("REC")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
        )
    }

    private var timeString: String {
        // Show processing time during transcribing, recording time during listening
        let time = controller.state == .transcribing ? controller.processingTime : controller.elapsedTime
        let seconds = Int(time)
        let tenths = Int((time * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d.%d", seconds, tenths)
    }

    private func startPulseAnimation() {
        guard controller.state == .listening else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulsePhase = 1.0
        }
    }

    private var indicatorColor: Color {
        switch controller.state {
        case .idle: return .white
        case .listening: return Color(red: 1.0, green: 0.3, blue: 0.3)
        case .transcribing: return Color(red: 1.0, green: 0.7, blue: 0.3)
        case .routing: return Color(red: 0.4, green: 1.0, blue: 0.5)
        }
    }

    private var sliverOpacity: Double {
        switch controller.state {
        case .idle: return 0.15
        case .listening: return 0.8
        case .transcribing: return 0.6
        case .routing: return 0.6
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
