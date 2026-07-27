import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Environment(SyncStatus.self) private var syncStatus
    @Query private var accruals: [DividendAccrual]
    @State private var showSettings = false

    /// Sorted by pay date, unknown pay dates last (by ex-date within).
    private var sorted: [DividendAccrual] {
        accruals.sorted { lhs, rhs in
            switch (lhs.payDate, rhs.payDate) {
            case let (left?, right?): left < right
            case (nil, .some): false
            case (.some, nil): true
            case (nil, nil): lhs.exDate < rhs.exDate
            }
        }
    }

    private var totalNetBase: Decimal {
        accruals.reduce(0) { $0 + $1.netAmountBase }
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
            if !sorted.isEmpty {
                Section {
                    ForEach(sorted) { accrual in
                        AccrualRow(accrual: accrual)
                    }
                } header: {
                    Text("Announced, not yet paid — \(totalNetBase.money("CHF"))")
                        .monospacedDigit()
                        .textCase(nil) // keep the exact mixed-case wording
                }
            }
        }
        .overlay {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No announced dividends right now",
                    systemImage: "calendar.badge.clock",
                    description: Text("Dividends your holdings have announced but not yet paid will show up here.")
                )
            }
        }
        .navigationTitle("Upcoming")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
    }
}

private struct AccrualRow: View {
    let accrual: DividendAccrual

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(accrual.symbol)
                    .font(.subheadline.weight(.semibold))
                Text("Ex \(accrual.exDate.dayMonth)\(payLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(accrual.netAmountBase.money("CHF"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("projected net")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var payLabel: String {
        guard let payDate = accrual.payDate else { return " · pay date TBA" }
        return " · pays \(payDate.dayMonth)"
    }
}
