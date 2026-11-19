#!/bin/bash
# Double-click to put the latest Courtside on the Apple TV only (run at least weekly; free signing lasts 7 days).
# Apple TV on, same Wi-Fi.
cd "$(dirname "$0")/.." || exit 1
git fetch -q origin main && git checkout -q FETCH_HEAD || { read -n 1 -s -r -p "Couldn't get the latest version. Press any key to close."; exit 1; }
export BUILD_NUMBER=$(date +%y%m%d%H%M)

echo "=== Apple TV ==="
if scripts/device-install.sh tv; then
  echo
  echo "Apple TV: updated. This window closes in 3 seconds."
  sleep 3
  (sleep 0.5; osascript -e 'tell application "Terminal" to close (every window whose name contains "Update Apple TV.command")' >/dev/null 2>&1) &
  disown
  exit 0
fi
echo
read -n 1 -s -r -p "Apple TV: FAILED (see above). Press any key to close."
