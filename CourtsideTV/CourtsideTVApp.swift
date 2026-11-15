import SwiftUI

@main
struct CourtsideTVApp: App {
    @StateObject private var model = AppModel()

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
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

/// Home, Live TV and Settings along the top (Apple TV's own tab bar), and the player over everything.
struct TVShell: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TVHomeView()
                .tabItem { Label("Home", systemImage: "basketball.fill") }
            TVLiveView()
                .tabItem { Label("EPG", systemImage: "tv") }
            TVSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) {
            // Coming back to the app: scores update, channels only if the saved copy is old.
            if scenePhase == .active { Task { await model.refresh() } }
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
}
