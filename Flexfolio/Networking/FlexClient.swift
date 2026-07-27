import Foundation

/// The IBKR Flex Web Service two-step flow. Read-only, plain HTTPS GETs, and
/// the mandatory `User-Agent` on every request. Tokens are only ever placed in
/// the request URL — never logged, never persisted here.
struct FlexClient {
    private static let sendRequestURL =
        URL(string: "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest")!
    private static let userAgent = "Flexfolio/1.0"

    /// 1019 polling backoff; ~50 s of waiting keeps total under the 60 s cap.
    private static let pollDelaysSeconds: [Double] = [3, 5, 8, 13, 21]

    // MARK: - Step 1

    /// Requests statement generation. Returns the reference code and the
    /// statement URL to poll. Also serves as Settings' "Test connection".
    func requestStatement(token: String, queryID: String) async throws -> (reference: String, statementURL: URL) {
        let response = try await serviceRequest(
            base: Self.sendRequestURL,
            queryItems: [
                URLQueryItem(name: "t", value: token),
                URLQueryItem(name: "q", value: queryID),
                URLQueryItem(name: "v", value: "3"),
            ]
        )
        guard case .serviceResponse(let service) = response else {
            // Step 1 never returns a statement document.
            throw FlexError.badResponse
        }
        if service.isSuccess, let reference = service.referenceCode {
            let url = service.url.flatMap(URL.init(string:))
                ?? URL(string: "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/GetStatement")!
            return (reference, url)
        }
        throw Self.error(from: service)
    }

    // MARK: - Step 2

    /// Fetches the generated statement, polling through ErrorCode 1019
    /// (in progress) with backoff, giving up after ~60 s.
    func fetchStatement(statementURL: URL, reference: String, token: String) async throws -> ParsedStatement {
        let queryItems = [
            URLQueryItem(name: "q", value: reference),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "v", value: "3"),
        ]
        var remainingDelays = Self.pollDelaysSeconds[...]
        while true {
            let result = try await serviceRequest(base: statementURL, queryItems: queryItems)
            switch result {
            case .statement(let statement):
                return statement
            case .serviceResponse(let service) where service.isInProgress:
                guard let delay = remainingDelays.popFirst() else {
                    throw FlexError.timedOut
                }
                try await Task.sleep(for: .seconds(delay))
            case .serviceResponse(let service):
                throw Self.error(from: service)
            }
        }
    }

    // MARK: - Transport

    /// One HTTPS GET → parsed Flex document. IBKR error 1018 (too many
    /// requests) is retried once after 10 s before being surfaced.
    private func serviceRequest(base: URL, queryItems: [URLQueryItem]) async throws -> FlexParseResult {
        do {
            return try await send(base: base, queryItems: queryItems)
        } catch FlexError.ibkr(code: 1018, let message) {
            try await Task.sleep(for: .seconds(10))
            do {
                return try await send(base: base, queryItems: queryItems)
            } catch FlexError.ibkr(code: 1018, _) {
                throw FlexError.ibkr(code: 1018, message: message)
            }
        }
    }

    private func send(base: URL, queryItems: [URLQueryItem]) async throws -> FlexParseResult {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw FlexError.badResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw FlexError.badResponse }

        #if DEBUG
        if let canned = DebugCannedResponses.response(for: queryItems) {
            return try Self.parseChecked(canned)
        }
        #endif

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Deliberately not logging the error object: the failing URL it
            // carries would contain the token.
            throw FlexError.network("Check your connection.")
        }
        guard let http = response as? HTTPURLResponse else { throw FlexError.badResponse }
        guard http.statusCode == 200 else { throw FlexError.http(http.statusCode) }
        return try Self.parseChecked(data)
    }

    /// Parses a response body, converting an error-bearing service response
    /// into the thrown `FlexError` — except 1019, which the poll loop handles.
    private static func parseChecked(_ data: Data) throws -> FlexParseResult {
        let result = try FlexResponseParser.parse(data)
        if case .serviceResponse(let service) = result,
           !service.isSuccess, !service.isInProgress {
            throw error(from: service)
        }
        return result
    }

    private static func error(from service: FlexServiceResponse) -> FlexError {
        if let code = service.errorCode {
            return .ibkr(code: code, message: service.errorMessage ?? "no message")
        }
        return .badResponse
    }
}

#if DEBUG
/// Canned XML for exercising the error mapping without network or with dummy
/// credentials (acceptance §11.2): enter token `debug-1012`, `debug-1003`, or
/// `debug-1019` in Settings and hit "Test connection".
enum DebugCannedResponses {
    static func response(for queryItems: [URLQueryItem]) -> Data? {
        guard let token = queryItems.first(where: { $0.name == "t" })?.value,
              token.hasPrefix("debug-") else { return nil }
        let body: String
        switch token {
        case "debug-1012":
            body = serviceXML(status: "Fail", code: 1012, message: "Token has expired.")
        case "debug-1003":
            body = serviceXML(status: "Fail", code: 1003, message: "Statement is not available.")
        case "debug-1019":
            body = serviceXML(status: "Fail", code: 1019, message: "Statement generation in progress.")
        default:
            body = serviceXML(status: "Fail", code: 1020, message: "Invalid request or unable to validate request.")
        }
        return Data(body.utf8)
    }

    private static func serviceXML(status: String, code: Int, message: String) -> String {
        """
        <FlexStatementResponse timestamp="01 January, 2026 00:00 AM EST">
          <Status>\(status)</Status>
          <ErrorCode>\(code)</ErrorCode>
          <ErrorMessage>\(message)</ErrorMessage>
        </FlexStatementResponse>
        """
    }
}
#endif
