#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only launch check (acceptance §11.3–.4): parses the spec's sample
/// statement (§6, plus a Po+Re accrual pair), imports it twice into an
/// in-memory store, and verifies exact row counts and idempotency. Prints a
/// single PASS/FAIL line; contains no credentials.
enum DebugSelfTest {
    private static var hasRun = false

    @MainActor
    static func runOnce() async {
        guard !hasRun else { return }
        hasRun = true
        do {
            try run()
        } catch {
            print("❌ Flexfolio self-test crashed: \(error)")
        }
    }

    private static func run() throws {
        // Parse
        guard case .statement(let parsed) = try FlexResponseParser.parse(Data(fixtureXML.utf8)) else {
            print("❌ Flexfolio self-test: fixture parsed as a service response")
            return
        }
        var failures: [String] = []
        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures.append(label) }
        }

        expect(parsed.baseCurrency == "CHF", "base currency CHF")
        expect(parsed.positions.count == 1, "1 parsed position (got \(parsed.positions.count))")
        expect(parsed.cashTransactions.count == 3, "3 parsed cash transactions (got \(parsed.cashTransactions.count))")
        expect(parsed.accruals.count == 3, "3 parsed accrual rows incl. Po+Re (got \(parsed.accruals.count))")
        expect(parsed.navPoints.count == 1, "1 parsed NAV point (got \(parsed.navPoints.count))")
        expect(parsed.positions.first?.position == Decimal(150), "GPIQ quantity 150")
        expect(parsed.positions.first?.positionValue == Decimal(string: "7381.50"), "GPIQ position value Decimal-exact")

        // Import into a throwaway in-memory store — twice.
        let schema = Schema([
            Position.self, DividendEvent.self, DividendAccrual.self,
            NavPoint.self, CashFlow.self, SyncRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false

        try StatementImporter.importStatement(parsed, into: context)
        try context.save()
        let firstCounts = try counts(in: context)
        try StatementImporter.importStatement(parsed, into: context)
        try context.save()
        let secondCounts = try counts(in: context)

        expect(firstCounts.positions == 1, "1 imported position (got \(firstCounts.positions))")
        expect(firstCounts.events == 2, "2 dividend events (got \(firstCounts.events))")
        expect(firstCounts.cashFlows == 1, "1 cash flow (got \(firstCounts.cashFlows))")
        expect(firstCounts.accruals == 1, "1 surviving accrual after Re removal (got \(firstCounts.accruals))")
        expect(firstCounts.navPoints == 1, "1 NAV point (got \(firstCounts.navPoints))")
        expect(firstCounts == secondCounts, "idempotent re-import (\(firstCounts) vs \(secondCounts))")

        if failures.isEmpty {
            print("✅ Flexfolio self-test passed: parser + idempotent import + Re removal")
        } else {
            print("❌ Flexfolio self-test FAILED: \(failures.joined(separator: "; "))")
        }
    }

    private struct Counts: Equatable, CustomStringConvertible {
        var positions = 0, events = 0, cashFlows = 0, accruals = 0, navPoints = 0
        var description: String {
            "positions \(positions), events \(events), cashFlows \(cashFlows), accruals \(accruals), nav \(navPoints)"
        }
    }

    private static func counts(in context: ModelContext) throws -> Counts {
        Counts(
            positions: try context.fetchCount(FetchDescriptor<Position>()),
            events: try context.fetchCount(FetchDescriptor<DividendEvent>()),
            cashFlows: try context.fetchCount(FetchDescriptor<CashFlow>()),
            accruals: try context.fetchCount(FetchDescriptor<DividendAccrual>()),
            navPoints: try context.fetchCount(FetchDescriptor<NavPoint>())
        )
    }

    /// §6 sample plus a TEST2 Po+Re pair proving reversal removal.
    private static let fixtureXML = """
    <FlexQueryResponse queryName="Flexfolio" type="AF">
     <FlexStatements count="1">
      <FlexStatement accountId="U1234567" fromDate="2025-07-28" toDate="2026-07-24" period="Last365CalendarDays" whenGenerated="2026-07-25;05:32:11">
       <AccountInformation accountId="U1234567" currency="CHF" name="Sample" />
       <OpenPositions>
        <OpenPosition symbol="GPIQ" description="GS NASDAQ-100 CORE PREM INC" isin="US38150Q6237" assetCategory="STK"
          currency="USD" fxRateToBase="0.7942" position="150" markPrice="49.21" positionValue="7381.50"
          costBasisMoney="7102.35" costBasisPrice="47.35" fifoPnlUnrealized="279.15" listingExchange="NASDAQ" side="Long"/>
       </OpenPositions>
       <CashTransactions>
        <CashTransaction transactionID="9876543210" symbol="GPIQ" isin="US38150Q6237" currency="USD" fxRateToBase="0.7942"
          dateTime="2026-07-15" amount="69.75" type="Dividends" description="GPIQ CASH DIVIDEND USD 0.465"/>
        <CashTransaction transactionID="9876543211" symbol="GPIQ" isin="US38150Q6237" currency="USD" fxRateToBase="0.7942"
          dateTime="2026-07-15" amount="-10.46" type="Withholding Tax" description="GPIQ WHT 15%"/>
        <CashTransaction transactionID="9876500001" symbol="" currency="CHF" fxRateToBase="1" dateTime="2026-07-01"
          amount="2000" type="Deposits/Withdrawals" description="CASH RECEIPT"/>
       </CashTransactions>
       <ChangeInDividendAccruals>
        <ChangeInDividendAccrual symbol="GPIQ" isin="US38150Q6237" currency="USD" fxRateToBase="0.7942" exDate="2026-07-31"
          payDate="2026-08-07" quantity="150" grossAmount="69.75" netAmount="59.29" code="Po"/>
        <ChangeInDividendAccrual symbol="TEST2" isin="US0000000000" currency="USD" fxRateToBase="0.7942" exDate="2026-06-30"
          payDate="2026-07-05" quantity="10" grossAmount="5.00" netAmount="4.25" code="Po"/>
        <ChangeInDividendAccrual symbol="TEST2" isin="US0000000000" currency="USD" fxRateToBase="0.7942" exDate="2026-06-30"
          payDate="2026-07-05" quantity="10" grossAmount="5.00" netAmount="4.25" code="Re"/>
       </ChangeInDividendAccruals>
       <EquitySummaryInBase>
        <EquitySummaryByReportDateInBase reportDate="2026-07-24" cash="118.42" stock="7381.50" total="7499.92"/>
       </EquitySummaryInBase>
      </FlexStatement>
     </FlexStatements>
    </FlexQueryResponse>
    """
}
#endif
