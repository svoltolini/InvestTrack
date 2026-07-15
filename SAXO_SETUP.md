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

This is the path for a permanent sign-in, and the only way to reach a **Live**
account.

### 1. Host the redirect (bounce) page

Saxo's portal only accepts **`http(s)` redirect URLs** — it rejects custom
schemes like `investtrack://`. iOS, on the other hand, needs a custom scheme to
hand the login back to the app. The bundled bounce page bridges the two: Saxo
redirects to an `https` page you host, and that page forwards the result to the
app's `investtrack://` scheme.

1. Publish `web/saxo-callback/index.html` at a public `https` URL. Any static
   host works:
   - **GitHub Pages** — enable Pages for this repo, then the file serves at
     e.g. `https://YOUR-USERNAME.github.io/InvestTrack/saxo-callback/`.
   - **Netlify / Vercel / Cloudflare Pages** — drag-and-drop the `web/` folder;
     use the URL they give you (ending in `/saxo-callback/`).
2. Note the final URL — you'll use it verbatim in both steps below.

You do **not** need to add a URL scheme in Xcode — `ASWebAuthenticationSession`
captures the `investtrack://` redirect on its own.

### 2. Register the app

In the developer portal, open **Application Management** and create an app
(**Simulation** to test, **Live** for your real account — see below) with:
- Grant type: **PKCE** (a "Code" app needs a secret, which doesn't belong in an
  iOS binary)
- Redirect URI: the **exact** `https` URL of your bounce page from step 1

### 3. Point the app at it

In `InvestTrack/Saxo/SaxoConfiguration.swift`:
- `appKey` → the generated **AppKey**
- `redirectURI` → the same `https` bounce-page URL
- `environment` → `.simulation` or `.live`

Build and run, then tap **Connect with Saxo Bank** (not the developer-token
sheet). It opens Saxo's real login; tokens are stored in the iOS Keychain and
refresh automatically (SIM sessions: 20-minute access / 40-minute rotating
refresh tokens; Live lifetimes come from the response).

## Going LIVE (your real money account)

Live is the same Option B flow, with a **separate Live app registration**:

1. You need a **funded live Saxo account**.
2. In the portal's **Live Apps** area, link your account and request a **Live**
   application (grant type **PKCE**, redirect URI = your `https` bounce page).
   Personal apps on your own account are usually auto-approved; the full
   evaluation/contract only applies to apps serving *other* Saxo clients.
3. In `SaxoConfiguration.swift`, set `environment: .live` and paste the **Live**
   AppKey (Live and Simulation keys are different).

The bounce page is the same for both environments — only the AppKey and
`environment` change.

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
