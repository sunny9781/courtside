#!/bin/bash
# Run on your Mac to put the latest Courtside on your iPhone (and to renew it; free signing lasts 7 days).
# The iPhone needs to be unlocked, on the same Wi-Fi (or plugged in), with Developer Mode on.
set -e
cd "$(dirname "$0")/.."
echo "Getting the latest version…"
git fetch -q origin main
git checkout -q FETCH_HEAD
BUILD_NUMBER=$(date +%y%m%d%H%M) exec scripts/device-install.sh ios
