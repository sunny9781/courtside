import SwiftUI

/// Settings, laid out like the Mac: sections down the left, the selected section on the right.
struct TVSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: TVNav
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = false
    @AppStorage(Prefs.matchFrameRate) private var matchFrameRate = true
    @AppStorage(Prefs.hdrPlayerFor4K) private var hdrPlayerFor4K = true
    @AppStorage(Prefs.hdrPlayerForAll) private var hdrPlayerForAll = true
    @AppStorage(Prefs.guideGrouped) private var grouped = true
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.hiddenLeagues) private var hiddenLeagues = ""
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @AppStorage(Prefs.multiview) private var multiview = true
    @AppStorage(Prefs.multiviewSelect) private var multiviewSelect = "big"
    /// Remembered while you're on other tabs, so coming back lands on the section you were in.
    private var section: Section { Section(rawValue: nav.settingsSection) ?? .account }
    @State private var confirmSignOut = false
    @State private var editingAccount = false
    @FocusState private var focusedSection: Section?
    /// Updates open in What's new (the newest starts open).
    @State private var openReleases: Set<String> = Set(Changelog.forThisApp.prefix(1).map(\.id))

    enum Section: String, CaseIterable, Identifiable {
        case account = "Account"
        /// A SOCKS5 / HTTPS / HTTP proxy for the provider's traffic (2.33).
        case proxy = "Proxy"
        /// How streams play: switching, frame rate, buffer.
        case playback = "Playback"
        /// Channels and guide, updates.
        case general = "General"
        /// Hidden (switched off) sports, categories and channels, to show them again.
        case hidden = "Hidden"
        case changelog = "Changelog"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .proxy: return "network.badge.shield.half.filled"
            case .hidden: return "eye.slash"
            case .playback: return "play.circle"
            case .general: return "slider.horizontal.3"
            case .changelog: return "sparkles"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: TVLayout.playerGap - 24) {
            // Built like the left column on Home and the EPG (same list, spacing and insets), so the three screens
            // line up when you switch tabs.
            ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Section.allCases) { item in
                    Button {
                        nav.settingsSection = item.rawValue
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
            }
            .padding(.vertical, 20)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
            .frame(width: TVLayout.sidebar)
            .padding(.bottom, model.pinned != nil ? TVLayout.playerInset : TVLayout.margin)
            .focusSection()

            ScrollView(.vertical) {
                // The section is highlighted on the left, so its name isn't repeated here. Rows are the same height
                // and spacing as the section list, so the first rows line up across.
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Runs to the bottom of the screen, under the now-playing bar.
            .contentMargins(.bottom, model.pinned != nil ? TVLayout.barHeight + TVLayout.margin : TVLayout.margin, for: .scrollContent)
            // Use the full width: no Apple TV side insets on top of our own small margin.
            .ignoresSafeArea(.container, edges: .horizontal)
            .focusSection()
        }
        .padding(.trailing, TVLayout.margin)
        // Pressing down from Home / EPG / Settings starts on the section list.
        .defaultFocus($focusedSection, section, priority: .userInitiated)
        .onChange(of: focusedSection) {
            nav.sideFocused = focusedSection != nil
            if let focusedSection { nav.settingsSection = focusedSection.rawValue }
        }
        // Back from a setting: to its section on the left.
        .onChange(of: nav.sideRequest) { focusedSection = section }
        .onDisappear { nav.sideFocused = false }
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

        case .proxy:
            TVProxySection()

        case .hidden:
            let sports = Sport.allCases.filter { Sport.hidden(hiddenSports).contains($0) }
            let leagues = League.all.filter { League.hidden(hiddenLeagues).contains($0.id) && !sports.contains($0.sport) }
            let cats = model.hiddenCategoryNames
            let chans = model.hiddenChannelNames
            if sports.isEmpty && leagues.isEmpty && cats.isEmpty && chans.isEmpty {
                Text("Nothing is hidden. Hold the select button on a sport or league on Home, or a category or channel in the EPG, and choose Hide.")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 22)
            } else {
                Text("Click one to show it again. A hidden sport is switched off: no scores are fetched and nothing is matched for it.")
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 22)
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

        case .playback:
            toggle("Switch to the next stream when one stalls", detail: "USA and Canada streams are tried first.", $autoSwitch)
            toggle("Match frame rate",
                   detail: !DisplayMatcher.available
                       ? "Not available on this Apple TV's version of tvOS."
                       : (DisplayMatcher.systemAllows
                          ? "Switches your TV to each stream's frame rate (50 or 60 fps) for smoother motion."
                          : "Also turn on Settings › Video and Audio › Match Content › Match Frame Rate on the Apple TV."),
                   $matchFrameRate)
            if PlaybackController.hasHDRPlayer {
                toggle("4K with the HDR player",
                       detail: "Real HDR: in full screen the TV switches into HDR, like other IPTV apps. If a 4K channel shows nothing within a few seconds, it plays with VLC instead. Off: 4K plays like everything else, in standard range.",
                       $hdrPlayerFor4K)
                if hdrPlayerFor4K {
                    toggle("HDR player for all channels",
                           detail: "Every channel plays with the HDR player, so HDR at 1080p or 720p shows as HDR too (and gets its HDR tag). Off: only 4K channels do; the rest play with VLC.",
                           $hdrPlayerForAll)
                }
            }
            action("Buffer", detail: "More buffer means fewer stalls but a longer delay behind live.",
                   value: "\(bufferMs / 1000) s") {
                bufferMs = next(after: bufferMs, in: [1000, 2000, 3000, 5000])
            }
            toggle("Multiview",
                   detail: "Hold select on a stream or a game and choose Watch alongside: two streams side by side, when your provider has a connection free.",
                   $multiview)
            if multiview {
                action("Select in multiview",
                       detail: multiviewSelect == "sound" ? "Select on a tile moves the sound there; the tiles stay the same size."
                           : "Select on a tile moves the sound there and makes it big; again goes back to side by side.",
                       value: multiviewSelect == "sound" ? "Move sound only" : "Make big") {
                    multiviewSelect = multiviewSelect == "sound" ? "big" : "sound"
                }
            }

        case .general:
            toggle("Hide SD streams", detail: "Most providers have HD versions of the same channels.", $hideSD)

            action("Refresh now", detail: (model.savedAt.map { "Last downloaded \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? "")
                       + "Channels and guide download at 3 PM, 9 PM, 3 AM and 9 AM (after the stream, if one is playing).",
                   value: model.refreshWaiting ? "After this stream" : (model.downloadingChannels || model.guideDownloading ? "Refreshing…" : nil)) {
                Task { await model.refresh(force: true) }
            }
            info("Version", version)
            Text("To update, double-click \"Update Apple TV and iPhone\" in the Courtside shortcuts folder on your Mac (at least weekly).")
                .font(.system(size: 20))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 22)
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
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.text)
        }
        .font(.system(size: 26))
        .padding(.horizontal, 22)
        .frame(minHeight: 72)
    }

    private func toggle(_ title: String, detail: String?, _ value: Binding<Bool>) -> some View {
        Button {
            value.wrappedValue.toggle()
        } label: {
            TVSettingRow(title: title, detail: detail, value: value.wrappedValue ? "On" : "Off")
        }
        .buttonStyle(TVRowButtonStyle())
    }

    private func hiddenHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Theme.muted)
            .padding(.leading, 22)
            .padding(.top, 14)
    }

    private func action(_ title: String, detail: String?, value: String? = nil, destructive: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            TVSettingRow(title: title, detail: detail, value: value, destructive: destructive)
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

/// A setting: bright title, dim grey detail, and the value in orange ("Off" grey), so each one reads at a glance.
struct TVSettingRow: View {
    @Environment(\.isFocused) private var focused
    let title: String
    let detail: String?
    var value: String?
    var destructive = false

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(focused ? Theme.bg : (destructive ? Theme.danger : Theme.text))
                if let detail {
                    Text(detail).font(.system(size: 19))
                        .foregroundStyle(focused ? Theme.bg.opacity(0.75) : Theme.muted)
                }
            }
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(focused ? Theme.bg : (value == "Off" ? Theme.muted : Theme.accent))
            }
        }
        .padding(.vertical, 10)
    }
}
