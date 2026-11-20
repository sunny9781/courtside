#!/bin/bash
# Builds the Mac app here on this Mac and puts it in place of the installed copy, then opens it.
#   scripts/mac-install.sh
# Uses the newest published build number, so the next release made on GitHub still counts as newer and updates it.
# Keeps its build folder (build-mac) between runs, so later builds only recompile what changed.
set -euo pipefail
LOG="build-mac.log"
trap 'echo "Stopped at line $LINENO"; [ -f "$LOG" ] && tail -40 "$LOG"' ERR
START=$SECONDS

VERSION=$(grep -o 'Release(version: "[0-9.]*"' Shared/Changelog.swift | head -1 | grep -o '[0-9][0-9.]*')
TAG=$(curl -fsS https://api.github.com/repos/sunny9781/courtside/releases/latest 2>/dev/null \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)
BUILD=${TAG#mac-}
case "$BUILD" in ''|*[!0-9]*) BUILD=2 ;; esac
echo "Building Courtside $VERSION (build $BUILD) for this Mac…"

# The Swift packages (VLCKit, KSPlayer…) Apple TV builds already downloaded are reused, so they aren't fetched twice.
PACKAGES=()
[ -d build-tv/SourcePackages ] && PACKAGES=(-clonedSourcePackagesDirPath build-tv/SourcePackages)

xcodebuild \
  -project Courtside.xcodeproj \
  -scheme Courtside \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build-mac \
  "${PACKAGES[@]}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  MARKETING_VERSION="$VERSION" \
  build > "$LOG" 2>&1 || { grep -E "error:" "$LOG" | sort -u | head -40; tail -30 "$LOG"; exit 1; }
BUILT=$((SECONDS - START))

NEW="build-mac/Build/Products/Release/Courtside.app"
test -d "$NEW"

# Where it's installed now (wherever you keep it), otherwise Applications.
TARGET=$(mdfind 'kMDItemCFBundleIdentifier == "local.courtside.app"' 2>/dev/null \
  | grep -v -e "/build" -e "/DerivedData/" -e "AppTranslocation" | head -1 || true)
TARGET=${TARGET:-/Applications/Courtside.app}

osascript -e 'tell application id "local.courtside.app" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Courtside || break; sleep 0.5; done
rm -rf "$TARGET"
ditto "$NEW" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
open "$TARGET"

echo
echo "Built in $((BUILT / 60))m $((BUILT % 60))s, installed at $TARGET (total $(((SECONDS - START) / 60))m $(((SECONDS - START) % 60))s)."
