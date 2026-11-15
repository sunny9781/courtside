import Foundation
#if !os(macOS)
import Security
#endif

/// Mac: saves the Xtream login in a private file in the app's Application Support folder,
/// readable only by your macOS user account (permissions 600).
/// Used instead of the Keychain because development builds are re-signed on every build,
/// which made macOS ask for your password each launch.
/// Apple TV: apps can't keep files there, so the login goes in the Apple TV's Keychain, which keeps it through
/// app updates and reinstalls (and never prompts on tvOS).
enum CredentialStore {
    #if !os(macOS)
    private static let service = "ca.sunny9781.courtside"
    private static let account = "xtream-login"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ credentials: XtreamCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> XtreamCredentials? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(XtreamCredentials.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
    #else
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
    #endif
}
