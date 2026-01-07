//
//  NotchOverlay.swift
//  TalkieLive
//
//  Dynamic Island-style overlay that appears around/below the notch
//  during recording. Provides visual feedback and quick controls.
//

import SwiftUI
import AppKit
import TalkieKit
import Combine

// MARK: - Notch Detection

struct NotchInfo {
    let hasNotch: Bool
    let notchRect: CGRect  // The notch area in screen coordinates
    let screenFrame: CGRect

    static func detect(for screen: NSScreen? = NSScreen.main) -> NotchInfo {
        guard let screen = screen else {
            return NotchInfo(hasNotch: false, notchRect: .zero, screenFrame: .zero)
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // The notch area is the difference between full frame and visible frame at the top
        // On notched MacBooks, safeAreaInsets.top > 0
        let topInset = screenFrame.maxY - visibleFrame.maxY
        let hasNotch = topInset > 24  // Menu bar is ~24pt, notch adds more

        // Notch is approximately centered, ~200pt wide, ~32pt tall
        let notchWidth: CGFloat = 200
        let notchHeight: CGFloat = 32
        let notchRect = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        return NotchInfo(
            hasNotch: hasNotch,
            notchRect: notchRect,
            screenFrame: screenFrame
        )
    }
}

// MARK: - Notch Overlay Controller

@MainActor
final class NotchOverlayController: ObservableObject {
    static let shared = NotchOverlayController()

    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    // State
    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var isExpanded: Bool = false
    @Published var captureIntent: String = "Paste"

    // Notch info
    @Published var notchInfo: NotchInfo = NotchInfo(hasNotch: false, notchRect: .zero, screenFrame: .zero)

    private var recordingStartTime: Date?
    private var timer: Timer?

    private init() {
        // Detect notch on init
        notchInfo = NotchInfo.detect()

        // Listen for screen changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notchInfo = NotchInfo.detect()
                if self?.window != nil {
                    self?.updateWindowPosition()
                }
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

    // MARK: - Window Management

    func show() {
        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let overlayView = NotchOverlayView()
        let hostingView = NSHostingView(rootView: overlayView.environmentObject(self))

        // Size for collapsed state
        let collapsedSize = NSSize(width: 220, height: 36)
        hostingView.frame = NSRect(origin: .zero, size: collapsedSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar  // Above most windows, near menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false

        // Position below the notch
        updateWindowPosition(panel: panel)

        // Animate in
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.window = panel
        startTimer()
    }

    func hide() {
        stopTimer()
        recordingStartTime = nil
        elapsedTime = 0

        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }

    private func updateWindowPosition(panel: NSPanel? = nil) {
        let targetPanel = panel ?? window
        guard let panel = targetPanel else { return }

        notchInfo = NotchInfo.detect()

        // Position just below the notch, centered
        let panelWidth = panel.frame.width
        let x: CGFloat
        let y: CGFloat

        if notchInfo.hasNotch {
            // Center below the notch
            x = notchInfo.notchRect.midX - panelWidth / 2
            y = notchInfo.notchRect.minY - panel.frame.height - 4
        } else {
            // Center at top of screen (for non-notched displays)
            x = notchInfo.screenFrame.midX - panelWidth / 2
            y = notchInfo.screenFrame.maxY - panel.frame.height - 28  // Below menu bar
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - State Updates

    func updateState(_ state: LiveState) {
        let previousState = self.state
        self.state = state

        if state == .listening && previousState != .listening {
            recordingStartTime = Date()
            elapsedTime = 0
            show()
            startTimer()
        } else if state == .idle && previousState != .idle {
            // Brief delay to show completion state
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                if self.state == .idle {
                    hide()
                }
            }
        }

        // Expand during active recording, collapse during processing
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = (state == .listening)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    func requestStop() {
        onStop?()
    }

    func requestCancel() {
        onCancel?()
    }
}

// MARK: - Notch Overlay View

struct NotchOverlayView: View {
    @EnvironmentObject var controller: NotchOverlayController
    @State private var isHovered: Bool = false

    // Layout constants
    private let collapsedWidth: CGFloat = 180
    private let expandedWidth: CGFloat = 280
    private let collapsedHeight: CGFloat = 32
    private let expandedHeight: CGFloat = 44
    private let cornerRadius: CGFloat = 20

    private var currentWidth: CGFloat {
        controller.isExpanded ? expandedWidth : collapsedWidth
    }

    private var currentHeight: CGFloat {
        controller.isExpanded ? expandedHeight : collapsedHeight
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left side: Recording indicator
            recordingIndicator

            Spacer(minLength: 0)

            // Center: Status or waveform
            if controller.isExpanded {
                audioWaveform
                    .frame(height: 20)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            // Right side: Timer and controls
            rightControls
        }
        .padding(.horizontal, 12)
        .frame(width: currentWidth, height: currentHeight)
        .background(
            Capsule()
                .fill(.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.state)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            // Pulsing red dot
            Circle()
                .fill(recordingColor)
                .frame(width: 8, height: 8)
                .shadow(color: recordingColor.opacity(0.6), radius: 4)
                .modifier(NotchPulseModifier(isAnimating: controller.state == .listening))

            if controller.isExpanded {
                Text(controller.captureIntent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    private var recordingColor: Color {
        switch controller.state {
        case .listening:
            return .red
        case .transcribing:
            return .orange
        case .routing:
            return .green
        case .idle:
            return .gray
        }
    }

    // MARK: - Audio Waveform

    private var audioWaveform: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { index in
                    AudioBar(
                        level: controller.audioLevel,
                        index: index,
                        totalBars: 12
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Right Controls

    private var rightControls: some View {
        HStack(spacing: 8) {
            // Timer
            Text(formatTime(controller.elapsedTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            // Stop button (visible on hover or expanded)
            if isHovered || controller.isExpanded {
                Button(action: { controller.requestStop() }) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Bar

struct AudioBar: View {
    let level: Float
    let index: Int
    let totalBars: Int

    @State private var animatedHeight: CGFloat = 0.2

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: max(4, animatedHeight * 20))
            .animation(.easeOut(duration: 0.1), value: animatedHeight)
            .onAppear {
                updateHeight()
            }
            .onChange(of: level) { _, _ in
                updateHeight()
            }
    }

    private func updateHeight() {
        // Create variation across bars
        let centerIndex = totalBars / 2
        let distanceFromCenter = abs(index - centerIndex)
        let positionFactor = 1.0 - (CGFloat(distanceFromCenter) / CGFloat(centerIndex)) * 0.3

        // Random variation + audio level
        let randomFactor = CGFloat.random(in: 0.6...1.0)
        let audioFactor = CGFloat(level) * 2.0 + 0.2

        animatedHeight = min(1.0, audioFactor * positionFactor * randomFactor)
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
    VStack(spacing: 20) {
        NotchOverlayView()
            .environmentObject(NotchOverlayController.shared)
    }
    .frame(width: 400, height: 100)
    .background(Color.gray.opacity(0.3))
}
