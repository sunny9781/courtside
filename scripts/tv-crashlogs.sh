#!/bin/bash
# Copies the Apple TV's crash reports for Courtside into ./crashlogs so they can be read.
set -e
cd "$(dirname "$0")/.."
DEVICES=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICES" >/dev/null 2>&1 || true
DEVICE=$(/usr/bin/python3 - "$DEVICES" <<'PY'
import json, sys
try: data = json.load(open(sys.argv[1]))
except Exception: data = {}
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    if hw.get("platform", "").lower() == "tvos" and hw.get("reality", "physical") == "physical":
        print(d.get("identifier", "")); break
PY
)
[ -n "$DEVICE" ] || { echo "No Apple TV found. Make sure it's on."; exit 1; }
rm -rf crashlogs/all && mkdir -p crashlogs/all
xcrun devicectl device copy from --device "$DEVICE" --domain-type systemCrashLogs --source / --destination crashlogs/all >/dev/null
find crashlogs/all -iname "*Courtside*" -newermt "-2 days" -exec cp {} crashlogs/ \; 2>/dev/null || true
rm -rf crashlogs/all
COUNT=$(ls crashlogs | grep -ci courtside || true)
echo "Saved $COUNT Courtside crash report(s) to $(pwd)/crashlogs"
