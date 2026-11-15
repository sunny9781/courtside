import SwiftUI

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "basketball.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Courtside")
                        .foregroundStyle(Theme.text)
                }
                .font(Theme.display(28))

                Text("Sign in with your Xtream Codes details. They're saved privately on this Mac and never leave it.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Field(placeholder: "Server, for example http://example.com:8080", text: $server)
                    Field(placeholder: "Username", text: $username)
                    Field(placeholder: "Password", text: $password, secure: true)
                }

                if let message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.danger)
                }

                HStack(spacing: 12) {
                    Button("Sign in") {
                        Task { await signIn() }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)

                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(36)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }

    private func signIn() async {
        busy = true
        message = await model.signIn(server: server, username: username, password: password)
        busy = false
    }
}
