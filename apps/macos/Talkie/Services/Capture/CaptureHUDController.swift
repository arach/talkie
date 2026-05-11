//
//  CaptureHUDController.swift
//  Talkie
//
//  Chord controller for the HUD bar capture menu.
//  Same keyboard/mouse handling as CaptureRadialController, using CaptureHUDPanel.
//

import AppKit
import TalkieKit

@MainActor
final class CaptureHUDController: CaptureChordController {

    private let panel = CaptureHUDPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let timeoutSeconds: TimeInterval = 30
    private let cursorGracePeriod: TimeInterval = 0.6
    private let cursorPadding: CGFloat = 50

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

            panel.show(
                mode: initialMode,
                showTrayOption: hasTrayItems,
                showSelectionOption: hasSelectionItems,
                trayCount: trayCount
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

            self.panel.state.onAction = { result in
                if let result {
                    timeout.cancel()
                    resume(result)
                } else {
                    resetTimeout()
                }
            }

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

            var cursorDismissTask: Task<Void, Never>?

            let trackMouse: (NSEvent) -> Void = { [weak self] _ in
                guard let self, let panelFrame = self.panel.frame else { return }
                let mouseLocation = NSEvent.mouseLocation
                let zone = panelFrame.insetBy(dx: -self.cursorPadding, dy: -self.cursorPadding)

                if zone.contains(mouseLocation) {
                    cursorDismissTask?.cancel()
                    cursorDismissTask = nil
                } else if cursorDismissTask == nil {
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
