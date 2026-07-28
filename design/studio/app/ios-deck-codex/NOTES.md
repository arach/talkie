# iOS Codex Deck — lane picker and host signals

Route: `/ios-deck-codex`

Study: `design/studio/components/studies/CodexDeckLaneSignals.tsx`

## Decision carried forward

T2, **Bottom Sill Rail**, is settled. The voice trigger sits outside the grid in the lowest reachable band. It remains a 351 × 76pt target, inset 18pt above the home indicator, in every treatment and state.

The earlier T1–T5 ergonomics study is now a collapsed decision record on the route. This round changes only the lane picker and the signal treatment above the rail.

## The lane picker is an instrument area

The first version of this study drew the picker as loose controls on a black screen: six pills in the same material as the utility grid tiles, an unhoused identity card floating above them, and 324pt of empty band. It read as a generic app screen that happened to be dark. Nothing about it said *Deck*.

The fix was structural, not decorative. Everything the picker needs is now inside **one bounded, recessed technical field** — the Codex counterpart to the Deck's trackpad area. The Deck's trackpad is a pointing surface and this is a channel selector, so the shape is not copied; what carries across is the material logic. Chassis is ground. Each module is one recessed field routed into it. Controls are seated in a pocket, lifted by their own top highlight. Legends are printed on the chassis, not floated over it. Amber is spent only on a state that has actually been verified.

### Vocabulary

Named for the whole pipeline — studio, Swift, and chat should use these words unchanged. The route renders the same table under **Names**.

| Term | Meaning |
| --- | --- |
| **Lane Console** | The bounded, recessed field the entire picker lives in. One module, not a row of loose controls. Aligned to the same 12pt gutter as the utility grid and the rail. |
| **Lane Bed** | The deeper routed pocket inside the console that the lane keys are seated in. |
| **Lane Key** | One seated bank key — a numbered channel selector at 44pt. Its material carries state; its position never moves. |
| **Group Seam** | The routed groove separating the six lane keys from the mapper key. A divider, not an empty gap. |
| **Task Readout** | The instrument's display: the tier that answers *which exact task, and is that still true?* Fixed-height in L3, a caption in L4, the whole field in L5. |
| **Silkscreen** | The printed legend across the console's top edge — module name left, current target right. |
| **Console Footer** | The hairline strip closing the console's bottom edge. Carries the last delivery receipt, or the printed sentence that stands in for one. |
| **Rail** | The settled T2 voice control. Never moves. |

The brief suggested *Channel Bed*. **Lane Bed** was chosen instead so a single word — LANE — covers a single concept everywhere: lane, lane key, lane bed, lane console, lane binding. "Channel" would have introduced a second noun for the thing the user already calls a lane, and the six positions are lanes in the product, in the host protocol, and on the phone.

### What was borrowed, and from where

| Source | Grammar taken | Where it lives here |
| --- | --- | --- |
| `components/studies/IOSDeck.tsx` | The chassis → console → keybed → keytop depth ladder, modelled purely in `boxShadow`: inset rings for recesses, drop shadow plus an inner top highlight for lift. | Lane Console is inset into the chassis; Lane Bed is inset again inside it; Lane Keys sit on top with `CAP_TOP` / `CAP_BOTTOM` / `CAP_LIFT`. |
| `components/studies/IOSDeck.tsx` · `Silkscreen` | 7px uppercase legend at `0.26em` tracking, printed in a subtle ink directly on the surface. | The console's top-edge legend and every `ConsoleNote`. |
| `components/studies/IOSDeck.tsx` · `Pad` | The tape-grain fill — a 135° repeating stripe at ~10% opacity — plus corner sheen and vignette, which make a surface read as a screen rather than a hole. | The Task Readout's face. |
| `components/studies/DeckKeyBed.tsx` | One recessed bed holding all keys, with a Group Seam rather than a gap where the key groups change function. | Lane Bed, and the seam before the mapper key. |
| `components/studies/DeckKeypad.tsx` | The faceplate recess: a module gets its own bounded plate with a visible lip, so it is legible as a part. | The Lane Console's outer recess and lip. |
| `app/ios-deck/page.tsx` · `NamesMarginalia` | Naming a study's parts in a table so studio, Swift, and conversation share one vocabulary. | The **Names** section above. |
| Tactical theme, `app/globals.css` | The palette itself — `--theme-amber` reserved for verified state, `--theme-screen-trace` for the readout grain, the three ink tiers for hierarchy without new colours. | Throughout. Amber appears only on a fresh confirmation and the live rail. |

Nothing was copied wholesale. The continuity is in the material logic, not in the shapes.

## Five treatments

All five now use the same console, bed, key, readout, silkscreen, and footer. **The comparison is how each one divides the same field.** The console is sized by a ceiling, not a fixed height, so each treatment shows its true cost in vertical space and none can crowd the quiet chassis above the utility grid.

