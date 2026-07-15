import Foundation

/// Configuration for the Saxo Bank OpenAPI connection.
///
/// To connect the app to a real Saxo account you need your own app key:
/// 1. Create a developer account at https://www.developer.saxo (free for the
///    Simulation environment; Live requires a funded Saxo account + approval).
/// 2. Register an application under "Application Management" with grant type
///    **PKCE**. Saxo only accepts `http(s)` redirect URLs — not custom
///    schemes — so register the URL of the bounce page in `web/saxo-callback/`
///    and set `redirectURI` below to match.
/// 3. Paste the app key into `appKey` and pick the matching `environment`.
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

    /// Which Saxo environment to talk to. Leave as `.simulation` for the
    /// developer-token demo; set to `.live` once you have a Live app key.
    var environment: Environment = .simulation

    /// The application key from Saxo's developer portal. Live and Simulation
    /// apps have separate keys — use the one matching `environment`.
    var appKey: String = "PASTE_YOUR_SAXO_APP_KEY_HERE"

    /// The `https` redirect registered on the Saxo app. Saxo rejects custom
    /// URL schemes, so this is the address of the hosted bounce page (the
    /// `web/saxo-callback/` file); it forwards the login result to
    /// `callbackScheme`. Must match the portal registration exactly.
    var redirectURI: String = "https://YOUR-USERNAME.github.io/InvestTrack/saxo-callback/"

    /// Custom scheme the bounce page redirects to and that the in-app login
    /// sheet intercepts. Does not need Info.plist registration — the login
    /// session (ASWebAuthenticationSession) captures it directly.
    var callbackScheme = "investtrack"

    /// Full custom-scheme URL the bounce page forwards to. Keep the page's
    /// redirect target and this value in sync.
    var callbackURL: String { "\(callbackScheme)://saxo-callback" }

    /// True once a real app key has been pasted in.
    var isConfigured: Bool {
        !appKey.isEmpty && appKey != "PASTE_YOUR_SAXO_APP_KEY_HERE"
    }

    static let `default` = SaxoConfiguration()
}
