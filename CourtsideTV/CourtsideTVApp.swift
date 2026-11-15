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

    var symbol: String {
        switch self {
        case .home: return "basketball.fill"
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
            .focusSection()
        }
        .onExitCommand {
            // Back on EPG or Settings goes to Home first (game screens handle their own Back).
            if nav.tab != .home { switchTab(.home) }
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvSwitchTab)) { note in
            if let tab = note.object as? TVTab { switchTab(tab) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.nowPlaying != nil },
            set: { if !$0 { model.closePlayer() } }
        )) {
            if let item = model.nowPlaying {
                TVPlayerView(item: item)
                    .environmentObject(model)
            }
        }
    }

    /// Like the Mac: whatever the mini player is showing keeps playing while you look at another tab.
    private func switchTab(_ tab: TVTab) {
        guard tab != nav.tab else { return }
        let playing = PlaybackController.shared.currentURL != nil && model.nowPlaying == nil
        model.backgroundChannel = playing ? model.previewChannel : nil
        nav.tab = tab
    }
}

extension Notification.Name {
    static let tvSwitchTab = Notification.Name("tvSwitchTab")
}

/// Home, EPG and Settings in the middle; connections on the left; "Updated 8:15 PM" on the right.
struct TVTopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav

    var body: some View {
        ZStack {
            HStack(spacing: 20) {
                ForEach(TVTab.allCases) { tab in
                    Button {
                        NotificationCenter.default.post(name: .tvSwitchTab, object: tab)
                    } label: {
                        Label(tab.rawValue, systemImage: tab.symbol)
                    }
                    .buttonStyle(TVTabButtonStyle(selected: nav.tab == tab))
                }
            }

            HStack {
                TVConnectionsPill(account: model.account)
                Spacer()
                status
            }
        }
        .padding(.horizontal, TVLayout.margin)
        .padding(.top, 30)
        .padding(.bottom, 20)
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
            Label("Updated \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "arrow.clockwise")
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
        }
    }
}
