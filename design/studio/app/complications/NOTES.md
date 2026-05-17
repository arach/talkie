# Complications — Decisions Log

## The pattern

**One ambient Talkie button. Three states. Universal across the app.**

The whole iPhone app uses a single interaction model for chrome
and voice: a permanent, low-key voice button in the bottom-left
that escalates through three states on successive gestures:

| State | Gesture | What appears |
|---|---|---|
| **1 · resting** | (default) | Content fills the screen. Only the ambient voice button is visible. |
| **2 · chrome up** | Quick tap | Corners + tray fade in. Voice button lights brass to signal "hold to talk." |
| **3 · listening** | Long-press the lit button | Voice-command bubble floats above the button with a live waveform + transcription. Release to send. |

The release-on-long-press semantic is the walkie-talkie idiom
Talkie's named after. Brand and interaction line up.

## Why this pattern, not something else

- **Single primitive** — every screen behaves identically. No
  per-screen tab bar / nav bar reinvention. Library, Compose,
  Recording Sheet all summon the same chrome.
- **Content is the priority** — at rest, the screen is the
  document/list/sheet. Chrome doesn't compete.
- **Voice is one gesture away** — long-press from any state on
  any screen brings up the command bubble. You never have to
  navigate to "talk."
- **Affordance escalates with intent** — quick tap is low-cost
  (just look at my options). Long-press is high-commitment (I'm
  holding it because I have something to say).

## Slot map (when chrome is up)

| Position | Function | Why |
|---|---|---|
| Bottom-left | The ambient voice button (always visible) | Thumb-natural; escalates per state |
| Top-left | Back / Done | iOS convention |
| Top-right | Settings | iOS convention |
| Bottom-right | Keyboard | Switch input mode; complements voice |
| Bottom-center tray | Camera · Record (FAB) · Compose | Quick-actions: start a new capture/creation |

Corners = chrome / destinations. Tray = create actions. The
voice button itself is both summon affordance + voice command
trigger.

## Alternatives explored (preserved in source for reference)

These variants are still in `components/studies/Complications.tsx`
but no longer surfaced in the picker. Each is one tap away from
being re-enabled if the pattern proves wrong:

- **`corners`** — 4 corner pills + center mic FAB (the current
  shipping pattern). Always-visible; crowds the screen.
- **`tray` only** — chrome stays in top corners, bottom is a
  3-slot tray with no corners below. Cleaner than `corners` but
  loses the bottom-corner real estate.
- **`full`** — all 4 corners + bottom tray, always visible. The
  most affordances; most cluttered.
- **`summon-idle` / `summon-active`** — pull-up summon via a
  hairline + caption at the bottom edge. Cleaner than always-on
  but uses an edge-swipe gesture that's less discoverable than
  a visible button.

The voice-pivot pattern won because it's the only one that gives
us **a visible, persistent affordance** AND **a hidden, intent-
driven escalation** AND **direct voice access** — all in one
40×40 target.

## Implications for the rest of the app

This pattern would replace per-screen nav chrome across the app:
- **Library** loses its tab row + search bar's bottom anchor; the
  tab row becomes a top-corner overflow (or moves into a sheet).
  Library content (memos list) takes the whole screen at rest.
- **Compose** loses its separate header + action tray; the bio
  fills the screen. Chrome summons in on tap; voice command
  triggers via long-press (replacing the bottom-left voice cmd
  button I built earlier).
- **Recording Sheet** is already mostly content + one big button;
  the voice button could replace the stop button (long-press to
  end recording — different intent layer).

Follow-up study: refactor Library and Compose to use this pattern
and see how the screens read at rest. (Not done in this pass —
the pattern is locked here first.)

## Open questions

1. **Discoverability** — at rest, only one button is visible. New
   users may not know to tap. Is a 3-second auto-hint ("tap to
   summon" caption) worth the cost?
2. **Tactical theme** — the round liquid-glass tray fights
   Tactical's square-corners discipline. Tray needs to be 0px
   radius under `[data-theme="tactical"]`. Not yet implemented.
3. **Right-handed default?** — bottom-left button works for
   right-thumb-dominant. Should the button auto-mirror for
   left-handed users (Settings → Handedness)?
4. **Lock-screen complication** — could the same button appear on
   the lock-screen, summoning a quick voice-command without
   unlocking? Apple Watch precedent says yes.
