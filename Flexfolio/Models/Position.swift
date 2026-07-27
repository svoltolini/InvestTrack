import Foundation
import SwiftData

/// One open position — snapshot data. Each sync upserts by symbol and deletes
/// symbols absent from the new statement. All money values are `Decimal`.
@Model
final class Position {
    @Attribute(.unique) var symbol: String
    var name: String
    var isin: String?
    var assetClass: String
    var currency: String
    var quantity: Decimal
    var markPrice: Decimal
    var marketValue: Decimal
    var marketValueBase: Decimal
    var costBasis: Decimal
    var unrealizedPnL: Decimal
    var unrealizedPnLBase: Decimal
    var fxRateToBase: Decimal
    var asOf: Date
    var importedAt: Date

    init(
        symbol: String,
        name: String,
        isin: String?,
        assetClass: String,
        currency: String,
        quantity: Decimal,
        markPrice: Decimal,
        marketValue: Decimal,
        marketValueBase: Decimal,
        costBasis: Decimal,
        unrealizedPnL: Decimal,
        unrealizedPnLBase: Decimal,
        fxRateToBase: Decimal,
        asOf: Date,
        importedAt: Date = .now
    ) {
        self.symbol = symbol
        self.name = name
        self.isin = isin
        self.assetClass = assetClass
        self.currency = currency
        self.quantity = quantity
        self.markPrice = markPrice
        self.marketValue = marketValue
        self.marketValueBase = marketValueBase
        self.costBasis = costBasis
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLBase = unrealizedPnLBase
        self.fxRateToBase = fxRateToBase
        self.asOf = asOf
        self.importedAt = importedAt
    }

    /// Cost basis converted at the position's current FX rate, for base-currency
    /// return and yield-on-cost math.
    var costBasisBase: Decimal { costBasis * fxRateToBase }
}
