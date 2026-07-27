import Charts
import SwiftData
import SwiftUI

struct DividendsView: View {
    @Environment(SyncStatus.self) private var syncStatus
    @Query(sort: \DividendEvent.date, order: .reverse) private var events: [DividendEvent]

    @State private var csvURL: URL?
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                SyncErrorBanner { showSettings = true }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                AsOfBadge()
                    .listRowBackground(Color.clear)
                headerStats
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if events.isEmpty {
                    ContentUnavailableView(
                        "No dividends yet",
                        systemImage: "banknote",
                        description: Text("Dividend payments appear here after your first sync.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    monthlyChart
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            }

            ForEach(monthSections, id: \.month) { section in
                Section {
                    ForEach(section.groups) { group in
                        PaymentGroupRow(group: group)
                    }
                } header: {
                    Text(section.month.monthYear)
                } footer: {
                    Text("Month net: \(section.groups.reduce(Decimal(0)) { $0 + $1.netBase }.money("CHF"))")
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Dividends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
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

    private var monthSections: [(month: Date, groups: [DividendMath.PaymentGroup])] {
        DividendMath.groupedByMonth(events)
    }

    // MARK: - Header

    private var headerStats: some View {
        HStack(spacing: 10) {
            StatCard(
                title: "TTM net income",
                value: DividendMath.ttmNet(events).money("CHF")
            )
            StatCard(
                title: "Withheld (DA-1 reclaimable)",
                value: DividendMath.ytdWithheld(events).money("CHF"),
                subtitle: "YTD withholding tax",
                tint: .orange
            )
        }
    }

    private var monthlyChart: some View {
        Chart(DividendMath.monthlyNet(events)) { bucket in
            BarMark(
                x: .value("Month", bucket.month, unit: .month),
                y: .value("Net CHF", bucket.net.plotValue)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisValueLabel(format: Date.FormatStyle.utcStatement.month(.narrow), centered: true)
            }
        }
        .frame(height: 140)
        .padding(.vertical, 6)
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

/// One payment: symbol and date, with gross → WHT → net trailing.
private struct PaymentGroupRow: View {
    let group: DividendMath.PaymentGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.symbol.isEmpty ? "Account" : group.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(group.date.dayMonthYear)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(group.netBase.money("CHF"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("gross \(group.grossBase.money("CHF")) − WHT \(group.withheldBase.money("CHF"))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
