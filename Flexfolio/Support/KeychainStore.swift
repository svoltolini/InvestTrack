import Foundation
import Security

/// Keychain-backed storage for the two IBKR Flex secrets. Generic-password
/// items, `kSecAttrAccessibleAfterFirstUnlock`. Secrets never touch
/// UserDefaults, source files, or logs.
enum KeychainStore {
    struct Credentials {
        let token: String
        let queryID: String
    }

    private static let service = "com.svoltolini.Flexfolio"
    private static let tokenAccount = "flex.token"
    private static let queryIDAccount = "flex.queryID"

    // MARK: - Public API

    static var token: String? { load(account: tokenAccount) }
    static var queryID: String? { load(account: queryIDAccount) }

    /// Both secrets, or nil when either is missing — sync can't run on half a
    /// credential pair.
    static func loadCredentials() -> Credentials? {
        guard let token, !token.isEmpty, let queryID, !queryID.isEmpty else { return nil }
        return Credentials(token: token, queryID: queryID)
    }

    static var hasCredentials: Bool { loadCredentials() != nil }

    static func save(token: String, queryID: String) {
        save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: tokenAccount)
        save(queryID.trimmingCharacters(in: .whitespacesAndNewlines), account: queryIDAccount)
    }

    static func deleteAll() {
        delete(account: tokenAccount)
        delete(account: queryIDAccount)
    }

    // MARK: - Primitives

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func save(_ value: String, account: String) {
        delete(account: account)
        guard !value.isEmpty else { return }
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
