import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(SyncStatus.self) private var syncStatus
    @Query(sort: \NavPoint.date) private var navPoints: [NavPoint]
    @Query(sort: \CashFlow.date) private var cashFlows: [CashFlow]
    @Query private var positions: [Position]
    @Query private var events: [DividendEvent]
    @Query private var accruals: [DividendAccrual]

    @State private var range: ChartRange = .year
    @State private var scrubDate: Date?
    @State private var showSettings = false

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "1M"
        case quarter = "3M"
        case year = "1Y"
        case all = "All"

        var id: String { rawValue }

        func cutoff(from now: Date) -> Date? {
            switch self {
            case .month: Calendar.flex.date(byAdding: .month, value: -1, to: now)
            case .quarter: Calendar.flex.date(byAdding: .month, value: -3, to: now)
            case .year: Calendar.flex.date(byAdding: .year, value: -1, to: now)
            case .all: nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SyncErrorBanner { showSettings = true }
                AsOfBadge()
                headline
                if visiblePoints.count > 1 {
                    chartCard
                } else if navPoints.isEmpty {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Pull down to sync your IBKR Flex statement.")
                    )
                    .frame(minHeight: 220)
                }
                statRow
                if case .running(let step) = syncStatus.phase {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Flexfolio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable { await syncStatus.manualSync() }
    }

    // MARK: - Headline number

    /// While scrubbing the chart, the headline mirrors the scrubbed day.
    private var headline: some View {
        let scrubbed = scrubbedPoint
        let total = scrubbed?.totalBase ?? latestTotal
        return VStack(alignment: .leading, spacing: 4) {
            Text(total.money("CHF"))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if let scrubbed {
                Text("\(scrubbed.date.dayMonthYear) · invested \(contributions(through: scrubbed.date).money("CHF"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                pnlLine
            }

            if let cash = navPoints.last?.cashBase, cash < 0 {
                Text("Borrowed: \((-cash).money("CHF"))")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var latestTotal: Decimal {
        navPoints.last?.totalBase ?? positions.reduce(0) { $0 + $1.marketValueBase }
    }

    @ViewBuilder
    private var pnlLine: some View {
        let pnl = positions.reduce(Decimal(0)) { $0 + $1.unrealizedPnLBase }
        let cost = positions.reduce(Decimal(0)) { $0 + $1.costBasisBase }
        if !positions.isEmpty, cost > 0 {
            let fraction = pnl / cost
            Text("\(pnl.signedMoney("CHF")) · \(fraction.percent1)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(pnl >= 0 ? .green : .red)
        }
    }

    // MARK: - Chart

    private var visiblePoints: [NavPoint] {
        guard let cutoff = range.cutoff(from: .now) else { return navPoints }
        return navPoints.filter { $0.date >= cutoff }
    }

    private var scrubbedPoint: NavPoint? {
        guard let scrubDate else { return nil }
        return visiblePoints.min {
            abs($0.date.timeIntervalSince(scrubDate)) < abs($1.date.timeIntervalSince(scrubDate))
        }
    }

    /// Running deposits-minus-withdrawals through a date (all-time, so the
    /// gap between the two chart lines is the account's actual growth).
    private func contributions(through date: Date) -> Decimal {
        cashFlows.lazy
            .filter { $0.date <= date }
            .reduce(0) { $0 + $1.amountBase }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            chart
                .frame(height: 220)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("CHF", point.totalBase.plotValue),
                    series: .value("Series", "Value")
                )
                .foregroundStyle(by: .value("Series", "Value"))
                .interpolationMethod(.monotone)
            }
            ForEach(visiblePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("CHF", contributions(through: point.date).plotValue),
                    series: .value("Series", "Net invested")
                )
                .foregroundStyle(by: .value("Series", "Net invested"))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.stepEnd)
            }
            if let scrubbedPoint {
                RuleMark(x: .value("Selected", scrubbedPoint.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartForegroundStyleScale([
            "Value": Color.accentColor,
            "Net invested": Color.secondary,
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $scrubDate)
    }

    // MARK: - Stat cards

    private var statRow: some View {
        HStack(spacing: 10) {
            StatCard(title: "TTM dividends", value: DividendMath.ttmNet(events).money("CHF"), subtitle: "net, CHF")
            StatCard(title: "YTD dividends", value: DividendMath.ytdNet(events).money("CHF"), subtitle: "net, CHF")
            StatCard(title: "Next pay date", value: nextPayLabel)
        }
    }

    private var nextPayLabel: String {
        let today = Calendar.flex.startOfDay(for: .now)
        let next = accruals
            .compactMap(\.payDate)
            .filter { $0 >= today }
            .min()
        return next?.dayMonth ?? "—"
    }
}
