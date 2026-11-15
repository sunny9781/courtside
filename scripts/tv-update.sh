#!/bin/bash
# Run this on your Mac to put the latest Courtside on the Apple TV (and to renew it; free signing lasts 7 days).
#   ~/courtside-tv/scripts/tv-update.sh
# The Apple TV needs to be on and on the same Wi-Fi. Takes a few minutes.
set -e
cd "$(dirname "$0")/.."
echo "Getting the latest version…"
git fetch -q origin main
git checkout -q FETCH_HEAD
BUILD_NUMBER=$(date +%y%m%d%H%M) exec scripts/tv-install.sh
