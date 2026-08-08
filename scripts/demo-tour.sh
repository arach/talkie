#!/bin/bash
set -euo pipefail

# Walks the app through the core screens on a fixed cadence, for screen
# recording. Navigation goes through the URL scheme rather than synthetic
# clicks so a take is reproducible: no coordinates to drift when a sidebar
# gains an item, and no mis-clicks landing in another app.
#
# Pair it with a recorder — start the recorder, run this, stop the recorder.
#
# Usage:
#   ./scripts/demo-tour.sh                 # dev build (talkie-dev://)
#   ./scripts/demo-tour.sh --prod          # release build (talkie://)
#   ./scripts/demo-tour.sh --dwell 4       # seconds to hold each screen

SCHEME="talkie-dev"
DWELL=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod)  SCHEME="talkie"; shift ;;
    --dwell) DWELL="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Each stop is "route|caption". The caption is what the screen is meant to
# show a viewer, and doubles as the narration track if one gets recorded.
#
# Every route here is registered in AppRoutes/SystemRoutes — check with
# `open "${SCHEME}://debug/routes"` before adding one. The Editor has no
# route yet, which is why it isn't a stop.
STOPS=(
  "home|Everything you captured today, in one place"
  "library|Every memo and dictation, searchable"
  "screenshots|Mark up a capture without leaving the app"
  "workflows|Chain audio, an LLM, and a destination into one routine"
  "console|The agent's own terminal, running locally"
  "home|Back home"
)

echo "▶ Demo tour · ${#STOPS[@]} stops · ${DWELL}s each · ${SCHEME}://"
echo

# Bring the app forward before the first stop, so the opening frame of a
# recording is the app rather than whatever was in front of it.
open "${SCHEME}://home"
sleep 2

for stop in "${STOPS[@]}"; do
  route="${stop%%|*}"
  caption="${stop#*|}"
  printf '  %-16s %s\n' "$route" "$caption"
  open "${SCHEME}://${route}"
  sleep "$DWELL"
done

echo
echo "✓ Tour complete"
