import Carbon.HIToolbox
import Testing
@testable import TalkieKit

@Test("Apple screenshot shortcuts are reserved")
func appleScreenshotShortcutsAreReserved() {
    let commandShift = UInt32(cmdKey | shiftKey)
    let commandControlShift = UInt32(cmdKey | controlKey | shiftKey)

    #expect(SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 20, modifiers: commandShift))
    #expect(SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 21, modifiers: commandShift))
    #expect(SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 23, modifiers: commandShift))
    #expect(SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 22, modifiers: commandControlShift))
}

@Test("Hyper screenshot shortcuts remain available")
func hyperScreenshotShortcutsRemainAvailable() {
    let hyper = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    #expect(!SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 20, modifiers: hyper))
    #expect(!SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 21, modifiers: hyper))
    #expect(!SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: 1, modifiers: hyper))
}
