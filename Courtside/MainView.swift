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
    /// The window's size, so the player can be capped at half of it.
    @State private var windowSize = CGSize(width: 1400, height: 900)
    /// What's typed in the top bar's filter box (EPG and game screens); cleared when you move on.
    @State private var filter = ""
    @State private var route: Route = .home
    @State private var openGameID: String?
    /// The sport picked in Home's left column; nil means "All sports".
    @State private var selectedSport: Sport?
    @State private var selectedLeague: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(route: route, onBack: onHome && openGameID != nil ? { openGameID = nil } : nil,
                       filter: showsFilter ? $filter : nil) { navigate(to: $0) }
                // The pinned player: only while something is playing, in the same spot on every screen.
                if let item = model.pinned {
                    // No score beside the video: the broadcast already shows it.
                    PinnedPlayerBar(item: item, hidden: model.nowPlaying != nil, game: nil,
                                    maxVideoHeight: min(windowSize.height * 0.5, windowSize.width * 0.45 * 9 / 16))
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .onChange(of: route) { filter = "" }
        .onChange(of: openGameID) { filter = "" }
        .onReceive(NotificationCenter.default.publisher(for: .openGame)) { note in
            guard let id = note.object as? String, let game = model.games.first(where: { $0.id == id }) else { return }
            selectedSport = game.league.sport
            selectedLeague = nil
            route = .home
            openGameID = id
        }
    }

    /// The filter box in the top bar shows on the EPG and on game screens.
    private var showsFilter: Bool { route == .guide || (onHome && openGameID != nil) }

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
                GameDetailView(search: $filter, game: game) {
                    openGameID = nil
                }
            } else {
                DashboardView(selectedSport: $selectedSport, selectedLeague: $selectedLeague) { game in
                    openGameID = game.id
                }
            }
        case .guide:
            GuideView(categorySearch: $filter) { gameID in
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
    /// Set on a game screen: a back arrow on the left.
    var onBack: (() -> Void)? = nil
    /// Set on the EPG and game screens: the filter box, on the right.
    var filter: Binding<String>? = nil
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

            // Left (after the window buttons): back, connections in use, and "EPG 9:10 PM ⟳" (refresh).
            HStack(spacing: 10) {
                Spacer().frame(width: 78)
                if let onBack {
                    RoundIconButton(symbol: "chevron.left", help: "Back (⌘[)", action: onBack)
                        .keyboardShortcut("[", modifiers: .command)
                }
                ConnectionsPill(account: model.account)
                if let saved = model.savedAt, !model.downloadingChannels {
                    EPGRefreshButton(date: saved) { Task { await model.refresh(force: true) } }
                }
                Spacer()
                if let filter {
                    Field(placeholder: "Filter", text: filter)
                        .frame(width: 220)
                }
                status
                // The version is the update button: click it to check for a new version; once one has
                // downloaded it turns into "Restart to update".
                if case .ready(let version) = updater.state {
                    UpdateReadyButton(version: version) { updater.restartToUpdate() }
                        .padding(.trailing, 20)
                } else {
                    VersionButton(updater: updater)
                        .padding(.trailing, 20)
                }
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
        }
    }
}

/// "v1.39 ⟳": checks for a newer Courtside.
struct VersionButton: View {
    @ObservedObject var updater: AppUpdater
    @State private var hovering = false

    private var symbol: String {
        switch updater.state {
        case .checking, .downloading: return "hourglass"
        default: return "arrow.clockwise"
        }
    }

    var body: some View {
        Button {
            Task { await updater.check(userInitiated: true) }
        } label: {
            HStack(spacing: 6) {
                Text("v\(updater.currentVersion)")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? Theme.raised : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help({
            if case .downloading(let v) = updater.state { return "Downloading version \(v)…" }
            if case .failed(let m) = updater.state { return m }
            return "Check for a new version"
        }())
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

/// "EPG 9:10 PM ⟳": when the channels and guide were last downloaded; click to download them again now.
struct EPGRefreshButton: View {
    let date: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("EPG " + (Calendar.current.isDateInToday(date)
                               ? date.formatted(date: .omitted, time: .shortened)
                               : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? Theme.raised : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Download channels and the guide again now")
    }
}
