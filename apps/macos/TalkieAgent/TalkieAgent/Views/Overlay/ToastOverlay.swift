//
//  ToastOverlay.swift
//  TalkieAgent
//
//  Center-screen HUD for temporary alerts.
//  Appears mid-screen, auto-dismisses, click or tap action to dismiss.
//

import SwiftUI
import AppKit
import TalkieKit

private let log = Log(.ui)

// MARK: - Toast Model

struct ToastMessage: Equatable {
    let icon: String
    let text: String
    let detail: String?
    let actionLabel: String?
    let action: (() -> Void)?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.icon == rhs.icon && lhs.text == rhs.text && lhs.detail == rhs.detail && lhs.actionLabel == rhs.actionLabel
    }
}

struct SelectionFeedbackMessage: Equatable {
    enum Tone {
        case neutral
        case active
        case success
        case warning
        case failure

        var tint: Color {
            switch self {
            case .neutral: return Color.white.opacity(0.32)
            case .active: return Color.accentColor.opacity(0.9)
            case .success: return Color.green.opacity(0.85)
            case .warning: return Color.orange.opacity(0.9)
            case .failure: return Color.red.opacity(0.9)
            }
        }
    }

    let title: String
    let detail: String?
    let tone: Tone
    let actionTitle: String?
    let action: (() -> Void)?

    static func == (lhs: SelectionFeedbackMessage, rhs: SelectionFeedbackMessage) -> Bool {
        lhs.title == rhs.title &&
        lhs.detail == rhs.detail &&
        lhs.tone == rhs.tone &&
        lhs.actionTitle == rhs.actionTitle
    }
}

// MARK: - Notification

extension Notification.Name {
    static let pasteBlockedByPermission = Notification.Name("pasteBlockedByPermission")
}

// MARK: - Toast Controller

@MainActor
final class ToastOverlayController {
    static let shared = ToastOverlayController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: ToastMessage, duration: TimeInterval = 4.0) {
        // Dismiss any existing toast
        dismiss()

        guard let screen = NSScreen.main else { return }

        let toastView = ToastHUDView(message: message, onDismiss: { [weak self] in
            self?.dismiss()
        })
        let hostingView = NSHostingView(rootView: toastView)
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false

        // Center on screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        // Scale-in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        // Auto-dismiss
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }

        log.info("Toast shown: \(message.text)")
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }

    /// Show a permission-blocked HUD with a "Fix" action
    func showPermissionBlocked() {
        show(ToastMessage(
            icon: "lock.trianglebadge.exclamationmark.fill",
            text: "Paste Blocked",
            detail: "Accessibility permission required",
            actionLabel: "Open Settings",
            action: { [weak self] in
                self?.dismiss()
                NotificationCenter.default.post(name: .showPermissionsWindow, object: nil)
            }
        ))
    }
}

@MainActor
final class SelectionFeedbackOverlayController {
    static let shared = SelectionFeedbackOverlayController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: SelectionFeedbackMessage, duration: TimeInterval? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        if let panel {
            update(panel: panel, with: message)
        } else {
            createPanel(for: message)
        }

        if let duration {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }

    private func createPanel(for message: SelectionFeedbackMessage) {
        guard let screen = NSScreen.main else { return }

        let hostingView = NSHostingView(rootView: SelectionFeedbackHUDView(message: message))
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.alphaValue = 0
        panel.setFrameOrigin(origin(for: size, on: screen))
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        log.info("Selection HUD shown: \(message.title)")
    }

    private func update(panel: NSPanel, with message: SelectionFeedbackMessage) {
        let hostingView = NSHostingView(rootView: SelectionFeedbackHUDView(message: message))
        let size = hostingView.fittingSize

        panel.contentView = hostingView
        panel.setContentSize(size)
        if let screen = panel.screen ?? NSScreen.main {
            panel.setFrameOrigin(origin(for: size, on: screen))
        }
        if panel.alphaValue < 1 {
            panel.alphaValue = 1
        }
    }

