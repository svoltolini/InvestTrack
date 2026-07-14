import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

// MARK: - PKCE (RFC 7636)

enum PKCE {
    /// Random URL-safe string; 48 random bytes → 64 base64url chars,
    /// within the RFC's 43–128 length and `[A-Za-z0-9-._~]` charset.
    static func randomURLSafeString(byteCount: Int = 48) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max)
            }
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Tokens

struct SaxoTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
    }
}

/// Persisted session state. Saxo rotates the refresh token on every refresh,
/// so this must be saved immediately after each token response.
struct SaxoTokens: Codable {
    var accessToken: String
    var accessTokenExpiry: Date
    var refreshToken: String?
    var refreshTokenExpiry: Date?
    /// Saxo's PKCE refresh grant includes a code_verifier.
    var codeVerifier: String?
    /// 24-hour tokens from the developer portal cannot be refreshed.
    var isDeveloperToken: Bool

    var isAccessTokenValid: Bool {
        Date.now < accessTokenExpiry.addingTimeInterval(-60)
    }

    var canRefresh: Bool {
        guard !isDeveloperToken,
              let refreshToken, !refreshToken.isEmpty,
              let refreshTokenExpiry else { return false }
        return Date.now < refreshTokenExpiry.addingTimeInterval(-30)
    }

    var hasUsableSession: Bool {
        isAccessTokenValid || canRefresh
    }

    static func from(response: SaxoTokenResponse, codeVerifier: String?, now: Date = .now) -> SaxoTokens {
        SaxoTokens(
            accessToken: response.accessToken,
            accessTokenExpiry: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            refreshToken: response.refreshToken,
            refreshTokenExpiry: response.refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
            codeVerifier: codeVerifier,
            isDeveloperToken: false
        )
    }

    static func developerToken(_ token: String, now: Date = .now) -> SaxoTokens {
        SaxoTokens(
            accessToken: token,
            // Portal tokens last 24h; we don't know when this one was issued,
            // so assume it is fresh and let 401 handling catch early expiry.
            accessTokenExpiry: now.addingTimeInterval(23 * 3600),
            refreshToken: nil,
            refreshTokenExpiry: nil,
            codeVerifier: nil,
            isDeveloperToken: true
        )
    }
}

// MARK: - Keychain persistence

enum KeychainStore {
    private static let service = "com.svoltolini.InvestTrack.saxo"
    private static let account = "tokens"

    static func saveTokens(_ tokens: SaxoTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadTokens() -> SaxoTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SaxoTokens.self, from: data)
    }

    static func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum SaxoAuthError: LocalizedError {
    case notConfigured
    case invalidConfiguration
    case cancelled
    case missingCallback
    case stateMismatch
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No Saxo app key is configured. Add your app key in SaxoConfiguration.swift, or connect with a developer token."
        case .invalidConfiguration:
            "The Saxo configuration is invalid — check the app key and redirect URI."
        case .cancelled:
            "Sign-in was cancelled."
        case .missingCallback:
            "Saxo did not return an authorization code."
        case .stateMismatch:
            "The sign-in response failed validation (state mismatch)."
        case .tokenRequestFailed(let message):
            "Saxo token request failed: \(message)"
        }
    }
}

// MARK: - Interactive sign-in

/// Runs the OAuth 2.0 Authorization Code + PKCE flow against Saxo's
/// logonvalidation endpoints using ASWebAuthenticationSession.
@MainActor
final class SaxoAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func authorize(configuration: SaxoConfiguration) async throws -> SaxoTokens {
        guard configuration.isConfigured else { throw SaxoAuthError.notConfigured }

        let verifier = PKCE.randomURLSafeString()
        let state = PKCE.randomURLSafeString(byteCount: 24)

        var components = URLComponents(
            url: configuration.environment.authBaseURL.appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.appKey),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge", value: PKCE.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components?.url else { throw SaxoAuthError.invalidConfiguration }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: configuration.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: SaxoAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SaxoAuthError.missingCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
        activeSession = nil

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw SaxoAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SaxoAuthError.missingCallback
        }

        let response = try await SaxoTokenClient.exchangeCode(
            code,
            verifier: verifier,
            configuration: configuration
        )
        return .from(response: response, codeVerifier: verifier)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Token endpoint

enum SaxoTokenClient {
    static func exchangeCode(
        _ code: String,
        verifier: String,
        configuration: SaxoConfiguration
    ) async throws -> SaxoTokenResponse {
        try await requestToken(configuration: configuration, parameters: [
            ("grant_type", "authorization_code"),
            ("client_id", configuration.appKey),
            ("code", code),
            ("redirect_uri", configuration.redirectURI),
            ("code_verifier", verifier),
        ])
    }

    static func refresh(
        _ tokens: SaxoTokens,
        configuration: SaxoConfiguration
    ) async throws -> SaxoTokenResponse {
        guard let refreshToken = tokens.refreshToken else {
            throw SaxoAuthError.tokenRequestFailed("no refresh token")
        }
        var parameters: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", configuration.appKey),
        ]
        // Saxo's documented PKCE refresh includes a code_verifier.
        if let verifier = tokens.codeVerifier {
            parameters.append(("code_verifier", verifier))
        }
        return try await requestToken(configuration: configuration, parameters: parameters)
    }

    private static func requestToken(
        configuration: SaxoConfiguration,
        parameters: [(String, String)]
    ) async throws -> SaxoTokenResponse {
        var request = URLRequest(url: configuration.environment.authBaseURL.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(parameters).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SaxoAuthError.tokenRequestFailed("no HTTP response")
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SaxoAuthError.tokenRequestFailed("HTTP \(http.statusCode) \(body.prefix(200))")
        }
        return try JSONDecoder().decode(SaxoTokenResponse.self, from: data)
    }

    private static func formEncoded(_ parameters: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }
}
