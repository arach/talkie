# Mac Learn KB — Article Reader (Design Notes)

## What this study is

The article-detail body that renders inside a local `WKWebView` hosted
by the macOS Learn KB shell. The web view is a *content slab*, not an
app. Native search, sidebar, history and back/forward stay SwiftUI; the
web view's job is one article at a time.

## What it is not

- Not the KB sidebar / list / filter / search — those are SwiftUI.
- Not a content corpus. No real KB articles are written here. The two
  sample articles are studio fakes (`ARTICLE_HYPER_S`,
  `ARTICLE_CONTEXT_RULES`) that exercise every block type.
- Not a marketing site. No hero photos, no CTAs in the dek, no
  illustration band. The page reads as an editorial article on a paper
  sheet — display serif, ledger meta, hairline rules.

## Article anatomy

1. **Hero** — topic eyebrow + display title + dek. Topic eyebrow uses
   the per-theme leader glyph (`·` / `—` / `›`) via
   `--theme-eyebrow-leader`. Title is Newsreader at 34/1.08 with
   per-theme display weight + tracking.

2. **Metadata ledger** — small-caps mono row in 4 cells (Updated,
   Reading, Maintained, Article slug) with hairline dividers, sitting
   on `--theme-canvas-alt`. Editorial masthead, not a tag soup.

3. **Shortcut strip** — keycaps for the combo + `then any of` disjoint
   row for chord follow-ups (A / S / D). Mono cap glyphs on
   `--theme-paper`, hairline border, per-theme chrome-corner. Optional
   per article.

4. **Body blocks** — `para`, `subhead`, `callout`, `steps`, `related`,
   `bridge`. The block model is the porting contract for the eventual
   markdown pipeline.

5. **Callout** — amber-faint fill, 2px brass left bar, small-caps label
   (`NOTE · ...` / `TIP · ...` / `WATCH OUT · ...`). Only block that
   uses accent fill; reserved on purpose.

6. **Steps** — numbered ordered list with channel-style indices
   (`S01`, `S02`...) in brass, thin hairline rules between each. Mirrors
   the donor `ScopeRule` rhythm.

7. **Related** — ledger rows with topic on the right; clicks resolve to
   another article in the KB (SwiftUI intercepts and routes).

8. **Bridge action rows** — the explicit KB → app handshake. Each row
   is a `talkie://` deep-link with a label, a mono URL line, and a
   one-sentence detail. Borders use `--theme-amber-soft` so they read
   as the *call to action*, distinct from related-article rows.

## Token mapping

Every visual decision is sourced from `--theme-*` CSS variables in
`app/globals.css`. Nothing in the article body uses Tailwind
`studio-*` colors — those are reserved for studio chrome (the page
header / borders around the previews).

| Region                         | Token                                                |
|--------------------------------|------------------------------------------------------|
| Article background             | `--theme-canvas`                                     |
| Ledger background              | `--theme-canvas-alt`                                 |
| Keycap / bridge row fill       | `--theme-paper`                                      |
| Headline ink                   | `--theme-ink`                                        |
| Body prose                     | `--theme-ink-muted`                                  |
| Metadata + chrome labels       | `--theme-ink-faint`                                  |
| Topic eyebrow, S0n indices, →  | `--theme-amber`                                      |
| Callout fill                   | `--theme-amber-faint`                                |
| Bridge row border              | `--theme-amber-soft`                                 |
| Bridge → arrow halo            | `--theme-amber-glow` × `--theme-glow-radius`         |
| Hairline rules                 | `--theme-edge-faint`                                 |
| Keycap & bridge borders        | `--theme-edge`                                       |
| Rounded chrome (cap, bridge)   | `--theme-chrome-corner`                              |
| Eyebrow leader glyph           | `--theme-eyebrow-leader`                             |
| Display face / weight / track  | `--theme-font-display`, `-weight`, `-tracking`       |
| Body face                      | `--theme-font-body`                                  |
| Mono (caps, ledger, eyebrows)  | `--theme-font-mono`                                  |

Swapping `data-theme` on the wrapper repaints every region above.
There are no theme-specific code paths in the component.

## Themes covered in the study

The deliverable required at least one strong light and one strong dark
treatment. The route shows three of the existing iOS theme bundles
applied to the same reader, demonstrating that the component is
theme-passive:

- **Scope (light, default)** — paper-white canvas, warm-graphite ink,
  brass amber accent. Eyebrow leader is `·`. 3px chrome corners,
  0.5px hairlines, glow radius 2. The default the macOS app ships.
- **Midnight (dark)** — near-black canvas, vivid info-blue accent
  (NOT amber — themed via `--theme-amber`). Eyebrow leader is `—`.
  2px chrome corners, glow radius 3.
- **Tactical (dark)** — Palantir/Anduril-inspired. Vivid orange accent,
  square (0px) chrome corners, 1.0px hairlines, near-zero glow,
  `›` eyebrow leader. The grittier dark.

## Design principles inherited from Scope

- Editorial display type for headlines; never sentence-case body
  styling on a hero.
- Ledger meta over chip soup. Hairlines, not pills.
- Restrained accent ration: brass/amber lives in eyebrows, callout
  fill, ordered-step indices, and bridge action rows. Nowhere else.
- No marketing voice. The dek answers "what is this article" in one
  sentence; it never promises or persuades.
- The article does not try to be the app. The bridge rows are where
  intent gets fulfilled — by handing back to SwiftUI.
