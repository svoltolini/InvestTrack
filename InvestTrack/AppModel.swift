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
    /// True when a returning Saxo user's token window has lapsed, so the login
    /// screen offers a one-tap reconnect instead of the cold first-run copy.
    private(set) var saxoSessionLapsed = false
    /// Guards the automatic reconnect so a cancelled prompt isn't re-shown
    /// within the same launch.
    private var didAttemptAutoReconnect = false

    var baseCurrency: Currency {
        didSet { UserDefaults.standard.set(baseCurrency.rawValue, forKey: Keys.currency) }
    }
    var paymentReminder: ReminderOption {
        didSet { UserDefaults.standard.set(paymentReminder.rawValue, forKey: Keys.reminder) }
    }
    var taxDisplay: TaxDisplay {
        didSet { UserDefaults.standard.set(taxDisplay.rawValue, forKey: Keys.tax) }
    }

    /// The Saxo app configuration, read from on-device storage (UserDefaults)
    /// layered over the bundled defaults. Because it lives on the device — not
    /// in a source file — it survives `git pull`, rebuilds, and app updates.
    var saxoConfiguration: SaxoConfiguration { Self.loadSaxoConfiguration() }

    private static func loadSaxoConfiguration() -> SaxoConfiguration {
        var config = SaxoConfiguration.default
        let defaults = UserDefaults.standard
        if let key = defaults.string(forKey: Keys.saxoAppKey), !key.isEmpty {
            config.appKey = key
        }
        if let raw = defaults.string(forKey: Keys.saxoEnvironment),
           let environment = SaxoConfiguration.Environment(rawValue: raw) {
            config.environment = environment
        }
        if let uri = defaults.string(forKey: Keys.saxoRedirectURI), !uri.isEmpty {
            config.redirectURI = uri
        }
        return config
    }

    private var saxoClient: SaxoAPIClient
    private let authenticator = SaxoAuthenticator()
    private var saxoService: SaxoPortfolioService { SaxoPortfolioService(client: saxoClient) }

    private enum Keys {
        static let connected = "investtrack.connected"
        static let source = "investtrack.dataSource"
        static let currency = "investtrack.baseCurrency"
        static let reminder = "investtrack.paymentReminder"
        static let tax = "investtrack.taxDisplay"
        static let saxoAppKey = "investtrack.saxo.appKey"
        static let saxoEnvironment = "investtrack.saxo.environment"
        static let saxoRedirectURI = "investtrack.saxo.redirectURI"
    }

    init() {
        let defaults = UserDefaults.standard
        self.saxoClient = SaxoAPIClient(configuration: Self.loadSaxoConfiguration())
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
    /// are still usable, otherwise offers a returning user a one-tap reconnect.
    func bootstrap() async {
        guard dataSource == .saxo, phase == .loggedOut else { return }
        guard await saxoClient.hasUsableSession else {
            // Idle longer than Saxo's refresh-token window — the tokens are
            // gone. Offer (and auto-start) a one-tap reconnect for a returning
            // user rather than dropping them onto a cold login screen.
            beginReconnect()
            return
        }
        phase = .connecting
        do {
            try await activateSaxo()
        } catch {
            phase = .loggedOut
            if isSessionExpiry(error) {
                // The refresh chain lapsed while we were away — reconnect.
                beginReconnect()
            } else {
                syncError = error.localizedDescription
            }
        }
    }

    /// A returning Saxo user whose token window lapsed. Flags the lapse so the
    /// login screen shows a "Reconnect" prompt, and — at most once per launch —
    /// starts the sign-in automatically. Saxo keeps its SSO cookie
    /// (`prefersEphemeralWebBrowserSession = false`), so the reconnect is
    /// usually a single tap with no password. Skipped for developer-token
    /// sessions, which have no app key to run OAuth against.
    private func beginReconnect() {
        guard saxoConfiguration.isConfigured else { return }
        saxoSessionLapsed = true
        guard !didAttemptAutoReconnect else { return }
        didAttemptAutoReconnect = true
        connectSaxo()
    }

    // MARK: - Saxo app configuration

    /// Persists the Saxo app credentials on-device (surviving pulls/rebuilds)
    /// and rebuilds the API client so the next connection uses them.
    func saveSaxoConfiguration(appKey: String, environment: SaxoConfiguration.Environment, redirectURI: String) {
        let defaults = UserDefaults.standard
        defaults.set(appKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.saxoAppKey)
        defaults.set(environment.rawValue, forKey: Keys.saxoEnvironment)
        defaults.set(redirectURI.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.saxoRedirectURI)
        saxoClient = SaxoAPIClient(configuration: saxoConfiguration)
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

    /// Loads the Saxo portfolio and fills in third-party market data (Yahoo)
    /// for prices and dividends. Enrichment is best-effort; a fresh service per
    /// load means each refresh fetches current prices.
    private func loadSaxoPortfolio() async throws -> Portfolio {
        let base = try await saxoService.loadPortfolio()
        return await PortfolioEnricher.enrich(base, using: MarketDataService())
    }

    private func activateSaxo() async throws {
        portfolio = try await loadSaxoPortfolio()
        lastSync = .now
        setSource(.saxo)
        UserDefaults.standard.set(true, forKey: Keys.connected)
        // Session is live again; re-arm the auto-reconnect for a future lapse.
        saxoSessionLapsed = false
        didAttemptAutoReconnect = false
        phase = .connected
    }

    /// Re-fetches the Saxo portfolio (pull-to-refresh). No-op for sample data.
    func refresh() async {
        guard dataSource == .saxo, phase == .connected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let loaded = try await loadSaxoPortfolio()
            // The user may have disconnected while the fetch was in flight —
            // don't overwrite whatever state they moved to.
            guard dataSource == .saxo, phase == .connected else { return }
            portfolio = loaded
            lastSync = .now
        } catch {
            guard dataSource == .saxo, phase == .connected else { return }
            if isSessionExpiry(error) {
                handleSessionExpiry()
            } else {
                syncError = error.localizedDescription
            }
        }
    }

    /// The tokens are gone (expired refresh chain or dead developer token) —
    /// return to the login screen. For an OAuth app that's a one-tap reconnect;
    /// a developer-token session must be re-pasted, so it still gets the alert.
    private func handleSessionExpiry() {
        phase = .loggedOut
        portfolio = .sample
        UserDefaults.standard.set(false, forKey: Keys.connected)
        if saxoConfiguration.isConfigured {
            beginReconnect()
        } else {
            syncError = SaxoAPIError.sessionExpired.errorDescription
        }
    }

    private func isSessionExpiry(_ error: Error) -> Bool {
        guard let apiError = error as? SaxoAPIError else { return false }
        switch apiError {
        case .sessionExpired, .notAuthenticated: return true
        default: return false
        }
    }

    func disconnect() {
        phase = .loggedOut
        portfolio = .sample
        setSource(.sample)
        saxoSessionLapsed = false
        didAttemptAutoReconnect = false
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

    /// Twelve months of income starting at the current calendar month, for the
    /// forward-looking monthly-income chart. Sample data rotates its
    /// representative year so it begins at "now"; a Saxo account buckets its
    /// real and projected dividend events into each of the next twelve months.
    func rollingMonthlyIncome() -> [MonthlyIncomePoint] {
        let calendar = Calendar.gregorian
        let now = Date.now
        let startMonth = calendar.component(.month, from: now)

        switch dataSource {
        case .sample:
            return (0..<12).map { offset in
                let monthNumber = ((startMonth - 1 + offset) % 12) + 1
                let amount = portfolio.monthlyIncome.first { $0.month == monthNumber }?.amount ?? 0
                return MonthlyIncomePoint(
                    id: offset,
                    label: Format.shortMonthNames[monthNumber - 1],
                    amount: amount,
                    isCurrent: offset == 0
                )
            }
        case .saxo:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return (0..<12).map { offset in
                let monthDate = calendar.date(byAdding: .month, value: offset, to: startOfMonth) ?? startOfMonth
                let total = portfolio.allEvents
                    .filter { calendar.isDate($0.date, equalTo: monthDate, toGranularity: .month) }
                    .reduce(0) { $0 + $1.amount }
                let monthNumber = calendar.component(.month, from: monthDate)
                return MonthlyIncomePoint(
                    id: offset,
                    label: Format.shortMonthNames[monthNumber - 1],
                    amount: total,
                    isCurrent: offset == 0
                )
            }
        }
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
