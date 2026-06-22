# TLK-032 Review — Share / Export Studio

**Reviewer**: Claude (tlk-032-review-claude) — stance: skeptical PM + pragmatic macOS architect
**Date**: 2026-06-20
**Spec reviewed**: [tlk-032-share-export-studio.md](tlk-032-share-export-studio.md)
**Grounding**: read against the current macOS codebase (TalkieObject model, CaptureMediaFileResolver, existing share paths). Citations inline.

---

## 1. Verdict

**Promising but needs cuts.**

The core thesis is right: Talkie has capture and collection, the missing layer is *output*, and "make this safe, beautiful, and correctly sized for where I'm sending it" is a real job. The spec is well-organized and the data-model instincts are sound.

But it is not spec-ready as written, for three reasons:

1. **"Private" is a trust promise the V1 treatment cannot keep** (cosmetic blur over metadata that includes browser URLs, terminal paths, and window titles). Shipping it as specified is worse than not shipping it.
2. **One surface for screenshots + clips + recordings is asserted, not earned.** Screenshots and recording cards share almost no controls; "one mental model" buys conditional UI, not simplicity.
3. **V1 is labeled "intentionally small" but spans images + recording cards + 4 presets + 7 controls + 2 actions + video in Milestone 2.** That's a medium feature wearing a small label.

Cut it to a screenshot-only framing panel and it's shippable. Keep the full surface and it's a quarter of work with a privacy landmine in it.

---

## 2. Top 5 Product Risks (by severity)

**P1 — "Private" implies safety it does not deliver.** The spec gives one word, *Private*, then defines the treatment as `blur + tint + centered Private pill` on the rendered image, with `metadata: still visible unless separately hidden`. The captured metadata is not benign: the model stores `browserURL`, `terminalWorkingDir`, `windowTitle`, `appBundleID` (RichContext, in `RecordingMetadata`). A user who trusts "Private" and shares the artifact can leak a URL or a working-directory path in the visible metadata strip or in residual EXIF/source-path data — the exact opposite of what the word promises. A blur is also defeatable if the radius is tuned for aesthetics over redaction. **A privacy feature that is mostly cosmetic is a liability, not a feature.**

**P2 — One surface, three media types → lowest-common-denominator UI.** Screenshots/clips want *framing* (background, padding, corners, shadow, chrome around existing pixels). Recordings want *card composition* (synthesize a new card from title, waveform, transcript, duration). These share almost no controls and require two distinct render paths. Forcing "one mental model" means every control needs a "does this apply to this artifact?" branch and users see knobs that do nothing. The shared model is claimed in the Product Frame but never justified.

**P3 — "Polished in under five seconds" is a promise against strong incumbents.** The success criterion competes directly with CleanShot X and the native macOS share sheet. If the default Polished output isn't visibly better than dragging the raw file into Slack, nobody opens the panel — the raw drag is already <5 seconds. The spec never commits to what "good framing" looks like or to a default that wins on open. Risk: a feature that ships and is never used.

**P4 — Presets-vs-knobs tension is unresolved.** "Most users should use presets, not tune individual knobs" — then V1 ships 7 controls *and* 4 presets. If presets are the bet, V1 should be preset-first with the knobs collapsed behind a disclosure. Shipping both produces the cluttered inspector the "work surface, not landing page" line says to avoid.

**P5 — "Destination Recipes" sets an expectation V1 won't meet.** The Slack/Linear/Notion/Slides table reads like Talkie knows each destination's needs. V1 produces a generic PNG; the table is documentation, not behavior. If it surfaces in the UI as a "Slack preset," users expect it to post to Slack. Either make destinations real (out of scope) or reframe the table as *size/quality* guidance and drop the destination names from the surface.

---

## 3. Top 5 Implementation Risks (by severity)

**I1 — No rasterization infrastructure exists; the render engine is the entire build.** There is no `ImageRenderer`, no `NSGraphicsContext`/`CGContext` pipeline anywhere in macOS today — only `NSSharingServicePicker` for raw-file shares (`ScopeCaptureDetailView.swift:777-781`, `ScreenshotsScreen.swift`). The spec's "V1 may use native rendering: SwiftUI/AppKit into bitmap" is one line hiding the single largest cost. `ImageRenderer` (macOS 13+) has real traps: Retina scale factor, async-loaded source images rendering blank, shadows clipped by view bounds, color management. **Budget the renderer as the critical path, not a footnote.**

**I2 — Styled video export is a full re-encode, not "where technically feasible."** No `AVMutableComposition` / `AVAssetExportSession` for video exists (only audio M4A export in `AudioArchiver.swift`, and recording-time `AVAssetWriter`). Adding background/padding/corners around a clip means compositing every frame through a Core Animation layer and re-encoding — slow, lossy, a large new pipeline. The phrase "where technically feasible" (Milestone 2) carries enormous load. Recommend: V1/V2 video = trim + quality tier only; **no framing around video** until there's a reason to pay for the composition pipeline.

