import SwiftUI

/// The §5 prerequisites checklist, rendered in-app: how the Activity Flex
/// Query must be configured in IBKR Client Portal.
struct FlexQueryHelpView: View {
    var body: some View {
        List {
            Section("1 · Create the token") {
                bullet("In Client Portal open Performance & Reports → Flex Queries.")
                bullet("Under Flex Web Service, generate a token. Set expiry to 1 year.")
                bullet("Paste the token into Flexfolio Settings.")
            }

            Section("2 · Create the Activity Flex Query") {
                bullet("New Activity Flex Query — the number IBKR assigns is the Query ID.")
                bullet("Include these sections: Open Positions (Summary), Cash Transactions, Change in Dividend Accruals, Equity Summary in Base by Report Date, Deposits & Withdrawals.")
                bullet("Cash Transactions types: Dividends, Payment In Lieu of Dividends, Withholding Tax, Deposits/Withdrawals.")
                bullet("Include the transactionID column wherever it is offered.")
            }

            Section("3 · Delivery settings") {
                bullet("Format: XML.")
                bullet("Period: Last 365 Calendar Days.")
                bullet("Date format: yyyy-MM-dd. Time format: HH:mm:ss.")
            }

            Section {
                Text("Flex statements are generated end-of-day. The data is read-only — a Flex token can never place trades or move money.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Flex Query setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.tint)
        }
        .font(.subheadline)
    }
}
