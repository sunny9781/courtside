import SwiftUI

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    /// Settings › Account › Edit account: starts filled in, and saves instead of signing in.
    var editing: XtreamCredentials? = nil
    var onDone: (() -> Void)? = nil
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

                Text(editing == nil ? "Sign in with your Xtream Codes details. They're saved privately on this Mac and never leave it."
                                    : "Change your Xtream Codes details. They're checked before they're saved.")
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
                    Button(editing == nil ? "Sign in" : "Save") {
                        Task { await signIn() }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)

                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let onDone {
                        Spacer()
                        Button("Cancel", action: onDone)
                            .buttonStyle(GhostButtonStyle())
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(36)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
        .onAppear {
            if let editing { server = editing.server; username = editing.username; password = editing.password }
        }
    }

    private func signIn() async {
        busy = true
        if editing != nil {
            message = await model.updateAccount(server: server.trimmingCharacters(in: .whitespaces),
                                                username: username.trimmingCharacters(in: .whitespaces), password: password)
            busy = false
            if message == nil { onDone?() }
            return
        }
        message = await model.signIn(server: server, username: username, password: password)
        busy = false
    }
}
