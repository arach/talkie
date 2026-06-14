# Talkie — Live markup overlay toolbar design review

**Date:** 2026-06-13
**Reviewer:** talkie-card-t-5aezgl (Claude, project-native relay)
**Source screenshot:** `~/Library/Application Support/Talkie/Tray/screenshots/Talkie Capture - 2026-06-13 15.57.14 - Region - 568x385 - be1cb8aa.png`
**Files:** `apps/macos/{Talkie,TalkieAgent/TalkieAgent}/Resources/CaptureMarkup/overlay.{html,css,js}`
**Intent:** design memo + implementation risks. Not a patch. Operator triages before any edits.

> **Vocabulary (name the parts).** I call the whole bottom-centered glass container the **dock**. The always-visible bottom row is the **primary rail**. The collapsible row above it is the **style drawer**. The five drawing tools form the **tool segment**; Agent/Demo is the **mode switch**; the single button that previews+opens presets is the **style chip**; Undo/Done/Cancel is the **commit cluster**. Reuse these names in Swift/JS/chat.

---

## 0 — State of the two copies (read this first)

The screenshot does **not** match the current `TalkieAgent` HTML. The two app copies have diverged:

- **`Talkie/…/overlay.html`** = the *old flat layout* — one `.toolbar` with ~20 equal-weight controls (`Select Pen Circle Arrow Note | Agent Demo | Sticky Bubble Glass | Solid Dash Glow | ●●●○ | M H | Undo Done Cancel`). **This is what the screenshot shows**, wrapping into 4 ragged rows. This is "the messy one."
- **`TalkieAgent/…/overlay.html`** = a *started-but-unfinished redesign* — a `.markup-dock` wrapping a hidden `.style-panel` (Note/Line/Color/Stroke groups) + a compact `.toolbar` (`S Pen C A N | Agent Demo | Style | Undo Done Cancel`). This is the right idea but it is **not wired** (see Risks R1/R2).
- **`overlay.css` and `overlay.js` are byte-identical** across both apps and only know about the *old flat* structure.

So the redesign instinct already exists in the Agent copy — it just stalled. This memo finishes that thought.

---

## 1 — Why the screenshot reads as messy

**Off.**
1. **No hierarchy.** ~20 controls at one visual weight, one pill shape, one size. The eye has no entry point — tools, a global context switch (Agent/Demo), style presets, and the commit actions all look like peers.
2. **Wrapping destroys grouping.** The `.divider` hairlines (overlay.css:122) only separate *within a row*. Once the bar wraps at a 568px region width, the dividers land mid-row or vanish and the four rows split groups arbitrarily (`Done`/`Cancel` orphaned on row 4).
3. **Three visual languages collide inline** — word-pills (`Sticky`), color dots, and bare actions — with no spatial separation, so color swatches read as "more buttons."
4. **Two things fight for the one strong accent.** Active tool fill and `Done` are *both* solid white (overlay.css:84–92). Nothing signals "this is the primary action" vs "this is selected."
5. **The capture region is small.** This shot is 568×385. Any resting bar wider than ~520px wraps. The flat layout has no overflow strategy, so it always wraps on region captures.

---

## 2 — The move: two-tier dock (finish the Agent copy's direction)

Keep **everything reachable**, but resting state shows only what you act on most. Presets move one tap away into the drawer — not gone, just folded.

```
            ┌─────────────────────────────────────────────┐
  drawer →  │  NOTE  Sticky Bubble Glass   LINE  Solid …   │  (hidden until chip tapped)
            │  COLOR ● ● ● ○                STROKE  M  H    │
            └─────────────────────────────────────────────┘
            ┌─────────────────────────────────────────────┐
  rail   →  │ [⌖ ✎ ○ ↗ ▤]  [Agent|Demo]  [●Sticky·Solid▸] │ ↶  Done  ✕ │
            └─────────────────────────────────────────────┘
              tool segment   mode switch    style chip      commit
```

Resting control count drops from ~20 to ~9, and the rail fits one row inside a 568px region.

**Tool segment** — the five tools live in one *segmented track* (shared recessed background, 2px inset), not five free pills. Active tool = amber pill. **Use SVG glyphs, not letters** (`⌖`/cursor, pencil, circle, arrow, note) — the Agent copy's `S/C/A/N` are cryptic and the old full words cost width; icons solve both. WKWebView renders inline SVG crisply.

**Mode switch** — Agent/Demo is a *context* switch, not a tool, so give it its own 2-up segmented control with a hair more separation. Keep the words; they carry meaning.

**Style chip** — one button that *previews current state* (a color dot + `Sticky · Solid`, or just the swatch + a `▸` chevron) and toggles the drawer. This is the crux: it keeps note/line/color/stroke presets one tap away while removing ~10 buttons from the resting bar.

**Commit cluster** — Undo as an icon (`↶`), Done as the *only* solid-fill button, Cancel demoted to a ghost `✕`.

---

## 3 — Make it feel like a Talkie thing

The chassis is already 80% there — keep the dark glass (`rgba(12,13,15,.78)` + `blur(18px)`, overlay.css:56–59). The brand work is in the **accent**.

