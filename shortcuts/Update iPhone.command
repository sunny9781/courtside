#!/bin/bash
# Double-click to put the latest Courtside on the iPhone only (run at least weekly; free signing lasts 7 days).
# iPhone unlocked, same Wi-Fi or plugged in, Developer Mode on.
cd "$(dirname "$0")/.." || exit 1
git fetch -q origin main && git checkout -q FETCH_HEAD || { read -n 1 -s -r -p "Couldn't get the latest version. Press any key to close."; exit 1; }
export BUILD_NUMBER=$(date +%y%m%d%H%M)

echo "=== iPhone ==="
if scripts/device-install.sh ios; then
  echo
  echo "iPhone: updated. This window closes in 3 seconds."
  sleep 3
  (sleep 0.5; osascript -e 'tell application "Terminal" to close (every window whose name contains "Update iPhone.command")' >/dev/null 2>&1) &
  disown
  exit 0
fi
echo
read -n 1 -s -r -p "iPhone: FAILED (see above). Press any key to close."
