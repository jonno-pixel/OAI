import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var connection = Connection()
    @State private var key = ""
    @State private var models: [String] = []
    @State private var testing = false
    @State private var result: String?
    @State private var testTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("AI-dienst") {
                    Picker("Dienst", selection: $connection.provider) {
                        ForEach(Provider.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(testing)
                }
                Section {
                    TextField("API-basis-URL", text: $connection.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API-sleutel", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Verbinding") } footer: {
                    Text(connection.provider == .openAI
                         ? "OpenAI API-gebruik wordt apart van je ChatGPT-abonnement betaald. De sleutel wordt alleen in de iPhone-sleutelhanger opgeslagen."
                         : "Vervang 192.168.1.100 door het IP-adres van je pc. localhost werkt hier niet. Gebruik HTTP alleen op een vertrouwd lokaal netwerk; onderweg een beveiligde verbinding.")
                }.disabled(testing)
                Section {
                    TextField("Model-ID", text: $connection.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !models.isEmpty {
                        Picker("Beschikbare modellen", selection: $connection.model) {
                            Text("Kies een model").tag("")
                            if !connection.model.isEmpty && !models.contains(connection.model) {
                                Text(connection.model).tag(connection.model)
                            }
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button {
                        testing = true; result = nil
                        let config = connection
                        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        testTask = Task {
                            defer { testing = false; testTask = nil }
                            do {
                                let loaded = try await APIClient.models(config, key: secret)
                                try Task.checkCancellation()
                                models = loaded
                                if loaded.count == 1 && connection.model.isEmpty { connection.model = loaded[0] }
                                result = loaded.isEmpty ? "Verbonden, maar er zijn geen modellen beschikbaar. Laad eerst een model op je pc." : "Verbonden · \(loaded.count) modellen gevonden. Kies een chatmodel."
                            } catch {
                                if !Task.isCancelled { result = ChatStore.friendly(error) }
                            }
                        }
                    } label: {
                        HStack {
                            Label("Verbinding testen en modellen ophalen", systemImage: "network")
                            if testing { Spacer(); ProgressView() }
                        }
                    }.disabled(testing)
                    if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Model") } footer: {
                    Text("Een model hoeft niet vooraf bekend te zijn: haal de lijst op. Voor het chatverzoek is uiteindelijk wel een model-ID nodig. OpenAI toont ook modellen die niet voor chat bedoeld zijn.")
                }
                Section("Op deze iPhone") {
                    Label("Gesprekken worden lokaal bewaard", systemImage: "iphone")
                    Label("Sleutels in de sleutelhanger", systemImage: "key.fill")
                    Text("Je berichten worden verstuurd naar de ingestelde AI-dienst. Chatgeschiedenis is lokaal leesbaar wanneer je toestel ontgrendeld is; er is geen appvergrendeling.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instellingen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        do {
                            connection.url = connection.url.trimmingCharacters(in: .whitespacesAndNewlines)
                            connection.model = connection.model.trimmingCharacters(in: .whitespacesAndNewlines)
                            _ = try APIClient.endpoint(connection, path: "models")
                            try store.configure(connection, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } catch { result = error.localizedDescription }
                    }.disabled(testing)
                }
            }
            .onAppear { connection = store.connection; key = Keychain.read(connection.provider) }
            .onChange(of: connection.provider) { _, provider in
                connection = store.state.connections[provider.rawValue] ?? Connection(provider: provider, url: provider.baseURL)
                key = Keychain.read(provider); models = []; result = nil
            }
            .onDisappear { testTask?.cancel() }
        }
    }
}
