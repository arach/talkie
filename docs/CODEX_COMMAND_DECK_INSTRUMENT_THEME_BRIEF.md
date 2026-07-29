# Codex Command Deck — instrument-panel integration brief

## Assignment

Refine the current `/ios-deck-codex` Studio study after the lane-picker round. The interaction and signal findings are valuable, especially the recommendation of **L3 · Two-Tier Identity**, but its current rendering diverges too far from Talkie's established Deck family.

The pictured L3 reads as a generic black app screen with a lane strip and a floating identity card. Restore the Deck's physical-instrument grammar: the upper control area should feel like a dedicated technical panel or channel-selection instrument that belongs to the same chassis as the utility keys and Bottom Sill Rail.

This is a refinement of the existing study, not a new visual world and not a reopening of the T2 or L3 decisions.

## Required visual evidence

Study these existing Talkie Studio implementations before editing:

- `design/studio/components/studies/IOSDeck.tsx` — full-bleed chassis, instrument console, device/status signals, integrated key system.
- `design/studio/components/studies/DeckKeyBed.tsx` — one recessed instrument bed rather than floating chip groups.
- `design/studio/components/studies/DeckKeypad.tsx` — physical macro-deck material hierarchy.
- `design/studio/components/studies/DeckPlayground.tsx` — material treatments and deck-family vocabulary.
- `design/studio/app/ios-deck/page.tsx` — the established names and physical model.
- Current study: `design/studio/components/studies/CodexDeckLaneSignals.tsx`.
- Current route: `design/studio/app/ios-deck-codex/page.tsx`.
- Screenshot showing the drift: `/Users/arach/Library/Application Support/Talkie/Screenshots/Talkie Capture - 2026-07-27 21.55.39 - Region - 446x1081 - f9bbbf90 t0ms.png`.

## Fixed product decisions

- **T2 Bottom Sill Rail stays fixed** in position, footprint, and primary-action role.
- **L3 Two-Tier Identity remains the recommendation**: six stable lane positions plus a dedicated exact-task identity tier.
- Lane and signal truth boundaries remain unchanged. Do not invent queue depth, progress, per-lane activity, ETA, tool, token, or approval controls.
- Queue is the safe default for an active turn; Steer is explicit. Talkie never approves Codex actions.
- Keep all five lane-picker treatments and their parameters for comparison, but bring their upper lane-selection zone into a coherent Deck-family material system.

## Design direction

Treat the lane selector as the Codex version of the Deck's trackpad/technical area:

- It is not literally a trackpad. It is a **channel-selection instrument** or **lane console**.
- Give it one distinct, bounded or recessed technical field within the chassis, with the lane controls and exact-task plate integrated inside it.
- Prefer a single composed instrument area over a row of unrelated pills plus a floating card.
- Reuse the established depth hierarchy: chassis as ground, inset well/bed, lifted or routed controls, printed legends, precise amber state accents, subtle material changes.
- Preserve the deck's dense, technical, physical character without decorating with arbitrary circuitry, fake telemetry, or monospace-for-its-own-sake.
- The lane numbers should read like channel selectors or bank keys. The identity tier should read like the instrument's display/readout, not a separate generic card.
- Let the module carry a clear name in the study vocabulary, such as **Lane Console**, **Channel Bed**, or another precise term supported by the design.
- Keep enough quiet space for ergonomic clarity. Restoring the theme does not mean filling the screen with ornamental controls.

## Deliverable

Update the existing Studio route and decision notes in place.

1. First inspect and explicitly summarize the reusable visual grammar from the existing Deck studies.
2. Refine all five treatment previews so they share that grammar.
3. Give L3 the strongest, most resolved treatment because it remains the recommendation.
4. Keep the live scenario and parameter controls working.
5. Update `design/studio/app/ios-deck-codex/NOTES.md` with the chosen instrument-area vocabulary and what was borrowed from the Deck studies.
6. Build with `bun run build` from `design/studio` and visually inspect `/ios-deck-codex` at a normal laptop viewport.
7. Do not change Swift, commit, or push.

The target is continuity without imitation: unmistakably Talkie Deck, purpose-built for Codex lane selection.
