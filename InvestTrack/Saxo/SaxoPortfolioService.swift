import Foundation

/// Fetches a Saxo account and maps it onto the app's `Portfolio` model.
///
/// Saxo's OpenAPI is authoritative for accounts, balances and positions.
/// Dividend data degrades gracefully:
/// - received payments come from `/cs/v1/reports/bookings` (real on LIVE;
///   mocked/empty on SIM), falling back to `/hist/v1/transactions`;
/// - upcoming dividends come from `/ca/v2/events`, which is entitlement-gated
///   for most apps — a 403 simply leaves the upcoming list empty;
/// - per-share dividend growth has no Saxo source and stays empty.
struct SaxoPortfolioService {
    let client: SaxoAPIClient

    struct IncomePayment {
        let date: Date
        let amount: Double // client base currency
        let uic: Int?
        let description: String?
        let detail: String
    }

    // MARK: - Loading

    func loadPortfolio() async throws -> Portfolio {
        let clientInfo = try await client.get(SaxoClient.self, path: "/port/v1/clients/me")
        let balance = try await client.get(SaxoBalance.self, path: "/port/v1/balances/me")
        let accounts = (try? await client.get(SaxoList<SaxoAccount>.self, path: "/port/v1/accounts/me").items) ?? []
        let positions = await fetchNetPositions(clientKey: clientInfo.clientKey)
        let payments = await fetchIncomePayments(clientKey: clientInfo.clientKey)
        let upcoming = await fetchUpcomingDividendEvents(clientKey: clientInfo.clientKey)

        return Self.map(
            clientInfo: clientInfo,
            accounts: accounts,
            balance: balance,
            positions: positions,
            payments: payments,
            upcoming: upcoming
        )
    }

    /// Pages through a collection endpoint. The contract's continuation signal
    /// is `__next`; page size is only a hint (the server may clamp `$top`).
    private func fetchAllPages<Element: Decodable>(
        path: String,
        baseQuery: [URLQueryItem],
        pageSize: Int,
        maxPages: Int = 20
    ) async -> [Element] {
        var all: [Element] = []
        var skip = 0
        for _ in 0..<maxPages {
            var query = baseQuery
            query.append(URLQueryItem(name: "$top", value: String(pageSize)))
            query.append(URLQueryItem(name: "$skip", value: String(skip)))
            guard let list = try? await client.get(SaxoList<Element>.self, path: path, query: query) else {
                break
            }
            all.append(contentsOf: list.items)
            if list.next == nil || list.items.isEmpty { break }
            skip += list.items.count
        }
        return all
    }

    private func fetchNetPositions(clientKey: String) async -> [SaxoNetPosition] {
        await fetchAllPages(
            path: "/port/v1/netpositions",
            baseQuery: [
                URLQueryItem(name: "FieldGroups", value: "NetPositionBase,NetPositionView,DisplayAndFormat"),
                URLQueryItem(name: "ClientKey", value: clientKey),
            ],
            pageSize: 400
        )
    }

