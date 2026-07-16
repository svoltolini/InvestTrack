import PhotosUI
import SwiftUI
import UIKit

/// The rounded ticker badge shown for a holding. Displays a user-uploaded icon
/// when present, otherwise the ticker text. Long-press (context menu) lets the
/// user upload or remove a custom icon from their photo library.
struct StockIconBadge: View {
    @Environment(StockIconStore.self) private var iconStore
    let ticker: String
    var size: CGFloat = 40

    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false

    private var cornerRadius: CGFloat { size * 0.3 }

    var body: some View {
        ZStack {
            if let image = iconStore.icon(for: ticker) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(ticker)
                    .font(.system(size: size * 0.275, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 1)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.accentTint)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contextMenu {
            Button {
                showPicker = true
            } label: {
                Label(iconStore.icon(for: ticker) == nil ? "Upload icon" : "Change icon", systemImage: "photo")
            }
            if iconStore.icon(for: ticker) != nil {
                Button(role: .destructive) {
                    iconStore.removeIcon(for: ticker)
                } label: {
                    Label("Remove icon", systemImage: "trash")
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                let image = data.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    if let image { iconStore.setIcon(image, for: ticker) }
                    pickerItem = nil
                }
            }
        }
    }
}
