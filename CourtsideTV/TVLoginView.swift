import SwiftUI

struct TVLoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(spacing: 36) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 90))
                .foregroundStyle(Theme.accent)
            Text("Courtside")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("Sign in with your IPTV provider's Xtream Codes login.")
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
            .frame(width: 900)

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
                    Text(working ? "Signing in…" : "Sign in")
                }
                .frame(width: 360)
            }
            .disabled(working || server.isEmpty || username.isEmpty || password.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signIn() async {
        working = true
        error = await model.signIn(server: server.trimmingCharacters(in: .whitespaces),
                                   username: username.trimmingCharacters(in: .whitespaces),
                                   password: password)
        working = false
    }
}
