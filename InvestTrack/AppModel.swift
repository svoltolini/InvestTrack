import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loggedOut
        case connecting
        case connected
    }

    private(set) var phase: Phase

    var baseCurrency: Currency {
        didSet { UserDefaults.standard.set(baseCurrency.rawValue, forKey: Keys.currency) }
    }
    var paymentReminder: ReminderOption {
        didSet { UserDefaults.standard.set(paymentReminder.rawValue, forKey: Keys.reminder) }
    }
    var taxDisplay: TaxDisplay {
        didSet { UserDefaults.standard.set(taxDisplay.rawValue, forKey: Keys.tax) }
    }

    let portfolio: Portfolio

    private enum Keys {
        static let connected = "investtrack.connected"
        static let currency = "investtrack.baseCurrency"
        static let reminder = "investtrack.paymentReminder"
        static let tax = "investtrack.taxDisplay"
    }

    init(portfolio: Portfolio = .sample) {
        let defaults = UserDefaults.standard
        self.portfolio = portfolio
        self.phase = defaults.bool(forKey: Keys.connected) ? .connected : .loggedOut
        self.baseCurrency = Currency(rawValue: defaults.string(forKey: Keys.currency) ?? "") ?? .chf
        self.paymentReminder = ReminderOption(rawValue: defaults.string(forKey: Keys.reminder) ?? "") ?? .dayBefore
        self.taxDisplay = TaxDisplay(rawValue: defaults.string(forKey: Keys.tax) ?? "") ?? .net
    }

    // MARK: - Session

    /// Simulates the Saxo OpenAPI OAuth hand-off with a short delay.
    func connect() {
        guard phase == .loggedOut else { return }
        phase = .connecting
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard phase == .connecting else { return }
            phase = .connected
            UserDefaults.standard.set(true, forKey: Keys.connected)
        }
    }

    func disconnect() {
        phase = .loggedOut
        UserDefaults.standard.set(false, forKey: Keys.connected)
    }

    // MARK: - Derived data

    var upcomingEvents: [DividendEvent] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return Array(
            portfolio.scheduledEvents
                .filter { $0.date >= startOfToday }
                .sorted { $0.date < $1.date }
                .prefix(5)
        )
    }

    var currentMonthIncome: Double {
        let month = Calendar.current.component(.month, from: .now)
        return portfolio.monthlyIncome.first { $0.month == month }?.amount ?? 0
    }

    func holding(for ticker: String?) -> Holding? {
        guard let ticker else { return nil }
        return portfolio.holdings.first { $0.ticker == ticker }
    }

    func events(in month: Date) -> [DividendEvent] {
        let calendar = Calendar.current
        return portfolio.allEvents
            .filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date < $1.date }
    }

    /// Total income for a calendar month. The mock statement provides exact
    /// monthly totals for the current year; other months fall back to the sum
    /// of known events.
    func incomeTotal(for month: Date) -> Double {
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        if components.year == portfolio.monthlyIncomeYear,
           let monthNumber = components.month,
           let entry = portfolio.monthlyIncome.first(where: { $0.month == monthNumber }) {
            return entry.amount
        }
        return events(in: month).reduce(0) { $0 + $1.amount }
    }

    // MARK: - Money formatting

    /// Formats a CHF-denominated amount in the selected base currency.
    func money(_ chfAmount: Double, decimals: Int = 0, withCode: Bool = false) -> String {
        let converted = chfAmount * baseCurrency.ratePerCHF
        let number = Format.amount(converted, decimals: decimals)
        return withCode ? "\(baseCurrency.rawValue) \(number)" : number
    }
}
