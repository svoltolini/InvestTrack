import SwiftUI

/// Label-over-value stat tile in the design's card treatment.
struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2, reservesSpace: false)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card(cornerRadius: 14)
    }
}
