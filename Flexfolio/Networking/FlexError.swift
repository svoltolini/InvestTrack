import Foundation

/// Errors from the Flex Web Service flow, mapped to actionable user-facing
/// text. IBKR error codes per the Flex Web Service reference.
enum FlexError: LocalizedError, Equatable {
    case notConfigured
    case network(String)
    case http(Int)
    case badResponse
    case timedOut
    case ibkr(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No IBKR credentials yet — add your Flex token and Query ID in Settings."
        case .network(let detail):
            return "Couldn't reach Interactive Brokers. \(detail)"
        case .http(let status):
            return "Interactive Brokers returned HTTP \(status). Try again later."
        case .badResponse:
            return "Interactive Brokers sent an unexpected response. Try again later."
        case .timedOut:
            return "IBKR is still generating the statement — it didn't finish within a minute. Try again shortly."
        case .ibkr(let code, let message):
            switch code {
            case 1003:
                return "Query not found — check the Query ID in Settings."
            case 1012, 1015:
                return "Your Flex token is invalid or expired. Regenerate it in IBKR Client Portal (Performance & Reports → Flex Queries) and update Settings. Set expiry to 1 year."
            case 1018:
                return "Too many requests to IBKR — wait a moment and try again."
            default:
                return "IBKR error \(code): \(message)"
            }
        }
    }

    /// True when fixing the problem means editing credentials — the error
    /// banner deep-links to Settings for these.
    var isCredentialError: Bool {
        switch self {
        case .notConfigured:
            return true
        case .ibkr(let code, _):
            return [1003, 1012, 1015].contains(code)
        default:
            return false
        }
    }
}
