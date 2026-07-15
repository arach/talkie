#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPTURE_CLIP="$SCRIPT_DIR/raw/capture-flow.mov"
COMPOSE_CLIP="$SCRIPT_DIR/raw/compose-flow.mov"
OUTPUT_DIR="$SCRIPT_DIR/output"
OUTPUT_VIDEO="$OUTPUT_DIR/Talkie-App-Preview-6.9-inch.mp4"

for command in ffmpeg ffprobe; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

for clip in "$CAPTURE_CLIP" "$COMPOSE_CLIP"; do
    if [ ! -f "$clip" ]; then
        echo "Missing raw capture: $clip" >&2
        echo "See README.md for the simulator capture commands." >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"

# Story edit (29 seconds):
#   00.0–04.0  populated Talkie home
#   04.0–11.0  record, speech-shaped waveform, live transcript
#   11.0–16.0  save celebration and memo detail
#   15.5–29.0  inline dictation, voice command, before/after review
#
# The short fade-to-white is intentionally the only editorial transition.
# Apple previews autoplay muted, so a standards-compliant silent AAC track is
# included while the visuals carry the complete story.
ffmpeg -y -v error \
    -i "$CAPTURE_CLIP" \
    -i "$COMPOSE_CLIP" \
    -f lavfi -t 29 -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
    -filter_complex \
    "[0:v]trim=start=24:end=40,setpts=PTS-STARTPTS,fps=30,scale=886:-2:flags=lanczos,crop=886:1920[capture];\
[1:v]trim=start=18:end=31.5,setpts=PTS-STARTPTS,fps=30,scale=886:-2:flags=lanczos,crop=886:1920[compose];\
[capture][compose]xfade=transition=fadewhite:duration=0.5:offset=15.5,format=yuv420p[video]" \
    -map "[video]" -map 2:a \
    -t 29 \
    -c:v libx264 -profile:v high -level:v 4.0 -preset slow -crf 18 -r 30 \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -movflags +faststart \
    "$OUTPUT_VIDEO"

# Five seconds is Apple's default poster-frame neighborhood. At 5.2 seconds
# Talkie's waveform and live transcript are both in a strong readable state.
ffmpeg -y -v error \
    -ss 5.2 -i "$OUTPUT_VIDEO" \
    -frames:v 1 \
    "$OUTPUT_DIR/poster-frame.png"

ffmpeg -y -v error \
    -i "$OUTPUT_VIDEO" \
    -vf "fps=1/1.5,scale=177:-1,tile=5x4" \
    -frames:v 1 \
    "$OUTPUT_DIR/contact-sheet.png"

probe="$(ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate \
    -show_entries format=duration,size \
    -of default=nw=1 \
    "$OUTPUT_VIDEO")"

for expected in \
    "codec_name=h264" \
    "width=886" \
    "height=1920" \
    "pix_fmt=yuv420p" \
    "r_frame_rate=30/1"; do
    if ! grep -q "^${expected}$" <<<"$probe"; then
        echo "App Preview validation failed: expected $expected" >&2
        echo "$probe" >&2
        exit 1
    fi
done

duration="$(awk -F= '/^duration=/{print $2}' <<<"$probe")"
if ! awk -v duration="$duration" 'BEGIN { exit !(duration >= 15 && duration <= 30) }'; then
    echo "App Preview validation failed: duration is ${duration}s" >&2
    exit 1
fi

echo "$probe"
echo "Created $OUTPUT_VIDEO"
