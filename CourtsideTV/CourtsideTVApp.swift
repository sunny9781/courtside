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
        }
        .animation(.easeOut(duration: 0.2), value: model.nowPlaying == nil)
    }

    private var shell: some View {
        VStack(spacing: 0) {
            TVTopBar()
                .focusSection()
            // The player, in the same spot on every screen while something plays (never takes focus).
            if let item = model.pinned {
                TVPinnedStrip(item: item, game: pinnedGame)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        // Use almost the full width of the screen (the content keeps a small margin of its own).
        .ignoresSafeArea(.container, edges: .horizontal)
        // Back on EPG or Settings goes to Home. On Home it's left alone, so a game screen goes back to the
        // list and the Home list leaves the app, as usual on Apple TV.
        .onExitCommand(perform: nav.tab != .home ? { switchTab(.home) } : nil)
        // Play/Pause on the remote stops the player at the top (and frees the connection).
        .onPlayPauseCommand {
            guard model.nowPlaying == nil, model.pinned != nil else { return }
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
                if let focusedTab, focusedTab != nav.tab {
                    NotificationCenter.default.post(name: .tvSwitchTab, object: focusedTab)
                }
            }

            HStack {
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
        } else if let saved = model.savedAt {
            // Like the Mac: "Updated 8:15 PM" is itself the refresh button.
            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Label("Updated \(saved.formatted(date: .omitted, time: .shortened)) · v\(appVersion)", systemImage: "arrow.clockwise")
                    .font(.system(size: 22, weight: .medium))
            }
            .buttonStyle(TVQuietButtonStyle())
        }
    }
}
