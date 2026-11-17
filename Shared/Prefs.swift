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
    static let pinnedVideoHeight = "pinnedVideoHeight" // Mac: height of the pinned player's video (dragged)
    static let pinnedVideoScale = "pinnedVideoScale"   // iPhone/iPad: pinned player's width, as a share of the screen
    static let showForeignStreams = "showForeignStreams" // game screens: list foreign-language streams too
    static let pinnedCollapsed = "pinnedCollapsed"     // pinned player showing just its buttons (sound keeps playing)
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
            refreshHours: 12,
            autoSwitch: true,
            matchFrameRate: true,
            hideAdult: true,
            guideGrouped: true
        ])
        let d = UserDefaults.standard
        // "UFC" became "Fighting" (with boxing): carry saved sport choices over, once.
        if !d.bool(forKey: "fightingRenamed") {
            for key in [hiddenSports, favoriteSports, sportOrder] {
                if let v = d.string(forKey: key), v.contains("UFC") {
                    d.set(v.split(separator: ",").map { $0 == "UFC" ? "Fighting" : String($0) }.joined(separator: ","), forKey: key)
                }
            }
            d.set(true, forKey: "fightingRenamed")
        }
        // The refresh default went from 6 to 12 hours: move anyone still on the old default over, once.
        if !d.bool(forKey: "refreshHours12") {
            if d.object(forKey: refreshHours) as? Int == 6 { d.set(12, forKey: refreshHours) }
            d.set(true, forKey: "refreshHours12")
        }
    }
}
