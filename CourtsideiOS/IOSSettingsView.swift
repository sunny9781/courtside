import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.showFinished) private var showFinished = true
    @AppStorage(Prefs.guidePreview) private var guidePreview = true
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.hiddenLeagues) private var hiddenLeagues = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    @AppStorage(Prefs.sportOrder) private var sportOrderPref = ""
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @AppStorage(Prefs.hideAdult) private var hideAdult = true
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    /// Updates open in What's new: only the newest to start with.
    @State private var openReleases: Set<String> = Set(Changelog.forThisApp.prefix(1).map(\.id))
    @State private var confirmSignOut = false
    @State private var castNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: model.credentials?.username ?? "")
                    LabeledContent("Status", value: model.account?.status ?? "–")
                    LabeledContent("Expires", value: model.account?.expires?.formatted(date: .long, time: .omitted) ?? "No expiry date")
                    LabeledContent("Connections", value: connections)
                    HStack {
                        Spacer()
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    }
                }

                Section {
                    Toggle("Switch to the next stream when one stalls", isOn: $autoSwitch)
                    if UserDefaults.standard.bool(forKey: CastManager.disabledKey) {
                        Button("Turn Chromecast back on") {
                            CastManager.enableAgain()
                            castNote = "Chromecast comes back the next time Courtside opens."
                        }
                        Text(castNote ?? "Chromecast was turned off because it made Courtside close while starting.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    Picker("Buffer", selection: $bufferMs) {
                        Text("1 s").tag(1000)
                        Text("2 s").tag(2000)
                        Text("3 s").tag(3000)
                        Text("5 s").tag(5000)
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("USA and Canada streams are tried first when switching. More buffer means fewer stalls but a longer delay behind live.")
                }

                Section {
                    ForEach(Sport.ordered(sportOrderPref)) { sport in
                        sportRow(sport)
                    }
                    .onMove { from, to in
                        var order = Sport.ordered(sportOrderPref)
                        order.move(fromOffsets: from, toOffset: to)
                        sportOrderPref = Sport.encode(order)
                    }
                } header: {
                    Text("Sports")
                } footer: {
                    Text("Tap a sport for its leagues. Switch one off to hide it; the heart keeps it first on Home. Tap Edit to reorder.")
                }

                Section("Games") {
                    Toggle("Show finished games", isOn: $showFinished)
                    Toggle("Hide SD streams", isOn: $hideSD)
                }

                Section("EPG") {
                    Toggle("Hide adult categories", isOn: Binding(
                        get: { hideAdult },
                        set: { hideAdult = $0; Task { await model.applyFilters(); await model.rematch() } }
                    ))
                    Toggle("Group similar categories", isOn: $grouped)
                }

                Section {
                    Picker("Download fresh channels after", selection: $refreshHours) {
                        Text("1 h").tag(1)
                        Text("3 h").tag(3)
                        Text("6 h").tag(6)
                        Text("12 h").tag(12)
                        Text("24 h").tag(24)
                    }
                    Button(model.downloadingChannels ? "Downloading…" : "Refresh now") {
                        Task { await model.refresh(force: true) }
                    }
                    .disabled(model.downloadingChannels)
                    LabeledContent("Version", value: version)
                } header: {
                    Text("Updates")
                } footer: {
                    if let saved = model.savedAt {
                        Text("Channels and guide last downloaded \(saved.formatted(date: .abbreviated, time: .shortened)). Scores update every minute.")
                    }
                }

                Section("What's new") {
                    ForEach(Array(Changelog.forThisApp.enumerated()), id: \.element.id) { index, release in
                        DisclosureGroup(isExpanded: Binding(
                            get: { openReleases.contains(release.id) },
                            set: { isOpen in
                                if isOpen { openReleases.insert(release.id) } else { openReleases.remove(release.id) }
                            })) {
                            ForEach(release.changes, id: \.self) { change in
                                Label {
                                    Text(change.text).font(.subheadline).foregroundStyle(Theme.soft)
                                } icon: {
                                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(release.title).font(.subheadline.weight(.semibold))
                                Text(index == 0 ? "Latest · \(release.dateLabel)" : release.dateLabel)
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { EditButton() }
            .confirmationDialog("Sign out of Courtside?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
        }
    }

    private func sportRow(_ sport: Sport) -> some View {
        let hidden = Sport.hidden(hiddenSports).contains(sport)
        let favorite = favorites.contains(sport)
        return HStack {
            Button {
                toggleFavorite(sport)
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.borderless)

            if sport.leagues.count > 1 {
                NavigationLink {
                    leagueList(sport)
                } label: {
                    Label(sport.rawValue, systemImage: sport.symbol)
                }
            } else {
                Label(sport.rawValue, systemImage: sport.symbol)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { !hidden }, set: { setHidden(sport, !$0) }))
                .labelsHidden()
        }
    }

    private func leagueList(_ sport: Sport) -> some View {
        Form {
            ForEach(sport.leagues) { league in
                Toggle(isOn: Binding(
                    get: { !League.hidden(hiddenLeagues).contains(league.id) },
                    set: { setLeagueHidden(league, !$0) }
                )) {
                    HStack {
                        IOSLeagueLogo(league: league, size: 24)
                        Text(league.name)
                    }
                }
            }
        }
        .navigationTitle(sport.rawValue)
    }

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

struct IOSLoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 60)
                Text("Courtside").font(.largeTitle.bold()).foregroundStyle(Theme.text)
                Text("Sign in with your IPTV provider's Xtream Codes login.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    field("Server, for example http://example.com:8080", text: $server)
                        .keyboardType(.URL)
                    field("Username", text: $username)
                    SecureField("Password", text: $password)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        working = true
                        error = await model.signIn(server: server.trimmingCharacters(in: .whitespaces),
                                                   username: username.trimmingCharacters(in: .whitespaces),
                                                   password: password)
                        working = false
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(Theme.onAccent) }
                        Text(working ? "Signing in…" : "Sign in").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(Theme.onAccent)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                }
                .disabled(working || server.isEmpty || username.isEmpty || password.isEmpty)
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}
