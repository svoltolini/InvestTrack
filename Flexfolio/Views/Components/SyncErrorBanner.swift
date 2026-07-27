import SwiftUI

/// Inline sync-failure banner in the design's amber warning treatment — never
/// a full-screen blocker over cached data. Credential-related failures
/// deep-link to Settings on tap.
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
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                        if error.isCredentialError {
                            Text("Tap to open Settings")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.warning.opacity(0.1))
                )
            }
            .buttonStyle(PressableStyle())
        }
    }
}
