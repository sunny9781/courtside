#!/bin/bash
# Builds CourtsideTV, signs it with the free "Personal Team" in Xcode, and installs it on the Apple TV.
# Optional: TEAM_ID (otherwise found automatically), TV_DEVICE (name or id; otherwise the first Apple TV).
set -euo pipefail

BUNDLE_ID="ca.sunny9781.courtside.tv"

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

# 2. Which Apple TV.
DEVICES=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICES" >/dev/null 2>&1 || true
DEVICE=$(/usr/bin/python3 - "$DEVICES" "${TV_DEVICE:-}" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = {}
wanted = sys.argv[2].lower()
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    props = d.get("deviceProperties", {})
    if hw.get("platform", "").lower() != "tvos":
        continue
    name = props.get("name", "")
    ident = d.get("identifier", "")
    if not wanted or wanted in (name.lower(), ident.lower(), hw.get("udid", "").lower()):
        print(ident, hw.get("udid", ""))
        break
PY
)
if [ -z "$DEVICE" ]; then
  echo "::error::No paired Apple TV found. Pair it in Xcode › Window › Devices and Simulators, and make sure it's on and on the same Wi-Fi."
  exit 1
fi
read -r DEVICE UDID <<< "$DEVICE"
echo "Apple TV: $DEVICE (UDID $UDID)"
# Building for this exact Apple TV is what registers it with the free team the first time.
if [ -n "$UDID" ]; then DEST="platform=tvOS,id=$UDID"; else DEST="generic/platform=tvOS"; fi

# 3. Throw away old signing profiles for this app so the build gets a fresh 7-day one.
for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  [ -d "$dir" ] || continue
  grep -l "$BUNDLE_ID" "$dir"/*.mobileprovision 2>/dev/null | while read -r f; do rm -f "$f"; done || true
done

# 4. Build and sign.
BUILD=$((BUILD_NUMBER + 1))
set -o pipefail
xcodebuild \
  -project Courtside.xcodeproj \
  -scheme CourtsideTV \
  -configuration Release \
  -destination "$DEST" \
  -derivedDataPath build-tv \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD" \
  MARKETING_VERSION="1.0.$BUILD" \
  build > tv-build.log 2>&1 || { grep -E "error:" tv-build.log | sort -u | head -40; tail -30 tv-build.log; exit 1; }

APP="build-tv/Build/Products/Release-appletvos/CourtsideTV.app"
test -d "$APP"

# 5. Install over Wi-Fi.
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed Courtside 1.0.$BUILD on the Apple TV."
