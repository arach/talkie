# TLK-018 — Media Surface Roundup

**Status**: Draft
**Owner**: TBD

## Summary

Talkie currently treats screenshots, clips, and attachments as related but separate concepts:

- `ScreenshotsScreen` mixes tray captures with screenshots already attached to recordings
- `TrayViewer` is a temporary capture gallery for screenshots, clips, and selections
- `TOAttachmentsSection` is a generic recording attachment browser
- iOS memo attachments are image-only and use the label "attachments"

That split makes the product feel more technical than intentional. A user who thinks in terms of "media I captured during this session" has to translate that idea into screenshots vs clips vs attachments vs tray state.

The user feedback here is directionally right:

- there are too few obvious actions on a media item
- right-click affordances are inconsistent or hidden
- double-click behavior is inconsistent
- visible metadata is sparse
- "Screenshots" is too narrow once clips and recordings are part of the same story

## Current gaps

### 1. Interaction model is inconsistent

- `ScreenshotsScreen` tray cards support a context menu, but attached screenshot rows only expose meaningful actions through a hidden right-click menu and single-click just selects the parent recording.
- `TrayViewer` supports double-click to enter a detail preview, but the gallery/list rows do not expose a SwiftUI context menu, so right-click is effectively absent there.
- The floating `ScreenshotPreviewPanel` has a custom AppKit right-click menu, but only for copy and dismiss.

Net effect: the app has actions, but the user has to guess where each surface hides them.

### 2. Metadata exists, but the UI does not surface enough of it

We already store a fair amount:

- iOS memo attachments store file size and pixel dimensions
- tray screenshots store width, height, mode, app name, window title, and display name
- recording attachments store file size and dimensions
- clips store duration and dimensions

But the main media surfaces rarely show:

- file size
- exact capture time
- duration for clips outside specific views
- whether the item is in tray vs saved on a recording
- source context in a consistent, readable way

### 3. Naming is too implementation-shaped

"Screenshots" works for a narrow feature, but not for the broader user mental model:

- screenshots
- video clips
- recording attachments
- imported photos/images

"Media" is the better top-level label for the product surface. "Screenshot" and "Clip" can remain item types inside that surface.

### 4. Important actions are discoverability-poor

The most likely actions a user wants are:

- open
- quick preview
- reveal in Finder
- copy
- share/export
- edit/annotate
- remove
- attach or move to a recording

Today many of those exist only in one surface, one hidden menu, or one small icon.

## Product recommendation

Rename the user-facing surface from **Screenshots** to **Media** and standardize every media item around one interaction contract:

- single click selects
- double click opens or quick-previews
- right click always shows the same style of action menu
- hover reveals a small action strip
- an inspector or detail pane shows metadata and secondary actions

That gives us a consistent mental model across screenshots, clips, and imported images.

## Suggested improvements

### Quick wins

1. **Add visible metadata to rows and cards**
   - Show file size anywhere a screenshot, clip, or attachment is listed.
   - Show `WIDTH × HEIGHT` plus clip duration when relevant.
   - Show exact capture timestamp on hover or in a secondary line.
   - Add a small status chip like `Tray`, `Saved`, or `Pinned`.

2. **Make actions visible without requiring right-click**
   - Add an inline action strip on hover for `Open`, `Reveal`, `Copy`, and `Remove`.
   - Keep destructive actions secondary, but do not hide all useful actions behind context menus.

3. **Normalize double-click behavior**
   - Double-click on tray items should open the actual media preview, not just the tray viewer shell.
   - Double-click on saved screenshot rows should open the file or a built-in preview.
   - Double-click on clips should open the clip player.

4. **Add context menus everywhere media appears**
   - `TrayViewer` gallery/list/carousel items should all offer a context menu.
   - Saved media rows should expose the same actions as tray items where possible.
   - Menus should be type-aware but structurally consistent.

5. **Show size and dimensions in iOS attachment tiles**
   - Even a lightweight secondary label like `2.4 MB • 1440×900` would make the items feel more tangible.

### Medium improvements

1. **Add a shared media inspector**

   Instead of each surface inventing its own tiny metadata strip, use a shared inspector panel that can show:

   - preview
   - type
   - file size
   - dimensions
   - duration
   - captured/added time
   - source app or window
   - location or owning recording
   - actions

2. **Merge screenshots and clips into one media browser**

   The current `ScreenshotsScreen` already pulls screenshots, clips, and selections from tray state but only saved screenshots from recordings. A real media browser should support:

   - filters: `All`, `Images`, `Clips`, `Selections`, `Saved`, `Tray`
   - search across app, window, title, and recording
   - sort by newest, oldest, largest, longest

3. **Add Quick Look style preview**

   Space bar should preview the selected media item everywhere this makes sense on macOS. That would immediately make the surface feel native.

4. **Add export/share pathways**

   - Share sheet
   - Copy file path
   - Save As
   - Open With
   - Annotate/Edit

### Bigger product moves

1. **Rename surfaces to "Media"**

   Examples:

   - `Screenshots` tab → `Media`
   - `Add screenshots or photos` → `Add media`
   - `No Screenshots` → `No Media`

2. **Introduce media-specific types and filters in the UI**

   The browser should visually distinguish:

   - screenshot
   - clip
   - imported image
   - document attachment

3. **Treat tray as a state, not a separate concept**

   Longer term, "tray" should feel like a filter or status inside the media system, not a different product area users need to understand.

## Recommended milestone plan

### Milestone 1 — discoverability

- Rename the primary screen copy to "Media"
- Add context menus to `TrayViewer`
- Add visible file size and richer secondary metadata
- Add inline hover actions to saved media rows
- Normalize double-click behavior

### Milestone 2 — shared preview + inspector

- Build a reusable media inspector
- Reuse it in tray viewer, saved media list, and attachments
- Add Quick Look style preview and keyboard shortcuts

### Milestone 3 — true unified media browser

- Merge screenshots/clips/imported images into one browser
- Add filters and sort
- Reduce the prominence of implementation terms like "tray"

## Code touchpoints

These are the main files to update if we turn this into implementation work:

- `apps/macos/Talkie/Views/ScreenshotsScreen.swift`
- `apps/macos/Talkie/Services/Tray/TrayViewer.swift`
- `apps/macos/Talkie/Services/Screenshots/ScreenshotPreviewPanel.swift`
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOAttachmentsSection.swift`
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift`
- `apps/ios/Talkie iOS/Views/MemoAttachmentsSection.swift`
- `apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/TranscriptionSegments.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/RecordingClip.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/RecordingAttachment.swift`

## Recommendation

If we want the highest-value first pass, do this:

1. Rename the surface to `Media`
2. Add visible metadata, especially file size
3. Add consistent right-click menus and double-click open behavior
4. Add one shared preview/inspector instead of scattering actions across hidden menus

That would make the feature feel much more intentional without requiring a full media-system rewrite.

## References

- Companion capture-quality spec: TLK-017 (`docs/specs/tlk-017-media-capture-quality.md`)
