import Foundation

/// Notices a stream that has stopped moving (frozen picture, or stuck "buffering" after it was playing). Hiccups are
/// waited out with the connection left open, like other IPTV apps: only after a whole minute without any progress
/// does it ask for a quiet restart (a connection that died without saying so). It never asks to move on to another
/// stream (`.skip` stays for callers but isn't returned).
@MainActor
final class FreezeWatch {
    enum Action { case none, restart, skip }

    private var lastProgress: Double = -1
    private var lastChange = Date()
    /// How long the picture may stand still before the stream is reopened.
    static let patience: TimeInterval = 60

    /// A new stream: forget everything.
    func reset() {
        lastProgress = -1
        lastChange = Date()
    }

    /// After a quiet restart: give it time to start again, but remember the restart.
    func restarted() {
        lastProgress = -1
        lastChange = Date().addingTimeInterval(6)   // a restart takes a few seconds to show a picture
    }

    /// `progress` is the playback position; `watching` is true once the stream has shown a picture and isn't
    /// paused, ended or failed.
    func check(progress: Double, watching: Bool) -> Action {
        let now = Date()
        guard watching else {
            lastChange = now
            return .none
        }
        if progress != lastProgress {
            lastProgress = progress
            if lastChange < now { lastChange = now }   // (after a restart, lastChange is a little in the future)
            return .none
        }
        guard now.timeIntervalSince(lastChange) >= Self.patience else { return .none }
        restarted()
        return .restart
    }
}
