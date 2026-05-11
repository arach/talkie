# Media Capture Quality Validation

## Summary

Talkie's current media capture defaults are generally reasonable for a **high-fidelity archival workflow**, but they are not yet optimized for an **AI-reference workflow** where smaller files and lower storage pressure may matter more than pixel-perfect fidelity.

The practical answer is:

- **Screenshots:** currently high quality, full-resolution, lossless PNG
- **Screen clips:** currently fixed H.264 MP4 at a medium-high bitrate
- **Camera clips:** already configurable in settings
- **Screenshot quality:** **not configurable today**
- **Lower-quality region capture for agent workflows:** **absolutely possible**, but requires code changes

## What the app does today

### Screenshots

The screenshot pipeline currently captures at best/native resolution and always encodes as PNG:

- fullscreen uses `CGDisplayCreateImage`
- region uses `CGWindowListCreateImage(..., [.bestResolution])`
- window uses `CGWindowListCreateImage(..., [.bestResolution, .boundsIgnoreFraming])`
- encoded output is always `UTType.png`
- storage is always `Talkie/Screenshots/*.png`

This means screenshots are effectively stored as **full-fidelity lossless assets**.

### Screen clips

Screen recording uses:

- `SCStreamConfiguration`
- capture dimensions based on the selected display/region/window
- 30 fps minimum frame interval
- H.264 MP4 output
- fixed average bitrate of **6 Mbps**

That is a solid default for readable UI video, but it is not adaptive by capture mode, not user-configurable, and not especially storage-sensitive.

### Camera clips

Camera bubble recording already has a real quality model:

- `standard` = 720p at **2 Mbps**
- `high` = 1080p at **4 Mbps**
- codec can be `H.264` or `HEVC`

This is the cleanest example in the current codebase of a capture-quality system that could be mirrored for screenshots and screen clips.

## What we observed locally

From the current local media directories:

- screenshots directory size: **11 MB**
- videos directory size: **14 MB**

Screenshots:

- file count: **18**
- total: **11.22 MB**
- median: **463.6 KB**
- average: **638.6 KB**
- 90th percentile: **1412.2 KB**
- max: **1687.7 KB**

Videos:

- file count: **10**
- total: **13.69 MB**
- median: **0.85 MB**
- average: **1.37 MB**
- 90th percentile: **2.97 MB**
- max: **3.20 MB**

## Interpretation

### Are the current defaults reasonable?

Yes, with an important qualifier.

For a product where screenshots may be:

- user-visible
- reopened later
- reviewed manually
- dragged into other apps
- used for annotation/editing

PNG is a defensible default. It preserves text edges, avoids compression artifacts, and keeps capture semantics simple.

For screen clips, 6 Mbps H.264 is also a defensible default if the goal is "readable UI motion without obvious degradation."

### Are they optimal for AI-agent feedback workflows?

No, probably not.

If the main use case is:

- capturing UI state for AI analysis
- providing visual context to an agent
- storing many short region captures
- prioritizing throughput and storage over perfect fidelity

then the current defaults are likely heavier than necessary, especially for screenshots.

The biggest mismatch is that **region screenshots are treated the same way as archival screenshots**, even though small cropped UI captures often compress extremely well as JPEG or HEIC with minimal impact on legibility.

## Can we define lower-quality or smaller presets?

Yes. The codebase is structurally ready for this, even though screenshot quality does not have a settings model yet.

### What is already configurable

- camera quality
- camera codec
- max camera clip duration
- screenshot launcher app

### What is not configurable yet

- screenshot format (`png` vs `jpeg` vs `heic`)
- screenshot compression level
- screenshot max dimensions
- per-mode capture policy (`fullscreen` vs `region` vs `window`)
- screen recording bitrate
- screen recording codec
- AI-oriented vs archival capture presets

## Recommended product direction

Instead of a single "quality" toggle, the better model is probably **capture intent**.

Suggested presets:

### 1. Archive

- screenshots: PNG
- no downscaling
- clips: H.264 or HEVC at current/high bitrate
- best for long-term storage, annotation, and human review

### 2. Balanced

- screenshots: JPEG or HEIC for region/window, PNG for fullscreen if needed
- optional max dimension cap
- clips: slightly lower bitrate than current defaults
- best default for most users

### 3. Agent

- screenshots: aggressively optimized for AI context
- region/window captures downscaled if large
- JPEG/HEIC at moderate compression
- clips: HEVC preferred, reduced bitrate
- best when captures are mostly prompts/context, not artifacts users will export

## Specific recommendations

### Screenshots

For screenshots, I would recommend:

1. Keep `PNG` as the default archival format.
2. Add a screenshot capture preset in settings.
3. Let presets vary by mode:
   - `fullscreen`: PNG or high-quality JPEG depending on preset
   - `window`: JPEG/HEIC is likely acceptable in most cases
   - `region`: best candidate for lower-quality agent mode
4. Add optional max pixel bounds in non-archive presets.

Example direction:

- `Archive`: PNG, full size
- `Balanced`: JPEG quality ~0.82 to 0.88, max width 2200 to 2800 px
- `Agent`: JPEG/HEIC quality ~0.65 to 0.78, max width 1400 to 1800 px for region captures

### Screen clips

For screen clips:

1. Expose codec and bitrate under a screen recording settings section.
2. Prefer `HEVC` when available for smaller files at similar readability.
3. Add bitrate tiers, for example:
   - `Agent`: 2.5 to 4 Mbps
   - `Balanced`: 4 to 6 Mbps
   - `Archive`: 6 to 10 Mbps

### Metadata

If we make quality tunable, we should also store:

- encoded file size
- format (`png`, `jpeg`, `heic`)
- quality preset used
- original dimensions vs stored dimensions

That will help the UI and make debugging much easier.

## Implementation feasibility

This is very feasible.

### Easy changes

- add screenshot settings fields to `TalkieSettingsConfiguration`
- add screenshot quality controls to `CameraSettingsView` or a new `Media/Capture` settings section
- add screen recording bitrate/codec settings
- surface file size in the UI

### Moderate changes

- replace hardcoded PNG-only screenshot encode with a format-aware encoder
- optionally downscale screenshots before encoding
- thread preset choice through tray capture and recording attachment flows

### Harder changes

- HEIC support if we want broad encode/decode handling and clean drag/export behavior everywhere
- adaptive quality based on image content

## Recommended next pass

If we want to move carefully, the best second pass is:

1. Add a `Screenshot Capture Preset` setting with `Archive`, `Balanced`, `Agent`
2. Add a `Screen Clip Quality` setting with bitrate tiers
3. Keep current behavior as the `Archive` default
4. Implement `Agent` mode only for `region` and `window` screenshots first
5. Track file size in metadata so we can validate real savings

That gives us a low-risk way to test whether smaller, AI-oriented captures are materially better without regressing the current high-fidelity workflow.
