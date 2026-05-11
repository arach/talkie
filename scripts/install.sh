#!/bin/bash
set -euo pipefail

# Talkie installer — curl -fsSL go.usetalkie.com/install | bash
#
# Installs @talkie/cli via the best available package manager,
# then downloads and launches Talkie.app.

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

info()  { echo -e "  ${BOLD}$1${RESET}"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $1"; }
fail()  { echo -e "  ${RED}✗${RESET} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Platform check
# ---------------------------------------------------------------------------

[[ "$(uname)" == "Darwin" ]] || fail "Talkie is macOS only"

# ---------------------------------------------------------------------------
# Ensure bun is installed (required runtime for @talkie/cli)
# ---------------------------------------------------------------------------

ensure_bun() {
  if command -v bun &>/dev/null; then
    ok "bun $(bun --version)"
    return
  fi

  info "installing bun..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"

  if command -v bun &>/dev/null; then
    ok "bun $(bun --version) installed"
  else
    fail "could not install bun — install manually: https://bun.sh"
  fi
}

# ---------------------------------------------------------------------------
# Detect best package manager for global install
# ---------------------------------------------------------------------------

detect_pm() {
  # Prefer bun > pnpm > yarn > npm
  if command -v bun &>/dev/null; then
    echo "bun"
  elif command -v pnpm &>/dev/null; then
    echo "pnpm"
  elif command -v yarn &>/dev/null; then
    echo "yarn"
  elif command -v npm &>/dev/null; then
    echo "npm"
  else
    echo "bun"
  fi
}

install_global() {
  local pm="$1"
  local pkg="@talkie/cli"

  case "$pm" in
    bun)   bun install -g "$pkg" ;;
    pnpm)  pnpm add -g "$pkg" ;;
    yarn)  yarn global add "$pkg" ;;
    npm)   npm install -g "$pkg" ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
info "Talkie Installer"
echo ""

# 1. Ensure bun runtime
ensure_bun

# 2. Pick package manager and install CLI
PM=$(detect_pm)
info "installing @talkie/cli via ${PM}..."
if install_global "$PM"; then
  ok "@talkie/cli installed"
else
  fail "install failed — try manually: ${PM} install -g @talkie/cli"
fi

# 3. Download and install Talkie.app
echo ""
info "installing Talkie.app..."
echo ""
talkie install --launch --pretty

echo ""
ok "all done — enjoy Talkie"
echo ""
