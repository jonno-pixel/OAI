import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsScreen: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Apple Metal gebruiken", isOn: $store.useMetal)
                    TextField("Contexttokens · 0 = modelstandaard", text: $store.contextText)
                        .keyboardType(.numberPad)
                    TextField("Temperatuur", text: $store.temperatureText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Model")
                } footer: {
                    Text("De actieve context wordt begrensd door het model en het beschikbare geheugen. Bij een volle context schuift de actieve geschiedenis door; de opgeslagen chat blijft volledig bewaard. Er is geen vaste uitvoertokenlimiet of timer.")
                }

                Section {
                    TextField("Leeg = modeltemplate · raw = directe invoer", text: $store.template)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Chattemplate")
                } footer: {
                    Text("Leeg gebruikt de modeltemplate, of directe invoer als het model geen template bevat. Met raw wordt berichtinhoud zonder rolmarkeringen, gescheiden door regeleinden, rechtstreeks aangeboden. JJS voegt geen systeemprompt of inhoudsfilter toe.")
                }

                Section("Gesprekken") {
                    Button("Exporteer dit gesprek als tekst", systemImage: "doc.text") {
                        Task { await store.exportChats(asText: true, selectedOnly: true) }
                    }
                    Button("Exporteer alle gesprekken als tekst", systemImage: "doc.on.doc") {
                        Task { await store.exportChats(asText: true) }
                    }
                    Button("Exporteer alle gesprekken als JSON", systemImage: "square.and.arrow.up") {
                        Task { await store.exportChats() }
                    }
                    if let exportURL = store.exportURL {
                        ShareLink("Deel JSON-export", item: exportURL)
                    }
                    Button("Importeer tekst of JSON", systemImage: "square.and.arrow.down") {
                        importing = true
                    }
                }

                Section {
                    Text("Tekstbestanden worden volledig als inhoud van een nieuw gesprek geïmporteerd. Tekstexport is een leesbaar transcript. JSON bewaart de berichtrollen en statussen voor volledige overdracht.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("JJS verstuurt gesprekken en bijlagen niet naar een server en bevat geen advertenties of analytics. Modellen draaien lokaal. Alleen een door jou gestarte modeldownload maakt verbinding met de opgegeven website; die ontvangt onder andere je IP-adres.")
                    Text("Gesprekken staan in de appopslag en kunnen deel uitmaken van je iOS-back-up. Modellen zijn uitgesloten van die back-up. Je kunt gesprekken en modellen afzonderlijk verwijderen. Bij delen of exporteren kies je zelf de bestemming.")
                    Text("Afbeeldingen worden lokaal als tekst gelezen. Voor audiobestanden vraagt JJS toestemming voor spraakherkenning en gebruikt het alleen herkenning op het toestel, als die beschikbaar is.")
                    NavigationLink("Licenties") {
                        ScrollView {
                            Text(licenseText)
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle("Licenties")
                    }
                }

                Section("Verwerking") {
                    Label("Lokale verwerking op dit toestel", systemImage: "iphone")
                    Text("iOS beheert de warmte, het geheugen en de achtergrondlevenscyclus. JJS legt geen eigen warmtepauze, generatietimer of maximumaantal antwoordtokens op.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instellingen")
            .toolbar { Button("Gereed") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text]) { result in
                switch result {
                case .success(let url):
                    Task { await store.importChats(from: url) }
                case .failure(let error):
                    store.problem = error.localizedDescription
                }
            }
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LLAMA-LICENSE", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "llama.cpp · MIT License · Copyright (c) 2023–2026 The ggml authors"
        }
        return value
    }

}
