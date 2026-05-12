//
//  FloatingPill.swift
//  TalkieAgent
//
//  Always-visible floating indicator pill - appears on all screens
//

import SwiftUI
import TalkieKit
import AppKit
import Combine
import os

private let pillLogger = Logger(subsystem: "to.talkie.app.agent", category: "FloatingPill")

// Notification for showing permissions window
extension Notification.Name {
    static let showPermissionsWindow = Notification.Name("showPermissionsWindow")
}

// MARK: - NSScreen Extension (Safe Display Access)

extension NSScreen {
    private static let overlayPlacementMargin: CGFloat = 6

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

    /// Check if this screen is an iPad connected via Sidecar
    /// Sidecar displays may include "iPad" in their localizedName (e.g. "Arach's iPad")
    /// or be named "Sidecar Display (AirPlay)" depending on connection method
    var isSidecar: Bool {
        guard isValid else { return false }
        let name = localizedName
        return name.localizedCaseInsensitiveContains("iPad") ||
               name.localizedCaseInsensitiveContains("Sidecar")
    }

    /// `visibleFrame` is occasionally reported in screen-local coordinates on secondary displays.
    /// Normalize it back into the global desktop space so placement is consistent across monitors.
    var correctedVisibleFrame: CGRect {
        let screenFrame = frame
        let visibleFrame = self.visibleFrame
        let centerDelta = abs(visibleFrame.midX - screenFrame.midX)
        guard centerDelta > 200 else { return visibleFrame }

        var corrected = visibleFrame
        corrected.origin.x += screenFrame.minX
        corrected.origin.y += screenFrame.minY
        return corrected
    }

    /// Shared placement rect for draggable overlays.
    /// We use the full physical screen width and bottom edge so settings map directly to what
    /// the user sees, but keep the top edge beneath the menu bar / notch region.
    func overlayPlacementFrame(edgeMargin: CGFloat = NSScreen.overlayPlacementMargin) -> CGRect {
        let screenFrame = frame
        let visibleFrame = correctedVisibleFrame
        let minX = screenFrame.minX + edgeMargin
        let maxX = max(minX, screenFrame.maxX - edgeMargin)
        let minY = screenFrame.minY + edgeMargin
        let maxY = max(
            minY,
            min(screenFrame.maxY - edgeMargin, visibleFrame.maxY - edgeMargin)
        )

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}

// MARK: - Floating Pill Controller

@MainActor
final class FloatingPillController: ObservableObject {
    static let shared = FloatingPillController()

    private var windows: [NSWindow] = []
    private var timerUpdateTimer: Timer?  // 1Hz timer for elapsed time display during recording
    private var healthCheckTimer: Timer?  // Periodic health check to heal from failed states
    private var recordingStartTime: Date?
    private var processingStartTime: Date?
    private var settingsCancellables = Set<AnyCancellable>()

    @Published var state: LiveState = .idle
    @Published var isVisible: Bool = true
    @Published var elapsedTime: TimeInterval = 0
    @Published var processingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0  // Throttled to 2Hz for UI (just sign of life)

    /// Brief error message shown as a toast near the pill, auto-clears after a few seconds
    @Published var errorMessage: String?
    private var errorDismissTask: Task<Void, Never>?

    /// Brief neutral message shown near the pill for proactive recovery/status.
    @Published var noticeMessage: String?
    private var noticeDismissTask: Task<Void, Never>?

    // Engine & queue status
    @Published var isEngineConnected: Bool = false
    @Published var isWrongEngineBuild: Bool = false
    @Published var pendingQueueCount: Int = 0

    // Capture intent (for showing scratchpad indicator on pill)
    @Published var captureIntent: String = "Paste"

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

