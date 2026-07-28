# Talkie — Eyes Off Screen

This campaign translates the iPad dark-room direction into a macOS story about
computing without continuous visual attention:

```text
Lean back.
Take your eyes off the screen.
Speak your ideas into existence.
```

The three copy-bearing frames are designed as a sequence, not as three
independent taglines:

1. `01-lean-back-2880x1800.png` — permission to disengage from the screen.
2. `02-eyes-off-screen-2880x1800.png` — the campaign's clearest product thesis.
3. `03-speak-ideas-into-existence-2880x1800.png` — the voice-to-work payoff.

## Directory structure

- `masters/` contains the selected 4:3 photographic concepts.
- `studies/` preserves useful explorations that are not part of the selected set.
- `exports/app-store-concepts/` contains deterministic 2880x1800 PNG exports.
- `render-campaign.swift` owns the 16:10 layout, copy, typography, and colors.
- `manifest.json` records the role and submission status of each export.

## Selected clean masters

- `hero-window-warm-city.png` — primary warm editorial direction.
- `hero-window-pearl-lake.png` — primary quiet daylight direction.
- `hero-dark-studio.png` — primary dramatic dark-room direction.
- `hero-warm-studio.png` and `hero-pearl-studio.png` — background alternatives.

## Render

Run from the repository root:

```bash
swift apps/macos/marketing/campaigns/eyes-off-screen/render-campaign.swift
```

The renderer uses Talkie's bundled Geist and Geist Mono fonts and exports
opaque 2880x1800 PNGs. Apple currently accepts 1280x800, 1440x900, 2560x1600,
or 2880x1800 screenshots for Mac, all at 16:10:

<https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>

## Submission status

These are campaign concepts, not final App Store screenshots. Their physical
desktop scenes and shortcut microphone are intentionally speculative, and the
screen shown in the generated photographic masters is a visual approximation
of Talkie rather than a literal app capture.

Before App Store Connect upload:

1. Capture the current shipping macOS interface.
2. Project that untouched capture into the display aperture.
3. Re-render the 2880x1800 sequence.
4. Review every visible claim and control against the shipping build.
5. Mark the chosen files `submissionReady: true` in `manifest.json`.

The clean exports are useful immediately for internal review, campaign
direction, and layout studies. Do not treat their accepted dimensions as proof
that their current screen content is submission-safe.

## Visual-generation lineage

The photographic masters were produced with the built-in image-generation
workflow. The selected direction asked for a centered, very thin desktop
display in a restrained bronze/cyan-lit environment, a low six-key Talkie
command pad, and a small integrated microphone. The window variants preserved
that hardware while introducing either a softly focused warm city-and-lake
horizon or a low-contrast misty lake-and-hills view.
