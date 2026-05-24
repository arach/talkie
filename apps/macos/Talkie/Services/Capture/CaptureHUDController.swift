//
//  CaptureHUDController.swift
//  Talkie
//
//  Chord controller for the HUD bar capture menu.
//  Owns the keyboard chord lifecycle and forwards into CaptureHUDPanel.
//

import AppKit
import TalkieKit

@MainActor
final class CaptureHUDController: CaptureChordController {

    private let panel = CaptureHUDPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var paletteTask: Task<Void, Never>?
    private let timeoutSeconds: TimeInterval = 30

    func beginChord(initialMode: CaptureBarMode, options: CaptureChordOptions = .captureOnly) async -> CaptureBarResult? {
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

            // Draw immediately with the appearance fallback. Wallpaper sampling
            // uses ScreenCaptureKit, so it must never hold up showing the HUD.
            let expectedFrame = CaptureHUDPanel.expectedFrame(
                for: NSEvent.mouseLocation,
                position: SettingsManager.shared.captureHUDPosition
            )
            panel.show(
                mode: initialMode,
                showCameraOption: showCameraOption,
                showTrayOption: hasTrayItems,
                showSelectionOption: hasSelectionItems,
                trayCount: trayCount,
                palette: WallpaperLuminanceSampler.fallbackPalette()
            )
            paletteTask = Task { @MainActor [weak self] in
                let palette = await WallpaperLuminanceSampler.samplePalette(for: expectedFrame)
                guard !Task.isCancelled else { return }
                self?.panel.updatePalette(palette)
            }

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

            self.panel.state.onAction = { result in
                if let result {
                    timeout.cancel()
                    resume(result)
                } else {
                    resetTimeout()
                }
            }

            // The opening chord's keyDown can be delivered more than once
            // while the HUD is coming up. Ignore every still-held Hyper+S/R
            // event so it never gets mistaken for Screen/Record selection.
            let handleKey: (NSEvent) -> Void = { [weak self] event in
                guard let self else { return }
                if event.isOpeningCaptureChordKey(initialMode: initialMode) {
                    resetTimeout()
                    return
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

                if event.keyCode == 48 {  // Tab
                    self.panel.toggleMode()
                    resetTimeout()
                }

                if event.keyCode == 53 {  // Escape
                    timeout.cancel()
                    resume(nil)
                }
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
                return nil
            }
        }
    }

    // MARK: - Private

    private func tearDown() {
        paletteTask?.cancel()
        paletteTask = nil
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
