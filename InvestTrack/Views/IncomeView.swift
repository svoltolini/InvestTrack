import SwiftUI
import Charts

struct IncomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statRow
                MonthlyIncomeCard()
                SectionHeader("Upcoming")
                upcomingList
                if !model.portfolio.currencyBreakdown.isEmpty {
                    SectionHeader("Currency breakdown")
                    CurrencyBreakdownCard()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .refreshable { await model.refresh() }
        .background(Theme.background)
        .navigationTitle("Income")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationDestination(for: Holding.self) { holding in
            HoldingDetailView(holding: holding)
        }
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 12) {
            StatBlock(
                label: Format.monthTitle(.now),
                value: model.money(model.currentMonthIncome, withCode: true)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            StatBlock(
                label: "Projected \(String(model.portfolio.monthlyIncomeYear))",
                value: model.money(model.portfolio.projectedAnnualIncome),
                tint: Theme.accent
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        if model.upcomingEvents.isEmpty {
            Text("No upcoming payments")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(18)
        } else {
            VStack(spacing: 14) {
                ForEach(model.upcomingEvents) { event in
                    UpcomingEventRow(event: event)
                }
            }
        }
    }
}

private struct UpcomingEventRow: View {
    @Environment(AppModel.self) private var model
    let event: DividendEvent

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 2) {
                Text(Format.dayNumber(event.date))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Format.monthAbbrev(event.date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 38)
            .padding(.top, 8)

            if let holding = model.holding(for: event.ticker) {
                NavigationLink(value: holding) {
                    card
                }
                .buttonStyle(PressableStyle())
            } else {
                card
            }
        }
    }

    private var card: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.upcomingDetail ?? event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Text(model.money(event.amount, decimals: 2))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }
}

private struct MonthlyIncomeCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let points = model.rollingMonthlyIncome()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Monthly income")
                Spacer()
                Text("Next 12 months")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
            }

            ZStack {
                chart(points)
                if points.allSatisfy({ $0.amount == 0 }) {
                    Text("No dividend income projected yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(16)
        .card()
    }

    private func chart(_ points: [MonthlyIncomePoint]) -> some View {
        // Categorical x keyed by month label; the window is exactly twelve
        // months, so every label is distinct and Charts preserves the forward
        // order they appear in.
        Chart(points) { point in
            BarMark(
                x: .value("Month", point.label),
                y: .value("Income", point.amount),
                width: .ratio(0.62)
            )
            .foregroundStyle(point.isCurrent ? Theme.accent : Theme.chartMuted)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    if let name = value.as(String.self) {
                        Text(name.prefix(1))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 100)
    }
}

private struct CurrencyBreakdownCard: View {
    @Environment(AppModel.self) private var model

    private static let palette: [Color] = [Theme.accent, Theme.accentMid, Theme.accentPale]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let slices = model.portfolio.currencyBreakdown
                let gaps = CGFloat(max(0, slices.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        Rectangle()
                            .fill(Self.palette[min(index, Self.palette.count - 1)])
                            .frame(width: max(0, (proxy.size.width - gaps) * slice.share))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 10)

            HStack(spacing: 16) {
                ForEach(Array(model.portfolio.currencyBreakdown.enumerated()), id: \.element.id) { index, slice in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.palette[min(index, Self.palette.count - 1)])
                            .frame(width: 8, height: 8)
                        Text("\(slice.code) \(Int((slice.share * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card()
    }
}

#Preview {
    NavigationStack {
        IncomeView()
    }
    .environment(AppModel())
}
