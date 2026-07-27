import Foundation
import SwiftData

/// One day of account equity in base currency, from Equity Summary in Base by
/// Report Date. Upserted by date. A negative `cashBase` is a margin/Lombard
/// loan and is surfaced, never hidden.
@Model
final class NavPoint {
    @Attribute(.unique) var date: Date
    var cashBase: Decimal
    var stockBase: Decimal
    var totalBase: Decimal
    var importedAt: Date

    init(date: Date, cashBase: Decimal, stockBase: Decimal, totalBase: Decimal, importedAt: Date = .now) {
        self.date = date
        self.cashBase = cashBase
        self.stockBase = stockBase
        self.totalBase = totalBase
        self.importedAt = importedAt
    }
}
