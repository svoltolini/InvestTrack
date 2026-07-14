import Foundation

/// Display currency. Amounts in the mock portfolio are CHF-denominated and
/// converted with fixed sample FX rates when another base currency is chosen.
enum Currency: String, CaseIterable, Identifiable {
    case chf = "CHF"
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }

    /// Mock conversion rate from CHF into this currency.
    var ratePerCHF: Double {
        switch self {
        case .chf: 1.0
        case .usd: 1.12
        case .eur: 1.05
        }
    }
}

enum ReminderOption: String, CaseIterable, Identifiable {
    case off = "Off"
    case sameDay = "Same day"
    case dayBefore = "1 day before"
    case weekBefore = "1 week before"

    var id: String { rawValue }
}

enum TaxDisplay: String, CaseIterable, Identifiable {
    case net = "Net"
    case gross = "Gross"

    var id: String { rawValue }
}

/// Dividend per share for one year, used in the 5-year growth chart.
struct DividendPoint: Identifiable, Hashable {
    let year: Int
    let dividendPerShare: Double

    var id: Int { year }
}

struct PastPayment: Identifiable, Hashable {
    let date: Date
    let amount: Double // CHF

    var id: Date { date }
}

struct NextPayment: Hashable {
    let date: Date
    let amount: Double // CHF
    let detail: String
    /// When true the payout date is only known to the month (e.g. "Apr 2027").
    let monthPrecision: Bool

    var dateLabel: String {
        monthPrecision ? Format.monthYear(date) : Format.dayMonth(date)
    }
}

struct Holding: Identifiable, Hashable {
    let ticker: String
    let name: String
    let subtitle: String // "ETF · 310 units · quarterly"
    let payoutDescription: String // "Quarterly, EUR"
    let shares: Int
    let positionValue: Double // CHF
    let annualIncome: Double // CHF per year
    let yieldOnCost: Double // 0.020 == 2.0 %
    let nextPayment: NextPayment
    let dividendGrowth: [DividendPoint]
    let paymentHistory: [PastPayment]

    var id: String { ticker }
}

/// A single dividend payment on the timeline — scheduled or already paid.
struct DividendEvent: Identifiable, Hashable {
    let date: Date
    let title: String
    let detail: String
    let amount: Double // CHF
    /// Ticker of the matching holding; nil for account-level income such as interest.
    let ticker: String?

    var id: String { "\(title)-\(date.timeIntervalSinceReferenceDate)" }
}

struct MonthlyIncome: Identifiable {
    let month: Int // 1…12
    let name: String // "Jan"
    let amount: Double // CHF

    var id: Int { month }
}

struct CurrencySlice: Identifiable {
    let code: String
    let share: Double // 0…1

    var id: String { code }
}

struct Portfolio {
    let accountLabel: String // "78'201-CHF"
    let cashBalance: Double // CHF, part of the total account value
    /// Reported by the broker in the mock; a real client would derive it from cost basis.
    let averageYieldOnCost: Double
    let incomeGrowthYoY: Double // vs previous year
    let monthlyIncomeYear: Int
    let monthlyIncome: [MonthlyIncome]
    let currencyBreakdown: [CurrencySlice]
    let holdings: [Holding]
    let scheduledEvents: [DividendEvent]

    var totalValue: Double {
        holdings.reduce(cashBalance) { $0 + $1.positionValue }
    }

    var projectedAnnualIncome: Double {
        holdings.reduce(0) { $0 + $1.annualIncome }
    }

    /// Scheduled payments plus each holding's payment history, for the calendar.
    var allEvents: [DividendEvent] {
        let history = holdings.flatMap { holding in
            holding.paymentHistory.map { payment in
                DividendEvent(
                    date: payment.date,
                    title: holding.name,
                    detail: holding.payoutDescription,
                    amount: payment.amount,
                    ticker: holding.ticker
                )
            }
        }
        return scheduledEvents + history
    }
}
