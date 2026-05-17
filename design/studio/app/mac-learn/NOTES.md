# Mac Learn — Decisions Log

## What this study replaces

The current `ScopeStatsScreen.swift` is "things you've done" data —
total dictations, heatmap, top apps. The user's read (2026-05-17):
**"unsatisfying. I don't know if it's the stats page that we need.
I think we might need something else, like learn."**

This study is the alternative. Not a dashboard, an **interstitial**.

## What the page is for

Three things, in order of frequency:

1. **Surface area in front of you.** Talkie has accumulated cool
   features (Workflows, Context Rules, Console, Compose, diffs,
   Hyper+S, etc.) that users don't necessarily know about. The page
   puts them in front of you visually.
2. **Ask the agent about Talkie.** An "Ask Talkie" box — "How do
   workflows trigger?" / "Can a context rule scope to one app?" /
   "What's bound to Hyper+S?". The agent has access to Talkie's
   capabilities and answers in context.
3. **"Did you know?" recaps.** Existing features that the user might
   not have discovered. Phrased as recaps with light interactivity —
   "Did you know you can diff compose edits?" with a small visual /
   try-it action.

## Composition

| Section | Intent | Source from user vision |
|---|---|---|
| **Hero** | Frame the page as a question, not a metric | "something inspirational" |
| **Ask Talkie** | Agent Q&A interstitial | "agent experience where it's like learn and ask questions" |
| **Did you know?** | Recap existing features (3 cards rotating) | "say hey did you know you could do diffs" |
| **Feature atlas** | Illustrated grid of surfaces | "illustrated knowledge base with interactive components" |
| **Integrations** | LLM providers + APIs the user can plug in | "do you have an API that we could use for LLMs we support XYZ" |
| **What's new** | Recently shipped (changelog-ish strip) | momentum / discovery for active users |

## Design principles

1. **No marketing copy.** Hero is a question, not a tagline. Feature
   cards use data lines + visuals, not aspirational verbs. Per the
   feedback memory on `grotesque` taglines (2026-05-17).

2. **Illustrated, not photographic.** Each feature card has a tiny
   visual that explains it at a glance — a node graph for Workflows,
   a tag chip for Context Rules, a terminal prompt for Console. Light
   SVG marks, not screenshots.

3. **Recap is fresh attention, not changelog.** "Did you know" cards
   surface *existing* features as if they were new — to the user who
   missed them, they ARE new. Distinct from "What's new" which is
   actually-recently-shipped.

4. **The agent box is the anchor.** Even when no question is typed,
   the suggested chips invite use. The page is meant to be returned to
   when you're curious, not when you want a daily report.

5. **Inherit Scope language.** Same tokens, same eyebrow pattern,
   same chrome conventions as Mac Home. The page reads as the same
   surface, just doing a different job.

## Open questions

- Whether "Learn" is the right name vs Discover / Atlas / Briefing.
  Going with **Learn** for now per the user's first phrasing.
- Whether this section replaces Stats in the sidebar or sits next to
  it as an additional surface. Studio-side, it's just a new study;
  the Swift sidebar question can wait.
- How much of the agent is real vs decorative on first port. For
  the Swift port, even a static FAQ-style "Ask Talkie" with curated
  Q&A would be useful — the integration with a real LLM that knows
  Talkie's capabilities is a follow-up project.
- Whether the feature atlas should include preview / try-it
  interactions inline (e.g. type into a compose mini-canvas to see
  diff feature) or just navigate to the real surface.

## Component map

- `components/studies/MacLearn.tsx` — composition root
- Sub-components inline:
  `TopBand`, `Hero`, `AskTalkie`, `DidYouKnow` / `RecapCard`,
  `FeatureAtlas` / `FeatureCard` + per-feature glyphs,
  `Integrations` / `ProviderTile`, `WhatsNew`, `SectionBlock`
