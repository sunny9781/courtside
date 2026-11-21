import SwiftUI

@main
struct CourtsideTVApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var nav = TVNav()

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(model)
                .environmentObject(nav)
                .preferredColorScheme(.dark)
        }
    }
}

enum TVTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case epg = "EPG"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String? {
        switch self {
        case .home: return nil
        case .epg: return "tv"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// Where you are in each tab, kept while you move between tabs (like the Mac app).
@MainActor
final class TVNav: ObservableObject {
    enum HomeSelection: Hashable {
        case liveNow
        case sport(Sport)
        case league(String)
    }

    @Published var tab: TVTab = .home
    @Published var homeSelection: HomeSelection = .liveNow
    @Published var homePath: [String] = []
    /// Focus is on Home / EPG / Settings at the top. The player's video can't take focus then, so pressing down
    /// from the tabs still lands on the page's left column.
    @Published var tabsFocused = false
    /// Focus is on a screen's left column (sports, EPG categories, Settings sections).
    @Published var sideFocused = false
    /// Focus is on Home's league list (beside the folded sports): Back goes to the sport, not the rail.
    @Published var leaguesFocused = false
    @Published var sportRequest = 0
    /// Each tab remembers where you were: the Settings section and the EPG groups you'd opened.
    @Published var settingsSection = "Account"
    @Published var guidePath: [String] = []
    /// Back steps out one level: from a page to its left column's selected row, from the left column up to the
    /// tabs. These ask the screen (or the tabs) to take focus.
    @Published var sideRequest = 0
    @Published var tabsRequest = 0

    enum Zone { case tabs, side, page }
    var zone: Zone { tabsFocused ? .tabs : (sideFocused ? .side : .page) }

    init() {
        switch DemoData.screen {
        case "sport": homeSelection = .sport(.basketball)
        case "game": homeSelection = .sport(.basketball); homePath = ["g1"]
        case "epg": tab = .epg
        case "settings": tab = .settings
        default: break
        }
    }
}

struct TVRootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if model.credentials == nil {
                TVLoginView()
            } else {
                TVShell()
            }
        }
    }
}

