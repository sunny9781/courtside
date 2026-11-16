import Foundation

/// Notices a stream that has stopped moving (frozen picture, or stuck "buffering" after it was playing) for
/// 4 seconds. The first couple of times it asks for a quiet restart; if it keeps freezing (3 times within
/// 2 minutes) it asks to move on to the next stream.
@MainActor
final class FreezeWatch {
    enum Action { case none, restart, skip }

    private var lastProgress: Double = -1
    private var lastChange = Date()
    private var restarts: [Date] = []

    /// A new stream: forget everything.
    func reset() {
        lastProgress = -1
        lastChange = Date()
        restarts = []
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
        guard now.timeIntervalSince(lastChange) >= 4 else { return .none }
        restarts = restarts.filter { now.timeIntervalSince($0) < 120 } + [now]
        if restarts.count >= 3 {
            restarts = []
            lastChange = now.addingTimeInterval(6)
            return .skip
        }
        restarted()
        return .restart
    }
}
