#!/bin/bash
# Bump Talkie marketing version and global build number.
# Usage: ./scripts/bump-version.sh [major|minor|patch] or ./scripts/bump-version.sh 2.5.12

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../VERSION"
CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"

if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    NEW_VERSION="$1"
elif [[ "${1:-}" == "patch" ]]; then
    NEW_VERSION="$(echo "$CURRENT" | awk -F. '{print $1"."$2"."$3+1}')"
elif [[ "${1:-}" == "minor" ]]; then
    NEW_VERSION="$(echo "$CURRENT" | awk -F. '{print $1"."$2+1".0"}')"
elif [[ "${1:-}" == "major" ]]; then
    NEW_VERSION="$(echo "$CURRENT" | awk -F. '{print $1+1".0.0"}')"
else
    echo "Current version: $CURRENT"
    echo "Usage: $0 [major|minor|patch|X.Y.Z]"
    exit 0
fi

echo "Bumping version: $CURRENT -> $NEW_VERSION"
"$SCRIPT_DIR/sync-version.sh" "$NEW_VERSION" --bump-build