**I3 — Privacy redaction has zero data-model support and the data is genuinely sensitive.** No `private`/`sensitive`/`redact`/`blur` field exists in `TalkieObject.swift`, `TalkieObjectMetadata.swift`, or any asset struct. Building Private *correctly* means a new subsystem: strip/redact metadata fields, scrub RichContext (`browserURL`, `terminalWorkingDir`, `windowTitle`), and guarantee the exported file carries no residual source path or EXIF. That is not a visual treatment — it's a feature on its own.

**I4 — Media files are resolved by multi-directory search, not stable URLs.** `CaptureMediaFileResolver.primaryMedia(for:)` searches Tray + persistent + attachment directories in priority order (`CaptureMediaFileResolver.swift:54-210`); tray items can be ephemeral and paths aren't guaranteed permanent. The renderer's clean boundary ("input: artifact reference + recipe") is the right shape, but the "reference" must be a **resolved, validated file URL**, not a bare `UUID`, and the renderer must handle missing-source gracefully (and probably copy/snapshot the source at export time).

**I5 — Metadata is fragmented across JSON blobs, per artifact type.** `TalkieObject` keeps screenshot/clip/attachment metadata in `assetsJSON`/`metadataJSON` (`TalkieObject.swift:76,85`), decoded into per-type substructures with different fields present per type. The export's metadata toggles (dimensions, file size, app/source, duration) need a per-type resolution layer; otherwise half the `ExportMetadataOptions` toggles render empty for half the artifacts. (Note the positives that *de-risk* the model: `id: UUID` is stable as the spec assumes — `TalkieObject.swift:23` — and transcript text is first-class via `text`/`timedTranscription`, `TalkieObject.swift:24,277`, so the spec's `artifactID: UUID` and transcript-excerpt plans are safe.)

---

## 4. What to Cut from V1

Make the first release a **screenshot/image framing panel** and nothing else. Specifically:

- **Cut recording share cards** → defer one milestone. This is the biggest single cut and directly answers Open Question #1: image-only first. (Recording cards are a *different render model* — see §6 position.)
- **Cut the "Private" preset and Private control entirely** → do not ship cosmetic privacy. Re-introduce only when the redaction subsystem (I3) exists. Shipping Private-as-blur is a net-negative on trust.
- **Cut the Bug Report preset** → depends on the fragmented-metadata resolution layer (I5); defer with metadata work.
- **Cut Shadow and Chrome controls** → background + padding + corners deliver ~90% of "polished." Window chrome is its own rabbit hole; device frames are already marked "later."
- **Cut the Destination Recipes table from the surface** → keep it as internal guidance for quality-tier defaults only.
- **Cut WebP** → PNG + JPEG only for V1.
- **Defer all video** (Milestone 2 as written) until the still-image path has shipped and earned the next investment.

**Resulting sharp V1**: screenshots only · presets **Original** + **Polished** · controls **background / padding / corners / quality / format(PNG, JPEG)** · actions **Copy** + **Save As**. One render path, one media type, no privacy claims. That is a release you can ship, measure, and build on.

---

## 5. Muddy / Overpromising / Too-Abstract Language

Quoting headings/phrases with proposed rewrites:

- **Summary — "polished, *safe*, and correctly sized"** and **the core job "Make this thing *safe*, beautiful, and correctly sized."** "Safe" is the overpromise; V1 can't deliver it. → Rewrite: *"Make this beautiful and correctly sized for where I'm sending it — without accidental recompression."* Re-introduce "safe" only when redaction ships.

- **Product Frame — "privacy as an opt-in *treatment*"** and **"support both with one mental model."** "Treatment" is the tell that it's cosmetic; "one mental model" is asserted. → Rewrite: *"Screenshots/clips and recordings share one entry point and command language, but use two composition bodies. Privacy, in V1, is out of scope — see Privacy."*

- **Privacy — "One user-facing state: Private"** + **"metadata: still visible unless separately hidden."** This pairing is the dangerous part. A privacy mode that leaves metadata visible *by default* is not private. → Rewrite the default: *"When Private is on, metadata and RichContext (URLs, paths, window titles) are stripped by default and the user opts specific fields back in."* And state plainly: *"Private must scrub source-path/EXIF from the exported file. A visual blur alone is not Private."*

- **Presets → Private — "app/source metadata visible by default."** Directly contradicts the privacy intent. → Rewrite: *"all metadata hidden by default; app/source opt-in."*

- **Surface Layout — "Expensive video transcodes can show an *estimated output* and run on export."** Vague. → Define: *"video preview uses a still-frame proxy at the chosen framing; the actual transcode runs on Copy/Save with a progress indicator."*

- **Rendering Model / Milestones — "V1 may use native rendering," "where possible," "where technically feasible" (3×).** Every hedge hides cost. → Replace each with a commitment or an explicit deferral. E.g. Milestone 2: *"Video framing (background/padding/corners) is deferred; V1–V2 video supports trim + quality tier only."*

