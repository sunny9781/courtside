#!/bin/bash
# Publishes a Mac build to sunny9781/courtside-releases:
#   1. a GitHub release "mac-<build>" with Courtside.zip attached
#   2. mac/latest.json, which the installed apps check for updates
# Needs GH_TOKEN (a token that can write to courtside-releases), BUILD and VERSION.
set -euo pipefail

ZIP="$1"
REPO="sunny9781/courtside-releases"
API="https://api.github.com/repos/$REPO"
TAG="mac-$BUILD"
AUTH=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")
NOTES="${NOTES:-}"
NOTES="$(printf '%s' "$NOTES" | head -n 1)"

json() { /usr/bin/python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }
field() { /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or '')" "$1"; }

echo "Creating release $TAG"
RELEASE=$(curl -fsS "${AUTH[@]}" -X POST "$API/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"Mac $VERSION\",\"body\":$(json "$NOTES"),\"make_latest\":\"true\"}")
RELEASE_ID=$(printf '%s' "$RELEASE" | field id)

echo "Uploading Courtside.zip"
ASSET=$(curl -fsS "${AUTH[@]}" -H "Content-Type: application/zip" \
  --data-binary @"$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=Courtside.zip")
URL=$(printf '%s' "$ASSET" | field browser_download_url)

echo "Updating mac/latest.json"
LATEST=$(printf '{\n  "build": %s,\n  "version": "%s",\n  "url": "%s",\n  "notes": %s\n}\n' \
  "$BUILD" "$VERSION" "$URL" "$(json "$NOTES")")
CONTENT=$(printf '%s' "$LATEST" | base64 | tr -d '\n')
SHA=$(curl -fsS "${AUTH[@]}" "$API/contents/mac/latest.json" 2>/dev/null | field sha || true)
BODY="{\"message\":\"Mac $VERSION\",\"content\":\"$CONTENT\""
[ -n "$SHA" ] && BODY="$BODY,\"sha\":\"$SHA\""
BODY="$BODY}"
curl -fsS "${AUTH[@]}" -X PUT "$API/contents/mac/latest.json" -d "$BODY" > /dev/null

echo "Published $VERSION: $URL"
