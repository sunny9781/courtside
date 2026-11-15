import SwiftUI

@main
struct CourtsideApp: App {
    @StateObject private var model = AppModel()

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(.dark)
                .task { AppUpdater.shared.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)

        // The pinned player popped out into its own window.
        Window("Player", id: PopOutPlayer.windowID) {
            PopOutPlayer()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 960, height: 540)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.credentials == nil {
            LoginView()
        } else {
            ShellView()
        }
    }
}
