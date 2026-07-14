import Foundation

extension Portfolio {
    /// Sample data mirroring the InvestTrack design prototype — a mocked,
    /// read-only Saxo Bank account. A production build would fetch this from
    /// the Saxo OpenAPI instead.
    static let sample: Portfolio = {
        func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = dayOfMonth
            components.hour = 12
            return Calendar.current.date(from: components) ?? .now
        }

        func growth(_ perShare: [Double]) -> [DividendPoint] {
            perShare.enumerated().map { DividendPoint(year: 2022 + $0.offset, dividendPerShare: $0.element) }
        }

        let holdings: [Holding] = [
            Holding(
                ticker: "VWRL",
                name: "Vanguard FTSE All-World",
                subtitle: "ETF · 310 units · quarterly",
                payoutDescription: "Quarterly · EUR",
                shares: 310,
                positionValue: 42_160,
                annualIncome: 912,
                yieldOnCost: 0.020,
                nextPayment: NextPayment(
                    date: day(2026, 8, 8),
                    amount: 228.10,
                    detail: "Q2 distribution · 310 units",
                    monthPrecision: false
                ),
                dividendGrowth: growth([1.90, 2.10, 2.30, 2.60, 2.94]),
                paymentHistory: [
                    PastPayment(date: day(2026, 5, 8), amount: 224.30),
                    PastPayment(date: day(2026, 2, 7), amount: 219.80),
                    PastPayment(date: day(2025, 11, 8), amount: 208.40),
                    PastPayment(date: day(2025, 8, 9), amount: 202.10),
                ]
            ),
            Holding(
                ticker: "ZURN",
                name: "Zurich Insurance",
                subtitle: "Stock · 30 shares · annual",
                payoutDescription: "Annual · CHF",
                shares: 30,
                positionValue: 16_890,
                annualIncome: 798,
                yieldOnCost: 0.054,
                nextPayment: NextPayment(
                    date: day(2027, 4, 15),
                    amount: 798.00,
                    detail: "Annual dividend · CHF 26.60/sh",
                    monthPrecision: true
                ),
                dividendGrowth: growth([20.00, 22.00, 24.00, 26.00, 26.60]),
                paymentHistory: [
                    PastPayment(date: day(2026, 4, 9), amount: 798.00),
                    PastPayment(date: day(2025, 4, 10), amount: 780.00),
                    PastPayment(date: day(2024, 4, 11), amount: 720.00),
                ]
            ),
            Holding(
                ticker: "O",
                name: "Realty Income",
                subtitle: "REIT · 240 shares · monthly",
                payoutDescription: "Monthly · USD",
                shares: 240,
                positionValue: 11_480,
                annualIncome: 642,
                yieldOnCost: 0.056,
                nextPayment: NextPayment(
                    date: day(2026, 7, 31),
                    amount: 53.20,
                    detail: "Monthly · USD 0.2635/sh",
                    monthPrecision: false
                ),
                dividendGrowth: growth([2.83, 2.98, 3.07, 3.13, 3.16]),
                paymentHistory: [
                    PastPayment(date: day(2026, 6, 30), amount: 53.10),
                    PastPayment(date: day(2026, 5, 29), amount: 52.80),
                    PastPayment(date: day(2026, 4, 30), amount: 53.40),
                    PastPayment(date: day(2026, 3, 31), amount: 52.95),
                ]
            ),
            Holding(
                ticker: "AAPL",
                name: "Apple Inc.",
                subtitle: "Stock · 85 shares · quarterly",
                payoutDescription: "Quarterly · USD",
                shares: 85,
                positionValue: 15_980,
                annualIncome: 661,
                yieldOnCost: 0.009,
                nextPayment: NextPayment(
                    date: day(2026, 8, 14),
                    amount: 55.05,
                    detail: "Quarterly · USD 0.26/sh",
                    monthPrecision: false
                ),
                dividendGrowth: growth([0.88, 0.92, 0.96, 1.00, 1.04]),
                paymentHistory: [
                    PastPayment(date: day(2026, 5, 15), amount: 54.80),
                    PastPayment(date: day(2026, 2, 13), amount: 54.20),
                    PastPayment(date: day(2025, 11, 14), amount: 53.60),
                ]
            ),
            Holding(
                ticker: "NESN",
                name: "Nestlé SA",
                subtitle: "Stock · 120 shares · annual",
                payoutDescription: "Annual + interim · CHF",
                shares: 120,
                positionValue: 10_330,
                annualIncome: 624,
                yieldOnCost: 0.031,
                nextPayment: NextPayment(
                    date: day(2026, 7, 24),
                    amount: 312.00,
                    detail: "Interim · CHF 2.60/sh",
                    monthPrecision: false
                ),
                dividendGrowth: growth([2.75, 2.80, 2.95, 3.00, 3.05]),
                paymentHistory: [
                    PastPayment(date: day(2026, 4, 24), amount: 312.00),
                    PastPayment(date: day(2025, 4, 25), amount: 366.00),
                    PastPayment(date: day(2024, 4, 26), amount: 360.00),
                ]
            ),
            Holding(
                ticker: "ROG",
                name: "Roche Holding",
                subtitle: "Stock · 60 shares · annual",
                payoutDescription: "Annual · CHF",
                shares: 60,
                positionValue: 17_600,
                annualIncome: 581,
                yieldOnCost: 0.036,
                nextPayment: NextPayment(
                    date: day(2027, 3, 15),
                    amount: 581.40,
                    detail: "Annual · CHF 9.69/sh",
                    monthPrecision: true
                ),
                dividendGrowth: growth([9.10, 9.30, 9.50, 9.60, 9.69]),
                paymentHistory: [
                    PastPayment(date: day(2026, 3, 18), amount: 581.40),
                    PastPayment(date: day(2025, 3, 19), amount: 576.00),
                    PastPayment(date: day(2024, 3, 20), amount: 570.00),
                ]
            ),
        ]