    /// Dividends and other income actually received, newest first.
    private func fetchIncomePayments(clientKey: String) async -> [IncomePayment] {
        let calendar = Calendar.gregorian
        let now = Date.now
        let currentYear = calendar.component(.year, from: now)
        var fromComponents = DateComponents()
        fromComponents.year = currentYear - 1
        fromComponents.month = 1
        fromComponents.day = 1
        let from = calendar.date(from: fromComponents) ?? now.addingTimeInterval(-730 * 86_400)

        let dayFormat: (Date) -> String = { date in
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
        }

        // Primary: client-statement bookings, which attribute payments to
        // instruments. "OngoingPayment" == dividends and coupons.
        let bookings: [SaxoBooking] = await fetchAllPages(
            path: "/cs/v1/reports/bookings/\(clientKey)",
            baseQuery: [
                URLQueryItem(name: "FromDate", value: dayFormat(from)),
                URLQueryItem(name: "ToDate", value: dayFormat(now)),
            ],
            pageSize: 1000
        )
        if !bookings.isEmpty {
            let payments = bookings
                .filter(\.isIncomePayment)
                .compactMap { booking -> IncomePayment? in
                    guard let date = SaxoDates.parse(booking.date ?? booking.valueDate) else { return nil }
                    let amount = booking.amountClientCurrency ?? booking.amountAccountCurrency ?? booking.amount ?? 0
                    guard amount != 0 else { return nil }
                    return IncomePayment(
                        date: date,
                        amount: amount,
                        uic: booking.uic,
                        description: booking.instrumentDescription ?? booking.instrumentSymbol,
                        detail: booking.amountSubClass ?? "Dividend"
                    )
                }
            if !payments.isEmpty {
                return payments.sorted { $0.date > $1.date }
            }
        }

        // Fallback: the transaction history ledger (no instrument attribution).
        let transactions: [SaxoHistTransaction] = await fetchAllPages(
            path: "/hist/v1/transactions",
            baseQuery: [
                URLQueryItem(name: "ClientKey", value: clientKey),
                URLQueryItem(name: "FromDate", value: dayFormat(from)),
                URLQueryItem(name: "ToDate", value: dayFormat(now)),
            ],
            pageSize: 1000
        )
        return transactions
            .filter(\.looksLikeDividend)
            .compactMap { transaction -> IncomePayment? in
                guard let date = SaxoDates.parse(transaction.date ?? transaction.valueDate),
                      let amount = transaction.bookedAmount, amount != 0 else { return nil }
                return IncomePayment(
                    date: date,
                    amount: amount,
                    uic: nil,
                    description: transaction.eventDisplay ?? transaction.transactionTypeDisplay,
                    detail: transaction.transactionTypeDisplay ?? "Corporate action"
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// Upcoming dividend corporate-action events. Requires an entitlement most
    /// apps don't have — treat failures (403 etc.) as "no data".
    private func fetchUpcomingDividendEvents(clientKey: String) async -> [SaxoCAEvent] {
        let query = [
            URLQueryItem(name: "ClientKey", value: clientKey),
            URLQueryItem(name: "EventTypes", value: "DVCA,DVOP,DVSE"),
        ]
        let list = try? await client.get(SaxoList<SaxoCAEvent>.self, path: "/ca/v2/events", query: query)
        return list?.items ?? []
    }

    // MARK: - Mapping

    static func map(
        clientInfo: SaxoClient,
        accounts: [SaxoAccount],
        balance: SaxoBalance,
        positions: [SaxoNetPosition],
        payments: [IncomePayment],
        upcoming: [SaxoCAEvent]
    ) -> Portfolio {
        let calendar = Calendar.gregorian
        let now = Date.now
        let currentYear = calendar.component(.year, from: now)
        let currencyCode = clientInfo.defaultCurrency ?? balance.currency ?? "USD"

        // Account label, e.g. "78201-CHF".
        let primaryAccount = accounts.first { $0.accountKey == clientInfo.defaultAccountKey } ?? accounts.first
        let accountLabel: String = {
            guard let primaryAccount else { return clientInfo.clientId ?? "Saxo account" }
            let name = primaryAccount.displayName ?? primaryAccount.accountId ?? "Saxo account"
            if let currency = primaryAccount.currency { return "\(name)-\(currency)" }
            return name
        }()

        // Payments per instrument, for per-holding history and income.
        let paymentsByUic = Dictionary(grouping: payments.filter { $0.uic != nil }, by: { $0.uic! })
        let trailingYearStart = now.addingTimeInterval(-365 * 86_400)

        var usedTickers: Set<String> = []
        var holdings: [Holding] = []
        for position in positions {
            let shares = position.base?.amount ?? 0
            guard shares != 0 else { continue }

            let symbol = position.displayAndFormat?.symbol ?? position.netPositionId ?? "?"
            var ticker = String(symbol.split(separator: ":").first ?? "?").uppercased()
            while usedTickers.contains(ticker) { ticker += "·" }
            usedTickers.insert(ticker)

            let kind = Self.assetKindLabel(position.base?.assetType)
            let instrumentCurrency = position.displayAndFormat?.currency
                ?? position.view?.exposureCurrency
                ?? currencyCode
            let value = position.view?.marketValueInBaseCurrency
                ?? position.view?.marketValue
                ?? 0

            let uic = position.base?.uic
            let instrumentPayments = uic.flatMap { paymentsByUic[$0] } ?? []
            let annualIncome = instrumentPayments
                .filter { $0.date >= trailingYearStart && $0.amount > 0 }
                .reduce(0) { $0 + $1.amount }
            let history = instrumentPayments
                .filter { $0.amount > 0 }
                .prefix(8)
                .map { PastPayment(date: $0.date, amount: $0.amount) }

            let sharesLabel = Format.amount(shares, decimals: shares.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2)
            holdings.append(
                Holding(
                    id: position.netPositionId ?? "\(ticker)-\(uic ?? 0)",
                    ticker: ticker,
                    name: position.displayAndFormat?.description ?? symbol,
                    subtitle: "\(kind) · \(sharesLabel) \(kind == "FX" ? "units" : "shares")",
                    payoutDescription: "\(kind) · \(instrumentCurrency)",
                    shares: shares,
                    positionValue: value,
                    annualIncome: annualIncome,
                    yieldOnCost: 0, // needs per-share dividend data Saxo doesn't provide
                    nextPayment: Self.nextPayment(for: uic, shares: shares, in: upcoming, after: now),
                    dividendGrowth: [], // no per-share dividend history in the OpenAPI
                    paymentHistory: Array(history),
                    unrealizedProfit: position.view?.profitLossOnTradeInBaseCurrency
                )
            )
        }
        holdings.sort { $0.positionValue > $1.positionValue }

        // Monthly income for the current year.
        let monthlyIncome = (1...12).map { month -> MonthlyIncome in
            let total = payments
                .filter {
                    let parts = calendar.dateComponents([.year, .month], from: $0.date)
                    return parts.year == currentYear && parts.month == month
                }
                .reduce(0) { $0 + $1.amount }
            return MonthlyIncome(month: month, name: Format.shortMonthNames[month - 1], amount: max(0, total))
        }

        // Year-over-year growth, if both years have income.
        let yearTotal: (Int) -> Double = { year in
            payments
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0) { $0 + $1.amount }
        }
        let thisYear = yearTotal(currentYear)
        let lastYear = yearTotal(currentYear - 1)
        let incomeGrowthYoY = (thisYear > 0 && lastYear > 0) ? (thisYear / lastYear) - 1 : 0

        // Currency exposure of positions plus cash.
        var currencyTotals: [String: Double] = [:]
        for position in positions {
            let value = position.view?.marketValueInBaseCurrency ?? position.view?.marketValue ?? 0
            guard value > 0 else { continue }
            let code = position.displayAndFormat?.currency ?? position.view?.exposureCurrency ?? currencyCode
            currencyTotals[code, default: 0] += value
        }
        let cash = balance.cashBalance ?? 0
        if cash > 0 {
            currencyTotals[currencyCode, default: 0] += cash
        }
        let exposureTotal = currencyTotals.values.reduce(0, +)
        let currencyBreakdown: [CurrencySlice] = exposureTotal > 0
            ? currencyTotals
                .map { CurrencySlice(code: $0.key, share: $0.value / exposureTotal) }
                .filter { $0.share >= 0.005 }
                .sorted { $0.share > $1.share }
            : []

        let scheduledEvents = Self.scheduledEvents(from: upcoming, holdings: holdings, after: now)
        let trailingIncome = payments
            .filter { $0.date >= trailingYearStart && $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }

        return Portfolio(
            currencyCode: currencyCode,
            accountLabel: accountLabel,
            cashBalance: cash,
            totalValue: balance.totalValue ?? holdings.reduce(cash) { $0 + $1.positionValue },
            projectedAnnualIncome: trailingIncome,
            averageYieldOnCost: 0,
            incomeGrowthYoY: incomeGrowthYoY,
            monthlyIncomeYear: currentYear,
            monthlyIncome: monthlyIncome,
            currencyBreakdown: currencyBreakdown,
            holdings: holdings,
            scheduledEvents: scheduledEvents
        )
    }

    private static func assetKindLabel(_ assetType: String?) -> String {
        guard let assetType else { return "Position" }
        switch assetType.lowercased() {
        case "stock": return "Stock"
        case let type where type.hasPrefix("etf"): return "ETF"
        case "bond": return "Bond"
        case "fxspot": return "FX"
        case "mutualfund": return "Fund"
        default: return assetType
        }
    }

    /// Estimated next payment for one instrument from CA events. Amounts use
    /// PayoutBreakdown × held shares and are labelled as estimates, since the
    /// per-share semantics aren't formally documented.
    private static func nextPayment(
        for uic: Int?,
        shares: Double,
        in events: [SaxoCAEvent],
        after now: Date
    ) -> NextPayment? {
        guard let uic else { return nil }
        let candidates = events
            .filter { $0.uic == uic }
            .compactMap { event -> NextPayment? in
                guard let option = event.options?.first(where: { $0.payment?.date != nil }),
                      let payDate = SaxoDates.parse(option.payment?.date),
                      payDate >= now else { return nil }
                let perShare = option.payoutBreakdown?.compactMap(\.amount).reduce(0, +) ?? 0
                let estimated = perShare * abs(shares)
                guard estimated > 0 else { return nil }
                return NextPayment(
                    date: payDate,
                    amount: estimated,
                    detail: "Estimated · \(event.eventType?.name ?? "Dividend")",
                    monthPrecision: false
                )
            }
        return candidates.min { $0.date < $1.date }
    }

    private static func scheduledEvents(
        from events: [SaxoCAEvent],
        holdings: [Holding],
        after now: Date
    ) -> [DividendEvent] {
        let holdingsByUicSuffix = holdings // ticker lookup by name match below
        return events.compactMap { event -> DividendEvent? in
            guard let option = event.options?.first(where: { $0.payment?.date != nil }),
                  let payDate = SaxoDates.parse(option.payment?.date),
                  payDate >= now else { return nil }
            let name = event.displayAndFormat?.description
                ?? event.displayAndFormat?.symbol
                ?? "Dividend"
            let symbol = event.displayAndFormat?.symbol
            let ticker = symbol.map { String($0.split(separator: ":").first ?? "").uppercased() }
            let matchedHolding = holdingsByUicSuffix.first { holding in
                ticker != nil && holding.ticker == ticker
            }
            let shares = abs(matchedHolding?.shares ?? 0)
            let perShare = option.payoutBreakdown?.compactMap(\.amount).reduce(0, +) ?? 0
            let estimated = perShare * shares
            guard estimated > 0 else { return nil }
            return DividendEvent(
                date: payDate,
                title: name,
                detail: "Estimated · \(event.eventType?.name ?? "Dividend")",
                amount: estimated,
                ticker: matchedHolding?.ticker
            )
        }
        .sorted { $0.date < $1.date }
    }
}
