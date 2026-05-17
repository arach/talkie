# Home — Decisions Log

## What this study renders

Talkie's canonical iPhone home screen, recreated from
`design/screenshots/2026-05-17/14-recording-capture-sheet.png` (the
home content behind the recording sheet, isolated). Composition:

1. **TALKIE wordmark** — quiet centered, no chrome around it
2. **STATION card** — paper-lifted card with the bichromatic headline
   ("5 signals on deck.") + meta + dark **Live · Action Bus** inset
   with three big numerals (MEMOS / TYPE / GRAB)
3. **Recent list** — channel-label divider with count pill + "All"
   right-aligned, then a list of 3 rows using the same `ListRow`
   primitive Library uses
4. **Ambient voice button** — the universal Talkie button per
   `/complications`, resting state, bottom-left

## Why a separate study

Home is the screen where the voice-pivot pattern matters most — the
button sits at rest while the user reads what's on deck. Library +
Compose are reached *by tapping* (or saying) from here. Getting Home
right tests whether the ambient affordance reads as ambient (vs as
floating debris on a busy surface).

## Design notes

- **Action Bus** is the only consistently-dark element on a light
  theme. It IS an instrument readout — the dark panel + glowing
  numerals language is on-brand. Reuses `--theme-screen-bg` and
  `--theme-screen-trace-glow` so each theme's screen tokens drive it
  (Scope: amber on near-black, Midnight: blue on black, Tactical:
  amber on black, Ghost: indigo on near-white, Lift: indigo on
  white).
- **STATION card** uses paper + the strong card shadow (from Lift's
  `--theme-card-shadow-strong`). On Lift the card lifts cleanly off
  white; on other themes the inner highlight reads as paper grain.
- **Recent count pill** sits next to the channel label as an
  inline accent — small, on-brand.

## Open questions

- Should the **Live Action Bus** numerals be tappable? Each could
  jump to a filtered library view (MEMOS = memos-only filter, GRAB =
  scanned items). Adds depth without adding chrome.
- **Action Bus position** — currently inside the STATION card. Could
  break it out as its own card below STATION (more breathing) or
  keep it nested (denser, more "instrument"). Inside feels more like
  a single piece of equipment.
- **"5 signals on deck."** — should this number be live (today's
  unprocessed captures) or all-time? Probably today's; the period
  could be a smallcap suffix ("5 today").
