//
//  HomeFeed.swift
//  Talkie iOS
//
//  Stub data source for HomeNextView (M1). Provides mock data so
//  the view compiles + renders for paint work. Codex replaces this
//  implementation with real wiring against Persistence + capture
//  stores; the protocol/shape stays the same.
//
//  Contract:
//    - lastDocument: PickUp? — most-recently-edited capture/doc
//    - recentTally: Tally — auto-rolls 24h → 7d → 30d if empty
//    - recentItems: [RecentItem] — top 5 recent captures
//
//  Spec: design/studio/app/home/SWIFT_PORT.md
//

import SwiftUI

@MainActor
final class HomeFeed: ObservableObject {
    @Published var lastDocument: PickUp?
    @Published var recentTally: Tally
    @Published var recentItems: [RecentItem]

    struct PickUp {
        let title: String
        let meta: String   // pre-formatted: "Compose · 31 words · 4m ago"
        let continueAction: () -> Void
    }

    struct Tally {
        let eyebrow: String      // "Last 24h · 9 captures" or "Quiet · long-press to capture"
        let cta: String?         // Optional right-side chip text ("Week ›")
        let cells: [Cell]        // typically 3; empty if no signal

        struct Cell {
            let value: String    // pre-formatted ("6", "1.2k")
            let label: String    // "Memos", "Type", "Grab"
        }
    }

    struct RecentItem: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String   // "9:34 AM", "Yesterday", "Mon"

        enum Source { case dictation, typed, link, scan }
    }

    init() {
        // Mock data for M1 paint work. Codex replaces this body with
        // a Persistence-backed implementation (see SWIFT_PORT.md):
        //   - PickUp = last-edited capture/document from Persistence
        //   - Tally = window-rolled capture counts grouped by kind
        //   - RecentItems = top 5 recent captures mapped to RecentItem
        self.lastDocument = PickUp(
            title: "Conference Bio",
            meta: "Compose · 31 words · 4m ago",
            continueAction: { /* TODO M2: route to ComposeNextView */ }
        )
        self.recentTally = Tally(
            eyebrow: "Last 24h · 9 captures",
            cta: "Week ›",
            cells: [
                Tally.Cell(value: "6", label: "Memos"),
                Tally.Cell(value: "1", label: "Type"),
                Tally.Cell(value: "2", label: "Grab"),
            ]
        )
        self.recentItems = [
            RecentItem(
                id: "1",
                source: .dictation,
                title: "Scope dashboard design notes",
                preview: "the trace band should anchor to the bottom of the sheet…",
                relativeTime: "9:34 AM"
            ),
            RecentItem(
                id: "2",
                source: .dictation,
                title: "Meeting notes — product roadmap",
                preview: "alex pushed back on the migration window, we settled on st…",
                relativeTime: "7:34 AM"
            ),
            RecentItem(
                id: "3",
                source: .link,
                title: "Keyboard configurator reference",
                preview: "iOS custom keyboard extension — entitlement scoping notes…",
                relativeTime: "6:34 AM"
            ),
        ]
    }
}
