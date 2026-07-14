# InvestTrack — Saxo Bank OpenAPI Implementation Contract (v1)
Target: native iOS (Swift), SIM environment by default. Verified against official Saxo docs 2026-07-14. Anything marked **UNVERIFIED** must not be hardcoded as fact — confirm empirically before relying on it.

---

## 0. Environments & Base URLs

| | SIM (default) | LIVE |
|---|---|---|
| Auth base | `https://sim.logonvalidation.net` | `https://live.logonvalidation.net` |
| Authorize | `https://sim.logonvalidation.net/authorize` | `https://live.logonvalidation.net/authorize` **(UNVERIFIED path — inferred from base; docs only show SIM URLs verbatim)** |
| Token | `https://sim.logonvalidation.net/token` | `https://live.logonvalidation.net/token` **(UNVERIFIED — same caveat)** |
| API gateway | `https://gateway.saxobank.com/sim/openapi` | `https://gateway.saxobank.com/openapi` **(LIVE base UNVERIFIED verbatim in fetched pages, but consistent across all docs)** |

- AppKey/AppSecret are **not shared** between SIM and LIVE — separate app registrations. LIVE app access requires Saxo evaluation/approval (see §5).
- Make environment a single enum injected everywhere: `enum SaxoEnvironment { case sim, live }` with `authBase` and `apiBase` computed properties.

---

## 1. OAuth — Authorization Code Grant with PKCE (this is the flow to implement)

Saxo docs verbatim: *"Native apps should use the Authorization Code Grant (RFC 6749) with Proof Key for Code Exchange (RFC 7636)."* No `client_secret` appears anywhere in the PKCE flow. **Do not embed an AppSecret in the iOS binary.**

