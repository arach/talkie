# Library → SwiftUI port spec (Phase 3 candidate)

**Status:** drafted ahead of Phase 3
**Branch:** `feat/ios-library-p3` (cut after M2 merges + decision point)
**Target file** (Claude writes; Codex scaffolds + bridges):

- `apps/ios/Talkie iOS/Views/Next/LibraryNextView.swift`

**Visual reference:** `http://localhost:3000/library` — soft brass
underline tabs (Memos · Dictations · Items), 2-line iOS-Notes-style
list rows, integrated search bar.

**Design rationale:** see `design/studio/app/library/NOTES.md`. Key
moves: soft tabs (no full amber pill), 2-line rows via the shared
`ListRow` primitive, search anchored flush below the list (not
floating), variant leading-icon glyph per source type (mira's #1
for Library).

---

## Entry assumption

Phase 0 shell + voice-pivot is in master. Library is reachable from
the shell — exact navigation pattern (NavigationStack inside the
shell? sheet? state-driven swap?) is settled by M2. This spec
assumes the same pattern.

## Composition

```
┌────────────────────────────────────────┐
│ status bar                             │
├────────────────────────────────────────┤
│ ‹ Done    Library          3 / 3       │  ← LibraryHeader
├────────────────────────────────────────┤
│  Memos      Dictations     Items       │  ← TabRow
│  ────                                  │     (brass 2px underline on active)
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ 〜 Meeting notes — product…  7:34 │ │
│ │   alex pushed back on the migrat…  │ │  ← LibraryListCard
│ │ 〜 Idea: offline-first sync   5:34 │ │
│ │   what if the bridge cached the…   │ │
│ │ ⌨ Quick thought on keyboard… 3:34 │ │
│ │   swap cmd-shift-3 to be the gl…   │ │
│ │ ───────────────────────────────── │ │
│ │ · EARLIER · THIS WEEK    12 MORE  │ │  ← inset divider + smallcap
│ │                                    │ │
│ │                                    │ │  ← breathing room
│ └────────────────────────────────────┘ │
│ ┌────────────────────────────────────┐ │
│ │ 🔍 Search memos                    │ │  ← SearchBar (flush footer)
│ └────────────────────────────────────┘ │
│                                        │
│ ●  ← shell voice button                │
└────────────────────────────────────────┘
```

---

## File: `LibraryNextView.swift`

```swift
import SwiftUI

enum LibraryTab: CaseIterable {
    case memos, dictations, items

    var label: String {
        switch self {
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .items:      return "Items"
        }
    }
}

struct LibraryNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @StateObject private var library: LibraryFeed
    @State private var activeTab: LibraryTab = .memos

    init(feed: LibraryFeed? = nil) {
        _library = StateObject(wrappedValue: feed ?? LibraryFeed())
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(count: library.items(for: activeTab).count, total: library.totalCount(for: activeTab))
            TabRow(active: $activeTab)
            LibraryListCard(items: library.items(for: activeTab), earlierCount: library.earlierCount(for: activeTab))
                .padding(.horizontal, 12)
                .padding(.top, 4)
            SearchBar()
                .padding(.horizontal, 12)
                .padding(.top, 8)
            Spacer(minLength: 80) // room for shell voice button
        }
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    let count: Int
    let total: Int

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Button(action: {
                // Pop / dismiss back to caller (Home)
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Library")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            // Right pill — count badge (e.g., "3 / 3")
            Text("\(count) / \(total)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(theme.colors.cardBackground)
                        .overlay(Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

// MARK: - Tab row (soft underline, no pill fill)

private struct TabRow: View {
    @Binding var active: LibraryTab
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: LibraryTab) -> some View {
        let isActive = (active == tab)
        return Button(action: { active = tab }) {
            VStack(spacing: 4) {
                Text(tab.label)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.05)
                    .foregroundStyle(isActive ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                Rectangle()
                    .fill(isActive ? theme.currentTheme.chrome.accent : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List card

private struct LibraryListCard: View {
    let items: [LibraryFeed.Item]
    let earlierCount: Int

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                LibraryRow(item: item, showDivider: idx > 0)
            }

            // Inset "EARLIER · THIS WEEK" divider with count on the right.
            HStack(spacing: 6) {
                Text("· EARLIER · THIS WEEK")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .textCase(.uppercase)
                Spacer()
                Text("\(earlierCount) MORE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .overlay(
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: 0.5)
                    .padding(.leading, 36),
                alignment: .top
            )

            Spacer(minLength: 24)
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
        )
    }
}

private struct LibraryRow: View {
    let item: LibraryFeed.Item
    let showDivider: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: 0.5)
                    .padding(.leading, 36)
            }
            HStack(alignment: .top, spacing: 8) {
                sourceGlyph
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tracking(-0.05)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.relativeTime)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    if let preview = item.preview {
                        Text(preview)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var sourceGlyph: some View {
        switch item.source {
        case .dictation:
            Image(systemName: "waveform").font(.system(size: 13))
        case .typed:
            Image(systemName: "keyboard").font(.system(size: 12))
        case .link:
            Image(systemName: "link").font(.system(size: 12))
        case .scan:
            Image(systemName: "viewfinder").font(.system(size: 12))
        }
    }
}

// MARK: - Search

private struct SearchBar: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var query: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)
            TextField("Search memos", text: $query)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .overlay(Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5))
        )
    }
}
```

