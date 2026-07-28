# Talkie instrument concept projection

This concept keeps the photographic device and the real Talkie interface as
separate layers. The clean plate has no caption, controls, or support-edge
ornament; `project-talkie-screen.swift` rounds and perspective-warps an
untouched 4:3 iPad screenshot into the measured inner glass quadrilateral.

Run from `apps/ios`:

```bash
swift fastlane/marketing/concepts/project-talkie-screen.swift
```

Optional positional arguments are the plate, screenshot, and output paths:

```bash
swift fastlane/marketing/concepts/project-talkie-screen.swift \
  /path/to/plate.png \
  /path/to/ipad-screenshot.png \
  /path/to/output.png
```

The default output is `talkie-instrument-clean-real-screen.png`. Input
screenshots must be 4:3 landscape; the current App Store capture is 2752x2064.

The dark-room variant uses the same measured glass geometry:

```bash
swift fastlane/marketing/concepts/project-talkie-screen.swift \
  fastlane/marketing/concepts/talkie-instrument-dark-room-plate.png \
  "fastlane/screenshots/iPad Pro 13-inch (M5)/state-home-ask-ready.png" \
  fastlane/marketing/concepts/talkie-instrument-dark-room-real-screen.png
```

The editorial tagline composition has its own measured projection and
deterministic typography pass:

```bash
swift fastlane/marketing/concepts/render-talkie-just-say-it.swift
```

This produces `talkie-just-say-it.png` from the text-free
`talkie-just-say-it-plate.png` and the current real iPad screenshot. The exact
rendered copy is:

```text
TALKIE:
Just say it.
```

The lockup uses the same two-family voice as the app: tracked SF Mono for the
instrument-style brand line and the bundled Newsreader face for the editorial
campaign line.

For the no-copy variant, pass `none` as the fourth positional argument:

```bash
swift fastlane/marketing/concepts/render-talkie-just-say-it.swift \
  fastlane/marketing/concepts/talkie-just-say-it-plate.png \
  "fastlane/screenshots/iPad Pro 13-inch (M5)/state-home-ask-ready.png" \
  fastlane/marketing/concepts/talkie-no-tagline.png \
  none
```

The no-copy mode enlarges the complete product and projected screenshot by 22%
around the lower-right anchor. This keeps the asymmetric dark-room composition
while returning the interface to hero scale.

For the preferred brand-signature variant, use `brand` instead. It keeps the
same large-screen framing and adds only the real Talkie wordmark treatment—
regular SF Mono with restrained tracking—centered in the room above the device:

```bash
swift fastlane/marketing/concepts/render-talkie-just-say-it.swift \
  fastlane/marketing/concepts/talkie-just-say-it-plate.png \
  "fastlane/screenshots/iPad Pro 13-inch (M5)/state-home-ask-ready.png" \
  fastlane/marketing/concepts/talkie-brand-caption.png \
  brand
```

## Blank-plate generation prompt

The current clean plate was produced with the built-in image-generation edit
workflow from the earlier instrument concept:

```text
Remove the floating caption card and reconstruct the warm pearl background.
Remove both rotary dials and the center indicator from the support, rebuilding
it as one pristine uninterrupted machined-aluminum edge. Recenter the iPad and
support with balanced negative space. Keep the landscape iPad at recognizable
4:3 proportions with a subtle symmetrical backward tilt, a thin black bezel,
and a completely blank smoked-teal glass aperture. Add no text, controls,
labels, screws, vents, ports, grooves, people, or watermark.
```

## Dark-room plate generation prompt

The dark-room plate was produced as an image-generation edit of the clean
plate, preserving the empty glass aperture for deterministic UI projection:

```text
Keep the iPad and its single uninterrupted low-profile machined support at the
exact same scale, position, perspective, bezel thickness, screen opening, and
support shape. Change only the environment and light response: a seamless deep
charcoal studio with a midnight-navy undertone, subtle warm copper edge light,
soft cool slate-blue counter-rim, dark graphite anodized support, restrained
contact shadow, and barely visible floor reflection. Keep the screen blank
smoked deep-teal glass. Add no UI, text, logos, captions, controls, knobs,
props, cables, people, scenery, bloom, or watermark.
```

## Editorial promo plate generation prompt

The tagline plate was generated from the dark-room plate without text. The
text is added afterward by `render-talkie-just-say-it.swift` so it remains
sharp and editable:

```text
Recompose the dark-room product photograph with the complete iPad and its
single machined support enlarged enough to remain readable at App Store
thumbnail size, anchored in the lower-right quadrant. Preserve a broad,
uninterrupted headline field across the upper-left and upper-center. Keep the
screen as blank smoked-teal glass and preserve the charcoal room, dark floor,
warm copper left rim, cool slate-blue right rim, and restrained reflection.
Add no text, UI, logo, caption, card, controls, knobs, extra hardware, props,
people, scenery, bloom, or watermark.
```