/// The same layout as the Mac: tabs centred along the top, connections on the left, last update on the right,
/// and the selected screen below. The player covers everything.
struct TVShell: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var multiview = TVMultiview.shared

    var body: some View {
        // Full screen is drawn on top of everything in this same screen (like the Mac), not as a separate
        // presentation: moving the video between two windows is what left the player at the top black.
        ZStack {
            shell
                .opacity(model.nowPlaying == nil && !multiview.active ? 1 : 0)
                .disabled(model.nowPlaying != nil || multiview.active)
            if let item = model.nowPlaying {
                TVPlayerView(item: item)
                    .transition(.opacity)
                    .zIndex(1)
            } else if multiview.active {
                // Multiview (2.30): two streams side by side, over everything.
                TVMultiviewView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if let message = model.notice {
                Text(message)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .zIndex(2)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(message.count > 80 ? 12 : 5))
                        if model.notice == message { model.notice = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.nowPlaying == nil)
        .animation(.easeOut(duration: 0.2), value: multiview.active)
    }

    private var shell: some View {
        ZStack(alignment: .bottomLeading) {
            // No top bar (2.24, like Android TV 2.7): the tabs and the status are in the rail down the left edge, and
            // every page starts at the top, just right of the rail.
            Group {
                switch nav.tab {
                case .home: TVHomeView()
                case .epg: TVLiveView()
                case .settings: TVSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .horizontal)
            .padding(.leading, TVLayout.rail)
            .focusSection()
            // Under everything, one line across the very bottom: what's playing. Pages scroll under it.
            if let item = model.pinned {
                TVNowPlayingBar(item: item)
                    .padding(.leading, TVLayout.rail)
                    .allowsHitTesting(false)
            }
            // The player: bottom-left corner above that line, the same spot on every tab, with each tab's left
            // panel on top of it. Its left side lines up with the start of the now-playing line.
            if let item = model.pinned {
                TVPinnedStrip(item: item, game: nil)
                    .padding(.leading, TVLayout.rail)
                    .padding(.bottom, TVLayout.margin + TVLayout.barHeight)
                    .focusSection()
                    .transition(.opacity)
            }
            // The open rail shades the page (the player too) and sits on top of it.
            if nav.tabsFocused {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            TVRail()
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeOut(duration: 0.15), value: nav.tabsFocused)
        // Use almost the whole screen: no Apple TV insets at the sides, top or bottom, just our own small margin
        // (the bottom inset left a big empty strip under the now-playing bar).
        .ignoresSafeArea(.container, edges: .all)
        .padding(.top, TVLayout.margin)
        // Back on EPG or Settings goes to Home; on a game screen it goes back to the Home list (also when focus
        // isn't inside the game screen, e.g. right after full screen); on the Home list it leaves the app, as
        // usual on Apple TV.
        .onExitCommand(perform: exitAction)
        // Play/Pause on the remote stops the player at the top (and frees the connection).
        // Hold Play/Pause: the player in the corner goes full screen (Android TV: hold Back).
        // Both from the same place, so on every screen a hold is never also taken as a short press (on Home the short
        // press used to stop the player before the hold could open it).
        .background(TVPlayPauseHold(action: {
            guard model.nowPlaying == nil, !multiview.active, let item = model.pinned else { return }
            model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
        }, tap: {
            guard model.nowPlaying == nil, !multiview.active, model.pinned != nil else { return }
            PlaybackController.shared.stop()
            model.pinned = nil
            model.checkConnectionsSoon()
        }))
        .animation(.easeOut(duration: 0.25), value: model.pinned == nil)
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.refresh() } }
            // Leaving the app: multiview's second stream closes; the first stays as normal playback does.
            if scenePhase == .background { multiview.end(model: model) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvSwitchTab)) { note in
            if let tab = note.object as? TVTab { switchTab(tab) }
        }
    }

    /// Back steps out one level at a time: a page (games, channels, a setting) → the selected row on the left →
    /// the tabs → Home's tab → leaves the app. A game screen goes back to its card first.
    private var exitAction: (() -> Void)? {
        if nav.tab == .home && !nav.homePath.isEmpty && nav.zone != .tabs { return { nav.homePath.removeLast() } }
        switch nav.zone {
        case .page: return { nav.sideRequest += 1 }
        case .side where nav.tab == .home && nav.leaguesFocused: return { nav.sportRequest += 1 }
        case .side: return { nav.tabsRequest += 1 }
        case .tabs:
            guard nav.tab != .home || !nav.homePath.isEmpty else { return nil }
            return {
                if nav.tab == .home { nav.homePath.removeAll() } else { switchTab(.home) }
                nav.tabsRequest += 1
            }
        }
    }

    /// The player at the top keeps playing while you look at another tab.
    private func switchTab(_ tab: TVTab) {
        guard tab != nav.tab else { return }
        nav.tab = tab
    }

    /// The game the player's stream was started from, so its score shows beside the video on every tab.
    private var pinnedGame: Game? {
        guard let item = model.pinned, let title = item.gameTitle else { return nil }
        return model.games.first { $0.title == title && model.pinnedIsFrom(gameID: $0.id) }
    }
}

extension Notification.Name {
    static let tvSwitchTab = Notification.Name("tvSwitchTab")
}

/// "1.22"
private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}

/// "EPG 9:10 PM", or what the refresh is doing ("Refreshing EPG…", "EPG refreshes after this stream").
@MainActor
func tvEPGStatus(_ model: AppModel) -> (text: String, busy: Bool)? {
    if model.refreshWaiting { return ("EPG refreshes after this stream", true) }
    if model.downloadingChannels { return ("Refreshing EPG · channels…", true) }
    if model.guideReading { return ("Reading EPG…", true) }
    if model.guideDownloading { return ("Refreshing EPG…", true) }
    if let saved = model.guideUpdated ?? model.savedAt { return ("EPG \(saved.formatted(date: .omitted, time: .shortened))", false) }
    return nil
}

