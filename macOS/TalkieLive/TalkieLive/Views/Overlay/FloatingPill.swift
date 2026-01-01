//
//  FloatingPill.swift
//  TalkieLive
//
//  Always-visible floating indicator pill - appears on all screens
//

import SwiftUI
import TalkieKit
import AppKit
import Combine
import os

private let pillLogger = Logger(subsystem: "jdi.talkie.live", category: "FloatingPill")

// Notification for showing permissions window
extension Notification.Name {
    static let showPermissionsWindow = Notification.Name("showPermissionsWindow")
}

// MARK: - NSScreen Extension (Safe Display Access)

extension NSScreen {
    /// Check if this screen is valid (not in a transitional/disconnected state)
    var isValid: Bool {
        // Check if we can get a valid display ID
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }

        // Check if frame is valid (non-zero)
        let screenFrame = frame
        guard screenFrame.width > 0 && screenFrame.height > 0 else {
            return false
        }

        // Check if this display is actually active
        // CGDisplayIsActive returns false for disconnected/sleeping displays
        return CGDisplayIsActive(displayID) != 0
    }

    /// Safe access to screen name that handles invalid display identifiers gracefully
    var safeDisplayName: String {
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return "Display"
        }

        // Only access localizedName if the display is valid
        // This prevents "invalid display identifier" errors for transitional screens
        guard isValid else {
            return "Display \(displayID) (inactive)"
        }

        let name = self.localizedName
        if name.isEmpty || name == "Display" {
            return "Display \(displayID)"
        }

        return name
    }
}

// MARK: - Floating Pill Controller

@MainActor
final class FloatingPillController: ObservableObject {
    static let shared = FloatingPillController()

    private var windows: [NSWindow] = []
    private var homePositions: [NSWindow: NSPoint] = [:]  // Store original positions
    private var mouseMonitor: Any?
    private var magneticTimer: Timer?
    private var timerUpdateTimer: Timer?  // Separate 1Hz timer for elapsed time display
    private var healthCheckTimer: Timer?  // Periodic health check to heal from failed states
    private var recordingStartTime: Date?
    private var processingStartTime: Date?
    private var settingsCancellables = Set<AnyCancellable>()

    // Proximity detection settings (for expansion trigger)
    private let proximityRadius: CGFloat = 80   // Distance at which pill expands
    private let maxBounce: CGFloat = 3  // Tiny bounce amount (very subtle)
    private let bounceSmoothness: CGFloat = 0.12  // Smooth return

    // Performance: threshold to avoid publishing tiny proximity changes
    private let proximityPublishThreshold: CGFloat = 0.05
    // Time-based throttle: max 5fps for SwiftUI updates (animation stays at 15fps)
    private let proximityPublishInterval: TimeInterval = 0.2

    @Published var state: LiveState = .idle
    @Published var isVisible: Bool = true
    @Published var proximity: CGFloat = 0  // 0 = far, 1 = very close (for view to react)
    @Published var elapsedTime: TimeInterval = 0
    @Published var processingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0  // Throttled to 2Hz for UI (just sign of life)

    // Engine & queue status
    @Published var isEngineConnected: Bool = false
    @Published var isWrongEngineBuild: Bool = false
    @Published var pendingQueueCount: Int = 0

    // Capture intent (for showing scratchpad indicator on pill)
    @Published var captureIntent: String = "Paste"

    // Track last published proximity to avoid redundant updates
    private var lastPublishedProximity: CGFloat = 0
    private var lastProximityUpdate: Date = .distantPast
    private var lastAudioLevelUpdate: Date = .distantPast

    private init() {
        // Initialize from current engine state (important: engine may already be connected)
        let initialState = EngineClient.shared.connectionState
        isEngineConnected = (initialState == .connected || initialState == .connectedWrongBuild)
        isWrongEngineBuild = (initialState == .connectedWrongBuild)
        pillLogger.debug("[Init] Initial engine connectionState=\(initialState.rawValue), isEngineConnected=\(self.isEngineConnected)")

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
                let isConnected = (state == .connected || state == .connectedWrongBuild)
                self?.isEngineConnected = isConnected
                self?.isWrongEngineBuild = (state == .connectedWrongBuild)

                pillLogger.debug("[Engine State] connectionState=\(state.rawValue), isEngineConnected=\(isConnected)")
            }
            .store(in: &settingsCancellables)

