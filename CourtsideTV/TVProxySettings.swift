import SwiftUI

/// Settings › Proxy (2.33): Courtside's provider traffic (sign-in, channels, guide, streams) through a SOCKS5, HTTPS
/// or HTTP proxy. Only this app uses it.
struct TVProxySection: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var draft = ProxyDraft()

    var body: some View {
        Text("Sends Courtside's connections to your provider through a proxy: sign-in, channels, the guide and every stream. The rest of the Apple TV isn't affected. If the proxy can't be reached, nothing connects directly instead.")
            .font(.system(size: 20))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        info("In use", draft.saved)
        Button { draft.pick(draft.kind.next) } label: {
            TVSettingRow(title: "Type", detail: "SOCKS5, HTTPS (an HTTP proxy reached over TLS) or HTTP.",
                         value: draft.kind.title)
        }
        .buttonStyle(TVRowButtonStyle())
        if draft.kind != .off {
            VStack(spacing: 16) {
                TextField("Proxy address, for example proxy.example.com", text: $draft.host)
                    .keyboardType(.URL)
                TextField("Port (\(draft.kind.defaultPort))", text: $draft.port)
                    .keyboardType(.numberPad)
                TextField("Username (if it needs one)", text: $draft.username)
                SecureField("Password", text: $draft.password)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 26))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            Button { draft.test(model.credentials) } label: {
                TVSettingRow(title: draft.testing ? "Testing…" : "Test",
                             detail: "Signs in to your provider through the proxy, without saving.", value: nil)
            }
            .buttonStyle(TVRowButtonStyle())
            .disabled(draft.testing)
        }
        Button { draft.save(model) } label: {
            TVSettingRow(title: draft.kind == .off ? "Save (proxy off)" : "Save",
                         detail: "New streams and downloads use it. A stream already playing keeps its connection until you switch.",
                         value: draft.changed ? nil : "Saved")
        }
        .buttonStyle(TVRowButtonStyle())
        if let result = draft.result {
            Text(result.text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(result.ok ? Theme.accent : Theme.danger)
                .padding(.horizontal, 22)
                .padding(.top, 6)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.text)
        }
        .font(.system(size: 26))
        .padding(.horizontal, 22)
        .frame(minHeight: 72)
    }
}