/// Home, EPG and Settings down the left edge, where every move starts (2.24, like Android TV): left from a page's
/// left column opens it, right (or clicking a tab) goes back into the page on its selected item, never straight to
/// the games. Closed it's icons, with the connections, the EPG time and a dot when a newer version is out at the
/// bottom; open it shows names, the full status and the version button, over the page.
struct TVRail: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @ObservedObject private var versions = VersionCheck.shared
    enum Item: Hashable { case tab(TVTab), version }
    @FocusState private var focused: Item?
    /// A tab switch waiting for you to stop on that tab.
    @State private var pendingTab: Task<Void, Never>?
    @State private var waitingTab: TVTab?

    private var open: Bool { focused != nil }

    private func symbol(_ tab: TVTab) -> String {
        switch tab {
        case .home: return "house.fill"
        case .epg: return "tv"
        case .settings: return "slider.horizontal.3"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                if open {
                    Text("Court").foregroundStyle(Theme.text)
                    Text("side").foregroundStyle(Theme.accent)
                } else {
                    Text("C").foregroundStyle(Theme.accent).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 30, weight: .bold))
            .padding(.horizontal, open ? 22 : 0)
            .frame(height: 56)
            ForEach(TVTab.allCases) { tab in
                Button {
                    pendingTab?.cancel()
                    waitingTab = nil
                    NotificationCenter.default.post(name: .tvSwitchTab, object: tab)
                    // Into the page, on its selected item (the rail closes as focus leaves it).
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(60))
                        nav.sideRequest += 1
                    }
                } label: {
                    HStack(spacing: 20) {
                        Image(systemName: symbol(tab))
                            .font(.system(size: 28))
                            .frame(width: 40)
                            .foregroundStyle(focused == .tab(tab) ? Theme.bg : (nav.tab == tab ? Theme.accent : Theme.muted))
                        if open {
                            Text(tab.rawValue).font(.system(size: 28, weight: .semibold)).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(TVRowButtonStyle(selected: nav.tab == tab))
                .focused($focused, equals: .tab(tab))
            }
            Spacer(minLength: 0)
            status
            if open {
                // The version, which checks for a newer Courtside (Apple TV is updated from the Mac).
                Button {
                    Task { await versions.check() }
                } label: {
                    Label(versions.newer.map { "Version \($0) is out: update from your Mac" } ?? "v\(versions.current)",
                          systemImage: versions.checking ? "hourglass"
                              : (versions.newer != nil ? "arrow.down.circle.fill" : "arrow.clockwise"))
                        .font(.system(size: 21, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(focused == .version ? Theme.bg : (versions.newer != nil ? Theme.accent : Theme.muted))
                }
                .buttonStyle(TVRowButtonStyle())
                .focused($focused, equals: .version)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, TVLayout.margin)
        .frame(width: open ? TVLayout.railOpen : TVLayout.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(open ? Theme.card : Theme.bg)
        .focusSection()
        // Coming onto the rail lands on the tab you're on (so it doesn't switch by accident).
        .defaultFocus($focused, .tab(nav.tab), priority: .userInitiated)
        // Back from a left column: to the tab you're on.
        .onChange(of: nav.tabsRequest) { focused = .tab(nav.tab) }
        // Moving through the tabs shows a page once you stop on its tab (a quarter second); leaving the rail shows it
        // now, and lands on the page's selected item.
        .onChange(of: focused) {
            nav.tabsFocused = focused != nil
            pendingTab?.cancel()
            guard let focused else {
                if let waitingTab { NotificationCenter.default.post(name: .tvSwitchTab, object: waitingTab) }
                waitingTab = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    if !nav.tabsFocused && !nav.sideFocused && model.nowPlaying == nil { nav.sideRequest += 1 }
                }
                return
            }
            guard case .tab(let tab) = focused, tab != nav.tab else { waitingTab = nil; return }
            waitingTab = tab
            pendingTab = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                waitingTab = nil
                NotificationCenter.default.post(name: .tvSwitchTab, object: tab)
            }
        }
        .task { await versions.check() }
        .animation(.easeOut(duration: 0.15), value: open)
    }

    /// Connections ("1/2", orange at the limit) and the EPG time: full when open, short under the icons when closed.
    @ViewBuilder
    private var status: some View {
        let epg = tvEPGStatus(model)
        if open {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle().fill(Theme.raised).frame(height: 2)
                TVConnectionsPill(account: model.account)
                if let epg {
                    Text(epg.text)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(epg.busy ? Theme.accent : Theme.muted)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        } else {
            VStack(spacing: 16) {
                if let max = model.account?.maxConnections, max > 0 {
                    let active = model.account?.activeConnections ?? 0
                    VStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 20))
                        Text("\(active)/\(max)").font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(active >= max ? Theme.accent : Theme.muted)
                }
                if let epg {
                    VStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 20))
                        Text(epg.busy ? "EPG…" : String(epg.text.dropFirst(4)).components(separatedBy: " ").first ?? "")
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(epg.busy ? Theme.accent : Theme.muted)
                }
                if versions.newer != nil {
                    Circle().fill(Theme.accent).frame(width: 12, height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
        }
    }
}
