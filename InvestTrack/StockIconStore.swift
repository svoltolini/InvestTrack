import Observation
import UIKit

/// Stores user-supplied stock icons on the device, keyed by ticker. Icons are
/// persisted as PNGs under Application Support and preloaded at launch so the
/// UI can read them synchronously during view updates.
@MainActor
@Observable
final class StockIconStore {
    private var images: [String: UIImage] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("StockIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preload()
    }

    func icon(for ticker: String) -> UIImage? {
        images[key(for: ticker)]
    }

    func setIcon(_ image: UIImage, for ticker: String) {
        let key = key(for: ticker)
        images[key] = image
        if let data = image.pngData() {
            try? data.write(to: directory.appendingPathComponent("\(key).png"))
        }
    }

    func removeIcon(for ticker: String) {
        let key = key(for: ticker)
        images[key] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).png"))
    }

    // MARK: - Private

    private func preload() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "png" {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                images[file.deletingPathExtension().lastPathComponent] = image
            }
        }
    }

    /// A filesystem-safe key for a ticker (tickers can contain "·", ":", etc.).
    private func key(for ticker: String) -> String {
        let allowed = ticker.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        return String(allowed)
    }
}
