import Foundation
import SwiftData

/// One sync attempt, success or failure — the "data as of / last synced"
/// source of truth. Messages never contain credentials.
@Model
final class SyncRecord {
    var timestamp: Date
    var outcomeRaw: String
    var message: String?
    var statementFrom: Date?
    var statementTo: Date?

    enum Outcome: String {
        case success
        case failure
    }

    init(timestamp: Date = .now, outcome: Outcome, message: String? = nil, statementFrom: Date? = nil, statementTo: Date? = nil) {
        self.timestamp = timestamp
        self.outcomeRaw = outcome.rawValue
        self.message = message
        self.statementFrom = statementFrom
        self.statementTo = statementTo
    }

    var outcome: Outcome {
        Outcome(rawValue: outcomeRaw) ?? .failure
    }
}
