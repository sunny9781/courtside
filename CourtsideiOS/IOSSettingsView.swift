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
    @AppStorage(Prefs.refreshHours) private var refreshHours = 12
    @AppStorage(Prefs.hideAdult) private var hideAdult = true
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    /// Updates open in What's new: only the newest to start with.
    @State private var openReleases: Set<String> = Set(Changelog.forThisApp.prefix(1).map(\.id))
    @State private var confirmSignOut = false
    @State private var castNote: String?
    @State private var editingAccount = false
    /// The section showing; the bar at the bottom switches it (like Home's sports), so nothing needs long scrolling.
    @State private var section: SettingsSection = .account
    @State private var barWidth: CGFloat = 390

    enum SettingsSection: String, CaseIterable, Identifiable {
        case account = "Account", sports = "Sports", general = "General", changelog = "Changelog"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .sports: return "sportscourt"
            case .general: return "slider.horizontal.3"
            case .changelog: return "sparkles"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if section == .account {
                Section("Account") {
                    LabeledContent("Username", value: model.credentials?.username ?? "")
                    LabeledContent("Status", value: model.account?.status ?? "–")
                    LabeledContent("Expires", value: model.account?.expires?.formatted(date: .long, time: .omitted) ?? "No expiry date")
                    LabeledContent("Connections", value: connections)
                    Button("Edit account") { editingAccount = true }
                    HStack {
                        Spacer()
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    }
                }

                }

                if section == .general {
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

                }

                if section == .sports {
                Section {
                    ForEach(Sport.ordered(sportOrderPref)) { sport in
                        sportRow(sport)
                    }
                } header: {
                    Text("Sports")
                } footer: {
                    Text("Tap a sport for its leagues. Switch one off to hide it; the heart keeps it first on Home.")
                }
                }

                if section == .general {
                Section("Games") {
                    Toggle("Show finished games", isOn: $showFinished)
                    Toggle("Hide SD streams", isOn: $hideSD)
                }

                }

                if section == .general {
                Section("EPG") {
                    Toggle("Hide adult categories", isOn: Binding(
                        get: { hideAdult },
                        set: { hideAdult = $0; Task { await model.applyFilters(); await model.rematch() } }
                    ))
                    Toggle("Group similar categories", isOn: $grouped)
                }

                }

                if section == .general {
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

                }

                if section == .changelog {
                Section("Changelog") {
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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sectionBar }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Sign out of Courtside?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
            .sheet(isPresented: $editingAccount) {
                IOSLoginView(editing: model.credentials) { editingAccount = false }
                    .environmentObject(model)
            }
        }
    }

    /// The sections as chips along the bottom, starting from the right edge (nearest the thumb).
    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases.reversed()) { item in
                    IOSChip(selected: section == item, action: { section = item }) {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                            if section == item { Text(item.rawValue) }
                        }
                        .frame(minHeight: 30)
                    }
                    .accessibilityLabel(item.rawValue)
                }
            }
            .padding(.horizontal)
            .frame(minWidth: barWidth, alignment: .trailing)
        }
        .defaultScrollAnchor(.trailing)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
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
    /// Settings › Account › Edit account: starts filled in, and saves instead of signing in.
    var editing: XtreamCredentials? = nil
    var onDone: (() -> Void)? = nil
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
                Text(editing == nil ? "Sign in with your IPTV provider's Xtream Codes login." : "Change your Xtream Codes login.")
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
                        let s = server.trimmingCharacters(in: .whitespaces), u = username.trimmingCharacters(in: .whitespaces)
                        error = editing == nil ? await model.signIn(server: s, username: u, password: password)
                                               : await model.updateAccount(server: s, username: u, password: password)
                        working = false
                        if error == nil { onDone?() }
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(Theme.onAccent) }
                        Text(working ? (editing == nil ? "Signing in…" : "Checking…") : (editing == nil ? "Sign in" : "Save")).bold()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(Theme.onAccent)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                }
                .disabled(working || server.isEmpty || username.isEmpty || password.isEmpty)

                if let onDone {
                    Button("Cancel", action: onDone).foregroundStyle(Theme.muted)
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .onAppear {
            if let editing { server = editing.server; username = editing.username; password = editing.password }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}