### L1 — Numbered Strip · Central Status

Bed plus a single-line readout. The cheapest use of the field and the quietest, but long titles and same-name tasks expose the limits of one status line.

Parameters: selected emphasis, identity line, confirmation freshness, failure disclosure, task recency.

### L2 — Selected-Lane Expansion

No second tier at all: the bed *is* the identity surface. The selected key grows a readout face inside the same pocket while the others collapse to slots. It puts detail at the point of selection, but must reserve row height to prevent reflow and preserve muscle memory.

Parameters: expanded height, collapsed slot, identity lines, reserve row height, task recency.

### L3 — Two-Tier Identity

Bed and readout as the console's two tiers, sharing one bounded field. Six fixed keys answer *which lane*; a fixed-height readout answers *which exact task, and is that still true?* It keeps switching fast while leaving room for project, long title, task ID, freshness, and the phone's own in-flight count. The `edge rule` confirmation style drives the readout's own amber lock rim rather than adding a badge.

Parameters: readout height, title lines, task ID tail, confirmation badge, task recency, your in-flight count.

### L4 — Per-Lane Status Glyphs

Taller keys take the field; the readout shrinks to one line and the footer carries the caption. Signals live directly on each lane, which scans beautifully but risks implying a six-lane activity feed that does not exist. With the current contract, unselected lanes may honestly say only "bound." Proposed activity lights are dashed and explicitly labelled, and the footer says so in words.

Parameters: glyph vocabulary, project initials in slot, unmapped slots, proposed per-lane activity.

### L5 — Current-Lane Plate · Switch Sheet

The console inverted: the readout takes the field and the bed shrinks to a transport strip. It is the calmest single-lane view and the strongest mapper on-ramp, but adds friction to frequent lane alternation.

Parameters: sheet trigger, quick-swap arrows, show sheet open, unmapped rows in sheet, task recency.

## Recommendation

Choose **L3 — Two-Tier Identity** on the fixed T2 rail.

It is the only treatment that survives all required scenarios at its default settings without moving the six lane targets or inventing host data. It also handles the collision case: two projects with the same task title, a long title, and a stale confirmation. In the instrument reading it is also the most resolved — bed and display are the two things an instrument of this kind actually has, in the proportion it would actually have them.

The final refinement keeps the quiet chassis instead of compressing every surface into the thumb zone. The exact task title is now the strongest readout element; confirmation moves into the display rim and a small inline lamp; the rail rests as dark steel and illuminates only while active; and the four unused matrix positions read as recessed numbered sockets rather than missing controls. Connected bridge chrome and the idle rail rim stay neutral so amber retains its meaning, and typed failures occupy the readout instead of expanding the console past its ceiling. This preserves the deck's instrument grammar without letting secondary chrome compete with the task being addressed.

Borrow L5's sheet as the mapper and overflow surface, not as the primary switcher. Keep L4's restraint as a rule: unselected keys may show binding, never fabricated live activity.

The production pass keeps this L3 layout in both appearances. Dark mode raises the console, keys, and rail one clear step above the black chassis so their edges do not disappear. Light mode uses the existing Scope paper chassis and the softer rounded caps from the earlier Codex lane mocks, while retaining a dark graphite task readout for exact identity. This is a material adaptation, not a layout fork: lane positions, the 112pt readout, the 3×4 navigation grid, and the 76pt rail stay fixed. During an active turn, the rail exposes adjacent 44pt queue and steer selectors without moving the rail itself.

## Signal boundary

### Available from the Mac host now

- Task catalog: exact ID, title, preview, cwd, updated time.
- Validation receipt: exact ID, title, cwd, or a typed error.
- Delivery receipt: task ID, optional turn ID and response, plus `started-turn`, `queued-turn`, or `steered-active-turn`.
- Typed failure code and the Mac's recovery hint.

### Derived on the phone now

- Bridge connectivity.
- Lane bindings and current selection.
- Confirmation age and freshness.
- Voice-loop phase.
- The user's queue/steer choice and last delivery receipt.
- Talkie-originated messages still in flight. This is not host queue depth.

### Proposed host extension

- A cheap batched status read for known task IDs, so a lane may truthfully show active, idle, or awaiting approval before selection.

Queue depth, queue position, progress, ETA, current tool, token usage, and execution stage remain unavailable. The study labels all such signals **PROPOSED**, draws them dashed, and keeps them off by default.

## Scenario set

The global scenario control drives mapped, confirmed, listening, waiting, approval, and title-collision states. Each treatment also supports a local scenario override so the comparison can hold multiple edge cases on screen at once.

The activity-feed proposal is a separate global switch. It exists to expose the contract gap, not to imply that the current host already supplies it.
