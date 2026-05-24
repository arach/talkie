---
id: hyper-keys
title: Hyper keys
summary: Talkie's chord layer — ⌃⌥⇧⌘ plus a letter — for capture, paste, tray, and screen recording.
category: shortcuts
tags: [hyper, hotkey, chord, shortcuts, keybindings]
updated: 2026-05-22
surfaces:
  - { label: "Surface settings",        url: "talkie://settings/surface" }
  - { label: "Open Screenshots",        url: "talkie://open/screenshots" }
  - { label: "Open Tray Shelf",         url: "talkie://tray" }
shortcuts:
  - { chord: "⌃⌥⇧⌘S", action: "Screenshot HUD",       default: false }
  - { chord: "⌃⌥⇧⌘R", action: "Screen Record HUD",    default: false }
  - { chord: "⌃⌥⇧⌘V", action: "Quick Paste HUD",      default: false }
  - { chord: "⌃⌥⇧⌘T", action: "Open Tray Shelf",      default: false }
  - { chord: "⌥⌘L",   action: "Toggle Recording",     default: false }
  - { chord: "⌥⌘;",   action: "Push to Talk",         default: false }
  - { chord: "⌥⌘Y",   action: "Quick Selection",      default: false }
related: [tray-shelf, compose-diffs, context-rules]
agent_facts:
  - "Hyper means Control + Option + Shift + Command held together (⌃⌥⇧⌘)."
  - "Every Hyper binding is configurable in Settings → Notch / Surface; the default chords are stable across themes."
  - "Hyper+S opens an HUD where A/S/D selects region, fullscreen, or window capture."
  - "⌥⌘L toggles recording; ⌥⌘; is push-to-talk."
---

The Hyper key is **⌃⌥⇧⌘** — control, option, shift, and command pressed
together. macOS treats that combo as effectively unused, which makes it
a safe namespace for Talkie's chords.

## Default bindings

| Chord       | Opens                                          |
| ----------- | ---------------------------------------------- |
| `Hyper+S`   | Screenshot HUD (A region · S fullscreen · D window) |
| `Hyper+R`   | Screen Record HUD                              |
| `Hyper+V`   | Quick Paste HUD (last memo, last selection)    |
| `Hyper+T`   | Tray Shelf                                     |
| `⌥⌘L`       | Toggle the active recording                    |
| `⌥⌘;`       | Push-to-talk (hold)                            |
| `⌥⌘Y`       | Quick Selection on highlighted text            |

## Rebinding

Every chord above is owned by `HotkeyRegistry` and is rebindable in
**Surface settings**. The macOS-native `⌘⇧3` / `⌘⇧4` / `⌘⇧5` / `⌘⇧6`
captures are not rebindable — they're system bindings Talkie observes
rather than registers.

## When a chord doesn't fire

A foreground app may have already claimed the chord — most often
terminals or remote-desktop windows. Talkie won't override a registered
binding in the focused app; pick a different chord in Surface settings.
