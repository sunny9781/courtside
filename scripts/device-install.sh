#!/bin/bash
# Builds Courtside for the Apple TV or iPhone/iPad, signs it with the free "Personal Team" in Xcode, and installs it.
#   scripts/device-install.sh tv     (Apple TV)
#   scripts/device-install.sh ios    (iPhone or iPad)
# Optional: TEAM_ID (otherwise found automatically), DEVICE_NAME (otherwise the first device of that kind).
set -euo pipefail
trap 'echo "::error::Stopped at line $LINENO"; [ -f "$LOG" ] && tail -40 "$LOG"' ERR

KIND="${1:-tv}"
if [ "$KIND" = "ios" ]; then
  BUNDLE_ID="ca.sunny9781.courtside.ios"; SCHEME="CourtsideiOS"; PLATFORM="ios"; SDKDIR="Release-iphoneos"
  BUILD_DIR="build-ios"; NICE="iPhone"
else
  BUNDLE_ID="ca.sunny9781.courtside.tv"; SCHEME="CourtsideTV"; PLATFORM="tvos"; SDKDIR="Release-appletvos"
  BUILD_DIR="build-tv"; NICE="Apple TV"
fi
LOG="$BUILD_DIR.log"

# 1. Which team signs it: the free Personal Team of the Apple ID added in Xcode › Settings › Accounts.
if [ -z "${TEAM_ID:-}" ]; then
  TEAM_ID=$(defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
teams = []
for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
    for v in (d.get(key) or {}).values():
        teams += v if isinstance(v, list) else []
free = [t for t in teams if t.get("isFreeProvisioningTeam")]
pick = (free or teams or [{}])[0]
print(pick.get("teamID", ""))
' || true)
fi
if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM_ID" ]; then
  echo "::error::No Apple account found. In Xcode, open Settings › Accounts and add your Apple ID."
  exit 1
fi
echo "Signing team: $TEAM_ID"

# 2. Which device.
DEVICES=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICES" >/dev/null 2>&1 || true
DEVICE=$(/usr/bin/python3 - "$DEVICES" "${DEVICE_NAME:-${TV_DEVICE:-}}" "$PLATFORM" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = {}
wanted = sys.argv[2].lower()
platform = sys.argv[3].lower()
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    props = d.get("deviceProperties", {})
    if hw.get("platform", "").lower() != platform:
        continue
    if hw.get("reality", "physical") != "physical":   # skip the simulator used for screenshots
        continue
    name = props.get("name", "")
    ident = d.get("identifier", "")
    if not wanted or wanted in (name.lower(), ident.lower(), hw.get("udid", "").lower()):
        print(ident, hw.get("udid", ""))
        break
PY
)
if [ -z "$DEVICE" ]; then
  echo "::error::No paired $NICE found. Pair it in Xcode (Shift-Command-2), and make sure it's on, unlocked and on the same Wi-Fi."
  exit 1
fi
read -r DEVICE UDID <<< "$DEVICE"
echo "$NICE: $DEVICE (UDID $UDID)"
# Building for this exact Apple TV is what registers it with the free team the first time.
if [ "$KIND" = "ios" ]; then OSNAME="iOS"; else OSNAME="tvOS"; fi
if [ -n "$UDID" ]; then DEST="platform=$OSNAME,id=$UDID"; else DEST="generic/platform=$OSNAME"; fi

# 3. Skip the work when nothing changed and the signature has more than 3 days left.
APP="$BUILD_DIR/Build/Products/$SDKDIR/$SCHEME.app"
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
days_left() {
  [ -f "$APP/embedded.mobileprovision" ] || { echo 0; return; }
  security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | /usr/bin/python3 -c '
import plistlib, sys, datetime
p = plistlib.loads(sys.stdin.buffer.read())
left = p["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) - datetime.datetime.now(datetime.timezone.utc)
print(max(int(left.total_seconds() // 86400), 0))' 2>/dev/null || echo 0
}
DAYS=$(days_left)
if [ -f $BUILD_DIR/.installed ] && [ "$(cat $BUILD_DIR/.installed)" = "$COMMIT" ] && [ "$DAYS" -gt 3 ]; then
  echo "Already up to date on the $NICE. Its signature is good for $DAYS more days."
  exit 0
fi

# Renew the 7-day signature only when it's close to running out (asking Apple adds a few seconds).
if [ "$DAYS" -le 3 ]; then
  echo "Renewing the signature…"
  for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    grep -l "$BUNDLE_ID" "$dir"/*.mobileprovision 2>/dev/null | while read -r f; do rm -f "$f"; done || true
  done
fi

# The build cache remembers where this folder was; if it has moved, start the cache fresh.
if [ -f $BUILD_DIR/.location ] && [ "$(cat $BUILD_DIR/.location)" != "$PWD" ]; then
  echo "This folder moved, so clearing the old build cache (the next build re-downloads the video player library)…"
  rm -rf "$BUILD_DIR"
elif [ -d "$BUILD_DIR" ] && [ ! -f $BUILD_DIR/.location ]; then
  echo "Starting the build cache fresh (one time; re-downloads the video player library)…"
  rm -rf "$BUILD_DIR"
fi

# 4. Build and sign.
# Build number: minutes since 2026 began. It must stay a small number: Google's Cast toolkit reads the app's version
# as a 32-bit number and crashes the app on a bigger one (like the old date-and-time build numbers).
BUILD=$(( ($(date +%s) - 1767225600) / 60 ))
# The version is the newest one in What's new (Shared/Changelog.swift), so they always match, written as
# major.minor.patch (1.37.0), the form the Cast toolkit expects.
VERSION=$(grep -o 'Release(version: "[0-9.]*"' Shared/Changelog.swift | head -1 | grep -o '[0-9][0-9.]*' || true)
VERSION=${VERSION:-1.0}
[ "$(echo "$VERSION" | tr -cd . | wc -c)" -lt 2 ] && VERSION="$VERSION.0"
set -o pipefail
xcodebuild \
  -project Courtside.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEST" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD" \
  MARKETING_VERSION="$VERSION" \
  build > "$LOG" 2>&1 || { grep -E "error:" "$LOG" | sort -u | head -40; tail -30 "$LOG"; exit 1; }

echo "$PWD" > $BUILD_DIR/.location
test -d "$APP"

# 5. Install over Wi-Fi.
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "$COMMIT" > $BUILD_DIR/.installed
echo "Installed Courtside $VERSION ($BUILD) on the $NICE (signature good for $(days_left) days)."
