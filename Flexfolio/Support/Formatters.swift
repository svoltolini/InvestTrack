import Foundation

// MARK: - Money & percent display

extension Decimal {
    /// Currency display via FormatStyle — grouping/decimal separators come
    /// from the device locale (Swiss grouping included), never hand-formatted.
    func money(_ code: String) -> String {
        formatted(.currency(code: code))
    }

    /// Currency with an explicit leading sign, for P&L (`+CHF 1'234.00`).
    func signedMoney(_ code: String) -> String {
        formatted(.currency(code: code).sign(strategy: .always(showZero: false)))
    }

    /// Percentage with one decimal, from a fraction (0.032 → "3.2%").
    var percent1: String {
        formatted(.percent.precision(.fractionLength(1)))
    }

    /// Display-only bridge for Swift Charts, which plots `Double`.
    /// Never used for money math.
    var plotValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Dates

extension Date {
    /// "24 Jul 2026" (locale-ordered), the app-wide date style.
    var dayMonthYear: String {
        formatted(.dateTime.day().month().year())
    }

    /// "24 Jul" for compact rows.
    var dayMonth: String {
        formatted(.dateTime.day().month())
    }

    /// "Jul 2026" for month section headers.
    var monthYear: String {
        formatted(.dateTime.month(.wide).year())
    }

    /// "2 hours ago" style, for sync freshness lines.
    var relativeToNow: String {
        formatted(.relative(presentation: .named))
    }
}

extension Calendar {
    /// Fixed Gregorian/UTC calendar for statement math, so month bucketing and
    /// keys are stable regardless of the device calendar or timezone.
    static let flex: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

// MARK: - Flex statement value parsing

/// Tolerant parsers for Flex attribute strings. Fixed en_US_POSIX locale;
/// money parses straight to `Decimal` (never through Double).
enum FlexValue {
    static func decimal(_ raw: String?) -> Decimal? {
        guard let raw, !raw.isEmpty else { return nil }
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    private static let dashed = makeDateFormatter("yyyy-MM-dd")
    private static let compact = makeDateFormatter("yyyyMMdd")

    /// Accepts `yyyy-MM-dd` or `yyyyMMdd`; tolerates a `;HH:mm:ss`,
    /// `,HH:mm:ss`, or ` HH:mm:ss` time suffix by using the date part only.
    static func date(_ raw: String?) -> Date? {
        guard var text = raw, !text.isEmpty else { return nil }
        for separator in [";", ",", " "] {
            if let range = text.range(of: separator) {
                text = String(text[..<range.lowerBound])
                break
            }
        }
        return dashed.date(from: text) ?? compact.date(from: text)
    }

    /// Canonical `yyyy-MM-dd` form of a date, for composite keys.
    static func dateKey(_ date: Date) -> String {
        dashed.string(from: date)
    }
}
