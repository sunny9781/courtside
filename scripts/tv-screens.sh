#!/bin/bash
set -euo pipefail
mkdir -p shots
BUNDLE_ID="ca.sunny9781.courtside.tv"

# The Apple TV simulator (downloads it once if Xcode doesn't have it yet; a few GB).
runtime() {
  xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "tvOS" and r.get("isAvailable")]
print(rs[-1]["identifier"] if rs else "")'
}
RUNTIME=$(runtime)
if [ -z "$RUNTIME" ]; then
  echo "Downloading the Apple TV simulator…"
  xcodebuild -downloadPlatform tvOS
  RUNTIME=$(runtime)
fi
TYPE=$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json, sys
tv = [t for t in json.load(sys.stdin)["devicetypes"] if "Apple TV" in t["name"]]
ts = [t for t in tv if "1080p" in t["name"]] or tv
print(ts[0]["identifier"] if ts else "")')
SIM=$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for rt, ds in json.load(sys.stdin)["devices"].items():
    for d in ds:
        if d["name"] == "Courtside TV" and d.get("isAvailable"):
            print(d["udid"]); raise SystemExit' || true)
if [ -z "$SIM" ]; then echo "Creating simulator ($TYPE)"; xcrun simctl list devicetypes | grep -i "apple tv" || true; SIM=$(xcrun simctl create "Courtside TV" "$TYPE" "$RUNTIME"); fi
echo "Simulator: $SIM ($RUNTIME, $TYPE)"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null

xcodebuild -project Courtside.xcodeproj -scheme CourtsideTV -configuration Debug \
  -destination "id=$SIM" -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO build > shots/build.log 2>&1 \
  || { grep -E "error:" shots/build.log | sort -u | head -40; exit 1; }
xcrun simctl install "$SIM" build-sim/Build/Products/Debug-appletvsimulator/CourtsideTV.app

for screen in home sport game epg settings; do
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$BUNDLE_ID" -demo -screen "$screen" >/dev/null
  sleep 7
  xcrun simctl io "$SIM" screenshot "shots/$screen.png" >/dev/null
  echo "Saved $screen"
done
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl shutdown "$SIM" 2>/dev/null || true
