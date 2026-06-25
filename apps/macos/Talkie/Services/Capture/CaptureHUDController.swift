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
    private var armedRegionOverlay: ScreenCaptureOverlay?
    private var armedRegionTask: Task<Void, Never>?
    private let timeoutSeconds: TimeInterval = 30

    func beginChord(initialMode: CaptureBarMode, options: CaptureChordOptions = .captureOnly) async -> CaptureBarResult? {
        let allItems = TrayItem.allItems()
        let showCameraOption = options.showCameraOption && FeatureFlags.shared.enableCameraBubble
        let hasTrayItems = options.showTrayOption && !allItems.isEmpty
        let hasSelectionItems = options.showSelectionOption && SelectionTray.shared.isNotEmpty
        let showMarkupOption = options.showMarkupOption
        let trayCount = allItems.count

        let expectedFrame = CaptureHUDPanel.expectedFrame(
            for: NSEvent.mouseLocation,
            position: SettingsManager.shared.captureHUDPosition
        )
        let initialPalette = await WallpaperLuminanceSampler.samplePalette(for: expectedFrame)

        return await withCheckedContinuation { continuation in
            var resumed = false

            let resume: (CaptureBarResult?) -> Void = { [weak self] result in
                guard !resumed else { return }
                resumed = true
                self?.tearDown()
                continuation.resume(returning: result)
            }

            // Resolve the wallpaper palette before ordering the HUD so the
            // first visible frame does not repaint from fallback chrome into
            // the sampled scheme.
            panel.show(
                mode: initialMode,
                showCameraOption: showCameraOption,
                showTrayOption: hasTrayItems,
                showSelectionOption: hasSelectionItems,
                showMarkupOption: showMarkupOption,
                trayCount: trayCount,
                palette: initialPalette
            )

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

            let commitSelectedMode: () -> Void = { [weak self] in
                guard let self else { return }
                timeout.cancel()
                let selected = self.panel.state.selectedCaptureMode
                switch self.panel.state.mode {
                case .screenshot:
                    resume(self.screenshotResult(for: selected))
                case .video:
                    resume(.screenRecord(selected))
                }
            }

            self.panel.state.onStart = commitSelectedMode
            self.panel.state.onCancel = {
                timeout.cancel()
                resume(nil)
            }
            self.panel.state.onAction = { result in
                if let result {
                    timeout.cancel()
                    resume(result)
                } else {
                    self.syncArmedRegionOverlay(resume: resume)
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

                if event.keyCode == 123 || event.keyCode == 124 { // Left / Right Arrow
                    self.panel.state.mode = event.keyCode == 123 ? .screenshot : .video
                    self.syncArmedRegionOverlay(resume: resume)
                    resetTimeout()
                    return
                }

                switch key {
                case "a":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot:
                        resume(self.screenshotResult(for: .region))
                    case .video:      resume(.screenRecord(.region))
                    }

                case "s":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot: resume(self.screenshotResult(for: .fullscreen))
                    case .video:      resume(.screenRecord(.fullscreen))
                    }

                case "d":
                    timeout.cancel()
                    switch currentMode {
                    case .screenshot: resume(self.screenshotResult(for: .window))
                    case .video:      resume(.screenRecord(.window))
                    }

                case "m":
                    if showMarkupOption, currentMode == .screenshot {
                        self.panel.state.markupDestinationEnabled.toggle()
                        self.syncArmedRegionOverlay(resume: resume)
                    }
                    resetTimeout()

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

                if event.keyCode == 48 {  // Tab
                    self.panel.toggleMode()
                    self.syncArmedRegionOverlay(resume: resume)
                    resetTimeout()
                }

                if event.keyCode == 36 || event.keyCode == 76 {  // Return / Enter (keypad)
                    // Commit the preselected mode. The HUD highlights
                    // REGION by default, so ↵ on first open fires a
                    // region capture without needing the A keystroke.
                    commitSelectedMode()
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

            syncArmedRegionOverlay(resume: resume)
        }
    }

    // MARK: - Private

    private func screenshotResult(for mode: CaptureMode) -> CaptureBarResult {
        panel.state.markupDestinationEnabled ? .screenshotMarkup(mode) : .screenshot(mode)
    }

    private func screenshotRegionResult(for rect: CGRect) -> CaptureBarResult {
        panel.state.markupDestinationEnabled ? .screenshotMarkupRegion(rect) : .screenshotRegion(rect)
    }

    private func tearDown() {
        cancelArmedRegionOverlay()
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

    private func syncArmedRegionOverlay(resume: @escaping (CaptureBarResult?) -> Void) {
        guard panel.state.mode == .screenshot else {
            cancelArmedRegionOverlay()
            return
        }
        armRegionOverlayIfNeeded(resume: resume)
    }

    private func armRegionOverlayIfNeeded(resume: @escaping (CaptureBarResult?) -> Void) {
        guard armedRegionOverlay == nil else { return }

        let overlay = ScreenCaptureOverlay()
        armedRegionOverlay = overlay
        armedRegionTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let rect = await overlay.selectRegion(freezesDesktop: false)
            guard !Task.isCancelled else { return }
            if self?.armedRegionOverlay === overlay {
                self?.armedRegionOverlay = nil
                self?.armedRegionTask = nil
            }
            if let rect {
                resume(self?.screenshotRegionResult(for: rect))
            } else {
                resume(nil)
            }
        }
    }

    private func cancelArmedRegionOverlay() {
        armedRegionTask?.cancel()
        armedRegionTask = nil
        armedRegionOverlay?.cancel()
        armedRegionOverlay = nil
    }
}
