import Foundation

// Wire models for the Saxo OpenAPI. Field names are PascalCase on the wire;
// nearly everything is optional because Saxo omits fields per asset type,
// account state, and environment (SIM vs LIVE).

/// Collection envelope: `{"Data":[...], "__next": "...", "__count": n}`.
struct SaxoList<Element: Decodable>: Decodable {
    let data: [Element]?
    let next: String?

    enum CodingKeys: String, CodingKey {
        case data = "Data"
        case next = "__next"
    }

    var items: [Element] { data ?? [] }
}

// MARK: - port/v1

struct SaxoClient: Decodable {
    let clientKey: String
    let clientId: String?
    let name: String?
    let defaultAccountKey: String?
    let defaultAccountId: String?
    let defaultCurrency: String?

    enum CodingKeys: String, CodingKey {
        case clientKey = "ClientKey"
        case clientId = "ClientId"
        case name = "Name"
        case defaultAccountKey = "DefaultAccountKey"
        case defaultAccountId = "DefaultAccountId"
        case defaultCurrency = "DefaultCurrency"
    }
}

struct SaxoAccount: Decodable {
    let accountKey: String
    let accountId: String?
    let currency: String?
    let displayName: String?
    let active: Bool?

    enum CodingKeys: String, CodingKey {
        case accountKey = "AccountKey"
        case accountId = "AccountId"
        case currency = "Currency"
        case displayName = "DisplayName"
        case active = "Active"
    }
}

struct SaxoBalance: Decodable {
    let totalValue: Double?
    let cashBalance: Double?
    let currency: String?
    let currencyDecimals: Int?
    let nonMarginPositionsValue: Double?
    let calculationReliability: String?

    enum CodingKeys: String, CodingKey {
        case totalValue = "TotalValue"
        case cashBalance = "CashBalance"
        case currency = "Currency"
        case currencyDecimals = "CurrencyDecimals"
        case nonMarginPositionsValue = "NonMarginPositionsValue"
        case calculationReliability = "CalculationReliability"
    }
}

struct SaxoNetPosition: Decodable {
    let netPositionId: String?
    let base: Base?
    let view: View?
    let displayAndFormat: DisplayAndFormat?

    enum CodingKeys: String, CodingKey {
        case netPositionId = "NetPositionId"
        case base = "NetPositionBase"
        case view = "NetPositionView"
        case displayAndFormat = "DisplayAndFormat"
    }

    struct Base: Decodable {
        let amount: Double?
        let assetType: String?
        let uic: Int?

        enum CodingKeys: String, CodingKey {
            case amount = "Amount"
            case assetType = "AssetType"
            case uic = "Uic"
        }
    }

    struct View: Decodable {
        let averageOpenPrice: Double?
        let currentPrice: Double?
        let marketValue: Double?
        let marketValueInBaseCurrency: Double?
        let exposure: Double?
        let exposureCurrency: String?
        let profitLossOnTradeInBaseCurrency: Double?
        let positionCount: Int?

        enum CodingKeys: String, CodingKey {
            case averageOpenPrice = "AverageOpenPrice"
            case currentPrice = "CurrentPrice"
            case marketValue = "MarketValue"
            case marketValueInBaseCurrency = "MarketValueInBaseCurrency"
            case exposure = "Exposure"
            case exposureCurrency = "ExposureCurrency"
            case profitLossOnTradeInBaseCurrency = "ProfitLossOnTradeInBaseCurrency"
            case positionCount = "PositionCount"
        }
    }

    struct DisplayAndFormat: Decodable {
        let symbol: String?
        let description: String?
        let currency: String?
        let decimals: Int?

        enum CodingKeys: String, CodingKey {
            case symbol = "Symbol"
            case description = "Description"
            case currency = "Currency"
            case decimals = "Decimals"
        }
    }
}

// MARK: - cs/v1 bookings (dividends received; real data on LIVE only)

struct SaxoBooking: Decodable {
    let amount: Double?
    let amountClientCurrency: Double?
    let amountAccountCurrency: Double?
    let currency: String?
    let date: String?
    let valueDate: String?
    let assetType: String?
    let uic: Int?
    let instrumentSymbol: String?
    let instrumentDescription: String?
    let amountClass: String?
    let amountSubClass: String?

