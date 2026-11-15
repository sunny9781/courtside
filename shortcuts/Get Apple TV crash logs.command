#!/bin/bash
# Double-click after Courtside crashes on the Apple TV: saves its crash reports to courtside-tv/crashlogs.
cd "$(dirname "$0")/.." || exit 1
git fetch -q origin main && git checkout -q FETCH_HEAD && scripts/tv-crashlogs.sh
echo
read -n 1 -s -r -p "Press any key to close."
