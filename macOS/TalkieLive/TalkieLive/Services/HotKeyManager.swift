//
//  HotKeyManager.swift
//  TalkieLive
//

import Cocoa
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "HotKeyManager")

// MARK: - Hotkey Event Type

enum HotKeyEventType {
    case pressed
    case released
}

// MARK: - Hotkey Timestamp

/// Captures the precise mach_absolute_time when a hotkey event is received
/// Used for accurate performance measurement from Carbon callback → recording start
struct HotKeyTimestamp {
    let machTicks: UInt64

    init() {
        self.machTicks = mach_absolute_time()
    }

    /// Convert to milliseconds elapsed since this timestamp
    func elapsedMs() -> Int {
        let now = mach_absolute_time()
        return Self.ticksToMs(now - machTicks)
    }

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func ticksToMs(_ ticks: UInt64) -> Int {
        let nanos = ticks * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        return Int(nanos / 1_000_000)
    }
}

// MARK: - Global Registry

/// Shared registry for all hotkeys - uses a single Carbon event handler
private final class HotKeyRegistry {
    static let shared = HotKeyRegistry()

    /// Press callbacks now receive the precise timestamp from the Carbon callback
    private var pressCallbacks: [HotKeyIdentifier: (HotKeyTimestamp) -> Void] = [:]
    private var releaseCallbacks: [HotKeyIdentifier: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var isInstalled = false

    /// Track which hotkeys are currently "down" to filter out key repeats
    private var keysCurrentlyDown: Set<HotKeyIdentifier> = []

    private init() {}

    struct HotKeyIdentifier: Hashable {
        let signature: OSType
        let id: UInt32
    }

    func register(signature: OSType, id: UInt32, onPress: @escaping (HotKeyTimestamp) -> Void, onRelease: (() -> Void)? = nil) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)
        pressCallbacks[identifier] = onPress
        if let onRelease = onRelease {
            releaseCallbacks[identifier] = onRelease
        }
        logger.info("Registered callback for signature=\(signature) id=\(id) hasRelease=\(onRelease != nil)")

        installHandlerIfNeeded()
    }

    func unregister(signature: OSType, id: UInt32) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)
        pressCallbacks.removeValue(forKey: identifier)
        releaseCallbacks.removeValue(forKey: identifier)
    }

    func handleEvent(signature: OSType, id: UInt32, eventType: HotKeyEventType, timestamp: HotKeyTimestamp) {
        let identifier = HotKeyIdentifier(signature: signature, id: id)

        switch eventType {
        case .pressed:
            // Filter out key repeats - only fire on initial press
            guard !keysCurrentlyDown.contains(identifier) else {
                logger.debug("Ignoring key repeat for signature=\(signature) id=\(id)")
                return
            }
            keysCurrentlyDown.insert(identifier)

            if let callback = pressCallbacks[identifier] {
                logger.info("Hotkey pressed: signature=\(signature) id=\(id)")
                callback(timestamp)
            } else {
                logger.warning("No press callback registered for this hotkey")
            }
        case .released:
            keysCurrentlyDown.remove(identifier)

            if let callback = releaseCallbacks[identifier] {
                logger.info("Hotkey released: signature=\(signature) id=\(id)")
                callback()
            }
            // No warning for missing release - it's optional
        }
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else { return }

        // Register for both press and release events
        var eventSpecs: [EventTypeSpec] = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            2,  // Now handling 2 event types
            &eventSpecs,
            nil,
            &eventHandlerRef
        )

        isInstalled = status == noErr
        logger.info("Installed global event handler (press+release), status=\(status)")
    }
}

// Single global C callback
private func globalHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    // CRITICAL: Capture timestamp IMMEDIATELY at Carbon callback entry
    // This is our most accurate measurement of when the hotkey was pressed
    let timestamp = HotKeyTimestamp()

    guard let event else { return noErr }

    // Determine event type (press or release)
    let eventKind = GetEventKind(event)
    let eventType: HotKeyEventType = eventKind == UInt32(kEventHotKeyReleased) ? .released : .pressed

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

    HotKeyRegistry.shared.handleEvent(signature: hotKeyID.signature, id: hotKeyID.id, eventType: eventType, timestamp: timestamp)

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

    /// Register a hotkey with press handler only (toggle mode)
    /// The handler receives a precise timestamp from the Carbon callback for performance measurement
    func registerHotKey(modifiers: UInt32, keyCode: UInt32, handler: @escaping (HotKeyTimestamp) -> Void) {
        registerHotKey(modifiers: modifiers, keyCode: keyCode, onPress: handler, onRelease: nil)
    }

    /// Register a hotkey with both press and release handlers (push-to-talk mode)
    /// The press handler receives a precise timestamp from the Carbon callback for performance measurement
    func registerHotKey(modifiers: UInt32, keyCode: UInt32, onPress: @escaping (HotKeyTimestamp) -> Void, onRelease: (() -> Void)?) {
        let sig = signature.fourCharCode

        logger.info("Registering hotkey: signature=\(self.signature)(\(sig)) id=\(self.hotkeyID) keyCode=\(keyCode) modifiers=\(modifiers) hasPTT=\(onRelease != nil)")

        // Register callbacks in shared registry
        HotKeyRegistry.shared.register(signature: sig, id: hotkeyID, onPress: onPress, onRelease: onRelease)

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

        if registerStatus == noErr {
            logger.info("✓ RegisterEventHotKey SUCCESS: keyCode=\(keyCode) modifiers=\(modifiers)")
        } else {
            logger.error("❌ RegisterEventHotKey FAILED: status=\(registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")
        }
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
