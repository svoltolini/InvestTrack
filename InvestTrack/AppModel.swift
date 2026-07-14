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

    enum DataSource: String {
        case sample
        case saxo
    }

    private(set) var phase: Phase = .loggedOut
    private(set) var dataSource: DataSource = .sample
    private(set) var portfolio: Portfolio = .sample
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    /// User-facing connection/sync error; surfaced as an alert.
    private(set) var syncError: String?

    var baseCurrency: Currency {
        didSet { UserDefaults.standard.set(baseCurrency.rawValue, forKey: Keys.currency) }
    }
    var paymentReminder: ReminderOption {
        didSet { UserDefaults.standard.set(paymentReminder.rawValue, forKey: Keys.reminder) }
    }
    var taxDisplay: TaxDisplay {
        didSet { UserDefaults.standard.set(taxDisplay.rawValue, forKey: Keys.tax) }
    }

    let saxoConfiguration = SaxoConfiguration.default
    private let saxoClient = SaxoAPIClient(configuration: .default)
    private let authenticator = SaxoAuthenticator()
    private var saxoService: SaxoPortfolioService { SaxoPortfolioService(client: saxoClient) }

    private enum Keys {
        static let connected = "investtrack.connected"
        static let source = "investtrack.dataSource"
        static let currency = "investtrack.baseCurrency"
        static let reminder = "investtrack.paymentReminder"
        static let tax = "investtrack.taxDisplay"
    }

    init() {
        let defaults = UserDefaults.standard
        self.baseCurrency = Currency(rawValue: defaults.string(forKey: Keys.currency) ?? "") ?? .chf
        self.paymentReminder = ReminderOption(rawValue: defaults.string(forKey: Keys.reminder) ?? "") ?? .dayBefore
        self.taxDisplay = TaxDisplay(rawValue: defaults.string(forKey: Keys.tax) ?? "") ?? .net
        self.dataSource = DataSource(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .sample
        // A sample session restores instantly; a Saxo session resumes
        // asynchronously in bootstrap() once the UI is up.
        if dataSource == .sample, defaults.bool(forKey: Keys.connected) {
            phase = .connected
        }
    }

    /// Called once at launch: resumes a persisted Saxo session if its tokens
    /// are still usable, otherwise leaves the user on the login screen.
    func bootstrap() async {
        guard dataSource == .saxo, phase == .loggedOut else { return }
        guard await saxoClient.hasUsableSession else { return }
        phase = .connecting
        do {
            try await activateSaxo()
        } catch {
            phase = .loggedOut
            // An expired session is expected after long inactivity — no alert.
            if case SaxoAPIError.sessionExpired = error {} else {
                syncError = error.localizedDescription
            }
        }
    }

    // MARK: - Session

    /// Browses the bundled sample portfolio (the design prototype's dataset),
    /// with a short fake hand-off like the design.
    func connectSample() {
        guard phase != .connected else { return }
        setSource(.sample)
        portfolio = .sample
        phase = .connecting
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard phase == .connecting else { return }
            phase = .connected
            UserDefaults.standard.set(true, forKey: Keys.connected)
        }
    }

    /// Full OAuth (PKCE) sign-in with Saxo, then loads the real portfolio.
    func connectSaxo() {
        guard phase != .connecting else { return }
        guard saxoConfiguration.isConfigured else {
            syncError = SaxoAuthError.notConfigured.errorDescription
            return
        }
        phase = .connecting
        Task {
            do {
                let tokens = try await authenticator.authorize(configuration: saxoConfiguration)
                await saxoClient.adopt(tokens)
                try await activateSaxo()
            } catch SaxoAuthError.cancelled {
                phase = .loggedOut
            } catch {
                await saxoClient.signOut()
                phase = .loggedOut
                syncError = error.localizedDescription
            }
        }
    }

    /// Connects with a 24-hour token from Saxo's developer portal — no app
    /// registration required.
    func connectSaxo(developerToken: String) {
        let token = developerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, phase != .connecting else { return }
        phase = .connecting
        Task {
            do {
                await saxoClient.adopt(.developerToken(token))
                try await activateSaxo()
            } catch {
                await saxoClient.signOut()
                phase = .loggedOut
                syncError = error.localizedDescription
            }
        }
    }

    private func activateSaxo() async throws {
        portfolio = try await saxoService.loadPortfolio()
        lastSync = .now
        setSource(.saxo)
        UserDefaults.standard.set(true, forKey: Keys.connected)
        phase = .connected
    }

    /// Re-fetches the Saxo portfolio (pull-to-refresh). No-op for sample data.
    func refresh() async {
        guard dataSource == .saxo, phase == .connected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            portfolio = try await saxoService.loadPortfolio()
            lastSync = .now
        } catch {
            syncError = error.localizedDescription
        }
    }

    func disconnect() {
        phase = .loggedOut
        portfolio = .sample
        setSource(.sample)
        UserDefaults.standard.set(false, forKey: Keys.connected)
        Task { await saxoClient.signOut() }
    }

    func clearSyncError() {
        syncError = nil
    }

    private func setSource(_ source: DataSource) {
        dataSource = source
        UserDefaults.standard.set(source.rawValue, forKey: Keys.source)
    }

    // MARK: - Derived data

    var upcomingEvents: [DividendEvent] {
        let startOfToday = Calendar.gregorian.startOfDay(for: .now)
        return Array(
            portfolio.scheduledEvents
                .filter { $0.date >= startOfToday }
                .sorted { $0.date < $1.date }
                .prefix(5)
        )
    }

    var currentMonthIncome: Double {
        let month = Calendar.gregorian.component(.month, from: .now)
        return portfolio.monthlyIncome.first { $0.month == month }?.amount ?? 0
    }

    func holding(for ticker: String?) -> Holding? {
        guard let ticker else { return nil }
        return portfolio.holdings.first { $0.ticker == ticker }
    }

    func events(in month: Date) -> [DividendEvent] {
        let calendar = Calendar.gregorian
        return portfolio.allEvents
            .filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date < $1.date }
    }

    /// Total income for a calendar month. The dataset provides exact monthly
    /// totals for its statement year; other months fall back to the sum of
    /// known events.
    func incomeTotal(for month: Date) -> Double {
        let components = Calendar.gregorian.dateComponents([.year, .month], from: month)
        if components.year == portfolio.monthlyIncomeYear,
           let monthNumber = components.month,
           let entry = portfolio.monthlyIncome.first(where: { $0.month == monthNumber }) {
            return entry.amount
        }
        return events(in: month).reduce(0) { $0 + $1.amount }
    }

    // MARK: - Money formatting

    /// Formats an amount in the active display currency. Sample data supports
    /// switching currencies with demo FX rates; a real Saxo portfolio is
    /// always shown in the account's own base currency.
    func money(_ amount: Double, decimals: Int = 0, withCode: Bool = false) -> String {
        switch dataSource {
        case .sample:
            let converted = amount * baseCurrency.ratePerCHF
            let number = Format.amount(converted, decimals: decimals)
            return withCode ? "\(baseCurrency.rawValue) \(number)" : number
        case .saxo:
            let number = Format.amount(amount, decimals: decimals)
            return withCode ? "\(portfolio.currencyCode) \(number)" : number
        }
    }
}
