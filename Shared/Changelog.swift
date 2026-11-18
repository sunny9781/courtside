import Foundation

/// What changed in each update, shown in Settings › Updates › What's new. Each app only lists the changes that
/// apply to it. Newest first. Add an entry (at the top) with every release.
enum Changelog {
    enum App: Hashable {
        case mac, tv, ios, android

        static var current: App {
            #if os(macOS)
            return .mac
            #elseif os(tvOS)
            return .tv
            #else
            return .ios
            #endif
        }
    }

    struct Change: Hashable {
        let text: String
        let apps: Set<App>
    }

    struct Release: Identifiable, Hashable {
        /// Goes up by one with every release: "1.16".
        let version: String
        let date: String          // yyyy-MM-dd
        let time: String          // HH:mm, Eastern time
        let title: String
        let changes: [Change]
        /// The apps the title is about, when it's about more than the ones every change is for.
        var titleApps: Set<App>? = nil
        var id: String { version }

        /// The title, or "2 changes" when the release's title was about other apps.
        var heading: String {
            if !title.isEmpty { return title }
            return changes.count == 1 ? "1 change" : "\(changes.count) changes"
        }

        /// "v1.16 · Sun, Nov 15 · 12:35 PM"
        var dateLabel: String {
            let parse = DateFormatter()
            parse.dateFormat = "yyyy-MM-dd HH:mm"
            parse.timeZone = TimeZone(identifier: "America/Toronto")
            guard let d = parse.date(from: "\(date) \(time)") else { return "v\(version) · \(date)" }
            let day = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let hour = d.formatted(.dateTime.hour().minute())
            return "v\(version) · \(day) · \(hour)"
        }
    }

    private static let all: Set<App> = [.mac, .tv, .ios]
    private static let mac: Set<App> = [.mac]
    private static let tv: Set<App> = [.tv]
    private static let ios: Set<App> = [.ios]
    private static let macTV: Set<App> = [.mac, .tv]
    private static let macIOS: Set<App> = [.mac, .ios]
    private static let tvIOS: Set<App> = [.tv, .ios]
    private static let android: Set<App> = [.android]
    private static let tvAndroid: Set<App> = [.tv, .android]
    private static let everywhere: Set<App> = [.mac, .tv, .ios, .android]

    /// The releases with changes for this app, each holding only this app's changes.
    static var forThisApp: [Release] {
        let app = App.current
        return releases.compactMap { r in
            let mine = r.changes.filter { $0.apps.contains(app) }
            // A release that also changed other apps: its title may be about them, so it isn't shown here.
            let title = (r.titleApps?.contains(app) ?? (mine.count == r.changes.count)) ? r.title : ""
            return mine.isEmpty ? nil : Release(version: r.version, date: r.date, time: r.time, title: title, changes: mine)
        }
    }

