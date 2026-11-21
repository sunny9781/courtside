import SwiftUI
import Network
import CoreImage
import CoreImage.CIFilterBuiltins

#if os(tvOS) || os(macOS)

/// Set up from your phone (2.21, like Android TV since 2.6): while the sign-in screen is showing, the app serves a
/// small web page on the home network. The phone scans the QR code (or types the address), fills in the Xtream
/// details and sends them straight here. Nothing goes through the internet, and the details are never logged. A PIN
/// (in the QR code) stops anyone else on the Wi-Fi from sending a login; five wrong PINs make a new one.
@MainActor
final class PhoneSetupServer: ObservableObject {
    @Published private(set) var pin = PhoneSetupServer.newPin()
    @Published private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private var wrong = 0
    private let onLogin: (XtreamCredentials) async -> String?

    static let preferredPort: UInt16 = 8642

    init(onLogin: @escaping (XtreamCredentials) async -> String?) {
        self.onLogin = onLogin
    }

    /// Port 8642 if it's free, otherwise any free port.
    func start(anyPort: Bool = false) {
        guard listener == nil else { return }
        let l = anyPort ? try? NWListener(using: .tcp)
                        : try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.preferredPort)!)
        guard let l else { if !anyPort { start(anyPort: true) }; return }
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.port = l.port?.rawValue ?? 0
                case .failed:
                    self.port = 0
                    l.cancel()
                    if self.listener === l {
                        self.listener = nil
                        if !anyPort { self.start(anyPort: true) }
                    }
                case .cancelled: self.port = 0
                default: break
                }
            }
        }
        l.start(queue: .main)
        listener = l
        ConnLog.add("Phone setup page on")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: Requests

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
        // Never hang on to a connection for long.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { conn.cancel() }
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { conn.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.count > 16_384 || error != nil { conn.cancel(); return }
                if let request = Self.parse(buffer) {
                    await self.handle(request, on: conn)
                } else if done {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buffer)
                }
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let body: [String: String]
    }

    /// A whole request (headers and, for a POST, its body), or nil while more is still to come.
    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return Request(method: "", path: "/", query: [:], body: [:]) }
        var length = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        }
        let bodyData = data[end.upperBound...]
        if bodyData.count < min(length, 8192) { return nil }
        let target = parts[1]
        let path = String(target.split(separator: "?", maxSplits: 1).first ?? "/")
        let query = target.contains("?") ? form(String(target.split(separator: "?", maxSplits: 1).last ?? "")) : [:]
        return Request(method: parts[0], path: path, query: query,
                       body: form(String(decoding: bodyData.prefix(8192), as: UTF8.self)))
    }

    private static func form(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            func decode(_ x: String) -> String { x.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? x }
            out[decode(kv[0])] = decode(kv[1])
        }
        return out
    }

    private func handle(_ r: Request, on conn: NWConnection) async {
        func send(_ code: String, _ html: String) {
            let body = Data(html.utf8)
            var out = Data(("HTTP/1.1 \(code)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n" +
                            "Cache-Control: no-store\r\nConnection: close\r\n\r\n").utf8)
            out.append(body)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }
        switch (r.method, r.path) {
        case ("GET", "/"):
            send("200 OK", page(pin: r.query["pin"] ?? "", error: nil, server: "", username: ""))
        case ("POST", "/login"):
            let server = (r.body["server"] ?? "").trimmingCharacters(in: .whitespaces)
            let username = (r.body["username"] ?? "").trimmingCharacters(in: .whitespaces)
            let password = r.body["password"] ?? ""
            guard (r.body["pin"] ?? "").trimmingCharacters(in: .whitespaces) == pin else {
                wrong += 1
                if wrong >= 5 { wrong = 0; pin = Self.newPin() }
                send("200 OK", page(pin: "", error: "That PIN doesn't match the one on the screen.", server: server, username: username))
                return
            }
            guard !server.isEmpty, !username.isEmpty, !password.isEmpty else {
                send("200 OK", page(pin: pin, error: "Fill in the server, username and password.", server: server, username: username))
                return
            }
            ConnLog.add("Phone setup: details received")
            let full = server.hasPrefix("http") ? server : "http://\(server)"
            if let error = await onLogin(XtreamCredentials(server: full, username: username, password: password)) {
                send("200 OK", page(pin: pin, error: error, server: server, username: username))
            } else {
                send("200 OK", done())
            }
        default:
            send("404 Not Found", "<h1>Not found</h1>")
        }
    }

    // MARK: Pages (the same as Android's)

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private let style = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{margin:0;background:#0E1116;color:#F2F4F7;font:16px -apple-system,system-ui,sans-serif;padding:28px 20px}
          h1{font-size:24px;margin:0 0 4px} p{color:#9AA3B2;margin:0 0 20px}
          label{display:block;font-size:13px;color:#9AA3B2;margin:14px 0 6px}
          input{width:100%;box-sizing:border-box;background:#171B22;color:#F2F4F7;border:1.5px solid #2E3643;
                border-radius:10px;padding:12px;font-size:16px}
          input:focus{outline:none;border-color:#FF8A3D}
          button{width:100%;margin-top:24px;background:#FF8A3D;color:#14100C;border:0;border-radius:10px;padding:14px;
                 font-size:17px;font-weight:600}
          .err{background:#3a1d1d;color:#F87171;border-radius:10px;padding:12px;margin-bottom:8px}
          .ok{font-size:56px;color:#4ADE80;margin:30px 0 10px}
        </style>
        """

    private func page(pin: String, error: String?, server: String, username: String) -> String {
        """
        <!doctype html><html><head><title>Courtside setup</title>\(style)</head><body>
        <h1>Courtside</h1><p>Send your Xtream Codes details to \(Self.deviceWord).</p>
        \(error.map { "<div class=\"err\">\(esc($0))</div>" } ?? "")
        <form method="post" action="/login" onsubmit="this.querySelector('button').textContent='Signing in…'">
          <label>Server</label><input name="server" type="url" inputmode="url" autocapitalize="off" autocorrect="off"
            placeholder="http://example.com:8080" value="\(esc(server))" required>
          <label>Username</label><input name="username" autocapitalize="off" autocorrect="off" autocomplete="username"
            value="\(esc(username))" required>
          <label>Password</label><input name="password" type="password" autocomplete="current-password" required>
          <label>PIN on the screen</label><input name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="4"
            value="\(esc(pin))" required>
          <button type="submit">Send to \(Self.deviceWord)</button>
        </form></body></html>
        """
    }

    private func done() -> String {
        """
        <!doctype html><html><head><title>Courtside setup</title>\(style)</head><body style="text-align:center">
        <div class="ok">✓</div><h1>Signed in</h1><p>Courtside is loading your channels. You can close this page.</p>
        </body></html>
        """
    }

    #if os(tvOS)
    static let deviceWord = "the TV"
    #else
    static let deviceWord = "the Mac"
    #endif

    private static func newPin() -> String { String(Int.random(in: 1000...9999)) }

    // MARK: Address and QR code

    /// This device's address on the home network (Ethernet or Wi-Fi), or nil when it isn't on one.
    nonisolated static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [(name: String, address: String)] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(truncatingIfNeeded: p.pointee.ifa_flags)
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let address = String(cString: host)
            // Private home-network ranges only.
            let parts = address.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4 else { continue }
            let home = parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
            if home { found.append((String(cString: p.pointee.ifa_name), address)) }
        }
        return found.sorted { ($0.name.hasPrefix("en") ? 0 : 1) < ($1.name.hasPrefix("en") ? 0 : 1) }.first?.address
    }

    nonisolated static func qr(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}

/// Beside the sign-in fields: QR code, address and PIN, while the setup page is on.
struct PhoneSetupPanel: View {
    @StateObject private var server: PhoneSetupServer
    @State private var address = PhoneSetupServer.localAddress()
    /// Sizes for the TV (big) or the Mac.
    var scale: CGFloat

    init(scale: CGFloat = 1, onLogin: @escaping (XtreamCredentials) async -> String?) {
        _server = StateObject(wrappedValue: PhoneSetupServer(onLogin: onLogin))
        self.scale = scale
    }

    private var base: String? {
        guard let address, server.port != 0 else { return nil }
        return server.port == 80 ? "http://\(address)" : "http://\(address):\(server.port)"
    }

    var body: some View {
        VStack(spacing: 6 * scale) {
            Text("Or set up from your phone")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(Color.white)
            if let base, let code = PhoneSetupServer.qr("\(base)/?pin=\(server.pin)") {
                Text("Scan with your phone's camera")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Color.white.opacity(0.6))
                Image(decorative: code, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 184 * scale, height: 184 * scale)
                    .padding(8 * scale)
                    .background(RoundedRectangle(cornerRadius: 12 * scale).fill(Color.white))
                    .padding(.vertical, 8 * scale)
                Text("or go to")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(base.replacingOccurrences(of: "http://", with: ""))
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("PIN  \(server.pin)")
                    .font(.system(size: 20 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.54, blue: 0.24))
                    .padding(.top, 4 * scale)
                Text("Your phone needs to be on the same Wi-Fi.")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Text(address == nil ? "Connect to your home network to use your phone." : "Starting…")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 300 * scale)
        .onAppear { server.start() }
        .onDisappear { server.stop() }
    }
}

#endif
