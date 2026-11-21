import SwiftUI

struct TVLoginView: View {
    @EnvironmentObject var model: AppModel
    /// Settings › Account › Edit account: starts filled in, and saves instead of signing in.
    var editing: XtreamCredentials? = nil
    var onDone: (() -> Void)? = nil
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        HStack(alignment: .center, spacing: 90) {
            form
            // Or from your phone (2.21, like Android TV): QR code, address and PIN.
            PhoneSetupPanel(scale: 1.6) { creds in await phoneLogin(creds) }
                .padding(40)
                .background(RoundedRectangle(cornerRadius: 30).fill(Theme.card))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let editing { server = editing.server; username = editing.username; password = editing.password }
        }
    }

    private var form: some View {
        VStack(spacing: 36) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 90))
                .foregroundStyle(Theme.accent)
            Text("Courtside")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(editing == nil ? "Sign in with your IPTV provider's Xtream Codes login." : "Change your Xtream Codes login.")
                .font(.system(size: 26))
                .foregroundStyle(Theme.muted)

            VStack(spacing: 20) {
                TextField("Server, for example http://example.com:8080", text: $server)
                    .keyboardType(.URL)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(width: 820)

            if let error {
                Text(error)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 16) {
                    if working { ProgressView() }
                    Text(working ? (editing == nil ? "Signing in…" : "Checking…") : (editing == nil ? "Sign in" : "Save"))
                }
                .frame(width: 360)
            }
            .disabled(working || server.isEmpty || username.isEmpty || password.isEmpty)

            if let onDone {
                Button("Cancel", action: onDone)
            }
        }
    }

    /// Details sent from the phone: signs in (or saves, when editing) the same way the form does.
    private func phoneLogin(_ creds: XtreamCredentials) async -> String? {
        let error = editing == nil
            ? await model.signIn(server: creds.server, username: creds.username, password: creds.password)
            : await model.updateAccount(server: creds.server, username: creds.username, password: creds.password)
        if error == nil { onDone?() }
        return error
    }

    private func signIn() async {
        working = true
        let s = server.trimmingCharacters(in: .whitespaces), u = username.trimmingCharacters(in: .whitespaces)
        error = editing == nil ? await model.signIn(server: s, username: u, password: password)
                               : await model.updateAccount(server: s, username: u, password: password)
        working = false
        if error == nil { onDone?() }
    }
}
