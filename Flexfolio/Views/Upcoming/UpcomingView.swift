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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SyncErrorBanner { showSettings = true }
                AsOfBadge()
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "No announced dividends right now",
                        systemImage: "calendar.badge.clock",
                        description: Text("Dividends your holdings have announced but not yet paid will show up here.")
                    )
                    .frame(minHeight: 300)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("Announced, not yet paid")
                        Spacer()
                        Text(totalNetBase.money("CHF"))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(sorted) { accrual in
                        AccrualRow(accrual: accrual)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle("Upcoming")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
    }
}

/// Card row with a leading pay-date column (ex-date when the pay date is TBA).
private struct AccrualRow: View {
    let accrual: DividendAccrual

    private var leadingDate: Date { accrual.payDate ?? accrual.exDate }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 2) {
                Text(leadingDate.formatted(.utcStatement.day()))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(leadingDate.formatted(.utcStatement.month(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 38)
            .padding(.top, 8)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accrual.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ex \(accrual.exDate.dayMonth)\(payLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(accrual.netAmountBase.money("CHF"))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("projected net")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .card(cornerRadius: 14)
        }
    }

    private var payLabel: String {
        guard let payDate = accrual.payDate else { return " · pay date TBA" }
        return " · pays \(payDate.dayMonth)"
    }
}