1. **Amber is the selection color; white is the commit color.** Resolve the collision in §1.4 by giving the two whites distinct jobs: **amber** (`--tk-amber: #E0A23C`, the same family as the sticky-note border `#D9912B` at overlay.js:46) marks *what is selected* — active tool, active preset, active mode. **Solid white** is reserved for the *one* commit action (`Done`). Two accents, two meanings, no fight.
2. **Reuse the "channel label" primitive.** The Scope review (`2026-05-17`) established lowercase amber smallcaps with a leading bullet (`• NOTE`) as the strongest brand signal after the brass palette. Use it for the drawer's `.style-label`s — instantly ties this surface to the rest of the app.
3. **Group by space, not hairlines.** Drop most `.divider` bars; let the segmented tracks and gaps do the grouping. Keep at most one divider, before the commit cluster.
4. **Quiet the swatches.** In the rail, the style chip shows only the *active* color. The full 4-swatch palette lives in the drawer. (Active swatch ring is already nice, overlay.css:117–120 — keep it.)
5. **Surface the keyboard shortcuts** as tooltips (`Pen — P`). The single-key bindings already exist (overlay.js:1138–1156: s/p/c/a/n/t/l/1/2) — exposing them makes it read as a pro tool, not a toy, at zero chrome cost.

### Concrete CSS direction

```css
:root { --tk-amber: #E0A23C; --tk-ink: #101318; }

/* dock = the positioned column; rail + drawer stack inside it */
.markup-dock {
  position: fixed; left: 50%; bottom: 26px; transform: translateX(-50%);
  z-index: 2; display: flex; flex-direction: column-reverse; align-items: center;
  gap: 8px; max-width: calc(100vw - 28px);
}
.toolbar {              /* the primary rail */
  position: static;     /* dock owns positioning now */
  flex-wrap: nowrap;    /* never wrap — overflow goes into the drawer */
  gap: 8px; padding: 6px;
}
/* segmented track for the tool group */
.tool-segment { display: flex; gap: 2px; padding: 2px;
  background: rgba(255,255,255,.06); border-radius: 12px; }
.tool { width: 28px; height: 28px; padding: 0; }      /* icon buttons */
.tool.active, .mode.active, .note-style.active,
.line-style.active, .width.active, .swatch.active-ring {
  color: var(--tk-ink); background: var(--tk-amber);  /* selection = amber */
}
.action.done { color: var(--tk-ink); background: #fff; }  /* commit = white */
.action.cancel { background: transparent; color: rgba(255,255,255,.5); }

/* drawer: same glass, animates in above the rail */
.style-panel {
  display: flex; gap: 12px; padding: 10px 12px;
  border: 1px solid rgba(255,255,255,.16); border-radius: 16px;
  background: rgba(12,13,15,.78);
  backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px);
  transition: opacity .14s ease, transform .14s ease;
}
.style-panel[hidden] { display: none; }
.style-label {           /* the "channel label" primitive */
  font: 650 9px/1 system-ui; letter-spacing: .08em; text-transform: uppercase;
  color: var(--tk-amber); }
```

Auto-close the drawer on tool change and on canvas click so it never lingers over the markup.

---

## 4 — Implementation risks

- **R1 — the Style button is dead; presets are currently unreachable in the Agent build (highest).** `overlay.html:63` emits `data-action="toggle-style"`, but the click handler (`overlay.js:938–986`) only handles `undo`/`done`/`cancel`. The `.style-panel` ships with the `hidden` attribute and nothing ever removes it. So in the TalkieAgent copy, Note/Line/Color/Stroke presets are **inaccessible right now** — a direct regression of the "keep presets accessible" goal. Must add a `toggle-style` branch (flip `hidden`, sync `aria-expanded`) before the drawer can ship.
- **R2 — no CSS for the new structure.** `overlay.css` styles only `.toolbar`, `button`, `.swatch`, `.divider`, `.note-editor`. There are **zero** rules for `.markup-dock`, `.style-panel`, `.style-group`, `.style-label`, `.style-toggle`, `.compact-tool`, `.compact-action`. Critically, `.markup-dock` is unpositioned — only `.toolbar` is `position: fixed` — so the new wrapper renders the drawer in document flow until the dock takes over positioning (see §3 CSS).
- **R3 — divergent copies.** `Talkie` HTML = old flat; `TalkieAgent` HTML = new drawer; CSS+JS identical and old-only. All three files are untracked/new. Pick one source of truth and re-mirror **all three** files; today the two apps render different toolbars from the same CSS/JS.
- **R4 — pointer guard scope.** Canvas drawing is suppressed via `if (toolbar.contains(event.target)) return;` (`overlay.js:622`) plus the toolbar's own `stopPropagation` (`overlay.js:934`). The new `.style-panel` sits **outside** `#toolbar`, so neither covers it. In practice the panel is a sibling of the canvas (not a descendant), so canvas pointer handlers shouldn't fire on it — but verify, and if the dock is restructured, extend the guard to `markupDock.contains(...)`.
- **R5 — `syncToolbarState` doesn't know about a style chip.** `overlay.js:989–1009` toggles `.active` on `.tool/.mode/.swatch/.width/.note-style/.line-style`. A new style chip that previews current color/preset must be updated there too — otherwise `setMode` (`overlay.js:1022–1035`, which overwrites color/stroke/noteStyle/lineStyle from presets on every Agent↔Demo switch) will silently change state the chip still shows stale.
- **R6 — icons.** Inline SVG in the WKWebView is the elegant, crisp route for the tool glyphs; avoid emoji (inconsistent metrics/baseline). Keep `aria-label`s already present on the compact tools.

---

## 5 — Next owner

Design guidance is complete and self-contained above — no further review needed from me. **Next move belongs to whoever ships the markup polish on `codex/polish-library-thumbnails`:** wire R1 (toggle handler), add R2 (drawer/dock CSS), and resolve R3 (re-mirror the three files to one source of truth). R1 is not just polish — the Agent overlay currently ships an unreachable preset drawer.
