#!/bin/bash
set -e

# Talkie Full Release Script
# End-to-end release: version sync → build → tag → push → publish
#
# Usage:
#   ./scripts/ship.sh 2.0.18
#   ./scripts/ship.sh 2.0.18 --dry-run    # Preview without executing
#   ./scripts/ship.sh 2.0.18 --skip-build # Skip build (use existing DMG)
#   ./scripts/ship.sh 2.0.18 --quiet      # No voice announcements

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
USETALKIE_DIR="$HOME/dev/usetalkie.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Voice announcements via speakeasy (non-blocking, fail-safe)
announce() {
    if [ "$QUIET" -eq 1 ]; then return; fi
    if command -v speakeasy &> /dev/null; then
        (speakeasy "$1" --provider openai --voice nova &) 2>/dev/null || true
    fi
}

# Parse arguments
VERSION=""
DRY_RUN=0
SKIP_BUILD=0
QUIET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

# Validate version
if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Version required${NC}"
    echo "Usage: ./scripts/ship.sh 2.0.18"
    echo "       ./scripts/ship.sh 2.0.18 --dry-run"
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ Invalid version format: $VERSION${NC}"
    echo "Expected format: X.Y.Z (e.g., 2.0.18)"
    exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           TALKIE RELEASE v$VERSION                    ${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

announce "Starting Talkie release $VERSION"

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}🔍 DRY RUN - No changes will be made${NC}"
    echo ""
fi

# Step 1: Check prerequisites
echo -e "${CYAN}[1/7]${NC} Checking prerequisites..."

if [ ! -d "$USETALKIE_DIR" ]; then
    echo -e "${RED}❌ usetalkie.com repo not found at $USETALKIE_DIR${NC}"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not installed${NC}"
    exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected:${NC}"
    git status --short
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} Prerequisites OK"
echo ""

# Step 2: Sync version
echo -e "${CYAN}[2/7]${NC} Syncing version to $VERSION..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would run: ./scripts/sync-version.sh $VERSION"
else
    "$SCRIPT_DIR/sync-version.sh" "$VERSION"
fi
echo ""

# Step 3: Commit version bump
echo -e "${CYAN}[3/7]${NC} Committing version bump..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would run: git add -A && git commit -m '🔖 Bump version to $VERSION'"
else
    git add -A
    git commit -m "🔖 Bump version to $VERSION" || echo "  (nothing to commit)"
fi
echo ""

# Step 4: Build installer
echo -e "${CYAN}[4/7]${NC} Building installer..."

if [ "$SKIP_BUILD" -eq 1 ]; then
    echo -e "${YELLOW}  Skipping build (--skip-build)${NC}"
    if [ ! -f "$ROOT_DIR/packaging/macos/Talkie-for-Mac.dmg" ]; then
        echo -e "${RED}❌ No existing DMG found at packaging/macos/Talkie-for-Mac.dmg${NC}"
        exit 1
    fi
elif [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would run: ./packaging/macos/build.sh --version $VERSION unified"
else
    announce "Building and signing"
    "$ROOT_DIR/packaging/macos/build.sh" --version "$VERSION" unified
    announce "Build complete, notarized"
fi
echo ""

# Step 5: Tag release
echo -e "${CYAN}[5/7]${NC} Tagging v$VERSION..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would run: git tag v$VERSION"
else
    if git rev-parse "v$VERSION" >/dev/null 2>&1; then
        echo -e "${YELLOW}  Tag v$VERSION already exists, skipping${NC}"
    else
        git tag "v$VERSION"
        echo -e "${GREEN}✓${NC} Tagged v$VERSION"
    fi
fi
echo ""

# Step 6: Push to origin
echo -e "${CYAN}[6/7]${NC} Pushing to origin..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would run: git push origin master"
    echo "  Would run: git push origin v$VERSION"
else
    git push origin master
    git push origin "v$VERSION"
    echo -e "${GREEN}✓${NC} Pushed commits and tag"
fi
echo ""

# Step 7: Create GitHub release on usetalkie.com
echo -e "${CYAN}[7/7]${NC} Creating GitHub release on usetalkie.com..."

DMG_PATH="$ROOT_DIR/packaging/macos/Talkie-for-Mac.dmg"
RELEASE_DMG="/tmp/Talkie.dmg"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would copy: $DMG_PATH → $RELEASE_DMG"
    echo "  Would run: gh release create v$VERSION $RELEASE_DMG --repo arach/usetalkie.com"
else
    cp "$DMG_PATH" "$RELEASE_DMG"

    cd "$USETALKIE_DIR"
    gh release create "v$VERSION" "$RELEASE_DMG" \
        --title "Talkie $VERSION" \
        --notes "Release $VERSION

Download and install Talkie for Mac."

    cd "$ROOT_DIR"
    echo -e "${GREEN}✓${NC} Release published"
    announce "Release published to GitHub"
fi
echo ""

# Done!
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              RELEASE COMPLETE! 🎉                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Version:  $VERSION"
echo "  Tag:      v$VERSION"
echo "  Download: https://github.com/arach/usetalkie.com/releases/latest/download/Talkie.dmg"
echo ""

announce "Talkie $VERSION shipped successfully"
