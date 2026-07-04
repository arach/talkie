//
//  PasteChordController.swift
//  Talkie
//
//  Chord controller for Quick Paste (Hyper+V).
//  Shows PasteBarPanel near cursor, waits for digit 1-5 with optional modifier.
//
//  Dismissal: Escape, valid selection (1-5), click outside panel, or 30s timeout.
//  Panel is "sticky" — releasing Hyper keys does NOT dismiss it.
//

import AppKit
import TalkieKit

private let log = Log(.system)

@MainActor
final class PasteChordController {

    private let panel = PasteBarPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private let timeoutSeconds: TimeInterval = 30

    func beginChord() async -> PasteBarResult? {
        let allItems: [TrayItem] = []

        return await withCheckedContinuation { continuation in
            var resumed = false

            let resume: (PasteBarResult?) -> Void = { [weak self] result in
                guard !resumed else { return }
                resumed = true
                self?.tearDown()
                continuation.resume(returning: result)
            }

            panel.show(items: allItems)

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

            // Panel click callback
            self.panel.state.onAction = { result in
                if let result {
                    timeout.cancel()
                    resume(result)
                } else {
                    resetTimeout()
                }
            }

            // Determine format from modifier flags
            let formatFromMods: (NSEvent.ModifierFlags) -> PasteFormat = { mods in
                let cleaned = mods.intersection(.deviceIndependentFlagsMask)
                if cleaned.contains(.command) && !cleaned.contains(.shift) && !cleaned.contains(.option) && !cleaned.contains(.control) {
                    return .dragFile
                } else if cleaned.contains(.shift) && cleaned.contains(.option) && !cleaned.contains(.control) && !cleaned.contains(.command) {
                    return .visionDescription
                } else if cleaned.contains(.shift) && !cleaned.contains(.option) && !cleaned.contains(.control) && !cleaned.contains(.command) {
                    return .filePath
                } else if cleaned.contains(.option) && !cleaned.contains(.shift) && !cleaned.contains(.control) && !cleaned.contains(.command) {
                    return .url
                } else if cleaned.contains(.control) && !cleaned.contains(.shift) && !cleaned.contains(.option) && !cleaned.contains(.command) {
                    return .base64
                }
                return .image
            }

            // Key handler
            let handleKey: (NSEvent) -> Void = { event in
                let key = event.charactersIgnoringModifiers

                // Escape
                if event.keyCode == 53 {
                    timeout.cancel()
                    resume(nil)
                    return
                }

                // W or Tab used to open the tray viewer. The tray is retired,
                // so this now behaves like a plain dismissal.
                if key == "w" || event.keyCode == 48 /* Tab */ {
                    timeout.cancel()
                    resume(nil)
                    return
                }

                // Empty tray — any key dismisses
                if allItems.isEmpty {
                    timeout.cancel()
                    resume(nil)
                    return
                }

                // Digit 1-5
                if let key, let digit = Int(key), digit >= 1, digit <= min(5, allItems.count) {
                    let index = digit - 1
                    let format = formatFromMods(event.modifierFlags)
                    log.info("Quick Paste slot selected", detail: "slot=\(digit) format=\(format.rawValue)")
                    timeout.cancel()
                    resume(PasteBarResult(item: allItems[index], format: format))
                    return
                }
            }

            // Flags-changed handler — update active format indicator live
            let handleFlags: (NSEvent) -> Void = { [weak self] event in
                guard let self else { return }
                self.panel.state.activeFormat = formatFromMods(event.modifierFlags)
            }

            // Click outside panel — dismiss
            let handleClick: (NSEvent) -> Bool = { [weak self] event in
                guard let self, let panelFrame = self.panel.frame else { return false }
                let mouseLocation = NSEvent.mouseLocation
                if !panelFrame.contains(mouseLocation) {
                    timeout.cancel()
                    resume(nil)
                    return true  // consumed
                }
                return false
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event)
                return nil
            }

            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                handleFlags(event)
            }

            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                handleFlags(event)
                return event
            }

            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                _ = handleClick(event)
            }

            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                if handleClick(event) {
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Private

    private func tearDown() {
        panel.dismiss()
        for monitor in [globalMonitor, localMonitor, clickMonitor, localClickMonitor, flagsMonitor, localFlagsMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalMonitor = nil
        localMonitor = nil
        clickMonitor = nil
        localClickMonitor = nil
        flagsMonitor = nil
        localFlagsMonitor = nil
    }
}
