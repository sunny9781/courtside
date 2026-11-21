import SwiftUI

/// Settings › Proxy (2.33): Courtside's provider traffic (sign-in, channels, guide, streams) through a SOCKS5, HTTPS
/// or HTTP proxy. Only this app uses it.
struct IOSProxySection: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var draft = ProxyDraft()

    var body: some View {
        Section {
            LabeledContent("In use", value: draft.saved)
            Picker("Type", selection: Binding(get: { draft.kind }, set: { draft.pick($0) })) {
                ForEach(ProxyKind.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Proxy")
        } footer: {
            Text("Sends Courtside's connections to your provider through a proxy: sign-in, channels, the guide and every stream. The rest of the phone isn't affected, and if the proxy can't be reached nothing connects directly instead. Chromecast fetches the stream itself (not through the proxy); AirPlay sends the picture from this phone.")
        }
        if draft.kind != .off {
            Section {
                TextField("Address (proxy.example.com)", text: $draft.host)
                    .keyboardType(.URL)
                TextField("Port (\(draft.kind.defaultPort))", text: $draft.port)
                    .keyboardType(.numberPad)
                TextField("Username (optional)", text: $draft.username)
                SecureField("Password", text: $draft.password)
            } header: {
                Text("Server")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section {
            if draft.kind != .off {
                Button(draft.testing ? "Testing…" : "Test") { draft.test(model.credentials) }
                    .disabled(draft.testing)
            }
            Button(draft.kind == .off ? "Save (proxy off)" : "Save") { draft.save(model) }
                .disabled(!draft.changed)
        } footer: {
            if let result = draft.result {
                Text(result.text).foregroundStyle(result.ok ? Theme.accent : Theme.danger)
            } else {
                Text("Test signs in to your provider through the proxy without saving. After saving, new streams and downloads use it.")
            }
        }
    }
}
