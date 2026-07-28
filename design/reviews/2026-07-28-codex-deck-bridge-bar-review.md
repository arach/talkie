# Talkie iOS — Codex Command Deck: de-buttonization review

**Date:** 2026-07-28
**Reviewer:** session-ms4xv7c9-hxfwqt (Claude, project-native relay)
**Route:** `http://localhost:3477/ios-deck-codex`
**Primary source:** `design/studio/components/studies/CodexDeckBridgeBar.tsx` (2393 lines)
**Reference implementations read:** `IOSDeck.tsx`, `DeckKeyBed.tsx`, `DeckKeypad.tsx`
**Intent:** design direction. No edits made. Operator triages before any patch.

> **Brief, in one line.** *"I do not mind the typography. What I mind is that everything is a button in a
> context where I want something that looks and feels like a nice, elegant UI."*

> **Vocabulary (name the parts).** **Bridge Line** = the 40pt chassis-level header. **Lane Ribbon** = the
> six-position lane indicator. **Turn Glass** = the black readout. **Bed** = the 4×4 key grid at the bottom.
> **Talk** = the two-slot control at grid 14–15. A **lamp** is a lit dot that is never pressable. A
> **segment** is flat lit text with no cap material. A **key** is a seated cap that presses. Reuse these
> names in TSX and in chat.

---

## 1 — Diagnosis: why everything reads as a button

Six mechanisms, all verifiable in the file. None of them are typographic.

**1. One primitive does five jobs.** `Key` (`CodexDeckBridgeBar.tsx:1079`) is the file's *only* interactive
vocabulary. It renders deck mode (`ModeKey:1256`), host target (`HostKey:1216`), and lane selection
(`LaneBed:1401`) with the identical `--cdb-cap` gradient and `--cdb-cap-shadow`. The material encodes
**state** — `on` / `dim` / `dashed` — but never **category**. Navigation, connection target, and selection
are three different kinds of act wearing one costume, so the eye can rank nothing.

**2. Two identical beds are stacked 8pt apart.** `Bed` (`:1063`) is instantiated twice — once by
`UnifiedBar`/`HostBed`/`HostFirstBar` (`:1295`, `:1323`, `:1348`), once by `LaneBed` (`:1391`) — with the
same radius (13), same `--cdb-bed-shadow`, same `BRIDGE_PAD`. The top ~140pt therefore reads as a single
11-key panel. Nothing in the composition says *this row is what I'm pointed at* and *that row is what I'm
talking to*.

**3. Passive information is wearing button clothes.** `HostKey` is simultaneously a button, a status lamp
(`:1239`), and a clock (`:1225`, `"14m AGO"`). Host liveness and last-seen are *facts*. They are drawn on
caps because a cap is the only container the file owns. Same failure on the lane caps, where a running turn
is a dash rendered inside the pressable surface (`:1422`).

**4. The file breaks its own stated rule.** `:1108` — *"Black glass. The one screen on the face — reserved
so it never reads as a key."* Then `:1503` puts a 7.5pt amber `<button>` on that glass. That STEER/QUEUE
pill is precisely the "post-send pair of tiny buttons" the brief rejects, and it is the single reason the
readout stops reading as a readout.

**5. Real buttons and fake buttons are indistinguishable — in both directions.** The eight utility tiles
(`:1822`) are `<div>`s wearing cap material at a blanket `opacity: 0.62`; they do not press but look like
they do. Meanwhile the most important press on the face — Talk — gets a shape shared with nothing else
(`SillRail:1870`, radius 18, 351×76). Affordance has fully decoupled from function. **That decoupling is
the actual mechanism behind "everything is a button":** once the cap look stops predicting behavior, the
brain gives up and reads every rectangle as pressable.

**6. The most expensive band is the one the thumb cannot reach.** The file computes this itself at
`:109-111` and then shrugs at `:730-738`: `BRIDGE_REACH` ≈ **719pt** from the thumb pivot versus ≈ **153pt**
for the rail. Five 44pt-tall targets are being paid for, in prime visual real estate, for a control that
cannot be operated one-handed. **It looks like a control panel and functions like a sign.** That is the
ergonomic core of the complaint.

**Count.** On the face today (T1, at rest): 2 mode + 3 host + 6 lane + 1 steer + 1 talk + 2 optional
steppers = up to **15 real buttons**, plus **8 key-shaped non-buttons** = **23 cap-shaped objects** competing
at one weight. The brief's word for this is correct.

---

## 2 — Recommended treatment: **"The header reads, the glass shows, one bed presses."**

One rule generates the whole composition:

> **Exactly one region of the face is made of keys.** It is the bottom grid, in thumb reach. Above it,
> nothing wears cap material. The Bridge Line is chassis and text; the Lane Ribbon is a machined groove;
> the Turn Glass is glass. Three materials, three meanings, no overlap.

This is not a new dialect — it is `IOSDeck.tsx` already: chassis masthead → glass Pad with signals *floating
on it* (`IOSDeck.tsx:435-480`) → one keybed below (`:800`). The Codex deck drifted away from the house form
by inventing a second and third bed. The direction is to come back.

