# Mac Skills — Decisions Log

## What this study renders

The committed shape of Talkie's macOS Skills surface: **one tab, one
page, the whole loop**. Pre-Swift.

Single mac window at 1180 width. The composition top to bottom:

1. **Header** — `· SKILLS · ` eyebrow, italic state line, status chip
   ("DAILY STANDUP · EDITING"), serif title.
2. **Editor bay** — chat (agent) ↔ markup (`.skill.md`). The space
   where iteration happens. Always visible.
3. **Console strip** — last run, ✓ marks. Cheap to scan.
4. **Starters row** — three cards. The one being edited shows an
   amber border + soft amber fill, an `EDITING` chip, and `OPEN
   ABOVE ↑` instead of `USE →`.
5. **Your skills** — populated with three cards demonstrating all
   three skill modes:
   - **Pull Calendar** — atomic skill (single action). Standard chip.
   - **Morning Routine** — composed skill, DO is `sequence(3)` over
     other skills. Standard chip; the pipeline preview signals
     composition.
   - **Brain Dump Processor** — workflow-graduated skill. Brass
     `WORKFLOW` chip + "OPEN IN EDITOR →" CTA + brass eyebrow.
     Visually distinct from amber atomic/composed cards.
6. **Where it fires** — 3-up preview row showing invocation surfaces:
   Compose (action chip), Voice (listening HUD with "say standup"),
   Library (apply-to-memo dropdown). Each preview is a slice of a
   real Talkie surface with the active skill highlighted.

The page reads top to bottom and the journey is visible without
leaving the surface: pick a starter at the bottom, watch it open in
the editor above, iterate via chat, run, save, see it land under
"your skills."

## What we dropped

- **"Forge"** as a name. It was a useful working word during the
  framing study (mac-skill-forge), but it isn't a committed product
  name. This study uses "Skills" — the section name — for everything.
  The editor bay isn't called anything; it's just where you talk to
  the agent about the active skill.
- **Five-frame progression.** Earlier draft stacked five mac windows
  to walk through the journey. Heavier and less honest than just
  showing the surface mid-iteration. One frame, one moment, one
  story.

## Why this shape

- **Same surface for picking and iterating.** No modal, no separate
  authoring tab. Starters live below the editor; clicking one loads
  it into the editor above. Saving lands it under "your skills" at
  the foot. The viewport pans the user's attention naturally.
- **Editor is always visible.** Even on day one with nothing
  selected, the editor bay is there waiting — chat invitation,
  empty markup. The user knows what the workspace is before they
  touch anything.
- **Console is part of the page, not a drawer.** Running a skill is
  a first-class action; console output should be as quiet/loud as
  the user's expectation of "what just happened?"
- **Empty state is a destination.** The dashed "your first skill
  will land here" panel isn't filler — it's a promise. After the
  first save, this panel becomes the first thing the user sees on
  future sessions, so the design has to feel like a place.
- **Invocation previews close the loop.** "Where it fires" is the
  payoff — the user sees the authored skill manifesting in Compose
  (smart-action chip), Voice (anywhere-trigger), and Library (apply
  to existing memo). Skills aren't just edited here; they ripple
  out to the rest of the app. This section is a "promise of reach"
  that the gallery alone can't make.
- **Three skill modes share one card shape.** Atomic, composed, and
  workflow skills all use the same card primitive — what changes is
  the pipeline preview text, the status chip, and the CTA. The brass
  color signals "this one lives in the legacy graph editor." Same
  visual grammar, three states.

## Open questions

- **Scroll vs no-scroll at 1180.** Composition is currently ~720pt
  tall — fits without scroll on default mac window heights. If we
  push the editor bay taller or add a "your skills" populated row,
  it tips into scroll. Decide before Swift port.
- **Active card UX.** Right now the EDITING starter card shows
  `OPEN ABOVE ↑`. Is the up-arrow legible, or does the active card
  need a different visual (e.g., a small connection line to the
  editor bay above)? Worth a second look on device.
- **Where does "+ NEW SKILL" live?** Currently implied by `⌘N`
  in the empty-state row. A visible primary button might be more
  inviting — but adds another CTA on a page that already has
  RUN / SAVE.
- **Markup edit-in-place vs chat-only.** Markup pane is rendered
  read-mostly. Clicking into a line should make it editable, but
  most users will drive via chat. Decide cursor affordance on
  hover.
- **Multiple skills in flight.** The composition assumes one active
  skill at a time. What if a user wants to draft three? Tabs in the
  editor? Recent-drafts dropdown? Out of scope here.
- **Starter set growth.** Three starters is the right density at
  1180. If we ship more, do we paginate the row, add a "browse
  starters" surface, or live with horizontal scroll?
- **Invocation surfaces beyond three.** Current previews: Compose,
  Voice, Library. Other plausible surfaces: notch quick-access,
  menubar palette, dictation post-process, recording stop hook.
  Pick a set of three for the canonical row; deeper inventory could
  live in a settings sub-panel.
- **Per-skill enablement.** Does every skill fire in every surface,
  or do users choose ("this one is voice-only, that one is
  Compose-only")? The previews currently assume universal — needs
  thought.

## Why these decisions (not changes)

- **No SchemeCard wrapper.** Scope-only pre-Swift. Modern/Technical
  variants are a separate study if we ship them.
- **No width-stamping.** Width isn't the variable in this study —
  the *shape of the surface* is. Single 1180 frame.
- **mac-skill-forge stays.** Earlier framing study is a record of
  the comparison that produced this shape. Not deleted.

## Component map

- `app/mac-skills/page.tsx` — route wrapper.
- `components/studies/MacSkills.tsx` — composition root.
- Sub-components inline:
  `Header`, `EditorBay`, `ConsoleStrip`, `SectionLine`,
  `StartersRow`, `YourSkillsRow`, `StarterCard`,
  `WhereItFires`, `PreviewShell`,
  `ComposePreview`, `VoicePreview`, `LibraryPreview`,
  `MiniChip`,
  `Footer`,
  `PaneHeader`, `Chip` (amber/brass/ink tones), `ChatPane`,
  `MarkupEditor`, `MarkupLine`.

Promotion candidates if a second study needs them:
- `<MarkupEditor>` + `<ChatPane>` — also used in mac-skill-forge.
  Worth promoting to `components/studies/primitives/` once they
  diverge less than they converge.
