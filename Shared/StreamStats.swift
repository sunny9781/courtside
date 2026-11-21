import Foundation

/// How reliable each stream has been on this device (2.21, like Android's StreamStats since 2.19): startup time,
/// buffering, freezes, drops and failed starts, kept per stream ID (never the URL, which holds the login) as running
/// averages, so recent viewings count more and the store never grows. Streams not watched for 60 days are dropped.
/// Only what's actually watched is measured: nothing is tested in the background (one connection at a time).
/// Saved in UserDefaults (summaries only, small enough for tvOS, which has no lasting files).
@MainActor
final class StreamStats: ObservableObject {
    static let shared = StreamStats()

    enum Rating { case good, ok, poor }

    private struct Summary: Codable {
        var rebuffer = 0.0       // share of time spent buffering, 0...1
        var eventsPerHour = 0.0  // buffers + freezes + drops per hour watched
        var startupMs = 0.0
        var failRate = 0.0       // share of opens that never showed a picture
        var watchMs = 0.0
        var opens = 0
        var lastAt = Date.distantPast
    }

    /// Recent viewings count this much in the running averages.
    private let weight = 0.3
    /// No dot until a stream has been watched this long in total (one bad first open shouldn't mark it).
    private let minWatchMs = 5.0 * 60_000
    private let forgetAfter: TimeInterval = 60 * 24 * 3600
    private let key = "streamStats"

    private var streams: [Int: Summary] = [:]

    /// The dot for each stream with enough history.
    @Published private(set) var ratings: [Int: Rating] = [:]

    // The viewing in progress.
    private var id: Int?
    private var startedAt = Date()
    private var startupMs: Double = -1
    private var watchMs = 0.0
    private var bufferMs = 0.0
    private var buffers = 0
    private var freezes = 0
    private var drops = 0
    private var wasBuffering = false
    private var lastTick = Date()

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Int: Summary].self, from: data) {
            let now = Date()
            streams = saved.filter { now.timeIntervalSince($0.value.lastAt) < forgetAfter }
        }
        publish()
    }

    /// The stream ID from an Xtream address (".../live/user/pass/1234.ts" → 1234).
    static func id(of url: URL) -> Int? {
        Int(url.deletingPathExtension().lastPathComponent)
    }

    /// A stream was pressed: ends the last viewing and starts one for this stream.
    func begin(_ url: URL) {
        end()
        guard let sid = Self.id(of: url) else { return }
        id = sid
        startedAt = Date()
        lastTick = startedAt
        startupMs = -1; watchMs = 0; bufferMs = 0; buffers = 0; freezes = 0; drops = 0; wasBuffering = false
    }

    func froze() { if id != nil { freezes += 1 } }
    func dropped() { if id != nil { drops += 1 } }

    /// Every half second from the player: `picture` = it has shown a picture, `playing` = picture moving,
    /// `buffering` = stalled after a picture. Paused or still opening counts as neither.
    func tick(picture: Bool, playing: Bool, buffering: Bool) {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTick) * 1000, 0), 2000)
        lastTick = now
        guard id != nil else { return }
        if picture, startupMs < 0 { startupMs = now.timeIntervalSince(startedAt) * 1000 }
        if playing { watchMs += dt }
        if buffering {
            bufferMs += dt
            if !wasBuffering { buffers += 1 }
        }
        wasBuffering = buffering
    }

    /// The stream was stopped (or another one started): folds this viewing into the stream's history and saves.
    func end() {
        guard let sid = id else { return }
        id = nil
        let failed = startupMs < 0
        // Opened and closed again straight away (flipping through streams): not a real try, nothing learned.
        if !failed && watchMs + bufferMs < 10_000 { return }
        if failed && Date().timeIntervalSince(startedAt) < 8 { return }
        var s = streams[sid] ?? Summary()
        let first = s.opens == 0
        func mix(_ old: Double, _ new: Double, _ fresh: Bool) -> Double { fresh ? new : old * (1 - weight) + new * weight }
        s.failRate = mix(s.failRate, failed ? 1 : 0, first)
        if !failed {
            let total = watchMs + bufferMs
            let events = Double(buffers + freezes + drops)
            let fresh = s.watchMs == 0
            s.rebuffer = mix(s.rebuffer, bufferMs / total, fresh)
            s.eventsPerHour = mix(s.eventsPerHour, events / (total / 3_600_000), fresh)
            s.startupMs = mix(s.startupMs, startupMs, fresh)
        }
        s.watchMs += watchMs
        s.opens += 1
        s.lastAt = startedAt
        streams[sid] = s
        publish()
        if let data = try? JSONEncoder().encode(streams) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func rate(_ s: Summary) -> Rating? {
        // Never shows a picture: red even without watch time.
        if s.opens >= 2 && s.failRate > 0.5 { return .poor }
        guard s.watchMs >= minWatchMs else { return nil }
        if s.rebuffer > 0.05 || s.eventsPerHour > 20 || s.failRate > 0.4 { return .poor }
        if s.rebuffer > 0.01 || s.eventsPerHour > 6 || s.failRate > 0.15 || s.startupMs > 8_000 { return .ok }
        return .good
    }

    private func publish() {
        ratings = streams.compactMapValues(rate)
    }
}
