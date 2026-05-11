//
//  CaptureRadialController.swift
//  Talkie
//
//  Chord controller for the radial capture menu.
//  Same keyboard handling as CaptureBarController, swapped to CaptureRadialPanel.
//

import AppKit
import TalkieKit

@MainActor
final class CaptureRadialController: CaptureChordController {

    private let panel = CaptureRadialPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let timeoutSeconds: TimeInterval = 30  // Long fallback only
    private let cursorGracePeriod: TimeInterval = 0.6
    private let cursorPadding: CGFloat = 50  // px beyond panel edge before dismiss

    /// Begin the capture chord flow with the radial menu.
    /// Shows the radial near the cursor and waits for user input.
    /// Returns the chosen result, or nil if cancelled/timed out.
    func beginChord(initialMode: CaptureBarMode) async -> CaptureBarResult? {
        let allItems = TrayItem.allItems()
        let hasTrayItems = !allItems.isEmpty
        let hasSelectionItems = SelectionTray.shared.isNotEmpty
        let trayCount = allItems.count

        return await withCheckedContinuation { continuation in
            var resumed = false

            let resume: (CaptureBarResult?) -> Void = { [weak self] result in
                guard !resumed else { return }
                resumed = true
                self?.tearDown()
                continuation.resume(returning: result)
            }

            // Show the radial
            panel.show(
                mode: initialMode,
                showTrayOption: hasTrayItems,
                showSelectionOption: hasSelectionItems,
                trayCount: trayCount
            )

            // Timeout task — resets on every keypress or click
            var timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(self.timeoutSeconds))
                resume(nil)
            }

            let resetTimeout: () -> Void = { [weak self] in
                guard let self else { return }
                timeout.cancel()
                timeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(self.timeoutSeconds))
                    resume(nil)
                }
            }

            // Wire click actions from the SwiftUI view
            self.panel.state.onAction = { result in
                if let result {
                    timeout.cancel()
                    resume(result)
                } else {
                    // nil = interaction without result (e.g. mode toggle), just reset timeout
                    resetTimeout()
                }
            }

            // Key handler shared by both monitors
            let handleKey: (NSEvent) -> Void = { [weak self] event in
                guard let self else { return }
                let key = event.charactersIgnoringModifiers?.lowercased()
                let currentMode = self.panel.state.mode

                switch key {
                case "a":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot: resume(.screenshot(.region))
                    case .video:      resume(.screenRecord(.region))
                    }

                case "s":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot: resume(.screenshot(.fullscreen))
                    case .video:      resume(.screenRecord(.fullscreen))
                    }

                case "d":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot: resume(.screenshot(.window))
                    case .video:      resume(.screenRecord(.window))
                    }

                case "c":
                    timeout.cancel()
                    resume(.toggleCamera)

                case "n":
                    if hasSelectionItems {
                        timeout.cancel()
                        resume(.saveSelection)
                    } else {
                        resetTimeout()
                    }

                case "f":
                    if hasTrayItems {
                        timeout.cancel()
                        resume(.pasteLastTray)
                    } else {
                        resetTimeout()
                    }

                case "w":
                    if hasTrayItems {
                        timeout.cancel()
                        resume(.viewTray)
                    } else {
                        resetTimeout()
                    }

                default:
                    break
                }

                // Tab toggles mode
                if event.keyCode == 48 {  // Tab
                    self.panel.toggleMode()
                    resetTimeout()
                }

                // Escape cancels
                if event.keyCode == 53 {
                    timeout.cancel()
                    resume(nil)
                }
            }

            // Global: catches keystrokes when another app is focused
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
            }

            // Local: catches keystrokes when Talkie is focused
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
                return nil  // consume the event
            }

            // Mouse tracking — dismiss when cursor leaves the zone
            var cursorDismissTask: Task<Void, Never>?

            let trackMouse: (NSEvent) -> Void = { [weak self] _ in
                guard let self, let panelFrame = self.panel.frame else { return }
                let mouseLocation = NSEvent.mouseLocation
                let zone = panelFrame.insetBy(dx: -self.cursorPadding, dy: -self.cursorPadding)

                if zone.contains(mouseLocation) {
                    // Cursor is in zone — cancel any pending dismiss
                    cursorDismissTask?.cancel()
                    cursorDismissTask = nil
                } else if cursorDismissTask == nil {
                    // Cursor left zone — start grace period
                    cursorDismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(self.cursorGracePeriod))
                        guard !Task.isCancelled else { return }
                        timeout.cancel()
                        resume(nil)
                    }
                }
            }

            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
                trackMouse(event)
            }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                trackMouse(event)
                return event
            }
        }
    }

    // MARK: - Private

    private func tearDown() {
        panel.dismiss()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }
}
