//
//  PasteChordController.swift
//  TalkieAgent
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

// MARK: - Paste chord key input

private struct PasteChordKeyInput: Sendable {
    let keyCode: UInt16
    let charactersIgnoringModifiers: String?
    let modifierFlagsRawValue: UInt

    init(event: NSEvent) {
        keyCode = event.keyCode
        charactersIgnoringModifiers = event.charactersIgnoringModifiers?.lowercased()
        modifierFlagsRawValue = event.modifierFlags.rawValue
    }

    init(event: CGEvent) {
        keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        charactersIgnoringModifiers = nil
        modifierFlagsRawValue = Self.modifierFlags(from: event.flags).rawValue
    }

    init(modifierFlags: NSEvent.ModifierFlags) {
        keyCode = 0
        charactersIgnoringModifiers = nil
        modifierFlagsRawValue = modifierFlags.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var isEscape: Bool { keyCode == 53 }
    var isTrayShortcut: Bool { keyCode == 13 || keyCode == 48 || charactersIgnoringModifiers == "w" }
    var isSystemScreenshotShortcut: Bool {
        guard let digit, [3, 4, 5].contains(digit) else { return false }
        let flags = normalizedModifierFlags
        return flags.contains(.command) && flags.contains(.shift) && !flags.contains(.option)
    }

    var pasteFormat: PasteFormat? {
        let flags = normalizedModifierFlags
        if flags.isEmpty { return .image }
        if flags == .shift { return .filePath }
        if flags == .option { return .url }
        if flags == .control { return .base64 }
        if flags == [.shift, .option] { return .visionDescription }
        if flags == .command { return .dragFile }
        if flags == [.command, .option, .control, .shift] { return .image }
        return nil
    }

    private var normalizedModifierFlags: NSEvent.ModifierFlags {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
    }

    var digit: Int? {
        switch keyCode {
        case 18, 83: return 1
        case 19, 84: return 2
        case 20, 85: return 3
        case 21, 86: return 4
        case 23, 87: return 5
        case 22, 88: return 6
        case 26, 89: return 7
        case 28, 91: return 8
        case 25, 92: return 9
        case 29, 82: return 0
        default:
            guard let charactersIgnoringModifiers,
                  charactersIgnoringModifiers.count == 1,
                  let digit = Int(charactersIgnoringModifiers) else { return nil }
            return digit
        }
    }

    func shouldConsumeForPasteChord(consumeAllKeys: Bool) -> Bool {
        if isSystemScreenshotShortcut { return false }
        return consumeAllKeys || isEscape || isTrayShortcut || (digit != nil && pasteFormat != nil)
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return modifiers
    }
}

// MARK: - CGEventTap Callback

private func pasteChordKeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown,
          let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<PasteChordController>.fromOpaque(refcon).takeUnretainedValue()
    guard controller.isKeyTapActive else {
        return Unmanaged.passUnretained(event)
    }

    let input = PasteChordKeyInput(event: event)
    guard input.shouldConsumeForPasteChord(consumeAllKeys: controller.keyTapConsumesAllKeys) else {
        return Unmanaged.passUnretained(event)
    }

    Task { @MainActor in
        controller.handleKeyTapInput(input)
    }

    return nil
}

@MainActor
final class PasteChordController {

    private let panel = PasteBarPanel()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var keyEventTap: CFMachPort?
    private var keyEventRunLoopSource: CFRunLoopSource?
    private var keyTapHandler: ((PasteChordKeyInput) -> Void)?
    private let timeoutSeconds: TimeInterval = 30

    // Thread-safe state read from the CGEventTap callback.
    private let keyTapLock = NSLock()
    private nonisolated(unsafe) var _isKeyTapActive = false
    private nonisolated(unsafe) var _keyTapConsumesAllKeys = false

    nonisolated var isKeyTapActive: Bool {
        get { keyTapLock.withLock { _isKeyTapActive } }
        set { keyTapLock.withLock { _isKeyTapActive = newValue } }
    }

    nonisolated var keyTapConsumesAllKeys: Bool {
        get { keyTapLock.withLock { _keyTapConsumesAllKeys } }
        set { keyTapLock.withLock { _keyTapConsumesAllKeys = newValue } }
    }

    func beginChord() async -> PasteBarResult? {
        let allItems = Self.recentLibraryCaptureItems(limit: 5)
        log.info("Quick Paste HUD shown", detail: "items=\(allItems.count)")

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
                PasteChordKeyInput(modifierFlags: mods).pasteFormat ?? .image
            }

