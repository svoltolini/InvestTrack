import SwiftData
import SwiftUI

/// "Data through 24 Jul 2026 · synced 2 hours ago" — IBKR Flex is end-of-day
/// data, and every screen says so honestly. Reads the latest NavPoint and the
/// latest successful SyncRecord itself, so screens just drop it in.
struct AsOfBadge: View {
    @Query(AsOfBadge.latestNavDescriptor) private var latestNav: [NavPoint]
    @Query(AsOfBadge.latestSuccessDescriptor) private var latestSuccess: [SyncRecord]

    static var latestNavDescriptor: FetchDescriptor<NavPoint> {
        var descriptor = FetchDescriptor<NavPoint>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var latestSuccessDescriptor: FetchDescriptor<SyncRecord> {
        let success = SyncRecord.Outcome.success.rawValue
        var descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate { $0.outcomeRaw == success },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        if let through = latestNav.first?.date {
            Label {
                Text("Data through \(through.dayMonthYear)\(syncedSuffix)")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if latestSuccess.isEmpty {
            Label("Not synced yet", systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var syncedSuffix: String {
        guard let synced = latestSuccess.first?.timestamp else { return "" }
        return " · synced \(synced.relativeToNow)"
    }
}
