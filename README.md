# Courtside

A sports-first IPTV app for Xtream Codes logins. The Mac app comes first, then Apple TV and Android TV.

## How changes ship
- Every push to `main` builds the Mac app on Sunny's Mac (a GitHub self-hosted runner) using `.github/workflows/mac.yml`.
- `scripts/publish-mac.sh` publishes the build to [courtside-releases](https://github.com/sunny9781/courtside-releases):
  - a `mac-<build>` release with `Courtside.zip`
  - an updated `mac/latest.json`
- Installed apps check `mac/latest.json` on launch and every 4 hours, download the new zip, and show **Restart to update** (see `Courtside/AppUpdater.swift`).
- Copies built in Xcode have build number 1 and never update themselves.

## One-time setup
- **Self-hosted runner:** Settings › Actions › Runners, on the Mac, installed as a service.
- **Secret `RELEASES_TOKEN`:** a fine-grained token with Contents read and write on `courtside-releases`.

No logins, server addresses or logos are stored in this repo or in the app.
