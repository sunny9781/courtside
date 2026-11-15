#!/bin/bash
# Double-click to put the latest Courtside on the Apple TV and the iPhone (run at least weekly; free signing lasts 7 days).
# Apple TV on, same Wi-Fi. iPhone unlocked, same Wi-Fi or plugged in, Developer Mode on.
# If one of them can't be reached, the other still gets updated.
cd "$(dirname "$0")/.." || exit 1
git fetch -q origin main && git checkout -q FETCH_HEAD || { read -n 1 -s -r -p "Couldn't get the latest version. Press any key to close."; exit 1; }
export BUILD_NUMBER=$(date +%y%m%d%H%M)

echo "=== Apple TV ==="
if scripts/device-install.sh tv; then tv="updated"; else tv="FAILED"; fi
echo
echo "=== iPhone ==="
if scripts/device-install.sh ios; then ios="updated"; else ios="FAILED"; fi

echo
echo "Apple TV: $tv"
echo "iPhone:   $ios"
if [ "$tv" = updated ] && [ "$ios" = updated ]; then
  echo "Done. This window closes in 3 seconds."
  sleep 3
  (sleep 0.5; osascript -e 'tell application "Terminal" to close (every window whose name contains "Update Apple TV and iPhone")' >/dev/null 2>&1) &
  disown
  exit 0
fi
echo
read -n 1 -s -r -p "Something went wrong (see above). Press any key to close."
