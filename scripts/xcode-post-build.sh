#!/bin/bash
# Xcode Post-Build Script for Talkie (Debug builds only)
#
# Add as a "Run Script" build phase at the END of Talkie target:
#   Script: "${SRCROOT}/../scripts/xcode-post-build.sh"
#
# Tasks:
#   1. Cleanup stale URL scheme registrations
#   2. Kill stale helper processes (TalkieAgent, TalkieEngine from other builds)
#   3. Re-register app with LaunchServices
#   4. Write build manifest (git info, timestamp) for debugging
#   5. Verify code signing

set -e

# Only run for Debug/Dev builds
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Dev" ]]; then
  echo "⏭️  Skipping post-build tasks (not a debug build)"
  exit 0
fi

# Only run for Talkie.app
if [[ "$PRODUCT_NAME" != "Talkie" ]]; then
  exit 0
fi

APP_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "⚠️  App not found: $APP_PATH"
  exit 0
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Talkie Post-Build Tasks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# 1. Cleanup stale URL scheme registrations
# ============================================================
echo ""
echo "1️⃣  Cleaning URL scheme registrations..."

STALE_APPS=$($LSREGISTER -dump 2>/dev/null | grep -B 20 "bindings:.*talkie-dev:" | grep "path:" | sed 's/.*path: *//' | sort -u || true)

CLEANED=0
if [ -n "$STALE_APPS" ]; then
  while IFS= read -r app; do
    # Skip if it's our current build
    if [[ "$app" == "$APP_PATH" ]]; then
      continue
    fi
    # Skip if it's in the same DerivedData folder (sibling apps)
    if [[ "$app" == "${BUILT_PRODUCTS_DIR}/"* ]]; then
      continue
    fi
    # Unregister stale app
    if [ -n "$app" ]; then
      echo "   Unregistering: $app"
      $LSREGISTER -u "$app" 2>/dev/null || true
      CLEANED=$((CLEANED + 1))
    fi
  done <<< "$STALE_APPS"
fi

if [ $CLEANED -eq 0 ]; then
  echo "   ✓ No stale registrations found"
else
  echo "   ✓ Cleaned $CLEANED stale registration(s)"
fi

# ============================================================
# 2. Kill stale helper processes (from OTHER DerivedData folders)
# ============================================================
echo ""
echo "2️⃣  Checking for stale helper processes..."

CURRENT_DERIVED_DATA=$(dirname "$(dirname "$(dirname "$APP_PATH")")")
KILLED=0

for helper in TalkieAgent TalkieEngine; do
  # Find running processes
  pids=$(pgrep -f "$helper.app/Contents/MacOS/$helper" 2>/dev/null || true)

  for pid in $pids; do
    # Get the full path of the running process
    proc_path=$(ps -p "$pid" -o command= 2>/dev/null | awk '{print $1}' || true)

    # Check if it's from a DIFFERENT DerivedData folder
    if [[ -n "$proc_path" && "$proc_path" != *"$CURRENT_DERIVED_DATA"* ]]; then
      echo "   Killing stale $helper (PID $pid)"
      kill "$pid" 2>/dev/null || true
      KILLED=$((KILLED + 1))
    fi
  done
done

if [ $KILLED -eq 0 ]; then
  echo "   ✓ No stale helpers running"
else
  echo "   ✓ Killed $KILLED stale process(es)"
fi

# ============================================================
# 3. Re-register apps with LaunchServices
# ============================================================
echo ""
echo "3️⃣  Registering apps with LaunchServices..."

$LSREGISTER -f "$APP_PATH"
echo "   ✓ Talkie.app"

# Also register helpers if they exist
for helper in TalkieAgent TalkieEngine; do
  HELPER_PATH="${BUILT_PRODUCTS_DIR}/${helper}.app"
  if [ -d "$HELPER_PATH" ]; then
    $LSREGISTER -f "$HELPER_PATH"
    echo "   ✓ ${helper}.app"
  fi
done

# ============================================================
# 4. Write build manifest
# ============================================================
echo ""
echo "4️⃣  Writing build manifest..."

