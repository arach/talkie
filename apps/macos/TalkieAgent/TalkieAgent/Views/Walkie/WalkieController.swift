//
//  WalkieController.swift
//  TalkieAgent
//
//  Owns the floating walkie instrument panel and the live session.
//  Press Hyper+T → panel blooms centered with `WalkieSession.beginTransmission()`.
//  Release → session runs the over → transcribe → LLM pipeline; the
//  panel STAYS VISIBLE through .thinking and .receiving so the user
//  can read the answer. Dismiss is explicit (Done button).
//
//  Panel resize is **event-driven**, not observation-driven. We watch
//  the session's phase and call `applyPanelSize(expanded:)` exactly
//  once per transition. (The previous KVO-on-preferredContentSize
//  approach produced an NSISEngine layout-cycle stack overflow when
//  the resize re-triggered SwiftUI layout which re-triggered the
//  observer.)
//

import AppKit
import Combine
import SwiftUI
import TalkieKit

private let log = Log(.ui)

private enum WalkiePanelGeometry {
    static let width: CGFloat = 640
    static let compactHeight: CGFloat = 290    // scope only
    static let expandedHeight: CGFloat = 520   // scope + response
}

@MainActor
final class WalkieController {
    static let shared = WalkieController()

    let session = WalkieSession()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<WalkieScopeView>?
    private var phaseSink: AnyCancellable?
    private var escapeMonitor: Any?
    private var clickOutsideMonitor: Any?

    private init() {
        // Drive panel size + visibility off the session's phase.
        // dropFirst() ignores the initial .ready that fires on subscribe.
        phaseSink = session.$phase
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase)
            }
    }

    /// Hyper+T pressed.
    func press() {
        session.beginTransmission()
        let panel = ensurePanel()
        // Reset to compact size each press; the phase sink will
        // expand it later if the pipeline produces a response.
        applyPanelSize(expanded: false, animated: false)
        centerPanel(panel, on: screenUnderCursor())
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        log.info("Walkie panel up", detail: "phase=transmitting")
    }

    /// Hyper+T released. Session drives the rest of the lifecycle —
    /// panel stays up until the session goes back to .ready.
    func release() {
        guard panel != nil else { return }
        log.info("Walkie release received", detail: "running pipeline")
        Task { @MainActor in
            await session.endTransmission()
        }
    }

    // MARK: - Phase changes

    private func handlePhaseChange(_ phase: WalkieScopePhase) {
        switch phase {
        case .ready:
            stopDismissMonitors()
            fadeOut()
        case .transmitting, .over:
            // Hotkey is held / just released — no dismiss yet.
            stopDismissMonitors()
            applyPanelSize(expanded: false, animated: true)
        case .thinking, .receiving, .error:
            // Reply (or error) phase — Escape / click-outside dismiss
            // become active.
            applyPanelSize(expanded: true, animated: true)
            startDismissMonitors()
        }
    }

    // MARK: - Dismiss monitors

    private func startDismissMonitors() {
        if escapeMonitor == nil {
            // Local monitor catches Escape when our app is active;
            // global monitor catches it when another app has focus.
            let handler: (NSEvent) -> Void = { [weak self] event in
                guard event.keyCode == 53 else { return }  // 53 = Escape
                Task { @MainActor in
                    self?.session.dismiss()
                }
            }
            escapeMonitor = [
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handler(event)
                    return event.keyCode == 53 ? nil : event  // swallow Escape locally
                },
                NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler),
            ]
        }

        if clickOutsideMonitor == nil {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self, let panel = self.panel, panel.isVisible else { return }
                    let mouse = NSEvent.mouseLocation
                    if !panel.frame.contains(mouse) {
                        self.session.dismiss()
                    }
                }
            }
        }
    }

    private func stopDismissMonitors() {
        if let monitors = escapeMonitor as? [Any] {
            for m in monitors {
                NSEvent.removeMonitor(m)
            }
        } else if let m = escapeMonitor {
            NSEvent.removeMonitor(m)
        }
        escapeMonitor = nil

        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
        }
        clickOutsideMonitor = nil
    }

    private func applyPanelSize(expanded: Bool, animated: Bool) {
        guard let panel, let hostingView else { return }
        let newHeight = expanded ? WalkiePanelGeometry.expandedHeight : WalkiePanelGeometry.compactHeight
        let frame = panel.frame
        if abs(frame.size.height - newHeight) < 0.5 { return }

        // Keep the panel's top edge stable so the scope doesn't jump
        // upward when the response section appears.
        let topY = frame.maxY
        let newFrame = NSRect(
            x: frame.origin.x,
            y: topY - newHeight,
            width: WalkiePanelGeometry.width,
            height: newHeight
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: WalkiePanelGeometry.width,
            height: newHeight
        )
        panel.setFrame(newFrame, display: true, animate: animated)
    }

    // MARK: - Panel construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let view = WalkieScopeView(session: session) { [weak self] in
            self?.session.dismiss()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: WalkiePanelGeometry.width,
            height: WalkiePanelGeometry.compactHeight
        )

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = false
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false

        panel = p
        hostingView = hosting
        return p
    }

    private func centerPanel(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: floor(frame.midX - size.width / 2),
            y: floor(frame.midY - size.height / 2 + frame.height * 0.08)
        )
        panel.setFrameOrigin(origin)
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
