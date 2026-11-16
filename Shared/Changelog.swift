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
        var id: String { version }

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

    /// The releases with changes for this app, each holding only this app's changes.
    static var forThisApp: [Release] {
        let app = App.current
        return releases.compactMap { r in
            let mine = r.changes.filter { $0.apps.contains(app) }
            return mine.isEmpty ? nil : Release(version: r.version, date: r.date, time: r.time, title: r.title, changes: mine)
        }
    }

    static let releases: [Release] = [
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
