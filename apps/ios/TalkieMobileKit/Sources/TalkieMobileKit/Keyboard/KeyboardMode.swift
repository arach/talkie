//
//  KeyboardMode.swift
//  TalkieMobileKit
//
//  Mode = Content layer for keyboard slots
//

import Foundation

// MARK: - Mode (Content Layer)

/// A mode defines what content appears in each slot
public struct KeyboardMode: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String        // SF Symbol name
    public let slots: [Int: SlotConfig]
    public let isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        icon: String,
        slots: [Int: SlotConfig],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.slots = slots
        self.isBuiltIn = isBuiltIn
    }

    /// Get config for a slot, with fallback to empty
    public func config(for slot: Int) -> SlotConfig {
        slots[slot] ?? .empty
    }
}

// MARK: - Slot Configuration

/// What a single slot contains
public struct SlotConfig: Codable, Sendable, Equatable {
    public let type: SlotType
    public let label: String       // Display text
    public let content: String     // What gets inserted
    public let icon: String?       // SF Symbol (optional)

    public init(type: SlotType, label: String, content: String, icon: String? = nil) {
        self.type = type
        self.label = label
        self.content = content
        self.icon = icon
    }

    public enum SlotType: String, Codable, Sendable {
        case text       // Simple text insertion
        case snippet    // Multi-line or complex text
        case action     // Built-in action (copy, paste, etc)
        case space      // Space bar
        case empty      // Placeholder
    }

    // MARK: - Convenience Constructors

    public static func text(_ label: String, inserts content: String? = nil) -> SlotConfig {
        SlotConfig(type: .text, label: label, content: content ?? label, icon: nil)
    }

    public static func snippet(_ label: String, content: String, icon: String? = nil) -> SlotConfig {
        SlotConfig(type: .snippet, label: label, content: content, icon: icon)
    }

    public static func action(_ label: String, icon: String) -> SlotConfig {
        SlotConfig(type: .action, label: label, content: label, icon: icon)
    }

    public static let space = SlotConfig(type: .space, label: "SPACE", content: " ", icon: nil)
    public static let empty = SlotConfig(type: .empty, label: "", content: "", icon: nil)
}

// MARK: - Built-in Modes

extension KeyboardMode {
    /// Full QWERTY keyboard - triggers CompactKeyboardView overlay
    public static let abc = KeyboardMode(
        id: "abc",
        name: "ABC",
        icon: "keyboard",
        slots: [:],  // No slots - uses CompactKeyboardView
        isBuiltIn: true
    )

    /// Keyboard shortcuts and utility actions
    public static let fn = KeyboardMode(
        id: "fn",
        name: "Shortcuts",
        icon: "function",  // Function key symbol ƒ
        slots: [
            // Row B (1-4): Core actions (closest to DICTATE row)
            1: .action("TAB", icon: "arrow.right.to.line"),
            2: .action("COPY", icon: "doc.on.doc"),
            3: .action("PASTE", icon: "doc.on.clipboard"),
            4: .action("DEL", icon: "delete.left"),
            // Row C (5-8): ESC, Capitalize, SPACE, Punctuation
            5: .action("ESC", icon: "escape"),
            6: .action("Aa", icon: "textformat"),
            7: .space,
            8: .action("PUNC", icon: ""),  // Opens punctuation overlay
            // Row D (9-12): Quick inputs
            9: .text("Best", inserts: "Best regards,\n"),
            10: .text("@"),
            11: .text("Re:", inserts: "Re: "),
            12: .text("FYI", inserts: "FYI - "),
            // Dictate row flanking slots
            13: .action("SELECT", icon: "selection.pin.in.out"),
            14: .action("ENTER", icon: "return"),
        ],
        isBuiltIn: true
    )

    /// Legacy alias for shortcuts (now fn)
    public static var shortcuts: KeyboardMode { fn }

    /// Number pad
    public static let numbers = KeyboardMode(
        id: "numbers",
        name: "Numbers",
        icon: "number",
        slots: [
            // Row A (1-4): 1 2 3 ENTER (closest to DICTATE row)
            1: .text("1"),
            2: .text("2"),
            3: .text("3"),
            4: .action("ENTER", icon: "return"),
            // Row B (5-8): 4 5 6 +
            5: .text("4"),
            6: .text("5"),
            7: .text("6"),
            8: .text("+"),
            // Row C (9-12): 7 8 9 DEL
            9: .text("7"),
            10: .text("8"),
            11: .text("9"),
            12: .action("DEL", icon: "delete.left"),
            // Dictate row flanking slots: 0 and decimal
            13: .text("0"),
            14: .text("."),
        ],
        isBuiltIn: true
    )

