import SwiftUI

struct TVSettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @AppStorage(Prefs.hideSD) private var hideSD = true
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.hiddenSports) private var hiddenSports = ""
    @AppStorage(Prefs.favoriteSports) private var favoriteSports = ""
    @AppStorage(Prefs.refreshHours) private var refreshHours = 6
    @State private var confirmSignOut = false

    private let buffers = [1000, 2000, 4000, 8000]
    private let refreshChoices = [1, 3, 6, 12, 24]

    var body: some View {
        List {
            Section("Playback") {
                Toggle("Switch streams automatically when one stalls", isOn: $autoSwitch)
                Toggle("Hide SD streams", isOn: $hideSD)
                Button {
                    bufferMs = next(after: bufferMs, in: buffers)
                } label: {
                    LabeledContent("Buffer", value: "\(bufferMs / 1000) s")
                }
            }

            Section("Sports") {
                ForEach(Sport.allCases) { sport in
                    let hidden = Sport.hidden(hiddenSports).contains(sport)
                    let favorite = favorites.contains(sport)
                    Button {
                        setHidden(sport, !hidden)
                    } label: {
                        HStack(spacing: 20) {
                            Image(systemName: sport.symbol)
                                .frame(width: 40)
                            Text(sport.rawValue)
                            if favorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            Text(hidden ? "Hidden" : "Shown")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button(favorite ? "Remove from favourites" : "Favourite: show first") {
                            toggleFavorite(sport)
                        }
                    }
                }
                Text("Click a sport to show or hide it. Press and hold to make it a favourite, so it comes first on Home.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            Section("Channels and guide") {
                Button {
                    refreshHours = next(after: refreshHours, in: refreshChoices)
                } label: {
                    LabeledContent("Download fresh channels after", value: "\(refreshHours) h")
                }
                Button {
                    Task { await model.refresh(force: true) }
                } label: {
                    LabeledContent("Refresh now",
                                   value: model.downloadingChannels ? "Downloading…" : lastDownloaded)
                }
                .disabled(model.downloadingChannels)
            }

            Section("Account") {
                LabeledContent("Username", value: model.credentials?.username ?? "")
                if let account = model.account {
                    LabeledContent("Status", value: account.status)
                    if let expires = account.expires {
                        LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let max = account.maxConnections {
                        LabeledContent("Connections", value: "\(account.activeConnections ?? 0) of \(max) in use")
                    }
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }

            Section("About") {
                LabeledContent("Version", value: version)
            }
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
        .confirmationDialog("Sign out of Courtside?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var lastDownloaded: String {
        guard let saved = model.savedAt else { return "" }
        return "Updated " + saved.formatted(date: .omitted, time: .shortened)
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

    private func toggleFavorite(_ sport: Sport) {
        var set = favorites
        if set.contains(sport) { set.remove(sport) } else { set.insert(sport) }
        favoriteSports = Sport.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}
