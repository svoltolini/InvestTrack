import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case income
        case portfolio
        case calendar
        case settings
    }

    @State private var selection: Tab = .income

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                IncomeView()
            }
            .tabItem { Label("Income", systemImage: "chart.bar.fill") }
            .tag(Tab.income)

            NavigationStack {
                PortfolioView()
            }
            .tabItem { Label("Portfolio", systemImage: "briefcase.fill") }
            .tag(Tab.portfolio)

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
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
}
