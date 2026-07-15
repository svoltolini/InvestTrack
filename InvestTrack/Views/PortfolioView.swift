import SwiftUI

struct PortfolioView: View {
    enum SortOption: String, CaseIterable, Identifiable {
        case income = "By income"
        case value = "By value"
        case yield = "By yield"
        case name = "By name"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var sort: SortOption = .income

    private var sortedHoldings: [Holding] {
        let holdings = model.portfolio.holdings
        switch sort {
        case .income:
            return holdings.sorted { $0.annualIncome > $1.annualIncome }
        case .value:
            return holdings.sorted { $0.positionValue > $1.positionValue }
        case .yield:
            return holdings.sorted { $0.yieldOnCost > $1.yieldOnCost }
        case .name:
            return holdings.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 24) {
                    StatBlock(
                        label: "Total value",
                        value: model.money(model.portfolio.totalValue, withCode: true),
                        size: 20
                    )
                    StatBlock(
                        label: "Avg yield on cost",
                        value: model.portfolio.averageYieldOnCost > 0
                            ? Format.percent(model.portfolio.averageYieldOnCost, decimals: 2)
                            : "—",
                        size: 20,
                        tint: Theme.accent
                    )
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
                                HoldingRow(holding: holding)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .refreshable { await model.refresh() }
        .background(Theme.background)
        .navigationTitle("Portfolio")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .navigationDestination(for: Holding.self) { holding in
            HoldingDetailView(holding: holding)
        }
    }
}

private struct HoldingRow: View {
    @Environment(AppModel.self) private var model
    let holding: Holding

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
                Text(holding.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.money(holding.annualIncome, withCode: true))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if holding.yieldOnCost > 0 {
                    Text("\(Format.percent(holding.yieldOnCost)) YoC")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.positive)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environment(AppModel())
}
