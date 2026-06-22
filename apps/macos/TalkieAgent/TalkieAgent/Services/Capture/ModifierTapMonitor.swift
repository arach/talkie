//
//  ModifierTapMonitor.swift
//  TalkieAgent
//
//  Fires on a *clean solitary tap* of a bare modifier key (left vs right
//  Control) anywhere system-wide — a conflict-free trigger that sidesteps the
//  crowded Hyper-chord space. Carbon hotkeys (HotKeyManager) can't bind a bare
//  modifier or tell left from right, so this uses NSEvent global + local
//  .flagsChanged monitors. It never suppresses the event: a tap that toggles
//  the ink layer still lets Ctrl behave normally.
//
//  The hard part is not firing during ordinary Ctrl use. The state machine only
//  fires when Ctrl was pressed and released *alone and quickly*: any keyDown,
//  mouseDown, or second modifier during the hold cancels the pending tap, and
//  release must land with no modifiers still held inside a short window. That
//  rejects Ctrl+click, Ctrl+key, chord-building, and Ctrl-held-for-drag.
//

import AppKit

@MainActor
final class ModifierTapMonitor {
    enum Side: Equatable {
        case leftControl
        case rightControl

        /// Physical virtual key code reported in .flagsChanged events
        /// (kVK_Control = 59, kVK_RightControl = 62).
        static func from(keyCode: UInt16) -> Side? {
            switch keyCode {
            case 59: return .leftControl
            case 62: return .rightControl
            default: return nil
            }
        }
    }

    /// Fires once per clean solitary tap of a watched side.
    var onTap: ((Side) -> Void)?

    private let watched: Set<Side>
    private let maxTapDuration: TimeInterval = 0.35
    private let modifierMask: NSEvent.ModifierFlags = [.control, .shift, .option, .command, .function]

    private var monitors: [Any] = []
    private var pendingSide: Side?
    private var pressTimestamp: TimeInterval = 0

    init(watching sides: Set<Side>) {
        self.watched = sides
    }

    func start() {
        stop()
        // Global monitors see events bound for *other* apps; local monitors see
        // events bound for our own overlay/panels. Both are needed so the taps
        // work whether or not the ink layer is key. Local handlers return the
        // event unmodified — we observe, never consume.
        addGlobal([.flagsChanged]) { [weak self] in self?.handleFlags($0) }
        addGlobal([.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in self?.cancel() }
        addLocal([.flagsChanged]) { [weak self] in self?.handleFlags($0) }
        addLocal([.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in self?.cancel() }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        cancel()
    }

    // MARK: - Monitor wiring

    private func addGlobal(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    private func addLocal(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(event)
            return event
        }
        if let monitor { monitors.append(monitor) }
    }

    // MARK: - State machine

    private func handleFlags(_ event: NSEvent) {
        guard let side = Side.from(keyCode: event.keyCode) else {
            // A non-Control modifier (shift/option/command/fn) changed — that
            // means Ctrl isn't being tapped alone. Drop any pending tap.
            cancel()
            return
        }

        let flags = event.modifierFlags.intersection(modifierMask)

        if flags.contains(.control) {
            // A control key just went down. Only a *solitary* control press is a
            // tap candidate; anything else held alongside it disqualifies it.
            if watched.contains(side), flags == [.control] {
                pendingSide = side
                pressTimestamp = event.timestamp
            } else {
                cancel()
            }
        } else {
            // A control key went up. Fire only if it's the same side we armed,
            // nothing else is held, and the press was brief.
            if let pending = pendingSide,
               pending == side,
               flags.isEmpty,
               event.timestamp - pressTimestamp <= maxTapDuration {
                cancel()
                onTap?(pending)
            } else {
                cancel()
            }
        }
    }

    private func cancel() {
        pendingSide = nil
    }
}
