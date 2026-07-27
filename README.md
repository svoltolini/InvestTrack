# Flexfolio

Personal iOS dividend & portfolio tracker for a single Interactive Brokers
account, fed by the **IBKR Flex Web Service** (token + query ID, read-only,
end-of-day data). Native SwiftUI + SwiftData + Swift Charts — zero third-party
dependencies. iOS 17+, iPhone only.

Built for a Swiss tax resident: withholding-tax totals and the CSV export are
first-class (the annual **DA-1** reclaim hand-in).

## Highlights
- **Dashboard** — total value in CHF, unrealized P&L, value vs *net invested*
  chart (the gap is your actual growth), TTM/YTD dividends, next pay date, and
  an honest "Borrowed: CHF …" line when the cash balance is negative.
- **Dividends** — monthly net income bars (13 months), gross → WHT → net per
  payment, YTD "Withheld (DA-1 reclaimable)", CSV export via the share sheet.
- **Upcoming** — announced-but-unpaid dividend accruals with ex/pay dates.
- **Holdings** — positions by value with weight and P&L; per-symbol dividend
  history and yield-on-cost.
- **Settings** — token + Query ID (Keychain only), test connection, sync
  limits (manual 1/min, auto-refresh only when >12 h stale), token-expiry
  warning, Flex Query setup checklist, delete-all.

## Setup
1. IBKR Client Portal → Performance & Reports → Flex Queries: create a Flex
   Web Service **token** (1-year expiry) and an Activity Flex Query with:
   Open Positions (Summary), Cash Transactions (Dividends, Payment In Lieu,
   Withholding Tax, Deposits/Withdrawals), Change in Dividend Accruals,
   Equity Summary in Base by Report Date; XML, Last 365 Calendar Days,
   `yyyy-MM-dd`, include `transactionID`.
2. Open `Flexfolio.xcodeproj`, build & run (Xcode 16+).
3. Enter token + Query ID in the onboarding screen. Done.

Secrets live in the Keychain, never in source or UserDefaults. All money math
is `Decimal`. A DEBUG build runs a parser/idempotency self-test at launch and
prints the result to the console.
