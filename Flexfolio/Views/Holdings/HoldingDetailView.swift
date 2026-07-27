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
            .background(Theme.background)
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AsOfBadge()
                statsCard
                if let yield = yieldOnCost {
                    yieldCard(yield)
                }
                if !symbolEvents.isEmpty {
                    SectionHeader("Dividend income · monthly net")
                    chartCard
                    SectionHeader("Payments")
                    paymentsCard
                } else {
                    ContentUnavailableView(
                        "No dividends recorded",
                        systemImage: "banknote",
                        description: Text("No dividend payments for \(position.symbol) in the statement window.")
                    )
                    .frame(minHeight: 180)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle(position.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .refreshable { await syncStatus.manualSync() }
    }

    // MARK: - Stats

    private var statsCard: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10, alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 14
        ) {
            DetailStat(label: "Value", value: position.marketValueBase.money("CHF"))
            DetailStat(
                label: "Unrealized P&L",
                value: position.unrealizedPnLBase.signedMoney("CHF"),
                tint: position.unrealizedPnLBase >= 0 ? Theme.positive : Theme.negative
            )
            DetailStat(
                label: "Quantity",
                value: position.quantity.formatted(),
                subtitle: "@ \(position.markPrice.money(position.currency))"
            )
            DetailStat(
                label: "Cost basis",
                value: position.costBasis.money(position.currency),
                subtitle: position.currency == "CHF" ? nil : "≈ \(position.costBasisBase.money("CHF"))"
            )
        }
        .padding(16)
        .card()
    }

    private func yieldCard(_ yield: Decimal) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Yield on cost")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("TTM net dividends ÷ cost basis")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Text(yield.percent1)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.positive)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.accentTint)
        )
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

    // MARK: - Dividends

    private var chartCard: some View {
        let buckets = DividendMath.monthlyNet(symbolEvents)
        let currentMonth = buckets.last?.month
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Month", bucket.month, unit: .month),
                y: .value("Net CHF", bucket.net.plotValue),
                width: .ratio(0.5)
            )
            .foregroundStyle(bucket.month == currentMonth ? Theme.accent : Theme.chartMuted)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.utcStatement.month(.narrow)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 80)
        .padding(16)
        .card()
    }

    private var paymentGroups: [DividendMath.PaymentGroup] {
        DividendMath.paymentGroups(symbolEvents)
    }

    private var paymentsCard: some View {
        VStack(spacing: 0) {
            let groups = paymentGroups
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                HStack {
                    Text(group.date.dayMonthYear)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(group.netBase.money("CHF"))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("gross \(group.grossBase.money("CHF")) − WHT \(group.withheldBase.money("CHF"))")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < groups.count - 1 {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                }
            }
        }
        .card()
    }
}

private struct DetailStat: View {
    let label: String
    let value: String
    var subtitle: String?
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}
