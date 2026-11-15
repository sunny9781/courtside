# Courtside

A sports-first IPTV app for Xtream Codes logins. The Mac app comes first, then Apple TV and Android TV.

## How changes ship
- **Mac:** every push to `main` builds the Mac app on GitHub's Macs (`.github/workflows/mac.yml`) and publishes it to [courtside-releases](https://github.com/sunny9781/courtside-releases). Installed apps update themselves (see `Courtside/AppUpdater.swift`).
- **Apple TV:** run `~/courtside-tv/scripts/tv-update.sh` on the Mac to install the latest version. Run it at least weekly, because free signing lasts 7 days.
- **Checking the code compiles:** start the **Check** workflow by hand from the Actions tab.
- **Screenshots:** `scripts/tv-screens.sh` takes Apple TV screenshots with sample data, using the simulator on the Mac.

No logins, server addresses or logos are stored in this repo or in the app.
