import CryptoKit
import Foundation
import SwiftData

struct SyncSummary {
    var newDividendEvents = 0
    var newCashFlows = 0
    var positionCount = 0
    var accrualCount = 0
    var navPointCount = 0
    var dataThrough: Date?
}

/// Turns a `ParsedStatement` into SwiftData rows. Pure upsert logic, callable
/// from the sync engine and the DEBUG self-test alike. Importing the same
/// statement twice produces zero new rows (acceptance criterion).
enum StatementImporter {
    /// Dividend-related cash transaction types → DividendKind; deposit rows
    /// become CashFlow. Everything else is ignored.
    @discardableResult
    static func importStatement(_ parsed: ParsedStatement, into context: ModelContext) throws -> SyncSummary {
        var summary = SyncSummary()
        let importedAt = Date.now

        try importPositions(parsed, context: context, importedAt: importedAt, summary: &summary)
        try importCashTransactions(parsed, context: context, importedAt: importedAt, summary: &summary)
        try importAccruals(parsed, context: context, importedAt: importedAt, summary: &summary)
        try importNavPoints(parsed, context: context, importedAt: importedAt, summary: &summary)

        summary.dataThrough = parsed.navPoints.map(\.reportDate).max() ?? parsed.toDate
        try context.save()
        return summary
    }

    // MARK: - Positions (snapshot: upsert by symbol, delete absentees)

    private static func importPositions(
        _ parsed: ParsedStatement,
        context: ModelContext,
        importedAt: Date,
        summary: inout SyncSummary
    ) throws {
        // Aggregate defensively in case the query is set to lot-level detail
        // and delivers several rows per symbol.
        var bySymbol: [String: ParsedPosition] = [:]
        for row in parsed.positions {
            if let existing = bySymbol[row.symbol] {
                bySymbol[row.symbol] = ParsedPosition(
                    symbol: row.symbol,
                    description: row.description,
                    isin: row.isin ?? existing.isin,
                    assetCategory: row.assetCategory,
                    currency: row.currency,
                    fxRateToBase: row.fxRateToBase,
                    position: existing.position + row.position,
                    markPrice: row.markPrice,
                    positionValue: existing.positionValue + row.positionValue,
                    costBasisMoney: existing.costBasisMoney + row.costBasisMoney,
                    fifoPnlUnrealized: existing.fifoPnlUnrealized + row.fifoPnlUnrealized
                )
            } else {
                bySymbol[row.symbol] = row
            }
        }

        let asOf = parsed.navPoints.map(\.reportDate).max() ?? parsed.toDate ?? importedAt
        let existing = try context.fetch(FetchDescriptor<Position>())
        var existingBySymbol = Dictionary(uniqueKeysWithValues: existing.map { ($0.symbol, $0) })

        for (symbol, row) in bySymbol {
            let valueBase = row.positionValue * row.fxRateToBase
            let pnlBase = row.fifoPnlUnrealized * row.fxRateToBase
            if let position = existingBySymbol.removeValue(forKey: symbol) {
                position.name = row.description
                position.isin = row.isin
                position.assetClass = row.assetCategory
                position.currency = row.currency
                position.quantity = row.position
                position.markPrice = row.markPrice
                position.marketValue = row.positionValue
                position.marketValueBase = valueBase
                position.costBasis = row.costBasisMoney
                position.unrealizedPnL = row.fifoPnlUnrealized
                position.unrealizedPnLBase = pnlBase
                position.fxRateToBase = row.fxRateToBase
                position.asOf = asOf
                position.importedAt = importedAt
            } else {
                context.insert(Position(
                    symbol: symbol,
                    name: row.description,
                    isin: row.isin,
                    assetClass: row.assetCategory,
                    currency: row.currency,
                    quantity: row.position,
                    markPrice: row.markPrice,
                    marketValue: row.positionValue,
                    marketValueBase: valueBase,
                    costBasis: row.costBasisMoney,
                    unrealizedPnL: row.fifoPnlUnrealized,
                    unrealizedPnLBase: pnlBase,
                    fxRateToBase: row.fxRateToBase,
                    asOf: asOf,
                    importedAt: importedAt
                ))
            }
        }
        // Whatever is left wasn't in the statement — position was closed.
        for (_, stale) in existingBySymbol {
            context.delete(stale)
        }
        summary.positionCount = bySymbol.count
    }

    // MARK: - Cash transactions (append-only, deduped on transactionID)

