import SwiftData
import SwiftUI

@main
struct FlexfolioApp: App {
    private let container: ModelContainer
    @State private var syncStatus: SyncStatus
    @State private var settings = AppSettings()

    init() {
        let schema = Schema([
            Position.self,
            DividendEvent.self,
            DividendAccrual.self,
            NavPoint.self,
            CashFlow.self,
            SyncRecord.self,
        ])
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        _syncStatus = State(initialValue: SyncStatus(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .environment(syncStatus)
        .environment(settings)
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncStatus.self) private var syncStatus
    @Environment(\.scenePhase) private var scenePhase
    @Query(AsOfBadge.latestSuccessDescriptor) private var latestSuccess: [SyncRecord]

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { DividendsView() }
                .tabItem { Label("Dividends", systemImage: "banknote") }
            NavigationStack { UpcomingView() }
                .tabItem { Label("Upcoming", systemImage: "calendar.badge.clock") }
            NavigationStack { HoldingsView() }
                .tabItem { Label("Holdings", systemImage: "briefcase") }
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            SettingsView(isOnboarding: true)
                .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await syncStatus.foregroundSyncIfStale(latestSuccess: latestSuccess.first?.timestamp)
            }
        }
        #if DEBUG
        .task {
            await DebugSelfTest.runOnce()
        }
        #endif
    }

    /// First launch: Settings appears full-screen until credentials exist.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !settings.hasCredentials },
            set: { _ in } // Dismissal happens by saving credentials.
        )
    }
}
