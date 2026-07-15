import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showDisconnectConfirmation = false
    @State private var showConfigSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionCard
                preferencesCard
                if model.dataSource == .saxo {
                    saxoSetupButton
                }

                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(isPresented: $showConfigSheet) {
            SaxoConfigSheet(configuration: model.saxoConfiguration)
        }
        .confirmationDialog(
            "Disconnect from Saxo Bank?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your holdings and payout data will no longer sync. You can reconnect anytime.")
        }
    }

    private var saxoSetupButton: some View {
        Button {
            showConfigSheet = true
        } label: {
            HStack {
                Text("Saxo app setup")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(model.saxoConfiguration.environment.displayName) ›")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(PressableStyle())
    }

    private var connectionCard: some View {
        HStack(spacing: 14) {
            Text("SB")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.navy)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Saxo Bank")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.positive)
                        .frame(width: 6, height: 6)
                    Text(connectionStatus)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(Theme.positive)
                }
            }

            Spacer(minLength: 8)

            Button {
                showDisconnectConfirmation = true
            } label: {
                Text("Disconnect")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.negative)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .card()
    }

    private var connectionStatus: String {
        switch model.dataSource {
        case .sample:
            "Connected · account \(model.portfolio.accountLabel)"
        case .saxo:
            "Connected · \(model.portfolio.accountLabel) · \(model.saxoConfiguration.environment.displayName)"
        }
    }

    private var footerText: String {
        switch model.dataSource {
        case .sample:
            "InvestTrack 1.0 · sample data, not connected to a live brokerage"
        case .saxo:
            "InvestTrack 1.0 · Saxo \(model.saxoConfiguration.environment.displayName) · pull down on Income or Portfolio to refresh"
        }
    }

    private var preferencesCard: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            if model.dataSource == .sample {
                SettingMenuRow(title: "Base currency", value: model.baseCurrency.rawValue) {
                    Picker("Base currency", selection: $model.baseCurrency) {
                        ForEach(Currency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                }
            } else {
                HStack {
                    Text("Base currency")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(model.portfolio.currencyCode)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            rowDivider

            SettingMenuRow(title: "Payment reminders", value: model.paymentReminder.rawValue) {
                Picker("Payment reminders", selection: $model.paymentReminder) {
                    ForEach(ReminderOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            rowDivider

            SettingMenuRow(title: "Include withholding tax", value: model.taxDisplay.rawValue) {
                Picker("Include withholding tax", selection: $model.taxDisplay) {
                    ForEach(TaxDisplay.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }
        }
        .card()
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }
}

private struct SettingMenuRow<Options: View>: View {
    let title: String
    let value: String
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            options()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppModel())
}
