import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case income
        case portfolio
        case calendar
        case settings
    }

    @Environment(AppModel.self) private var model
    @State private var selection: Tab = .portfolio

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                PortfolioView()
            }
            .tabItem { Label("Portfolio", systemImage: "briefcase.fill") }
            .tag(Tab.portfolio)

            NavigationStack {
                IncomeView()
            }
            .tabItem { Label("Income", systemImage: "chart.bar.fill") }
            .tag(Tab.income)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(Tab.calendar)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .alert(
            "Sync problem",
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
}

#Preview {
    MainTabView()
        .environment(AppModel())
        .environment(StockIconStore())
}
