# Mac Library — Decisions Log

## What this study renders

The full macOS Library composition. Source of truth in Swift:
`apps/macos/Talkie/Views/Library/ScopeLibraryView.swift`.

The study stamps the same composition at **three widths** stacked
vertically:

| Stamp | Width | Format  | What it surfaces |
|---|---|---|---|
| 1 | 820  | Compact | Below the Swift `< 880` breakpoint → list-only fallback (no inspector). |
| 2 | 1180 | Default | Studio standard. Split view with list ~520 + inspector. |
| 3 | 1440 | Wide    | External display. Inspector gets generous space for transcript. |

The 820 stamp is the important one — it's the only one that crosses
the responsive boundary and forces the layout to make a different
decision. 1180 and 1440 differ in inspector breathing room, not in
layout shape.

## Composition

Header band (title + count, filter pills row, search field), body
(list column + divider + inspector when split), footer bar. The list
column groups rows into date buckets (TODAY / YESTERDAY / THIS WEEK)
with a small mono-caps header inserted in flow.

Each row carries a channel-letter circle (M / D / N / C), a 12.5px
title with a mono meta line beneath, a trailing time + mini-waveform.
Memos and dictations get the waveform; notes and captures get an
empty slot at the same height so vertical rhythm stays intact.

The inspector has four parts top-to-bottom:

1. **Readout panel** — a 200pt dark instrument bay floating inside
   the inspector with phase-plot trace + graticule. Echoes Swift's
   `phasePlot` `readoutBodyVariant`. Wrapped in `m-4` so it sits as a
   distinct slab on the cream paper, not as a flush header.
2. **Masthead** — toolbar slug (sequence + tool buttons), then
   eyebrow / serif headline / byline. Same shape as MacMemoDetail so
   the two surfaces feel of a piece.
3. **Body** — lead paragraph in display serif at 15px, follow-on
   paragraphs in 13px sans, brass marginal rule at the left gutter.
4. **Player rail** — typesetter's bar on a warm `#F2EDDE` sub-band.
   Played region tints amber, unplayed peaks stay paper-gray.

## Open questions

- **List column width.** Swift defaults to 520 and clamps to a 460
  minimum. Here it's `max(440, min(560, width - 720))` — at 1180 that
  pegs the list at 460 (inspector gets 714); at 1440 it grows to 560
  (inspector gets 874). Is 460 too narrow at 1180? The list rows
  truncate at 460 in a way they don't at 520. Worth comparing.
- **Readout panel at 820.** Currently the readout doesn't render at
  820 because the inspector is hidden in compact mode. But the Swift
  app at sub-880 widths might want a compact readout overlay (a
  bottom rail?). Not modeled here — out of scope for iteration 1.
- **Mini-waveform on notes / captures.** Right now they leave an
  empty 56×10 slot to preserve rhythm. Could instead show a content
  glyph (text lines for notes, image dimensions for captures). The
  current choice keeps the trailing column predictable but loses
  the variant signal.
- **Filter pill counts at 820.** With five pills (`All` / `Memos` /
  `Dictations` / `Notes` / `Captures`) the row gets tight at 820;
  consider truncating to icons or moving to a Menu at compact.
- **Footer bar.** The "LIST · LIST-ONLY MODE" / "SPLIT · INSPECTOR
  LIVE" status text on the right is studio-flavor — useful to call
  out what mode the artifact is in, but probably noise in shipping
  Swift. Decide before porting.

## Component map

- `app/mac-library/page.tsx` — route wrapper, uses MacWindowGrid.
- `components/studies/MacLibrary.tsx` — composition root, accepts
  `width` prop and branches at 880.
- Sub-components inline:
  `HeaderBand`, `FilterPill`, `ListColumn`, `BucketHeader`,
  `LibraryRow`, `MiniWave`, `DividerHandle`, `Inspector`,
  `ReadoutPanel`, `InspectorMasthead`, `InspectorBody`,
  `InspectorPlayerRail`, `PlayerWave`, `FooterBar`, `ToolButton`.

Promotion candidates if a second mac study needs them:
- `<DividerHandle>` — the 6px ghost handle pattern. Will need to
  share with mac-compose if Compose grows a split layout.
- `<MiniWave>` / `<PlayerWave>` — amplitude strips. Likely belong in
  `primitives/Waveform.tsx` once a third caller appears.
