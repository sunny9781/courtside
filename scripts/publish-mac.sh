#!/bin/bash
# Publishes a Mac build as a release "mac-<build>" on sunny9781/courtside, with two files attached:
#   Courtside.zip  the app
#   latest.json    what the installed apps check for updates (they read the newest release's copy)
# Needs GH_TOKEN (the workflow's own token, allowed to write releases), BUILD and VERSION.
#
# Copies installed before the move check sunny9781/courtside-releases instead. While LEGACY_TOKEN is set (the
# old RELEASES_TOKEN secret), that repo's mac/latest.json is pointed at the new release too, so those copies
# update once more and from then on check here. Once courtside-releases is deleted this step just skips.
set -euo pipefail

ZIP="$1"
REPO="sunny9781/courtside"
API="https://api.github.com/repos/$REPO"
TAG="mac-$BUILD"
AUTH=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")
NOTES="${NOTES:-}"
NOTES="$(printf '%s' "$NOTES" | head -n 1)"

json() { /usr/bin/python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }
field() { /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or '')" "$1"; }

echo "Creating release $TAG"
RELEASE=$(curl -fsS "${AUTH[@]}" -X POST "$API/releases" \
  -d "{\"tag_name\":\"$TAG\",\"target_commitish\":\"${GITHUB_SHA:-main}\",\"name\":\"Mac $VERSION (build $BUILD)\",\"body\":$(json "$NOTES"),\"make_latest\":\"true\"}")
RELEASE_ID=$(printf '%s' "$RELEASE" | field id)

echo "Uploading Courtside.zip"
ASSET=$(curl -fsS "${AUTH[@]}" -H "Content-Type: application/zip" \
  --data-binary @"$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=Courtside.zip")
URL=$(printf '%s' "$ASSET" | field browser_download_url)

echo "Uploading latest.json"
printf '{\n  "build": %s,\n  "version": "%s",\n  "url": "%s",\n  "notes": %s\n}\n' \
  "$BUILD" "$VERSION" "$URL" "$(json "$NOTES")" > latest.json
curl -fsS "${AUTH[@]}" -H "Content-Type: application/json" \
  --data-binary @latest.json \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=latest.json" > /dev/null

echo "Published $VERSION (build $BUILD): $URL"

# Copies installed before the move: point the old feed at this release.
if [ -n "${LEGACY_TOKEN:-}" ]; then
  OLD="https://api.github.com/repos/sunny9781/courtside-releases/contents/mac/latest.json"
  OLDAUTH=(-H "Authorization: Bearer $LEGACY_TOKEN" -H "Accept: application/vnd.github+json")
  if SHA=$(curl -fsS "${OLDAUTH[@]}" "$OLD" | field sha); then
    CONTENT=$(base64 < latest.json | tr -d '\n')
    BODY="{\"message\":\"Mac $VERSION (now published on sunny9781/courtside)\",\"content\":\"$CONTENT\""
    [ -n "$SHA" ] && BODY="$BODY,\"sha\":\"$SHA\""
    BODY="$BODY}"
    if curl -fsS "${OLDAUTH[@]}" -X PUT "$OLD" -d "$BODY" > /dev/null; then
      echo "Old feed (courtside-releases) points here too"
    else
      echo "Couldn't update the old feed (skipped)"
    fi
  else
    echo "Old feed not reachable (courtside-releases deleted?), skipped"
  fi
fi