    /// Punctuation and symbols
    public static let symbols = KeyboardMode(
        id: "symbols",
        name: "Symbols",
        icon: "textformat.abc",
        slots: [
            // Row A (1-4): Common punctuation
            1: .text("."),
            2: .text(","),
            3: .text("?"),
            4: .text("!"),
            // Row B (5-8): Quotes and common
            5: .text("'"),
            6: .text("\""),
            7: .text("-"),
            8: .text("@"),
            // Row C (9-12): Brackets and special
            9: .text("("),
            10: .text(")"),
            11: .text("/"),
            12: .action("DEL", icon: "delete.left"),
            // Dictate row flanking slots
            13: .action("SELECT", icon: "selection.pin.in.out"),
            14: .action("DEL", icon: "delete.left"),
        ],
        isBuiltIn: true
    )

    /// Emoji keyboard
    public static let emoji = KeyboardMode(
        id: "emoji",
        name: "Emoji",
        icon: "face.smiling",
        slots: [
            // Row A (1-4): Common reactions
            1: .text("👍"),
            2: .text("👎"),
            3: .text("❤️"),
            4: .text("😊"),
            // Row B (5-8): Expressions
            5: .text("😂"),
            6: .text("🙏"),
            7: .text("🔥"),
            8: .text("✨"),
            // Row C (9-12): Voice Search + Work
            9: .action("VOICE", icon: "mic.fill"),  // Voice emoji search (easy left-hand access)
            10: .text("❌"),
            11: .text("✅"),
            12: .text("💯"),
            // Dictate row flanking slots
            13: .action("SELECT", icon: "selection.pin.in.out"),
            14: .action("ENTER", icon: "return"),
        ],
        isBuiltIn: true
    )

    /// Minimal single-row layout: [slot1][slot2][ DICTATE ][slot3][slot4]
    /// Slot numbering: 1 and 2 are left of DICTATE, 3 and 4 are right
    public static let minimal = KeyboardMode(
        id: "minimal",
        name: "Minimal",
        icon: "minus",
        slots: [
            1: .action("COPY", icon: "doc.on.doc"),
            2: .action("PASTE", icon: "doc.on.clipboard"),
            3: .space,
            4: .action("ENTER", icon: "return"),
        ],
        isBuiltIn: true
    )

    /// All built-in modes (ABC typing, shortcuts, numbers, symbols, emoji)
    public static let builtIn: [KeyboardMode] = [abc, fn, numbers, symbols, emoji, minimal]
}

// MARK: - Keyboard Configuration

/// Complete user configuration for the keyboard
public struct KeyboardConfig: Codable, Sendable {
    /// Selected layout ID
    public var layoutId: String

    /// Ordered list of mode IDs (position = dial/gesture order)
    public var modeOrder: [String]

    /// Currently active mode ID
    public var activeModeId: String

    /// User-created custom modes
    public var customModes: [KeyboardMode]

    /// Ordered list of layout IDs for swipe cycling between layouts
    public var layoutOrder: [String]

    public init(
        layoutId: String = "compact",
        modeOrder: [String] = ["abc", "numbers", "fn", "symbols", "emoji"],  // Default visual order
        activeModeId: String = "fn",
        customModes: [KeyboardMode] = [],
        layoutOrder: [String] = ["compact", "minimal"]
    ) {
        self.layoutId = layoutId
        self.modeOrder = modeOrder
        self.activeModeId = activeModeId
        self.customModes = customModes
        self.layoutOrder = layoutOrder
    }

    /// Get the current layout
    public var layout: KeyboardLayout {
        KeyboardLayout.builtIn.first { $0.id == layoutId } ?? .compact
    }

    /// All modes in display order
    public var orderedModes: [KeyboardMode] {
        modeOrder.compactMap { id in
            KeyboardMode.builtIn.first { $0.id == id }
            ?? customModes.first { $0.id == id }
        }
    }

    /// Currently active mode
    public var activeMode: KeyboardMode {
        orderedModes.first { $0.id == activeModeId } ?? .abc
    }

    /// Cycle to next mode (for gestures)
    public mutating func cycleToNextMode() {
        let modes = orderedModes
        guard let currentIndex = modes.firstIndex(where: { $0.id == activeModeId }) else { return }
        let nextIndex = (currentIndex + 1) % modes.count
        activeModeId = modes[nextIndex].id
    }

    /// Cycle to previous mode (for gestures)
    public mutating func cycleToPreviousMode() {
        let modes = orderedModes
        guard let currentIndex = modes.firstIndex(where: { $0.id == activeModeId }) else { return }
        let prevIndex = (currentIndex - 1 + modes.count) % modes.count
        activeModeId = modes[prevIndex].id
    }

    /// Cycle to next layout in the layout order
    public mutating func cycleToNextLayout() {
        guard let currentIndex = layoutOrder.firstIndex(of: layoutId) else {
            if let first = layoutOrder.first { layoutId = first }
            return
        }
        let nextIndex = (currentIndex + 1) % layoutOrder.count
        layoutId = layoutOrder[nextIndex]
    }

    /// Cycle to previous layout in the layout order
    public mutating func cycleToPreviousLayout() {
        guard let currentIndex = layoutOrder.firstIndex(of: layoutId) else {
            if let first = layoutOrder.first { layoutId = first }
            return
        }
        let prevIndex = (currentIndex - 1 + layoutOrder.count) % layoutOrder.count
        layoutId = layoutOrder[prevIndex]
    }
}