        LiveSettings.shared.$pillPlacement
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    if self?.isVisible == true {
                        self?.repositionAllPills()
                    }
                }
            }
            .store(in: &settingsCancellables)

        LiveSettings.shared.$pillEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        self?.show()
                    } else {
                        self?.hide()
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

    /// Show a brief error message near the pill that auto-dismisses
    func showError(_ message: String, duration: TimeInterval = 4) {
        noticeDismissTask?.cancel()
        noticeMessage = nil
        errorDismissTask?.cancel()
        errorMessage = message
        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.errorMessage = nil
            }
        }
    }

    /// Show a brief neutral message near the pill that auto-dismisses
    func showNotice(_ message: String, duration: TimeInterval = 3) {
        errorDismissTask?.cancel()
        errorMessage = nil
        noticeDismissTask?.cancel()
        noticeMessage = message
        noticeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.noticeMessage = nil
            }
        }
    }

    func show() {
        guard LiveSettings.shared.pillEnabled else {
            hide()
            return
        }

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

        // Create pills based on settings
        let showOnAllScreens = LiveSettings.shared.pillShowOnAllScreens
        let allScreens = showOnAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }

        // Filter out invalid/transitional screens to avoid display identifier errors
        let validScreens = allScreens.filter { $0.isValid }

        pillLogger.debug("[Screens] Total: \(allScreens.count), Valid: \(validScreens.count)")

        // Log all valid screens
        for (index, screen) in validScreens.enumerated() {
            let frame = screen.frame
            let visibleFrame = screen.correctedVisibleFrame
            let placementFrame = screen.overlayPlacementFrame()
            pillLogger.debug("""
                [Screen \(index)] \(screen.safeDisplayName)
                  Full frame: x=\(frame.minX), y=\(frame.minY), w=\(frame.width), h=\(frame.height)
                  Visible frame: x=\(visibleFrame.minX), y=\(visibleFrame.minY), w=\(visibleFrame.width), h=\(visibleFrame.height)
                  Placement frame: x=\(placementFrame.minX), y=\(placementFrame.minY), w=\(placementFrame.width), h=\(placementFrame.height)
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

        // Start periodic health checks (every 5 seconds)
        startHealthChecks()
    }

    private func createPill(on screen: NSScreen) {
        let pillOverrides = OverlayIndicatorOverridesStore.shared
        let contentAlignment: Alignment
        switch LiveSettings.shared.pillPosition {
        case .bottomLeft:
            contentAlignment = .leading
        case .bottomRight:
            contentAlignment = .trailing
        case .bottomCenter, .topCenter:
            contentAlignment = .center
        }

        // Keep enough headroom for expanded/pulsing states without creating an
        // oversized transparent hit target around the pill.
        let pillWidth = pillOverrides.pillWidth(fallback: 160)
        let developerWidth = pillOverrides.pillDeveloperWidth(fallback: 240)
        let maxPillHitWidth = pillOverrides.pillHitWidth(fallback: 144)
        let pillHeight = pillOverrides.pillHeight(fallback: 20)
        let hostingWidth = max(maxPillHitWidth, max(pillWidth, developerWidth))
        let pillView = FloatingPillView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        let hostingView = NSHostingView(rootView: pillView.environmentObject(self))
        hostingView.frame = NSRect(x: 0, y: 0, width: hostingWidth, height: pillHeight)

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
        let position = calculateHomePosition(for: panel, on: screen)
        panel.setFrameOrigin(position)

        let positioningFrame = screen.overlayPlacementFrame()
        let anchorPoint = LiveSettings.shared.pillPlacement.screenAnchorPoint(in: positioningFrame)

        // Log the final pill position
        pillLogger.debug("""
            [Pill Position] \(screen.safeDisplayName)
              Panel position: x=\(position.x), y=\(position.y)
              Anchor point: x=\(anchorPoint.x), y=\(anchorPoint.y)
              Placement: x=\(LiveSettings.shared.pillPlacement.x), y=\(LiveSettings.shared.pillPlacement.y)
            """
        )

        panel.orderFront(nil)
        windows.append(panel)
    }

    private func calculateHomePosition(for panel: NSWindow, on screen: NSScreen) -> NSPoint {
        let positioningFrame = screen.overlayPlacementFrame()
        let origin = LiveSettings.shared.pillPlacement.origin(
            in: positioningFrame,
            itemSize: panel.frame.size
        )
        return NSPoint(x: floor(origin.x), y: floor(origin.y))
    }

    private func repositionAllPills() {
        // Rebuild pills when screen config changes
        if isVisible {
            show()
        }
    }

    // MARK: - Timer Updates (for elapsed time display)

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

    private func updateElapsedTime() {
        if let start = recordingStartTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
        if let start = processingStartTime {
            processingTime = Date().timeIntervalSince(start)
        }
    }

    func hide() {
        isVisible = false
        stopTimerUpdates()
        stopHealthChecks()

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
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
        } else if state == .refining {
            // Keep processing timer running (refining is a sub-phase of routing)
            if processingStartTime == nil {
                processingStartTime = Date()
            }
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
        let wasActive = previousState == .listening || previousState == .transcribing || previousState == .refining
        let isActive = state == .listening || state == .transcribing || state == .refining
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
    ///
    /// Behavior depends on current state:
    /// - Idle: Opens interstitial directly (quick path to scratchpad mode)
    /// - Listening: Toggles capture intent between Paste and Scratchpad
    func handleShiftToggle() {
        switch state {
        case .idle:
            // Shift+hover in idle = open interstitial directly for chill dictation
            pillLogger.info("Shift+hover in idle: opening interstitial directly")
            InterstitialPanelController.shared.showEmpty()

        case .listening:
            guard let controller = agentController else {
                pillLogger.warning("handleShiftToggle: no agentController reference")
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

        case .transcribing, .routing, .refining:
            // Don't interrupt processing states
            break
        }
    }

    // Reference to AgentController (set by AppDelegate)
    weak var agentController: AgentController?
}

// MARK: - Floating Pill View (expands when cursor approaches)

struct FloatingPillView: View {
    @EnvironmentObject var controller: FloatingPillController
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    private let overlayOverrides = OverlayIndicatorOverridesStore.shared
    @State private var isHovered = false
    @State private var showDevInfo = false
    @State private var pidCopied = false
    @State private var tapFeedbackScale: CGFloat = 1.0
    @State private var slideInOpacity: Double = 0
    @State private var showPermissionWarning = false

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
        isHovered
    }

    private var pillWidth: CGFloat {
        overlayOverrides.pillWidth(fallback: 160)
    }

    private var developerWidth: CGFloat {
        overlayOverrides.pillDeveloperWidth(fallback: 240)
    }

    private var pillHeight: CGFloat {
        overlayOverrides.pillHeight(fallback: 20)
    }

    private var currentWidth: CGFloat {
        showDevInfo ? max(developerWidth, pillWidth) : pillWidth
    }

    private var pillCornerRadius: CGFloat {
        max(8, pillHeight / 2)
    }

    private var warningOffsetY: CGFloat {
        (pillHeight / 2) + 13
    }

    private var errorOffsetY: CGFloat {
        (pillHeight / 2) + 21
    }

    var body: some View {
        HStack(spacing: 6) {
            // Permission warning badge (appears when missing)
            if !permissionManager.allRequiredGranted && isExpanded {
                Button(action: { showPermissionWarning.toggle() }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
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
                        Text(verbatim: "PID \(ProcessInfo.processInfo.processIdentifier)")
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
        // Silence warning overlay - appears below the pill when mic is silent
        .overlay(alignment: .bottom) {
            if controller.state == .listening && audioMonitor.isSilent {
                Button(action: {
                    AudioTroubleshooterController.shared.show()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.9))
                        Text("Check mic")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.cyan.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .offset(y: warningOffsetY)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: audioMonitor.isSilent)
            }
        }
        // Status toast - appears below the pill when recovery or errors need attention.
        .overlay(alignment: .bottom) {
            if let noticeMsg = controller.noticeMessage {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.9))
                    Text(noticeMsg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .offset(y: errorOffsetY)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.25), value: controller.noticeMessage)
                .onTapGesture {
                    withAnimation { controller.noticeMessage = nil }
                }
            } else if let errorMsg = controller.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                    Text(errorMsg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .offset(y: errorOffsetY)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.25), value: controller.errorMessage)
                .onTapGesture {
                    withAnimation { controller.errorMessage = nil }
                }
            }
        }
        // Frame tightly wraps the pill content - expanded for dev info, compact otherwise
        .frame(width: currentWidth, height: pillHeight)
        .contentShape(RoundedRectangle(cornerRadius: pillCornerRadius))
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
