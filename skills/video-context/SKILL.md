---
name: video-context
description: >
  Inspect video clips for AI context using ffprobe metadata and ffmpeg contact
  sheets. Use for Talkie tray clips, screen recordings, recently shared videos,
  dictation context clips, or any task asking what is visible in a video.
---

# Video Context

Use this skill when a video clip is evidence or context for engineering, product,
or agent work. The default move is: inspect metadata, make a 4x4 contact sheet,
then visually review the sheet before drawing conclusions.

## Workflow

1. Quote the video path and confirm it exists.
2. Run `ffprobe` for duration, size, dimensions, frame rate, and codec.
3. Generate a contact sheet with `scripts/clip_contact_sheet.sh`.
4. View the contact sheet with the local image viewer before summarizing.
5. Keep generated frames/contact sheets in temporary storage unless the user asks
   to preserve them.

## Commands

Metadata:

```bash
ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "$VIDEO"
```

Contact sheet from a video:

```bash
skills/video-context/scripts/clip_contact_sheet.sh "$VIDEO"
```

Contact sheet from pre-extracted frames:

```bash
ffmpeg -hide_banner -loglevel error \
  -pattern_type glob -i "$FRAME_DIR/frame-*.jpg" \
  -vf 'tile=4x4:margin=8:padding=4,scale=1720:-1' \
  "$OUT_JPG"
```

For Talkie clips, look first under:

```text
~/Library/Application Support/Talkie/Tray/clips/
```

## Interpretation

- Treat the contact sheet as a map of visual states, not as proof of every frame.
- If motion timing matters, extract a short slice or individual frames around the
  relevant timestamp after the first pass.
- Pair the visual read with adjacent transcript, screenshot, or tray metadata
  when available.
