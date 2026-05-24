---
id: tray-shelf
title: Tray Shelf and screenshots
summary: A pull-down shelf that holds your recent screenshots and clips beside the current recording.
category: capture
tags: [tray, shelf, screenshot, capture, viewer]
updated: 2026-05-22
surfaces:
  - { label: "Open Tray Shelf",       url: "talkie://tray" }
  - { label: "Open Tray Viewer",      url: "talkie://tray/viewer" }
  - { label: "Screenshots",           url: "talkie://open/screenshots" }
  - { label: "Surface settings",      url: "talkie://settings/surface" }
shortcuts:
  - { chord: "⌃⌥⇧⌘T", action: "Toggle Tray Shelf",        default: false }
  - { chord: "⌘⇧5",   action: "Open Tray Viewer",          default: true }
  - { chord: "⌃⌥⇧⌘S", action: "Screenshot HUD (A/S/D)",    default: false }
  - { chord: "⌘⇧3",   action: "Fullscreen screenshot",     default: true }
  - { chord: "⌘⇧4",   action: "Region screenshot",         default: true }
  - { chord: "⌘⇧6",   action: "Window screenshot",         default: true }
  - { chord: "⌘⇧V",   action: "Paste last screenshot",     default: true }
related: [hyper-keys, compose-diffs, privacy-local-sync]
agent_facts:
  - "The Tray Shelf slides down from the top of the screen and holds recent screenshots and clips."
  - "Hyper+T toggles the Tray Shelf; ⌘⇧5 opens the Tray Viewer."
  - "Hyper+S opens the Screenshot HUD: A = region, S = fullscreen, D = window."
  - "If a recording is active, a captured screenshot attaches to that recording instead of standing alone."
---

The Tray Shelf is a pull-down strip at the top of the screen. It collects
recent screenshots and screen clips so you can drag, reuse, or attach
them without leaving the foreground app.

## How it works

- **Hyper+T** toggles the shelf in and out.
- **Hyper+S** opens the Screenshot HUD with three choices — **A** for a
  region, **S** for fullscreen, **D** for a window.
- macOS-native chords still work: **⌘⇧3** / **⌘⇧4** / **⌘⇧6** capture
  fullscreen, region, and window respectively, and the result lands in
  the shelf either way.
- **⌘⇧V** pastes the most recent screenshot wherever the cursor is.

## Behaviour during a recording

If a recording is active when you grab a screenshot, the image attaches
to that recording — pinned next to the words rather than living
separately. The two end up in the same memo when you finish.

## Tray Viewer vs Tray Shelf

The **Shelf** is the lightweight strip. The **Viewer** (⌘⇧5) is the
full-window inspector with metadata, search, and the option to send a
screenshot into Compose or a workflow.
