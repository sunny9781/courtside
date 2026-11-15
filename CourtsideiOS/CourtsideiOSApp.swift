import SwiftUI
import UIKit

@main
struct CourtsideiOSApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var nav = IOSNav()

    init() {
        Prefs.register()
        CastManager.setUp()
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(model)
                .environmentObject(nav)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum IOSTab: Hashable {
    case home, epg, settings
}

/// Where you are in each tab, kept while you switch tabs.
@MainActor
final class IOSNav: ObservableObject {
    enum HomeSelection: Hashable {
        case liveNow
        case sport(Sport)
        case league(String)
    }

    @Published var tab: IOSTab = .home
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

    /// The sport a selection belongs to (a league's sport, for league filters).
    var selectedSport: Sport? {
        switch homeSelection {
        case .liveNow: return nil
        case .sport(let s): return s
        case .league(let id): return League.all.first { $0.id == id }?.sport
        }
    }
}

struct IOSRootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if model.credentials == nil {
                IOSLoginView()
            } else {
                IOSShell()
            }
        }
    }
}

struct IOSShell: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: IOSNav
    @ObservedObject private var playback = IOSPlayback.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            // The pinned player: only while something is playing, in the same spot on every tab. On iPhone it's
            // above the tabs; on iPad it sits inside each tab's content (see pinnedPlayerSlot), so it doesn't push
            // the sidebar down.
            if sizeClass != .regular, let item = model.pinned, model.nowPlaying == nil {
                IOSPinnedPlayer(item: item, game: model.pinnedGame)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tabs
        }
        .background(Theme.bg)
        .animation(.easeOut(duration: 0.25), value: model.pinned == nil)
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task { await model.refresh() }
                // Back in the app after closing Picture in Picture: carry on in the player at the top.
                if let item = model.pinned, model.nowPlaying == nil, !playback.isActive {
                    let buffer = UserDefaults.standard.object(forKey: Prefs.bufferMs) as? Int ?? 2000
                    playback.play(item.channel, model: model, bufferMs: buffer)
                }
            case .background:
                // Leaving the app stops the sound unless it went into Picture in Picture (which starts on its own
                // as you swipe up). Checked a moment later so Picture in Picture has time to start.
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if scenePhase == .background, !playback.av.pipActive, !playback.av.pipStarting { stopEverything() }
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            // The phone locked: no sound while locked, not even from Picture in Picture.
            stopEverything()
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.nowPlaying != nil },
            set: { if !$0 { model.closePlayer() } }
        )) {
            if let item = model.nowPlaying {
                IOSPlayerView(item: item)
                    .environmentObject(model)
            }
        }
        .onAppear {
            // Picture in Picture: "back to app" returns to the app with the stream still playing. Closing the floating
            // window stops the stream (so nothing plays in the background) but keeps your place: opening the app
            // again carries on in the player at the top.
            playback.av.onPiPRestore = {}
            playback.av.onPiPClosed = {
                guard UIApplication.shared.applicationState != .active else { return }
                IOSPlayback.shared.stop()
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.notice {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.raised))
                    .padding(.bottom, 70)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        model.notice = nil
                    }
            }
        }
    }

    private func stopEverything() {
        playback.stop()
        model.pinned = nil
        model.closePlayer()
    }

    private var tabs: some View {
        TabView(selection: $nav.tab) {
            IOSHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(IOSTab.home)
            IOSEPGView()
                .pinnedPlayerSlot(.epg)
                .tabItem { Label("EPG", systemImage: "tv") }
                .tag(IOSTab.epg)
            IOSSettingsView()
                .pinnedPlayerSlot(.settings)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(IOSTab.settings)
        }
    }
}

/// iPad: the pinned player at the top of this tab's content, shown only on the tab you're on (one player at a time).
private struct PinnedPlayerSlot: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: IOSNav
    @Environment(\.horizontalSizeClass) private var sizeClass
    let tab: IOSTab

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if sizeClass == .regular, nav.tab == tab, let item = model.pinned, model.nowPlaying == nil {
                IOSPinnedPlayer(item: item, game: model.pinnedGame)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    func pinnedPlayerSlot(_ tab: IOSTab) -> some View { modifier(PinnedPlayerSlot(tab: tab)) }
}
