import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.guideHours) private var guideHours = 6
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = false
    @AppStorage(Prefs.guidePreview) private var guidePreview = true
    @AppStorage(Prefs.sportOrder) private var sportOrder = ""
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.hiddenLeagues) private var hiddenLeagues = ""
    @AppStorage(Prefs.multiview) private var multiview = true
    @AppStorage(Prefs.multiviewSelect) private var multiviewSelect = "big"
    @State private var section: SettingsSection = .account
    @State private var openSport: Sport?
    @State private var editingAccount = false

    enum SettingsSection: String, CaseIterable, Identifiable {
        // The same sections as on the TVs.
        case account = "Account"
        /// A SOCKS5 / HTTPS / HTTP proxy for the provider's traffic (2.33).
        case proxy = "Proxy"
        case playback = "Playback"
        case general = "General"
        /// Sports and leagues switched off, and hidden categories and channels.
        case hidden = "Hidden"
        case changelog = "Changelog"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .proxy: return "network.badge.shield.half.filled"
            case .playback: return "play.rectangle"
            case .general: return "slider.horizontal.3"
            case .hidden: return "eye.slash"
            case .changelog: return "sparkles"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sections down the left, like Home.
            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { item in
                    SportRow(symbol: item.symbol, name: item.rawValue, detail: nil, live: 0,
                             selected: section == item, dimmed: false, favorite: nil) {
                        section = item
                    }
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 230)
            .frame(maxHeight: .infinity)
            .background(Theme.sidebar)

            Rectangle().fill(Theme.raised).frame(width: 1)

            ScrollView {
                // The section is highlighted on the left, so its name isn't repeated here.
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editingAccount) {
            LoginView(editing: model.credentials) { editingAccount = false }
                .environmentObject(model)
                .frame(width: 560, height: 420)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .account:
            panel("Your provider") {
                row("Server", host)
                row("Username", model.credentials?.username ?? "")
                row("Status", model.account?.status ?? "–")
                row("Expires", model.account?.expires?.formatted(date: .long, time: .omitted) ?? "No expiry date")
                row("Connections", connections)
                HStack {
                    Button("Edit account") { editingAccount = true }
                        .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button("Sign out") { model.signOut() }
                        .buttonStyle(GhostButtonStyle(tint: Theme.danger))
                }
            }

        case .proxy:
            MacProxyPanel()

        case .hidden:
            panel("Sports and leagues") {
                Text("Order of the sports on Home (you can also drag them there). Switch a sport or league off to hide it. Click a sport to see its leagues.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                let order = Sport.ordered(sportOrder)
                VStack(spacing: 6) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, sport in
                        sportRow(sport, index: index, count: order.count)
                        if openSport == sport && sport.leagues.count > 1 {
                            ForEach(sport.leagues) { league in
                                leagueRow(league, sportHidden: Sport.hidden(hiddenSports).contains(sport))
                            }
                        }
                    }
                }
            }

            // Categories and channels hidden in the EPG (categories with "adult" in the name start out here).
            panel("Categories and channels") {
                let cats = model.hiddenCategoryNames
                let chans = model.hiddenChannelNames
                if cats.isEmpty && chans.isEmpty {
                    Text("Nothing hidden. Right-click a category or channel in the EPG to hide it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Categories with \"adult\" in the name start out here. Show one to bring it back.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(cats, id: \.id) { item in
                    hiddenRow(item.name, icon: "folder") { model.setCategoryHidden(item.id, false) }
                }
                ForEach(chans, id: \.id) { item in
                    hiddenRow(item.name, icon: "tv") { model.setChannelHidden(item.id, false) }
                }
            }


        case .playback:
            panel("Player") {
                setting("Buffer", "More buffer means fewer stalls but a longer delay behind live.") {
                    Picker("", selection: $bufferMs) {
                        Text("1 s").tag(1000)
                        Text("2 s").tag(2000)
                        Text("3 s").tag(3000)
                        Text("5 s").tag(5000)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                toggle("Switch to the next stream when one stalls (USA and Canada first)", $autoSwitch)
                toggle("Mini player previews (EPG and game screens)", $guidePreview)
                engineNote
            }

            // 2.44, like the TVs: two streams side by side.
            panel("Multiview") {
                toggle("Watch alongside (right-click a stream, a game or an EPG channel while something plays)", $multiview)
                if multiview {
                    setting("Clicking a tile", multiviewSelect == "sound"
                            ? "Moves the sound there; the tiles stay the same size."
                            : "Moves the sound there and makes it big; again goes back to side by side.") {
                        Picker("", selection: $multiviewSelect) {
                            Text("Make big").tag("big")
                            Text("Move sound only").tag("sound")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                }
            }

            panel("Games") {
                toggle("Hide SD streams", $hideSD)
            }

        case .general:
            panel("EPG") {
                setting("Hours to show", "How far ahead the guide goes. Takes effect on the next refresh.") {
                    Picker("", selection: $guideHours) {
                        Text("4").tag(4)
                        Text("6").tag(6)
                        Text("8").tag(8)
                        Text("12").tag(12)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }

            panel("Updates") {
                setting("Channels and guide", "Download at 3 PM, 9 PM, 3 AM and 9 AM (after the stream, if one is playing). Scores always update every minute.") {
                    EmptyView()
                }
                HStack {
                    Text(model.savedAt.map { "Last downloaded \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not downloaded yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button(model.downloadingChannels ? "Downloading…" : "Refresh now") {
                        Task { await model.refresh(force: true) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.downloadingChannels)
                }
            }
            ConnectionLogPanel()
            AppVersionPanel()

        case .changelog:
            panel("Changelog") {
                WhatsNewList()
            }
        }
    }

    private func sportRow(_ sport: Sport, index: Int, count: Int) -> some View {
        let hidden = Sport.hidden(hiddenSports).contains(sport)
        return HStack(spacing: 12) {
            Button {
                openSport = openSport == sport ? nil : sport
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: sport.leagues.count > 1 ? (openSport == sport ? "chevron.down" : "chevron.right") : "circle.fill")
                        .font(.system(size: sport.leagues.count > 1 ? 11 : 4, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 14)
                    Image(systemName: sport.symbol)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    Text(sport.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hidden ? Theme.muted : Theme.text)
                    Spacer()
                }
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sport.leagues.count > 1 ? "Show its leagues" : "")

            Toggle("", isOn: Binding(
                get: { !hidden },
                set: { show in setHidden(sport, !show) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)
            .help("Show or hide this sport")
            Button { moveSport(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(IconButtonStyle())
                .disabled(index == 0)
            Button { moveSport(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle())
                .disabled(index == count - 1)
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised.opacity(0.5)))
    }

    private func leagueRow(_ league: League, sportHidden: Bool) -> some View {
        let hidden = League.hidden(hiddenLeagues).contains(league.id)
        return HStack(spacing: 12) {
            LeagueLogo(league: league, size: 22)
            Text(league.name)
                .font(.system(size: 13))
                .foregroundStyle(hidden || sportHidden ? Theme.muted : Theme.soft)
            Spacer()
            Toggle("", isOn: Binding(
                get: { !hidden },
                set: { show in setLeagueHidden(league, !show) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)
            .disabled(sportHidden)
            .help(sportHidden ? "Turn the sport on first" : "Show or hide this league")
        }
        .padding(.leading, 64)
        .padding(.trailing, 12)
        .frame(height: 40)
    }

    private func setLeagueHidden(_ league: League, _ hide: Bool) {
        var set = League.hidden(hiddenLeagues)
        if hide { set.insert(league.id) } else { set.remove(league.id) }
        hiddenLeagues = League.all.map(\.id).filter { set.contains($0) }.joined(separator: ",")
        model.applyLeagueFilter()
    }

    private func setHidden(_ sport: Sport, _ hide: Bool) {
        var set = Sport.hidden(hiddenSports)
        if hide { set.insert(sport) } else { set.remove(sport) }
        hiddenSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func moveSport(_ index: Int, by delta: Int) {
        var order = Sport.ordered(sportOrder)
        let target = index + delta
        guard order.indices.contains(index), order.indices.contains(target) else { return }
        order.swapAt(index, target)
        sportOrder = Sport.encode(order)
    }

    private var host: String {
        guard let server = model.credentials?.server else { return "" }
        let withScheme = server.contains("://") ? server : "http://" + server
        return URL(string: withScheme)?.host ?? server
    }

    private var connections: String {
        guard let max = model.account?.maxConnections else { return "–" }
        let active = model.account?.activeConnections.map(String.init) ?? "?"
        return "\(active) of \(max) in use"
    }

    @ViewBuilder
    private var engineNote: some View {
        if PlaybackController.usesVLC {
            Text("Built-in player engine: VLC. Plays nearly every stream format.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        } else {
            Banner(text: "Built-in player engine: Apple. Many Xtream streams won't play with it. Add the VLCKit package in Xcode to switch to VLC.",
                   icon: "info.circle.fill")
        }
    }

    // MARK: Pieces

    private func hiddenRow(_ name: String, icon: String, show: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.muted).frame(width: 18)
            Text(name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            Button("Show", action: show).buttonStyle(GhostButtonStyle())
        }
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(Theme.display(18))
                .foregroundStyle(Theme.text)
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
        }
        .font(.system(size: 14))
    }

    private func setting<Control: View>(_ label: String, _ help: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(help)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
                .labelsHidden()
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }
}


/// Settings › Updates: which version this is, and checking for a newer one.
struct AppVersionPanel: View {
    @ObservedObject private var updater = AppUpdater.shared

    private var statusText: String {
        switch updater.state {
        case .idle, .checking:
            if case .checking = updater.state { return "Checking…" }
            if updater.isDevelopmentBuild { return "Built in Xcode, so it doesn't update itself" }
            return updater.lastChecked.map { "Checked \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        case .upToDate: return "Up to date"
        case .downloading(let v): return "Downloading version \(v)…"
        case .ready(let v): return "Version \(v) is ready"
        case .failed(let message): return message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App version")
                .font(Theme.display(18))
                .foregroundStyle(Theme.text)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Courtside \(updater.currentVersion)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if updater.isReady {
                    Button("Restart to update") { updater.restartToUpdate() }
                        .buttonStyle(AccentButtonStyle())
                } else {
                    Button("Check for updates") {
                        Task { await updater.check(userInitiated: true) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(updater.state == .checking)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}

/// What used a connection to the provider, newest first: to see what caused 2/2 when only one thing plays.
struct ConnectionLogPanel: View {
    @ObservedObject private var log = ConnLog.shared
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection log")
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.text)
                    Text("Streams opened and closed, downloads, and what the provider said was in use.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(open ? "Hide" : "Show") { open.toggle() }
                    .buttonStyle(GhostButtonStyle())
            }
            if open {
                if log.entries.isEmpty {
                    Text("Nothing yet.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                ForEach(Array(log.entries.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.soft)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}
