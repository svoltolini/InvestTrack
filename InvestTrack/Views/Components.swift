import SwiftUI

/// Uppercase section label, e.g. "UPCOMING".
struct SectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .kerning(0.5)
            .font(.system(size: 12, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textMuted)
    }
}

/// Label-over-value stat, e.g. "Projected 2026 / 4'218".
struct StatBlock: View {
    let label: String
    let value: String
    var size: CGFloat = 24
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

/// Dims the label while pressed, matching the design's press feedback.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small capsule chip used for toolbar menus ("CHF ▾", "By income ▾").
struct PillChipLabel: View {
    let text: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.pill))
    }
}

/// Toolbar menu for switching the display currency.
struct CurrencyMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Base currency", selection: $model.baseCurrency) {
                ForEach(Currency.allCases) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
        } label: {
            PillChipLabel(text: model.baseCurrency.rawValue)
        }
    }
}