    private func origin(for size: CGSize, on screen: NSScreen) -> NSPoint {
        let notchInfo = NotchInfo.detect()
        let visibleFrame = screen.visibleFrame
        let xCenter = notchInfo.hasNotch && notchInfo.screenFrame.equalTo(screen.frame)
            ? notchInfo.screenCenter
            : visibleFrame.midX
        let x = floor(xCenter - size.width / 2)
        let yInset: CGFloat = notchInfo.hasNotch ? 10 : 14
        let y = visibleFrame.maxY - size.height - yInset
        return NSPoint(x: x, y: y)
    }
}

// MARK: - HUD View (center-screen alert)

private struct ToastHUDView: View {
    let message: ToastMessage
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 10) {
            // Icon
            Image(systemName: message.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.orange)

            // Title
            Text(message.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))

            // Detail
            if let detail = message.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Action button
            if let actionLabel = message.actionLabel {
                Button(action: {
                    message.action?()
                }) {
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.6))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .opacity(isHovered ? 0.9 : 1.0)
        .onHover { isHovered = $0 }
        .onTapGesture {
            onDismiss()
        }
    }
}

private struct SelectionFeedbackHUDView: View {
    let message: SelectionFeedbackMessage
    @ObservedObject private var playbackController = SelectionSpeechPlaybackController.shared
    private let overlayTuning = OverlayTuning.shared

    var body: some View {
        AgentOverlay(
            animationStyle: animationStyle,
            animationDirection: .outbound,
            width: overlayWidth,
            height: overlayHeight,
            cornerRadius: cornerRadius,
            backgroundFill: backgroundFill,
            borderColor: borderColor,
            audioLevel: playbackController.audioLevel,
            controlVisibility: playbackControlsVisible ? .always : .hidden,
            content: AnyView(contentBody),
            leadingControl: playPauseControl,
            trailingControl: stopControl
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private var contentBody: some View {
        HStack {
            Spacer()

            VStack(spacing: message.detail == nil ? 0 : 2) {
                Text(message.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.7)
                    .foregroundColor(.white.opacity(0.96))

                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.35)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: statusPlateWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(statusPlate)

            Spacer()
        }
    }

    private var playPauseControl: AnyView? {
        guard playbackControlsVisible else { return nil }
        return AnyView(
            Button(action: { playbackController.togglePlayPause() }) {
                Image(systemName: playbackController.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(controlPlate)
            }
            .buttonStyle(.plain)
        )
    }

    private var stopControl: AnyView? {
        guard playbackControlsVisible else { return nil }
        return AnyView(
            Button(action: { playbackController.stop() }) {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(controlPlate)
            }
            .buttonStyle(.plain)
        )
    }

    private var playbackControlsVisible: Bool {
        message.tone == .active && playbackController.hasPlaybackSession
    }

    private var animationStyle: AgentOverlay.AnimationStyle {
        switch message.tone {
        case .active:
            return .particles(calm: false, speedMultiplier: 1.35)
        case .neutral:
            return .particles(calm: true, speedMultiplier: 0.55)
        case .success, .warning, .failure:
            return .none
        }
    }

    private var statusPlate: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
            )
    }

    private var controlPlate: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var backgroundFill: Color {
        Color(white: 0, opacity: overlayTuning.backgroundOpacity * 0.7)
    }

    private var borderColor: Color {
        switch message.tone {
        case .active:
            return AgentTheme.textSecondary.opacity(0.1)
        case .success:
            return Color.green.opacity(0.28)
        case .warning:
            return Color.orange.opacity(0.28)
        case .failure:
            return Color.red.opacity(0.32)
        case .neutral:
            return AgentTheme.textSecondary.opacity(0.1)
        }
    }

    private var cornerRadius: CGFloat {
        CGFloat(overlayTuning.cornerRadius)
    }

    private var overlayWidth: CGFloat {
        max(300, CGFloat(overlayTuning.overlayWidth) - 24)
    }

    private var overlayHeight: CGFloat {
        max(44, CGFloat(overlayTuning.overlayHeight) - 8)
    }

    private var statusPlateWidth: CGFloat {
        132
    }
}
