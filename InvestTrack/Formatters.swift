import Foundation

extension Calendar {
    /// Fixed Gregorian calendar so the mock dataset and all date math match
    /// the design on every device configuration (e.g. a Buddhist or Japanese
    /// device calendar would otherwise shift the sample dates).
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
}

/// Number and date formatting helpers.
///
/// Amounts use the Swiss apostrophe grouping style from the design (e.g. `118'440`),
/// and all copy is pinned to the design's fixed English regardless of device locale.
enum Format {
    private static let wholeNumber = makeNumberFormatter(decimals: 0)
    private static let twoDecimals = makeNumberFormatter(decimals: 2)

    private static func makeNumberFormatter(decimals: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "'"
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter
    }

    static func amount(_ value: Double, decimals: Int = 0) -> String {
        let formatter = decimals == 0 ? wholeNumber : twoDecimals
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(decimals)f", value)
    }

    /// Formats a fraction as a percentage, e.g. `0.082` → `"8.2%"`.
    static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", fraction * 100)
    }

    // MARK: - Dates

    private static let dayMonthFormatter = makeDateFormatter("d MMM")
    private static let monthYearFormatter = makeDateFormatter("MMM yyyy")
    private static let fullDateFormatter = makeDateFormatter("d MMM yyyy")
    private static let monthTitleFormatter = makeDateFormatter("MMMM yyyy")
    private static let dayNumberFormatter = makeDateFormatter("d")
    private static let monthAbbrevFormatter = makeDateFormatter("MMM")

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .gregorian
        formatter.dateFormat = format
        return formatter
    }

    /// "8 Aug"
    static func dayMonth(_ date: Date) -> String { dayMonthFormatter.string(from: date) }
    /// "Apr 2027"
    static func monthYear(_ date: Date) -> String { monthYearFormatter.string(from: date) }
    /// "8 May 2026"
    static func fullDate(_ date: Date) -> String { fullDateFormatter.string(from: date) }
    /// "July 2026"
    static func monthTitle(_ date: Date) -> String { monthTitleFormatter.string(from: date) }
    /// "8"
    static func dayNumber(_ date: Date) -> String { dayNumberFormatter.string(from: date) }
    /// "AUG"
    static func monthAbbrev(_ date: Date) -> String { monthAbbrevFormatter.string(from: date).uppercased() }
}
