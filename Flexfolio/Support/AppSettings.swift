import Foundation
import Observation

/// Non-secret app state: whether credentials exist (the values themselves stay
/// in the Keychain) and when the current token was saved, for the 11-month
/// expiry warning. IBKR tokens live at most 1 year.
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let tokenCreatedAt = "flexfolio.tokenCreatedAt"
    }

    private(set) var hasCredentials: Bool
    private(set) var tokenCreatedAt: Date?

    init() {
        hasCredentials = KeychainStore.hasCredentials
        tokenCreatedAt = UserDefaults.standard.object(forKey: Keys.tokenCreatedAt) as? Date
    }

    /// Persists credentials to the Keychain; records the token save date only
    /// when the token actually changed, so re-saving the query ID doesn't
    /// reset the expiry clock.
    func saveCredentials(token: String, queryID: String) {
        let tokenChanged = token.trimmingCharacters(in: .whitespacesAndNewlines) != KeychainStore.token
        KeychainStore.save(token: token, queryID: queryID)
        if tokenChanged {
            tokenCreatedAt = .now
            UserDefaults.standard.set(tokenCreatedAt, forKey: Keys.tokenCreatedAt)
        }
        hasCredentials = KeychainStore.hasCredentials
    }

    func deleteCredentials() {
        KeychainStore.deleteAll()
        UserDefaults.standard.removeObject(forKey: Keys.tokenCreatedAt)
        tokenCreatedAt = nil
        hasCredentials = false
    }

    /// Passive warning threshold: tokens cap at 1 year; warn from 11 months.
    var tokenNearingExpiry: Bool {
        guard let tokenCreatedAt else { return false }
        return Date.now.timeIntervalSince(tokenCreatedAt) > 335 * 86_400
    }
}
