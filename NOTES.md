# Courtside: project notes

Read this at the start of a session. Keep it short and current.

## What it is
Sports IPTV app for Xtream Codes providers. Repo `sunny9781/courtside` (public).
- **Apple** (Swift/SwiftUI): `Courtside/` (Mac), `CourtsideTV/` (Apple TV), `CourtsideiOS/` (iPhone/iPad), shared code in `Shared/`.
- **Android TV / Google TV** (Kotlin, Compose for TV, Media3): `android/app/src/main/java/ca/sunny9781/courtside/`.
  Runs on Android 7.1+ (minSdk 25) so older Fire TV Sticks (Fire OS 6) work; keep API 26+ calls behind SDK_INT checks.
- Scores from ESPN's public scoreboard; streams matched to games from channel names and the guide (`Matcher`).

## Rules
- Never log or share stream URLs (they contain the Xtream login). The user enters the login in the app only.
- Secrets live only in GitHub secrets (RELEASES_TOKEN, ANDROID_KEYSTORE, ANDROID_KEYSTORE_PASSWORD). Never commit a keystore.
- Commit messages end with the Co-Authored-By / Claude-Session lines.

## Release flow
1. Branch from main, change code, add an entry at the top of `Shared/Changelog.swift`:
   next version, Eastern date/time, title, each change tagged with apps (`mac`, `tv`, `ios`, `android`, or inline
   `[.tv, .android]`). Optional `titleApps:` after `changes: [...]` says which apps see the title (otherwise the title
   shows only where every change applies). `android/changelog.py` turns the Android entries into the app's What's new.
2. Apple build check: `gh workflow run check.yml -R sunny9781/courtside --ref <branch>` (macOS runner; sometimes
   queues ~15 min and gets cancelled: just re-run).
3. Android build without publishing: `gh workflow run android.yml -R sunny9781/courtside --ref <branch> -f publish=false`.
4. Merge to main with `--no-ff` and push. Each app publishes from its own workflow; the Mac one skips pushes that only
   touch android/**, Apple TV files and the changelog. Main publishes the Mac app (latest.json) and the Android APK
   (release "android", Courtside.apk + android.json). Apple TV and iPhone: the user runs the
   "Update Apple TV and iPhone" shortcut.

## Layout (Android TV and Apple TV match)
- Top bar: connections pill, EPG refresh, version/update button (one press checks and installs).
- Player in the bottom-left corner; left panels (sports, EPG categories, game stream categories, settings sections)
  sit on top of it; a one-line now-playing bar runs along the very bottom; pages on the right scroll under the bar.
- Home: sports sidebar (groups: live scores / channel sports / nothing today) + EPG-style list of games (one line per
  game; upcoming grey). Channel-only sports (pickleball) show channels grouped by category.
- Game screen: mini EPG, categories left ("All" first, with group headings), streams right; first non-4K stream autoplays.
- EPG (Apple TV, 1.81): timeline guide (option C mock-up): 2.5 h from the last half hour, cells coloured by sport
  (`TVGuide.sport` guesses from title, then channel name), orange now line, past part darker; the focused row opens to
  two lines (times, time left, title; tags under the channel). Android still uses the columns below; port once settled.
- EPG: no what's-playing panel (the bottom bar shows it); Done/Enter in Filter jumps to the first result.
- Settings sections (both TVs): Account, General, Hidden, Changelog.
- Corner player to full screen: click it; Android also hold Back, Apple TV hold Play/Pause (tvOS keeps hold-Back).
- Apple TV shell ignores all safe areas (own 20pt margin); the now-playing bar sits on the screen's bottom edge.
- EPG: favourites (hold select / heart) listed first; Hide via hold; Settings › Hidden lists hidden sports, leagues,
  categories, channels. Hidden sports/leagues are switched off (not fetched, not matched).
- Android Lite mode (default on except Nvidia Shield): no corner player (channels open full screen, Back stops),
  no live scores (games load once at open), no logos, no zoom.
- Apple TV playback (1.83): VLCKit 3.6 for everything except 4K channels, which play on `CourtsideTV/HDREngine.swift`
  (KSPlayer 5.6.2 GPL build: a binary xcframework with a tvOS slice, + FFmpegKit 9; linked only into CourtsideTV, so
  `#if os(tvOS) && canImport(KSPlayer)`). It reads the same TS URL as VLC (one connection), passes the video's
  frame rate + format to `displayCriteria` (applied only in full screen by TVPlayerView; KSPlayer's own TV switch is
  overridden) and shows HDR10/HLG/Dolby Vision tags. No picture in 6 s or an error: the 4K player is closed, 1 s gap,
  then the same URL on VLC (that URL skips the 4K player for the rest of the session). KSPlayer logging is silenced
  (URLs). Setting: Playback › HDR player for 4K (`hdrPlayer4K`, default on). The old AVPlayer/HLS path (1.80) is gone.
  Licence: KSPlayer is GPL-3.0 (fine while the repo is public and the app isn't sold); LGPL is a paid version.
- Android streams open TS first (HLS fallback): HLS made the provider count extra connections while flipping.
- Android full screen always uses SurfaceView (no HDR switch; the TV's Match content setting decides HDR). The video
  renderer forces a fresh decoder on every surface change (handover garbled 4K on Chromecast).

## Working preferences (Sunny)
- Report how long each request took.
- Always tell Sunny when a release is actually published (after the main runs finish), not just merged.
- To save credits: build and settle features on Android first, then port to Apple TV/Mac/iPhone in one batch.
  Batch requests into one release. Use quick mock-ups before coding big layout changes. Start fresh sessions
  instead of one very long one.

## Open items
- 1.83 Apple TV HDR player: unconfirmed on the TV (HDR badge in full screen, 1/2 connections, 4K ↔ normal switching,
  sound/fps tags from KSPlayer's track info).
- 1.81 Apple TV timeline EPG: merged without the check.yml build (gh had no login in that session); unconfirmed on the TV.
- iPhone Home "Live Now" blue bar: unexplained; ask for a screenshot if it's still there.
- Chromecast crashes: Android now saves crash details (shown once on next start, and in Settings › General).
- Apple TV hasn't got a Lite mode (not needed so far).
