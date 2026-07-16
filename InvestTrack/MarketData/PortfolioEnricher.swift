import Foundation

/// Fills a Saxo-sourced `Portfolio` with third-party market data (Yahoo):
/// live market values, 5-year dividend-per-share growth, yield on cost, and an
/// estimated next payout derived from dividend cadence. Best-effort — holdings
/// that can't be enriched keep their cost-basis values, and if nothing can be
/// enriched the portfolio is returned unchanged.
enum PortfolioEnricher {
    static func enrich(_ portfolio: Portfolio, using service: MarketDataService) async -> Portfolio {
        guard portfolio.holdings.contains(where: { $0.marketSymbol != nil }) else {
            return portfolio
        }

        let base = portfolio.currencyCode
        var newHoldings: [Holding] = []
        var estimatedEvents: [DividendEvent] = []
        var anyLiveValue = false
        var anyDividendData = false

        for holding in portfolio.holdings {
            let (enriched, events, gotValue, gotDividends) = await enrichHolding(holding, base: base, service: service)
            newHoldings.append(enriched)
            estimatedEvents.append(contentsOf: events)
            anyLiveValue = anyLiveValue || gotValue
            anyDividendData = anyDividendData || gotDividends
        }

        guard anyLiveValue || anyDividendData else { return portfolio }

        // Totals and currency exposure from live values, when we have them.
        let totalValue: Double
        let currencyBreakdown: [CurrencySlice]
        if anyLiveValue {
            let holdingsValue = newHoldings.reduce(0) { $0 + $1.positionValue }
            totalValue = portfolio.cashBalance + holdingsValue

            var totals: [String: Double] = [:]
            for holding in newHoldings where holding.positionValue > 0 {
                let code = holding.instrumentCurrency.isEmpty ? base : holding.instrumentCurrency
                totals[code, default: 0] += holding.positionValue
            }
            if portfolio.cashBalance > 0 {
                totals[base, default: 0] += portfolio.cashBalance
            }
            let exposureTotal = totals.values.reduce(0, +)
            currencyBreakdown = exposureTotal > 0
                ? totals.map { CurrencySlice(code: $0.key, share: $0.value / exposureTotal) }
                    .filter { $0.share >= 0.005 }
                    .sorted { $0.share > $1.share }
                : portfolio.currencyBreakdown
        } else {
            totalValue = portfolio.totalValue
            currencyBreakdown = portfolio.currencyBreakdown
        }

        // Dividend run-rate and yield on cost from the enriched holdings.
        let projectedAnnualIncome: Double
        let averageYieldOnCost: Double
        if anyDividendData {
            projectedAnnualIncome = newHoldings.reduce(0) { $0 + $1.annualIncome }
            let totalAnnual = newHoldings.reduce(0.0) { $0 + $1.annualIncome }
            let totalCost = newHoldings.reduce(0.0) { $0 + ($1.costBasis ?? 0) }
            averageYieldOnCost = totalCost > 0 ? totalAnnual / totalCost : portfolio.averageYieldOnCost
        } else {
            projectedAnnualIncome = portfolio.projectedAnnualIncome
            averageYieldOnCost = portfolio.averageYieldOnCost
        }

        return Portfolio(
            currencyCode: base,
            accountLabel: portfolio.accountLabel,
            cashBalance: portfolio.cashBalance,
            totalValue: totalValue,
            projectedAnnualIncome: projectedAnnualIncome,
            averageYieldOnCost: averageYieldOnCost,
            incomeGrowthYoY: portfolio.incomeGrowthYoY,
            monthlyIncomeYear: portfolio.monthlyIncomeYear,
            monthlyIncome: portfolio.monthlyIncome,
            currencyBreakdown: currencyBreakdown,
            holdings: newHoldings,
            scheduledEvents: portfolio.scheduledEvents + estimatedEvents
        )
    }

    // MARK: - Per holding

