import SwiftUI
import AppKit

enum Route: Hashable {
    case home
    case sport(Sport)
    case guide
    case settings
}

/// Top bar plus the selected screen, with the player covering everything when a stream is open.
struct ShellView: View {
    @EnvironmentObject var model: AppModel
    @State private var route: Route = .home
    @State private var openGameID: String?
    /// The sport picked in Home's left column; nil means "All sports".
    @State private var selectedSport: Sport?
    @State private var selectedLeague: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(route: route, onBack: onHome && openGameID != nil ? { openGameID = nil } : nil) { navigate(to: $0) }
                // The pinned player: only while something is playing, in the same spot on every screen.
                if let item = model.pinned {
                    PinnedPlayerBar(item: item, hidden: model.nowPlaying != nil, game: pinnedGame)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.bg)
            .ignoresSafeArea()

            if let item = model.nowPlaying {
                PlayerView(item: item)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.nowPlaying)
        .animation(.easeOut(duration: 0.25), value: model.pinned == nil)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.raised))
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        model.notice = nil
                    }
            }
        }
        .task {
            await model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGame)) { note in
            guard let id = note.object as? String, let game = model.games.first(where: { $0.id == id }) else { return }
            selectedSport = game.league.sport
            selectedLeague = nil
            route = .home
            openGameID = id
        }
    }

    /// The game the player's stream was started from, so its score stays in the player strip on every screen
    /// (EPG and Settings too) for as long as that stream plays.
    private var pinnedGame: Game? {
        guard let item = model.pinned, let title = item.gameTitle else { return nil }
        if onHome, let id = openGameID, model.pinnedIsFrom(gameID: id) {
            return model.games.first { $0.id == id }
        }
        return model.games.first { $0.title == title && model.pinnedIsFrom(gameID: $0.id) }
    }

    private var onHome: Bool {
        if case .sport = route { return true }
        return route == .home
    }

    /// Tabs keep their place: an open game stays open, and whatever the mini player is playing keeps going
    /// in the background. Clicking Home while already on Home goes back to the overview.
    private func navigate(to target: Route) {
        let goingHome = target == .home
        if goingHome && onHome {
            openGameID = nil
            return
        }
        if target == route { return }
        route = target
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .home, .sport:
            if let id = openGameID, let game = model.games.first(where: { $0.id == id }) {
                GameDetailView(game: game) {
                    openGameID = nil
                }
            } else {
                DashboardView(selectedSport: $selectedSport, selectedLeague: $selectedLeague) { game in
                    openGameID = game.id
                }
            }
        case .guide:
            GuideView { gameID in
                if let game = model.games.first(where: { $0.id == gameID }) {
                    selectedSport = game.league.sport
                    selectedLeague = nil
                    route = .home
                    openGameID = gameID
                }
            }
        case .settings:
            SettingsView()
        }
    }
}

/// Along the top: Courtside (home and sports), Live TV (the guide) and Settings.
/// It sits in the window's title bar area, so it leaves room for the window buttons on the left.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared
    let route: Route
    /// Set on a game screen: a back arrow left of the connection count.
    var onBack: (() -> Void)? = nil
    let onNavigate: (Route) -> Void

    private var onHome: Bool {
        if case .sport = route { return true }
        return route == .home
    }

    var body: some View {
        ZStack {
            // Tabs in the middle of the bar.
            HStack(spacing: 10) {
                TopTab(title: "Home", symbol: nil, selected: onHome) { go(.home) }
                TopTab(title: "EPG", symbol: "tv", selected: route == .guide) { go(.guide) }
                TopTab(title: "Settings", symbol: "slider.horizontal.3", selected: route == .settings) { go(.settings) }
            }

            // Back on the left (after the window buttons), refresh status on the right.
            HStack(spacing: 10) {
                if let onBack {
                    RoundIconButton(symbol: "chevron.left", help: "Back (⌘[)", action: onBack)
                        .keyboardShortcut("[", modifiers: .command)
                        .padding(.leading, 88)
                }
                Spacer()
                if case .ready(let version) = updater.state {
                    UpdateReadyButton(version: version) { updater.restartToUpdate() }
                }
                status
                    .padding(.trailing, 20)
            }
        }
        .frame(height: 64)
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.raised).frame(height: 1)
        }
        .onAppear {
            // Lets you drag the window by the bar's empty space, like a normal title bar.
            NSApp.windows.forEach { $0.isMovableByWindowBackground = true }
        }
    }

    private func go(_ target: Route) {
        onNavigate(target)
    }

    /// "Updated 1:15 PM" is itself the refresh button. It shows when the channels and guide were last
    /// downloaded (scores update on their own every minute), and a spinner only while that download runs.
    @ViewBuilder
    private var status: some View {
        if model.downloadingChannels {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading channels…")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
        } else if let note = model.guideStatus {
            Label(note, systemImage: "tablecells")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        } else if let saved = model.savedAt {
            UpdatedButton(date: saved) {
                Task { await model.refresh(force: true) }
            }
        }
    }
}

/// "1/2": streams in use on the IPTV account right now, out of how many it allows. Orange at the limit.
struct ConnectionsPill: View {
    let account: AccountInfo?

    var body: some View {
        if let max = account?.maxConnections, max > 0 {
            let active = account?.activeConnections ?? 0
            let full = active >= max
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(active)/\(max)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(full ? Theme.onAccent : Theme.muted)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(full ? Theme.accent : Theme.raised))
            .help(full ? "All \(max) connections on your account are in use"
                       : "\(active) of \(max) connections on your account in use")
        }
    }
}

/// Shows when a new version has downloaded; clicking it restarts into the new version.
struct UpdateReadyButton: View {
    let version: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Restart to update")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Theme.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Version \(version) is ready")
    }
}

struct UpdatedButton: View {
    let date: Date
    let action: () -> Void
    @State private var hovering = false

    private var text: String {
        Calendar.current.isDateInToday(date)
            ? "Updated \(date.formatted(date: .omitted, time: .shortened))"
            : "Updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? Theme.raised : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Download channels, guide and scores now")
    }
}

struct TopTab: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accent : Theme.soft)
                }
                Text(title)
                    .font(.system(size: 17, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.soft)
            }
            .padding(.horizontal, 22)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Theme.raised : (hovering ? Theme.card : Color.clear)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension Notification.Name {
    /// Open a game's screen (object: the game's id), e.g. from the player strip.
    static let openGame = Notification.Name("openGame")
}
