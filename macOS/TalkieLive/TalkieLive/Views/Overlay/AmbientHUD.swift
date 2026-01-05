//
//  AmbientHUD.swift
//  TalkieLive
//
//  Futuristic floating HUD for ambient mode - shows activity log and live status.
//  Inspired by JARVIS - translucent, tech-forward, auto-appending activity log.
//

import SwiftUI
import AppKit
import TalkieKit

private let log = Log(.ui)

// MARK: - Activity Entry

/// An entry in the ambient activity log
struct AmbientActivityEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: ActivityType
    let message: String
    var result: String?

    enum ActivityType {
        case heard      // Raw transcript (what Whisper heard)
        case wake       // Wake phrase detected
        case command    // Command captured
        case cancelled  // Command cancelled
        case sent       // Sent to Talkie
        case system     // System message (enabled, disabled, etc.)

        var icon: String {
            switch self {
            case .heard: return "ear"
            case .wake: return "waveform.circle"
            case .command: return "text.bubble"
            case .cancelled: return "xmark.circle"
            case .sent: return "arrow.up.circle"
            case .system: return "gear"
            }
        }

        var color: Color {
            switch self {
            case .heard: return .white.opacity(0.4)  // Subtle - these are frequent
            case .wake: return .cyan
            case .command: return .green
            case .cancelled: return .orange
            case .sent: return .blue
            case .system: return .gray
            }
        }
    }

    static func heard(_ text: String) -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .heard, message: text)
    }

    static func wake() -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .wake, message: "Wake phrase detected")
    }

    static func command(_ text: String) -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .command, message: text)
    }

    static func cancelled() -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .cancelled, message: "Cancelled")
    }

    static func sent(_ command: String) -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .sent, message: command, result: "Sent to Talkie")
    }

    static func system(_ message: String) -> AmbientActivityEntry {
        AmbientActivityEntry(id: UUID(), timestamp: Date(), type: .system, message: message)
    }
}

// MARK: - HUD Controller

@MainActor
final class AmbientHUDController: ObservableObject {
    static let shared = AmbientHUDController()

    // MARK: - State

    @Published var isVisible: Bool = false
    @Published var currentState: AmbientState = .disabled
    @Published var liveTranscript: String = ""
    @Published var activityLog: [AmbientActivityEntry] = []

    private var window: NSWindow?
    private let maxLogEntries = 50  // Increased to show more transcript history

    // MARK: - Init

    private init() {}

    // MARK: - Window Management

    func show() {
        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let hudView = AmbientHUDView()
        let hostingView = NSHostingView(rootView: hudView.environmentObject(self))

        // Size for the activity log
        let width: CGFloat = 320
        let height: CGFloat = 400
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

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
        panel.isMovableByWindowBackground = false  // Fixed position like FloatingPill
        panel.hasShadow = false  // No shadow - cleaner native feel
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        // Position: top-left, flush to top edge
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.minX  // Flush to left edge
            let y = screenFrame.maxY - height  // Flush to top (just below menu bar)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.window = panel
        isVisible = true

        // Add system entry
        addActivity(.system("Ambient mode active"))
        log.info("Ambient HUD shown")
    }

    func hide() {
        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.window = nil
        })

        isVisible = false
        log.info("Ambient HUD hidden")
    }

    // MARK: - Activity Log

    func addActivity(_ entry: AmbientActivityEntry) {
        activityLog.insert(entry, at: 0)

        // Trim old entries
        if activityLog.count > maxLogEntries {
            activityLog = Array(activityLog.prefix(maxLogEntries))
        }
    }

    func updateLiveTranscript(_ text: String) {
        liveTranscript = text
    }

    func clearLog() {
        activityLog.removeAll()
    }
}

// MARK: - HUD View
//
// Design Philosophy: Native OS Layer
// - Fixed geometry - never changes size
// - All content always rendered
// - Opacity/blur modulation reveals content on hover
// - Feels like a layer of the desktop, not a window

struct AmbientHUDView: View {
    @EnvironmentObject var controller: AmbientHUDController
    @State private var isHovered = false

    // Fixed dimensions - never change
    private let hudWidth: CGFloat = 280
    private let hudHeight: CGFloat = 340

