import Foundation

/// Plain value types emitted by the parser — SwiftData models are built from
/// these during import. All money is `Decimal`, parsed straight from the XML
/// attribute strings.

struct ParsedStatement {
    var accountID: String?
    var baseCurrency: String
    var fromDate: Date?
    var toDate: Date?
    var whenGenerated: Date?
    var positions: [ParsedPosition] = []
    var cashTransactions: [ParsedCashTransaction] = []
    var accruals: [ParsedAccrual] = []
    var navPoints: [ParsedNavPoint] = []
}

struct ParsedPosition {
    let symbol: String
    let description: String
    let isin: String?
    let assetCategory: String
    let currency: String
    let fxRateToBase: Decimal
    let position: Decimal
    let markPrice: Decimal
    let positionValue: Decimal
    let costBasisMoney: Decimal
    let fifoPnlUnrealized: Decimal
}

struct ParsedCashTransaction {
    let transactionID: String?
    let symbol: String?
    let currency: String
    let fxRateToBase: Decimal
    let date: Date
    let amount: Decimal
    let type: String
    let description: String
}

struct ParsedAccrual {
    let symbol: String
    let currency: String
    let fxRateToBase: Decimal
    let exDate: Date
    let payDate: Date?
    let quantity: Decimal
    let grossAmount: Decimal
    let netAmount: Decimal
    /// `Po` posts an accrual, `Re` reverses (removes) the matching one.
    let isReversal: Bool
}

struct ParsedNavPoint {
    let reportDate: Date
    let cash: Decimal
    let stock: Decimal
    let total: Decimal
}

/// The service-response document (`FlexStatementResponse`) — step 1's answer,
/// and step 2's answer while generation is still in progress or failed.
struct FlexServiceResponse {
    var status: String?
    var errorCode: Int?
    var errorMessage: String?
    var referenceCode: String?
    var url: String?

    var isSuccess: Bool { status?.lowercased() == "success" }
    var isInProgress: Bool { errorCode == 1019 }
}

enum FlexParseResult {
    case statement(ParsedStatement)
    case serviceResponse(FlexServiceResponse)
}
