//
//  SessionLayoutManager.swift
//  Talkie
//
//  Manages draggable overlay positions for the current session
//  Positions reset on app restart or when session ends
//
//  Usage:
//  - Cmd+Drag to reposition overlays
//  - Cmd+L to lock/unlock layout
//  - Cmd+R to reset to defaults
//

import SwiftUI
import Combine
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "SessionLayout")

@MainActor
@Observable
final class SessionLayoutManager {
    static let shared = SessionLayoutManager()

    // MARK: - Published State

    var isLayoutLocked: Bool = false
    var isCommandHeld: Bool = false

    // Overlay positions (nil = use default)
    var onAirPosition: CGPoint?
    var pillPosition: CGPoint?
    var waveOverlayPosition: CGPoint?

    // Visual feedback
    var showDragHints: Bool = false

    // MARK: - Keyboard Monitoring

    @ObservationIgnored private var eventMonitor: Any?

    private init() {
        startMonitoringModifiers()
    }

    // MARK: - Position Management

    func setPosition(for overlay: OverlayType, position: CGPoint) {
        guard !isLayoutLocked else {
            logger.debug("Layout is locked, ignoring position change")
            return
        }

        switch overlay {
        case .onAir:
            onAirPosition = position
            logger.debug("ON AIR position: \(position.x), \(position.y)")
        case .pill:
            pillPosition = position
            logger.debug("Pill position: \(position.x), \(position.y)")
        case .waveOverlay:
            waveOverlayPosition = position
            logger.debug("Wave overlay position: \(position.x), \(position.y)")
        }
    }

    func getPosition(for overlay: OverlayType) -> CGPoint? {
        switch overlay {
        case .onAir: return onAirPosition
        case .pill: return pillPosition
        case .waveOverlay: return waveOverlayPosition
        }
    }

    func resetToDefaults() {
        onAirPosition = nil
        pillPosition = nil
        waveOverlayPosition = nil
        logger.info("Reset all overlay positions to defaults")
    }

    func toggleLock() {
        isLayoutLocked.toggle()
        logger.info("Layout \(self.isLayoutLocked ? "locked" : "unlocked")")
    }

    // MARK: - Modifier Key Monitoring

    private func startMonitoringModifiers() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updateModifierState(event.modifierFlags)
            }
            return event
        }
    }

    private func stopMonitoringModifiers() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func updateModifierState(_ flags: NSEvent.ModifierFlags) {
        let commandHeld = flags.contains(.command)

        if commandHeld != isCommandHeld {
            isCommandHeld = commandHeld
            showDragHints = commandHeld && !isLayoutLocked

            if commandHeld {
                logger.debug("⌘ Command held - overlays draggable")
            }
        }
    }
}

// MARK: - Overlay Types

enum OverlayType {
    case onAir
    case pill
    case waveOverlay
}

// MARK: - Draggable Overlay Modifier

struct DraggableOverlay: ViewModifier {
    let overlayType: OverlayType
    let defaultPosition: CGPoint

    @State private var layoutManager = SessionLayoutManager.shared
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var currentPosition: CGPoint {
        layoutManager.getPosition(for: overlayType) ?? defaultPosition
    }

    var showDragHint: Bool {
        layoutManager.showDragHints && !layoutManager.isLayoutLocked
    }

    func body(content: Content) -> some View {
        content
            .position(currentPosition)
            .overlay(alignment: .topLeading) {
                if showDragHint {
                    // Drag hint glow
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 2)
                        .shadow(color: .accentColor.opacity(0.3), radius: 4)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard layoutManager.isCommandHeld && !layoutManager.isLayoutLocked else { return }

                        if !isDragging {
                            isDragging = true
                        }

                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard layoutManager.isCommandHeld && !layoutManager.isLayoutLocked else {
                            dragOffset = .zero
                            isDragging = false
                            return
                        }

                        let newPosition = CGPoint(
                            x: currentPosition.x + dragOffset.width,
                            y: currentPosition.y + dragOffset.height
                        )

                        layoutManager.setPosition(for: overlayType, position: newPosition)
                        dragOffset = .zero
                        isDragging = false
                    }
            )
            .offset(isDragging ? dragOffset : .zero)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
}

extension View {
    func draggableOverlay(type: OverlayType, defaultPosition: CGPoint) -> some View {
        modifier(DraggableOverlay(overlayType: type, defaultPosition: defaultPosition))
    }
}

// MARK: - Global Keyboard Shortcuts

struct SessionLayoutKeyboardShortcuts: View {
    @State private var layoutManager = SessionLayoutManager.shared

    var body: some View {
        EmptyView()
            .onAppear {
                setupKeyboardShortcuts()
            }
    }

    private func setupKeyboardShortcuts() {
        // Cmd+L = Lock/Unlock Layout
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "l" {
                layoutManager.toggleLock()
                return nil // Consume event
            }

            // Cmd+R = Reset to Defaults
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "r" {
                layoutManager.resetToDefaults()
                return nil // Consume event
            }

            return event
        }
    }
}
