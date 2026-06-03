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

/// Shared flag: true while a capture chord (the Hyper+S / Hyper+R bar) is on
/// screen and owns the keyboard. The app's single-key navigation reads this
/// and stands down — otherwise the chord's letter keys (A/S/D = region /
/// fullscreen / window) would *also* fire single-key nav (S → Screenshots,
/// D → Dictations) and change the screen behind the bar. Main-thread only.
enum CaptureChord {
    nonisolated(unsafe) static var isActive = false
}

@MainActor
final class CaptureBarController {

    private let panel = CaptureBarPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let timeoutSeconds: TimeInterval = 3

    /// Begin the unified capture chord flow.
    /// Shows the bar in the given mode and waits for user input.
    /// Returns the chosen result, or nil if cancelled/timed out.
    func beginChord(initialMode: CaptureBarMode, options: CaptureChordOptions = .captureOnly) async -> CaptureBarResult? {
        CaptureChord.isActive = true
        let allItems = TrayItem.allItems()
        let showCameraOption = options.showCameraOption && FeatureFlags.shared.enableCameraBubble
        let hasTrayItems = options.showTrayOption && !allItems.isEmpty
        let hasSelectionItems = options.showSelectionOption && SelectionTray.shared.isNotEmpty
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
                showCameraOption: showCameraOption,
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

            // Key handler shared by both monitors.
            // Ignore every still-held opening Hyper+S/R event. The keyDown can
            // repeat while the panel appears, and "S" is also the fullscreen
            // choice after the HUD is open.
            let handleKey: (NSEvent) -> Void = { [weak self] event in
                guard let self else { return }
                if event.isOpeningCaptureChordKey(initialMode: initialMode) {
                    resetTimeout()
                    return
                }
                let key = event.charactersIgnoringModifiers?.lowercased()
                let currentMode = self.panel.state.mode

                if event.keyCode == 123 || event.keyCode == 124 { // Left / Right Arrow
                    self.panel.state.mode = event.keyCode == 123 ? .screenshot : .video
                    resetTimeout()
                    return
                }

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
                    if showCameraOption {
                        timeout.cancel()
                        resume(.toggleCamera)
                    } else {
                        resetTimeout()
                    }

                case "n":
                    if hasSelectionItems {
                        timeout.cancel()
                        resume(.saveSelection)
                    } else {
                        resetTimeout()
                    }

                case "v", "f":
                    if hasTrayItems {
                        timeout.cancel()
                        resume(.pasteLastTray)
                    } else {
                        resetTimeout()
                    }

                case "t", "w":
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

                // Return / Enter commits the preselected capture mode
                // (REGION by default). Mirrors the HUD controller so
                // both surfaces share the picker affordance.
                if event.keyCode == 36 || event.keyCode == 76 {
                    timeout.cancel()
                    let selected = self.panel.state.selectedCaptureMode
                    switch self.panel.state.mode {
                    case .screenshot: resume(.screenshot(selected))
                    case .video:      resume(.screenRecord(selected))
                    }
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
        CaptureChord.isActive = false
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
