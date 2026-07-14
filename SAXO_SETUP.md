# Connecting InvestTrack to your Saxo Bank account

InvestTrack talks to the [Saxo Bank OpenAPI](https://www.developer.saxo). There
are three ways to run the app, from zero setup to a full sign-in flow:

| Mode | Setup needed | Data |
|---|---|---|
| **Sample data** | none | The bundled demo portfolio from the design prototype |
| **Developer token** | free developer login | Your real **Simulation** account, valid for 24h |
| **OAuth (PKCE)** | register an app once | Your account with automatic sign-in and token refresh |

## Option A — Developer token (fastest, no registration)

1. Create a free developer account at <https://www.developer.saxo/accounts/sim/signup>.
   You get a Simulation account with ~100'000 in demo cash.
2. Log in to the portal and copy the **24-hour token** it offers.
3. In the app, tap **Use a developer token**, paste it, and connect.

Notes:
- The token expires after 24 hours — just paste a fresh one.
- A brand-new Simulation account has cash but **no positions**. Place a few
  demo trades on Saxo's SIM platform ([SaxoTraderGO](https://www.saxotrader.com/sim/))
  to see holdings in the app.

## Option B — Full OAuth sign-in (register once)

1. In the developer portal, open **Application Management** and create a new
   app on the **Simulation** environment with:
   - Grant type: **PKCE** (required — a "Code" app won't work without a secret,
     and secrets don't belong in an iOS binary)
   - Redirect URI: `investtrack://saxo-callback`
     — Saxo's docs only show http(s) examples for redirect URIs; if the portal
     rejects a custom scheme, ask Saxo support (openapi.help.saxo) to enable it,
     or use Option A meanwhile.
2. Copy the generated **AppKey** into
   `InvestTrack/Saxo/SaxoConfiguration.swift` → `appKey`.
3. Build and run. **Connect with Saxo Bank** now opens Saxo's real login page;
   tokens are stored in the iOS Keychain and refresh automatically
   (SIM sessions: 20-minute access / 40-minute rotating refresh tokens).

## Going LIVE (your real money account)

1. Register a **Live** app in the portal (separate AppKey; requires a funded
   Saxo account and Saxo's approval — personal apps are often auto-approved).
2. In `SaxoConfiguration.swift`, set `environment: .live` and the live AppKey.

## What data the app can and cannot get from Saxo

Verified against Saxo's docs (see `docs/saxo-openapi-contract.md`):

- ✅ **Accounts, cash balance, total value** — `/port/v1/clients`, `/accounts`, `/balances`
- ✅ **Positions** (shares, market value, currency, cost price) — `/port/v1/netpositions`
- ⚠️ **Dividends received** — `/cs/v1/reports/bookings` ("OngoingPayment") and
  `/hist/v1/transactions`; real data on **LIVE only** (SIM returns mocked or
  empty back-office data). Feeds the monthly income chart, payment history and
  the trailing-12-month "projected" income.
- ⚠️ **Upcoming dividends** — `/ca/v2/events` requires a special entitlement
  most apps don't have; without it the Upcoming list stays empty.
- ❌ **Per-share dividend history / yields** — not in the OpenAPI at all. The
  5Y growth chart and yield-on-cost show only for the sample dataset (a
  third-party fundamentals feed would be needed for real instruments).

On SIM, stock/ETF prices may also be unavailable (Saxo only serves FX prices to
plain demo accounts), in which case position values show as 0 while balances
remain correct.