        // Initialize and observe pending queue count
        pendingQueueCount = TranscriptionRetryManager.shared.pendingCount
        TranscriptionRetryManager.shared.$pendingCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.pendingQueueCount = count
            }
            .store(in: &settingsCancellables)

        // Observe audio level (throttled to 2Hz - just a sign of life indicator)
        AudioLevelMonitor.shared.$level
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &settingsCancellables)
    }

    func show() {
        isVisible = true

        // IMPORTANT: Preserve callback before clearing windows
        // This callback gets set in AppDelegate.setupFloatingPill() and must survive window recreation
        let preservedCallback = onTap
        pillLogger.info("show(): Preserving onTap callback (nil=\(preservedCallback == nil))")

        // Remove existing windows
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        homePositions.removeAll()

        // Create pills based on settings
        let showOnAllScreens = LiveSettings.shared.pillShowOnAllScreens
        let allScreens = showOnAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }

        // Filter out invalid/transitional screens to avoid display identifier errors
        let validScreens = allScreens.filter { $0.isValid }

        pillLogger.debug("[Screens] Total: \(allScreens.count), Valid: \(validScreens.count)")

        // Log all valid screens
        for (index, screen) in validScreens.enumerated() {
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            pillLogger.debug("""
                [Screen \(index)] \(screen.safeDisplayName)
                  Full frame: x=\(frame.minX), y=\(frame.minY), w=\(frame.width), h=\(frame.height)
                  Visible frame: x=\(visibleFrame.minX), y=\(visibleFrame.minY), w=\(visibleFrame.width), h=\(visibleFrame.height)
                  Visible midX: \(visibleFrame.midX)
                """
            )
        }

        // Only create pills on valid screens
        for screen in validScreens {
            createPill(on: screen)
        }

        // Restore callback after window recreation
        onTap = preservedCallback
        pillLogger.info("show(): Callback restored (nil=\(self.onTap == nil))")

        // Start magnetic tracking
        startMagneticTracking()

        // Start periodic health checks (every 5 seconds)
        startHealthChecks()
    }

    private func createPill(on screen: NSScreen) {
        let pillView = FloatingPillView()
        let hostingView = NSHostingView(rootView: pillView.environmentObject(self))
        // Frame must be large enough to accommodate expanded state (240 when showing dev info)
        hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 30)

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

        // Log the final pill position
        let contentCenterX = homePosition.x + (panel.frame.width / 2)
        let expectedContentCenterX = screen.visibleFrame.midX
        let centerOffset = contentCenterX - expectedContentCenterX

        pillLogger.debug("""
            [Pill Position] \(screen.safeDisplayName)
              Panel position: x=\(homePosition.x), y=\(homePosition.y)
              Panel width: \(panel.frame.width)
              Panel center X: \(contentCenterX)
              Screen center X: \(expectedContentCenterX)
              Offset from screen center: \(centerOffset) px
            """
        )

        panel.orderFront(nil)
        windows.append(panel)
    }

    private func calculateHomePosition(for panel: NSWindow, on screen: NSScreen) -> NSPoint {
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let margin: CGFloat = 8

        // Actual pill content width when collapsed (not the full panel width)
        let pillContentWidth: CGFloat = 160

        switch LiveSettings.shared.pillPosition {
        case .bottomCenter:
            // Center based on the actual pill content, not the panel width
            // Panel is wider (220px) to accommodate expanded states, but we center the content (160px)
            let contentCenterX = floor(screenFrame.midX - (pillContentWidth / 2))
            // Offset slightly to account for the panel being wider than content
            let panelOffset = (panelSize.width - pillContentWidth) / 2
            let finalX = contentCenterX - panelOffset

            pillLogger.debug("""
                [Centering] Screen: \(screen.safeDisplayName)
                  screenFrame.midX: \(screenFrame.midX)
                  screenFrame.width: \(screenFrame.width)
                  panelSize.width: \(panelSize.width)
                  pillContentWidth: \(pillContentWidth)
                  contentCenterX: \(contentCenterX)
                  panelOffset: \(panelOffset)
                  finalX: \(finalX)
                """
            )

            return NSPoint(
                x: finalX,
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

        // Magnetic position updates at 15fps - smooth hover effects without excessive CPU
        magneticTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMagneticPositions()
            }
        }

        // Separate 1Hz timer for elapsed time display - prevents flicker from frequent updates
        // Only run during active states (listening or transcribing)
        if state == .listening || state == .transcribing {
            startTimerUpdates()
        }
    }

    private func startTimerUpdates() {
        stopTimerUpdates()

        // Update immediately on start
        updateElapsedTime()

        // Then update every second (1Hz) - smooth, no flicker
        timerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopTimerUpdates() {
        timerUpdateTimer?.invalidate()
        timerUpdateTimer = nil
    }

    private func stopMagneticTracking() {
        magneticTimer?.invalidate()
        magneticTimer = nil
        stopTimerUpdates()

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

        // Only publish proximity if changed meaningfully AND enough time has passed
        // This keeps animation smooth (15fps) but throttles SwiftUI updates (5fps max)
        // Exception: publish immediately when leaving (proximity → 0) for snappy collapse
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastProximityUpdate)
        let valueChanged = abs(closestProximity - lastPublishedProximity) > proximityPublishThreshold
        let isLeaving = closestProximity == 0 && lastPublishedProximity > 0

        if isLeaving || (valueChanged && timeSinceLastUpdate >= proximityPublishInterval) {
            proximity = closestProximity
            lastPublishedProximity = closestProximity
            lastProximityUpdate = now
        }
    }

    func hide() {
        isVisible = false
        stopMagneticTracking()
        stopHealthChecks()

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

            // Heal from failed state: Refresh engine connection status when returning to idle
            // This ensures we don't stay in offline state after completing a recording
            refreshEngineState()
        }

        // Start/stop timer updates based on state transitions
        let wasActive = previousState == .listening || previousState == .transcribing
        let isActive = state == .listening || state == .transcribing
        if isActive && !wasActive {
            // Transition to active state - start timer updates
            startTimerUpdates()
        } else if !isActive && wasActive {
            // Transition to inactive state - stop timer updates
            stopTimerUpdates()
        }
    }

    /// Refresh engine connection state (call when we might have healed from a failed state)
    private func refreshEngineState() {
        let currentState = EngineClient.shared.connectionState
        let newIsConnected = (currentState == .connected || currentState == .connectedWrongBuild)

        if newIsConnected != self.isEngineConnected {
            pillLogger.debug("[Health Check] Engine state refreshed: \(currentState.rawValue), was: \(self.isEngineConnected), now: \(newIsConnected)")
            self.isEngineConnected = newIsConnected
            self.isWrongEngineBuild = (currentState == .connectedWrongBuild)
        }
    }

    // MARK: - Periodic Health Checks

    private func startHealthChecks() {
        stopHealthChecks()

        // Check engine health every 5 seconds to heal from transient failures
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEngineState()
            }
        }
    }

    private func stopHealthChecks() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    // Simple callback - just report the tap with current state and modifiers
    // Controller decides what action to take based on state
    var onTap: ((LiveState, NSEvent.ModifierFlags) -> Void)?

    func handleTap() {
        let modifiers = NSEvent.modifierFlags
        NSLog("[FloatingPill] handleTap: state=%@, modifiers=%d", state.rawValue, modifiers.rawValue)

        // Check if callback is set
        guard let callback = onTap else {
            NSLog("[FloatingPill] ⚠️ onTap callback is nil!")
            pillLogger.error("onTap callback not set - pill tap will not work")
            return
        }

        NSLog("[FloatingPill] Calling onTap callback...")
        callback(state, modifiers)
        NSLog("[FloatingPill] onTap callback completed")
    }

    /// Handle tap on the queue badge - retry or clear pending transcriptions
    func handleQueueTap() {
        let modifiers = NSEvent.modifierFlags
        NSLog("[FloatingPill] handleQueueTap: pendingCount=%d, modifiers=%d", pendingQueueCount, modifiers.rawValue)

        if modifiers.contains(.option) {
            // Option+click: Clear/dismiss pending items
            TranscriptionRetryManager.shared.clearPending()
            NSLog("[FloatingPill] Cleared pending transcriptions")
        } else {
            // Regular click: Retry pending transcriptions
            Task {
                await TranscriptionRetryManager.shared.retryFailedTranscriptions()
            }
            NSLog("[FloatingPill] Triggered retry of pending transcriptions")
        }
    }

    /// Toggle scratchpad mode when Shift is pressed on hover
    /// Called via LivePill's onShiftToggle callback
    func handleShiftToggle() {
        guard state == .listening else { return }
        guard let controller = liveController else {
            pillLogger.warning("handleShiftToggle: no liveController reference")
            return
        }

        // Toggle based on current state
        if controller.captureIntent == "Paste" {
            controller.setInterstitialIntent()
        } else {
            controller.clearIntent()
        }
        captureIntent = controller.captureIntent
        pillLogger.debug("Shift toggle: intent now \(self.captureIntent)")
    }

    // Reference to LiveController (set by AppDelegate)
    weak var liveController: LiveController?
}

