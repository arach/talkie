# Mac Skill Forge — Decisions Log

## What this study renders

Two surfaces stacked inside a single mac window:

1. **Starter gallery** — three cards previewing built-in skills.
   The entry surface — this is what you see before authoring anything.
2. **Three editor framings** — A markup-primary · B chat-driven · C trifold.
   What you see *after* picking a starter (or starting blank).

No Swift source yet — this study is upstream of any port.

## The exploration that produced this

- A **skill** (not a "workflow") is a semantic description of intent:
  what to do when a trigger fires. Reads more like a telegram than a
  wired-up block graph.
- The markup is **voice-dictatable, diffable, agent-writable**.
- The console is already running in Talkie. Piping a skill at it costs
  nothing — that's the run loop.
- The editor is a **WebKit-hosted CodeMirror**, not a native code view.
  Native code editors are a decade of work to reach parity with the web;
  skills are short, the cost isn't justified.
- Originally proposed four ways (map · chat · markup · form). Pared to
  two essentials for the starter (markup + chat) with map as a derived
  lens. Form is parked until a node makes the markup genuinely fiddly.

## The skill syntax (mock)

Four keywords, each a single uppercase token, amber, followed by a
content tail. Sub-fields indent with `↳`. Mono throughout.

```
WHEN  voice "log bug"

WITH  region screenshot
      ↳ last paragraph

DO    github.issue
      ↳ title  ← derive from selection
      ↳ body   ← selection + screenshot

THEN  voice ack
```

This is a wireframe of the syntax shape, not a committed grammar.
The point is: keywords read at a glance, the body is short enough
to dictate, and it diffs well in git.

## Starter gallery

Three starters as cards, in a 3-column grid at 1180:

1. **Log Bug** (Productivity · READY) — the one we use throughout
   the editor framings. Voice → region + last paragraph → GitHub issue.
2. **Daily Standup** (Comms · READY) — voice → dictation → Slack post.
   Tightening pass via Claude implicit in the DO step.
3. **Capture Thought** (Personal · DRAFT) — voice → dictation →
   auto-tagged library note. Drafted state to show what "not yet
   ready" looks like.

Card anatomy (top to bottom):

- Eyebrow: `· CATEGORY · S-NNNN`
- Title (font-display, 20pt)
- Italic byline (Newsreader, one line, voice-y)
- Hairline rule
- Compact pipeline preview — `WHEN voice · WITH region · DO github · THEN ack`
- Footer: status chip (READY/DRAFT) + `USE →` or `OPEN →` affordance

The pipeline preview is the same syntax as the editor body, just
compressed to one line. That's the through-line: same vocabulary in
the gallery and the editor, so picking a starter feels like reading
a sentence in a smaller font.

**Why only three?** Anything more and the row starts to look like
an app store. Three reads as "here's a flavor of what's possible" —
the full set lives in a library surface, out of scope here.

**Why ink-toned section break for starters, amber for framings?**
Amber is reserved for the keyword highlights (WHEN/WITH/DO/THEN)
and the framing labels — those are the *variables* of the study.
The starters are a quieter section, marked with the standard ink
eyebrow.

## Three framings

### A · Markup-primary

The IDE shape. Editor takes the bulk of the surface; outline (derived
from markup) is a thin right rail; console pinned below.

- **Strengths:** highest editing throughput; feels like writing code
  (because it is); the outline makes structure visible without
  duplicating the source.
- **Weaknesses:** non-coders may not approach it; agent feels absent
  unless explicitly invoked.

### B · Chat-driven

Agent composes the markup, you tweak. Chat is the primary input;
markup is the receipt of what the agent did.

- **Strengths:** lowest floor for new users; voice-first flow ("make
  a skill that…"); markup learns by reading what the agent writes.
- **Weaknesses:** wide chat pane wastes pixels once you're proficient;
  always-on agent feels heavy for a one-line edit.

### C · Trifold

Chat (narrow) + markup (wide) + derived map (narrow). All three lenses
on the same source. Map is read-only — it's not an editor.

- **Strengths:** every cognitive style is served (visual / textual /
  conversational); shows the "lenses on one source" principle clearly.
- **Weaknesses:** three panes is busy at 1180; eyes don't know where
  to land; risk of looking like a Zapier knockoff.

## Recommendation embedded in the study

**Start with A (markup-primary).** Add chat as a pop-over or sidesheet
that the user opens explicitly, not a permanent pane. The map becomes
a separate "view as map" toggle on the markup pane once the syntax is
stable.

That gets the best framing (markup as source of truth, console for
feedback) without committing to the multi-pane sync work that B and C
demand.

## Open questions

- **Naming.** "Skill Forge" is the working title — has the right
  artisanal tone (Compose, Notch, Tray are all shape-words). "Workshop",
  "Bench", "Studio" all rejected (studio conflicts with the design
  studio itself; workshop is generic; bench is mechanical).
- **Markup syntax.** WHEN / WITH / DO / THEN reads cleanly but isn't
  committed. Alternatives: YAML (familiar but verbose), Markdown-with-
  headings (literate but ambiguous), pure DSL with parens (powerful but
  cold). Picking the grammar is the next study.
- **Run target.** The console shows a single run with three checks.
  Is "run" a one-shot test or does it actually fire the side effects
  (creating a real GitHub issue)? Likely needs a dry-run mode with a
  separate "arm" button before the real trigger is enabled.
- **Voice authoring.** The VOICE chip in the chat input row is a stub.
  How does dictating WHEN/WITH/DO/THEN actually work — does the user
  say the keywords, or does the agent infer them from prose?
- **Trifold legibility.** At 1180 the three panes are tight (252 /
  flex / 224). Either the chat or the map needs to be collapsible.

## Why these decisions

- **No SchemeCard wrapper.** Pre-Swift, Scope-language only. Forging
  Modern/Technical variants would happen after the framing is picked.
- **Same stub skill across all three.** "Log Bug" — capture a region,
  open a GitHub issue, voice-ack. Concrete enough to read; short enough
  to mock at three layouts.
- **No width-stamping.** Other mac studies use MacWindowGrid to model
  breakpoint behavior. This study's variable is the framing, not the
  viewport — single 1180-width frame, three sections inside.

## Component map

- `app/mac-skill-forge/page.tsx` — route wrapper, single MacWindowFrame.
- `components/studies/MacSkillForge.tsx` — composition root.
- Sub-components inline:
  `ForgeHeader`, `FramingBreak`, `ForgeFooter`,
  `FramingA`, `FramingB`, `FramingC`,
  `Surface`, `PaneHeader`, `Chip`,
  `MarkupEditor`, `MarkupLine`,
  `OutlinePane`,
  `ChatPane`, `ChatInputRow`,
  `ConsolePane`, `ConsoleStrip`,
  `MapPane`, `MapNode`, `MapConnector`.

Promotion candidates if a second study needs them:
- `<MarkupEditor>` — would be reused by any "code-in-a-paper-pane"
  surface (skill editor, workflow rules, future config files).
- `<Chip>` — already drifts toward `<Chip>` in MacCompose. Worth
  unifying at the primitive layer.
