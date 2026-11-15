import Foundation

/// Saves the Xtream login in a private file in the app's Application Support folder,
/// readable only by your macOS user account (permissions 600).
/// Used instead of the Keychain because development builds are re-signed on every build,
/// which made macOS ask for your password each launch.
enum CredentialStore {
    private static var file: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Courtside", isDirectory: true).appendingPathComponent("login.json")
    }

    @discardableResult
    static func save(_ credentials: XtreamCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }

    static func load() -> XtreamCredentials? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(XtreamCredentials.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: file)
    }
}
