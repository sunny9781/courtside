#!/bin/bash
# Double-click to put the latest Courtside on the Apple TV (run at least weekly).
cd "$(dirname "$0")/.." || exit 1
if git fetch -q origin main && git checkout -q FETCH_HEAD && scripts/tv-update.sh; then
  echo
  echo "Done. This window closes in 3 seconds."
  sleep 3
  (sleep 0.5; osascript -e 'tell application "Terminal" to close (every window whose name contains "Update Apple TV")' >/dev/null 2>&1) &
  disown
  exit 0
fi
echo
read -n 1 -s -r -p "Something went wrong (see above). Press any key to close."