    private static func importCashTransactions(
        _ parsed: ParsedStatement,
        context: ModelContext,
        importedAt: Date,
        summary: inout SyncSummary
    ) throws {
        var knownEventIDs = Set(try context.fetch(FetchDescriptor<DividendEvent>()).map(\.transactionID))
        var knownCashFlowIDs = Set(try context.fetch(FetchDescriptor<CashFlow>()).map(\.transactionID))

        for row in parsed.cashTransactions {
            if let kind = DividendKind(flexType: row.type) {
                let id = row.transactionID ?? fallbackID(row)
                guard knownEventIDs.insert(id).inserted else { continue }
                context.insert(DividendEvent(
                    transactionID: id,
                    symbol: row.symbol ?? "",
                    date: row.date,
                    kind: kind,
                    amount: row.amount,
                    amountBase: row.amount * row.fxRateToBase,
                    currency: row.currency,
                    fxRateToBase: row.fxRateToBase,
                    descriptionText: row.description,
                    importedAt: importedAt
                ))
                summary.newDividendEvents += 1
            } else if isDepositWithdrawal(row.type) {
                let id = row.transactionID ?? fallbackID(row)
                guard knownCashFlowIDs.insert(id).inserted else { continue }
                context.insert(CashFlow(
                    transactionID: id,
                    date: row.date,
                    amountBase: row.amount * row.fxRateToBase,
                    kind: row.amount < 0 ? .withdrawal : .deposit,
                    importedAt: importedAt
                ))
                summary.newCashFlows += 1
            }
        }
    }

    private static func isDepositWithdrawal(_ type: String) -> Bool {
        let normalized = type.lowercased()
        return normalized == "deposits/withdrawals" || normalized == "deposits & withdrawals"
    }

    /// Deterministic fallback key when IBKR omits transactionID:
    /// SHA-256 of (symbol|date|type|amount).
    private static func fallbackID(_ row: ParsedCashTransaction) -> String {
        let seed = "\(row.symbol ?? "")|\(FlexValue.dateKey(row.date))|\(row.type)|\(row.amount)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Accruals (statement-driven state: Po upserts, Re removes)

    private static func importAccruals(
        _ parsed: ParsedStatement,
        context: ModelContext,
        importedAt: Date,
        summary: inout SyncSummary
    ) throws {
        // Fold the statement's rows in document order: a Re cancels the
        // matching Po even within the same statement (a paid dividend appears
        // as Po earlier + Re when it pays).
        var folded: [String: ParsedAccrual] = [:]
        for row in parsed.accruals {
            let key = DividendAccrual.makeKey(symbol: row.symbol, exDate: row.exDate)
            if row.isReversal {
                folded.removeValue(forKey: key)
            } else {
                folded[key] = row
            }
        }

        // The statement window (365 days) fully covers live accruals, so DB
        // state is reconciled to the fold: upsert survivors, delete the rest.
        let existing = try context.fetch(FetchDescriptor<DividendAccrual>())
        var existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })

        for (key, row) in folded {
            if let accrual = existingByKey.removeValue(forKey: key) {
                accrual.payDate = row.payDate
                accrual.quantity = row.quantity
                accrual.grossAmount = row.grossAmount
                accrual.netAmount = row.netAmount
                accrual.netAmountBase = row.netAmount * row.fxRateToBase
                accrual.currency = row.currency
                accrual.importedAt = importedAt
            } else {
                context.insert(DividendAccrual(
                    key: key,
                    symbol: row.symbol,
                    exDate: row.exDate,
                    payDate: row.payDate,
                    quantity: row.quantity,
                    grossAmount: row.grossAmount,
                    netAmount: row.netAmount,
                    netAmountBase: row.netAmount * row.fxRateToBase,
                    currency: row.currency,
                    importedAt: importedAt
                ))
            }
        }
        for (_, stale) in existingByKey {
            context.delete(stale)
        }
        summary.accrualCount = folded.count
    }

    // MARK: - NAV points (upsert by date)

    private static func importNavPoints(
        _ parsed: ParsedStatement,
        context: ModelContext,
        importedAt: Date,
        summary: inout SyncSummary
    ) throws {
        let existing = try context.fetch(FetchDescriptor<NavPoint>())
        let existingByDate = Dictionary(uniqueKeysWithValues: existing.map { ($0.date, $0) })

        // Fold duplicate report dates (last row wins) before touching the DB.
        var byDate: [Date: ParsedNavPoint] = [:]
        for row in parsed.navPoints {
            byDate[row.reportDate] = row
        }

        for (_, row) in byDate {
            if let point = existingByDate[row.reportDate] {
                point.cashBase = row.cash
                point.stockBase = row.stock
                point.totalBase = row.total
                point.importedAt = importedAt
            } else {
                context.insert(NavPoint(
                    date: row.reportDate,
                    cashBase: row.cash,
                    stockBase: row.stock,
                    totalBase: row.total,
                    importedAt: importedAt
                ))
            }
        }
        summary.navPointCount = byDate.count
    }
}
