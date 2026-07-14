import SwiftUI
import Charts

struct HoldingDetailView: View {
    @Environment(AppModel.self) private var model
    let holding: Holding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statsCard
                nextPaymentCard
                SectionHeader("Dividend per share · 5Y")
                growthCard
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
            DetailStat(label: "Shares", value: String(holding.shares))
            DetailStat(label: "Annual dividend", value: model.money(holding.annualIncome, withCode: true), tint: Theme.accent)
            DetailStat(label: "Yield on cost", value: Format.percent(holding.yieldOnCost), tint: Theme.positive)
        }
        .padding(16)
        .card()
    }

    private var nextPaymentCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next payment")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(holding.nextPayment.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.money(holding.nextPayment.amount, decimals: 2, withCode: true))
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(holding.nextPayment.dateLabel)
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

    private var historyCard: some View {
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