    // Visibility levels
    private var contentOpacity: Double { isHovered ? 1.0 : 0.15 }
    private var backgroundOpacity: Double { isHovered ? 0.7 : 0.08 }
    private var blurRadius: Double { isHovered ? 0 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible (more opaque at rest)
            headerView

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .opacity(contentOpacity)

            // Live transcript (during command capture)
            if controller.currentState == .command && !controller.liveTranscript.isEmpty {
                liveTranscriptView
            }

            // Activity log - always rendered, opacity modulated
            activityLogView
        }
        .frame(width: hudWidth, height: hudHeight, alignment: .top)
        .background(hudBackground)
        .blur(radius: blurRadius)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Header (always visible, more prominent)

    private var headerView: some View {
        HStack(spacing: 10) {
            // Status indicator - always visible
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .shadow(color: stateColor.opacity(0.8), radius: 4)
                .modifier(AmbientPulseModifier(isActive: controller.currentState == .listening || controller.currentState == .command))

            VStack(alignment: .leading, spacing: 1) {
                Text("AMBIENT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.cyan.opacity(isHovered ? 0.9 : 0.4))

                Text(controller.currentState.displayName.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(isHovered ? 0.5 : 0.2))
            }

            Spacer()

            // Recording indicator (command mode)
            if controller.currentState == .command {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("REC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }

            // Close button - only visible on hover
            Button(action: {
                AmbientSettings.shared.isEnabled = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Header is more visible even at rest
        .opacity(isHovered ? 1.0 : 0.5)
    }

    private var stateColor: Color {
        switch controller.currentState {
        case .disabled: return .gray
        case .listening: return .green
        case .command: return .orange
        case .processing: return .cyan
        case .cancelled: return .gray
        }
    }

    // MARK: - Live Transcript

    private var liveTranscriptView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)

                Text("CAPTURING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.orange)
            }

            Text(controller.liveTranscript)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Activity Log

    private var activityLogView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(controller.activityLog) { entry in
                    activityRow(entry)
                }
            }
        }
        .opacity(contentOpacity)
    }

    private func activityRow(_ entry: AmbientActivityEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: entry.type.icon)
                .font(.system(size: 10))
                .foregroundColor(entry.type.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                // Timestamp + message
                HStack(spacing: 6) {
                    Text(formatTime(entry.timestamp))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))

                    Text(entry.message)
                        .font(.system(size: 10))
                        .foregroundColor(entry.type == .heard ? .white.opacity(0.6) : .white.opacity(0.9))
                        .lineLimit(1)
                }

                // Result (if any)
                if let result = entry.result {
                    HStack(spacing: 4) {
                        Text("→")
                            .foregroundColor(.cyan.opacity(0.5))
                        Text(result)
                            .foregroundColor(.cyan.opacity(0.7))
                    }
                    .font(.system(size: 9))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Background (Native layer feel)

    private var hudBackground: some View {
        ZStack {
            // Base layer - modulated by hover state
            Color.black.opacity(backgroundOpacity)

            // Subtle accent gradient
            LinearGradient(
                colors: [
                    Color.cyan.opacity(isHovered ? 0.05 : 0.01),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Bottom fade (content fades out)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(backgroundOpacity * 0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }
        }
        // Only round bottom corners - top is flush with screen edge
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0
            )
        )
    }
}

// MARK: - Ambient Pulse Animation Modifier

struct AmbientPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? 1.2 : 1.0)
            .opacity(isPulsing && isActive ? 0.7 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
            .onChange(of: isActive) { _, newValue in
                if !newValue {
                    isPulsing = false
                } else {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    let controller = AmbientHUDController.shared
    controller.currentState = .listening
    controller.activityLog = [
        .heard("hey talky check my calendar"),
        .wake(),
        .command("Check my calendar for tomorrow"),
        .sent("Check my calendar for tomorrow"),
        .heard("hay talkie"),
        .heard("hey taki"),
        .heard("a talking about something"),
        .heard("hey talkie"),
        .wake(),
        .cancelled(),
        .system("Ambient mode active")
    ]

    return AmbientHUDView()
        .environmentObject(controller)
        .frame(width: 320, height: 400)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
