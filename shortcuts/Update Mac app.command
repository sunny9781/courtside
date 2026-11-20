#!/bin/bash
# Double-click to build the latest Courtside here on this Mac and install it (no GitHub build needed).
# The first run takes longer (it builds everything once); after that only what changed is rebuilt.
cd "$(dirname "$0")/.." || exit 1
# -f: this file may already be here untracked the first time; take main's copy.
git fetch -q origin main && git checkout -q -f FETCH_HEAD || { read -n 1 -s -r -p "Couldn't get the latest version. Press any key to close."; exit 1; }

echo "=== Mac app ==="
if scripts/mac-install.sh; then
  echo
  read -n 1 -s -r -p "Mac app: updated. Press any key to close."
  exit 0
fi
echo
read -n 1 -s -r -p "Mac app: FAILED (see above). Press any key to close."
