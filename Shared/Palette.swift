import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0E1116)
    static let sidebar = Color(hex: 0x131820)
    static let card = Color(hex: 0x171B22)
    static let cardHover = Color(hex: 0x1E242E)
    static let raised = Color(hex: 0x232A35)
    static let border = Color(hex: 0x2E3643)
    static let text = Color(hex: 0xF2F4F7)
    static let soft = Color(hex: 0xD5DAE2)
    static let muted = Color(hex: 0x9AA3B2)
    static let accent = Color(hex: 0xFF8A3D)
    static let onAccent = Color(hex: 0x14100C)
    static let matchBG = Color(hex: 0x3A2614)
    static let matchText = Color(hex: 0xFFD9BD)
    static let danger = Color(hex: 0xFF6B6B)
    static let winning = Color(hex: 0x4ADE80)
    static let losing = Color(hex: 0xF87171)
    static let champion = Color(hex: 0xFACC15)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Game {
    /// Score colour for one side: live leader green, trailing red; final winner gold, loser grey;
    /// tied stays white; not started is grey.
    func scoreColor(_ side: Team) -> Color {
        let other = side == away ? home : away
        guard let mine = Double(side.score), let theirs = Double(other.score) else { return Theme.text }
        switch state {
        case .upcoming:
            return Theme.muted
        case .live:
            if mine == theirs { return Theme.winning }
            return mine > theirs ? Theme.winning : Theme.losing
        case .finished:
            if mine == theirs { return Theme.text }
            return mine > theirs ? Theme.champion : Theme.muted
        }
    }
}

extension URL {
    /// ESPN's logos are 500-pixel images; rows show them at about 30 points. ESPN's image server sends them at the
    /// size they're shown (sharp on a 4K TV and Retina screens too), so there's much less to download and shrink.
    /// Other addresses are left as they are.
    func smallLogo(_ size: CGFloat) -> URL {
        let s = absoluteString
        let prefix = "https://a.espncdn.com/i/"
        guard s.hasPrefix(prefix), query == nil else { return self }
        let px = Int(min(max(size * 3, 48), 160))
        return URL(string: "https://a.espncdn.com/combiner/i?img=/i/\(s.dropFirst(prefix.count))&w=\(px)&h=\(px)") ?? self
    }
}

#if canImport(UIKit)
import UIKit
typealias LogoPlatformImage = UIImage
#else
import AppKit
typealias LogoPlatformImage = NSImage
#endif

/// Logos, kept once they've loaded: in memory for the session (so redrawing Home, switching sports or scrolling
/// shows them at once, without downloading or decoding them again) and on disk for 30 MB (so the next launch doesn't
/// download them either). One download per address, however many cards show it.
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private let memory = NSCache<NSURL, LogoPlatformImage>()
    private var loading: [URL: Task<LogoPlatformImage?, Never>] = [:]
    /// Addresses that failed this session: not tried again until the next launch.
    private var failed: Set<URL> = []
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 30 << 20,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                       .appendingPathComponent("Courtside/logos", isDirectory: true))
        // A logo doesn't change: use the saved copy without asking the server again.
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() { memory.countLimit = 400 }

    func cached(_ url: URL) -> LogoPlatformImage? { memory.object(forKey: url as NSURL) }
    func hasFailed(_ url: URL) -> Bool { failed.contains(url) }

    func load(_ url: URL) async -> LogoPlatformImage? {
        if let image = cached(url) { return image }
        if failed.contains(url) { return nil }
        if let task = loading[url] { return await task.value }
        let session = self.session
        let task = Task<LogoPlatformImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return LogoPlatformImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) } else { failed.insert(url) }
        return image
    }
}

/// A logo at the size it's shown; if the small version won't load, the full-size one. Loaded once (LogoCache), so a
/// card drawn again shows it straight away.
struct SmallLogoImage<Placeholder: View>: View {
    let url: URL?
    let size: CGFloat
    var inset: CGFloat = 0
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: LogoPlatformImage?

    private var small: URL? { url?.smallLogo(size) }

    var body: some View {
        Group {
            if let image = image ?? small.flatMap({ LogoCache.shared.cached($0) }) ?? url.flatMap({ LogoCache.shared.cached($0) }) {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFit().padding(inset)
                #else
                Image(nsImage: image).resizable().scaledToFit().padding(inset)
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard image == nil, let small, let url else { return }
            if let found = await LogoCache.shared.load(small) { image = found; return }
            if small != url, let full = await LogoCache.shared.load(url) { image = full }
        }
    }
}
