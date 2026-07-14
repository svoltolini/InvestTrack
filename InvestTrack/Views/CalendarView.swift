import SwiftUI

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var displayedMonth: Date = CalendarView.startOfCurrentMonth()

    private static func startOfCurrentMonth() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: .now)
        return calendar.date(from: components) ?? .now
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthCard
                SectionHeader("Payments this month")
                paymentsList
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle("Calendar")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                monthButton(systemImage: "chevron.left") { shiftMonth(by: -1) }
                monthButton(systemImage: "chevron.right") { shiftMonth(by: 1) }
            }
        }
        .navigationDestination(for: Holding.self) { holding in
            HoldingDetailView(holding: holding)
        }
    }

    private func monthButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.pill)
                )
        }
        .buttonStyle(PressableStyle())
    }

    private func shiftMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = next
            }
        }
    }

    // MARK: - Month grid

    private struct DayCell: Identifiable {
        let id: Int
        let day: Int?
        let isPayday: Bool
    }

    private var dayCells: [DayCell] {
        let calendar = Calendar.current
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        // Monday-first offset of the month's first weekday (1 = Sunday … 7 = Saturday).
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingBlanks = (firstWeekday + 5) % 7
        let paydays = Set(model.events(in: displayedMonth).map { calendar.component(.day, from: $0.date) })

        var cells: [DayCell] = []
        for index in 0..<leadingBlanks {
            cells.append(DayCell(id: -1 - index, day: nil, isPayday: false))
        }
        for day in dayRange {
            cells.append(DayCell(id: day, day: day, isPayday: paydays.contains(day)))
        }
        return cells
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var monthCard: some View {
        let total = model.incomeTotal(for: displayedMonth)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.monthTitle(displayedMonth))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if total > 0 {
                    Text(model.money(total, withCode: true))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(dayCells) { cell in
                    VStack(spacing: 2) {
                        if let day = cell.day {
                            Text(String(day))
                                .font(.system(size: 12, weight: cell.isPayday ? .bold : .regular))
                                .foregroundStyle(cell.isPayday ? Theme.accent : Theme.textPrimary)
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 4, height: 4)
                                .opacity(cell.isPayday ? 1 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(cell.isPayday ? Theme.accentTint : Color.clear)
                    )
                }
            }
        }
        .padding(16)
        .card()
    }

    // MARK: - Payments list

    @ViewBuilder
    private var paymentsList: some View {
        let events = model.events(in: displayedMonth)
        if events.isEmpty {
            Text("No payments this month")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(18)
        } else {
            VStack(spacing: 8) {
                ForEach(events) { event in
                    if let holding = model.holding(for: event.ticker) {
                        NavigationLink(value: holding) {
                            CalendarEventRow(event: event)
                        }
                        .buttonStyle(PressableStyle())
                    } else {
                        CalendarEventRow(event: event)
                    }
                }
            }
        }
    }
}

private struct CalendarEventRow: View {
    @Environment(AppModel.self) private var model
    let event: DividendEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(Format.dayNumber(event.date))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Format.monthAbbrev(event.date))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Text(model.money(event.amount, decimals: 2))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card(cornerRadius: 14)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .environment(AppModel())
}
