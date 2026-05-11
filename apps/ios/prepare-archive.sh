#!/bin/bash
#
# Prepare iOS app for Archive.
# Run this before Archive in Xcode.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

"$ROOT_DIR/scripts/sync-version.sh" --bump-build

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")"

echo ""
echo "Ready: Talkie $VERSION ($BUILD_NUMBER)"
echo ""
echo "Now Archive in Xcode: Product -> Archive"
