import Foundation
import SwiftData

enum DividendKind: String, Codable, CaseIterable {
    case dividend
    case paymentInLieu
    case withholdingTax

    /// Maps the Flex `type` attribute; nil for non-dividend cash rows.
    init?(flexType: String) {
        switch flexType.lowercased() {
        case "dividends": self = .dividend
        case "payment in lieu of dividends": self = .paymentInLieu
        case "withholding tax": self = .withholdingTax
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .dividend: "Dividend"
        case .paymentInLieu: "Payment in lieu"
        case .withholdingTax: "Withholding tax"
        }
    }
}

/// One dividend-related cash transaction. Append-only; strictly deduped on
/// `transactionID` (or a deterministic fallback key when IBKR omits it).
/// Withholding-tax rows carry negative amounts.
@Model
final class DividendEvent {
    @Attribute(.unique) var transactionID: String
    var symbol: String
    var date: Date
    var kindRaw: String
    var amount: Decimal
    var amountBase: Decimal
    var currency: String
    var fxRateToBase: Decimal
    var descriptionText: String
    var importedAt: Date

    init(
        transactionID: String,
        symbol: String,
        date: Date,
        kind: DividendKind,
        amount: Decimal,
        amountBase: Decimal,
        currency: String,
        fxRateToBase: Decimal,
        descriptionText: String,
        importedAt: Date = .now
    ) {
        self.transactionID = transactionID
        self.symbol = symbol
        self.date = date
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.amountBase = amountBase
        self.currency = currency
        self.fxRateToBase = fxRateToBase
        self.descriptionText = descriptionText
        self.importedAt = importedAt
    }

    var kind: DividendKind {
        DividendKind(rawValue: kindRaw) ?? .dividend
    }

    var isWithholding: Bool { kind == .withholdingTax }
}
