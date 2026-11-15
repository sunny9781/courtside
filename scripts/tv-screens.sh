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
  xcrun simctl launch --stdout="$PWD/shots/$screen.out.txt" --stderr="$PWD/shots/$screen.out.txt" \
    "$SIM" "$BUNDLE_ID" -demo -screen "$screen" >/dev/null
  sleep 7
  if ! xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "::warning::App not running on $screen screen (crashed?)"
    tail -30 "shots/$screen.out.txt" || true
    CRASH=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/CourtsideTV* 2>/dev/null | head -1 || true)
    if [ -n "$CRASH" ]; then
      cp "$CRASH" "shots/$screen-crash.ips"
      /usr/bin/python3 - "$CRASH" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text[text.index("\n") + 1:])
print("Exception:", body.get("exception"), body.get("termination", {}).get("indicator"))
imgs = body.get("usedImages", [])
for t in body.get("threads", []):
    if t.get("triggered"):
        for f in t.get("frames", [])[:25]:
            img = imgs[f["imageIndex"]].get("name", "?") if f.get("imageIndex", -1) < len(imgs) else "?"
            print(" ", img, f.get("symbol", ""), f.get("sourceFile", ""), f.get("sourceLine", ""))
PY
    fi
  fi
  xcrun simctl io "$SIM" screenshot "shots/$screen.png" >/dev/null
  echo "Saved $screen"
done
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl shutdown "$SIM" 2>/dev/null || true
