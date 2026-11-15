import Foundation

enum XtreamError: LocalizedError {
    case badServer
    case loginFailed(String)
    case badResponse
    case guideUnreadable

    var errorDescription: String? {
        switch self {
        case .badServer:
            return "That server address doesn't look right. It should look like http://example.com:8080"
        case .loginFailed(let why):
            return why
        case .badResponse:
            return "The server replied with something that isn't an Xtream Codes response."
        case .guideUnreadable:
            return "The provider's guide file couldn't be read."
        }
    }
}

struct XtreamClient {
    let creds: XtreamCredentials

    private var base: String {
        var s = creds.server.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func url(_ path: String, action: String? = nil) throws -> URL {
        guard var comps = URLComponents(string: base + path) else { throw XtreamError.badServer }
        var items = [
            URLQueryItem(name: "username", value: creds.username),
            URLQueryItem(name: "password", value: creds.password)
        ]
        if let action {
            items.append(URLQueryItem(name: "action", value: action))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw XtreamError.badServer }
        return url
    }

    private func getJSON(action: String?) async throws -> Any {
        var request = URLRequest(url: try url("/player_api.php", action: action))
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw XtreamError.loginFailed("The server refused the request. Check the address, username and password.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw XtreamError.badResponse
        }
        return json
    }

    /// Checks the login and returns the account details. Throws with a readable message when it fails.
    @discardableResult
    func login() async throws -> AccountInfo {
        let json = try await getJSON(action: nil)
        guard let dict = json as? [String: Any],
              let user = dict["user_info"] as? [String: Any] else {
            throw XtreamError.badResponse
        }
        if (Flex.int(user["auth"]) ?? 0) != 1 {
            throw XtreamError.loginFailed("Wrong username or password.")
        }
        let status = (user["status"] as? String) ?? "Unknown"
        if status.lowercased() != "active" {
            throw XtreamError.loginFailed("The account is not active (status: \(status)).")
        }
        var expires: Date?
        if let exp = Flex.int(user["exp_date"]), exp > 0 {
            expires = Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return AccountInfo(status: status,
                           expires: expires,
                           maxConnections: Flex.int(user["max_connections"]),
                           activeConnections: Flex.int(user["active_cons"]))
    }

    /// Live categories and channels only. The video-on-demand and series actions are never called.
    func live() async throws -> (categories: [ChannelCategory], channels: [Channel]) {
        async let categoriesJSON = getJSON(action: "get_live_categories")
        async let streamsJSON = getJSON(action: "get_live_streams")
        let (cats, streams) = try await (categoriesJSON, streamsJSON)

        var categories: [ChannelCategory] = []
        for item in (cats as? [[String: Any]]) ?? [] {
            if let id = Flex.string(item["category_id"]), let name = item["category_name"] as? String {
                categories.append(ChannelCategory(id: id, name: name))
            }
        }
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        guard let list = streams as? [[String: Any]] else { throw XtreamError.badResponse }
        let channels: [Channel] = list.compactMap { item in
            guard let id = Flex.int(item["stream_id"]), let name = item["name"] as? String else { return nil }
            let categoryID = Flex.string(item["category_id"]) ?? ""
            let epg = ((item["epg_channel_id"] as? String) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            var icon: URL?
            if let raw = item["stream_icon"] as? String, raw.lowercased().hasPrefix("http") {
                icon = URL(string: raw)
            }
            return Channel(id: id, number: Flex.int(item["num"]), name: name, categoryID: categoryID,
                           categoryName: names[categoryID] ?? "", epgID: epg, icon: icon)
        }
        return (categories, channels)
    }

    /// Downloads the provider's full XMLTV guide to a file.
    func downloadGuide(to destination: URL) async throws {
        var request = URLRequest(url: try url("/xmltv.php"))
        request.timeoutInterval = 300
        let (tmp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw XtreamError.guideUnreadable
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    /// Reads only the wanted channels and time window out of a guide file.
    static func parseGuide(file: URL, wanted: Set<String>, from: Date, to: Date) throws -> [String: [Programme]] {
        guard let stream = InputStream(url: file) else { throw XtreamError.guideUnreadable }
        let delegate = XMLTVParser(wanted: wanted, from: from, to: to)
        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        let ok = parser.parse()
        if !ok && delegate.result.isEmpty { throw XtreamError.guideUnreadable }
        return delegate.result.mapValues { $0.sorted { $0.start < $1.start } }
    }

    /// The stream address contains the username and password, so never log or share it.
    func streamURL(for channel: Channel, hls: Bool) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let user = creds.username.addingPercentEncoding(withAllowedCharacters: allowed),
              let pass = creds.password.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(base)/live/\(user)/\(pass)/\(channel.id).\(hls ? "m3u8" : "ts")")
    }
}

/// Streaming XMLTV reader that keeps only what the app shows, so huge guide files stay cheap.
final class XMLTVParser: NSObject, XMLParserDelegate {
    private let wanted: Set<String>
    private let from: Date
    private let to: Date
    private(set) var result: [String: [Programme]] = [:]

    private var channel: String?
    private var start: Date?
    private var end: Date?
    private var inTitle = false
    private var hasTitle = false
    private var title = ""

    private let withZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    private let plain: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    init(wanted: Set<String>, from: Date, to: Date) {
        self.wanted = wanted
        self.from = from
        self.to = to
    }

    private func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        if let d = withZone.date(from: text) { return d }
        return plain.date(from: String(text.prefix(14)))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "programme" {
            channel = nil
            guard let ch = attributeDict["channel"]?.lowercased(), wanted.contains(ch),
                  let s = date(attributeDict["start"]), let e = date(attributeDict["stop"]),
                  s < to, e > from else { return }
            channel = ch
            start = s
            end = e
            hasTitle = false
            title = ""
        } else if elementName == "title", channel != nil, !hasTitle {
            inTitle = true
            title = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { title += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "title", inTitle {
            inTitle = false
            hasTitle = true
        } else if elementName == "programme", let ch = channel, let s = start, let e = end {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            result[ch, default: []].append(Programme(title: clean, start: s, end: e))
            channel = nil
        }
    }
}
