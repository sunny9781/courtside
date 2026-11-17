import SwiftUI

/// Settings, laid out like the Mac: sections down the left, the selected section on the right.
struct TVSettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @AppStorage(Prefs.matchFrameRate) private var matchFrameRate = true
    @AppStorage(Prefs.hideAdult) private var hideAdult = true
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.hiddenLeagues) private var hiddenLeagues = ""
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @State private var section: Section = .account
    @State private var confirmSignOut = false
    @State private var editingAccount = false
    @FocusState private var focusedSection: Section?
    /// Updates open in What's new (the newest starts open).
    @State private var openReleases: Set<String> = Set(Changelog.forThisApp.prefix(1).map(\.id))

    enum Section: String, CaseIterable, Identifiable {
        case account = "Account"
        /// Playback, games, EPG and updates together.
        case general = "General"
        /// Hidden (switched off) sports, categories and channels, to show them again.
        case hidden = "Hidden"
        case changelog = "Changelog"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .hidden: return "eye.slash"
            case .general: return "slider.horizontal.3"
            case .changelog: return "sparkles"
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
            .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : 0)
            .focusSection()

            ScrollView(.vertical) {
                // The section is highlighted on the left, so its name isn't repeated here.
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.vertical, 20)
                .frame(maxWidth: 1000, alignment: .leading)
            }
            // Runs to the bottom of the screen, under the now-playing bar.
            .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : 0, for: .scrollContent)
            // Use the full width: no Apple TV side insets on top of our own small margin.
            .ignoresSafeArea(.container, edges: .horizontal)
            .focusSection()
        }
        .padding(.horizontal, TVLayout.margin)
        // Pressing down from Home / EPG / Settings starts on the section list.
        .defaultFocus($focusedSection, section, priority: .userInitiated)
        .onChange(of: focusedSection) {
            if let focusedSection { section = focusedSection }
        }
        .confirmationDialog("Sign out of Courtside?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $editingAccount) {
            TVLoginView(editing: model.credentials) { editingAccount = false }
                .environmentObject(model)
                .background(Theme.bg)
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
            action("Edit account", detail: "Change the server, username or password.") { editingAccount = true }
                .padding(.top, 20)
            action("Sign out", detail: nil, destructive: true) { confirmSignOut = true }
                .padding(.top, 20)
                // The connection count is fetched fresh each time you open Account.
                .task { await model.refreshAccount() }

        case .hidden:
            let sports = Sport.allCases.filter { Sport.hidden(hiddenSports).contains($0) }
            let leagues = League.all.filter { League.hidden(hiddenLeagues).contains($0.id) && !sports.contains($0.sport) }
            let cats = model.hiddenCategoryNames
            let chans = model.hiddenChannelNames
            if sports.isEmpty && leagues.isEmpty && cats.isEmpty && chans.isEmpty {
                Text("Nothing is hidden. Hold the select button on a sport on Home, or a category or channel in the EPG, and choose Hide.")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Click one to show it again. A hidden sport is switched off: no scores are fetched and nothing is matched for it.")
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 10)
                if !sports.isEmpty || !leagues.isEmpty { hiddenHeading("Sports") }
                ForEach(sports) { sport in
                    action(sport.rawValue, detail: nil, value: "Show") {
                        var set = Sport.hidden(hiddenSports)
                        set.remove(sport)
                        hiddenSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
                        model.sportsChanged()
                    }
                }
                ForEach(leagues) { league in
                    action(league.name, detail: league.sport.rawValue, value: "Show") {
                        let set = League.hidden(hiddenLeagues).subtracting([league.id])
                        hiddenLeagues = League.all.filter { set.contains($0.id) }.map(\.id).joined(separator: ",")
                        model.sportsChanged()
                    }
                }
                if !cats.isEmpty { hiddenHeading("Categories") }
                ForEach(cats, id: \.id) { item in
                    action(item.name, detail: nil, value: "Show") { model.setCategoryHidden(item.id, false) }
                }
                if !chans.isEmpty { hiddenHeading("Channels") }
                ForEach(chans, id: \.id) { item in
                    action(item.name, detail: nil, value: "Show") { model.setChannelHidden(item.id, false) }
                }
            }

        case .general:
            toggle("Switch to the next stream when one stalls", detail: "USA and Canada streams are tried first.", $autoSwitch)
            toggle("Match frame rate",
                   detail: !DisplayMatcher.available
                       ? "Not available on this Apple TV's version of tvOS."
                       : (DisplayMatcher.systemAllows
                          ? "Switches your TV to each stream's frame rate (50 or 60 fps) for smoother motion."
                          : "Also turn on Settings › Video and Audio › Match Content › Match Frame Rate on the Apple TV."),
                   $matchFrameRate)
            action("Buffer", detail: "More buffer means fewer stalls but a longer delay behind live.",
                   value: "\(bufferMs / 1000) s") {
                bufferMs = next(after: bufferMs, in: [1000, 2000, 3000, 5000])
            }
            toggle("Hide SD streams", detail: "Most providers have HD versions of the same channels.", $hideSD)

            toggle("Adult categories", detail: "Any category with \"adult\" in its name, and its channels. Off by default.", Binding(
                get: { !hideAdult },
                set: { hideAdult = !$0; Task { await model.applyFilters(); await model.rematch() } }
            ))

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
            Text("To update, double-click \"Update Apple TV and iPhone\" in the Courtside shortcuts folder on your Mac (at least weekly).")
                .font(.system(size: 20))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)

        case .changelog:
            ForEach(Array(Changelog.forThisApp.enumerated()), id: \.element.id) { index, release in
                Button {
                    if openReleases.contains(release.id) { openReleases.remove(release.id) } else { openReleases.insert(release.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            Image(systemName: openReleases.contains(release.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 24)
                            Text(release.heading).font(.system(size: 26, weight: .semibold))
                            Spacer()
                            Text(index == 0 ? "Latest · \(release.dateLabel)" : release.dateLabel)
                                .font(.system(size: 20)).opacity(0.6)
                        }
                        if openReleases.contains(release.id) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(release.changes, id: \.self) { change in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text("•")
                                        Text(change.text).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.system(size: 21))
                                    .opacity(0.85)
                                }
                            }
                            .padding(.leading, 40)
                        }
                    }
                }
                .buttonStyle(TVRowButtonStyle())
            }
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

    private func hiddenHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Theme.muted)
            .padding(.top, 14)
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

    private func next(after value: Int, in list: [Int]) -> Int {
        guard let i = list.firstIndex(of: value) else { return list[0] }
        return list[(i + 1) % list.count]
    }
}
