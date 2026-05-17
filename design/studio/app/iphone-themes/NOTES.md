# iPhone Themes — Decisions Log

## What the study renders

A multi-theme **mock shell** for iPhone UI variants. Renders one
canonical iPhone phone-frame four times in a grid, each wrapped in
its own `[data-theme]` scope: **Scope**, **Midnight**, **Tactical**,
**Ghost**. Drop the SAME mock markup into every `.iphone-frame__content`
slot and it re-paints across the theme spectrum simultaneously.

Plus a vocabulary style-guide section showing every shared primitive
(`.eyebrow`, `.channel-label`, `.status-line`, `.headline`, `.tile`,
`.panel`, `.screen`, `.chip`, `.dot`, `.bus-line`, `.btn`,
`.graticule`) rendered under each theme — use this to verify a
pattern works across themes before committing it to a mock.

Source-of-truth tokens live in `../_shared/tokens.css`. Anchored to
usetalkie.com's canonical default (Modern + Slate per StudioPanel
defaults, Cormorant Garamond display, Inter body, JetBrains Mono
chrome — verified against `usetalkie.com/app/layout.jsx` and
`components/home/HomePage.jsx`).

## Anchor themes

Four iOS theme bundles, each remapping the full token set keyed off
`[data-theme]`:

- **Scope** — cream-paper instrument with amber-on-charcoal phosphor.
  The default. Light, warm, editorial. (Note: the Scope canvas was
  re-grounded on cool slate in branch `ui/instrument-bay-polish` to
  drop the warm-brown bias — the tokens.css default mirrors that.)
- **Midnight** — green-phosphor on near-black. Studio scope identity.
  `--amber` remaps to green; the semantic ("chrome accent") stays.
- **Tactical** — olive-drab charcoal with low-emission amber. Fatigue-
  resistant; reduced glow.
- **Ghost** — near-white stationery with neutral slate accent. No
  phosphor, no warm halo — `--glow-*` is neutralized to `none`.

## How to use

1. Open this page in a browser.
2. Author one iPhone mock once — use the studio's primitive classes
   (e.g. `<div class="panel"><div class="screen">...</div></div>`).
3. Paste it into all four `.iphone-frame__content` slots.
4. The mock paints across the four themes at the same time — verify
   it reads in each before declaring done.
5. For one-off live experimentation, the sticky top bar lets you
   flip the page-level theme via `<html data-theme="X">`.

## Open questions

- Whether to add a fifth theme bundle for an as-yet-unnamed iPhone
  variant (e.g. the "Brass" deep-warm tilt some users prefer).
- Whether the `.iphone-frame__content` should provide a default
  status-bar / notch / home-indicator chrome, or leave that to the
  mock (currently leaves it).
- Whether the mock-vocabulary cheatsheet section should split out
  into its own page once it grows past a screen height — currently
  it's inline below the phone grid.

## Why this study and not a scheme grid

Unlike `agent-bay/` and `recording-sheet/` (which iterate one artifact
across many *material schemes* — AMBER / CARBON / SLATE / etc.), this
study iterates a *whole iPhone surface* across iOS *themes*. The two
axes are complementary:

- **Scheme studies** answer "what material does this artifact want?"
- **Theme studies** answer "does this mock survive across all themes
  the iOS app actually ships?"

Run a scheme study first to pick the surviving material for a single
artifact. Then drop that artifact into the iphone-themes shell to
verify it holds across all iOS themes.
