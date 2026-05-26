#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist

# Prefer an already-cached TypeScript compiler so this app-resource build does
# not require network or a package install. Fall back to bunx for clean machines.
TSC_JS="${TALKIE_TSC_JS:-$HOME/.bun/install/cache/typescript@6.0.3@@@1/lib/_tsc.js}"
if [[ -f "$TSC_JS" ]]; then
  node "$TSC_JS" -p tsconfig.json
else
  bunx tsc -p tsconfig.json
fi
