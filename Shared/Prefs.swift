import Foundation

/// Settings keys, shared by the Settings screen (@AppStorage) and the model (UserDefaults).
enum Prefs {
    static let player = "player"                 // "builtin" | "iina" | "vlc"
    static let bufferMs = "bufferMs"
    static let showFinished = "showFinished"
    static let hideSD = "hideSDStreams"          // renamed so it starts switched on
    static let hiddenSports = "hiddenSports"     // comma-separated Sport raw values
    static let hiddenLeagues = "hiddenLeagues"   // comma-separated League ids
    static let guideHours = "guideHours"
    static let guideCategory = "guideCategory"
    static let recentChannels = "recentChannels"
    static let sportOrder = "sportOrder"         // comma-separated Sport raw values
    static let favoriteSports = "favoriteSports" // comma-separated Sport raw values
    static let guidePreview = "guidePreview"
    static let measuredQuality = "measuredQuality"
    static let measuredFrameRate = "measuredFrameRate"
    static let matchFrameRate = "matchFrameRate"
    static let hideAdult = "hideAdult"             // hide categories (and their channels) with "adult" in the name   // Apple TV: switch the TV's refresh rate to match the stream
    static let autoSwitch = "autoSwitch"         // switch to the next stream when one stalls
    static let refreshHours = "refreshHours"     // how long saved channels and guide are reused
    static let guideGrouped = "guideGroupedOn"   // renamed so grouping starts switched on

    static func register() {
        UserDefaults.standard.register(defaults: [
            player: "builtin",
            bufferMs: 2000,
            showFinished: true,
            hideSD: true,
            guideHours: 6,
            guideCategory: "",
            sportOrder: "",
            guidePreview: true,
            refreshHours: 6,
            autoSwitch: true,
            matchFrameRate: true,
            hideAdult: true,
            guideGrouped: true
        ])
    }
}
