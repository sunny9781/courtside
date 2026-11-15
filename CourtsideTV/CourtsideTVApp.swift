import SwiftUI

@main
struct CourtsideTVApp: App {
    @StateObject private var model = AppModel()

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            Text("Courtside")
                .environmentObject(model)
        }
    }
}
