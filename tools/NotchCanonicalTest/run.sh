#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--detached" ]]; then
  swift build
  open ./.build/debug/NotchCanonicalTest
  echo "Started NotchCanonicalTest via open"
  exit 0
fi

swift run
