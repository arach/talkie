#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 VIDEO [OUT_JPG]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

video=$1
if [[ ! -f "$video" ]]; then
  echo "video not found: $video" >&2
  exit 1
fi

duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
duration=${duration:-0}

if [[ $# -eq 2 ]]; then
  out=$2
else
  base=$(basename "$video")
  base=${base%.*}
  out="${TMPDIR:-/tmp}/${base}.contact.jpg"
fi

mkdir -p "$(dirname "$out")"

fps=$(awk -v duration="$duration" 'BEGIN {
  if (duration > 0) {
    value = 16 / duration
    if (value < 0.02) value = 0.02
    printf "%.6f", value
  } else {
    printf "1"
  }
}')

ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "$video"

ffmpeg -hide_banner -loglevel error \
  -i "$video" \
  -vf "fps=${fps},scale=430:-1,tile=4x4:margin=8:padding=4,scale=1720:-1" \
  -frames:v 1 \
  "$out"

ls -l "$out"
