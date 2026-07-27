import Foundation
import SwiftData

/// End-to-end sync: Keychain → step 1 → poll step 2 → parse → import in one
/// save → SyncRecord. Runs off the main actor; views keep showing SwiftData
/// content throughout (offline-first — sync only augments).
actor SyncEngine {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func sync(progress: @Sendable @escaping (String) -> Void = { _ in }) async throws -> SyncSummary {
        guard let credentials = KeychainStore.loadCredentials() else {
            throw FlexError.notConfigured
        }
        let client = FlexClient()
        do {
            progress("Requesting statement…")
            let (reference, statementURL) = try await client.requestStatement(
                token: credentials.token,
                queryID: credentials.queryID
            )
            progress("Waiting for IBKR…")
            let parsed = try await client.fetchStatement(
                statementURL: statementURL,
                reference: reference,
                token: credentials.token
            )
            progress("Importing…")
            return try importAndRecord(parsed)
        } catch {
            recordFailure(error)
            throw error
        }
    }

    /// Imports the statement and writes the success SyncRecord in the same
    /// context save, so the record never claims data that didn't land.
    private func importAndRecord(_ parsed: ParsedStatement) throws -> SyncSummary {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var summary = try StatementImporter.importStatement(parsed, into: context)
        context.insert(SyncRecord(
            outcome: .success,
            message: nil,
            statementFrom: parsed.fromDate,
            statementTo: parsed.toDate
        ))
        try context.save()
        if summary.dataThrough == nil {
            summary.dataThrough = parsed.toDate
        }
        return summary
    }

    /// Best-effort failure record; the error message never contains
    /// credentials (FlexError descriptions are static/user-facing text).
    private func recordFailure(_ error: Error) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let message = (error as? FlexError)?.errorDescription ?? error.localizedDescription
        context.insert(SyncRecord(outcome: .failure, message: message))
        try? context.save()
    }
}
