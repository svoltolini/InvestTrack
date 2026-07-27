import Foundation
import Observation
import SwiftData

/// Observable sync state + the app's rate discipline: manual refresh at most
/// once per 60 s, foreground auto-refresh only when the last success is
/// older than 12 h. IBKR Flex is end-of-day data — syncing more often than a
/// few times a day gains nothing.
@MainActor
@Observable
final class SyncStatus {
    enum Phase: Equatable {
        case idle
        case running(String)
        case failed(FlexError)
        case done(Date)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastAttempt: Date?

    private let engine: SyncEngine
    static let manualCooldown: TimeInterval = 60
    static let autoRefreshAge: TimeInterval = 12 * 3600

    init(container: ModelContainer) {
        engine = SyncEngine(container: container)
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Seconds until the next manual refresh is allowed (0 = allowed now).
    func cooldownRemaining(at now: Date = .now) -> Int {
        guard let lastAttempt else { return 0 }
        let remaining = Self.manualCooldown - now.timeIntervalSince(lastAttempt)
        return max(0, Int(remaining.rounded(.up)))
    }

    /// Manual refresh (button or pull-to-refresh). Silently ignored while a
    /// sync is running or the 60 s cooldown is active.
    func manualSync() async {
        guard !isRunning, cooldownRemaining() == 0 else { return }
        await run()
    }

    /// On app foreground: sync only when the last successful sync is stale.
    /// `latestSuccess` comes from the caller's SwiftData query.
    func foregroundSyncIfStale(latestSuccess: Date?) async {
        guard KeychainStore.hasCredentials else { return }
        let stale = latestSuccess.map { Date.now.timeIntervalSince($0) > Self.autoRefreshAge } ?? true
        guard stale, !isRunning else { return }
        await run()
    }

    func clearFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }

    private func run() async {
        lastAttempt = .now
        phase = .running("Starting…")
        do {
            _ = try await engine.sync { [weak self] step in
                Task { @MainActor in
                    self?.phase = .running(step)
                }
            }
            phase = .done(.now)
        } catch let error as FlexError {
            phase = .failed(error)
        } catch {
            phase = .failed(.network(error.localizedDescription))
        }
    }
}
