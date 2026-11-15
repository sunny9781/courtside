#!/bin/bash
# Builds CourtsideTV, signs it with the free "Personal Team" in Xcode, and installs it on the Apple TV.
# Optional: TEAM_ID (otherwise found automatically), TV_DEVICE (name or id; otherwise the first Apple TV).
set -euo pipefail
trap 'echo "::error::Stopped at line $LINENO"; [ -f tv-build.log ] && tail -40 tv-build.log' ERR

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
  echo "::error::No paired Apple TV found. Pair it in Xcode › Window › Devices and Simulators, and make sure it's on and on the same Wi-Fi."
  exit 1
fi
read -r DEVICE UDID <<< "$DEVICE"
echo "Apple TV: $DEVICE (UDID $UDID)"
# Building for this exact Apple TV is what registers it with the free team the first time.
if [ -n "$UDID" ]; then DEST="platform=tvOS,id=$UDID"; else DEST="generic/platform=tvOS"; fi

# 3. Skip the work when nothing changed and the signature has more than 3 days left.
APP="build-tv/Build/Products/Release-appletvos/CourtsideTV.app"
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
if [ -f build-tv/.installed ] && [ "$(cat build-tv/.installed)" = "$COMMIT" ] && [ "$DAYS" -gt 3 ]; then
  echo "Already up to date on the Apple TV. Its signature is good for $DAYS more days."
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
if [ -f build-tv/.location ] && [ "$(cat build-tv/.location)" != "$PWD" ]; then
  echo "This folder moved, so clearing the old build cache (the next build re-downloads the video player library)…"
  rm -rf build-tv
elif [ -d build-tv ] && [ ! -f build-tv/.location ]; then
  echo "Starting the build cache fresh (one time; re-downloads the video player library)…"
  rm -rf build-tv
fi

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

echo "$PWD" > build-tv/.location
test -d "$APP"

# 5. Install over Wi-Fi.
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "$COMMIT" > build-tv/.installed
echo "Installed Courtside 1.0.$BUILD on the Apple TV (signature good for $(days_left) days)."
