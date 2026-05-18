//
//  LibraryFeed.swift
//  Talkie iOS
//
//  Phase 3 paint stub. Returns mock items so LibraryNextView renders
//  cleanly across all three tabs. Codex replaces the init body with
//  real Persistence + KeyboardDictationStore + CaptureStore queries
//  grouped by source, keeping the public surface stable:
//
//    items(for:)        -> [Item]
//    totalCount(for:)   -> Int
//    earlierCount(for:) -> Int
//

import Foundation
import SwiftUI

@MainActor
final class LibraryFeed: ObservableObject {
    enum Source { case dictation, typed, link, scan }

    struct Item: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String
    }

    @Published private(set) var memos: [Item]
    @Published private(set) var dictations: [Item]
    @Published private(set) var items: [Item]

    @Published private(set) var memosTotal: Int
    @Published private(set) var dictationsTotal: Int
    @Published private(set) var itemsTotal: Int

    @Published private(set) var earlierMemos: Int
    @Published private(set) var earlierDictations: Int
    @Published private(set) var earlierItems: Int

    init() {
        self.memos = Self.mockMemos
        self.dictations = Self.mockDictations
        self.items = Self.mockItems
        self.memosTotal = Self.mockMemos.count + 12
        self.dictationsTotal = Self.mockDictations.count + 4
        self.itemsTotal = Self.mockItems.count + 7
        self.earlierMemos = 12
        self.earlierDictations = 4
        self.earlierItems = 7
    }

    func items(for tab: LibraryTab) -> [Item] {
        switch tab {
        case .memos:      return memos
        case .dictations: return dictations
        case .items:      return items
        }
    }

    func totalCount(for tab: LibraryTab) -> Int {
        switch tab {
        case .memos:      return memosTotal
        case .dictations: return dictationsTotal
        case .items:      return itemsTotal
        }
    }

    func earlierCount(for tab: LibraryTab) -> Int {
        switch tab {
        case .memos:      return earlierMemos
        case .dictations: return earlierDictations
        case .items:      return earlierItems
        }
    }

    // MARK: - Mock fixtures

    private static let mockMemos: [Item] = [
        Item(id: "m1", source: .dictation,
             title: "Meeting notes — product review",
             preview: "alex pushed back on the migration timeline; said we should move it to q3",
             relativeTime: "7:34 AM"),
        Item(id: "m2", source: .dictation,
             title: "Idea: offline-first sync architecture",
             preview: "what if the bridge cached the last 24h of writes locally and replayed them",
             relativeTime: "5:34 AM"),
        Item(id: "m3", source: .typed,
             title: "Quick thought on keyboard shortcuts",
             preview: "swap cmd-shift-3 to be the global capture, much faster than the menu bar",
             relativeTime: "3:34 AM"),
    ]

    private static let mockDictations: [Item] = [
        Item(id: "d1", source: .typed,
             title: "Reply to Jordan re: pricing",
             preview: "thanks for the breakdown — let's talk through it tomorrow",
             relativeTime: "Yesterday"),
        Item(id: "d2", source: .typed,
             title: "Slack thread on the FluidAudio bump",
             preview: "the new version is faster but the swift bindings broke our",
             relativeTime: "Mon"),
    ]

    private static let mockItems: [Item] = [
        Item(id: "i1", source: .link,
             title: "ArXiv: speculative decoding for long context",
             preview: "arxiv.org/abs/2403.09919",
             relativeTime: "9:12 AM"),
        Item(id: "i2", source: .scan,
             title: "Whiteboard from offsite",
             preview: "Photo · 4.2 MB",
             relativeTime: "Yesterday"),
        Item(id: "i3", source: .link,
             title: "Linear ticket — API rate limits",
             preview: "linear.app/team/issue/INF-412",
             relativeTime: "Fri"),
    ]
}
