# Home → SwiftUI port spec (superseded M1)

> Status note, 2026-07-01: this document describes the older
> STATION/PICK UP/Action Bus Home direction. The current Studio route at
> `http://localhost:3000/home` mirrors the newer iOS Home composition:
> header complication, Today ticker, Quick deck, Recent screen, Explore rail,
> bottom voice pivot, and central mic FAB. Treat `NOTES.md` and
> `components/studies/Home.tsx` as the current design surface until this port
> spec is rewritten.

**Status:** drafted while Codex builds Phase 0
**Branch:** kick off on a new branch `feat/ios-home-m1` once Phase 0 lands in master.
**Target file** (Claude writes; Codex scaffolds + bridges):

- `apps/ios/Talkie iOS/Views/Next/HomeNextView.swift` (new — replaces the Phase 0 `HomeNextStub.swift`)

**Visual reference:** `http://localhost:3000/home` — composition:
TALKIE wordmark · PICK UP card · smart Action Bus · Recent list ·
(ambient voice button sits in the shell, not in this view).

**Design rationale:** see `design/studio/app/home/NOTES.md`. Key
moves: PICK UP replaces the redundant "5 signals on deck"
placeholder with a real one-tap continue surface; Action Bus
auto-rolls 24h → week → 30d so it never just shows zeros;
TALKIE wordmark is SF Mono (channel-label vocabulary), not display
serif.

---

## Entry-point swap

In `apps/ios/Talkie iOS/App/talkieApp.swift:75` once Phase 0 has
merged: swap `AppShellNext { HomeNextStub() }` →
`AppShellNext { HomeNextView() }`. One line.

---

## Composition

```
┌────────────────────────────────────────┐
│ status bar (provided by system)        │
├────────────────────────────────────────┤
│       [TALKIE mono wordmark]    ⚙       │  ← HomeHeader
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ · pick up                          │ │
│ │ Conference Bio              [Continue ›] │
│ │ COMPOSE · 31 WORDS · 4M AGO        │ │
│ │ ┌────────────────────────────────┐ │ │
│ │ │ ● last 24h · 9 captures  week ›│ │ │  ← ActionBus inset
│ │ │   6      1      2              │ │ │
│ │ │ MEMOS  TYPE   GRAB             │ │ │
│ │ └────────────────────────────────┘ │ │
│ └────────────────────────────────────┘ │  ← StationCard
├────────────────────────────────────────┤
│ · recent  [5]                    ALL  │
│ ┌────────────────────────────────────┐ │
│ │ 〜 Scope dashboard design notes 9:34│ │
│ │   the trace band should anchor t…  │ │  ← RecentList
│ │ 〜 Meeting notes — product roadmap 7:34│ │
│ │   alex pushed back on the migrat…  │ │
│ │ 🔗 Keyboard configurator reference 6:34│ │
│ └────────────────────────────────────┘ │
│                                        │
│ ●  ← ambient voice button (shell)     │
└────────────────────────────────────────┘
```

---

## File: `HomeNextView.swift`

```swift
import SwiftUI

struct HomeNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @StateObject private var feed = HomeFeed()  // Codex bridges this

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                StationCard(
                    pickUp: feed.lastDocument,
                    actionBus: feed.recentTally
                )
                .padding(.horizontal, 12)

                RecentSection(items: feed.recentItems)
                    .padding(.horizontal, 12)

                Spacer(minLength: 80)   // leave room for voice button
            }
            .padding(.top, 0)
        }
        .scrollIndicators(.hidden)
    }
}
```

---

## Subviews

### `HomeHeader`

Centered TALKIE wordmark in SF Mono — channel-label vocabulary,
not display serif. Settings gear top-right; spacer top-left
balances the layout (Settings is also reachable via the chrome
overlay so duplication is OK at this stage).

```swift
private struct HomeHeader: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Color.clear.frame(width: 28, height: 28)

            Spacer()

            Text("TALKIE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(3.2)   // ~0.32em at 10pt
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { /* opens chrome via voice button, or routes to Settings */ }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.colors.cardBackground)
                            .overlay(Circle().strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

### `StationCard`

Paper-lifted card with PICK UP eyebrow + document title + meta +
Continue pill. Embeds the dark Action Bus at the bottom.

```swift
private struct StationCard: View {
    let pickUp: HomeFeed.PickUp?      // nil = "nothing recent"
    let actionBus: HomeFeed.Tally     // never nil; falls back to wider periods

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // PICK UP header — eyebrow · title · meta · Continue button.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PICK UP")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.6)
                        .foregroundStyle(theme.currentTheme.chrome.accent)

