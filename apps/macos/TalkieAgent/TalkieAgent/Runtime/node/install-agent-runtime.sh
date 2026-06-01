#!/bin/zsh
set -euo pipefail

RUNTIME_HOME="${TALKIE_AGENT_RUNTIME_HOME:-$HOME/.talkie/agent-runtime}"
RUNTIME_PACKAGE="${TALKIE_AGENT_RUNTIME_PACKAGE:-@talkie/agent-runtime@0.1.0}"

if ! command -v npm >/dev/null 2>&1; then
  printf '[TalkieAgent] npm is required to install %s.\n' "$RUNTIME_PACKAGE" >&2
  printf '[TalkieAgent] Install Node.js/npm first, then rerun this command.\n' >&2
  exit 1
fi

mkdir -p "$RUNTIME_HOME"

printf '[TalkieAgent] Installing %s into %s\n' "$RUNTIME_PACKAGE" "$RUNTIME_HOME"
npm install \
  --foreground-scripts \
  --install-links \
  --no-audit \
  --no-fund \
  --prefix "$RUNTIME_HOME" \
  "$RUNTIME_PACKAGE"

MODULE_PATH="$RUNTIME_HOME/node_modules/@talkie/agent-runtime/index.mjs"
if [[ ! -f "$MODULE_PATH" ]]; then
  printf '[TalkieAgent] Install finished, but %s was not found.\n' "$MODULE_PATH" >&2
  exit 1
fi

mkdir -p "$RUNTIME_HOME/bin"
if [[ -x "$RUNTIME_HOME/node_modules/.bin/talkie-agent-runtime" ]]; then
  ln -sf "$RUNTIME_HOME/node_modules/.bin/talkie-agent-runtime" "$RUNTIME_HOME/bin/talkie-agent-runtime"
fi

printf '[TalkieAgent] Talkie Agent Runtime ready.\n'
printf '[TalkieAgent] Module: %s\n' "$MODULE_PATH"
printf '[TalkieAgent] Doctor: %s\n' "$RUNTIME_HOME/bin/talkie-agent-runtime doctor"
