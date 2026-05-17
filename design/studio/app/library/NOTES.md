# Library — Decisions Log

## What this study renders

The Library screen (Memos tab) recreated from
`design/screenshots/2026-05-17/02-library-memos-scope-view.png`,
rendered across all 4 iOS themes simultaneously inside `<PhoneFrame>`.

The Library component is pure-theme (reads `--theme-*` vars). Same
markup paints differently per theme; the comparison surfaces whether
the design holds across the spectrum.

## Mira's critique applied (from `design/reviews/2026-05-17-scope-design-review.md`)

- **Variant leading icons by source.** Killed the all-mic column — now
  dictation gets a waveform glyph, typed captures get a keyboard,
  clipped items get a chain link. Glyph IS the metadata.
- **Inline transcript preview line.** One line under each title at
  `ink-faint`, ~11px. Doubles row information density without adding
  rows.
- **Hairline above the search bar.** Was marooned at the bottom;
  now anchored to the list above by a `--theme-edge-faint` rule.
- **Filled the void.** The big empty space below the 3 rows is now a
  channel-label divider (`· Earlier · this week`) and a low-contrast
  empty-state hint at the bottom (`·  ·  ·   nothing else clipped today`).

## Open questions

- The `3 / 3` counter is a pill; should it stay a paper pill or
  become a channel-badge (`· T03 / 03`)? Pill reads more iOS-native;
  channel-badge reads more on-brand. Pick when the rest of the app
  codifies channel badges.
- Tab row uses 3 chips with leading glyphs (wave / keyboard / tray).
  Glyphs may be too small at 12px — bump or drop?
- The Earlier divider could move further up so the rule isn't
  fighting the search bar's top hairline.

## Why these primitives

This study introduced `<NavBar>`, `<NavPill>`, `<Chip>`, `<ListRow>`,
`<ChannelLabel>` to `components/studies/primitives/`. Any future iOS
screen study should compose from these. If a primitive isn't enough,
extend it — don't fork.
