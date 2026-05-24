//
//  CaptureBarController.swift
//  Talkie
//
//  Unified chord controller for the capture bar.
//  Handles keyboard events, Tab mode cycling, timeout, and returns a CaptureBarResult.
//
//  Replaces ScreenshotChordController and ScreenRecordChordController.
//

import AppKit
import TalkieKit

@MainActor
final class CaptureBarController {

    private let panel = CaptureBarPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let timeoutSeconds: TimeInterval = 3

    /// Begin the unified capture chord flow.
    /// Shows the bar in the given mode and waits for user input.
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

            // Show the bar
            panel.show(
                mode: initialMode,
                showTrayOption: hasTrayItems,
                showSelectionOption: hasSelectionItems,
                trayCount: trayCount
            )

            // Timeout task — resets on every keypress
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
            var shouldIgnoreOpeningKey = true
            let handleKey: (NSEvent) -> Void = { [weak self] event in
                guard let self else { return }
                if shouldIgnoreOpeningKey {
                    shouldIgnoreOpeningKey = false
                    if event.isOpeningCaptureChordKey(initialMode: initialMode) {
                        resetTimeout()
                        return
                    }
                }
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
    }
}
