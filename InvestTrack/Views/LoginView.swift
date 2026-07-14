import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text("D")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 10)

                Text("Track every\ndividend.")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(2)

                Text("Connect your Saxo Bank account to see income, payout dates and growth across all your holdings.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            footer
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var footer: some View {
        if model.phase == .connecting {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                Text("Connecting to Saxo…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .card()
        } else {
            VStack(spacing: 12) {
                Button {
                    model.connect()
                } label: {
                    Text("Connect with Saxo Bank")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.navy)
                        )
                }
                .buttonStyle(PressableStyle())

                Text("Read-only access via Saxo OpenAPI · you can disconnect anytime")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
}
