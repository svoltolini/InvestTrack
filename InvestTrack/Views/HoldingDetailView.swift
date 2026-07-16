import SwiftUI
import Charts

struct HoldingDetailView: View {
    @Environment(AppModel.self) private var model
    let holding: Holding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statsCard
                if let nextPayment = holding.nextPayment {
                    nextPaymentCard(nextPayment)
                }
                if !holding.dividendGrowth.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("Dividend per share · 5Y")
                        Spacer()
                        if let cagr = holding.dividendCAGR {
                            growthBadge(cagr)
                        }
                    }
                    growthCard
                }
                SectionHeader("Payment history")
                historyCard
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(holding.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(holding.ticker)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.pill)
                        )
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }

    private var statsCard: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10, alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 14
        ) {
            DetailStat(label: "Position value", value: model.money(holding.positionValue, withCode: true))
            DetailStat(label: "Shares", value: holding.sharesLabel)
            DetailStat(
                label: "Annual dividend",
                value: holding.annualIncome > 0 ? model.money(holding.annualIncome, withCode: true) : "—",
                tint: Theme.accent
            )
            DetailStat(
                label: "Yield on cost",
                value: holding.yieldOnCost > 0 ? Format.percent(holding.yieldOnCost) : "—",
                tint: Theme.positive
            )
        }
        .padding(16)
        .card()
    }

    private func nextPaymentCard(_ nextPayment: NextPayment) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next payment")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(nextPayment.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.money(nextPayment.amount, decimals: 2, withCode: true))
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(nextPayment.dateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.accentTint)
        )
    }

    /// Annualised dividend-per-share growth (CAGR) across the full years shown,
    /// e.g. "▲ 6.2%/yr". Green when growing, red when shrinking.
    private func growthBadge(_ fraction: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: fraction >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 7))
            Text("\(Format.percent(abs(fraction)))/yr")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(fraction >= 0 ? Theme.positive : Theme.negative)
    }

    private var growthCard: some View {
        let latestYear = holding.dividendGrowth.map(\.year).max()
        return Chart(holding.dividendGrowth) { point in
            BarMark(
                x: .value("Year", String(point.year)),
                y: .value("Dividend", point.dividendPerShare),
                width: .ratio(0.5)
            )
            .foregroundStyle(point.year == latestYear ? Theme.accent : Theme.chartMuted)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    if let year = value.as(String.self) {
                        Text(year)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 70)
        .padding(16)
        .card()
    }

    @ViewBuilder
    private var historyCard: some View {
        if holding.paymentHistory.isEmpty {
            Text("No payments recorded for this position")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(18)
                .card()
        } else {
            historyRows
        }
    }

    private var historyRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(holding.paymentHistory.enumerated()), id: \.element.id) { index, payment in
                HStack {
                    Text(Format.fullDate(payment.date))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(model.money(payment.amount, decimals: 2, withCode: true))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < holding.paymentHistory.count - 1 {
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
        }
    }
}

#Preview {
    NavigationStack {
        HoldingDetailView(holding: Portfolio.sample.holdings[0])
    }
    .environment(AppModel())
}
