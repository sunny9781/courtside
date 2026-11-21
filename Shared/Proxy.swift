import Foundation
import Network

/// Settings › Proxy (2.33): send Courtside's provider traffic (sign-in, channels, guide, streams) through a SOCKS5,
/// HTTPS or HTTP proxy. Only this app uses it; ESPN scores and logos go direct. When it's on and the proxy can't be
/// reached, nothing falls back to a direct connection, so the provider never sees your own address by accident.
enum ProxyKind: String, CaseIterable, Identifiable {
    case off, socks5, https, http
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .socks5: return "SOCKS5"
        case .https: return "HTTPS"
        case .http: return "HTTP"
        }
    }
    var defaultPort: Int {
        switch self {
        case .off: return 0
        case .socks5: return 1080
        case .https: return 443
        case .http: return 8080
        }
    }
}

struct ProxySettings: Equatable {
    var kind: ProxyKind = .off
    var host = ""
    var port = 0
    var username = ""
    var password = ""

    static let kindKey = "proxyKind", hostKey = "proxyHost", portKey = "proxyPort"
    static let userKey = "proxyUser", passwordKey = "proxyPassword"

    var enabled: Bool { kind != .off && !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0 && port < 65536 }

    static var current: ProxySettings {
        let d = UserDefaults.standard
        return ProxySettings(kind: ProxyKind(rawValue: d.string(forKey: kindKey) ?? "") ?? .off,
                             host: d.string(forKey: hostKey) ?? "", port: d.integer(forKey: portKey),
                             username: d.string(forKey: userKey) ?? "", password: d.string(forKey: passwordKey) ?? "")
    }

    func save() {
        let d = UserDefaults.standard
        d.set(kind.rawValue, forKey: Self.kindKey)
        d.set(host.trimmingCharacters(in: .whitespaces), forKey: Self.hostKey)
        d.set(port, forKey: Self.portKey)
        d.set(username, forKey: Self.userKey)
        d.set(password, forKey: Self.passwordKey)
        ProxyNet.settingsChanged()
    }

    /// What Settings shows: "SOCKS5 · proxy.example.com:1080" or "Off".
    var summary: String { enabled ? "\(kind.title) · \(host):\(port)" : "Off" }

    fileprivate var configuration: ProxyConfiguration? {
        guard enabled, let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host.trimmingCharacters(in: .whitespaces)), port: p)
        var config: ProxyConfiguration
        switch kind {
        case .socks5: config = ProxyConfiguration(socksv5Proxy: endpoint)
        case .https: config = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: NWProtocolTLS.Options())
        case .http: config = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case .off: return nil
        }
        if !username.isEmpty { config.applyCredential(username: username, password: password) }
        config.allowFailover = false
        return config
    }
}

/// The URLSession for anything that talks to the provider: through the proxy when one is set, else the shared one.
enum ProxyNet {
    private static let lock = NSLock()
    private static var cached: (ProxySettings, URLSession)?

    static var session: URLSession {
        let settings = ProxySettings.current
        guard settings.enabled else { return .shared }
        lock.lock(); defer { lock.unlock() }
        if let cached, cached.0 == settings { return cached.1 }
        let session = URLSession(configuration: makeConfiguration(settings))
        cached?.1.finishTasksAndInvalidate()
        cached = (settings, session)
        return session
    }

    static func makeConfiguration(_ settings: ProxySettings) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        if let proxy = settings.configuration { config.proxyConfigurations = [proxy] }
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return config
    }

    static func settingsChanged() {
        lock.lock()
        cached?.1.finishTasksAndInvalidate()
        cached = nil
        lock.unlock()
        ProxyRelay.shared.settingsChanged()
    }

    /// Settings › Proxy › Test: signs in to the provider through the proxy. Nil when it worked, or what went wrong.
    static func test(_ settings: ProxySettings, creds: XtreamCredentials?) async -> String? {
        guard settings.enabled else { return "Fill in the proxy's address and port." }
        let session = URLSession(configuration: makeConfiguration(settings))
        defer { session.invalidateAndCancel() }
        // The provider when signed in (that's the one that matters), else a well-known address.
        var target = URL(string: "http://captive.apple.com/hotspot-detect.html")!
        if let creds, let api = XtreamClient(creds: creds).apiURL() { target = api }
        var request = URLRequest(url: target)
        request.timeoutInterval = 20
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "The proxy answered with something unexpected." }
            return http.statusCode < 500 ? nil : "Reached the provider through the proxy, but it replied with error \(http.statusCode)."
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the proxy (or the provider through it). Check the address and port."
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return "The proxy refused the username or password."
            case .timedOut: return "The proxy didn't answer in time."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "The HTTPS proxy's certificate wasn't accepted. Is it an HTTP proxy instead?"
            default: return "It didn't work: \(error.localizedDescription)"
            }
        } catch {
            return "It didn't work: \(error.localizedDescription)"
        }
    }
}

