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

    struct TriggerResult: Equatable, Identifiable {
        enum Outcome: Equatable {
            case pending
            case running
            case succeeded
            case failed
        }

        let slotID: String
        let outcome: Outcome
        let message: String
        let completedAt: Date

        var id: String { "\(slotID)-\(completedAt.timeIntervalSince1970)" }

        var isTerminal: Bool {
            outcome == .succeeded || outcome == .failed
        }
    }

    /// Current board as ingested from the Mac. nil = no snapshot yet
    /// (paired but Mac hasn't shipped state, or unpaired).
    @Published private(set) var board: DeckBoardSnapshot?
    /// True while the last `fire(slotID:)` call is in flight. UI shows
    /// a brief pulse on the firing tile.
    @Published private(set) var firingSlotID: String?
    /// Set when the last fire failed; UI shows an inline banner.
    @Published private(set) var lastErrorMessage: String?
    /// Last optimistic or Mac-confirmed trigger result. UI surfaces this
    /// as transient feedback and highlights the matching tile.
    @Published private(set) var lastTriggerResult: TriggerResult?

    /// Most recent runtime state for an in-flight shortcut on the Mac
    /// — exposes `phase` (preparing/recording/processing), `elapsedSeconds`,
    /// and `signalLevel` so the cockpit can distinguish the recording
    /// window from the "Mac is transcribing" tail and show a timer.
    @Published private(set) var lastRuntimeState: CompanionShortcutRuntimeState?

    private var triggerResultResetTask: Task<Void, Never>?
    private var lastRecentResultKey: String?

    private init() {}

    /// Replace the board snapshot. Called by Codex from the bridge
    /// event-stream callback once it lands on iOS.
    func set(board: DeckBoardSnapshot?) {
        self.board = board
    }

    func apply(companionState: CompanionStateResponse?) {
        set(board: companionState?.resolvedCommandDeck)

        if let runtimeState = companionState?.shortcutStates?.first {
            lastRuntimeState = runtimeState
            let message = runtimeState.detail ?? runtimeState.phase.displayName
            setTriggerResult(
                slotID: runtimeState.shortcutId,
                outcome: .running,
                message: message,
                autoResetAfter: nil
            )
            return
        }
        // No active runtime: clear so the cockpit can exit "in-flight"
        // visuals (timer, phase-specific waveform state) cleanly.
        let hadActiveRuntime = lastRuntimeState != nil
        lastRuntimeState = nil

        guard let recentResult = companionState?.recentResults?.first else {
            clearRunningTriggerResultAfterRemoteIdle(hadActiveRuntime: hadActiveRuntime)
            return
        }
        let key = "\(recentResult.shortcutId)-\(recentResult.completedAt)"
        guard key != lastRecentResultKey else { return }

        lastRecentResultKey = key
        setTriggerResult(
            slotID: recentResult.shortcutId,
            outcome: .succeeded,
            message: recentResult.resultText,
            completedAt: Self.date(from: recentResult.completedAt),
            autoResetAfter: .seconds(4)
        )
    }

    private func clearRunningTriggerResultAfterRemoteIdle(hadActiveRuntime: Bool) {
        guard let lastTriggerResult,
              hadActiveRuntime || lastTriggerResult.outcome == .running,
              lastTriggerResult.outcome == .pending || lastTriggerResult.outcome == .running else {
            return
        }

        triggerResultResetTask?.cancel()
        triggerResultResetTask = nil
        self.lastTriggerResult = nil
    }

    /// Fire a slot on the paired Mac via the bridge. Keeps
    /// `firingSlotID` set for the duration of the round-trip so the
    /// deck tile still pulses while the Mac handles the command.
    func fire(slotID: String) {
        guard firingSlotID == nil else { return }
        firingSlotID = slotID
        lastErrorMessage = nil
        setTriggerResult(
            slotID: slotID,
            outcome: .pending,
            message: "Sent to Mac…",
            autoResetAfter: nil
        )
        Task { @MainActor in
            defer { firingSlotID = nil }

            do {
                let response = try await BridgeManager.shared.triggerCompanionShortcut(slotID)
                if response.ok == false {
                    let message = response.error ?? response.message ?? "Mac did not handle \(slotID)."
                    lastErrorMessage = message
                    setTriggerResult(
                        slotID: slotID,
                        outcome: .failed,
                        message: message,
                        autoResetAfter: .seconds(6)
                    )
                } else if let runtimeState = response.runtimeState {
                    setTriggerResult(
                        slotID: runtimeState.shortcutId,
                        outcome: .running,
                        message: runtimeState.detail ?? runtimeState.phase.displayName,
                        autoResetAfter: .seconds(4)
                    )
                } else {
                    setTriggerResult(
                        slotID: response.handledShortcutId ?? slotID,
                        outcome: .succeeded,
                        message: response.message ?? "Shortcut triggered on Mac.",
                        autoResetAfter: .seconds(4)
                    )
                }
            } catch {
                let message = error.localizedDescription
                lastErrorMessage = message
                setTriggerResult(
                    slotID: slotID,
                    outcome: .failed,
                    message: message,
                    autoResetAfter: .seconds(6)
                )
            }
        }
    }

    func pasteImageToMac(imageData: Data, mimeType: String, autoPaste: Bool = true) {
        let slotID = "mac-paste-image"
        guard firingSlotID == nil else { return }
        firingSlotID = slotID
        lastErrorMessage = nil
        setTriggerResult(
            slotID: slotID,
            outcome: .pending,
            message: "Sending image to Mac…",
            autoResetAfter: nil
        )

        Task { @MainActor in
            defer { firingSlotID = nil }

            do {
                let response = try await BridgeManager.shared.sendCompanionImageToMac(
                    imageData: imageData,
                    mimeType: mimeType,
                    autoPaste: autoPaste
                )
                if response.ok == false {
                    let message = response.error ?? response.message ?? "Mac did not accept the image."
                    lastErrorMessage = message
                    setTriggerResult(
                        slotID: slotID,
                        outcome: .failed,
                        message: message,
                        autoResetAfter: .seconds(6)
                    )
                } else {
                    setTriggerResult(
                        slotID: slotID,
                        outcome: .succeeded,
                        message: response.message ?? "Image sent to Mac.",
                        autoResetAfter: .seconds(4)
                    )
                }
            } catch {
                let message = error.localizedDescription
                lastErrorMessage = message
                setTriggerResult(
                    slotID: slotID,
                    outcome: .failed,
                    message: message,
                    autoResetAfter: .seconds(6)
                )
            }
        }
    }

    func reportLocalTriggerFailure(slotID: String, message: String) {
        lastErrorMessage = message
        setTriggerResult(
            slotID: slotID,
            outcome: .failed,
            message: message,
            autoResetAfter: .seconds(6)
        )
    }

    private func setTriggerResult(
        slotID: String,
        outcome: TriggerResult.Outcome,
        message: String,
        completedAt: Date = .now,
        autoResetAfter delay: Duration?
    ) {
        lastTriggerResult = TriggerResult(
            slotID: slotID,
            outcome: outcome,
            message: message,
            completedAt: completedAt
        )
        scheduleTriggerResultReset(after: delay)
    }

    private func scheduleTriggerResultReset(after delay: Duration?) {
        triggerResultResetTask?.cancel()
        guard let delay else { return }

        triggerResultResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.lastTriggerResult = nil
                self?.triggerResultResetTask = nil
            }
        }
    }

    private static func date(from value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .now
    }
}

