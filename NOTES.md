# Courtside: project notes

Read this at the start of a session. Keep it short and current.

## 2.9 (2026-11-20, broken Mac 2.5)
- Mac 2.5 (mac-115) was published without Contents/MacOS/Courtside: a Changelog.swift typo failed the build, and
  `xcodebuild | tail` hid it (no pipefail), so `test -d` passed on the half-built app → "damaged or incomplete".
  mac.yml now has `set -o pipefail` and checks the program + `codesign --verify --deep`; AppUpdater refuses a
  download without its program or a valid signature. A Changelog-only fix doesn't republish the Mac app (paths-ignore):
  after fixing a broken Mac release, run `gh workflow run mac.yml --ref main`.

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
2. Apple build check: `gh workflow run check.yml -R sunny9781/courtside --ref <branch>` (all apps, ~7 min cold), or
   `-f apps=tv` / `mac` / `ios` when only that app's folder changed (Apple TV alone ~2 min with the package cache).
   Use all when Shared/ changed. Batch mid-work requests into the release in progress: one check per release.
   (gh only works once the repo is attached to the session.) (macOS runner; sometimes
   queues ~15 min and gets cancelled: just re-run).
3. Android build without publishing: `gh workflow run android.yml -R sunny9781/courtside --ref <branch> -f publish=false`.
4. Merge to main with `--no-ff` and push. Each app publishes from its own workflow; the Mac one skips pushes that only
   touch android/**, Apple TV files and the changelog. Main publishes the Mac app (latest.json) and the Android APK
   (release "android", Courtside.apk + android.json). Apple TV and iPhone: the user runs the
   "Update Apple TV and iPhone" shortcut.

## Layout (Android TV and Apple TV match)
- Top bar: connections pill, EPG refresh, version/update button (one press checks and installs). Apple TV only since
  2.4: Android TV has no top bar but a rail down the left edge (`NavRail` in Screens.kt, 56 dp closed / 214 dp open,
  drawn after the video so it covers the corner player when open): Home / EPG / Settings icons, connections + EPG time
  (short) + an update dot at the bottom; open = names, full status, version button. Left off a page's left edge opens
  it, Right goes to `model.leftPanel`, Back from a left panel focuses it ("tabs"). Pages start at the top (Column has
  start padding RAIL_WIDTH). EPG download status also at the right end of the now-playing bar.
- Android Home 2.20: league chips are back (2.7's folding league list was dropped: it felt jumpy), pinned above the
  cards' LazyColumn (outside it, so they never scroll away). Focusing a section's first card row scrolls its heading
  into view (`showHeading`). Rail Right/click emits focusMoves "side" (page focuses its selected left-menu item), with
  `model.leftPanel` as fallback. Left menus and the corner player have no start margin: they line up with the
  now-playing bar's divider. TV updates (2.20): background check only finds (`Updater.availableVersion`, phones still
  auto-download); rail button: Download update vX → Downloading → Install update vX.
- Player in the bottom-left corner; left panels (sports, EPG categories, game stream categories, settings sections)
  sit on top of it; a one-line now-playing bar runs along the very bottom; pages on the right scroll under the bar.
- Home: sports sidebar (groups: live scores / channel sports / nothing today) + score cards (1.95, both TVs; replaced
  the one-line game rows): status + 4K + stream count on top, then each team (logo, name, score). As many per row as
  fit (Apple TV `TVScoreCard.minWidth` 400 pt, Android `CARD_MIN_WIDTH` 200 dp); right on the last card of a row jumps
  to the EPG. Channel-only sports (pickleball) show channels grouped by category (`channelSportGroups` in Shared).
- Game screen: mini EPG, categories left ("All" first, with group headings), streams right; first non-4K stream autoplays.
- EPG (Apple TV, 1.81): timeline guide (option C mock-up): 2.5 h from the last half hour, cells coloured by sport
  (`TVGuide.sport` guesses from title, then channel name), orange now line, past part darker; the focused row opens to
  two lines (times, time left, title; tags under the channel). Android has it too since 1.93 (`Guide`/`GuideRow` in Epg.kt: channel 110 dp, rows 46 dp).
- EPG: no what's-playing panel (the bottom bar shows it); Done/Enter in Filter jumps to the first result.
- Settings sections (both TVs): Account, General, Hidden, Changelog.
- Apple TV (1.88/1.89): Home has no Live Now row (opens on the first sport; Android too since 1.93); score column
  66 pt (3-digit scores). EPG channel column 220 pt, names wrap (3 lines), tags always shown, rows 92 pt, no expanding.
  Edge shortcuts: right on a Home game → EPG, left on EPG categories → Home, left on game-screen categories → back
  (`tvEdgeJump`; Android `onEdgeKey`, 1.93). Full screen centre button: stream info panel (both TVs). Rows don't zoom on
  focus (Android TvButton default focusedScale 1f; tabs 1.04). Finished games open (Android Lite folds them).
- Corner player to full screen: click it; Android also hold Back, Apple TV hold Play/Pause (tvOS keeps hold-Back).
- Apple TV shell ignores all safe areas (own 20pt margin); the now-playing bar sits on the screen's bottom edge.
- EPG: favourites (hold select / heart) listed first; Hide via hold; Settings › Hidden lists hidden sports, leagues,
  categories, channels. Hidden sports/leagues are switched off (not fetched, not matched).
- Apple TV playback (1.87): VLCKit 3.6 for everything except 4K channels, which play with KSPlayer
  (kingslay/KSPlayer, pinned by revision 3df1658 = tag 5.6.2, product KSPlayerUI so FFmpegKit comes along; GPL build:
  KSPlayer itself is a closed binary framework, fine for this public repo; the paid LGPL build is the alternative).
  `CourtsideTV/HDRPlayer.swift` wraps KSPlayerLayer with KSMEPlayer only (no AVPlayer second try = no second
  connection), on the same TS URL VLC uses. `HDROptions.updateVideo` hands AVDisplayCriteria (HDR + fps) to
  PlaybackController.displayCriteria; TVPlayerView applies it in full screen only. No picture within 7 s (or an
  error before one): close it, wait 1 s, open the same URL on VLC; that URL then skips the HDR player for the session.
  Settings › Playback › "4K with the HDR player" (`hdrPlayerFor4K`, default on). `wantsHDRPlayer` in AppModel picks
  4K by name/category/measured quality. The 1.80 AVPlayer/HLS path is gone. KSPlayer logs are set to panic (URLs).
- Mac + iPhone (1.95): no Live Now (`startingSport`: favourite with something live, else any live), folds via
  `HomeFolds` (RedZone; no Later today since 2.2), EPG colours from `Shared/GuideColour.swift` (moved out of TVGuide), sound tags
  (iPhone AVPlayer: `AVEngine.soundLabel` from the audio format), EPG download status in the top bar / top of Home,
  Settings sections Account/Playback/General/Hidden/Changelog, Connection log (`Shared/ConnLog.swift`, shared by the
  Apple apps; Android has its own ConnLog.kt). iPhone: two cards per row; sideways on an EPG category =
  `IOSGuideTimeline`. Mac: finished games open by default; channel sports as `MacSportChannels`.
- Stalls (all apps, 2.5): the connection stays open through hiccups; FreezeWatch only reopens a picture that hasn't
  moved for 10 s (2.10; 60 s in 2.5) and never skips to another stream (`onRepeatedFreezing` no longer fires). A stream that had shown a
  picture and then errors/ends is reopened (same URL, every 3 s, up to 2 min, shown as buffering); one that never
  showed a picture fails as before. Switching streams only with the opt-in auto-switch setting.
- Android Lite mode (1.94): Settings › Lite mode section, only when `settings.slowDevice` (not NVIDIA). Master switch
  plus one Flag per option, least → most effect: liteSettle (350 ms), liteFoldFinished, liteNoLogos, liteNoScores,
  liteNoAutoplay, liteNoCorner. Defaults follow the old `lite` pref. Drawing code reads them via `Perf` (settings ref).
- Android streams open TS first (HLS fallback): HLS made the provider count extra connections while flipping.
- Android full screen always uses SurfaceView (no HDR switch; the TV's Match content setting decides HDR). The video
  renderer forces a fresh decoder on every surface change (handover garbled 4K on Chromecast).

- Apple guide (1.85): parsed guide saved as Caches/Courtside/guide.json (wanted channels, up to guide hours + refresh
  interval ahead); the raw guide.xml is deleted after parsing. `refresh()` loads it right after saved channels, while
  ESPN downloads (Android does the same via Cache.kt). tvOS can still purge Caches (no persistent storage there).

## Android phone app (2.0, 2026-11-20)
- Same APK as the TVs. `Device.tv` (Device.kt: UI mode television, leanback, Fire TV, or no touchscreen) picks the
  layout in `CourtsideApp`: TVs keep `Shell`, phones/tablets get `PhoneApp` (Phone.kt, PhoneHome.kt, PhoneEpg.kt,
  PhoneSettings.kt), modelled on the iPhone app. Lite mode defaults are off on phones (`slowDevice` needs a TV).
- Phone: edge to edge, any orientation (TVs set landscape in code; the manifest no longer forces it), pinned player
  above the tabs (same single SurfaceView placed at `cornerBounds`, overlay for controls), bottom tabs, chips at the
  bottom starting from the right (`TrailingRow`). Sideways on a game = full screen (back upright closes it);
  sideways on an EPG category = timeline (reuses `GuideRow`). Picture in picture: auto-enter on Android 12+,
  onUserLeaveHint on 8-11, PiP button in full screen; closing PiP or locking the phone stops the stream (onStop).
- Chromecast on the phone app (2.17, Cast.kt): play-services-cast-framework + the Default Media Receiver, own Compose
  picker (MediaRouter routes; no MediaRouteButton, which needs AppCompat/FragmentActivity). `AppModel.startStream`
  loads the HLS URL on the Chromecast instead of Playback while connected; `castChanged` moves the current stream
  there or back. `streamOpen` counts `Cast.hasMedia`, so downloads wait while the TV plays. Leaving the app keeps
  casting (onStop). Volume keys → TV volume. Crash guard like iOS (prefs "cast": starting/disabled). Unconfirmed:
  the provider's HLS may lack CORS headers, which the web receiver needs; then casting fails ("couldn't play").
  No AirPlay on Android. material3 added for Switch,
  pull to refresh, spinner, dialog.

## Working preferences (Sunny)
- Small changes (a number, text, a changelog line) merge straight away without check.yml; the Mac release build
  refuses to publish a broken build (2.9). Anything that changes behaviour or Apple TV/iPhone code still gets check.yml
  first. Always re-check Changelog.swift after resolving a merge conflict in it (2.10 broke the Mac build that way).
- Report how long each request took.
- Always tell Sunny when a release is actually published (after the main runs finish), not just merged.
- To save credits: build and settle features on Android first, then port to Apple TV/Mac/iPhone in one batch.
  Batch requests into one release. Use quick mock-ups before coding big layout changes. Start fresh sessions
  instead of one very long one.

## Open items
- 1.87 Apple TV HDR player (KSPlayer): HDR badge confirmed on the TV in full screen. Still to confirm: 1/2 connections,
  4K <-> normal switching, fps/sound tags. First build after 1.87 downloads KSPlayer + FFmpegKit git history (~2.5 GB,
  one time; later builds reuse build-tv/SourcePackages).
- 1.83 Apple TV EPG: rows 124/176 pt, wrapped titles, sport colour also from today's team names and the channel's
  category. Builds (check.yml passed); look on the TV not yet confirmed. Note: gh only works once the repo is attached
  to the session (add_repo, push).
- iPhone Home "Live Now" blue bar: unexplained; ask for a screenshot if it's still there.
- Chromecast crashes: Android now saves crash details (shown once on next start, and in Settings › General).
- Apple TV hasn't got a Lite mode (not needed so far).

## 2.3 (2026-11-20, Mac Home width + local Mac builds)
- Home cards: `GridItem(.adaptive(minimum: cardWidth × 0.86))` with no maximum, so cards stretch and an extra one fits.
- `LeagueSummary` (logo 24 + name + "2 live · 9 coming up"): at the right end of the chip row when one league is on
  screen (DashboardView `leagueChips`), otherwise a compact heading per league (SportView `showHeading`).
- Local Mac build: `shortcuts/Update Mac app.command` → `scripts/mac-install.sh` (xcodebuild Release arm64 into
  build-mac, reuses build-tv/SourcePackages, build number = newest mac-N release so GitHub releases still update it,
  replaces the installed copy and opens it, prints the time). Kept, but NOT the normal flow: Sunny doesn't want to
  double-click for Mac builds (2026-11-20). Keep the GitHub check + GitHub Mac release; don't merge Mac changes with
  `[skip ci]` expecting a local build (2.3 was, then published with `gh workflow run mac.yml --ref main`).

## 2.1 (2026-11-20, Mac EPG)
- `guideReading` (Shared): after the guide download, while the file is parsed: "Reading EPG…" (Mac/TV/iPhone); a stream
  starting then no longer cancels it. Mac EPG banner hidden while downloading (the top bar shows it).
- Mac EPG channel column: `ChannelCell` number 44 pt (one line), logo 52, name on up to 2 lines, `MacScrollingText` when
  it needs more (hovered/selected); column = longest/2 clamped 110–180 + fixed, min 290. Category panel 0x0B0E12 + edge line.
- Mac Home: the sections VStack is full width/leading (all-folded leagues used to centre).

## 1.98 (2026-11-20, Mac follows the TVs)
- Home sports list: TV groups with a line between (scores | channel sports | nothing today, `orderedSports`), badge = live
  count only, "Channels" detail, right-click Favourite/Hide. League chips in `Sport.leagues` order with live badge.
- Score cards: stream count (or "None" in red). Game screen: categories left (All, sections, Foreign, Local and likely),
  `GameStreamLine` rows (logo, name, now + progress, tags); lineup = current category; old StreamRow/FlowLayout unused.
- Full screen: click / I = stream information panel (1.99: no info button). 1.99: Home folds (Finished; Later today gone in 2.2)
  sit above their own cards. Mini player: now times + progress, next.
- EPG: right-click Hide on categories and channels. The Mac mini player stays at the top (not the TVs' corner).

## 1.96 (2026-11-20)
- Android navigation like Apple TV's: Back = page → left panel (selected item) → current tab → Home tab → exit
  (`model.sideFocused`, `model.focusMoves` "side"/"tabs"); Settings section kept in `model.settingsSection`. No edge
  shortcuts any more (left on a left panel, right on the last card: nothing). Apple TV already worked this way (TVNav zone).
- League chips: fixed order (All, then `Sport.leagues` order = popularity); Sunny chose this over favourite leagues.
- Matcher (both): a match confirmed by channel name or guide is never `local`; event sports list every 4K match under 4K.
- autoSwitch default off everywhere, turned off once for existing installs (`autoSwitchOff196`).
- Apple logos: `LogoCache` in Palette.swift (NSCache + 30 MB URLCache, one download per URL); Mac channel icons use it.
- Scores poll every minute only while a game is live or starts within 15 min, else every 5 min; Android skips polling
  while the app isn't on screen (`onScreen`, `cameBack()`).
- Lite mode options are named positively (Logos, Live scores, Player in the corner...); stored flags unchanged.
- Stopping a stream on Android: Play/Pause on the remote stops the corner player; in Lite (no corner) Back from full
  screen stops it.

## 2.2 (2026-11-20)
- "Later today · N" fold on Home is now an Android Lite mode option only (Settings › Lite mode › Later games,
  `liteFoldLater`, `Perf.foldLater` = slowDevice && liteFoldLater). Shield, Android phones, Apple TV, Mac and iPhone
  show later games as ordinary cards after the ones coming up soon (`HomeFolds.isLater` removed).

## 2.4 (2026-11-20)
- Recent streams in full screen (all apps): `watched` in both AppModels (most recent first, max 8; a stream counts
  after 5 s on it, so flipping past doesn't add it; `recentStreams(besides/item, limit)` leaves out the current one).
  Apple: tracked from nowPlaying/pinned didSet, checked on the next main-actor turn (closePlayer sets two values).
  Android: `noteWatching` in pin()/play().
  TVs: centre shows the stream information + a strip of up to 5 cards above the info bar; left/right picks (orange
  outline), centre plays it, Back hides (Android `BackHandler(enabled = showDetails)`, Apple TV onExitCommand).
  Mac: click / I shows it, cards clickable, Left/Right + Return. Phones (iPhone, Android): shown with the controls on
  tap, as many cards as fit (up to 4), tap plays. Android shared card: `RecentCard` in Screens.kt.
- EPG refresh shows "Refreshing EPG…" only (no % or bar) everywhere; Apple keeps "Reading EPG…" after the download.
  The % sat at 100%: the file arrives in a burst and the reading/sorting/saving after it isn't measured.

## 2.6 (2026-11-20, set up from your phone, Android TV)
- TV sign-in screen (and Edit account) has a right-hand panel: QR code + address + 4-digit PIN (`PhoneSetup.kt`).
  While it's on screen, `PhoneSetupServer` (plain ServerSocket, port 8642 or any free one) serves a sign-in page on
  the home network; POST /login checks the PIN (5 wrong = new PIN), then runs signIn/updateAccount on the main thread
  and answers with the result. Details never logged (ConnLog only says "details received"). QR via zxing core.
- Not on the Android phone layout. Apple TV/Mac/iPhone not ported yet (Apple TV would use NWListener).

## 2.8 (2026-11-20)
- Android full screen: no stream information panel (StreamDetails removed); the centre button only shows the recent
  strip. Recent strip (all apps): a bin at the left clears it (`clearWatched()`); on the TVs it's index -1 (left from
  the first card). Cards and bin at black 0.18 (picked 0.35), border white 0.08 (picked: orange).

## 2.14 (2026-11-20)
- Game screen: `StreamSections.byQuality` sorts every section (and foreign groups, local and likely) by
  `qualityRank(m, measured)` (measured label 4K/1080p/720p/SD, else the name's `qualityRank`; unknown = 2 like HD),
  then measured fps, then the matcher's order. Callers pass `measuredQuality` / `measuredFrameRate`. Android builds it
  inside `remember(all, league)`, so rows don't move while you're on the screen; the Apple views recompute live.
- 2.15: ties on resolution and rounded fps go to HDR (`measuredHDR`/`measuredHdr`, any label), then `soundRank`
  (Atmos 4, Dolby+ 3, 5.1/Dolby 2, Stereo 1, unknown 0), then the matcher's order.

## 2.16 (2026-11-20)
- Reconnect in full screen (all apps): first tile of the recent strip (strip now shows even with no recents). TVs:
  strip index -2 = Reconnect, -1 = bin (only with recents), 0… = recents; opens on the first recent, else Reconnect.
  Android `Playback.reconnect()` (stop, clear, 600 ms, open same URL; ConnLog "Reconnect pressed"). Apple views:
  `controller.stop()` / `playback.stop()`, 600 ms, `start()`. Apple TV strip shows 4 recents (room for 2 icons).
- A stream "looping the last ~15 s": likely the provider's restream server replaying its buffer each time the app
  reconnects to a stalled source (auto-reconnect after a drop since 2.5). If it recurs, the Connection log should
  show repeated "Stream dropped: opening … again". Possible follow-up: stop auto-reconnecting after a few quick drops.

## 2.17 (2026-11-21)
- "No sound" (`StreamSections.noSound` / `Playback.NO_SOUND`) becomes the sound label when a stream has shown a
  picture for 8 s with no sound label: Android `Playback.poll` (firstFrame, PLAYING, 8 s after open), VLC
  `playingPolls == 16` (asks VLC for the sound every 2 s until then), KSPlayer the same, iPhone AVPlayer
  `playingSince` + 8 s. A real label replaces it later. Recorded in measuredAudio like any sound, so it shows as a tag
  everywhere tags show. `byQuality` puts "No sound" streams last in each section, before any other key.
  Can't spot a sound track that's present but silent (no level metering).

## 2.19 (2026-11-21, stream reliability dots, Android only)
- `StreamStats.kt`: per stream ID (never the URL) running averages (weight 0.3) of rebuffer ratio, events/hour
  (buffers + freezes + drops), startup ms, fail rate; last 15 sessions; files/stream-stats.json; dropped after 60 days.
  Hooks in Playback.kt: begin (play), firstPicture, tick (poll, 500 ms), froze (FreezeWatch restart), dropped
  (reconnectAfterDrop), end (stop / next play). Sessions under 10 s watched (or failed under 8 s) are ignored.
- `ReliabilityDot` (Components.kt) on game-screen streams (TV `StreamCell`, phone `StreamRow`): shows after 5 min
  watched; red at rebuffer >5% / >20 events/h / fail >40% (or 2+ opens failing >50%), amber at >1% / >6 /h / >15% /
  startup >8 s. `StreamStats.reset()` exists but no Settings button yet. Not on Apple apps yet.
