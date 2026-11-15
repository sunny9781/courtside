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

    var body: some View {
        TabView(selection: $nav.tab) {
            IOSHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(IOSTab.home)
            IOSEPGView()
                .tabItem { Label("EPG", systemImage: "tv") }
                .tag(IOSTab.epg)
            IOSSettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(IOSTab.settings)
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task { await model.refresh() }
            case .background:
                // Leaving the app stops the sound unless it went into Picture in Picture (which starts on its own
                // as you swipe up). Checked a moment later so Picture in Picture has time to start.
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if scenePhase == .background, !playback.av.pipActive, !playback.av.pipStarting {
                        playback.stop()
                        model.closePlayer()
                    }
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            // The phone locked: no sound while locked, not even from Picture in Picture.
            playback.stop()
            model.closePlayer()
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
        .onChange(of: nav.tab) {
            // Switching tabs keeps the mini player's stream going; the next screen's mini player picks it up.
            model.backgroundChannel = playback.isActive && model.nowPlaying == nil ? model.previewChannel : nil
        }
        .onAppear {
            // Picture in Picture: "back to app" reopens full screen; closing the floating window stops it.
            playback.av.onPiPRestore = { [weak model] in
                guard let model, model.nowPlaying == nil, let channel = model.previewChannel else { return }
                model.play(channel, lineup: [channel])
            }
            playback.av.onPiPClosed = { [weak model] in
                IOSPlayback.shared.stop()
                model?.closePlayer()
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
}
