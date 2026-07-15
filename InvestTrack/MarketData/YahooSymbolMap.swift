import Foundation

/// Maps a Saxo instrument symbol (e.g. "DG:xpar") to a Yahoo Finance symbol
/// (e.g. "DG.PA"). Saxo encodes the exchange after the colon; Yahoo uses a
/// per-exchange suffix (US exchanges have none).
enum YahooSymbolMap {
    /// Saxo exchange code (lowercased, after ':') → Yahoo suffix.
    private static let suffixes: [String: String] = [
        // United States / North America
        "xnas": "", "xnys": "", "arcx": "", "bats": "", "xase": "", "iexg": "",
        "xtse": ".TO", "xtsx": ".V",
        // Euronext
        "xpar": ".PA", "xams": ".AS", "xbru": ".BR", "xlis": ".LS", "xdub": ".IR",
        // United Kingdom
        "xlon": ".L",
        // German-speaking
        "xetr": ".DE", "xfra": ".F", "xswx": ".SW", "xvtx": ".SW", "xwbo": ".VI",
        // Southern Europe
        "xmil": ".MI", "xmad": ".MC", "bvmf": ".SA",
        // Nordics
        "xsto": ".ST", "xhel": ".HE", "xcse": ".CO", "xosl": ".OL", "xice": ".IC",
        // Central / Eastern Europe
        "xwar": ".WA", "xlju": ".LJ",
        // Asia-Pacific
        "xhkg": ".HK", "xtks": ".T", "xasx": ".AX", "xnze": ".NZ", "xses": ".SI",
    ]

    /// Returns a Yahoo symbol, or nil when the exchange is unknown (in which
    /// case the holding simply isn't enriched with market data).
    static func symbol(forSaxo saxoSymbol: String?) -> String? {
        guard let saxoSymbol, !saxoSymbol.isEmpty else { return nil }
        let parts = saxoSymbol.split(separator: ":", maxSplits: 1)
        let base = String(parts.first ?? "").uppercased()
        guard !base.isEmpty else { return nil }

        // No exchange segment → assume a US listing (no suffix).
        guard parts.count > 1 else { return base }

        let exchange = parts[1].lowercased()
        guard let suffix = suffixes[exchange] else { return nil }
        return base + suffix
    }
}
