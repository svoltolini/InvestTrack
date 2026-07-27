import SwiftUI

/// Inline sync-failure banner — never a full-screen blocker over cached data.
/// Credential-related failures deep-link to Settings on tap.
struct SyncErrorBanner: View {
    @Environment(SyncStatus.self) private var syncStatus
    /// Invoked for credential errors; the hosting screen opens Settings.
    var openSettings: () -> Void

    var body: some View {
        if case .failed(let error) = syncStatus.phase {
            Button {
                if error.isCredentialError {
                    openSettings()
                }
                syncStatus.clearFailure()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.errorDescription ?? "Sync failed.")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                        if error.isCredentialError {
                            Text("Tap to open Settings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