                    if let pickUp {
                        Text(pickUp.title)
                            .font(.system(size: 22, weight: .medium))
                            .tracking(-0.4)        // ~-0.018em at 22pt
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(pickUp.meta)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(theme.colors.textTertiary)
                    } else {
                        Text("Nothing recent")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                if let pickUp {
                    Button(action: pickUp.continueAction) {
                        Text("Continue ›")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.colors.cardBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ActionBus(tally: actionBus)
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
```

### `ActionBus`

Dark inset row showing captured-today (or auto-rolled period)
counts: memos / type / grab. Use `theme.colors.background` so
on light themes the bus is light (per the studio's "don't fight
cream/white" fix), on dark themes naturally dark.

```swift
private struct ActionBus: View {
    let tally: HomeFeed.Tally

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.currentTheme.chrome.accent)
                    .frame(width: 5, height: 5)

                Text(tally.eyebrow)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .textCase(.uppercase)

                Spacer()

                if let cta = tally.cta {
                    Text(cta)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(theme.colors.textTertiary)
                        .textCase(.uppercase)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 0) {
                ForEach(Array(tally.cells.enumerated()), id: \.offset) { idx, cell in
                    VStack(spacing: 4) {
                        Text(cell.value)
                            .font(.system(size: 24, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                            .tracking(-0.5)

                        Text(cell.label)
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(theme.colors.textTertiary)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    if idx < tally.cells.count - 1 {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(width: 0.5)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(theme.colors.background)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}
```

### `RecentSection` + `RecentRow`

Channel-label header with count pill + `ALL` right-aligned, then
the 2-line iOS-Notes-style list.

```swift
private struct RecentSection: View {
    let items: [HomeFeed.RecentItem]

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· RECENT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .textCase(.uppercase)

                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.currentTheme.chrome.accentTint))

                Spacer()

                Text("ALL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    RecentRow(item: item, showDivider: idx > 0)
                }
            }
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
            )
        }
    }
}

private struct RecentRow: View {
    let item: HomeFeed.RecentItem
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
                SourceGlyph(source: item.source)
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
}

private struct SourceGlyph: View {
    let source: HomeFeed.RecentItem.Source

    var body: some View {
        switch source {
        case .dictation:
            // Tiny waveform.
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .regular))
        case .typed:
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .regular))
        case .link:
            Image(systemName: "link")
                .font(.system(size: 12, weight: .regular))
        case .scan:
            Image(systemName: "viewfinder")
                .font(.system(size: 12, weight: .regular))
        }
    }
}
```

---

## `HomeFeed` — service bridge (Codex writes this)

This is the **wiring** part — Codex writes it. The shape needed
by my view code:

```swift
@MainActor
final class HomeFeed: ObservableObject {
    @Published var lastDocument: PickUp?    // nil when no recent capture
    @Published var recentTally: Tally       // never nil; auto-rolls window
    @Published var recentItems: [RecentItem] = []

    struct PickUp {
        let title: String
        /// E.g. "COMPOSE · 31 WORDS · 4M AGO" — caller renders verbatim.
        let meta: String
        let continueAction: () -> Void
    }

    struct Tally {
        /// E.g. "Last 24h · 9 captures"
        let eyebrow: String
        /// Optional right-side chip (e.g. "WEEK ›" suggesting period scope)
        let cta: String?
        let cells: [Cell]   // typically 3

        struct Cell {
            let value: String   // pre-formatted (e.g. "6" or "1.2k")
            let label: String   // "Memos", "Type", "Grab"
        }
    }

    struct RecentItem: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String     // "9:34 AM", "Yesterday", "Mon"

        enum Source { case dictation, typed, link, scan }
    }

    init() {
        // Codex wires this up:
        // - PickUp = query last-edited capture from Persistence
        // - Tally = scan captures over last 24h; if empty, roll to 7d,
        //   then 30d; eyebrow + cells reflect the chosen window
        // - RecentItems = top 5 recent captures, mapped to RecentItem
    }
}
```

### Bridge specifics for Codex

- **PickUp.continueAction** — for M1, route to a stub Compose
  destination (could be a placeholder NavigationLink, or print a
  debug log). M2 wires this to the real ComposeNextView.
- **Persistence** — the existing CoreData stack (Persistence.swift).
  Captures probably have a `lastEditedAt` and `documentType` field.
- **Tally window rule** — try 24h first. If sum of cells == 0, try
  7d (eyebrow: "Last 7 days · N captures"). If still 0, try 30d.
  If still 0, return `Tally(eyebrow: "Quiet · long-press to capture", cta: nil, cells: [])`
  and the view will render an empty bus (or you can hide it
  entirely by returning nil — your call).
- **Recent items source mapping** — existing capture types likely
  map cleanly: voice/dictation → `.dictation`, manual entry →
  `.typed`, shared link → `.link`, photo/scan → `.scan`.

---

## Cut criteria for M1

- [ ] HomeNextView renders inside AppShellNext (entry point swap)
- [ ] PICK UP shows the actual last-edited document (or fallback)
- [ ] Continue button routes somewhere reasonable (stub OK in M1)
- [ ] Action Bus shows real counts; auto-rolls when 24h is empty
- [ ] Recent list shows last 5 real captures with correct icons
- [ ] Voice button + chrome from Phase 0 still work over this content
- [ ] Renders correctly across all 5 themes; light themes get a
      light Action Bus (no dark inset fighting cream/white)
- [ ] Screenshots match the studio mock at
      `http://localhost:3000/home` reasonably closely (allow for
      iOS-rendering vs CSS rendering differences in line-height,
      letter-spacing precision)

---

## Out of scope for M1 (push to M2 or later)

- Tappable Action Bus cells (jumping to filtered library)
- Tappable Recent rows (opening individual captures)
- Pull-to-refresh
- Live updating when captures change (just initial load is fine)
- Empty-state polish beyond the "Quiet · long-press to capture"
  bus fallback
