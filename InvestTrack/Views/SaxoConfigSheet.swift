import SwiftUI

/// Lets the user enter their Saxo app credentials in the app. Values are
/// stored on-device (UserDefaults) rather than in source, so they survive
/// `git pull`, rebuilds, and app updates.
struct SaxoConfigSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var environment: SaxoConfiguration.Environment
    @State private var appKey: String
    @State private var redirectURI: String

    init(configuration: SaxoConfiguration) {
        _environment = State(initialValue: configuration.environment)
        _appKey = State(initialValue: configuration.isConfigured ? configuration.appKey : "")
        _redirectURI = State(initialValue: configuration.redirectURI)
    }

    private var canSave: Bool {
        !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Environment", selection: $environment) {
                        Text("Simulation").tag(SaxoConfiguration.Environment.simulation)
                        Text("Live").tag(SaxoConfiguration.Environment.live)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Environment")
                } footer: {
                    Text("Live uses your real Saxo account and needs a Live app key. Simulation is the free demo environment.")
                }

                Section {
                    TextField("App key", text: $appKey, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("App key")
                } footer: {
                    Text("From developer.saxo → your app. Use the key that matches the environment above.")
                }

                Section {
                    TextField("Redirect URI", text: $redirectURI, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Redirect URI")
                } footer: {
                    Text("The https bounce-page URL, matching the redirect registered on your Saxo app. See SAXO_SETUP.md.")
                }
            }
            .navigationTitle("Saxo app setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.saveSaxoConfiguration(
                            appKey: appKey,
                            environment: environment,
                            redirectURI: redirectURI
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    SaxoConfigSheet(configuration: .default)
        .environment(AppModel())
}
