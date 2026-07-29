# iOS Codex Deck — Alternate K: One Display, One Scale, One Keyboard

Route: `/ios-deck-codex-kimi`

Study: `design/studio/components/studies/CodexDeckKimi.tsx`

Answers: `design/reviews/2026-07-28-codex-deck-bridge-bar-review.md` (the de-buttonization review of the Bridge Bar round). Incumbent (untouched): `/ios-deck-codex` → `CodexDeckBridgeBar.tsx`.

## Spatial thesis

Four bands never move in any state: the chrome line at the top, the lane scale under it, the black glass in the middle, and the 4×4 keybed at the bottom. Everything the host says lands on the single glass, and nothing on that glass is pressable. The scale above it only ever answers *where am I*; the bed at the bottom is the only region made of keys. The top of the face is quiet on purpose — the air between the wordmark and the host line is what makes it read as a header instead of a console.

The operator's correction — *"the typography is fine; the problem is that everything is a button"* — is answered categorically, not typographically. Interaction semantics are carried by five material registers that never overlap, so affordance never has to be inferred from contrast or size:

| Register | Meaning | Lives at |
| --- | --- | --- |
| Chrome text | ambient identity and host telemetry | Band 1 |
| Engraved segment | a *selection*, not an action | deck mode in Band 1 |
| Recessed scale | lane position + selection | Band 2 |
| Black glass | the readout | Band 3 |
| Seated cap | the only thing that presses | Band 4, all sixteen slots |

## Why each former control changed category

- **Mode keys → segment.** CODEX / CMD was two seated caps. It is a selection, so it became two flat text positions in a hairline groove: active gets amber ink on `amber-faint`, no cap gradient, no raised shadow. Real `<button>`s with `aria-pressed`; zero cap material.
- **Host keys → host line + lamp.** Three caps (which the incumbent itself admitted could never honestly be three lit hosts) became one transparent text line: lamp + name + `⌄`. Exactly one host is ever connected, so exactly one is ever shown; tapping cycles to the next paired host through the incumbent's `onHost` logic, including the global vs host-keyed `laneScope` behaviour.
- **Lane bed → scale.** Six seated caps became ONE machined channel with six divisions separated by 1pt routed ticks. Selection is a lit number plus a 2.5pt amber detent bar at the top edge; a turn in flight carries a 3.5pt amber tick lamp that shows even when its lane is not selected. Divisions are real `<button>`s (focusable, `aria-pressed`), but there is no per-division background or shadow — it reads as one groove, never six keys.
- **Steer/Queue button → printed attribute + bed key.** The incumbent's 7.5pt amber `<button>` on the glass was the single element that broke the glass rule. The mode is now printed silk in the glass head (`STEER` / `QUEUE`, plain text, no pill), and it is *set* from slot 09 in the bed — `DELIVER` over the mode word, amber for steer (the hotter mode), cap ink for queue.
- **Rail → Talk at 14+15.** The 351×76 bottom rail is deleted; its 94pt went to the glass. Talk is a two-slot cap in the keybed, flanked by empty sockets 13 and 16 — the air is mandatory. The incumbent's `railFace()` disabled-reason ladder is ported verbatim onto this key.

## Deliberate tradeoffs

- **The lane scale sits at the top**, out of comfortable thumb reach, and it *is* pressable there. That is accepted: in production, lane switching also happens by swiping the glass itself — a large, reachable, one-handed gesture with the scale as its position readout. The scale being pressable is the discoverable path; the swipe is the habitual one. Intended gesture, noted here because the static study cannot draw it.
- **Talk is amber-washed at rest** (`--kcd-cap-on`) whenever it is enabled. It is the deck's one deliberate primary, and the grammar can afford exactly one. Every other cap wears the plain `--kcd-cap`.
- **Audio is deliberately quiet.** Slot 01 is the same cap material and ink as its neighbours — the waveform glyph and label carry it, not contrast. It must never be the loudest object on the bed.
- **Alarm is a rim, not a flood.** Stale/offline talk states get rec ink and `inset 0 0 0 1px rgba(255,107,95,0.45)`. No red fill.
- **Utility keys are real `<button>`s.** The incumbent's fake-div tiles at blanket `opacity: 0.62` were a defect named in the review; here every bound slot is focusable and presses (`translateY(1px)` on `:active`). Their `onClick` is a no-op in the study.
- **Empty slots are sockets, not disabled buttons.** Recessed socket material, engraved slot number at 35% ink, plain `<div>`.

## Ported from the incumbent (product truth, unchanged)

- The entire model: hosts, host-local lane sets, turns, delivery modes, the twelve scenarios (idle, sending, queued, working, progress, responded, failed, elsewhere, switching, stale, switched, offline), `laneScopeStale`, `hostStateOf`, `ago`.
- The glass content stack: head line + status word + elapsed, transcript with its amber rule, the live channel with kind marks (`▸` tool / `·` commentary), `NO PUBLIC UPDATES YET`, `RESPONSE · ARRIVED WHOLE` (the response lands whole — it never pretend-streams, because `job.response` is atomic), the typed failure block with the Mac's own recovery sentence, and the pane foot sentences.
- The `railFace()` disabled-reason ladder, verbatim, retargeted to the Talk key.
- The material recipes: `appearanceVars` (renamed `--cdb-*` → `--kcd-*`), the `Phone` shell, the `Glass` black-glass recipe with its theme remaps, scanlines and vignette, and the cap/socket/bed shadow language.
- The shimmer (running with no published updates) and the live-lamp pulse — the only two authored motions, exactly as in the incumbent.

## Caveats

- Study-only: utility key `onClick`s are no-ops; delivery mode is local component state (`Record<number, DeliveryMode>`, default steer); host cycling lands in the settled post-switch state (the connecting transient has its own scenario).
- The glass swipe for lane switching is stated intent, not implemented — this is a static composition study.
- Host-keyed lane scope is still the production blocker inherited from the incumbent: `codex.lanes.v1` / `codex.lanes.active.v1` are globally keyed today, and the stale scenario is drawn as-is, with talk refused.
- Search params `?a=light|dark` and `?s=<scenarioKey>` set the initial state for scripted screenshots.
