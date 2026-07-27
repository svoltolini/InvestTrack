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
        List {
            Section {
                SyncErrorBanner { showSettings = true }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                AsOfBadge()
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(sorted) { position in
                    NavigationLink {
                        HoldingDetailView(position: position)
                    } label: {
                        PositionRow(position: position, portfolioTotal: totalValueBase)
                    }
                }
            }
        }
        .overlay {
            if positions.isEmpty {
                ContentUnavailableView(
                    "No holdings yet",
                    systemImage: "briefcase",
                    description: Text("Your open positions appear here after the first sync.")
                )
            } else if sorted.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Symbol or name")
        .navigationTitle("Holdings")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
    }
}

private struct PositionRow: View {
    let position: Position
    let portfolioTotal: Decimal

    private var weight: Decimal {
        portfolioTotal > 0 ? position.marketValueBase / portfolioTotal : 0
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(position.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(position.quantity.formatted()) × \(position.markPrice.money(position.currency))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.marketValueBase.money("CHF"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(weight.percent1)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(position.unrealizedPnLBase.signedMoney("CHF"))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(position.unrealizedPnLBase >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 2)
    }
}