/// The players (VLC, the HDR player, Apple's player) can't use a proxy themselves, so while one is set they open the
/// stream from this small server inside the app (127.0.0.1, this device only), which fetches it through the proxy and
/// hands the bytes straight on. HLS playlists are rewritten so their parts come through here too. Closing the player
/// closes the connection here, which closes the one to the provider: still one connection at a time. Addresses carry a
/// random code made at launch, so other apps on the device can't use it, and nothing is logged (stream addresses hold
/// the Xtream login).
final class ProxyRelay: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = ProxyRelay()

    private let queue = DispatchQueue(label: "courtside.proxy-relay")
    private lazy var delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.underlyingQueue = queue
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let code = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var session: URLSession?
    private var relays: [Int: Relay] = [:]

    private final class Relay {
        let connection: NWConnection
        let original: URL
        var playlist = false
        var body = Data()
        var status = 200
        var headersSent = false
        var base: URL
        init(connection: NWConnection, original: URL) { self.connection = connection; self.original = original; base = original }
    }

    /// The address a player should open: the stream itself without a proxy, else this relay's address for it.
    func wrap(_ url: URL) -> URL {
        guard ProxySettings.current.enabled else { return url }
        guard let port = queue.sync(execute: { ensureListening() }) else {
            // Never fall back to the provider directly: a dead address makes the player fail instead.
            return URL(string: "http://127.0.0.1:9/unavailable/\(url.lastPathComponent)")!
        }
        return relayURL(url, port: port)
    }

    func settingsChanged() {
        queue.async {
            for r in self.relays.values { r.connection.cancel() }
            self.relays.removeAll()
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    private func relayURL(_ url: URL, port: UInt16) -> URL {
        let token = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let name = url.lastPathComponent.isEmpty ? "stream" : url.lastPathComponent
        return URL(string: "http://127.0.0.1:\(port)/\(code)/\(token)/\(name)")!
    }

    private func original(fromPath path: String) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == code else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let s = String(data: data, encoding: .utf8) else { return nil }
        return URL(string: s)
    }

    /// Starts the server the first time (on `queue`); its port, or nil if it couldn't start.
    private func ensureListening() -> UInt16? {
        if listener != nil, port != 0 { return port }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: .any) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = l.port?.rawValue ?? 0
                ready.signal()
            case .failed, .cancelled:
                self?.queue.async { if self?.listener === l { self?.listener = nil; self?.port = 0 } }
                ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener = l
        // Its own queue for the start, so waiting here (on `queue`) can't block it.
        l.start(queue: DispatchQueue(label: "courtside.proxy-listener"))
        _ = ready.wait(timeout: .now() + 3)
        if port == 0 { l.cancel(); listener = nil; return nil }
        ConnLog.add("Proxy relay on")
        return port
    }

    private func upstream() -> URLSession {
        if let session { return session }
        let config = ProxyNet.makeConfiguration(ProxySettings.current)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 24
        let s = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        session = s
        return s
    }

    // MARK: The player's side

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        readRequest(c, buffer: Data())
    }

    private func readRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(c, head: String(decoding: buf[..<end.lowerBound], as: UTF8.self))
            } else if complete || error != nil || buf.count > 32768 {
                c.cancel()
            } else {
                self.readRequest(c, buffer: buf)
            }
        }
    }

    private func handle(_ c: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        guard parts.count >= 2, method == "GET" || method == "HEAD",
              let target = original(fromPath: String(parts[1]).components(separatedBy: "?")[0]) else {
            reply(c, status: 404)
            return
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // What the player asks for, minus what's about this little server's own connection.
            if ["range", "user-agent", "accept", "accept-language", "icy-metadata"].contains(name.lowercased()) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        let task = upstream().dataTask(with: request)
        let relay = Relay(connection: c, original: target)
        relays[task.taskIdentifier] = relay
        let id = task.taskIdentifier
        c.stateUpdateHandler = { [weak self, weak task] state in
            switch state {
            case .failed, .cancelled:
                task?.cancel()
                self?.relays[id] = nil
            default: break
            }
        }
        watchClose(c, task: task)
        task.resume()
    }

    /// The player hanging up (closing the stream) ends the provider's connection right away.
    private func watchClose(_ c: NWConnection, task: URLSessionTask) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak task] _, _, complete, error in
            if complete || error != nil {
                task?.cancel()
                c.cancel()
            } else if let task {
                self?.watchClose(c, task: task)
            }
        }
    }

    private func reply(_ c: NWConnection, status: Int) {
        let text = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n" +
            "Content-Length: 0\r\nConnection: close\r\n\r\n"
        c.send(content: Data(text.utf8), isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }

    private func sendHeaders(_ r: Relay, status: Int, headers: [String: String]) {
        var text = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        for (k, v) in headers { text += "\(k): \(v)\r\n" }
        text += "Connection: close\r\nCache-Control: no-store\r\n\r\n"
        r.headersSent = true
        r.connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    // MARK: The provider's side (through the proxy)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let r = relays[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
        let http = response as? HTTPURLResponse
        r.status = http?.statusCode ?? 200
        r.base = response.url ?? r.original
        let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        r.playlist = type.contains("mpegurl") || r.base.pathExtension.lowercased() == "m3u8"
            || r.original.pathExtension.lowercased() == "m3u8"
        if !r.playlist {
            var headers: [String: String] = [:]
            for key in ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"] {
                if let v = http?.value(forHTTPHeaderField: key) { headers[key] = v }
            }
            sendHeaders(r, status: r.status, headers: headers)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let r = relays[dataTask.taskIdentifier] else { dataTask.cancel(); return }
        if r.playlist {
            r.body.append(data)
            if r.body.count > 4_000_000 { dataTask.cancel() }
            return
        }
        r.connection.send(content: data, completion: .contentProcessed { [weak dataTask] error in
            if error != nil { dataTask?.cancel() }
        })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let r = relays.removeValue(forKey: task.taskIdentifier) else { return }
        let c = r.connection
        if !r.headersSent {
            let relayPort = port
            guard error == nil, r.playlist, relayPort != 0 else {
                reply(c, status: 502)
                return
            }
            let body = Data(rewrite(String(decoding: r.body, as: UTF8.self), base: r.base, port: relayPort).utf8)
            sendHeaders(r, status: r.status, headers: ["Content-Type": "application/vnd.apple.mpegurl",
                                                       "Content-Length": "\(body.count)"])
            c.send(content: body, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
            return
        }
        c.send(content: nil, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }

    /// Every address in an HLS playlist (parts, other qualities, keys) pointed at this relay.
    private func rewrite(_ text: String, base: URL, port: UInt16) -> String {
        func relay(_ s: String) -> String {
            guard let u = URL(string: s, relativeTo: base)?.absoluteURL else { return s }
            return relayURL(u, port: port).absoluteString
        }
        let uriPattern = try? NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        return text.components(separatedBy: "\n").map { raw -> String in
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty { return raw }
            if !line.hasPrefix("#") { return relay(line.trimmingCharacters(in: .whitespaces)) }
            guard let uriPattern, line.contains("URI=\"") else { return line }
            var out = line
            for m in uriPattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(m.range(at: 1), in: line), let whole = Range(m.range, in: out) else { continue }
                out.replaceSubrange(whole, with: "URI=\"\(relay(String(line[range])))\"")
            }
            return out
        }.joined(separator: "\n")
    }
}

/// What the Proxy settings screens edit (all three Apple apps): saved only with Save, after an optional Test.
@MainActor
final class ProxyDraft: ObservableObject {
    @Published var kind: ProxyKind
    @Published var host: String
    @Published var port: String
    @Published var username: String
    @Published var password: String
    @Published var testing = false
    /// The last test or save: the message, and whether it worked.
    @Published var result: (text: String, ok: Bool)?

    init() {
        let s = ProxySettings.current
        kind = s.kind; host = s.host; port = s.port > 0 ? String(s.port) : ""
        username = s.username; password = s.password
    }

    var settings: ProxySettings {
        ProxySettings(kind: kind, host: host.trimmingCharacters(in: .whitespaces),
                      port: Int(port.trimmingCharacters(in: .whitespaces)) ?? (kind == .off ? 0 : kind.defaultPort),
                      username: username.trimmingCharacters(in: .whitespaces), password: password)
    }

    var changed: Bool { settings != ProxySettings.current }
    var saved: String { ProxySettings.current.summary }

    func pick(_ k: ProxyKind) {
        let oldDefault = String(kind.defaultPort)
        kind = k
        if port.isEmpty || port == oldDefault { port = k == .off ? "" : String(k.defaultPort) }
        result = nil
    }

    func test(_ creds: XtreamCredentials?) {
        let s = settings
        testing = true
        result = nil
        Task {
            let error = await ProxyNet.test(s, creds: creds)
            testing = false
            result = error.map { ($0, false) } ?? (creds == nil ? "The proxy works." : "Your provider answered through the proxy.", true)
        }
    }

    func save(_ model: AppModel) {
        let s = settings
        if s.kind != .off && !s.enabled { result = ("Fill in the proxy's address and port.", false); return }
        (s.enabled ? s : ProxySettings()).save()
        result = (s.enabled ? "Saved. New streams and downloads go through the proxy." : "Proxy off. Courtside connects directly again.", true)
        Task { await model.refreshAccount() }
    }
}

extension ProxyKind {
    /// The next type, for a TV row that cycles through them.
    var next: ProxyKind { let all = Self.allCases; return all[(all.firstIndex(of: self)! + 1) % all.count] }
}
