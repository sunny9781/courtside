import SwiftUI

/// Settings › Proxy (2.33): Courtside's provider traffic (sign-in, channels, guide, streams) through a SOCKS5, HTTPS
/// or HTTP proxy. Only this app uses it (IINA or VLC as the player get the stream from the app too).
struct MacProxyPanel: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var draft = ProxyDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proxy")
                .font(Theme.display(18))
                .foregroundStyle(Theme.text)
            Text("Sends Courtside's connections to your provider through a proxy: sign-in, channels, the guide and every stream. The rest of the Mac isn't affected, and if the proxy can't be reached nothing connects directly instead.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("In use").foregroundStyle(Theme.muted)
                Spacer()
                Text(draft.saved).foregroundStyle(Theme.text)
            }
            .font(.system(size: 14))
            Picker("", selection: Binding(get: { draft.kind }, set: { draft.pick($0) })) {
                ForEach(ProxyKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            if draft.kind != .off {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Address").foregroundStyle(Theme.muted)
                        TextField("proxy.example.com", text: $draft.host)
                    }
                    GridRow {
                        Text("Port").foregroundStyle(Theme.muted)
                        TextField(String(draft.kind.defaultPort), text: $draft.port).frame(width: 100)
                    }
                    GridRow {
                        Text("Username").foregroundStyle(Theme.muted)
                        TextField("optional", text: $draft.username)
                    }
                    GridRow {
                        Text("Password").foregroundStyle(Theme.muted)
                        SecureField("optional", text: $draft.password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .frame(maxWidth: 460)
            }
            HStack(spacing: 12) {
                if draft.kind != .off {
                    Button(draft.testing ? "Testing…" : "Test") { draft.test(model.credentials) }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(draft.testing)
                }
                Button(draft.kind == .off ? "Save (proxy off)" : "Save") { draft.save(model) }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(!draft.changed)
                if let result = draft.result {
                    Text(result.text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(result.ok ? Theme.accent : Theme.danger)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}
