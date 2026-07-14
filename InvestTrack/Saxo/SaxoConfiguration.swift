import Foundation

/// Configuration for the Saxo Bank OpenAPI connection.
///
/// To connect the app to a real Saxo account you need your own app key:
/// 1. Create a free developer account at https://www.developer.saxo
/// 2. Register an application under "Application Management" with grant type
///    **PKCE** and the redirect URI below.
/// 3. Paste the app key into `appKey`.
/// See SAXO_SETUP.md for the full walkthrough (including the zero-setup
/// 24-hour developer-token option that needs no app registration).
struct SaxoConfiguration {
    enum Environment: String {
        case simulation
        case live

        var authBaseURL: URL {
            switch self {
            case .simulation: URL(string: "https://sim.logonvalidation.net")!
            case .live: URL(string: "https://live.logonvalidation.net")!
            }
        }

        var apiBaseURL: URL {
            switch self {
            case .simulation: URL(string: "https://gateway.saxobank.com/sim/openapi")!
            case .live: URL(string: "https://gateway.saxobank.com/openapi")!
            }
        }

        var displayName: String {
            switch self {
            case .simulation: "Simulation"
            case .live: "Live"
            }
        }
    }

    var environment: Environment = .simulation

    /// The application key from Saxo's developer portal.
    var appKey: String = "PASTE_YOUR_SAXO_APP_KEY_HERE"

    /// Must exactly match a redirect URI registered on the Saxo app.
    ///
    /// Saxo's documentation only shows http(s) redirect examples for PKCE
    /// apps; if the portal rejects a custom scheme, see SAXO_SETUP.md for
    /// alternatives (Saxo's support can enable it, or use a developer token).
    var redirectURI: String = "investtrack://saxo-callback"

    /// True once a real app key has been pasted in.
    var isConfigured: Bool {
        !appKey.isEmpty && appKey != "PASTE_YOUR_SAXO_APP_KEY_HERE"
    }

    var callbackScheme: String? {
        URL(string: redirectURI)?.scheme
    }

    static let `default` = SaxoConfiguration()
}
