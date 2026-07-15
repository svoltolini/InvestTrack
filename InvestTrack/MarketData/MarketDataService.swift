import Foundation

/// Fetches delayed prices and dividend history from Yahoo Finance's public
/// chart endpoint (no API key required).
///
/// This is an unofficial, rate-limited, best-effort source: any failure is
/// non-fatal and simply leaves a holding without live data (it falls back to
/// cost basis). A fresh instance is used per portfolio load, so its caches
/// only dedupe repeated symbols/FX pairs within one refresh.
actor MarketDataService {
    struct Quote {
        let price: Double // in `currency`
        let currency: String
        let dividends: [DividendPayment] // per share, ascending by date
    }

    struct DividendPayment {
        let date: Date
        let amountPerShare: Double
    }

    private var quoteCache: [String: Quote?] = [:]
    private var fxCache: [String: Double?] = [:]

    func quote(symbol: String) async -> Quote? {
        if let cached = quoteCache[symbol] { return cached }
        let result = await fetchChart(symbol: symbol)
        quoteCache[symbol] = result
        return result
    }

    /// Conversion rate `from` → `to` (e.g. USD → CHF), via Yahoo's "USDCHF=X".
    func fxRate(from: String, to: String) async -> Double? {
        if from.caseInsensitiveCompare(to) == .orderedSame { return 1 }
        let key = "\(from)->\(to)"
        if let cached = fxCache[key] { return cached }
        let rate = await fetchChart(symbol: "\(from)\(to)=X")?.price
        fxCache[key] = rate
        return rate
    }

    // MARK: - Networking

    private func fetchChart(symbol: String) async -> Quote? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        for host in ["query1.finance.yahoo.com", "query2.finance.yahoo.com"] {
            guard var components = URLComponents(string: "https://\(host)/v8/finance/chart/\(encoded)") else { continue }
            components.queryItems = [
                URLQueryItem(name: "range", value: "5y"),
                URLQueryItem(name: "interval", value: "1mo"),
                URLQueryItem(name: "events", value: "div"),
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let quote = Self.parse(data) { return quote }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Parsing

    private static func parse(_ data: Data) -> Quote? {
        guard let root = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let result = root.chart.result?.first,
              let meta = result.meta,
              let rawPrice = meta.regularMarketPrice,
              let rawCurrency = meta.currency else {
            return nil
        }

        // London (and some other) instruments quote in pence ("GBp"), a
        // hundredth of the major unit — normalise to the major currency.
        var currency = rawCurrency
        var scale = 1.0
        if currency == "GBp" || currency == "GBX" {
            currency = "GBP"
            scale = 0.01
        } else if currency == "ZAc" {
            currency = "ZAR"
            scale = 0.01
        }

        let price = rawPrice * scale
        guard price > 0 else { return nil }

        let dividends = (result.events?.dividends ?? [:]).values
            .compactMap { entry -> DividendPayment? in
                guard let amount = entry.amount, let timestamp = entry.date, amount > 0 else { return nil }
                return DividendPayment(
                    date: Date(timeIntervalSince1970: timestamp),
                    amountPerShare: amount * scale
                )
            }
            .sorted { $0.date < $1.date }

        return Quote(price: price, currency: currency, dividends: dividends)
    }

    // MARK: - Wire models

    private struct ChartResponse: Decodable {
        let chart: Chart
        struct Chart: Decodable {
            let result: [Result]?
        }
        struct Result: Decodable {
            let meta: Meta?
            let events: Events?
        }
        struct Meta: Decodable {
            let currency: String?
            let regularMarketPrice: Double?
        }
        struct Events: Decodable {
            let dividends: [String: Dividend]?
        }
        struct Dividend: Decodable {
            let amount: Double?
            let date: Double?
        }
    }
}
