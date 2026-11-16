#!/bin/bash
# Double-click after Courtside crashes on the iPhone (iPhone unlocked, same Wi-Fi or plugged in):
# saves its crash reports to courtside-tv/crashlogs.
cd "$(dirname "$0")/.." || exit 1
git fetch -q origin main && git checkout -q FETCH_HEAD && scripts/crashlogs.sh ios
echo
read -n 1 -s -r -p "Press any key to close."
