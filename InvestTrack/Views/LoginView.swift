import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var showTokenSheet = false

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
        .sheet(isPresented: $showTokenSheet) {
            DeveloperTokenSheet()
        }
        .alert(
            "Couldn't connect to Saxo",
            isPresented: Binding(
                get: { model.syncError != nil },
                set: { if !$0 { model.clearSyncError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.syncError ?? "")
        }
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
                    if model.saxoConfiguration.isConfigured {
                        model.connectSaxo()
                    } else {
                        showTokenSheet = true
                    }
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

                HStack(spacing: 18) {
                    Button("Use a developer token") {
                        showTokenSheet = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                    Button("Browse sample data") {
                        model.connectSample()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 2)
            }
        }
    }
}

/// Connects to the user's Saxo Simulation account with a 24-hour token from
/// the developer portal — the zero-setup path that needs no app registration.
private struct DeveloperTokenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Log in at developer.saxo (free signup) and copy the 24-hour access token from the portal, then paste it here. This connects the app to your Saxo Simulation account — no app registration needed.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)

                    TextField("Paste access token", text: $token, axis: .vertical)
                        .lineLimit(4...8)
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .card(cornerRadius: 12)

                    Button {
                        model.connectSaxo(developerToken: trimmedToken)
                        dismiss()
                    } label: {
                        Text("Connect to Simulation")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.navy)
                            )
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(trimmedToken.isEmpty)
                    .opacity(trimmedToken.isEmpty ? 0.5 : 1)

                    Text("Tokens from the portal expire after 24 hours. For a permanent sign-in flow, register a PKCE app and set its key in SaxoConfiguration.swift — see SAXO_SETUP.md.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .lineSpacing(2)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Developer token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
}