    private static func enrichHolding(
        _ holding: Holding,
        base: String,
        service: MarketDataService
    ) async -> (holding: Holding, events: [DividendEvent], gotValue: Bool, gotDividends: Bool) {
        guard let symbol = holding.marketSymbol,
              let quote = await service.quote(symbol: symbol),
              let fx = await service.fxRate(from: quote.currency, to: base) else {
            return (holding, [], false, false)
        }

        var updated = holding
        var gotValue = false
        var gotDividends = false
        var events: [DividendEvent] = []

        // Saxo's average open price per share, reconciled to Yahoo's
        // (major-unit) price. UK/LSE instruments are frequently quoted in pence
        // by the broker — even when the currency is reported as "GBP" — so a
        // shared reconciled value is used for both cost/return and yield.
        let openPrice: Double? = holding.averageOpenPrice.flatMap { raw in
            raw > 0 ? reconciledOpenPrice(raw, yahooPrice: quote.price, currency: holding.instrumentCurrency) : nil
        }

        // Live market value in base currency (Yahoo already normalises pence).
        let liveValue = quote.price * abs(holding.shares) * fx
        if liveValue > 0 {
            updated.positionValue = liveValue
            updated.valueIsAtCost = false
            updated.nativeCostLabel = nil
            // Cost basis from the average open price is reliable even for
            // margin/Lombard accounts, unlike Saxo's MarketValue − P/L (which
            // can collapse toward zero and inflate the return).
            if let openPrice, quote.price > 0 {
                let costBasis = liveValue * (openPrice / quote.price)
                updated.costBasis = costBasis
                updated.unrealizedProfit = liveValue - costBasis
            } else if let cost = holding.costBasis {
                updated.unrealizedProfit = liveValue - cost
            }
            gotValue = true
        }

        let dividends = quote.dividends
        if !dividends.isEmpty {
            gotDividends = true
            updated.dividendGrowth = growthPoints(dividends)

            let trailingPerShare = trailingPerShare(dividends)
            if trailingPerShare > 0 {
                // Both the dividend (Yahoo) and openPrice are now in major units.
                if let openPrice {
                    updated.yieldOnCost = trailingPerShare / openPrice
                }
                // Fill an income run-rate only when Saxo didn't report received payments.
                if updated.annualIncome <= 0 {
                    updated.annualIncome = trailingPerShare * abs(holding.shares) * fx
                }
            }

            events = projectedEvents(dividends, shares: abs(holding.shares), fx: fx, holding: updated)
            if let next = events.first {
                updated.nextPayment = NextPayment(
                    date: next.date,
                    amount: next.amount,
                    detail: "Estimated · based on payout history",
                    monthPrecision: false
                )
            }
        }

        return (updated, events, gotValue, gotDividends)
    }

    /// Reconciles a broker per-share price to the (major-unit) reference price.
    /// UK/LSE instruments are commonly quoted in pence — sometimes even when
    /// the currency is reported as "GBP" — a factor-of-100 gap. Only British
    /// (and known pence) instruments are adjusted, so genuine large losses on
    /// other currencies are never mistaken for a unit mismatch.
    private static func reconciledOpenPrice(_ price: Double, yahooPrice: Double, currency: String) -> Double {
        // Explicit minor-unit currency codes.
        if ["GBX", "GBp", "ZAc", "ILA"].contains(currency) { return price / 100 }
        // British stock labelled "GBP" but priced in pence: a ~100× gap vs the
        // major-unit reference price confirms it.
        if currency == "GBP", yahooPrice > 0, price / yahooPrice > 20 { return price / 100 }
        return price
    }

    // MARK: - Dividend math

    /// Dividend per share summed per calendar year, most recent five years.
    private static func growthPoints(_ dividends: [MarketDataService.DividendPayment]) -> [DividendPoint] {
        let calendar = Calendar.gregorian
        var byYear: [Int: Double] = [:]
        for dividend in dividends {
            let year = calendar.component(.year, from: dividend.date)
            byYear[year, default: 0] += dividend.amountPerShare
        }
        return byYear.keys.sorted().suffix(5).map { year in
            DividendPoint(year: year, dividendPerShare: byYear[year] ?? 0)
        }
    }

    /// Dividend per share paid in the trailing 12 months.
    private static func trailingPerShare(_ dividends: [MarketDataService.DividendPayment]) -> Double {
        let cutoff = Date.now.addingTimeInterval(-365 * 86_400)
        return dividends.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.amountPerShare }
    }

    /// Projects future payouts from the median spacing of past dividends,
    /// stepping forward from the last ex-date across the horizon (soonest
    /// first). Each uses the most recent per-share amount × shares × FX.
    private static func projectedEvents(
        _ dividends: [MarketDataService.DividendPayment],
        shares: Double,
        fx: Double,
        holding: Holding,
        horizonMonths: Int = 13
    ) -> [DividendEvent] {
        guard dividends.count >= 2, let last = dividends.last, shares > 0 else { return [] }

        var gaps: [Double] = []
        for index in 1..<dividends.count {
            gaps.append(dividends[index].date.timeIntervalSince(dividends[index - 1].date) / 86_400)
        }
        gaps.sort()
        let gapDays = max(20, gaps[gaps.count / 2])

        let amount = last.amountPerShare * shares * fx
        guard amount > 0 else { return [] }

        let now = Date.now
        let horizon = now.addingTimeInterval(Double(horizonMonths) * 30.44 * 86_400)
        var date = last.date
        var events: [DividendEvent] = []
        var guardCount = 0
        while guardCount < 60 {
            date = date.addingTimeInterval(gapDays * 86_400)
            guardCount += 1
            if date <= now { continue }
            if date > horizon { break }
            events.append(DividendEvent(
                date: date,
                title: holding.name,
                detail: "Estimated payout",
                amount: amount,
                ticker: holding.ticker
            ))
        }
        return events
    }
}