- **Metadata — "Defaults by preset, not by raw control state."** Right principle, underspecified. → Add: *"Each preset defines a default control matrix **per artifact type**, since available controls differ by type."*

- **Success Criteria — "make a screenshot look polished in under five seconds."** Marketing claim, not a spec. → Rewrite measurably: *"Time-to-first-Copy with the Polished preset is under five seconds from Export…; 'polished' = the exact output of the Polished preset."*

- **Title — "Share / Export *Studio*."** "Studio" oversells a panel and collides with the existing design `studio/`. → Call V1 what it is: *"Export panel"* (or inspector). Reserve "Studio" for the later multi-media surface if it ever earns the name.

---

## 6. Recommended V1 User Flow (image-only)

1. User has a screenshot in a Library row, the capture detail toolbar, or a tray hover action.
2. User triggers **Export…** (or **Copy Styled**). It opens as an **inspector over the current detail view** — not a separate navigation destination (answers Open Question #4).
3. Panel opens with the **Polished** preset pre-selected and the live preview **already rendered** — the default that wins on open.
4. Left: large preview of the framed screenshot. Right column top: preset chips (**Original · Polished**).
5. User optionally adjusts **background / padding / corners**; the preview updates synchronously (stills are cheap with `ImageRenderer`).
6. User optionally picks **quality** (Small / Medium / High) and **format** (PNG / JPEG); the panel shows resulting **pixel dimensions + estimated file size**.
7. User clicks **Copy** → styled PNG to the pasteboard, toast confirms "Copied." Or **Save As** → standard save panel → **Reveal in Finder**.
8. Panel remembers the **last-used preset** for the next image (answers Open Question #5: yes, simplest scope = a single global last-used preset).

Eight steps, one media type, no Private, no recording card, no video.

---

## 7. Position on "one export surface for screenshots, clips, and recordings"

**The operator asked me to take a side. My position: no — not as one render path, and not in V1.**

Keep **one entry point and one command language** (`Share… / Export… / Copy Styled / Copy Original`) across all artifact types — that's good and reduces surface sprawl. Keep shared infrastructure (quality tiers, format, the eventual privacy subsystem, pasteboard/save plumbing).

But **fork the composition body**:

- **"Frame the media" path** (screenshots, clips): transform *existing pixels* — background, padding, corners, shadow around what's already there.
- **"Compose a card" path** (recordings): synthesize *new pixels* — lay out title, waveform, duration, transcript excerpt into a card.

These are different rendering models with disjoint control sets and disjoint preview pipelines. Unifying them forces conditional UI and a doubled preview path for a "one mental model" benefit users won't perceive. Ship the framing path in V1; the recording card is a sibling surface in a later milestone, behind the same Export… entry point.

(Architecture note that supports this and answers the TLK-018 question: put the **renderer in TalkieKit**, not in the Talkie app target, so TalkieAgent can reuse it. Treat this as its own feature track, not a sub-bullet of the TLK-018 media roadmap.)

---

## 8. Open Questions That Must Be Answered Before Swift

Re-answering the spec's own questions with a recommendation, plus the ones it omits:

**Must decide before writing the shell:**

1. **Minimum macOS deployment target?** *(spec never states it — this gates everything.)* `ImageRenderer` is macOS 13+. If the target is older, the renderer is AppKit `NSImage`/`bitmapImageRep` and the cost goes up. **Answer this first.**
2. **Surface form: modal / inspector / nav destination?** (Open Q #4.) → Recommend **inspector over detail**. Decides view hierarchy and who owns preview state.
3. **Image-only V1?** (Open Q #1.) → Recommend **yes** (cut recording cards, §4).
4. **What does "Private" guarantee in V1?** If the honest answer is "blur + pill, metadata still present," then **Private does not ship in V1** (P1/I3). Decide: cut it, or fund real redaction.

**Must decide before the renderer:**

5. **Does the renderer resolve+copy the source at export time?** Files aren't on stable paths (I4). Define the missing-source behavior.
6. **Pasteboard contract for "Copy."** What types does it write — PNG only, or PNG + TIFF + file URL? Determines paste behavior into Slack vs. Finder vs. a doc.
7. **Export scale / color management.** Target scale for stills (1× logical, 2× Retina, source-native) and color space? Directly affects the "correctly sized" promise.

**Defer-able but name the owner:**

8. **TLK-018 roadmap vs. separate track** (spec's final review item). → Recommend **separate track; renderer in TalkieKit** (§7).

---

### Bottom line

Cut to a screenshot-only framing panel (Original + Polished, four controls, Copy/Save As), drop the cosmetic Private until redaction is real, and keep recordings + video behind the same entry point for later. That version is sharp, shippable, and honest about what it promises. The full spec as written is a quarter of work with a privacy landmine; the cut version is a few weeks with a clean spine you can grow.
