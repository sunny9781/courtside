import SwiftUI

/// Settings, laid out like the Mac: sections down the left, the selected section on the right.
struct TVSettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @AppStorage(Prefs.matchFrameRate) private var matchFrameRate = true
    @AppStorage(Prefs.hideAdult) private var hideAdult = true
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.showFinished) private var showFinished = true
    @AppStorage(Prefs.guidePreview) private var guidePreview = true
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.hiddenLeagues) private var hiddenLeagues = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @State private var section: Section = .account
    @State private var openSport: Sport?
    @State private var confirmSignOut = false
    @FocusState private var focusedSection: Section?

    enum Section: String, CaseIterable, Identifiable {
        case account = "Account"
        case playback = "Playback"
        case sports = "Sports"
        case games = "Games"
        case epg = "EPG"
        case updates = "Updates"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .playback: return "play.rectangle"
            case .sports: return "sportscourt"
            case .games: return "list.bullet.rectangle"
            case .epg: return "tv"
            case .updates: return "arrow.clockwise"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 26))
                                .frame(width: 40)
                            Text(item.rawValue)
                                .font(.system(size: 28, weight: .semibold))
                            Spacer()
                        }
                    }
                    .buttonStyle(TVRowButtonStyle(selected: section == item))
                    .focused($focusedSection, equals: item)
                }
                Spacer()
            }
            .padding(.vertical, 20)
            .frame(width: TVLayout.sidebar)
            .focusSection()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.rawValue)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Changes save automatically")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 16)
                    content
                }
                .padding(.vertical, 20)
                .frame(maxWidth: 1000, alignment: .leading)
            }
            .focusSection()
        }
        .padding(.horizontal, TVLayout.margin)
        .onChange(of: focusedSection) {
            if let focusedSection { section = focusedSection }
        }
        .confirmationDialog("Sign out of Courtside?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .account:
            info("Username", model.credentials?.username ?? "")
            info("Status", model.account?.status ?? "–")
            info("Expires", model.account?.expires?.formatted(date: .long, time: .omitted) ?? "No expiry date")
            info("Connections", connections)
            action("Sign out", detail: nil, destructive: true) { confirmSignOut = true }
                .padding(.top, 20)

        case .playback:
            toggle("Switch to the next stream when one stalls", detail: "USA and Canada streams are tried first.", $autoSwitch)
            toggle("Match frame rate",
                   detail: DisplayMatcher.systemAllows
                       ? "Switches your TV to each stream's frame rate (50 or 60 fps) for smoother motion."
                       : "Also turn on Settings › Video and Audio › Match Content › Match Frame Rate on the Apple TV.",
                   $matchFrameRate)
            toggle("Mini player", detail: "Click a stream once to play it in the mini player, again for full screen.", $guidePreview)
            action("Buffer", detail: "More buffer means fewer stalls but a longer delay behind live.",
                   value: "\(bufferMs / 1000) s") {
                bufferMs = next(after: bufferMs, in: [1000, 2000, 3000, 5000])
            }

        case .sports:
            Text("Click a sport to show or hide it, or the heart to keep it first on Home. Open a sport to switch its leagues on or off.")
                .font(.system(size: 21))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 10)
            ForEach(Sport.ordered(UserDefaults.standard.string(forKey: Prefs.sportOrder) ?? "")) { sport in
                sportRow(sport)
                if openSport == sport {
                    ForEach(sport.leagues) { league in
                        leagueRow(league, sportHidden: Sport.hidden(hiddenSports).contains(sport))
                    }
                }
            }

        case .games:
            toggle("Show finished games", detail: nil, $showFinished)
            toggle("Hide SD streams", detail: "Most providers have HD versions of the same channels.", $hideSD)

        case .epg:
            toggle("Hide adult categories", detail: "Any category with \"adult\" in its name, and its channels.", Binding(
                get: { hideAdult },
                set: { hideAdult = $0; Task { await model.applyFilters(); await model.rematch() } }
            ))
            toggle("Group similar categories", detail: "Sports, Country, 24/7 and so on, opened one level at a time.", $grouped)

        case .updates:
            action("Download fresh channels and guide after",
                   detail: "Opening the app reuses the saved channels and guide until they're this old. Scores always update every minute.",
                   value: "\(refreshHours) h") {
                refreshHours = next(after: refreshHours, in: [1, 3, 6, 12, 24])
            }
            action("Refresh now", detail: model.savedAt.map { "Last downloaded \($0.formatted(date: .abbreviated, time: .shortened))" },
                   value: model.downloadingChannels ? "Downloading…" : nil) {
                Task { await model.refresh(force: true) }
            }
            info("Version", version)
            Text("Your Mac installs updates automatically when it's awake and on the same Wi-Fi.")
                .font(.system(size: 20))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
    }

    // MARK: Rows

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).foregroundStyle(Theme.text)
        }
        .font(.system(size: 26))
        .padding(.horizontal, 22)
        .frame(minHeight: 64)
    }

    private func toggle(_ title: String, detail: String?, _ value: Binding<Bool>) -> some View {
        Button {
            value.wrappedValue.toggle()
        } label: {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 26, weight: .medium))
                    if let detail {
                        Text(detail).font(.system(size: 19)).opacity(0.6)
                    }
                }
                Spacer()
                Text(value.wrappedValue ? "On" : "Off")
                    .font(.system(size: 24, weight: .semibold))
                    .opacity(0.8)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(TVRowButtonStyle())
    }

    private func action(_ title: String, detail: String?, value: String? = nil, destructive: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(destructive ? Theme.danger : Color.primary)
                    if let detail {
                        Text(detail).font(.system(size: 19)).opacity(0.6)
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 24, weight: .semibold))
                        .opacity(0.8)
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(TVRowButtonStyle())
    }

    private func sportRow(_ sport: Sport) -> some View {
        let hidden = Sport.hidden(hiddenSports).contains(sport)
        let favorite = favorites.contains(sport)
        return HStack(spacing: 16) {
            Button {
                setHidden(sport, !hidden)
            } label: {
                HStack(spacing: 18) {
                    Image(systemName: sport.symbol)
                        .font(.system(size: 26))
                        .frame(width: 40)
                    Text(sport.rawValue)
                        .font(.system(size: 26, weight: .medium))
                    Spacer()
                    Text(hidden ? "Hidden" : "Shown")
                        .font(.system(size: 22, weight: .semibold))
                        .opacity(hidden ? 0.5 : 0.8)
                }
            }
            .buttonStyle(TVRowButtonStyle())

            Button {
                toggleFavorite(sport)
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(favorite ? Theme.accent : Theme.muted)
            }
            .buttonStyle(TVPillButtonStyle())

            if sport.leagues.count > 1 {
                Button {
                    openSport = openSport == sport ? nil : sport
                } label: {
                    Image(systemName: openSport == sport ? "chevron.up" : "chevron.down")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(TVPillButtonStyle())
            } else {
                Color.clear.frame(width: 76, height: 60)
            }
        }
        .opacity(hidden ? 0.7 : 1)
    }

    private func leagueRow(_ league: League, sportHidden: Bool) -> some View {
        let hidden = League.hidden(hiddenLeagues).contains(league.id)
        return Button {
            setLeagueHidden(league, !hidden)
        } label: {
            HStack(spacing: 16) {
                TVLeagueLogo(league: league, size: 36)
                Text(league.name).font(.system(size: 23))
                Spacer()
                Text(hidden ? "Hidden" : "Shown")
                    .font(.system(size: 21, weight: .semibold))
                    .opacity(hidden ? 0.5 : 0.8)
            }
            .padding(.leading, 56)
        }
        .buttonStyle(TVRowButtonStyle())
        .disabled(sportHidden)
        .padding(.trailing, 184)
    }

    // MARK: Helpers

    private var connections: String {
        guard let max = model.account?.maxConnections else { return "–" }
        return "\(model.account?.activeConnections ?? 0) of \(max) in use"
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(v) (\(b))"
    }

    private var favorites: Set<Sport> {
        Set(favoriteSports.split(separator: ",").compactMap { Sport(rawValue: String($0)) })
    }

    private func next(after value: Int, in list: [Int]) -> Int {
        guard let i = list.firstIndex(of: value) else { return list[0] }
        return list[(i + 1) % list.count]
    }

    private func setHidden(_ sport: Sport, _ hide: Bool) {
        var set = Sport.hidden(hiddenSports)
        if hide { set.insert(sport) } else { set.remove(sport) }
        hiddenSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func setLeagueHidden(_ league: League, _ hide: Bool) {
        var set = League.hidden(hiddenLeagues)
        if hide { set.insert(league.id) } else { set.remove(league.id) }
        hiddenLeagues = League.all.filter { set.contains($0.id) }.map(\.id).joined(separator: ",")
        model.applyLeagueFilter()
    }

    private func toggleFavorite(_ sport: Sport) {
        var set = favorites
        if set.contains(sport) { set.remove(sport) } else { set.insert(sport) }
        favoriteSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}
