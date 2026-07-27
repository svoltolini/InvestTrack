import Foundation
import SwiftData

enum CashFlowKind: String, Codable {
    case deposit
    case withdrawal
}

/// A deposit or withdrawal, in base currency. The running sum of these is the
/// dashed "Net invested" line on the dashboard chart.
@Model
final class CashFlow {
    @Attribute(.unique) var transactionID: String
    var date: Date
    var amountBase: Decimal
    var kindRaw: String
    var importedAt: Date

    init(transactionID: String, date: Date, amountBase: Decimal, kind: CashFlowKind, importedAt: Date = .now) {
        self.transactionID = transactionID
        self.date = date
        self.amountBase = amountBase
        self.kindRaw = kind.rawValue
        self.importedAt = importedAt
    }

    var kind: CashFlowKind {
        CashFlowKind(rawValue: kindRaw) ?? .deposit
    }
}
