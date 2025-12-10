#!/bin/bash
# Talkie Release Script
# Usage: ./release.sh 1.3.0

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.3.0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=================================="
echo "  Talkie Release v$VERSION"
echo "=================================="
echo ""

# Pre-flight checks
echo "Pre-flight checks..."

# Check signing identities
if ! security find-identity -v | grep -q "Developer ID Application"; then
    echo "ERROR: Developer ID Application certificate not found"
    exit 1
fi

if ! security find-identity -v | grep -q "Developer ID Installer"; then
    echo "ERROR: Developer ID Installer certificate not found"
    exit 1
fi

# Check notarization credentials
if ! xcrun notarytool history --keychain-profile "notarytool" >/dev/null 2>&1; then
    echo "ERROR: Notarization credentials not configured"
    echo "Run: xcrun notarytool store-credentials \"notarytool\" --apple-id YOUR_APPLE_ID --team-id 2U83JFPW66"
    exit 1
fi

echo "All checks passed!"
echo ""

# Confirm
read -p "Build and notarize Talkie v$VERSION? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Run the build
echo ""
echo "Starting build..."
cd "$SCRIPT_DIR"
VERSION="$VERSION" ./build.sh

echo ""
echo "=================================="
echo "  Release v$VERSION Complete!"
echo "=================================="
echo ""
echo "Output: $SCRIPT_DIR/Talkie-for-Mac.pkg"
echo ""
echo "Next steps:"
echo "  1. Test the installer locally"
echo "  2. Upload to website/GitHub release"
echo "  3. Update landing page download link"
echo ""