**Registration prerequisites** (developer portal, Application Management, https://www.developer.saxo/openapi/appmanagement):
- Grant type is chosen at registration time — the app **must be registered with grant type "pkce"**. A "code"-registered app will not work secretless.
- Redirect URI(s) must be registered. PKCE rule (verbatim): *"redirect URLs cannot be registered with a specific port number... any port will be allowed as long as the domain and path match."* `http://localhost/...` is explicitly allowed.
- **Custom URL schemes (`investtrack://callback`) are UNVERIFIED** — no official doc mentions them; all examples are http(s). Plan A: `ASWebAuthenticationSession` with an https redirect (universal-link style) or a localhost loopback; confirm custom-scheme support with Saxo support (openapi.help.saxo) before shipping. Do not assume it works.

### 1.1 Authorize request
```
GET {authBase}/authorize
  ?response_type=code                 (literal "code", required)
  &client_id={AppKey}
  &state={cryptographically random string}   (validate on callback)
  &redirect_uri={registered URI, URL-encoded}
  &code_challenge={BASE64URL(SHA256(ASCII(code_verifier)))}
  &code_challenge_method=S256         (MUST be S256; "Plain" only by agreement with Saxo)
```
`code_verifier`: random, chars `[A-Za-z0-9-._~]`, length 43–128. Store in memory for the token exchange.
Callback: `{redirect_uri}?code=<authorization_code>&state=<state>`. Reject if state mismatches.

### 1.2 Token exchange
```
POST {authBase}/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&client_id={AppKey}
&code={authorization_code}
&redirect_uri={same as authorize}
&code_verifier={original verifier}
```
No client_secret.

**Token response (exact JSON, decode all five fields):**
```json
{
  "access_token": "eyJhbGc...",
  "expires_in": 1200,
  "token_type": "Bearer",
  "refresh_token": "5e7fa3d2-5e13-4736-80c1-9c3e5cde660b",
  "refresh_token_expires_in": 2400
}
```
```swift
struct TokenResponse: Codable {
  let accessToken: String        // "access_token" — opaque, treat as string
  let expiresIn: Int             // "expires_in" — 1200 s (20 min) on SIM
  let tokenType: String          // "token_type" — "Bearer"
  let refreshToken: String       // "refresh_token" — NEW value on every refresh
  let refreshTokenExpiresIn: Int // "refresh_token_expires_in" — 2400 s (40 min) on SIM
}
```
(Use `.convertFromSnakeCase` or explicit CodingKeys — these are the only snake_case payloads in this contract; all portfolio APIs are PascalCase.)

### 1.3 Refresh
```
POST {authBase}/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token={current refresh_token}
&code_verifier={a code_verifier}       ← Saxo-specific: PKCE refresh includes code_verifier (doc example verbatim)
```
- **UNVERIFIED:** whether `client_id` is required on PKCE refresh (doc example omits it). Include it anyway — harmless and safest.
- Response: same `TokenResponse` shape with a **new refresh_token every time**. Persist the newest pair atomically (Keychain).
- Lifetimes (SIM): access 20 min, refresh 40 min. Refresh chain can be continued indefinitely. **LIVE lifetimes UNVERIFIED — read `expires_in`/`refresh_token_expires_in` from the response, never hardcode 1200/2400.**
- Refresh policy: schedule refresh at ~`expires_in − 120` s; on app foreground, refresh if access token is expired but refresh token is still valid; if refresh token is expired or refresh fails, force interactive re-auth.

### 1.4 API calls
Header on every request: `Authorization: Bearer {access_token}`. That is the only required header for GETs. Optional: `Accept-Encoding: gzip, deflate`. No API-key/app-id header exists.

### 1.5 Dev shortcut
The developer portal issues a **24-hour token, SIM only** — useful for wiring the API layer before OAuth is done. Free SIM signup: https://www.developer.saxo/accounts/sim/signup (simulated ~$100,000 account).

---

## 2. Portfolio rendering — minimal endpoint sequence

All under `{apiBase}/port/v1/`. All field names are **PascalCase** — define explicit `CodingKeys` or a PascalCase key-decoding strategy. All collection endpoints wrap results in `{"Data":[...]}` with optional `"__count"` (Int) and `"__next"` (String URL — if present, more pages exist; **fetch `__next` verbatim**). Paging params: `$top`, `$skip`. Single-object endpoints return a bare object (no `Data` wrapper).

Sequence: **(1) clients/me → (2) accounts/me → (3) balances → (4) netpositions**.

### 2.1 `GET /port/v1/clients/me` — no params
Bare object. Decode:
```swift
struct ClientResponse: Codable {
  let clientKey: String        // "ClientKey"  — REQUIRED input for all later ?ClientKey= params
  let clientId: String         // "ClientId"
  let defaultAccountKey: String// "DefaultAccountKey"
  let defaultAccountId: String // "DefaultAccountId"
  let defaultCurrency: String  // "DefaultCurrency" — client base currency (note: NOT "Currency")
  let currencyDecimals: Int    // "CurrencyDecimals"
  let name: String             // "Name"
  let positionNettingMode: String? // "PositionNettingMode"
}
```
(Other fields exist — `LegalAssetTypes`, `IsMarginTradingAllowed`, etc. — ignore them.)

### 2.2 `GET /port/v1/accounts/me` — no params
`{"Data":[Account]}` — a client can have multiple accounts.
```swift
struct Account: Codable {
  let accountKey: String     // "AccountKey" — opaque key for API calls
  let accountId: String      // "AccountId"  — user-facing id
  let clientKey: String      // "ClientKey"
  let currency: String       // "Currency"   — account currency
  let currencyDecimals: Int  // "CurrencyDecimals"
  let displayName: String?   // "DisplayName" — OPTIONAL, absent unless user renamed the account; fall back to accountId
  let accountType: String    // "AccountType" e.g. "Normal"
  let accountSubType: String?// "AccountSubType"
  let active: Bool           // "Active"
  let creationDate: String   // "CreationDate" — UTC ISO8601
  let legalAssetTypes: [String]? // "LegalAssetTypes"
}
```
Single account: `GET /port/v1/accounts/{AccountKey}`.

### 2.3 Balances
- Whole client in base currency: `GET /port/v1/balances/me` (no params).
- Per account: `GET /port/v1/balances?ClientKey={ck}&AccountKey={ak}` (`ClientKey` required on the non-/me route; `AccountKey` optional; values then in account currency). Optional `FieldGroups=MarginOverview` — not needed for InvestTrack. (Other BalanceFieldGroup values: **UNVERIFIED**.)

Bare object. Decode the subset the app needs:
```swift
struct BalanceResponse: Codable {
  let totalValue: Double            // "TotalValue" — total account value: cash + unrealized positions + unbooked transactions. THIS is the headline portfolio number.
  let cashBalance: Double           // "CashBalance"
  let currency: String              // "Currency"
  let currencyDecimals: Int         // "CurrencyDecimals" — use for formatting
  let nonMarginPositionsValue: Double?   // "NonMarginPositionsValue" — sum of MarketValue of stock/ETF/bond holdings
  let unrealizedPositionsValue: Double?  // "UnrealizedPositionsValue"
  let cashAvailableForTrading: Double?   // "CashAvailableForTrading"
  let transactionsNotBooked: Double?     // "TransactionsNotBooked"
  let openPositionsCount: Int?           // "OpenPositionsCount"
  let calculationReliability: String?    // "CalculationReliability" — "Ok" normally; surface a warning otherwise
}
```
(The full schema has dozens of margin fields — ignore. Trivia hazard: Saxo's own `LineStatus` sub-object misspells `UtilzationPct`; irrelevant here but don't "fix" spellings when decoding.)

### 2.4 Holdings — `GET /port/v1/netpositions` (one row per instrument; use this, not /positions, for the holdings screen)
Exact request Saxo's official sample builds:
```
GET /port/v1/netpositions?FieldGroups=NetPositionBase,NetPositionView,DisplayAndFormat&ClientKey={ck}[&AccountKey={ak}]
```
(`/netpositions/me` variant exists too; on the non-/me route ClientKey is required.) **You must request `DisplayAndFormat` explicitly** — the default omits it and you get no symbol/name.

Response `{"__count":N,"Data":[NetPosition]}`:
```swift
struct NetPositionsEnvelope: Codable {
  let data: [NetPosition]     // "Data"
  let count: Int?             // "__count"
  let next: String?           // "__next"
}
struct NetPosition: Codable {
  let netPositionId: String                 // "NetPositionId" e.g. "EURUSD__FxSpot"
  let netPositionBase: NetPositionBase      // "NetPositionBase"
  let netPositionView: NetPositionView      // "NetPositionView"
  let displayAndFormat: DisplayAndFormat?   // "DisplayAndFormat"
}
struct NetPositionBase: Codable {
  let amount: Double        // "Amount" — signed net quantity/shares (negative = short)
  let assetType: String     // "AssetType" — "Stock","Etf","Bond","FxSpot","CfdOnIndex",...
  let uic: Int              // "Uic" — instrument id; (Uic, AssetType) uniquely identifies an instrument
  let accountId: String?    // "AccountId" (present when account-scoped)
  let canBeClosed: Bool?    // "CanBeClosed"
  let isMarketOpen: Bool?   // "IsMarketOpen"
  let positionsAccount: String? // "PositionsAccount"
  let valueDate: String?    // "ValueDate"
}
struct NetPositionView: Codable {
  let averageOpenPrice: Double?               // "AverageOpenPrice" — avg cost per unit
  let currentPrice: Double?                   // "CurrentPrice"
  let currentPriceType: String?               // "CurrentPriceType" — "Bid"/"Ask"/"LastTraded"
  let currentPriceDelayMinutes: Int?          // "CurrentPriceDelayMinutes"
  let marketValue: Double?                    // "MarketValue" — instrument ccy; populated for non-margin instruments (stocks/ETFs/bonds). FX/margin positions have Exposure instead — make optional.
  let marketValueInBaseCurrency: Double?      // "MarketValueInBaseCurrency"
  let exposure: Double?                       // "Exposure"
  let exposureCurrency: String?               // "ExposureCurrency"
  let profitLossOnTrade: Double?              // "ProfitLossOnTrade" (quote ccy)
  let profitLossOnTradeInBaseCurrency: Double?// "ProfitLossOnTradeInBaseCurrency"
  let instrumentPriceDayPercentChange: Double?// "InstrumentPriceDayPercentChange"
  let positionCount: Int?                     // "PositionCount"
  let status: String?                         // "Status" — "Open" etc.
  let calculationReliability: String?         // "CalculationReliability"
}
struct DisplayAndFormat: Codable {
  let symbol: String        // "Symbol" e.g. "AAPL:xnas"
  let description: String   // "Description" — instrument name
  let currency: String      // "Currency" — instrument currency (== ExposureCurrency)
  let decimals: Int         // "Decimals" — display resolution
  let format: String?       // "Format" — "Normal","Percentage","AllowDecimalPips","Fractions","ModernFractions",...
}
```
**Holdings-row mapping:** symbol=`DisplayAndFormat.Symbol`, name=`.Description`, shares=`NetPositionBase.Amount`, cost basis/share=`NetPositionView.AverageOpenPrice`, current price=`.CurrentPrice`, value=`.MarketValueInBaseCurrency` (base ccy) or `.MarketValue` (instrument ccy), P/L=`.ProfitLossOnTradeInBaseCurrency`, instrument identity=(`Uic`,`AssetType`).

Individual lots (only if you need per-lot detail): `GET /port/v1/positions/me?FieldGroups=PositionBase,PositionView,DisplayAndFormat`. PositionFieldGroup enum: `Costs, DisplayAndFormat, ExchangeInfo, Greeks, PositionBase, PositionIdOnly, PositionView`. Key extra fields: `PositionBase.OpenPrice`, `PositionBase.ExecutionTimeOpen` (UTC), `PositionBase.Status` ("Open","Closed","Closing","PartiallyClosed","Locked"), `PositionId`, `NetPositionId`. Exact sub-fields of `Costs`/`ExchangeInfo` groups: **UNVERIFIED**.

**Make essentially every leaf field Optional in Swift.** Saxo omits fields per asset type (MarketValue absent on FX, DisplayName absent on unnamed accounts, etc.). Only treat `ClientKey`, `AccountKey`, `Uic`, `AssetType`, `Amount` as required.

---

## 3. Dividend data strategy

### 3.0 Big-picture constraints (read first)
1. **Upcoming dividends (`/ca/`)**: entitlement-gated. Docs verbatim: *"This service is subject to special licensing agreements and not generally available to all OpenAPI applications."* Requires "Confidential: Read" permission. **Assume InvestTrack does NOT have this unless Saxo explicitly grants it.** Build the fallback (3.4) as the primary path.
2. **Historical dividends (`/hist/`, `/cs/`)**: real data on **LIVE only**. Support article verbatim: SIM *"does not have back offices functionality... the endpoints on the simulation environment returns mocked data."* In SIM you can test decoding, not amounts.
3. **Saxo has zero dividend fundamentals.** `/ref/v1/instruments/details` exposes **no** DividendYield, frequency, or ex-date fields in any documented FieldGroup. A third-party fundamentals source is mandatory for forward-looking data (see 3.4).

### 3.1 Historical dividends received — PRIMARY: `GET /hist/v1/transactions`
```
GET {apiBase}/hist/v1/transactions
  ?ClientKey={ck}
  &FromDate={yyyy-MM-dd}&ToDate={yyyy-MM-dd}
  [&AccountKeys=...][&TransactionType=...][&AssetTypes=...][&Uics=...]
  [&$top][&$skip]
```
Dividends appear as **"Corporate Action"** transaction type (learn-page example: "Cash Dividend payout from existing holdings", with withholding-tax bookings attached). **UNVERIFIED: the exact query-enum string for TransactionType ("CorporateAction" vs "Corporate Action") and exact `Event`/`AmountType` values for dividends.** Implementation rule: fetch WITHOUT the TransactionType filter first, log distinct `TransactionType`/`Event`/`Bookings[].AmountType` values from one LIVE call, then filter client-side; only push the server-side filter after the string is confirmed.

Decode (exact JSON names from the learn page):
```swift
struct HistTransaction: Codable {
  let accountId: String?         // "AccountId"
  let date: String?              // "Date"
  let valueDate: String?         // "ValueDate"
  let transactionType: String?   // "TransactionType"
  let transactionTypeDisplay: String? // "TransactionTypeDisplay"
  let event: String?             // "Event"
  let eventDisplay: String?      // "EventDisplay"
  let currency: String?          // "Currency"
  let currencyDecimals: Int?     // "CurrencyDecimals"
  let bookedAmount: Double?      // "BookedAmount" — the cash received
  let conversionRate: Double?    // "ConversionRate"
  let bookings: [Booking]?       // "Bookings" — gross amount + withholding tax lines
  struct Booking: Codable {
    let bookingId: String?       // "BookingId" (type UNVERIFIED — decode leniently)
    let amountType: String?      // "AmountType"
    let bookedAmount: Double?    // "BookedAmount"
  }
}
```
Request param `CorporateActionId` exists → each dividend transaction links to a CA event id. Feeds: **payment history**, **monthly income chart** (bucket by `Date` month, sum base-currency amounts), and the realized half of **projected annual income**.

### 3.2 Historical dividends — ALTERNATE: `GET /cs/v1/reports/bookings/{ClientKey}`
Query: `FromDate`, `ToDate`, `AccountKey`, `$top`, `$skip`, `$skiptoken`. Envelope `Data[]/__next/__count/MaxRows`. Permission "Personal: Read".
Filter on **`AmountClass == "OngoingPayment"`** (officially documented: *"ongoing payments from securities such as dividends and bond coupons"*); distinguish dividends from coupons via `AssetType`. Fields: `Amount`, `AmountAccountCurrency`, `AmountClientCurrency`, `Currency`, `Date`, `ValueDate`, `AssetType`, `Uic`, `InstrumentSymbol`, `InstrumentDescription`, `AmountClass`, `AmountSubClass`, `BkAmountType`, `AffectsBalance`. Exact `AmountSubClass`/`BkAmountType` strings for dividends vs withholding tax: **UNVERIFIED**.
Period totals only: `GET /cs/v1/reports/aggregatedAmounts/{ClientKey}/{FromDate}/{ToDate}` — good for a "dividends received this period" number, not a ledger.
Do NOT use the `cr` group (Account Statement etc.) — it returns PDF/XLS only. There is **no** `/cs/v1/reports/dividends` endpoint; Saxo's "Dividends report" is an Excel-add-in template.

### 3.3 Upcoming dividends — ONLY if the app is CA-entitled: `GET /ca/v2/events`
```
GET {apiBase}/ca/v2/events?ClientKey={ck}&EventTypes=DVCA,DVOP,DVSE&FromExDate={today}[&ToPayDate=...]
```
Other params: `AccountKey`, `EventStates` (Approved|Confirmed|Preliminary|Withdrawn), `FromPayDate/ToPayDate`, `$top`, `$skip`. Envelope `{Data, __count, MaxRows}`. Event type codes: `DVCA` cash dividend, `DVSE` stock dividend, `DVOP` cash-or-shares option, `CAPG`, `SHPR`.
**Dates are nested objects, not scalars** — decode `Ex.Date`, `Record.Date`, `Options[].Payment.Date`, `Options[].Deadline.Date` (ISO 8601, e.g. `"2021-02-12T00:00:00Z"`). There is no flat "ExDate".
Key fields: `EventId`, `EventType{Code,Name,Description}`, `EventState`, `Uic`, `AssetType`, `DisplayAndFormat{Symbol,Description,IsinCode}`, `Options[]{OptionType /*"CASH"*/, CashMovements[]{Currency,...}, PayoutBreakdown[]{Amount,Currency,Component{Code,Name}}, IsGross, IsTaxable}`, `Holdings[]{Amount, ElectedAmount}`.
**UNVERIFIED (critical):** no documented field named `Rate`/`GrossAmount`/`DividendPerShare`; the per-share amount appears to be `Options[].PayoutBreakdown[].Amount` but **per-share vs total semantics are unconfirmed** — verify with one entitled LIVE call before computing payout = Amount × Holdings.Amount. SIM behavior of /ca/: **UNVERIFIED**.
ENS alternative (`GET /ens/v1/activities?Activities=CorporateActions&CANotificationTypes=Payment`): documented, "Personal: Read", but **UNVERIFIED whether it bypasses CA licensing** — treat as gated.

### 3.4 Fallback plan per design section (assume no CA entitlement; this is the default architecture)
Saxo gives you: **holdings (Uic, symbol, ISIN, shares, cost)** + **cash dividend payments received (LIVE)**. Everything forward-looking comes from a third-party dividend/fundamentals provider keyed by **ISIN** (get ISIN from `/ref/v1/instruments/details/{Uic}/{AssetType}` → `IsinCode`; **UNVERIFIED whether IsinCode needs a specific FieldGroup** — inspect one response) or by ticker.

| App section | Data source |
|---|---|
| Upcoming payouts | 3rd-party dividend calendar (declared ex/pay dates + per-share amount) × `NetPositionBase.Amount`. Upgrade to `/ca/v2/events` only if entitled. |
| Monthly income chart | LIVE: `/hist/v1/transactions` bucketed by month. SIM/demo: synthesize from 3rd-party historical per-share payments × current shares, labeled "estimated". |
| 5Y dividend-per-share growth | 3rd-party only. Saxo has no per-share dividend history for instruments (its history is *your* cash receipts, which conflate share-count changes). |
| Payment history | LIVE: `/hist/v1/transactions` (primary) or `/cs/.../bookings` filtered `AmountClass=="OngoingPayment"`. Not real on SIM. |
| Projected annual income | Σ over holdings: 3rd-party forward dividend/share × `Amount`, converted to base ccy. |
| Yield on cost | (3rd-party trailing/forward dividend per share) ÷ `NetPositionView.AverageOpenPrice` per holding. All inputs available without CA entitlement. |

---

## 4. Errors, rate limits, sessions

### 4.1 Error body (4xx domain errors)
```swift
struct SaxoError: Codable {
  let errorCode: String              // "ErrorCode" — always present on 400-class bodies
  let message: String                // "Message"   — always present
  let modelState: [String: [String]]?// "ModelState" — validation errors only
}
```
**Exception — 401:** no JSON body is documented; do NOT attempt to decode SaxoError on 401 (**body/WWW-Authenticate presence UNVERIFIED**).

### 4.2 Status-code handling rules
| Code | Meaning | Client action |
|---|---|---|
| 200 | GET success | decode |
| 201 | POST success | decode body |
| 204 | PUT/PATCH/DELETE success | **no body — do not decode JSON** |
| 400 | validation/domain error | decode SaxoError, surface `Message` |
| 401 | token expired/invalid/missing | refresh token → retry once; if refresh fails, interactive re-auth. Never retry-loop. |
| 403 | permission/entitlement (e.g. /ca/ without license) | **not a token problem** — do not refresh; disable the feature, show entitlement message |
| 404 | not found | treat per-endpoint |
| 409 | duplicate identical request within 15 s | for POSTs, set a unique `x-request-id` header to disambiguate legitimate retries |
| 429 | rate limit | back off (4.3) |
| 500/503 | server | exponential backoff retry (GETs only) |

### 4.3 Rate limits (all enforced; SIM and LIVE)
- App: 10,000,000 req/day across all users.
- **Session: 120 req/min per service group** — the one InvestTrack can realistically hit; a full portfolio refresh is ~4 calls, so cap auto-refresh accordingly and never poll faster than ~1 full refresh / 5 s.
- Orders: 1/sec/session (N/A for read-only app).

Headers on every response (and on the 429 itself): `X-RateLimit-AppDay-{Limit,Remaining,Reset}`, `X-RateLimit-Session-{Limit,Remaining,Reset}`, `X-RateLimit-SessionOrders-{...}`. `Reset` = **seconds** until quota reset. On 429: sleep `X-RateLimit-Session-Reset` seconds, then retry. **No Retry-After header documented (UNVERIFIED whether ever sent) — rely on X-RateLimit-*-Reset.**

### 4.4 Session/token rules recap
- Access token 20 min / refresh token 40 min on SIM (read from response, don't hardcode; **LIVE lifetimes UNVERIFIED**). Every refresh rotates the refresh token — persist immediately (Keychain, `kSecAttrAccessibleAfterFirstUnlock` or stricter).
- Background: iOS suspension will outlive the 40-min refresh window; on resume, if refresh token is expired go straight to interactive login. Design the UI for silent re-auth via `ASWebAuthenticationSession` with `prefersEphemeralWebBrowserSession = false` so Saxo's SSO cookie can shorten re-login.

### 4.5 SIM expectations (so the demo doesn't look "broken")
- Fresh SIM user: valid `clients/me`/`accounts/me`, ~$100k cash, **no preloaded positions** (inferred, **UNVERIFIED wording**) — user must place SIM trades to see holdings.
- **Prices:** SIM serves market data for FX only to plain demo accounts; **stocks/ETFs typically return "NoAccess"/missing prices** (hence Optional `CurrentPrice`/`MarketValue`). Linking a LIVE account upgrades SIM to delayed prices; real-time never available on SIM.
- Reporting/back-office endpoints in SIM return **mocked data** (`MockDataId` param exists on /cs/ reports). Whether `/hist/v1/transactions` returns mock vs empty in SIM: **UNVERIFIED**.
- SIM reset: `PUT /port/v1/port/v1/accounts/{AccountKey}/reset` — correct path is `PUT {apiBase}/port/v1/accounts/{AccountKey}/reset` (SIM only; request body schema **UNVERIFIED**).
- SIM API version may be ahead of LIVE — tolerate unknown JSON fields everywhere (never use `Decodable` strictly against unknown keys; that's default-safe in Swift, keep it that way).

### 4.6 Going LIVE (roadmap constraint)
Personal LIVE key requires: funded live Saxo account + tested SIM app + portal request ("Live Apps" → link accounts → "Request LIVE app"); can be auto-approved. Serving *other* Saxo clients requires the third-party evaluation process via openapisupport@saxobank.com and a signed contract. LIVE apps are monitored; noisy/erroring clients get flagged — get 429/refresh handling right before requesting LIVE.

---

## Consolidated UNVERIFIED list (confirm each with one live/Explorer call; do not hardcode)
1. LIVE `/authorize` + `/token` exact paths (inferred from `live.logonvalidation.net` base) and LIVE gateway base verbatim.
2. Custom URL-scheme redirect support for PKCE (assume https/localhost only).
3. `client_id` requirement on PKCE refresh (include it regardless).
4. Real AppKey character format; LIVE token lifetimes.
5. `TransactionType`/`Event`/`AmountType` enum strings for dividends in `/hist/v1/transactions`; SIM behavior of that endpoint.
6. Per-share vs total semantics of `/ca/` `PayoutBreakdown[].Amount`; SIM behavior of `/ca/`; ENS CorporateActions gating.
7. `AmountSubClass`/`BkAmountType` strings for dividends/withholding in `/cs/` bookings.
8. Whether `IsinCode` in `/ref/v1/instruments/details` needs a FieldGroup.
9. Full BalanceFieldGroup enum; `Costs`/`ExchangeInfo` position sub-fields; `WatchlistId` param on /positions.
10. Retry-After on 429; 401 body/headers; SIM auto-reset schedule; reset-endpoint body schema; "no preloaded SIM positions" exact wording.