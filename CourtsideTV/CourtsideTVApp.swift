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

    var body: some View {
        // Full screen is drawn on top of everything in this same screen (like the Mac), not as a separate
        // presentation: moving the video between two windows is what left the player at the top black.
        ZStack {
            shell
                .opacity(model.nowPlaying == nil ? 1 : 0)
                .disabled(model.nowPlaying != nil)
            if let item = model.nowPlaying {
                TVPlayerView(item: item)
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
    }

    private var shell: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                TVTopBar()
                    .focusSection()
                Group {
                    switch nav.tab {
                    case .home: TVHomeView()
                    case .epg: TVLiveView()
                    case .settings: TVSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .horizontal)
                .focusSection()
            }
            // Under everything, one line across the very bottom: what's playing. Pages scroll under it.
            if let item = model.pinned {
                TVNowPlayingBar(item: item)
                    .allowsHitTesting(false)
            }
            // The player: bottom-left corner above that line, the same spot on every tab, with each tab's left
            // panel on top of it.
            if let item = model.pinned {
                TVPinnedStrip(item: item, game: nil)
                    .padding(.leading, TVLayout.margin)
                    .padding(.bottom, TVLayout.margin + TVLayout.barHeight)
                    .focusSection()
                    .transition(.opacity)
            }
        }
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
        .background(TVPlayPauseHold {
            guard model.nowPlaying == nil, let item = model.pinned else { return }
            model.play(item.channel, gameTitle: item.gameTitle, lineup: item.lineup)
        })
        .onPlayPauseCommand {
            guard !TVRemoteHold.justHeld, model.nowPlaying == nil, model.pinned != nil else { return }
            PlaybackController.shared.stop()
            model.pinned = nil
            model.checkConnectionsSoon()
        }
        .animation(.easeOut(duration: 0.25), value: model.pinned == nil)
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvSwitchTab)) { note in
            if let tab = note.object as? TVTab { switchTab(tab) }
        }
    }

    private var exitAction: (() -> Void)? {
        if nav.tab != .home { return { switchTab(.home) } }
        if !nav.homePath.isEmpty { return { nav.homePath.removeLast() } }
        return nil
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

/// Home, EPG and Settings in the middle; connections on the left; "Updated 8:15 PM" on the right.
/// "1.22"
private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}

struct TVTopBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var versions = VersionCheck.shared
    @EnvironmentObject var nav: TVNav
    @FocusState private var focusedTab: TVTab?

    var body: some View {
        ZStack {
            HStack(spacing: 20) {
                ForEach(TVTab.allCases) { tab in
                    Button {
                        NotificationCenter.default.post(name: .tvSwitchTab, object: tab)
                    } label: {
                        if let symbol = tab.symbol {
                            Label(tab.rawValue, systemImage: symbol)
                        } else {
                            Text(tab.rawValue)
                        }
                    }
                    .buttonStyle(TVTabButtonStyle(selected: nav.tab == tab))
                    .focused($focusedTab, equals: tab)
                }
            }
            // Coming back up to the tabs lands on the one you're on (so it doesn't switch by accident).
            .defaultFocus($focusedTab, nav.tab, priority: .userInitiated)
            // Moving across Home / EPG / Settings switches straight away, no click needed.
            .onChange(of: focusedTab) {
                nav.tabsFocused = focusedTab != nil
                if let focusedTab, focusedTab != nav.tab {
                    NotificationCenter.default.post(name: .tvSwitchTab, object: focusedTab)
                }
            }

            HStack(spacing: 16) {
                // Connections in use, and "EPG 9:10 PM ⟳": when the channels and guide were last downloaded
                // (click to download them again).
                TVConnectionsPill(account: model.account)
                if let saved = model.savedAt, !model.downloadingChannels {
                    Button {
                        Task { await model.refresh(force: true) }
                    } label: {
                        Label("EPG \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "arrow.clockwise")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(TVQuietButtonStyle())
                }
                Spacer()
                status
            }
        }
        .padding(.horizontal, TVLayout.margin)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var status: some View {
        if model.downloadingChannels {
            HStack(spacing: 12) {
                ProgressView()
                Text("Downloading channels…")
            }
            .font(.system(size: 22))
            .foregroundStyle(Theme.muted)
        } else {
            // The version, which checks for a newer Courtside; when there is one, it says so (Apple TV is updated
            // from the Mac). Channels refresh on their own, or from Settings › General › Refresh now.
            Button {
                Task { await versions.check() }
            } label: {
                Label(versions.newer.map { "Version \($0) is out: update from your Mac" } ?? "v\(versions.current)",
                      systemImage: versions.checking ? "hourglass"
                          : (versions.newer != nil ? "arrow.down.circle.fill" : "arrow.clockwise"))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(versions.newer != nil ? Theme.accent : Theme.muted)
            }
            .buttonStyle(TVQuietButtonStyle())
            .task { await versions.check() }
        }
    }
}