    enum CodingKeys: String, CodingKey {
        case amount = "Amount"
        case amountClientCurrency = "AmountClientCurrency"
        case amountAccountCurrency = "AmountAccountCurrency"
        case currency = "Currency"
        case date = "Date"
        case valueDate = "ValueDate"
        case assetType = "AssetType"
        case uic = "Uic"
        case instrumentSymbol = "InstrumentSymbol"
        case instrumentDescription = "InstrumentDescription"
        case amountClass = "AmountClass"
        case amountSubClass = "AmountSubClass"
    }

    /// "Ongoing payments from securities such as dividends and bond coupons".
    var isIncomePayment: Bool {
        guard let amountClass else { return false }
        return amountClass.compare("OngoingPayment", options: .caseInsensitive) == .orderedSame
    }
}

// MARK: - hist/v1 transactions (fallback income ledger; no instrument attribution)

struct SaxoHistTransaction: Decodable {
    let date: String?
    let valueDate: String?
    let transactionType: String?
    let transactionTypeDisplay: String?
    let event: String?
    let eventDisplay: String?
    let currency: String?
    let bookedAmount: Double?

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case valueDate = "ValueDate"
        case transactionType = "TransactionType"
        case transactionTypeDisplay = "TransactionTypeDisplay"
        case event = "Event"
        case eventDisplay = "EventDisplay"
        case currency = "Currency"
        case bookedAmount = "BookedAmount"
    }

    /// Heuristic dividend match — the exact enum strings are undocumented,
    /// so match broadly on "dividend"/"corporate action" wording.
    var looksLikeDividend: Bool {
        let haystack = [transactionType, transactionTypeDisplay, event, eventDisplay]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return haystack.contains("dividend") || haystack.contains("corporate action")
    }
}

// MARK: - ca/v2 events (upcoming dividends; entitlement-gated, expect 403)

struct SaxoCAEvent: Decodable {
    let eventId: String?
    let eventState: String?
    let eventType: EventType?
    let uic: Int?
    let assetType: String?
    let displayAndFormat: SaxoNetPosition.DisplayAndFormat?
    let exDate: EventDate?
    let options: [EventOption]?
    let holdings: [EventHolding]?

    enum CodingKeys: String, CodingKey {
        case eventId = "EventId"
        case eventState = "EventState"
        case eventType = "EventType"
        case uic = "Uic"
        case assetType = "AssetType"
        case displayAndFormat = "DisplayAndFormat"
        case exDate = "Ex"
        case options = "Options"
        case holdings = "Holdings"
    }

    struct EventType: Decodable {
        let code: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case name = "Name"
        }
    }

    struct EventDate: Decodable {
        let date: String?

        enum CodingKeys: String, CodingKey {
            case date = "Date"
        }
    }

    struct EventOption: Decodable {
        let optionType: String?
        let payment: EventDate?
        let payoutBreakdown: [Payout]?

        enum CodingKeys: String, CodingKey {
            case optionType = "OptionType"
            case payment = "Payment"
            case payoutBreakdown = "PayoutBreakdown"
        }

        struct Payout: Decodable {
            let amount: Double?
            let currency: String?

            enum CodingKeys: String, CodingKey {
                case amount = "Amount"
                case currency = "Currency"
            }
        }
    }

    struct EventHolding: Decodable {
        let amount: Double?

        enum CodingKeys: String, CodingKey {
            case amount = "Amount"
        }
    }
}

// MARK: - Date parsing

enum SaxoDates {
    private static let isoWithTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .gregorian
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let raw = isoWithTime.date(from: string)
            ?? isoWithFraction.date(from: string)
            ?? dayOnly.date(from: String(string.prefix(10)))
        guard let raw else { return nil }
        // Saxo dates are day-precision at UTC midnight. Rebuild the same
        // calendar day at local noon so month bucketing and date labels
        // (which use the local-timezone calendar) never shift a day.
        var components = utcCalendar.dateComponents([.year, .month, .day], from: raw)
        components.hour = 12
        return Calendar.gregorian.date(from: components) ?? raw
    }
}