// MARK: - Floating Pill View (expands when cursor approaches)

struct FloatingPillView: View {
    @EnvironmentObject var controller: FloatingPillController
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isHovered = false
    @State private var showDevInfo = false
    @State private var pidCopied = false
    @State private var tapFeedbackScale: CGFloat = 1.0
    @State private var slideInOpacity: Double = 0
    @State private var showPermissionWarning = false

    // Expansion threshold - only expand when very close (proximity > 0.7) or hovered
    private let expandThreshold: CGFloat = 0.7

    // Build info - executable modification date is more useful than version in dev
    private var buildInfo: String {
        // Get the executable's modification date (when it was built)
        if let execURL = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d HH:mm"  // e.g., "Dec 26 14:32"
            return formatter.string(from: modDate)
        }
        // Fallback to version
        return "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
    }

    private var isExpanded: Bool {
        controller.proximity > expandThreshold || isHovered
    }

    var body: some View {
        HStack(spacing: 6) {
            // Permission warning badge (appears when missing)
            if !permissionManager.allRequiredGranted && isExpanded {
                Button(action: { showPermissionWarning.toggle() }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Missing permissions - click to fix")
                .popover(isPresented: $showPermissionWarning, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Missing Permissions")
                            .font(.system(size: 12, weight: .semibold))

                        if permissionManager.microphoneStatus != .granted {
                            Label("Microphone not granted", systemImage: "mic.slash.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        if permissionManager.accessibilityStatus != .granted {
                            Label("Accessibility not granted", systemImage: "hand.raised.slash.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }

                        Button("Open Permissions...") {
                            showPermissionWarning = false
                            // Post notification to show permissions window
                            NotificationCenter.default.post(name: .showPermissionsWindow, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .frame(width: 200)
                }
            }

            LivePill(
                state: controller.state,
                isWarmingUp: false,
                showSuccess: false,
                recordingDuration: controller.elapsedTime,
                processingDuration: controller.processingTime,
                isEngineConnected: controller.isEngineConnected,
                pendingQueueCount: controller.pendingQueueCount,
                micDeviceName: AudioDeviceManager.shared.selectedDeviceName,
                audioLevel: controller.audioLevel,
                forceExpanded: isExpanded,
                identifier: "floating",
                captureIntent: controller.captureIntent,
                onTap: {
                    // Visual feedback - quick scale down/up
                    provideTapFeedback()
                    // Trigger actual handler
                    controller.handleTap()
                },
                onQueueTap: {
                    // Tap on queue badge - retry or clear (Option+click)
                    provideTapFeedback()
                    controller.handleQueueTap()
                },
                onShiftToggle: {
                    // Toggle scratchpad mode when Shift is pressed while hovering
                    controller.handleShiftToggle()
                }
            )
            .scaleEffect(tapFeedbackScale)

            // Dev info appears on Command+hover (build time + PID)
            if showDevInfo {
                HStack(spacing: 4) {
                    // Build timestamp (e.g., "Dec 26 14:32")
                    Text(buildInfo)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(TalkieTheme.textSecondary)

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textMuted)

                    // PID (clickable to copy)
                    Button(action: { copyPID() }) {
                        Text("PID \(ProcessInfo.processInfo.processIdentifier)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(pidCopied ? SemanticColor.success : TalkieTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy PID")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        // Frame must accommodate expanded state + dev info for proper hit testing
        .frame(width: showDevInfo ? 240 : 160, height: 30)
        // Center within the full 250px panel width
        .frame(width: 250, height: 30)
        .scaleEffect(slideInOpacity == 0 ? 0.8 : 1.0)  // Scale up instead of offset (stays in bounds)
        .opacity(slideInOpacity)
        .animation(.easeInOut(duration: 0.15), value: showDevInfo)
        .onAppear {
            // Animate in with scale + opacity (no offset to avoid out-of-bounds warnings)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                slideInOpacity = 1.0
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if !hovering {
                withAnimation { showDevInfo = false }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Command modifier while hovering to show dev info
                let commandHeld = NSEvent.modifierFlags.contains(.command)
                if commandHeld != showDevInfo {
                    withAnimation { showDevInfo = commandHeld }
                }
            case .ended:
                withAnimation { showDevInfo = false }
                pidCopied = false
            }
        }
    }

    private func copyPID() {
        let pid = ProcessInfo.processInfo.processIdentifier
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
        }
    }

    private func provideTapFeedback() {
        // Quick scale down, then bounce back
        withAnimation(.easeOut(duration: 0.1)) {
            tapFeedbackScale = 0.92
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                tapFeedbackScale = 1.0
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
