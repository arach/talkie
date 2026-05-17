# Compose — Decisions Log

## What this study renders

The Compose screen (textarea editor + model picker + action bar)
recreated from `design/screenshots/2026-05-17/12-compose-type-editor.png`,
rendered across all 4 iOS themes simultaneously inside `<PhoneFrame>`.

## Mira's critique applied

- **Pre-selected default model.** The shipping placeholder
  (`Choose model ▾` in gray-italic) reads as broken / disabled. Now
  shows `✦ Claude Sonnet 4.6 ▾` by default — the dropdown still works,
  the empty state just doesn't look unset.
- **Labeled cursor pad** (`· Cursor` smallcap underneath). The
  shipping arrow-pad was genuinely cryptic — could be cursor nav,
  joystick, anything. Mono caption clears it up.
- **Brass mic ring + halo** on empty-textarea state. The shipping mic
  was a plain gray circle; now it picks up the brass border + amber
  glow. Highest-leverage moment to signal "dictate now."
- **Hint copy inside the empty textarea.** Two-line low-contrast hint
  ("Write or paste — then run any model. / Or tap the mic to dictate.")
  distinguishes Compose from Dictate so the user knows what kind of
  editor this is.

## Open questions

- The header is split across three centered lines (`· COMPOSE WITH` /
  `✦ Claude Sonnet 4.6 ▾`). Reads correctly on cream Scope but might
  feel busy on Ghost. Worth a single-line variant?
- Send button is shown in disabled state (gray paper). When the user
  types, it should flip to amber fill with halo. Worth adding a
  `ready` toggle to the study so we can A/B both?
- Quick Commands chip row is squeezed at the bottom; if more commands
  are needed, the row needs a fade-edge scroll affordance — pull from
  AI commands screen (`05`) treatment.

## Why these primitives

Compose reuses `<StatusBar>`, `<ChannelLabel>`, `<Chip>` from
`primitives/`. The `<CursorPad>`, `<BrassMic>`, `<SendButton>` are
inline here for now — promote to primitives if a second screen needs
them (likely the AI commands sheet `05`).
