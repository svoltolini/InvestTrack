import SwiftUI

struct PortfolioView: View {
    enum SortOption: String, CaseIterable, Identifiable {
        case value = "By value"
        case gain = "By return"
        case income = "By income"
        case name = "By name"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var sort: SortOption = .value

    private var sortedHoldings: [Holding] {
        let holdings = model.portfolio.holdings
        switch sort {
        case .value:
            return holdings.sorted { $0.positionValue > $1.positionValue }
        case .gain:
            return holdings.sorted { ($0.unrealizedProfit ?? 0) > ($1.unrealizedProfit ?? 0) }
        case .income:
            return holdings.sorted { $0.annualIncome > $1.annualIncome }
        case .name:
            return holdings.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                holdingsSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .refreshable { await model.refresh() }
        .background(Theme.background)
        .navigationTitle("Portfolio")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationDestination(for: Holding.self) { holding in
            HoldingDetailView(holding: holding)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let portfolio = model.portfolio
        let profit = portfolio.totalUnrealizedProfit
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total value")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                Text(model.money(portfolio.totalValue, withCode: true))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let profit, profit != 0 {
                    returnBadge(profit: profit, fraction: portfolio.totalReturnFraction)
                }
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            HStack(alignment: .top) {
                miniStat("Cash", model.money(portfolio.cashBalance))
                Spacer()
                miniStat("Positions", String(portfolio.holdings.count))
                Spacer()
                miniStat(
                    "Income / yr",
                    portfolio.projectedAnnualIncome > 0 ? model.money(portfolio.projectedAnnualIncome) : "—"
                )
            }
        }
        .padding(16)
        .card()
    }

    private func returnBadge(profit: Double, fraction: Double?) -> some View {
        let up = profit >= 0
        let amount = model.money(abs(profit), withCode: true)
        let percent = fraction.map { " (\(Format.percent(abs($0))))" } ?? ""
        return HStack(spacing: 4) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
            Text("\(amount)\(percent) all-time")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(up ? Theme.positive : Theme.negative)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Holdings

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("Holdings")
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    PillChipLabel(text: sort.rawValue)
                }
            }

            if sortedHoldings.isEmpty {
                Text("No open positions in this account")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedHoldings) { holding in
                        NavigationLink(value: holding) {
                            HoldingRow(holding: holding, portfolioValue: model.portfolio.totalValue)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

private struct HoldingRow: View {
    @Environment(AppModel.self) private var model
    let holding: Holding
    let portfolioValue: Double

    private var allocation: Double? {
        guard portfolioValue > 0, holding.positionValue > 0 else { return nil }
        return holding.positionValue / portfolioValue
    }

    private var subtitle: String {
        var parts = ["\(holding.sharesLabel) shares"]
        if let allocation {
            parts.append("\(Int((allocation * 100).rounded()))% of portfolio")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(holding.ticker)
                .font(.system(size: 11, weight: .bold))
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .padding(.horizontal, 1)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accentTint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.money(holding.positionValue))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                trailingDetail
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }

    @ViewBuilder
    private var trailingDetail: some View {
        if let fraction = holding.returnFraction {
            let up = fraction >= 0
            Text("\(up ? "▲" : "▼") \(Format.percent(abs(fraction)))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(up ? Theme.positive : Theme.negative)
        } else if holding.annualIncome > 0 {
            Text("\(model.money(holding.annualIncome))/yr")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environment(AppModel())
}
