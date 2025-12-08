//
//  HotKeyManager.swift
//  TalkieLive
//

import Cocoa
import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let wrapper = HotKeyWrapper()   // always alive

    func registerHotKey(modifiers: UInt32, keyCode: UInt32, handler: @escaping () -> Void) {
        // Update callback on the persistent wrapper
        wrapper.callback = handler

        let hotKeyID = EventHotKeyID(
            signature: "TLIV".fourCharCode,
            id: 1
        )

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Pass the wrapper as userData so the global callback can call back into Swift
        let userData = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(wrapper).toOpaque()
        )

        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            userData,
            &handlerRef
        )

        self.eventHandlerRef = handlerRef

        // Register the actual hotkey
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregisterAll() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

// A simple wrapper object we can hand through Carbon as opaque userData
final class HotKeyWrapper {
    var callback: (() -> Void)?

    func fire() {
        callback?()
    }
}

// Global C-style callback for Carbon
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }

    let wrapper = Unmanaged<HotKeyWrapper>
        .fromOpaque(userData)
        .takeUnretainedValue()

    wrapper.fire()
    return noErr
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