### Spatially, top to bottom

**Band 0 · Status bar — 47pt.** Unchanged.

**Band 1 · Bridge Line — 40pt, chassis level. Zero keys.**
Left: deck switching as a **two-position segment**, `CODEX | CMD` — flat lit text in a hairline groove,
underline or faint amber fill, *no* `--cdb-cap`, *no* raised shadow. It is a selection, so it gets a
selection treatment. ~104pt.
Right: host as **one text line with a lamp and a chevron** — `◉ MINI ⌄`. Tap opens the host picker sheet,
which is where the fqdn, the last-seen times, and the standby list belong. ~110pt.
Between them: **air**. The top band being mostly empty is what makes it read as a header instead of a
console. This is the elegance move, and it costs 0pt — it reuses the existing `MAST_H`.

Three hosts still switch fast: one tap opens, one tap chooses. Hosts are switched every few hours
(`lastSelected` in the fixtures is 14m and 2d), not every few seconds. Spending five permanent out-of-reach
targets on that cadence is the trade that produced the current surface.

**Band 2 · Lane Ribbon — ~28pt, one recessed groove.**
Six divisions in a single machined channel — a tuner scale, not six caps. The selected division is lit; a
lane with a running turn carries an amber tick under its division. **6 buttons → 1 rail.** The selected
lane's title and project are printed in the glass head immediately below, so the ribbon never has to carry
text.

**Band 3 · Turn Glass — the subject, and the only thing that grows.**
Everything the host says lands here, and **nothing on it is pressable**. Top to bottom: head line
(`LANE 03 · TALKIE · STEER` + status word + lamp + elapsed) → the transcript you sent, against its amber
rule → the live channel of progress updates, dim, newest bright → the response, or the typed failure and
its recovery sentence → foot line with the delivery outcome. All text, one lamp.

**Lane switching happens by swiping this glass** — a large, reachable, one-handed gesture, with the ribbon
above as its position readout. That is what buys back the reachability the top band cannot provide, and it
satisfies "a user can switch lanes while turns are running" without adding a single target.

**Steer/queue becomes a printed lane attribute** in the head (`STEER` / `QUEUE` in the silkscreen register),
set from a key in the bed. Persistent lane-level mode, shown as state, changed where actions live. Exactly
as the brief specifies.

**Band 4 · The Bed — 4×4, sixteen slots, all keys, in reach.**
Slot 01 audio, at the *same* cap material as its neighbours — let the icon and label carry it, not contrast.
Slots **14+15** are Talk, two slots wide; **13 and 16 stay empty sockets** so it is flanked by air. Every
real action on the deck lives in this one region.

**Band 5 · Deleted.** No rail. The 76pt rail plus its 18pt inset return **94pt to the glass**.

---

## 3 — Inventory: what stays a button, what stops being one

| Element | Today | Becomes | Category |
|---|---|---|---|
| Deck mode CODEX/CMD | 2 seated caps (`ModeKey:1256`) | flat **segment** in the Bridge Line | selection |
| Host × 3 | 3 seated caps (`HostKey:1216`) | **one text line + chevron** → picker sheet | compact navigation |
| Host liveness | dot per cap (`:1239`) | **one lamp** beside the host name | passive status |
| Host last-seen `"14m AGO"` | sub-line on standby caps (`:1225`) | **off the face** — lives in the picker | ambient info |
| Host stepper ± | 2 caps by the rail (`:1884`,`:1919`) | **deleted** — picker replaces it | — |
| Lane × 6 | 6 seated caps (`LaneBed:1401`) | **one recessed ribbon**, 6 divisions | selection + readout |
| Lane running mark | dash inside each cap (`:1422`) | **tick on the ribbon** at that division | passive status |
| Lane title / project | text | text (in the glass head) | ambient info |
| Steer / Queue | **amber `<button>` on the glass** (`:1503`) | **silkscreen text** in the head; set by a bed key | state + true action |
| Turn status word | text (`:1493`) | text + **one lamp** | passive status |
| Elapsed | text (`:1499`) | text | ambient info |
| Transcript | text + amber rule (`:1525`) | unchanged | ambient info |
| Progress updates | text (`:1549`) | unchanged | ambient info |
| Response / failure | text (`:1582`,`:1598`) | unchanged | ambient info |
| Delivery outcome | text (`PaneFoot:1609`) | unchanged | ambient info |
| Utility tiles × 8 | `<div>`s at `opacity:.62` (`:1822`) | **real keys** in the bed | true action |
| Empty grid slots | dim numbered sockets | unchanged — an empty mount reads correctly | passive |
| **Talk** | full-width rail button (`:1899`) | **two-slot key at 14+15**, empty 13/16 | true action |

**Net.** Cap-shaped objects on the face fall from **23 → 16**, and — the part that matters — **every
pressable cap now lives in one region**, with only two non-cap affordances above it (the segment and the
chevron). Hierarchy comes from the material grammar, not from size or contrast.

---

## 4 — Implementation guidance, tied to the file

