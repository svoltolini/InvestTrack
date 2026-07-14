import Foundation

enum SaxoAPIError: LocalizedError {
    case notAuthenticated
    case sessionExpired
    case notEntitled
    case rateLimited
    case transport
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not signed in to Saxo."
        case .sessionExpired:
            "Your Saxo session has expired — please sign in again."
        case .notEntitled:
            "This Saxo endpoint is not enabled for the app."
        case .rateLimited:
            "Saxo rate limit reached — try again in a moment."
        case .transport:
            "Couldn't reach Saxo. Check your connection."
        case .server(let status, let message):
            "Saxo request failed (HTTP \(status))\(message.map { ": \($0)" } ?? "")."
        }
    }
}

/// Standard OpenAPI 4xx error body.
struct SaxoErrorBody: Decodable {
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "ErrorCode"
        case message = "Message"
    }
}

/// Authenticated GET client for the Saxo OpenAPI gateway.
///
/// Owns the token pair: refreshes the access token when needed (Saxo rotates
/// the refresh token on every refresh, so the newest pair is persisted to the
/// Keychain immediately) and retries a request once after a 401.
actor SaxoAPIClient {
    private let configuration: SaxoConfiguration
    private var tokens: SaxoTokens?
    private static let decoder = JSONDecoder()

    init(configuration: SaxoConfiguration) {
        self.configuration = configuration
        self.tokens = KeychainStore.loadTokens()
    }

    var hasUsableSession: Bool {
        tokens?.hasUsableSession ?? false
    }

    func adopt(_ tokens: SaxoTokens) {
        self.tokens = tokens
        KeychainStore.saveTokens(tokens)
    }

    func signOut() {
        tokens = nil
        KeychainStore.deleteTokens()
    }

    func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var attemptedRefresh = false
        while true {
            let accessToken = try await validAccessToken()

            guard var components = URLComponents(
                url: configuration.environment.apiBaseURL,
                resolvingAgainstBaseURL: false
            ) else { throw SaxoAPIError.transport }
            components.path += path
            if !query.isEmpty {
                components.queryItems = query
            }
            guard let url = components.url else { throw SaxoAPIError.transport }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw SaxoAPIError.transport
            }
            guard let http = response as? HTTPURLResponse else { throw SaxoAPIError.transport }

            switch http.statusCode {
            case 200:
                do {
                    return try Self.decoder.decode(T.self, from: data)
                } catch {
                    throw SaxoAPIError.server(status: 200, message: "unexpected response shape (\(error))")
                }
            case 401 where !attemptedRefresh:
                attemptedRefresh = true
                // Force a refresh (or sessionExpired) on the next loop pass.
                tokens?.accessTokenExpiry = .distantPast
                continue
            case 401:
                throw SaxoAPIError.sessionExpired
            case 403:
                throw SaxoAPIError.notEntitled
            case 429:
                throw SaxoAPIError.rateLimited
            default:
                let body = try? Self.decoder.decode(SaxoErrorBody.self, from: data)
                throw SaxoAPIError.server(status: http.statusCode, message: body?.message)
            }
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw SaxoAPIError.notAuthenticated }
        if current.isAccessTokenValid {
            return current.accessToken
        }
        guard current.canRefresh else {
            signOut()
            throw SaxoAPIError.sessionExpired
        }
        do {
            let response = try await SaxoTokenClient.refresh(current, configuration: configuration)
            var refreshed = SaxoTokens.from(response: response, codeVerifier: current.codeVerifier)
            // Some responses may omit a new refresh token; keep the old one then.
            if refreshed.refreshToken == nil {
                refreshed.refreshToken = current.refreshToken
                refreshed.refreshTokenExpiry = current.refreshTokenExpiry
            }
            adopt(refreshed)
            return refreshed.accessToken
        } catch {
            signOut()
            throw SaxoAPIError.sessionExpired
        }
    }
}
