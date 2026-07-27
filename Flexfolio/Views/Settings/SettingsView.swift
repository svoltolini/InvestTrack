import SwiftData
import SwiftUI

struct SettingsView: View {
    /// Onboarding mode: presented full-screen on first launch, not dismissable
    /// until credentials are saved.
    var isOnboarding = false

    @Environment(AppSettings.self) private var settings
    @Environment(SyncStatus.self) private var syncStatus
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(AsOfBadge.latestSuccessDescriptor) private var latestSuccess: [SyncRecord]
    @Query(SettingsView.latestRecordDescriptor) private var latestRecord: [SyncRecord]

    @State private var token = ""
    @State private var queryID = ""
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var savedFlash = false
    @State private var confirmDelete = false
    @State private var showHelp = false

    enum TestResult: Equatable {
        case success
        case failure(String)
    }

    static var latestRecordDescriptor: FetchDescriptor<SyncRecord> {
        var descriptor = FetchDescriptor<SyncRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    Section {
                        Text("Flexfolio reads your Interactive Brokers account through the Flex Web Service — read-only, straight from IBKR, no third-party servers. You need a Flex **token** and a **Query ID** from Client Portal.")
                            .font(.footnote)
                    }
                }

                credentialsSection
                syncSection
                tokenExpirySection
                helpSection
                if !isOnboarding {
                    dangerSection
                }
            }
            .navigationTitle(isOnboarding ? "Welcome" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear {
                token = KeychainStore.token ?? ""
                queryID = KeychainStore.queryID ?? ""
            }
        }
    }

    // MARK: - Credentials

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedQueryID: String { queryID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !trimmedToken.isEmpty && !trimmedQueryID.isEmpty }

    private var credentialsSection: some View {
        Section {
            SecureField("Flex token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Query ID", text: $queryID)
                .keyboardType(.numberPad)

            Button {
                runConnectionTest()
            } label: {
                HStack {
                    Text("Test connection")
                    if isTesting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!canSubmit || isTesting)

            if let testResult {
                switch testResult {
                case .success:
                    Label("Connection OK — query found", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Button {
                settings.saveCredentials(token: trimmedToken, queryID: trimmedQueryID)
                savedFlash = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    savedFlash = false
                }
            } label: {
                HStack {
                    Text(isOnboarding ? "Save & start" : "Save")
                        .fontWeight(.semibold)
                    if savedFlash {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(!canSubmit)
        } header: {
            Text("IBKR Flex credentials")
        } footer: {
            Text("Stored only in the device Keychain. Read-only access — a Flex token cannot place trades.")
        }
    }

    private func runConnectionTest() {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil
        let testToken = trimmedToken
        let testQueryID = trimmedQueryID
        Task {
            defer { isTesting = false }
            do {
                _ = try await FlexClient().requestStatement(token: testToken, queryID: testQueryID)
                testResult = .success
            } catch let error as FlexError {
                testResult = .failure(error.errorDescription ?? "Connection failed.")
            } catch {
                testResult = .failure("Connection failed.")
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            if let record = latestRecord.first {
                LabeledContent("Last sync") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.timestamp.relativeToNow)
                        Text(record.outcome == .success ? "Succeeded" : (record.message ?? "Failed"))
                            .font(.caption2)
                            .foregroundStyle(record.outcome == .success ? Color.secondary : Color.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } else {
                Text("Never synced")
                    .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let cooldown = syncStatus.cooldownRemaining(at: context.date)
                Button {
                    Task { await syncStatus.manualSync() }
                } label: {
                    HStack {
                        Text(cooldown > 0 ? "Sync now (wait \(cooldown)s)" : "Sync now")
                        if syncStatus.isRunning {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(!settings.hasCredentials || syncStatus.isRunning || cooldown > 0)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("IBKR Flex is end-of-day data. Flexfolio refreshes automatically when opened if the last sync is older than 12 hours; manual refresh is limited to once a minute.")
        }
    }

    // MARK: - Token expiry

    private var tokenExpirySection: some View {
        Section {
            if settings.tokenNearingExpiry {
                Label(
                    "Your token was saved over 11 months ago and is likely close to expiry. Regenerate it in Client Portal soon.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            if let created = settings.tokenCreatedAt {
                LabeledContent("Token saved", value: created.dayMonthYear)
            }
            Text("IBKR tokens expire (max 1 year). If sync fails with code 1012 or 1015, regenerate the token in Client Portal and update it here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Help & danger

    private var helpSection: some View {
        Section {
            Button("Flex Query setup checklist") {
                showHelp = true
            }
            .sheet(isPresented: $showHelp) {
                NavigationStack {
                    FlexQueryHelpView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showHelp = false }
                            }
                        }
                }
            }
        } footer: {
            Text("How to create the token and Query ID in IBKR Client Portal.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Delete all local data", role: .destructive) {
                confirmDelete = true
            }
            .confirmationDialog(
                "Delete all local data?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes all synced data and your credentials from this device. IBKR is not affected.")
            }
        }
    }

    private func deleteAllData() {
        try? modelContext.delete(model: Position.self)
        try? modelContext.delete(model: DividendEvent.self)
        try? modelContext.delete(model: DividendAccrual.self)
        try? modelContext.delete(model: NavPoint.self)
        try? modelContext.delete(model: CashFlow.self)
        try? modelContext.delete(model: SyncRecord.self)
        try? modelContext.save()
        settings.deleteCredentials()
        token = ""
        queryID = ""
        testResult = nil
        dismiss()
    }
}
