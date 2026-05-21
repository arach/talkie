//
//  DeckBoardSnapshot.swift
//  Talkie iOS
//
//  iOS-side mirror of the macOS Command Deck (4×4 shortcut grid per
//  Space). Paint pass — `DeckMirrorStore.shared` owns a mock board and
//  a fire-stub. Codex wires the real bridge:
//    1. Bridge companion event payload ships `DeckBoardSnapshot` from
//       Mac to iOS (extend the existing companion event stream in
//       `BridgeManager`).
//    2. `DeckMirrorStore.set(board:)` updates from the event stream.
//    3. `DeckMirrorStore.fire(slotID:)` calls into BridgeClient to
//       trigger the slot on Mac (the receiving side already exists in
//       `apps/macos/Talkie/Services/TalkieServer.swift` — `case
//       "deck-up":` etc.).
//

import Foundation

/// Full snapshot of the Command Deck as it stands on the paired Mac.
/// `activeSpaceID` reflects whichever Space the Mac is showing right
/// now; iOS displays that one selected by default but can pivot
/// between any Space without changing the Mac's selection.
struct DeckBoardSnapshot: Codable, Equatable {
    let spaces: [DeckSpace]
    let activeSpaceID: String?

    static let empty = DeckBoardSnapshot(spaces: [], activeSpaceID: nil)
}

struct DeckSpace: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let tiles: [DeckTile]   // 16 entries for the canonical 4×4 grid
}

struct DeckTile: Codable, Equatable, Identifiable {
    /// Stable per-position id (`spaceID:gridIndex`) — distinct from
    /// `slotID` because an unbound tile has no slot but still needs a
    /// stable identity for SwiftUI diffing.
    let id: String
    /// Slot identifier that the Mac handler dispatches on (e.g.
    /// "talkie-dictate", "deck-up", "mac-paste-image"). `nil` = empty
    /// tile / placeholder.
    let slotID: String?
    /// Display label shown on the tile. Mac resolves this from its
    /// shortcut catalog; iOS just renders it.
    let label: String
    /// SF Symbol name for the tile icon.
    let icon: String
    /// Optional secondary hint shown under the label (e.g. keystroke
    /// hint, capture count). Nil = no subtitle.
    let hint: String?
}

@MainActor
final class DeckMirrorStore: ObservableObject {
    static let shared = DeckMirrorStore()

    /// Current board as ingested from the Mac. nil = no snapshot yet
    /// (paired but Mac hasn't shipped state, or unpaired).
    @Published private(set) var board: DeckBoardSnapshot?
    /// True while the last `fire(slotID:)` call is in flight. UI shows
    /// a brief pulse on the firing tile.
    @Published private(set) var firingSlotID: String?
    /// Set when the last fire failed; UI shows an inline banner.
    @Published private(set) var lastErrorMessage: String?

    private init() {}

    /// Replace the board snapshot. Called by Codex from the bridge
    /// event-stream callback once it lands on iOS.
    func set(board: DeckBoardSnapshot?) {
        self.board = board
    }

    /// Fire a slot on the paired Mac via the bridge. Keeps
    /// `firingSlotID` set for the duration of the round-trip so the
    /// deck tile still pulses while the Mac handles the command.
    func fire(slotID: String) {
        guard firingSlotID == nil else { return }
        firingSlotID = slotID
        lastErrorMessage = nil
        Task { @MainActor in
            defer { firingSlotID = nil }

            do {
                let response = try await BridgeManager.shared.client.companionTrigger(shortcutId: slotID)
                if response.ok == false {
                    lastErrorMessage = response.error ?? response.message ?? "Mac did not handle \(slotID)."
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Mock board (paint reference; replace via store.set(board:))

extension DeckBoardSnapshot {
    /// Mirrors the macOS `defaultLegacyShortcutSlots` order so paint
    /// shows the same 4×4 the user would see on the Mac. Labels +
    /// icons are paint-side approximations; Codex pulls the resolved
    /// display info from the Mac side once the payload lands.
    static let mock = DeckBoardSnapshot(
        spaces: [
            DeckSpace(
                id: "talkie",
                title: "Talkie",
                tiles: Self.mockTalkieTiles
            ),
            DeckSpace(
                id: "workspace",
                title: "Workspace",
                tiles: (0..<16).map { idx in
                    DeckTile(
                        id: "workspace:\(idx)",
                        slotID: nil,
                        label: "—",
                        icon: "square.dashed",
                        hint: nil
                    )
                }
            )
        ],
        activeSpaceID: "talkie"
    )

    private static let mockTalkieTiles: [DeckTile] = [
        ("talkie-dictate",      "Dictate",       "mic.fill",                    nil),
        ("talkie-record",       "Record",        "waveform",                    nil),
        ("talkie-settings",     "Settings",      "gearshape",                   nil),
        ("talkie-search",       "Search",        "magnifyingglass",             nil),
        ("mac-claude",          "Claude",        "sparkles",                    "Mac"),
        ("talkie-agent",        "Agent",         "person.crop.circle.fill",     nil),
        ("talkie-ssh",          "SSH",           "terminal.fill",               nil),
        ("mac-sessions",        "Sessions",      "rectangle.stack.fill",        "Mac"),
        ("mac-windows",         "Windows",       "macwindow",                   "Mac"),
        ("talkie-keyboard",     "Keyboard",      "keyboard",                    nil),
        ("talkie-memos",        "Memos",         "list.bullet.rectangle.fill",  nil),
        ("talkie-command",      "Command",       "command",                     nil),
        ("talkie-pending",      "Pending",       "clock",                       nil),
        ("talkie-recent",       "Recent",        "clock.arrow.circlepath",      nil),
        ("talkie-home",         "Home",          "house.fill",                  nil),
        ("mac-paste-image",     "Paste image",   "doc.on.clipboard.fill",       "Mac")
    ].enumerated().map { idx, raw in
        DeckTile(id: "talkie:\(idx)", slotID: raw.0, label: raw.1, icon: raw.2, hint: raw.3)
    }
}
