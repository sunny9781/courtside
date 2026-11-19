import Foundation

/// What used a connection to the provider, newest first (Settings › Connection log): streams opened and closed,
/// downloads started and finished, and what the provider said was in use. Never holds an address (they contain the
/// login): streams are named by their stream number only.
final class ConnLog: ObservableObject {
    static let shared = ConnLog()
    @Published private(set) var entries: [String] = []

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    static func add(_ text: String) {
        let line = "\(time.string(from: Date()))  \(text)"
        DispatchQueue.main.async {
            shared.entries.insert(line, at: 0)
            if shared.entries.count > 40 { shared.entries.removeLast(shared.entries.count - 40) }
        }
    }

    /// "stream 12345 (TS)" from a stream address, without the login in it.
    static func stream(_ url: URL?) -> String {
        guard let url else { return "stream" }
        let file = url.lastPathComponent
        let id = file.split(separator: ".").first.map(String.init) ?? file
        return "stream \(id) (\(url.pathExtension == "m3u8" ? "HLS" : "TS"))"
    }
}
