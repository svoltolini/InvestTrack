import SwiftUI
import Charts

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
                if model.dataSource == .saxo && model.portfolio.hasIncompletePricing {
                    pricingNotice
                }
                allocationSection
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

            HStack(alignment: .top, spacing: 0) {
                cashStat(portfolio.cashBalance)
                    .frame(maxWidth: .infinity)
                miniStat("Positions", String(portfolio.holdings.count))
                    .frame(maxWidth: .infinity)
                miniStat(
                    "Income / yr",
                    portfolio.projectedAnnualIncome > 0 ? model.money(portfolio.projectedAnnualIncome) : "—"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .card()
    }

    private func returnBadge(profit: Double, fraction: Double?) -> some View {
        let up = profit >= 0
        let amount = model.money(abs(profit), decimals: 2, withCode: true)
        let text = fraction.map { "\(amount) • \(Format.percent(abs($0)))" } ?? amount
        return HStack(spacing: 4) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(up ? Theme.positive : Theme.negative)
    }

    private var pricingNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            Text("Some holdings couldn't be priced, so their amount shows what you invested (at cost). Other prices are delayed and sourced from Yahoo Finance.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accentTint)
        )
    }

    private func miniStat(_ label: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .multilineTextAlignment(.center)
    }

    /// A negative cash balance is a Lombard/margin loan: shown in amber with no
    /// minus sign and labelled "Loan"; a positive balance is cash, in blue.
    private func cashStat(_ balance: Double) -> some View {
        let isLoan = balance < 0
        return miniStat(
            isLoan ? "Loan" : "Cash",
            model.money(abs(balance)),
            color: isLoan ? Theme.warning : Theme.accent
        )
    }

    // MARK: - Holdings

    // MARK: - Allocation

    private var allocationSlices: [AllocationSlice] {
        AllocationSlice.make(from: model.portfolio.holdings)
    }

    @ViewBuilder
    private var allocationSection: some View {
        let slices = allocationSlices
        if slices.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Allocation")
                AllocationCard(slices: slices)
            }
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
                            HoldingRow(holding: holding)
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

    private var subtitle: String {
        "\(holding.sharesLabel) shares"
    }

    var body: some View {
        HStack(spacing: 12) {
            StockIconBadge(ticker: holding.ticker)

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
                valueText
                trailingDetail
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }

    @ViewBuilder
    private var valueText: some View {
        if holding.positionValue > 0 {
            Text(model.money(holding.positionValue))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        } else if let native = holding.nativeCostLabel {
            Text(native)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text("—")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var isAtCost: Bool {
        holding.valueIsAtCost || (holding.positionValue <= 0 && holding.nativeCostLabel != nil)
    }

    @ViewBuilder
    private var trailingDetail: some View {
        if isAtCost {
            Text("at cost")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textMuted)
        } else if let fraction = holding.returnFraction {
            let up = fraction >= 0
            Text("\(up ? "▲" : "▼") \(Format.percent(abs(fraction)))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(up ? Theme.positive : Theme.negative)
        } else if holding.positionValue <= 0 {
            Text("no live price")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textFaint)
        }
    }
}

// MARK: - Allocation donut

private struct AllocationSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let share: Double // 0…1
    let color: Color

    /// Validated categorical hues (data-viz light palette). Order is the
    /// colorblind-safety mechanism — assigned in order, never cycled.
    private static let palette: [Color] = [
        Color(hex: 0x2A78D6), // blue
        Color(hex: 0x008300), // green
        Color(hex: 0xE87BA4), // magenta
        Color(hex: 0xEDA100), // yellow
        Color(hex: 0x1BAF7A), // aqua
        Color(hex: 0xEB6834), // orange
    ]
    private static let otherColor = Color(hex: 0xB8BCC2)

    /// Builds slices from holdings by market value, largest first, folding the
    /// smallest into "Other" once past the palette size.
    static func make(from holdings: [Holding]) -> [AllocationSlice] {
        let priced = holdings.filter { $0.positionValue > 0 }
            .sorted { $0.positionValue > $1.positionValue }
        let total = priced.reduce(0) { $0 + $1.positionValue }
        guard total > 0 else { return [] }

        let maxNamed = palette.count
        var slices: [AllocationSlice] = []
        if priced.count <= maxNamed {
            for (index, holding) in priced.enumerated() {
                slices.append(AllocationSlice(
                    id: holding.id,
                    label: holding.ticker,
                    value: holding.positionValue,
                    share: holding.positionValue / total,
                    color: palette[index]
                ))
            }
        } else {
            for (index, holding) in priced.prefix(maxNamed - 1).enumerated() {
                slices.append(AllocationSlice(
                    id: holding.id,
                    label: holding.ticker,
                    value: holding.positionValue,
                    share: holding.positionValue / total,
                    color: palette[index]
                ))
            }
            let rest = priced.dropFirst(maxNamed - 1).reduce(0) { $0 + $1.positionValue }
            slices.append(AllocationSlice(
                id: "other",
                label: "Other",
                value: rest,
                share: rest / total,
                color: otherColor
            ))
        }
        return slices
    }
}

private struct AllocationCard: View {
    let slices: [AllocationSlice]

    var body: some View {
        HStack(spacing: 18) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Value", slice.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(Int((slice.share * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card()
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environment(AppModel())
    .environment(StockIconStore())
}
