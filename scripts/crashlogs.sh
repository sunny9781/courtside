#!/bin/bash
# Copies Courtside's crash reports from the Apple TV (tv) or the iPhone (ios) into ./crashlogs so they can be read.
set -e
cd "$(dirname "$0")/.."
WANT=${1:-tv}
DEVICES=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICES" >/dev/null 2>&1 || true
DEVICE=$(/usr/bin/python3 - "$DEVICES" "$WANT" <<'PY'
import json, sys
try: data = json.load(open(sys.argv[1]))
except Exception: data = {}
want = "tvos" if sys.argv[2] == "tv" else "ios"
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    if hw.get("platform", "").lower() == want and hw.get("reality", "physical") == "physical":
        print(d.get("identifier", "")); break
PY
)
NAME=$([ "$WANT" = tv ] && echo "Apple TV" || echo "iPhone")
[ -n "$DEVICE" ] || { echo "No $NAME found. Make sure it's on (and the iPhone is unlocked)."; exit 1; }
rm -rf crashlogs/all && mkdir -p crashlogs/all
xcrun devicectl device copy from --device "$DEVICE" --domain-type systemCrashLogs --source / --destination crashlogs/all >/dev/null
find crashlogs/all -iname "*Courtside*" -newermt "-2 days" -exec cp {} crashlogs/ \; 2>/dev/null || true
rm -rf crashlogs/all
COUNT=$(ls crashlogs | grep -ci courtside || true)
echo "Saved $COUNT Courtside crash report(s) from the $NAME to $(pwd)/crashlogs"
