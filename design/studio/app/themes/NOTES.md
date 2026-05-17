# Themes — Decisions Log

## What this gallery is

The articulation card for each iOS theme. Shows identity, typography
spec (display weight + tracking + italic accent), palette swatches,
behavior flags (glow / graticule / dark surface), and the blurb that
states what the theme *feels* like.

Theme data: `lib/themes.ts`. Token bundles applied at runtime:
`app/globals.css` `[data-theme="..."]` blocks. The two must stay in
sync; if you add a token, add it to ALL four bundles AND extend the
preview array in `lib/themes.ts` so this gallery reflects truth.

## Why the studio's font stack is the iOS font stack

User-stated direction: we're "building our own font family system
with JetBrains Mono as inspiration, Newsreader as another inspiration,
and Inter as another inspiration." Until that custom family ships,
these three ARE the fonts — and the studio uses them too so the
mocks render exactly how iOS will. Three faces, three roles:

- **Newsreader** — display / headlines / large numerals
- **Inter** — body / paragraphs / UI text
- **JetBrains Mono** — chrome / channel labels / eyebrows / status pills

Per-theme typographic differentiation is in WEIGHT + TRACKING +
italic discipline. Same face everywhere.

## Anchor themes (what each one says)

- **Scope** — the default. Warm cream paper, brass amber phosphor,
  charcoal trace. Editorial; subtle glow. Display 500w / -0.018em,
  italic accent allowed (per the "Editorial." italic example).
- **Midnight** — cool studio scope flip. Green phosphor on near-black.
  Same Newsreader weight (500w) but tracking opens slightly (-0.015em)
  since dark backgrounds read tighter. Halo glow is brand.
- **Tactical** — olive drab field unit. Display drops to 400w,
  tracking tightens (-0.012em) — less editorial, more workhorse. Glow
  off. No italic accent (utility doesn't romance).
- **Ghost** — near-white stationery. Display 400w with the most-open
  tracking (-0.02em) for a magazine-paper feel. Italic accent
  encouraged. Zero glow.

## Why a separate gallery page (not embedded in `/iphone-themes`)

iphone-themes is the *scaffold* — drop a mock into 4 PhoneFrame
slots, see how it renders. The Themes gallery is the *reference* —
explains the language each theme speaks before you mock anything.
Two different jobs.

## Open questions

- Should this page also include a typographic ladder per theme (h1
  through h6 + body + caption + mono variants)? Right now it states
  the type stack but doesn't render it. Worth a follow-up section.
- "BehaviorPill" indicator (filled vs outline circle) is studio
  chrome — should it adopt a more on-brand glyph?
- The `Editorial.` italic moment in each card uses inline italic to
  show off the italicAccent flag. Some themes might want to be more
  restrained — flag worth re-examining.
