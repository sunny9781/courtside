import SwiftUI
import UIKit

@main
struct CourtsideiOSApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var nav = IOSNav()

    init() {
        Prefs.register()
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
            // Apple's player for Picture in Picture lives here, behind everything, so it's always on screen.
            PiPLayerHost()
                .ignoresSafeArea()
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
    @ObservedObject private var pip = PiPManager.shared
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
                // Leaving the app or locking the phone stops the sound, unless Picture in Picture is showing.
                if !pip.active {
                    model.closePlayer()
                    PlaybackController.shared.stop()
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            // The phone locked: no sound while locked, not even from Picture in Picture.
            pip.stop()
            PlaybackController.shared.stop()
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
        .overlay(alignment: .bottom) {
            if let message = pip.message ?? model.notice {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.raised))
                    .padding(.bottom, 70)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        pip.message = nil
                        model.notice = nil
                    }
            }
        }
    }
}
