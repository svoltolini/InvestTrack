import Charts
import SwiftData
import SwiftUI

struct HoldingDetailView: View {
    let position: Position
    @Environment(SyncStatus.self) private var syncStatus
    @Query private var symbolEvents: [DividendEvent]

    init(position: Position) {
        self.position = position
        let symbol = position.symbol
        _symbolEvents = Query(
            filter: #Predicate<DividendEvent> { $0.symbol == symbol },
            sort: \DividendEvent.date,
            order: .reverse
        )
    }

    var body: some View {
        // A sync can close (delete) this position while the screen is pushed —
        // snapshot semantics remove symbols absent from the new statement.
        // Never keep reading a deleted model.
        if position.isDeleted {
            ContentUnavailableView(
                "Position closed",
                systemImage: "briefcase",
                description: Text("This position is no longer in your account.")
            )
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                AsOfBadge()
                    .listRowBackground(Color.clear)
                statsGrid
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let yield = yieldOnCost {
                Section {
                    LabeledContent("Yield on cost (TTM net)") {
                        Text(yield.percent1)
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
            }

            if !symbolEvents.isEmpty {
                Section("Dividend income · monthly net") {
                    miniChart
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
                Section("Payments") {
                    ForEach(paymentGroups) { group in
                        HStack {
                            Text(group.date.dayMonthYear)
                                .font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(group.netBase.money("CHF"))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Text("gross \(group.grossBase.money("CHF")) − WHT \(group.withheldBase.money("CHF"))")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No dividends recorded",
                        systemImage: "banknote",
                        description: Text("No dividend payments for \(position.symbol) in the statement window.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(position.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await syncStatus.manualSync() }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCard(title: "Value", value: position.marketValueBase.money("CHF"))
            StatCard(
                title: "Unrealized P&L",
                value: position.unrealizedPnLBase.signedMoney("CHF"),
                tint: position.unrealizedPnLBase >= 0 ? .green : .red
            )
            StatCard(
                title: "Quantity",
                value: position.quantity.formatted(),
                subtitle: "@ \(position.markPrice.money(position.currency))"
            )
            StatCard(
                title: "Cost basis",
                value: position.costBasis.money(position.currency),
                subtitle: position.currency == "CHF" ? nil : "≈ \(position.costBasisBase.money("CHF"))"
            )
        }
    }

    /// TTM net dividends ÷ cost basis — only meaningful with a real payment
    /// history, so it requires at least four dividend events.
    private var yieldOnCost: Decimal? {
        let dividendCount = symbolEvents.filter { !$0.isWithholding }.count
        guard dividendCount >= 4, position.costBasisBase > 0 else { return nil }
        let ttm = DividendMath.ttmNet(symbolEvents)
        guard ttm > 0 else { return nil }
        return ttm / position.costBasisBase
    }

    private var paymentGroups: [DividendMath.PaymentGroup] {
        DividendMath.paymentGroups(symbolEvents)
    }

    private var miniChart: some View {
        Chart(DividendMath.monthlyNet(symbolEvents)) { bucket in
            BarMark(
                x: .value("Month", bucket.month, unit: .month),
                y: .value("Net CHF", bucket.net.plotValue)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                AxisValueLabel(format: Date.FormatStyle.utcStatement.month(.narrow), centered: true)
            }
        }
        .frame(height: 90)
        .padding(.vertical, 4)
    }
}