private extension CompanionStateResponse {
    var resolvedCommandDeck: DeckBoardSnapshot? {
        if let commandDeck {
            return commandDeck
        }

        guard let shortcutPages, !shortcutPages.isEmpty else {
            return nil
        }

        let spaces = shortcutPages.enumerated().map { index, page in
            let trimmedID = page.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let spaceID = trimmedID.isEmpty ? "space-\(index + 1)" : trimmedID
            var slots = page.shortcutSlots.prefix(16).map { $0 }
            while slots.count < 16 {
                slots.append("")
            }

            return DeckSpace(
                id: spaceID,
                title: page.title,
                tiles: slots.enumerated().map { tileIndex, slotID in
                    let slot = slotID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let display = DeckLegacyDisplayInfo.display(for: slot)
                    return DeckTile(
                        id: "\(spaceID):\(tileIndex)",
                        slotID: slot.isEmpty ? nil : slot,
                        label: display.label,
                        icon: display.icon,
                        hint: display.hint
                    )
                }
            )
        }

        return DeckBoardSnapshot(
            spaces: spaces,
            activeSpaceID: spaces.first(where: { $0.id == "talkie" })?.id ?? spaces.first?.id
        )
    }
}

private enum DeckLegacyDisplayInfo {
    struct Display {
        let label: String
        let icon: String
        let hint: String?
    }

    static func display(for slotID: String) -> Display {
        switch slotID {
        case "talkie-dictate": return Display(label: "Dictate", icon: "waveform.badge.mic", hint: nil)
        case "talkie-record": return Display(label: "Memo", icon: "square.and.pencil", hint: nil)
        case "talkie-settings": return Display(label: "Voice", icon: "waveform.badge.plus", hint: nil)
        case "talkie-search": return Display(label: "Search", icon: "magnifyingglass", hint: nil)
        case "mac-claude": return Display(label: "Claude", icon: "sparkles", hint: "Mac")
        case "talkie-agent": return Display(label: "Pi", icon: "circle.grid.cross", hint: nil)
        case "talkie-ssh": return Display(label: "Shell", icon: "terminal", hint: nil)
        case "mac-sessions": return Display(label: "Workflow", icon: "wand.and.stars", hint: "Mac")
        case "mac-windows": return Display(label: "Desktop", icon: "display", hint: "Mac")
        case "talkie-keyboard": return Display(label: "Screen", icon: "record.circle", hint: nil)
        case "talkie-memos": return Display(label: "Memos", icon: "waveform", hint: nil)
        case "talkie-command": return Display(label: "Command", icon: "command", hint: nil)
        case "talkie-pending": return Display(label: "Pending", icon: "hourglass", hint: nil)
        case "talkie-recent": return Display(label: "Recent", icon: "clock.arrow.circlepath", hint: nil)
        case "talkie-home": return Display(label: "Home", icon: "house", hint: nil)
        case "talkie-devices": return Display(label: "Devices", icon: "ipad.and.iphone", hint: nil)
        case "mac-paste-image": return Display(label: "Share", icon: "photo.on.rectangle.angled", hint: "Mac")
        case "iterm-dictate": return Display(label: "iTerm", icon: "terminal.fill", hint: nil)
        case "":
            return Display(label: "-", icon: "square.dashed", hint: nil)
        default:
            let label = slotID
                .split(separator: "-")
                .last
                .map { String($0).capitalized } ?? "Command"
            return Display(label: label, icon: "square.grid.2x2", hint: nil)
        }
    }
}

private extension CompanionShortcutRuntimeState.Phase {
    var displayName: String {
        switch self {
        case .preparing: return "Preparing…"
        case .recording: return "Recording on Mac…"
        case .processing: return "Processing on Mac…"
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