    static let releases: [Release] = [
        Release(version: "1.72", date: "2026-11-17", time: "23:15", title: "Lighter Home and EPG", changes: [
            Change(text: "Team and league logos are downloaded at the size they're shown, not as large images shrunk on the TV.", apps: android),
            Change(text: "When the scores update, only the games that changed are drawn again (not every row on Home).", apps: android),
            Change(text: "EPG: what's on now and next is worked out once per programme, so long categories scroll more smoothly.", apps: android)
        ]),
        Release(version: "1.71", date: "2026-11-17", time: "22:55", title: "Faster moving through lists", changes: [
            Change(text: "Home: moving through the sports only draws a sport's games once you stop on it, so flipping past several is quicker. Clicking, or pressing right into the games, is instant.", apps: android),
            Change(text: "The tabs: going from Home to Settings no longer draws the EPG on the way past. Pressing down into a page is instant.", apps: android),
            Change(text: "EPG and game screen: moving through the categories only draws a category's channels once you stop on it.", apps: android)
        ]),
        Release(version: "1.70", date: "2026-11-17", time: "22:40", title: "Smooth, clear 4K in full screen", changes: [
            Change(text: "Full screen always uses the fast video path, like other IPTV apps: 4K is smooth and HDR shows at the right brightness. Whether the TV switches into HDR is up to its own Match content setting, so the HDR in full screen switch is gone.", apps: android),
            Change(text: "Going from the corner player to full screen starts the video decoder fresh, so the picture no longer turns fuzzy and unwatchable (Chromecast with Google TV).", apps: android),
            Change(text: "A frozen stream is closed before it's reopened, so the restart no longer counts as two connections (2/2).", apps: android),
            Change(text: "Streams that don't say their frame rate (most 4K) get it counted from the picture, so the fps badge shows and the TV can match it.", apps: android)
        ]),
        Release(version: "1.69", date: "2026-11-17", time: "22:20", title: "Installs on older Fire TV Sticks", changes: [
            Change(text: "Courtside now installs on Android 7.1, so older Fire TV Sticks (Fire OS 6) can run it.", apps: android)
        ]),
        Release(version: "1.68", date: "2026-11-17", time: "21:53", title: "More channels for each game", changes: [
            Change(text: "Games also list their Canadian, UK and European channels (Sportsnet, TSN, Sky…) and those channels' 4K feeds, from the official NHL, NBA and MLB schedules and a table of who holds the rights, like on Apple TV. Networks that only usually carry a league are under Local and likely.", apps: android),
            Change(text: "Channel sports (Fighting, pickleball…) show their streams straight away when the app opens, instead of after today's scores load.", apps: android)
        ]),
        Release(version: "1.67", date: "2026-11-17", time: "20:00", title: "Tidier Settings, slimmer now-playing bar, hold Play/Pause for full screen", changes: [
            Change(text: "Settings: the section list and the settings beside it line up the same way as Home and the EPG.", apps: tv),
            Change(text: "The now-playing bar sits at the very bottom of the screen and is slimmer (no big empty strip under it).", apps: tv),
            Change(text: "Hold Play/Pause on the remote: the player in the corner goes full screen (holding Back is kept by the Apple TV for its Home screen). A short press still stops it.", apps: tv)
        ]),
        Release(version: "1.66", date: "2026-11-17", time: "15:20", title: "Steadier EPG focus, no screensaver mid-game", changes: [
            Change(text: "EPG: Back from full screen goes back to the channel you were watching, not the category.", apps: android),
            Change(text: "EPG: opening or leaving a group no longer flashes the EPG time at the top; leaving a group lands on that group.", apps: android),
            Change(text: "The screensaver no longer comes on while something is playing (it stopped the stream on Chromecast).", apps: android)
        ]),
        Release(version: "1.65", date: "2026-11-17", time: "14:55", title: "Apple TV and Android TV lined up", changes: [
            Change(text: "Settings: the sections are in the same order as on Android TV (Account, General, Hidden, Changelog). Mini player and Show finished games are gone: neither did anything on the Apple TV.", apps: tv),
            Change(text: "Settings › Account checks the connection count each time you open it.", apps: tv),
            Change(text: "EPG: what's playing is only in the bar along the bottom (the extra panel under the categories is gone), and the channel that's playing is orange in the list.", apps: tv),
            Change(text: "EPG: Done on the Filter keyboard goes to the first result.", apps: tv),
            Change(text: "Game screen: with no streams found, a Back to the games button.", apps: tv),
            Change(text: "Long messages (like update problems) stay on screen for 12 seconds instead of 5.", apps: tv),
            Change(text: "The connection count is checked 20 seconds after you switch streams (not 5, when the provider still counted the old one), and every minute while something plays.", apps: [.mac, .tv, .ios]),
            Change(text: "Hiding a sport says Settings › Hidden brings it back (it said Settings › Sports). Settings › Hidden explains that a hidden sport is switched off.", apps: android)
        ], titleApps: [.tv, .android]),
        Release(version: "1.64", date: "2026-11-17", time: "14:38", title: "Lighter Lite mode", changes: [
            Change(text: "Lite mode has no player in the corner: a channel or stream opens straight in full screen, and Back stops it (freeing the connection).", apps: android),
            Change(text: "Lite mode has no live scores: today's games load once when the app opens, with no scores or game clocks, and nothing is fetched or re-matched every minute.", apps: android)
        ]),
        Release(version: "1.63", date: "2026-11-17", time: "14:21", title: "Room above the now-playing bar", changes: [
            Change(text: "The now-playing bar has the same gap above it as the player has below, so lists scrolling under it don't look squished.", apps: [.tv, .android]),
            Change(text: "If the app closes unexpectedly, the next start says why, and Settings › General shows the details (kept on the TV only).", apps: android)
        ]),
        Release(version: "1.62", date: "2026-11-17", time: "14:01", title: "Apple TV catches up", changes: [
            Change(text: "Home: every sport is a list like the EPG, one line per game (status, the teams and scores, the number of streams), under a heading per league. Upcoming games are grey, so live games stand out in white.", apps: [.tv, .android]),
            Change(text: "What's playing is on one line along the very bottom of the screen, under the player, on every page. Pages scroll under it.", apps: [.tv, .android]),
            Change(text: "Hold the select button on a sport on Home, or a category or channel in the EPG, to favourite or hide it. A hidden sport is switched off: no scores fetched and nothing matched for it. Settings › Hidden lists everything hidden to show it again, and replaces Settings › Sports.", apps: tv),
            Change(text: "Hidden sports and leagues are switched off: their scores aren't fetched and nothing is matched for them. Showing one again fetches it straight away.", apps: [.mac, .ios]),
            Change(text: "Full screen: no \"Opening…\" message, and flipping shows the channel only in the bar at the bottom.", apps: tv),
            Change(text: "Coming up from the games on Home lands on the selected league chip (All, or the league).", apps: [.tv, .android]),
            Change(text: "The update button checks and installs in one press.", apps: android),
            Change(text: "Holding the select button opens its menu and leaves it open when you let go, so you can choose.", apps: android)
        ], titleApps: [.tv]),
        Release(version: "1.61", date: "2026-11-17", time: "13:12", title: "Home as a guide, now-playing bar", changes: [
            Change(text: "Home: every sport is a list like the EPG (status, the teams and scores, and the number of streams), with a heading per league, instead of score cards.", apps: android),
            Change(text: "What's playing is in a bar along the bottom beside the player, across to the right edge, on every page. Pages scroll under it, and the row you're on always stays above it.", apps: android),
            Change(text: "Flipping channels uses one connection: streams now open as TS first (closed the moment you switch away) instead of HLS, which the provider kept counting for a while after each flip. Settings › General › Stream format switches back.", apps: android),
            Change(text: "Full screen: no \"Opening…\" message, and flipping shows the channel only in the bar at the bottom.", apps: android),
            Change(text: "Hold the select button on a sport on Home, or a category or channel in the EPG, to favourite or hide it. A hidden sport is switched off: no scores fetched and nothing matched for it.", apps: android),
            Change(text: "Settings › Hidden lists everything hidden (sports, categories and channels) to show it again. It replaces Settings › Sports.", apps: android),
            Change(text: "Pressing up from the player goes to the panel above it, not the top bar.", apps: android),
            Change(text: "Channel names in every guide-style list (EPG, game screens, channel sports on Home) stay on one line, using the width of the screen. Channel sports on Home list their channels under the category they come from.", apps: [.tv, .android]),
            Change(text: "EPG: the channel column is wide enough for long channel names.", apps: mac)
        ], titleApps: android),
        Release(version: "1.60", date: "2026-11-17", time: "11:49", title: "What's playing above the player", changes: [
            Change(text: "EPG: what's playing (now, its times and progress, and what's next) sits in its own section under the categories, just above the player, so the schedule starts at the top.", apps: [.tv, .android]),
            Change(text: "The EPG shows straight away after an update or reopening, from the saved guide, instead of a few minutes later once today's scores are in.", apps: android)
        ], titleApps: [.tv, .android]),
        Release(version: "1.59", date: "2026-11-17", time: "11:29", title: "Every stream under All", changes: [
            Change(text: "Game screen: All lists every stream (local and likely channels too), under headings for each group (USA, Local and likely…). Channel names stay on one line, using the space there is.", apps: [.tv, .android]),
            Change(text: "Home: scrolling through the sports no longer flickers; a sport's games show once you pause on it.", apps: android)
        ], titleApps: [.tv, .android]),
        Release(version: "1.58", date: "2026-11-17", time: "11:00", title: "EPG favourites", changes: [
            Change(text: "EPG favourites: hover a category or channel and click its heart (or right-click it). Favourite channels get their own Favourites list at the top, favourite categories are listed first, and favourite channels come first in their category.", apps: mac),
            Change(text: "EPG favourites: hold the select button on a category or channel and choose Add to Favourites. Favourite channels get their own Favourites list at the top, favourite categories are listed first, and favourite channels come first in their category.", apps: [.tv, .android]),
            Change(text: "EPG favourites: tap the heart on a category or channel. Your favourites sit along the bottom above the filter (categories, a line, then channels), and favourites come first in every list.", apps: ios),
            Change(text: "EPG: swipe from the left edge to go back, like other iPhone apps; the back button is at the top.", apps: ios),
            Change(text: "Switching streams closes the old one first and waits a moment before opening the next, so it never uses a second connection. Flipping quickly through channels only opens the one you stop on.", apps: [.mac, .tv, .ios, .android]),
            Change(text: "A game screen starts with a stream that isn't 4K, now also when the 4K only shows in the category name or the picture it played before.", apps: [.mac, .tv, .ios, .android]),
            Change(text: "Channels and the guide are downloaded fresh every 6 hours by default (was 12).", apps: [.mac, .tv, .ios, .android]),
            Change(text: "What's new only lists the changes for this app.", apps: [.mac, .tv, .ios, .android]),
            Change(text: "The bar of icons along the bottom of Home and Settings is centred.", apps: ios),
            Change(text: "Game screen: \"Local stations and likely channels\" no longer repeats its name inside when opened.", apps: ios),
            Change(text: "Updating: if the first install doesn't take (common on Chromecast), the app tries again by itself, and frees memory before the installer opens.", apps: android)
        ], titleApps: everywhere),
        Release(version: "1.57", date: "2026-11-17", time: "10:35", title: "Apple TV matches Android TV", changes: [
            Change(text: "The player is in the bottom-left corner on every tab, just the video, with each tab's left panel on top of it and the page to its right from the top.", apps: tv),
            Change(text: "Home: sports are grouped with lines between them (live scores, channel sports like pickleball, nothing today); a channel sport shows its channels as an EPG list.", apps: tv),
            Change(text: "Game screen: a mini EPG for the game, its stream categories on the left (All first) and the channels on the right with now, next and quality.", apps: tv),
            Change(text: "Settings: the section icons in the bottom bar are all centred.", apps: ios)
        ]),
        Release(version: "1.56", date: "2026-11-17", time: "10:17", title: "Live Now in a grid", changes: [
            Change(text: "Home › Live Now: the live games are in one grid of rows, like the TV apps, instead of a sideways-scrolling row per sport. Each card shows its league.", apps: mac),
            Change(text: "Switching streams closes the old one first, and the connection count is checked once you've settled on a stream (20 seconds after the last switch) and every minute while playing, so it no longer shows 2 while only one plays.", apps: android)
        ]),
        Release(version: "1.55", date: "2026-11-17", time: "00:51", title: "Fighting, channel sports, tidier panels", changes: [
            Change(text: "UFC is now Fighting, with boxing added: boxing shows and channels from the guide join UFC's schedule.", apps: everywhere),
            Change(text: "Home's sports are grouped, with a line between each group: sports with live scores, then sports shown as channels (like pickleball), then sports with nothing today.", apps: android),
            Change(text: "A sport with channels but no live scores (like pickleball) shows its channels as an EPG list instead of score cards.", apps: android),
            Change(text: "Channel names can use two lines, so long names aren't cut off. Enter on the keyboard closes it and goes to the first EPG result.", apps: android),
            Change(text: "The side panels stop the same distance above the player as the player is from the bottom of the screen.", apps: android),
            Change(text: "Settings: \"Hide adult categories\" is now \"Adult categories\", off by default. The grouping option left Settings; it's on the EPG page, now called Auto-Group.", apps: everywhere),
            Change(text: "Top bar, left: connections in use (1/2) and \"EPG 9:10 PM\", which downloads the channels and guide again when clicked.", apps: [.mac, .tv, .android])
        ]),
        Release(version: "1.54", date: "2026-11-17", time: "00:12", title: "Lite mode for less powerful TVs", changes: [
            Change(text: "Lite mode (Settings › General), on by default on every TV except an Nvidia Shield: no zoom when moving around, no team logos on Home cards, and the fastest way of drawing video, the small player included, so scrolling stays smooth while it plays.", apps: android)
        ]),
        Release(version: "1.53", date: "2026-11-16", time: "23:48", title: "Game screen as a mini EPG", changes: [
            Change(text: "Game screen: a mini EPG for the game. Its stream categories are on the left (All first, then each section, Foreign, and Local), and the channels on the right with what's on now and next and each stream's quality.", apps: android),
            Change(text: "Reopening the app shows each game's streams straight away (from last time) while today's are worked out again.", apps: android)
        ]),
        Release(version: "1.52", date: "2026-11-16", time: "23:30", title: "Much faster on Chromecast", changes: [
            Change(text: "Faster everywhere, especially on the Chromecast with Google TV: the app is prepared for speed when it's installed, Home works out its lists once instead of on every move, stream matching runs at low priority and only when the schedule actually changes, the guide keeps the next 8 hours, the EPG Filter searches in the background, and logos use less memory.", apps: android),
            Change(text: "On low-memory players (like the Chromecast), full screen uses the faster video path.", apps: android)
        ]),
        Release(version: "1.51", date: "2026-11-16", time: "23:10", title: "Smaller app, steadier picture", changes: [
            Change(text: "Opening a game starts with its first stream that isn't 4K (or the first one, if they're all 4K).", apps: everywhere),
            Change(text: "The app is much smaller, so updates need far less free space on the TV.", apps: android),
            Change(text: "HDR is off by default: full screen shows everything in standard range, so the TV doesn't switch modes. Turn it on in Settings › General › HDR in full screen.", apps: android),
            Change(text: "Game screen: the streams use the whole page, flowing around the player in the corner (the game name above the player is gone).", apps: android),
            Change(text: "EPG: the category list uses the same text size as the other side panels.", apps: android)
        ]),
        Release(version: "1.50", date: "2026-11-16", time: "22:42", title: "Clearer update problems", changes: [
            Change(text: "Before installing an update, Courtside checks there's enough free space and says how much is needed if there isn't.", apps: android),
            Change(text: "If Android's installer says \"App not installed\", Courtside explains the usual fix when you're back (free up storage, or reinstall with Downloader). The downloaded update file is deleted once it's installed.", apps: android)
        ]),
        Release(version: "1.49", date: "2026-11-16", time: "22:32", title: "Player bottom left", changes: [
            Change(text: "The player is in the bottom-left corner on every tab, with each tab's left panel on top of it and the page to its right from the top.", apps: android),
            Change(text: "Game screen: the game's name and status sit above the player; the streams fill the right.", apps: android)
        ]),
        Release(version: "1.48", date: "2026-11-16", time: "22:27", title: "Steadier pickleball cards", changes: [
            Change(text: "Pickleball: only shows on now or later today (nothing from after midnight).", apps: everywhere),
            Change(text: "Pickleball cards no longer disappear and come back every minute when scores update.", apps: everywhere)
        ]),
        Release(version: "1.47", date: "2026-11-16", time: "22:22", title: "Update screen is back", changes: [
            Change(text: "Install update uses Android's installer screen again (confirm, then \"App installed\" with Open) instead of closing the app. If Courtside isn't allowed to install apps yet, the switch for it still opens first.", apps: android)
        ]),
        Release(version: "1.46", date: "2026-11-16", time: "22:17", title: "Player top left, pages beside it", changes: [
            Change(text: "The player is back in the top-left corner on every tab, just the video. Each tab's left panel (sports, EPG categories, Settings sections) sits under it at the same width, and the page starts right beside it at the top.", apps: android),
            Change(text: "Game screen: streams start beside the player and wrap underneath it.", apps: android)
        ]),
        Release(version: "1.45", date: "2026-11-16", time: "21:56", title: "One card per pickleball channel", changes: [
            Change(text: "Pickleball: each pickleball channel is one card (showing what's on now) instead of a card for every show in its schedule. Pickleball shows on other channels still get their own cards.", apps: everywhere)
        ]),
        Release(version: "1.44", date: "2026-11-16", time: "21:53", title: "Install update gets the newest", changes: [
            Change(text: "Install update checks once more first, so it always installs the newest version (not one that's already been replaced).", apps: android)
        ]),
        Release(version: "1.43", date: "2026-11-16", time: "21:44", title: "Player in the corner", changes: [
            Change(text: "The player sits in the top-right corner on every tab, with what's playing to its left. Pages use the space beside and below it.", apps: android),
            Change(text: "Home: the left column is sport icons and live counts, top to bottom.", apps: android),
            Change(text: "EPG: the Filter and categories start at the top; \"Group similar categories\" is now just Group; the category column is narrower.", apps: android),
            Change(text: "Settings: a narrower section list.", apps: android),
            Change(text: "Updates install through Android's package installer, which works on Google TV sets (like Sony) too. If Courtside isn't allowed to install apps yet, the switch for it opens first. A cut-off download is caught before installing.", apps: android)
        ]),
        Release(version: "1.42", date: "2026-11-16", time: "21:16", title: "Back to the smoother player", changes: [
            Change(text: "Going between full screen and the player at the top is seamless again (the stream isn't reopened).", apps: android),
            Change(text: "Home: the sport names are back in the left column, lined up with the player.", apps: android)
        ]),
        Release(version: "1.41", date: "2026-11-16", time: "20:56", title: "Edit your account", changes: [
            Change(text: "Settings › Account › Edit account: change the server, username or password. The new details are checked before they're saved; a different account starts fresh with its own channels.", apps: everywhere),
            Change(text: "The connection count is checked again a few seconds after a stream starts or stops, and each time you open Settings › Account.", apps: android),
            Change(text: "New versions are checked for every 30 minutes while the app is open, so \"Install update\" appears on its own.", apps: android),
            Change(text: "Home: the sport's name shows above its games, beside its leagues when it has more than one.", apps: android)
        ]),
        Release(version: "1.40", date: "2026-11-16", time: "20:38", title: "Pickleball channels, version button", changes: [
            Change(text: "Pickleball: everything on a pickleball channel in the next six hours shows as an event (not only shows with \"pickleball\" in the title), and the pickleball channels themselves follow after the events.", apps: everywhere),
            Change(text: "Top right: the version is now the button. Click it to check for a new version; when there is one it becomes the update button. Channels refresh on their own, or from Settings › General › Refresh now.", apps: [.mac, .tv, .android]),
            Change(text: "Anyone still on the old 6-hour refresh is moved to the new 12-hour default.", apps: everywhere),
            Change(text: "Home: the left column is just icons and live counts, always the same width, and cards are sized for each sport, so more fit on every row (Live Now included).", apps: android),
            Change(text: "Going back from full screen no longer makes the picture flicker green.", apps: android)
        ]),
        Release(version: "1.39", date: "2026-11-16", time: "00:56", title: "Simpler settings", changes: [
            Change(text: "Settings has four sections: Account, Sports, General (playback, games, EPG and updates together) and Changelog (what used to be What's new).", apps: everywhere),
            Change(text: "Channels and the guide are downloaded fresh every 12 hours by default (was 6).", apps: everywhere),
            Change(text: "Home: \"Nothing live right now\" no longer shrinks the page to a narrow strip.", apps: ios)
        ]),
        Release(version: "1.38", date: "2026-11-16", time: "23:59", title: "Home fits more games", changes: [
            Change(text: "Home: the left column stays lined up with the player (it no longer shrinks), so moving to the games is smooth.", apps: tvAndroid),
            Change(text: "Home: score cards are just wide enough for their teams and scores instead of stretching, so more fit on screen.", apps: tvAndroid),
            Change(text: "Live Now: live games from different sports share rows (each card shows its league) instead of one row per sport.", apps: tvAndroid)
        ]),
        Release(version: "1.37", date: "2026-11-15", time: "23:54", title: "Chromecast fixed", changes: [
            Change(text: "Chromecast no longer crashes the app: Google's Cast toolkit couldn't read the app's long build number. Chromecast switches itself back on with this update.", apps: ios)
        ]),
        Release(version: "1.36", date: "2026-11-15", time: "23:22", title: "Tidier settings, smoother filter", changes: [
            Change(text: "Settings: one section at a time, picked from a bar at the bottom like Home's sports. No more Edit button.", apps: ios),
            Change(text: "Game screen: the filter box only shows when there are more than 10 streams.", apps: ios),
            Change(text: "EPG: the filter searches in the background, so typing stays smooth on a big channel list.", apps: mac),
            Change(text: "A bigger home-screen banner, the same width as other apps.", apps: android),
            Change(text: "The player at the top no longer switches the TV into HDR (or another refresh rate) for a 4K stream; full screen still shows HDR.", apps: android),
            Change(text: "Hold Back while something plays at the top to open it full screen.", apps: android),
            Change(text: "Right at the end of a row of streams or games goes on to the next row, and left at the start goes back.", apps: android),
            Change(text: "Home: moving between the sports and the games is smooth; the cards stretch instead of jumping between layouts.", apps: android),
            Change(text: "Game screen: stream cards are all the same height.", apps: mac)
        ]),
        Release(version: "1.35", date: "2026-11-15", time: "22:57", title: "Saved channels, steadier filter, Chromecast fix", changes: [
            Change(text: "Game screen: streams no longer list why they matched (\"channel name has the teams\" and so on).", apps: everywhere),
            Change(text: "Channels and the guide are saved and reused for 6 hours (Settings › Updates), so opening the app or installing an update doesn't download them again.", apps: android),
            Change(text: "The player at the top no longer switches the TV's refresh rate when a stream (like a 4K one) starts; only full screen does.", apps: android),
            Change(text: "Moving right past the last stream (or left past the first) stays put instead of jumping to the top bar.", apps: android),
            Change(text: "EPG: the filter switches to results only once they're ready, so the list no longer jumps around on the second letter.", apps: mac),
            Change(text: "Chromecast now starts after the app has finished opening. If it ever makes the app close while starting, it's switched off so Courtside still opens, and Settings › Playback can turn it back on.", apps: ios)
        ]),
        Release(version: "1.34", date: "2026-11-15", time: "22:45", title: "Streams play on Android TV", changes: [
            Change(text: "Streams open as HLS first, like the iPhone app, and if one shows no picture within 8 seconds the TS version is tried. Settings › Playback › Stream format switches the order.", apps: android),
            Change(text: "Streams that start between keyframes no longer stay black, and the player now follows redirects and identifies itself the way VLC does.", apps: android),
            Change(text: "The Filter box on the EPG only opens the keyboard when you click it, not when you move onto it.", apps: android)
        ]),
        Release(version: "1.33", date: "2026-11-15", time: "22:15", title: "Android TV works like the Apple TV app", changes: [
            Change(text: "Moving left from the games goes back to the sport you were on, and Back from a game, a stream or full screen lands where you came from.", apps: android),
            Change(text: "The EPG: categories grouped like the Apple TV app (Sports, Country, 24/7, Movies…), what's on now and next for every channel, and one Filter box for categories, channels and shows.", apps: android),
            Change(text: "Home: the sports you favourite come first, games are grouped by league, cards show the stream count and 4K, and the left column shrinks while you're on the games.", apps: android),
            Change(text: "Game screen: the score and box score until a stream plays, foreign streams and local stations behind buttons, and each stream's real quality and frame rate once it has played.", apps: android),
            Change(text: "Full screen: a stream that stalls for 10 seconds or stops switches to the next one (USA and Canada first). Play/Pause outside full screen stops the player at the top.", apps: android),
            Change(text: "Settings like the Apple TV app: show, hide and favourite sports and leagues, hide SD streams and adult categories, buffer, and What's new.", apps: android)
        ]),
        Release(version: "1.32", date: "2026-11-15", time: "20:50", title: "Courtside for Android TV", changes: [
            Change(text: "First Android TV version, for the Nvidia Shield and Chromecast with Google TV: sign in, today's games by sport and league, every stream for a game in sections, the player at the top and full screen (up/down to switch streams), refresh-rate matching, and updates that download on their own.", apps: android)
        ]),
        Release(version: "1.31", date: "2026-11-15", time: "20:10", title: "Even more screen", changes: [
            Change(text: "Less space above Home / EPG / Settings: the same small margin as the sides.", apps: tv),
            Change(text: "The hint under the player's title is gone.", apps: tv)
        ]),
        Release(version: "1.30", date: "2026-11-15", time: "19:25", title: "Frozen streams fix themselves", changes: [
            Change(text: "A stream that freezes for 4 seconds restarts on its own, quietly. If it keeps freezing (3 times in 2 minutes), the app says so and moves to the next stream for the game.", apps: all),
            Change(text: "The player at the top is about 12% bigger, the left column on Home matches its width, and the games line up with the text beside the video.", apps: tv)
        ]),
        Release(version: "1.29", date: "2026-11-15", time: "19:10", title: "Controls in thumb reach", changes: [
            Change(text: "Home: sports and leagues are at the bottom, above the tabs, starting from the right edge (Live Now and \"All\" nearest your thumb). Sports with no games today are left out.", apps: ios),
            Change(text: "EPG: the filter box, Group and the way back out of a group are at the bottom too.", apps: ios),
            Change(text: "Settings: Sign out is on the right, and What's new opens with only the latest update expanded.", apps: ios)
        ]),
        Release(version: "1.28", date: "2026-11-15", time: "18:55", title: "No repeated score", changes: [
            Change(text: "The score is no longer shown beside the video or on the game screen while one of the game's streams plays: the broadcast already shows it. The game screen still shows the score when nothing from that game is playing.", apps: all)
        ]),
        Release(version: "1.27", date: "2026-11-15", time: "18:35", title: "Picture in Picture and swiping", changes: [
            Change(text: "Closing the Picture in Picture window no longer ends everything: open the app again and the stream carries on in the player at the top.", apps: ios),
            Change(text: "Full screen: swiping goes back to the player at the top instead of changing stream (the arrows still switch streams).", apps: ios),
            Change(text: "Back after leaving full screen on a game screen goes back to Home instead of leaving the app.", apps: tv),
            Change(text: "After full screen, the highlight goes back to the stream (or EPG channel) you were watching.", apps: tv),
            Change(text: "Player: as you drag it bigger, the title, score and game info beside the video shrink to fit instead of disappearing.", apps: mac)
        ]),
        Release(version: "1.26", date: "2026-11-15", time: "18:30", title: "Apple TV focus fixes", changes: [
            Change(text: "Move up from a page onto the player's video and click it for full screen.", apps: tv),
            Change(text: "Home: the left column is as wide as the player's video above it.", apps: tv),
            Change(text: "Home: going back left from the games lands on the sport you came from.", apps: tv),
            Change(text: "4K channels only go at the top when their name or guide shows this game. A 4K channel that's just the network's 4K feed (often event-only) moves to \"Local stations and likely channels\", or is left out if its guide shows something else.", apps: all)
        ]),
        Release(version: "1.25", date: "2026-11-15", time: "18:15", title: "Tidier player and stream cards", changes: [
            Change(text: "Player: dragging it bigger stops at half the window, and what's beside it adapts (leaving out the venue and times, then the title) so it stays readable. The rest of the page no longer gets pushed off screen.", apps: mac),
            Change(text: "Game screen: each stream card is as wide as its text, so more fit on a row.", apps: mac),
            Change(text: "Game screen: no Back button (the remote's Back button goes back).", apps: tv),
            Change(text: "4K: a stream only counts as 4K (top of the list, and the 4K badge on Home) when its name says 4K or UHD.", apps: all)
        ]),
        Release(version: "1.24", date: "2026-11-15", time: "17:55", title: "More room on the Apple TV", changes: [
            Change(text: "Home and game screens use the full width of the TV, lined up with the player at the top.", apps: tv),
            Change(text: "Home: when you move onto the games, the left column shrinks to icons and live counts, leaving more room for scores.", apps: tv)
        ]),
        Release(version: "1.23", date: "2026-11-15", time: "17:35", title: "Smooth back from full screen", changes: [
            Change(text: "Full screen now opens within the same screen (like the Mac), so going back leaves the stream playing in the player at the top, with no black picture and no reconnect.", apps: tv),
            Change(text: "Home, game screens, EPG and Settings now line up with the player at the top and use the full width of the TV.", apps: tv)
        ]),
        Release(version: "1.22", date: "2026-11-15", time: "17:00", title: "Filter in the top bar", changes: [
            Change(text: "The filter box is in the top bar on the EPG and game screens, and stays put while you type.", apps: mac),
            Change(text: "The version number is in the top bar.", apps: macTV),
            Change(text: "Almost no border on the left and right: everything uses the full width of the TV.", apps: tv)
        ]),
        Release(version: "1.21", date: "2026-11-15", time: "16:35", title: "Apple TV Home tidy-up", changes: [
            Change(text: "Home: moving across the league chips (All, NBA, WNBA…) switches straight away, no click needed.", apps: tv),
            Change(text: "Home: the live count line is gone; live games show as an orange number on the league chips and in the left column.", apps: tv),
            Change(text: "Sports are listed favourites first, then ones with live games, then games still to come, then the rest.", apps: tvIOS)
        ]),
        Release(version: "1.20", date: "2026-11-15", time: "16:30", title: "Filters, tabs and a tidier iPhone", changes: [
            Change(text: "The search boxes are now called Filter.", apps: all),
            Change(text: "Game screen: the filter sits in the middle of the first line, and only appears when there are more streams than fit on screen.", apps: mac),
            Change(text: "Home: sports down the left, and the sport's leagues as chips across the top (like the Apple TV).", apps: mac),
            Change(text: "EPG: the filter works as soon as you press Done on the keyboard, with a \"Results for…\" heading.", apps: tv),
            Change(text: "Closing full screen no longer leaves the player at the top black.", apps: tvIOS),
            Change(text: "Home, EPG and Settings switch as you move across them, no click needed.", apps: tv),
            Change(text: "Home: game cards stretch to fill the width of the screen.", apps: tv),
            Change(text: "The spinning \"buffering\" sign only shows before a stream first appears (it used to flicker on while streams played fine).", apps: tvIOS),
            Change(text: "Home: the \"Updated\" line is gone (it's in Settings; pull down to refresh), and sports show as icons with counts.", apps: ios),
            Change(text: "Game screen: no back button or title bar (swipe from the left edge to go back).", apps: ios),
            Change(text: "Player: the score and channel are on one line, and tapping the video shows the quality and buttons over it.", apps: ios)
        ]),
        Release(version: "1.19", date: "2026-11-15", time: "15:35", title: "Updates from one place", changes: [
            Change(text: "Updates now come from the main Courtside page on GitHub.", apps: mac),
            Change(text: "If an update has downloaded and you just quit, it installs on the way out, so the next launch is the new version.", apps: mac)
        ]),
        Release(version: "1.18", date: "2026-11-15", time: "14:20", title: "More room for what matters", changes: [
            Change(text: "EPG: the panel above the guide is gone; what's on now, what's next and \"All streams for this game\" are in the player strip, and the category's name sits at the left of the time row.", apps: mac),
            Change(text: "Game screen: the search box is at the right end of the first section's line instead of its own row.", apps: mac),
            Change(text: "EPG: the channel you're on is described in two short lines, so the channel list starts higher.", apps: tv),
            Change(text: "Game screen: the score is in the player at the top while one of the game's streams plays, so the streams start higher.", apps: ios),
            Change(text: "iPad: the player sits inside the page (on Home, in the right-hand column) instead of pushing the sidebar down.", apps: ios)
        ]),
        Release(version: "1.17", date: "2026-11-15", time: "13:05", title: "Apple TV player strip and less repeated text", changes: [
            Change(text: "Home: the sport you picked on the left (or in the chips) isn't repeated as a big title above the games.", apps: all),
            Change(text: "One player strip under the top bar on every screen, like the Mac and iPhone: it keeps playing as you move around, shows the score beside the video for games, and never gets in the way of moving with the remote. Click the playing stream again for full screen; Play/Pause stops it.", apps: tv),
            Change(text: "Closing full screen always leaves the stream playing in the player at the top.", apps: all),
            Change(text: "Player: no more dragging to resize; the hide/show button stays.", apps: ios),
            Change(text: "Settings: the section you picked on the left isn't repeated as a title, and the \"Changes save automatically\" line is gone.", apps: macTV)
        ]),
        Release(version: "1.16", date: "2026-11-15", time: "12:35", title: "Score stays with the player", changes: [
            Change(text: "The score stays in the player strip when you move to the EPG or Settings while a game's stream plays.", apps: mac),
            Change(text: "The connection count is gone from the top bar; Settings shows it exactly as your provider reports it.", apps: all),
            Change(text: "What's new shows each update's version number and the time it came out.", apps: all)
        ]),
        Release(version: "1.15", date: "2026-11-15", time: "12:23", title: "French streams", changes: [
            Change(text: "Game screen: French-language channels (\"CA | French\", RDS, TVA) and Spanish ones in US categories go in Foreign streams, grouped by language.", apps: all)
        ]),
        Release(version: "1.14", date: "2026-11-15", time: "12:17", title: "Score in the player", changes: [
            Change(text: "Game screen: the score and game info sit in the player strip, to the right of the video, while one of the game's streams plays.", apps: mac),
            Change(text: "Player: resolution and frame rate are under the channel name instead of on the video.", apps: mac),
            Change(text: "The player strip is the same size on every screen; on game screens the score shrinks to fit (and grows when you drag the player bigger).", apps: mac)
        ]),
        Release(version: "1.13", date: "2026-11-15", time: "11:46", title: "Player strip everywhere and better updates", changes: [
            Change(text: "The player is the strip under the top bar on every screen, game screens included.", apps: mac),
            Change(text: "Drag the handle under the player to resize it again, on every screen (it stays 16:9).", apps: mac),
            Change(text: "\"Foreign languages\" is now \"Foreign streams\"; English-language Canadian channels are never in it.", apps: all),
            Change(text: "Updates: \"Restart to update\" always installs the newest version, even if several came out since you last restarted. The app checks every 15 minutes.", apps: mac)
        ]),
        Release(version: "1.12", date: "2026-11-15", time: "11:38", title: "Tidier game screen and player", changes: [
            Change(text: "Player: the quality and buttons sit over the bottom of the video and only show when you hover over it.", apps: mac),
            Change(text: "Game screen: foreign-language streams (Spain, Latino, Mexico…) are folded into one \"Foreign languages\" group near the bottom; click it to open it.", apps: all),
            Change(text: "Game screen: local stations and likely channels are a group at the very bottom.", apps: all),
            Change(text: "Game screen: the \"streams found\" line is gone.", apps: mac)
        ]),
        Release(version: "1.11", date: "2026-11-15", time: "11:14", title: "Game screen streams and a slimmer player", changes: [
            Change(text: "Game screen: streams are ordered 4K, then the league's own channels (like NFL Sunday Ticket), then the official broadcasters from the league's home country (USA for the NFL and NBA, Canada then USA for the NHL, UK for the Premier League), then other countries.", apps: all),
            Change(text: "Game screen: foreign-language streams (Latino, Spanish, French…) are hidden unless you switch them on.", apps: all),
            Change(text: "Game screen: click a section (4K, USA, Canada…) to fold it shut or open it.", apps: all),
            Change(text: "Game screen: search box to filter the streams.", apps: macIOS),
            Change(text: "Back is now an arrow in the top bar, left of the connection count (or press ⌘[).", apps: mac),
            Change(text: "Player: shrinking it now folds the whole panel, score included, into one slim bar.", apps: mac),
            Change(text: "Player: resizing stops at the smallest size where the quality and buttons fit on one line; drag past it to shrink to the slim bar.", apps: ios),
            Change(text: "Fixed the game screen scrolling on past the last stream.", apps: mac),
            Change(text: "EPG: one search box for categories and channels. \"NFL\" finds every NFL category and channel; \"Lions\" finds just the channels (or games on now) with the Lions, grouped by category. Click a group to fold it.", apps: all),
            Change(text: "Home: live badges show live out of today's games (\"2/5 LIVE\"), and the date is gone.", apps: all),
            Change(text: "Pop-out player: a separate window for the stream, like a second screen. The app's player shrinks to a slim bar, picking a stream in the app plays it in that window, and full screen puts that window full screen.", apps: mac)
        ]),
        Release(version: "1.10", date: "2026-11-15", time: "10:36", title: "What's new and smarter EPG groups", changes: [
            Change(text: "What's new: this list of changes, in Settings › Updates.", apps: all),
            Change(text: "Player bar: the buttons now sit right under the video: hide video (keeps the sound), full screen and stop.", apps: macIOS),
            Change(text: "Player bar: Stop ends the stream, so it frees a connection right away. The up/down arrows and pause are gone.", apps: macIOS),
            Change(text: "Player bar: drag the handle at the bottom to make the player bigger or smaller (it stays 16:9).", apps: macIOS),
            Change(text: "Pop the player out to its own window (resize it, or put it full screen on another display). Closing the window puts it back.", apps: mac),
            Change(text: "Game screen: the player and the score are combined into one panel.", apps: macTV),
            Change(text: "Game screen: streams no longer draw over the player when you scroll. The \"All streams for this game\" heading is gone.", apps: tv),
            Change(text: "Live Now shows only games that are live right now (no upcoming games or final scores).", apps: all),
            Change(text: "EPG: a category can be in more than one group (\"UK | Sports\" is under both Country › UK and Sports).", apps: all),
            Change(text: "EPG: new Movies group for any category with movies, films or cinema in its name.", apps: all),
            Change(text: "EPG: \"Random\" is now \"Other\".", apps: all),
            Change(text: "EPG: moving onto a group shows all of its channels; opening it and picking a category shows just that one.", apps: tv),
            Change(text: "EPG: an open group starts with \"All … channels\" to see every channel in it at once.", apps: ios),
            Change(text: "Streams no longer reshuffle while you tap through them.", apps: all)
        ]),
        Release(version: "1.9", date: "2026-11-15", time: "09:38", title: "Pinned player", changes: [
            Change(text: "The player is pinned at the top of every screen while something plays, and keeps playing as you move between Home, games, EPG and Settings. It's hidden when nothing is playing.", apps: macIOS),
            Change(text: "Closing full screen leaves the stream playing in the pinned player.", apps: macIOS),
            Change(text: "Tapping the video in full screen brings back the resolution, frame rate and controls.", apps: tvIOS),
            Change(text: "Streams that played sound over a black screen (some 4K channels) now switch to the VLC player automatically, and it remembers those channels.", apps: ios),
            Change(text: "One shortcut on the Mac updates both the Apple TV and the iPhone.", apps: tvIOS)
        ]),
        Release(version: "1.8", date: "2026-11-15", time: "09:21", title: "Score cards that fit", changes: [
            Change(text: "Score cards are sized per sport so every team name and score fits.", apps: all),
            Change(text: "Long scores (cricket) get their own line.", apps: all),
            Change(text: "Opening a game plays its first stream; after that, only clicking plays something else.", apps: all)
        ]),
        Release(version: "1.7", date: "2026-11-15", time: "01:17", title: "Cricket, pickleball, Chromecast and AirPlay", changes: [
            Change(text: "New sports: cricket (current matches in major series) and pickleball (events from the TV guide).", apps: all),
            Change(text: "Apple's player first, with automatic Picture in Picture when you swipe home, and AirPlay.", apps: ios),
            Change(text: "Chromecast support.", apps: ios),
            Change(text: "EPG: cleaner layout, with \"Group\" as a filter beside search.", apps: ios),
            Change(text: "Connection count and last-updated time on the Home page.", apps: ios)
        ]),
        Release(version: "1.6", date: "2026-11-15", time: "00:34", title: "iPhone and iPad app", changes: [
            Change(text: "Courtside for iPhone and iPad: Home, game screens, EPG, Settings and a full-screen player (swipe up/down to change stream).", apps: ios),
            Change(text: "Picture in Picture (stops when the phone locks).", apps: ios)
        ]),
        Release(version: "1.5", date: "2026-11-15", time: "00:03", title: "Navigation and filters", changes: [
            Change(text: "Pressing down from the top tabs starts on the left column on every page.", apps: tv),
            Change(text: "Fixed a crash when leaving full screen.", apps: tv),
            Change(text: "Hide adult categories (on by default) in Settings › EPG.", apps: all),
            Change(text: "The connection count shows 1 as soon as a stream starts here, before the provider catches up.", apps: all),
            Change(text: "Home: a sports-only menu, with league filters above the games.", apps: tv),
            Change(text: "EPG: groups open one level at a time.", apps: tv)
        ]),
        Release(version: "1.4", date: "2026-11-14", time: "23:10", title: "Frame rates and Back everywhere", changes: [
            Change(text: "Frame rates on every stream and in full screen.", apps: all),
            Change(text: "Match the TV's refresh rate to the stream (Settings › Player).", apps: tv),
            Change(text: "Click a stream to preview it, click again for full screen; scrolling no longer starts streams.", apps: tv),
            Change(text: "The Back button on the remote works on every page.", apps: tv),
            Change(text: "Game cards no longer slide under the left column.", apps: tv),
            Change(text: "Fight cards: PPV streams come right after 4K.", apps: all),
            Change(text: "No repeated \"Live Now\" heading; no icon on the Home tab.", apps: macTV),
            Change(text: "Group similar categories toggle and a working refresh button.", apps: tv)
        ]),
        Release(version: "1.3", date: "2026-11-14", time: "22:50", title: "Apple TV redesign", changes: [
            Change(text: "Redesigned to match the Mac: sports down the left, back buttons and better alignment.", apps: tv),
            Change(text: "Your login is kept when the app updates.", apps: tv),
            Change(text: "Live connection count at the top left, checked every 30 seconds and after streams start or stop.", apps: macTV)
        ]),
        Release(version: "1.2", date: "2026-11-14", time: "20:23", title: "Streams and tabs", changes: [
            Change(text: "Each stream shows the category it comes from.", apps: macTV),
            Change(text: "Live TV is now called EPG.", apps: macTV),
            Change(text: "Tied scores are both green.", apps: macTV),
            Change(text: "Home cards show a 4K badge when a 4K stream is available, instead of the network.", apps: macTV),
            Change(text: "A game keeps playing while you look around other tabs, and Home goes back to where you were.", apps: macTV)
        ]),
        Release(version: "1.1", date: "2026-11-14", time: "19:55", title: "First Apple TV version", changes: [
            Change(text: "Courtside for Apple TV: Home, game streams, player, Live TV and Settings.", apps: tv)
        ]),
        Release(version: "1.0", date: "2026-11-14", time: "19:37", title: "First Mac version", changes: [
            Change(text: "Courtside for Mac, with updates installed from inside the app.", apps: mac),
            Change(text: "Basketball app icon; built for Apple Silicon Macs.", apps: mac),
            Change(text: "The Courtside tab is now called Home.", apps: mac)
        ])
    ]
}
