import Foundation
import SwiftData

/// An announced-but-unpaid dividend, from Change in Dividend Accruals.
/// `Po` rows upsert by key (symbol|exDate); `Re` rows delete the matching key
/// — a paid dividend shows up as Re here plus a CashTransaction.
@Model
final class DividendAccrual {
    @Attribute(.unique) var key: String
    var symbol: String
    var exDate: Date
    var payDate: Date?
    var quantity: Decimal
    var grossAmount: Decimal
    var netAmount: Decimal
    var netAmountBase: Decimal
    var currency: String
    var importedAt: Date

    init(
        key: String,
        symbol: String,
        exDate: Date,
        payDate: Date?,
        quantity: Decimal,
        grossAmount: Decimal,
        netAmount: Decimal,
        netAmountBase: Decimal,
        currency: String,
        importedAt: Date = .now
    ) {
        self.key = key
        self.symbol = symbol
        self.exDate = exDate
        self.payDate = payDate
        self.quantity = quantity
        self.grossAmount = grossAmount
        self.netAmount = netAmount
        self.netAmountBase = netAmountBase
        self.currency = currency
        self.importedAt = importedAt
    }

    static func makeKey(symbol: String, exDate: Date) -> String {
        "\(symbol)|\(FlexValue.dateKey(exDate))"
    }
}
