import Charts
import SwiftData
import SwiftUI

struct DividendsView: View {
    @Environment(SyncStatus.self) private var syncStatus
    @Query(sort: \DividendEvent.date, order: .reverse) private var events: [DividendEvent]

    @State private var csvURL: URL?
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SyncErrorBanner { showSettings = true }
                AsOfBadge()
                headerStats
                if events.isEmpty {
                    ContentUnavailableView(
                        "No dividends yet",
                        systemImage: "banknote",
                        description: Text("Dividend payments appear here after your first sync.")
                    )
                    .frame(minHeight: 200)
                } else {
                    chartCard
                    monthList
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle("Dividends")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Export dividends as CSV")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
        .task(id: events.count) { regenerateCSV() }
    }

    // MARK: - Header

    private var headerStats: some View {
        HStack(spacing: 10) {
            StatCard(
                title: "TTM net income",
                value: DividendMath.ttmNet(events).money("CHF"),
                tint: Theme.accent
            )
            StatCard(
                title: "Withheld (DA-1 reclaimable)",
                value: DividendMath.ytdWithheld(events).money("CHF"),
                subtitle: "YTD withholding tax",
                tint: Theme.warning
            )
        }
    }

    private var chartCard: some View {
        let buckets = DividendMath.monthlyNet(events)
        let currentMonth = buckets.last?.month
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Monthly income")
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Month", bucket.month, unit: .month),
                    y: .value("Net CHF", bucket.net.plotValue),
                    width: .ratio(0.62)
                )
                .foregroundStyle(bucket.month == currentMonth ? Theme.accent : Theme.chartMuted)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.utcStatement.month(.narrow)))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
        }
        .padding(16)
        .card()
    }

    // MARK: - Month sections

    private var monthList: some View {
        ForEach(DividendMath.groupedByMonth(events), id: \.month) { section in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(section.month.monthYear)
                    Spacer()
                    Text(section.groups.reduce(Decimal(0)) { $0 + $1.netBase }.money("CHF"))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(section.groups) { group in
                    PaymentGroupRow(group: group)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - CSV export (DA-1 hand-in)

    private func regenerateCSV() {
        guard !events.isEmpty else {
            csvURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Flexfolio-Dividends.csv")
        do {
            try DividendMath.csv(events).write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
        } catch {
            csvURL = nil
        }
    }
}

/// One payment as a design card row: leading day/month column, symbol with
/// gross − WHT detail, trailing net.
private struct PaymentGroupRow: View {
    let group: DividendMath.PaymentGroup

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 2) {
                Text(group.date.formatted(.utcStatement.day()))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(group.date.formatted(.utcStatement.month(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 38)
            .padding(.top, 8)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.symbol.isEmpty ? "Account" : group.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("gross \(group.grossBase.money("CHF")) − WHT \(group.withheldBase.money("CHF"))")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textMuted)
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                Text(group.netBase.money("CHF"))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .card(cornerRadius: 14)
        }
    }
}
