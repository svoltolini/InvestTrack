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
            let (enriched, event, gotValue, gotDividends) = await enrichHolding(holding, base: base, service: service)
            newHoldings.append(enriched)
            if let event { estimatedEvents.append(event) }
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
    ) async -> (holding: Holding, event: DividendEvent?, gotValue: Bool, gotDividends: Bool) {
        guard let symbol = holding.marketSymbol,
              let quote = await service.quote(symbol: symbol),
              let fx = await service.fxRate(from: quote.currency, to: base) else {
            return (holding, nil, false, false)
        }

        var updated = holding
        var gotValue = false
        var gotDividends = false
        var event: DividendEvent?

        // Live market value in base currency.
        let liveValue = quote.price * abs(holding.shares) * fx
        if liveValue > 0 {
            updated.positionValue = liveValue
            updated.valueIsAtCost = false
            updated.nativeCostLabel = nil
            // Cost basis from the average open price is reliable even for
            // margin/Lombard accounts, unlike Saxo's MarketValue − P/L (which
            // can collapse toward zero and inflate the return). The ratio
            // (openPrice / currentPrice) is currency-unit agnostic since both
            // are per-share in the instrument's own currency.
            if let averageOpenPrice = holding.averageOpenPrice, averageOpenPrice > 0, quote.price > 0 {
                // Normalise pence-quoted open prices (e.g. London "GBX") to the
                // major unit so the ratio matches Yahoo's normalised price.
                let isPence = ["GBX", "GBp", "ZAc"].contains(holding.instrumentCurrency)
                let openPrice = averageOpenPrice * (isPence ? 0.01 : 1)
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
                if let averageOpenPrice = holding.averageOpenPrice, averageOpenPrice > 0 {
                    updated.yieldOnCost = trailingPerShare / averageOpenPrice
                }
                // Fill an income run-rate only when Saxo didn't report received payments.
                if updated.annualIncome <= 0 {
                    updated.annualIncome = trailingPerShare * abs(holding.shares) * fx
                }
            }

            if let estimate = nextEstimate(dividends, shares: abs(holding.shares), fx: fx) {
                updated.nextPayment = NextPayment(
                    date: estimate.date,
                    amount: estimate.amount,
                    detail: "Estimated · based on payout history",
                    monthPrecision: false
                )
                event = DividendEvent(
                    date: estimate.date,
                    title: holding.name,
                    detail: "Estimated payout",
                    amount: estimate.amount,
                    ticker: holding.ticker
                )
            }
        }

        return (updated, event, gotValue, gotDividends)
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

    /// Projects the next payout from the median spacing of past dividends.
    private static func nextEstimate(
        _ dividends: [MarketDataService.DividendPayment],
        shares: Double,
        fx: Double
    ) -> (date: Date, amount: Double)? {
        guard dividends.count >= 2, let last = dividends.last else { return nil }

        var gaps: [Double] = []
        for index in 1..<dividends.count {
            gaps.append(dividends[index].date.timeIntervalSince(dividends[index - 1].date) / 86_400)
        }
        gaps.sort()
        let medianGapDays = max(20, gaps[gaps.count / 2])

        var next = last.date
        let now = Date.now
        var guardCount = 0
        while next <= now && guardCount < 24 {
            next = next.addingTimeInterval(medianGapDays * 86_400)
            guardCount += 1
        }
        guard next > now else { return nil }

        let amount = last.amountPerShare * shares * fx
        guard amount > 0 else { return nil }
        return (next, amount)
    }
}