MANIFEST_PATH="$APP_PATH/Contents/Resources/build-manifest.json"

# Get git info
GIT_COMMIT=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "${SRCROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git -C "${SRCROOT}" diff --quiet 2>/dev/null && echo "false" || echo "true")
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_USER=$(whoami)
BUILD_HOST=$(hostname -s)

cat > "$MANIFEST_PATH" << EOF
{
  "buildTime": "$BUILD_TIME",
  "gitCommit": "$GIT_COMMIT",
  "gitBranch": "$GIT_BRANCH",
  "gitDirty": $GIT_DIRTY,
  "configuration": "$CONFIGURATION",
  "buildUser": "$BUILD_USER",
  "buildHost": "$BUILD_HOST",
  "xcodeVersion": "${XCODE_VERSION_ACTUAL:-unknown}",
  "sdkVersion": "${SDK_VERSION:-unknown}",
  "appPath": "$APP_PATH"
}
EOF

echo "   ✓ $MANIFEST_PATH"

# ============================================================
# 5. Verify code signing
# ============================================================
echo ""
echo "5️⃣  Verifying code signature..."

if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
  # Get signing identity
  SIGNING_ID=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=" | head -1 | sed 's/Authority=//' || echo "unknown")
  echo "   ✓ Valid signature: $SIGNING_ID"
else
  echo "   ⚠️  Code signature verification failed (may cause Gatekeeper issues)"
fi

# ============================================================
# 6. Async cleanup tasks (run in background, don't block build)
# ============================================================
echo ""
echo "6️⃣  Spawning async cleanup tasks..."

# Background cleanup script
(
  CLEANUP_LOG="${TMPDIR}/talkie-post-build-cleanup.log"
  exec > "$CLEANUP_LOG" 2>&1

  echo "=== Async Cleanup Started: $(date) ==="

  # --- Clean old DerivedData folders (older than 7 days, not current project) ---
  echo "Checking for stale DerivedData folders..."
  DERIVED_DATA_ROOT=~/Library/Developer/Xcode/DerivedData
  CURRENT_PROJECT_HASH=$(basename "$CURRENT_DERIVED_DATA" | sed 's/Talkie-//')

  find "$DERIVED_DATA_ROOT" -maxdepth 1 -type d -name "Talkie-*" -mtime +7 2>/dev/null | while read dir; do
    DIR_HASH=$(basename "$dir" | sed 's/Talkie-//')
    if [[ "$DIR_HASH" != "$CURRENT_PROJECT_HASH" ]]; then
      SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
      echo "  Removing stale: $dir ($SIZE)"
      rm -rf "$dir"
    fi
  done

  # --- Clean module cache if too large (> 2GB) ---
  echo "Checking module cache size..."
  MODULE_CACHE=~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
  if [ -d "$MODULE_CACHE" ]; then
    CACHE_SIZE=$(du -sm "$MODULE_CACHE" 2>/dev/null | cut -f1)
    if [ "$CACHE_SIZE" -gt 2048 ]; then
      echo "  Module cache is ${CACHE_SIZE}MB, cleaning..."
      rm -rf "$MODULE_CACHE"/*
    fi
  fi

  # --- Clean old build logs (older than 14 days) ---
  echo "Cleaning old build logs..."
  BUILD_LOGS=~/Library/Developer/Xcode/DerivedData/*/Logs/Build
  find $BUILD_LOGS -name "*.xcactivitylog" -mtime +14 -delete 2>/dev/null || true

  # --- Clean old Instruments traces (older than 30 days, > 100MB each) ---
  echo "Checking for old Instruments traces..."
  find ~/Documents -name "*.trace" -mtime +30 -size +100M 2>/dev/null | while read trace; do
    SIZE=$(du -sh "$trace" 2>/dev/null | cut -f1)
    echo "  Would remove old trace: $trace ($SIZE)"
    # Uncomment to actually delete: rm -rf "$trace"
  done

  echo "=== Async Cleanup Done: $(date) ==="
) &

echo "   ✓ Background cleanup started (see ${TMPDIR}/talkie-post-build-cleanup.log)"

# ============================================================
# Done
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Post-build tasks complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