        let scheduledEvents: [DividendEvent] = [
            DividendEvent(date: day(2026, 7, 15), title: "Cash sweep interest", detail: "Saxo CHF account", amount: 12.40, ticker: nil),
            DividendEvent(date: day(2026, 7, 24), title: "Nestlé", detail: "Interim · CHF 2.60/sh", amount: 312.00, ticker: "NESN"),
            DividendEvent(date: day(2026, 7, 31), title: "Realty Income", detail: "Monthly · USD", amount: 53.20, ticker: "O"),
            DividendEvent(date: day(2026, 8, 8), title: "VWRL ETF", detail: "Q2 distribution", amount: 228.10, ticker: "VWRL"),
            DividendEvent(date: day(2026, 8, 14), title: "Apple", detail: "Quarterly · USD", amount: 55.05, ticker: "AAPL"),
            DividendEvent(date: day(2026, 8, 31), title: "Realty Income", detail: "Monthly · USD", amount: 53.20, ticker: "O"),
            DividendEvent(date: day(2026, 9, 30), title: "Realty Income", detail: "Monthly · USD", amount: 53.20, ticker: "O"),
        ]

        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthAmounts: [Double] = [210, 180, 390, 590, 240, 486, 486, 336, 53, 290, 230, 720]
        let monthlyIncome = monthAmounts.enumerated().map { index, amount in
            MonthlyIncome(month: index + 1, name: monthNames[index], amount: amount)
        }

        return Portfolio(
            accountLabel: "78'201-CHF",
            cashBalance: 4_000,
            averageYieldOnCost: 0.0382,
            incomeGrowthYoY: 0.082,
            monthlyIncomeYear: 2026,
            monthlyIncome: monthlyIncome,
            currencyBreakdown: [
                CurrencySlice(code: "CHF", share: 0.62),
                CurrencySlice(code: "USD", share: 0.28),
                CurrencySlice(code: "EUR", share: 0.10),
            ],
            holdings: holdings,
            scheduledEvents: scheduledEvents
        )
    }()
}
