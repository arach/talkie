#!/usr/bin/env bash
set -euo pipefail

scope="${1:-all}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
derived_root="${RUNNER_TEMP:-/tmp}/talkie-apple-build-smoke-derived-data"

cd "$repo_root"

case "$scope" in
  all|macos|ios) ;;
  *)
    echo "Usage: $0 [all|macos|ios]" >&2
    exit 64
    ;;
esac

xcode_common=(
  -skipPackagePluginValidation
  -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
)

run_group() {
  local title="$1"
  shift

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::group::$title"
  else
    printf '\n==> %s\n' "$title"
  fi

  "$@"

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::endgroup::"
  fi
}

build_macos_project() {
  local label="$1"
  local project="$2"
  local scheme="$3"

  run_group "Build $label" \
    xcodebuild \
      -project "$project" \
      -scheme "$scheme" \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "$derived_root/$label" \
      "${xcode_common[@]}" \
      build
}

build_ios_project() {
  run_group "Build iOS app for simulator" \
    xcodebuild \
      -project apps/ios/Talkie-iOS.xcodeproj \
      -scheme Talkie \
      -configuration Debug \
      -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$derived_root/ios" \
      "${xcode_common[@]}" \
      build
}

build_watch_project() {
  run_group "Build watchOS app for simulator" \
    xcodebuild \
      -project apps/ios/TalkieWatch/TalkieWatch.xcodeproj \
      -scheme TalkieWatch \
      -configuration Debug \
      -sdk watchsimulator \
      -destination 'generic/platform=watchOS Simulator' \
      -derivedDataPath "$derived_root/watchos" \
      "${xcode_common[@]}" \
      build
}

if [[ "$scope" == "all" || "$scope" == "macos" ]]; then
  build_macos_project "Talkie" "apps/macos/Talkie/Talkie.xcodeproj" "Talkie"
  build_macos_project "TalkieAgent" "apps/macos/TalkieAgent/TalkieAgent.xcodeproj" "TalkieAgent"
  build_macos_project "TalkieSync" "apps/macos/TalkieSync/TalkieSync.xcodeproj" "TalkieSync"
  build_macos_project "TalkieHeadless" "apps/macos/TalkieHeadless/TalkieHeadless.xcodeproj" "TalkieHeadless"
  build_macos_project "TalkieMic" "apps/macos/TalkieMic/TalkieMic.xcodeproj" "TalkieMic"
fi

if [[ "$scope" == "all" || "$scope" == "ios" ]]; then
  build_ios_project
  build_watch_project
fi
