# Mac Memo Detail — Decisions Log

## What this study renders

The **right-hand pane of the macOS Library split view** — the panel
that shows when you select a memo in the list. Source of truth in
Swift (when this lands): the Library detail panel currently rendered
by the Library screen's split view.

The study renders the realistic shape: faint window chrome, a
compressed library-list gutter on the left for context, and the detail
pane on the right at its true split-view width (~880px inside a
1180px window). Cream studio canvas, no scheme picker — Scope-first.

## What was wrong with the shipping pane

Look at `/tmp/talkie-home.png`. The right pane top reads as a
dashboard that crashed into a content header:

- **Three metric pills** (`90` / `147` / `8024`) — dashboard widgetry
  that doesn't belong to the memo. They're aggregate-vibe in a
  detail context.
- **Tiny lonely timestamp** (`Today at 10:58 AM`) — the only piece
  of editorial copy is set smaller than the chrome around it. The
  reader's eye has nowhere to land.
- **Four-column metadata grid** (DEVICE · MODEL · DURATION · PROVENANCE)
  — dense, chromy, uneditorial. Reads as a properties inspector.
- **Wall-of-mono transcript** — no rhythm, no lead-in, no breaks.
- **Utilitarian player** — fine as a tool, but stylistically detached
  from the rest of the surface.

## What this study does instead

**The pane is a sheet of paper opened on a desk, not a dashboard.**

Five moves:

1. **Editorial masthead.** Replaces the metric pills + the four-column
   grid with three lines:
   - Eyebrow: `· CH-02 · DICTATION` ——————— `Today · 10:58 AM`
   - Serif headline: a derived title at 34px Newsreader 500
   - Byline: single line, `iTerm2 · 6:14 duration · 412 words · MacBook Pro · Parakeet v3`
     — mono caps, no labels, order is the contract.

   The headline is the eye-magnet. The byline carries the factual
   load that the four-column grid was carrying, at a fraction of the
   chrome.

2. **Toolbar slug-line above the masthead.** The pane's top region is
   `M-0421 · · DICTATION` on the left, a row of low-key tool buttons
   (Star · Pin · Share · Export · ⋯) on the right. Reads as a printer's
   slug, not as a toolbar.

3. **Transcript as document.** The first paragraph is set in the
   display serif at 18px with a small-caps timecode opener (`0:00 ·`).
   Subsequent paragraphs are sans body at 14px / 1.7 leading, each
   prefixed by its own timecode in the left gutter (scrub-by-paragraph).
   A thin brass marginal rule runs the full height of the body — a
   printed-page gutter. End-of-document slug closes the read with
   `end · 6:14 · 412 words`.

4. **Right-margin highlights column.** Pull-quotes the user (or the
   agent) flagged, with timestamps and a small brass border-left.
   Below that, a `· Linked` block — related memos the user can jump
   to. Reads as the editor's margin, not a sidebar widget.

5. **Player rail as typesetter's bar.** Sits at the foot of the
   document on a slightly warmer band (`#F2EDDE` with an inset
   highlight). Transport on the left, brass-amber waveform with
   played-region tint, scrubber as a glowing brass needle, time
   readout in mono. Wears the cream palette — not the black
   media-player register.

## Critique applied (mapped to the user's prompt)

| Critique | Move |
|---|---|
| "Metric pills don't belong to the memo" | Pills deleted. Numeric load redistributed into the byline + end-slug. |
| "Memo timestamp is lonely and small" | Date + time live in the eyebrow line; the serif headline IS the page's eye-magnet. |
| "Four-column metadata grid is dense and chromy" | Replaced by single editorial byline. |
| "Transcript has no rhythm" | Lead-paragraph treatment + paragraph breaks + gutter timecodes + marginal rule. |
| "Player is utilitarian, doesn't feel of a piece" | Recolored to brass-on-cream, sits on a warm sub-band, reads as foot-of-document chrome. |

## What I deliberately did NOT do

- **No new fonts.** Newsreader (display) + Inter (body) + JetBrains
  Mono (chrome) — same stack as the rest of the studio.
- **No animation.** Static composition. The waveform is a static
  amplitude strip with a fixed progress position.
- **No multi-scheme grid.** One canonical scheme rendering (cream +
  brass), big and clear. Future v2 can add the scheme picker.
- **No marketing copy.** No taglines, no aspirational verbs. The
  byline says what it says. The end-slug says `end · 6:14 · 412 words`.
- **No fake "AI summary" block.** Tempting to add a "key points"
  card; that's another study. Here the document is the surface.

## Open questions

- **Headline source.** I'm hand-authoring "Re-grounding the bay
  against the chiffon canvas" — a derived noun-phrase title.
  Talkie's procedural pipeline doesn't currently emit titles; the
  Swift port would either need a small title-extractor pass, an LLM
  call, or a graceful fallback to `Today · 10:58 AM` as the headline
  (the current behavior). Which is the contract?
- **Highlights provenance.** Are highlights user-authored (manual
  selection during playback), agent-authored (LLM-flagged after
  transcription), or both? The visual treatment is the same either
  way, but the empty state differs.
- **Linked memos.** Renders here as a small block under Highlights;
  not in the data model yet. Could ship empty, could be promoted to
  its own pane region if it turns out to carry weight.
- **Right-margin column at narrower widths.** Below ~720px panel
  width the highlights column should collapse above the body, not
  vanish. Not yet specified.
- **Whether the toolbar should hide on scroll.** A long memo will
  push the masthead off; the toolbar could sticky-collapse to a
  thin chip with the headline + transport. Future, not now.
- **End-of-document affordance.** Currently a slug; could become
  an inline "Next memo · 10:42 · Okay, do you want to switch?"
  hand-off so reading flows down the library. Test before adopting.

## Why these primitives

Composition is inline — no new shared primitives introduced. The
study reuses the established Scope vocabulary:

- `studio-ink` / `studio-ink-faint` / `studio-edge` for the ink
  ladder.
- `font-display` (Newsreader) for the headline, lead paragraph, and
  highlights.
- `font-mono` (JetBrains Mono) for the eyebrow, byline, timecodes,
  and slug.
- Brass amber `#C47D1C` for the marginal rule, played-waveform
  region, scrubber needle, and highlight borders — the single
  accent.

If this composition makes it through review, candidates to extract:

- `<Masthead>` — eyebrow + serif headline + byline — generalizes
  to other document surfaces (Compose, Note detail).
- `<PlayerRail>` — cream-palette media bar — generalizes to any
  audio-bearing document.
- `<MarginalGutter>` — the thin brass rule + cue-timecodes pattern
  — could template the transcript view in other Library types.

## Component map

- `app/mac-memo-detail/page.tsx` — route wrapper, uses `<StudioPage>`.
- `components/studies/MacMemoDetail.tsx` — composition root.
- Sub-components inline:
  `PaneFrame`, `WindowChrome`, `LibraryListGutter`, `DetailPane`,
  `Toolbar`, `Masthead`, `Sep`, `Body`, `PlayerRail`, `PlayButton`,
  `TransportButton`, `Footnote`.
