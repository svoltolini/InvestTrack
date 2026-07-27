import SwiftUI

extension Color {
    /// Creates an sRGB color from a 24-bit hex value, e.g. `Color(hex: 0x3D6EE0)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Design tokens from the Dividend Tracker design file (the same system the
/// previous Saxo app used). The design is light-pinned — the app forces light
/// mode at the root.
enum Theme {
    static let background = Color(hex: 0xFBFAF8)
    static let cardBorder = Color(hex: 0xECEBE6)
    static let divider = Color(hex: 0xF3F2EE)
    static let pill = Color(hex: 0xF0EFEB)

    static let textPrimary = Color(hex: 0x1F2328)
    static let textSecondary = Color(hex: 0x5C636B)
    static let textMuted = Color(hex: 0x8A8F96)
    static let textFaint = Color(hex: 0xA3A8AE)

    static let accent = Color(hex: 0x3D6EE0)
    static let accentMid = Color(hex: 0x7FA4EC)
    static let accentPale = Color(hex: 0xCDD9F4)
    static let accentTint = Color(hex: 0xEEF2FB)
    static let chartMuted = Color(hex: 0xDFE6F3)

    static let navy = Color(hex: 0x0F2F6D)
    static let positive = Color(hex: 0x3D9E6B)
    static let negative = Color(hex: 0xC05252)
    /// Amber — borrowed cash (margin balance) and warnings.
    static let warning = Color(hex: 0xE0863D)
}

extension View {
    /// White card with the design's hairline border and rounded corners.
    func card(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

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

/// Dims the label while pressed, matching the design's press feedback.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Rounded ticker badge (the design's stock icon placeholder).
struct TickerBadge: View {
    let symbol: String
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.accentTint)
            .frame(width: size, height: size)
            .overlay {
                Text(symbol.prefix(2).uppercased())
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
    }
}