            // Key handler
            let handleInput: (PasteChordKeyInput) -> Bool = { input in
                // Escape
                if input.isEscape {
                    timeout.cancel()
                    resume(nil)
                    return true
                }

                if input.isSystemScreenshotShortcut {
                    return false
                }

                // W or Tab used to open the tray viewer. The tray viewer is retired,
                // so this now just dismisses the empty picker.
                if input.isTrayShortcut {
                    timeout.cancel()
                    resume(nil)
                    return true
                }

                // Empty tray — any key dismisses
                if allItems.isEmpty {
                    timeout.cancel()
                    resume(nil)
                    return true
                }

                // Digit keys are consumed while the paste chord is active so
                // selection numbers do not leak into the focused app.
                if let digit = input.digit {
                    if digit >= 1, digit <= min(5, allItems.count) {
                        guard let format = input.pasteFormat else {
                            return false
                        }
                        let index = digit - 1
                        log.info("Quick Paste slot selected", detail: "slot=\(digit) format=\(format.rawValue)")
                        timeout.cancel()
                        resume(PasteBarResult(item: allItems[index], format: format))
                    } else {
                        resetTimeout()
                    }
                    return true
                }

                return false
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

            startKeyEventTap(consumeAllKeys: allItems.isEmpty, handler: handleInput)

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                _ = handleInput(PasteChordKeyInput(event: event))
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleInput(PasteChordKeyInput(event: event)) ? nil : event
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

    private static func recentLibraryCaptureItems(limit: Int) -> [AgentLiveTrayItem] {
        let records = UnifiedDatabase.recentCaptures(limit: max(limit * 3, limit))
        let items = records.compactMap { libraryPasteItem(from: $0) }
        return Array(items.prefix(limit))
    }

    private static func libraryPasteItem(from record: LiveRecording) -> AgentLiveTrayItem? {
        guard let assets = TalkieObjectAssets.from(json: record.assetsJSON) else {
            return nil
        }

        if let screenshot = assets.screenshots?.first,
           let fileURL = CaptureMediaFileResolver.screenshotURL(filename: screenshot.filename) {
            return AgentLiveTrayItem(
                id: record.id,
                kind: .screenshot,
                capturedAt: record.createdAt,
                filename: screenshot.filename,
                width: screenshot.width ?? 0,
                height: screenshot.height ?? 0,
                captureMode: screenshot.captureMode,
                windowTitle: screenshot.windowTitle,
                appName: screenshot.appName,
                appBundleID: screenshot.appBundleID,
                displayName: screenshot.displayName,
                ocrText: ocrText(for: screenshot.filename, in: assets),
                fileURL: fileURL
            )
        }

        if let clip = assets.clips?.first,
           let fileURL = CaptureMediaFileResolver.clipURL(filename: clip.filename) {
            return AgentLiveTrayItem(
                id: record.id,
                kind: .clip,
                capturedAt: record.createdAt,
                durationMs: clip.durationMs,
                filename: clip.filename,
                width: clip.width ?? 0,
                height: clip.height ?? 0,
                captureMode: clip.captureMode ?? "clip",
                windowTitle: clip.windowTitle,
                appName: clip.appName,
                appBundleID: nil,
                displayName: clip.displayName,
                fileURL: fileURL
            )
        }

        if let context = assets.visualContexts?.first,
           let fileURL = CaptureMediaFileResolver.visualContextSourceURL(for: context) {
            return AgentLiveTrayItem(
                id: record.id,
                kind: .clip,
                capturedAt: record.createdAt,
                durationMs: context.durationMs,
                filename: fileURL.lastPathComponent,
                width: context.width ?? 0,
                height: context.height ?? 0,
                captureMode: context.captureMode,
                windowTitle: context.windowTitle,
                appName: context.appName,
                appBundleID: nil,
                displayName: context.displayName,
                fileURL: fileURL
            )
        }

        return nil
    }

    private static func ocrText(for filename: String, in assets: TalkieObjectAssets) -> String? {
        assets.textProvenance?.first {
            $0.source == .ocr && ($0.sourceAssetId == nil || $0.sourceAssetId == filename)
        }?.originalText
    }

    private func startKeyEventTap(
        consumeAllKeys: Bool,
        handler: @escaping (PasteChordKeyInput) -> Bool
    ) {
        guard keyEventTap == nil else { return }

        keyTapHandler = { input in
            _ = handler(input)
        }
        keyTapConsumesAllKeys = consumeAllKeys

        let eventMask = 1 << CGEventType.keyDown.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: pasteChordKeyEventCallback,
            userInfo: refcon
        ) else {
            keyTapHandler = nil
            keyTapConsumesAllKeys = false
            log.warning("Failed to create paste chord event tap; selection digits may reach the focused app")
            return
        }

        keyEventTap = tap
        keyEventRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = keyEventRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        isKeyTapActive = true
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleKeyTapInput(_ input: PasteChordKeyInput) {
        keyTapHandler?(input)
    }

    private func stopKeyEventTap() {
        isKeyTapActive = false
        keyTapConsumesAllKeys = false
        keyTapHandler = nil

        if let tap = keyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = keyEventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        keyEventTap = nil
        keyEventRunLoopSource = nil
    }

    private func tearDown() {
        stopKeyEventTap()
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
