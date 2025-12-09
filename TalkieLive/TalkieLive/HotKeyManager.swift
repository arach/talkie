//
//  HotKeyManager.swift
//  TalkieLive
//

import Cocoa
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "HotKeyManager")

// MARK: - Global Registry

/// Shared registry for all hotkeys - uses a single Carbon event handler
private final class HotKeyRegistry {
    static let shared = HotKeyRegistry()

    private var callbacks: [HotKeyIdentifier: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var isInstalled = false

    private init() {}

    struct HotKeyIdentifier: Hashable {
        let signature: OSType
        let id: UInt32
    }

    func register(signature: OSType, id: UInt32, callback: @escaping () -> Void) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)
        callbacks[identifier] = callback
        logger.info("Registered callback for signature=\(signature) id=\(id)")

        installHandlerIfNeeded()
    }

    func unregister(signature: OSType, id: UInt32) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)
        callbacks.removeValue(forKey: identifier)
    }

    func handleEvent(signature: OSType, id: UInt32) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)
        logger.info("Looking up callback for signature=\(signature) id=\(id)")
        if let callback = callbacks[identifier] {
            logger.info("Found callback, firing!")
            callback()
        } else {
            logger.warning("No callback registered for this hotkey")
        }
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        isInstalled = status == noErr
        logger.info("Installed global event handler, status=\(status)")
    }
}

// Single global C callback
private func globalHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }

    logger.info("Hotkey event: signature=\(hotKeyID.signature) id=\(hotKeyID.id)")
    HotKeyRegistry.shared.handleEvent(signature: hotKeyID.signature, id: hotKeyID.id)

    return noErr
}

// MARK: - HotKeyManager

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?

    /// Unique signature and ID for this hotkey instance
    private let signature: String
    private let hotkeyID: UInt32

    /// Create a HotKeyManager with unique signature/ID to allow multiple instances
    init(signature: String = "TLIV", hotkeyID: UInt32 = 1) {
        self.signature = signature
        self.hotkeyID = hotkeyID
    }

    func registerHotKey(modifiers: UInt32, keyCode: UInt32, handler: @escaping () -> Void) {
        let sig = signature.fourCharCode

        logger.info("Registering hotkey: signature=\(self.signature)(\(sig)) id=\(self.hotkeyID) keyCode=\(keyCode) modifiers=\(modifiers)")

        // Register callback in shared registry
        HotKeyRegistry.shared.register(signature: sig, id: hotkeyID, callback: handler)

        // Register the actual hotkey with Carbon
        let hotKeyID = EventHotKeyID(signature: sig, id: hotkeyID)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        logger.info("RegisterEventHotKey status: \(registerStatus)")
    }

    func unregisterAll() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        HotKeyRegistry.shared.unregister(signature: signature.fourCharCode, id: hotkeyID)
    }

    deinit {
        unregisterAll()
    }
}

// String → OSType helper for "TLIV"
private extension String {
    var fourCharCode: OSType {
        var result: UInt32 = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + UInt32(scalar.value)
        }
        return OSType(result)
    }
}
