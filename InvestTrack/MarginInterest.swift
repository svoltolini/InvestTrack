import Foundation

/// Estimates Saxo Lombard / margin loan interest on a tiered (blended) scale:
/// each tranche of the borrowed amount is charged at its tier's annual rate —
/// 2% on the first 250,000, 1.5% from 250,000 to 1,000,000, 1% above — in the
/// account's base currency.
enum MarginInterest {
    private static let tiers: [(upperBound: Double, annualRate: Double)] = [
        (250_000, 0.020),
        (1_000_000, 0.015),
        (.infinity, 0.010),
    ]

    /// Annual interest for a positive loan amount.
    static func annualInterest(loan: Double) -> Double {
        guard loan > 0 else { return 0 }
        var lowerBound = 0.0
        var total = 0.0
        for tier in tiers {
            let bandAmount = min(loan, tier.upperBound) - lowerBound
            guard bandAmount > 0 else { break }
            total += bandAmount * tier.annualRate
            lowerBound = tier.upperBound
            if loan <= tier.upperBound { break }
        }
        return total
    }

    /// Monthly interest for a positive loan amount.
    static func monthlyInterest(loan: Double) -> Double {
        annualInterest(loan: loan) / 12
    }

    /// Blended effective annual rate (e.g. 0.018 == 1.8 %).
    static func effectiveRate(loan: Double) -> Double {
        guard loan > 0 else { return 0 }
        return annualInterest(loan: loan) / loan
    }
}
