import SwiftData
import SwiftUI

struct HoldingsView: View {
    @Environment(SyncStatus.self) private var syncStatus
    @Query private var positions: [Position]
    @State private var searchText = ""
    @State private var showSettings = false

    private var sorted: [Position] {
        let filtered = searchText.isEmpty
            ? positions
            : positions.filter {
                $0.symbol.localizedCaseInsensitiveContains(searchText)
                    || $0.name.localizedCaseInsensitiveContains(searchText)
            }
        return filtered.sorted { $0.marketValueBase > $1.marketValueBase }
    }

    private var totalValueBase: Decimal {
        positions.reduce(0) { $0 + $1.marketValueBase }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SyncErrorBanner { showSettings = true }
                AsOfBadge()
                if positions.isEmpty {
                    ContentUnavailableView(
                        "No holdings yet",
                        systemImage: "briefcase",
                        description: Text("Your open positions appear here after the first sync.")
                    )
                    .frame(minHeight: 300)
                } else if sorted.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(minHeight: 300)
                } else {
                    VStack(spacing: 10) {
                        ForEach(sorted) { position in
                            NavigationLink {
                                HoldingDetailView(position: position)
                            } label: {
                                PositionRow(position: position, portfolioTotal: totalValueBase)
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
        .background(Theme.background)
        .searchable(text: $searchText, prompt: "Symbol or name")
        .navigationTitle("Holdings")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
    }
}

/// Design holding row: ticker badge, name/quantity, trailing value + weight +
/// colored P&L, all in a card.
private struct PositionRow: View {
    let position: Position
    let portfolioTotal: Decimal

    private var weight: Decimal {
        portfolioTotal > 0 ? position.marketValueBase / portfolioTotal : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            TickerBadge(symbol: position.symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(position.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Text("\(position.quantity.formatted()) × \(position.markPrice.money(position.currency))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(position.marketValueBase.money("CHF"))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(weight.percent1)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textMuted)
                Text(position.unrealizedPnLBase.signedMoney("CHF"))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(position.unrealizedPnLBase >= 0 ? Theme.positive : Theme.negative)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 14)
    }
}