**Delete outright**
- `RAIL`, `RAIL_TOP` (`:88-90`), `SillRail` (`:1870`), `RailFace` (`:1850`). But **keep `railFace()`
  (`:1852`) as a function** — its disabled-reason ladder (stale bed → switching → no bridge → unbound lane →
  failed → running) is the best piece of state reasoning in the file. Retarget it to produce the Talk key's
  face plus the one-line reason printed in the glass foot. Do not lose it in the deletion.
- `reachStepper` param (`:522`) and both stepper buttons (`:1884`, `:1919`).
- The STEER/QUEUE `<button>` (`:1502-1519`) → replace with `<Silk>{deliveryMode}</Silk>`. **Do this edit
  first**; it is the smallest change with the largest effect, because it restores the glass rule the file
  declares at `:1108` and violates 400 lines later.
- `UnifiedBar` / `HostBed` / `HostFirstBar` (`:1295`, `:1323`, `:1348`), `ModeKey` (`:1256`),
  `HostKey` (`:1216`). `HOST_TONE` (`:1209`) survives — it feeds the lamp and the picker rows.
- `keyH` param (`:499`) and `BRIDGE_PAD` / `BRIDGE_TOP` as *bridge* constants. The "32 / 36 / 44 HIG" dial
  is a question about a control that no longer exists.

**Rescope, don't rewrite**
- **`Key` (`:1079`) becomes grid-slots-only.** This single scoping change is what fixes the complaint. Add
  two siblings beside it: `Segment` (flat, text, lit fill, no cap shadow, never touches `--cdb-cap`) and
  `Lamp` (4–6pt dot, optional word, never pressable, never rendered inside a `<button>`).
- **`Bed` (`:1063`) survives once**, as the Lane Ribbon's groove. Add a `divisions` prop so the six lanes are
  drawn as segments of one channel rather than six children with independent shadows.
- **`Glass` (`:1109`) is unchanged and becomes load-bearing** — with the rail gone and the pill removed it is
  the only non-key surface in the middle of the face, and it should absorb the recovered 94pt.
- **`UtilityGrid` (`:1806`)** — tiles become `<button>`s; grid becomes 4×4; `UTILITIES` (`:1799`) becomes a
  16-slot sparse array in the established `(Tile | null)[]` style of `IOSDeck.tsx:267`. **Remove the blanket
  `opacity: 0.62`** — that dimming is exactly why bound keys currently read as decoration. Slot 01 drops to
  neighbour contrast.
- **`Masthead` (`:1139`)** absorbs both switches. Port the form from `IOSDeck.tsx:435-480` — that
  `MAC MINI · MAC ⌄` line plus status pill is already the house pattern for "host identity + chevron +
  liveness." Reusing it is what keeps this from becoming a fourth dialect.
- **`solve()` (`:118`)** — rewrite. Inputs become `(ribbonH, borrowedRows)`; `bridgeKeyH` disappears. The
  frozen-spine thesis (`:71-78`) survives intact and gets *stronger*: three bands still never move, they are
  just Bridge Line / Ribbon / Bed instead of Bridge Bar / Lane Bed / Rail.
- **`appearanceVars` (`:986`)** — the cap material is good and is not the problem; the problem is how many
  things wear it. Add only `--cdb-seg-on` / `--cdb-seg-ink` so the segment never reaches for `--cdb-cap`.

**Unaffected.** The truth boundary (`SIGNALS:171`), the production blocker on `codex.lanes.v1`, the stale-bed
refusal, and every `PROPOSED` marking are orthogonal to this and carry over as-is. The stale-bed alarm now
lands on the ribbon and the Talk key instead of the bed and the rail.

---

## 5 — Two variations within the treatment

Same header, same glass, same materials. They differ only in how lane selection is pressed.

**A · Ribbon Only.** The ribbon is purely a readout; lanes change by swiping the glass. Cleanest face, most
elegant, all 16 slots free for utilities. **Risk:** the swipe is undiscoverable — a first-run user may never
find it, and there is no in-reach pressable path to lane 5.

**B · Ribbon + Lane Keys.** Identical top; the bed binds lanes 01–06 as real keys in its upper rows, so lane
selection has a fully in-reach pressable path *and* the swipe, with the ribbon as pure readout. **Cost:** six
of sixteen slots, leaving ~5 for utilities after audio (01), Talk (14+15) and the two flanking blanks — the
remaining utilities move behind a sheet. **It does not reintroduce the problem**, because all six live in the
one region where keys belong.

**Recommendation: B.** The brief states that users switch lanes while turns are running. That is a frequent,
in-flight act, and it should not depend on a gesture with no visible affordance. Take A only if the deck
turns out to be effectively single-lane in practice.

---

## 6 — Sequencing, if this is adopted

1. Remove the glass pill; print the mode. *(smallest edit, largest legibility gain — do it standalone)*
2. Collapse the Bridge Bar into the Bridge Line; delete the three `*Bar` components.
3. Collapse the Lane Bed into the Ribbon; add glass swipe.
4. Delete the rail; grow the glass; move Talk into slots 14+15.
5. Rescope `Key`, add `Segment` and `Lamp`, make the utility tiles real.

Steps 1 and 2 alone should be enough to tell whether the diagnosis is right, before the spine is re-solved.
