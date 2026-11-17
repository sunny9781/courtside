import Foundation

/// Apple TV and iPhone: the version button in the top bar checks whether a newer Courtside is out (the Mac app's
/// release feed, which carries every version). These apps are installed from the Mac, so a newer version is
/// installed there with "Update Apple TV and iPhone".
@MainActor
final class VersionCheck: ObservableObject {
    static let shared = VersionCheck()

    @Published private(set) var checking = false
    /// A newer version that's out, if any.
    @Published private(set) var newer: String?
    @Published private(set) var upToDate = false

    private let feed = "https://github.com/sunny9781/courtside/releases/latest/download/latest.json"

    /// "1.39" (the build tools may write it as 1.39.0).
    var current: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return v.hasSuffix(".0") && v.split(separator: ".").count == 3 ? String(v.dropLast(2)) : v
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        struct Latest: Decodable { let version: String }
        guard let url = URL(string: feed + "?t=\(Int(Date().timeIntervalSince1970))"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let latest = try? JSONDecoder().decode(Latest.self, from: data) else { return }
        if Self.isNewer(latest.version, than: current) {
            newer = latest.version
            upToDate = false
        } else {
            newer = nil
            upToDate = true
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
