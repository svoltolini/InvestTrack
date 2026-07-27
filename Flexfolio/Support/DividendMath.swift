import Foundation

/// Pure aggregation over `DividendEvent`s shared by Dashboard, Dividends, and
/// the holding detail. All sums in `Decimal`; WHT rows carry negative amounts,
/// so "net" is a plain sum and "withheld" is the absolute WHT sum.
enum DividendMath {
    // MARK: - Headline sums (base currency)

    /// Net dividend income over the trailing twelve months.
    static func ttmNet(_ events: [DividendEvent], now: Date = .now) -> Decimal {
        let cutoff = now.addingTimeInterval(-365 * 86_400)
        return events.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.amountBase }
    }

    /// Net dividend income for the current calendar year.
    static func ytdNet(_ events: [DividendEvent], now: Date = .now) -> Decimal {
        let year = Calendar.flex.component(.year, from: now)
        return events
            .filter { Calendar.flex.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amountBase }
    }

    /// Absolute withholding tax for the current calendar year — the DA-1
    /// reclaim headline.
    static func ytdWithheld(_ events: [DividendEvent], now: Date = .now) -> Decimal {
        let year = Calendar.flex.component(.year, from: now)
        let sum = events
            .filter { $0.isWithholding && Calendar.flex.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amountBase }
        return -sum
    }

    // MARK: - Monthly buckets

    struct MonthBucket: Identifiable {
        let month: Date
        let net: Decimal
        var id: Date { month }
    }

    /// Net income bucketed by calendar month, oldest first, covering the last
    /// `count` months up to and including the current one. Empty months stay
    /// in the series so chart spacing is honest.
    static func monthlyNet(_ events: [DividendEvent], months count: Int = 13, now: Date = .now) -> [MonthBucket] {
        let calendar = Calendar.flex
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        var totals: [Date: Decimal] = [:]
        for event in events {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: event.date)) else { continue }
            totals[month, default: 0] += event.amountBase
        }
        return (0..<count).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth) else { return nil }
            return MonthBucket(month: month, net: totals[month] ?? 0)
        }
    }

    // MARK: - Gross → WHT → net row groups

    /// One dividend payment with its withholding paired by (symbol, date).
    /// Unpaired WHT rows still form a group of their own.
    struct PaymentGroup: Identifiable {
        let symbol: String
        let date: Date
        let currency: String
        let fxRateToBase: Decimal
        var gross: Decimal = 0
        var withheld: Decimal = 0 // stored positive
        var grossBase: Decimal = 0
        var withheldBase: Decimal = 0

        var net: Decimal { gross - withheld }
        var netBase: Decimal { grossBase - withheldBase }
        var id: String { "\(symbol)|\(FlexValue.dateKey(date))" }
    }

    /// Groups events by (symbol, day), newest first.
    static func paymentGroups(_ events: [DividendEvent]) -> [PaymentGroup] {
        var groups: [String: PaymentGroup] = [:]
        for event in events {
            let key = "\(event.symbol)|\(FlexValue.dateKey(event.date))"
            var group = groups[key] ?? PaymentGroup(
                symbol: event.symbol,
                date: event.date,
                currency: event.currency,
                fxRateToBase: event.fxRateToBase
            )
            if event.isWithholding {
                group.withheld += -event.amount
                group.withheldBase += -event.amountBase
            } else {
                group.gross += event.amount
                group.grossBase += event.amountBase
            }
            groups[key] = group
        }
        return groups.values.sorted { $0.date > $1.date }
    }

    /// Payment groups bucketed by month, newest month first.
    static func groupedByMonth(_ events: [DividendEvent]) -> [(month: Date, groups: [PaymentGroup])] {
        let calendar = Calendar.flex
        var byMonth: [Date: [PaymentGroup]] = [:]
        for group in paymentGroups(events) {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: group.date)) else { continue }
            byMonth[month, default: []].append(group)
        }
        return byMonth
            .map { (month: $0.key, groups: $0.value) }
            .sorted { $0.month > $1.month }
    }

    // MARK: - CSV (the DA-1 hand-in)

    /// CSV of all payment groups: date, symbol, currency, gross, WHT, net, fx,
    /// and base-currency amounts. `Decimal.description` is plain dot-decimal,
    /// so the file is locale-independent.
    static func csv(_ events: [DividendEvent]) -> String {
        var lines = ["date,symbol,currency,gross,withholding_tax,net,fx_rate_to_base,gross_base,withholding_tax_base,net_base"]
        for group in paymentGroups(events).sorted(by: { $0.date < $1.date }) {
            let symbol = group.symbol.contains(",") ? "\"\(group.symbol)\"" : group.symbol
            lines.append(
                "\(FlexValue.dateKey(group.date)),\(symbol),\(group.currency)," +
                "\(group.gross),\(group.withheld),\(group.net),\(group.fxRateToBase)," +
                "\(group.grossBase),\(group.withheldBase),\(group.netBase)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
