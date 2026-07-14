# InvestTrack

A native iOS dividend tracker built with SwiftUI, implementing the
"Dividend Tracker App" Claude Design prototype for a (mocked) Saxo Bank
account.

<p>
  <em>Income · Portfolio · Calendar · Settings — plus a per-holding detail
  screen with 5-year dividend growth and payment history.</em>
</p>

## Features

- **Connect screen** — mock Saxo Bank OAuth hand-off with a connecting
  state; the session persists across launches.
- **Income** — current-month and projected yearly income, a 12-month
  income bar chart (Swift Charts), upcoming payouts, and a currency
  breakdown bar.
- **Portfolio** — total account value and average yield on cost, with a
  holdings list sortable by income, value, yield, or name.
- **Holding detail** — position stats, next payment, 5-year
  dividend-per-share chart, and payment history.
- **Calendar** — a month grid with payout markers, freely navigable by
  month, with the month's payments listed underneath.
- **Settings** — connection status with disconnect confirmation, base
  currency (CHF/USD/EUR with mock FX conversion), payment reminders, and
  withholding-tax display preferences.

## Tech

- SwiftUI with native elements throughout: `TabView`, `NavigationStack`,
  Swift Charts, `Menu` pickers, `confirmationDialog`.
- `@Observable` (Observation framework) app model, iOS 17+.
- No third-party dependencies.
- All data is a mock portfolio (`MockPortfolio.swift`) mirroring the
  design prototype; a production build would fetch it from the Saxo
  OpenAPI.

## Requirements

- Xcode 16 or newer (the project uses buildable folders).
- iOS 17.0+ deployment target, iPhone (portrait).

## Getting started

Open `InvestTrack.xcodeproj` in Xcode and run the `InvestTrack` scheme on
an iPhone simulator.

## Project structure

```
InvestTrack/
├── InvestTrackApp.swift      // app entry point + root login/app switch
├── AppModel.swift            // @Observable session, preferences, derived data
├── Models.swift              // Holding, DividendEvent, Portfolio, …
├── MockPortfolio.swift       // sample data mirroring the design
├── Theme.swift               // design tokens (colors, card style)
├── Formatters.swift          // Swiss-style number + date formatting
└── Views/
    ├── LoginView.swift
    ├── MainTabView.swift
    ├── IncomeView.swift      // charts, upcoming payouts, currency split
    ├── PortfolioView.swift
    ├── HoldingDetailView.swift
    ├── CalendarView.swift
    ├── SettingsView.swift
    └── Components.swift      // shared section headers, stats, chips
```
