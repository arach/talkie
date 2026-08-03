# iOS Deck — Key Lift & Inactive Grammar

Route: `/ios-deck-key-material`

Study: `design/studio/components/studies/DeckKeyMaterial.tsx`

## Why this exists

Two live companion captures (2026-08-01) made the same material problem obvious from two sides:

1. **Command deck** — every key wears a soft dual drop-shadow (ambient radius ~6–8, y ~3–5). Caps read as floating iOS cards, not seated instrument keys.
2. **Codex deck** — unavailable actions (History / Read / Copy / Replay / Stop / Talk with no channel) keep the raised face and only fade ink to ~40%. Half the bed looks broken.

Layout is frozen. This study only compares **resting lift** and **inactive grammar**.

## Three materials, no fourth

| Material | Meaning |
| --- | --- |
| **Seated cap** | Ready to press. Contact lift (or milled seat), full ink. |
| **Socket** | Unavailable / empty / blocked primary. Recessed dimple, engraved index, no icon wash. |
| **Armed** | Actually on (dictating, listening, fired). Accent ring + tint only. |

Opacity is not a material. Soft ambient shadow is not a seat.

## Dials

### Resting lift (S0–S4)

| Key | Name | Note |
| --- | --- | --- |
| S0 | Shipping | Dual soft shadow — today's card language |
| S1 | Contact only | Tight contact, no ambient bloom |
| S2 | Contact + hairline | S1 + 0.5px edge so silhouette holds on white |
| S3 | Milled pocket | Depth from a recessed well; caps sit tight |
| S4 | Flush chamfer | No drop shadow; paint and light only |

### Inactive (I0–I3)

| Key | Name | Note |
| --- | --- | --- |
| I0 | Shipping ghost | Same face + alpha — today's broken look |
| I1 | Full face · muted ink | Cap stays raised; only label/icon mute |
| I2 | Socket | Category change for context-disabled utilities |
| I3 | Socket + reason | Talk blocked: short silk (`MAP A LANE`), never ghost |

## Recommended default

- **Lift:** S2 · Contact + hairline (S3 if the bed wants a milled pocket)
- **Inactive utilities:** I2 · Socket
- **Talk blocked:** I3 · Socket + reason
- **Armed:** accent only while something is actually on

## Swift touch points (not edited in this study)

- `apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift` · `keycapSurface(active:isEmpty:)`
- `apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift` · `keycapSurface` / `actionKey` / `captureKey` / `talkKeySurface`

Disabled state must reach the **surface recipe**, not only `.foregroundStyle` or whole-control `.opacity`.

## Capture references

- `Talkie Capture - 2026-08-01 17.09.26` — Codex, no channel, ghosted utilities + Talk
- `Talkie Capture - 2026-08-01 17.09.56` — Command, soft dual shadow on all 16 keys