---

## `LibraryFeed` — service bridge (Codex writes this)

```swift
@MainActor
final class LibraryFeed: ObservableObject {
    enum Source { case dictation, typed, link, scan }

    struct Item: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String   // "9:34 AM" / "Yesterday" / "Mon"
    }

    @Published private(set) var memos: [Item] = []
    @Published private(set) var dictations: [Item] = []
    @Published private(set) var items: [Item] = []

    @Published private(set) var memosTotal: Int = 0
    @Published private(set) var dictationsTotal: Int = 0
    @Published private(set) var itemsTotal: Int = 0

    @Published private(set) var earlierMemos: Int = 0
    @Published private(set) var earlierDictations: Int = 0
    @Published private(set) var earlierItems: Int = 0

    func items(for tab: LibraryTab) -> [Item] { /* Codex implements */ [] }
    func totalCount(for tab: LibraryTab) -> Int { /* Codex implements */ 0 }
    func earlierCount(for tab: LibraryTab) -> Int { /* Codex implements */ 0 }

    init() {
        // Codex wires: query Persistence for captures grouped by source.
        // - Memos = audio capture entries
        // - Dictations = transcribed-text-only entries (no audio)
        // - Items = clipped links + scans
        // Top N (3 in the mock; could be 5-10 in real) shown; rest →
        // "Earlier this week" count.
    }
}
```

### Bridge specifics for Codex

- **Tab → source mapping** — if existing capture types don't split
  cleanly into memos/dictations/items, ask Claude before guessing.
- **"This week" cutoff** — items younger than 7 days but not in the
  top-N go into `earlierCount`. Items older than 7 days are not
  surfaced on Library at all (would be in a deeper "All time" view
  later).
- **Search wiring** — out of scope for the initial port; the
  `SearchBar` is decorative until M3+. Just don't break TextField
  bindings.

---

## Cut criteria

- [ ] LibraryNextView reachable from Home (or wherever navigation
      decides to put it)
- [ ] Real captures show in each tab via LibraryFeed
- [ ] Tab switching works; brass underline animates smoothly
- [ ] List row layout matches studio mock at all 5 themes
- [ ] Search bar renders flush as the list footer; no floating gap
- [ ] EARLIER · THIS WEEK divider shows the "N MORE" count
- [ ] Voice-pivot summon still works over Library content

---

## Out of scope

- Real search (TextField is a stub; M4 wires actual search index)
- Row tap → capture detail (M3+; navigation pattern TBD)
- Pull-to-refresh
- Empty-state polish (just shows "Library" with empty list — fine)
- Sort / filter options (single hard-coded sort = lastEditedAt desc)
