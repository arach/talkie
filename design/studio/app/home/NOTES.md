# Home — Decisions Log

## Current Study

`/home` is now a Studio comparison board for the current iOS Home shape:

1. Header complication + TALKIE wordmark + settings
2. Today ticker
3. Quick deck
4. Recent screen
5. Explore rail
6. Bottom voice pivot + central record FAB

The route renders the baseline Swift parity target and five layout/material
variants across every iOS theme. The intent is to let design review drive a
small implementation choice before the SwiftUI surface changes again.

## Content Ideas

The first `/home` board section now holds content-model explorations on the
same promising lane: `deduped-quick` alignment in Scope, Tactical, and Lift.
These intentionally keep the shell stable and vary only what Home is trying to
say:

- **Utility Console:** no Today stats; shortcuts first, omni search/command
  second, eight Recent rows, and Explore without Library because `All` already
  exits the Recent section.
- **Life Pulse:** contribution/momentum chart, not a clerical Today count.
- **Cockpit Dots:** lead cockpit for bridge, shares, replies, and routing
  state, with a compact Life-in-Dots module.
- **Cockpit Inbox:** the same cockpit with a notification-center module.
- **Cockpit Full-Width:** the same cockpit as one uninterrupted rectangle,
  with no side column.
- **Activity Pulse:** today's counts and recent captures.
- **Pick Up Memo:** the next edit on the current memo.
- **Growth Loop:** a daily focus block and creative seed list.
- **Review Inbox:** pending screenshots, shares, and AI outputs.
- **Bridge Ready:** paired-Mac state and the next cross-device action.

## Variant Questions

- **Ticker demoted:** should Today become one compact ambient line instead of a
  three-cell band?
- **Grouped rhythm:** does more vertical pause between Today, Quick, and Recent
  lower cognitive load?
- **Simple Recent:** does removing filter/sort chrome from the section header
  make the list feel calmer?
- **De-duped Quick:** should the record FAB own recording so Quick does not
  repeat it, and should Explore omit Deck when the deck button already sits in
  the header?
- **Material calibration:** do the new action/metal/recess tokens create enough
  structure without adding accent color everywhere?

## Material Direction

Keep one opposition: raised metal versus recessed screen.

- **Raised metal:** header circles, Quick deck, mic FAB.
- **Recessed screen:** Recent list container.
- **Ambient:** Today and Explore should be quiet, lower-container surfaces.

Color stays disciplined: accent is for state and signal, not for solving depth.
Depth should come from light, rim, recession, and spacing.

## Parity Corrections (2026-07-01, second pass)

The baseline mock drifted from the July-1 `HomeNextView.swift`; these were
re-aligned so "Current Swift" tells the truth:

- Explore rail ends in **Keyboard**, not Settings (Settings is the header's
  right circle; Swift's last chip is Keyboard).
- Explore chip glyphs are **accent** ink on paper capsules (Swift line ~573),
  not action ink on tinted fill — action ink there is now the calibration
  variant's move.
- Quick deck glyphs use **action** ink in every variant (Swift adopted
  `chrome.action` in the July-1 pass); deck height 56.
- Mic FAB is the **accent-filled** 56pt circle with paper glyph + accent glow
  (ChromeOverlay `MicFAB`), not an ink-filled 74px disc. Voice pivot 48pt.
- Header circles 40pt, no status bead (Swift removed the bead — bridge state
  lives on the Deck surface), Deck complication in **all** variants — the
  de-duped premise is that the header owns Deck.
- Recent rows 38pt with full-width hairlines; count reads "40 items"
  (tertiary); load-more row uses the arrow glyph (was literal "down" text).
- Eyebrows all sit at secondary ink; RECENT differentiates via tracking, not
  accent. Leader glyph now honors `--theme-eyebrow-leader` per theme (·/—/›).

Still intentionally ahead of Swift (proposal, not parity): metal-gradient fill
on the header circles — Swift's `HomeHeaderButtonGlyph` is still flat paper;
the REVIEW below recommends the specular treatment.

## Source Review

Claude review artifact:

- `design/studio/app/home/REVIEW-2026-07-01-visual.md`

## Ask Talkie Console (2026-07-14)

The middle Home control now has one primary job and one explicit alternate
mode. **Ask** is the default: it offers Plan, Draft, and Think starters and
sends a typed prompt directly into a fresh Ask AI conversation. **Find** is a
deliberate mode that filters Recents live, rather than silently borrowing the
same text binding.

This removes two conflicting affordances from the prior Home shape:

- Quick no longer repeats Ask AI; its fourth action is Search, which focuses
  Find mode.
- The command bar no longer shows a microphone that starts a voice memo.
  Release-to-send voice commands remain owned by the shell voice pivot.

The Ask AI destination now receives a structured seed request (stage or send,
continue or start fresh), has a clearer first-run proposition, and exposes a
new-conversation action after a thread begins.

Inference stays reusable and separate from this Home intent. The iOS
`InferenceService` accepts structured system/user/assistant messages, prefers
an exact provider configured on the phone, and otherwise sends the same
messages to the paired Mac's configured-inference route. On macOS that route
uses TalkieAgentServer's existing Gateway provider registry; Scout remains the
agent/session handoff boundary. Mac provider credentials never need to be
copied onto the phone for this flow.

Swift sources:

- `apps/ios/Talkie iOS/Views/Next/HomeNextView.swift`
- `apps/ios/Talkie iOS/Views/Next/AppShellNext.swift`
- `apps/ios/Talkie iOS/Views/Next/AskAINext.swift`
- `apps/ios/Talkie iOS/Services/Inference/InferenceService.swift`
- `apps/macos/TalkieServer/src/bridge/routes/configured-inference.ts`
