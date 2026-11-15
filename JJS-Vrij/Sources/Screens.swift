import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum VrijTab: Hashable { case chat, conversations, models, settings }

@MainActor
struct VrijHome: View {
    @EnvironmentObject private var space: Workspace
    @State private var tab = VrijTab.chat
    var body: some View {
        TabView(selection: $tab) {
            WritingRoom().tabItem { Label("Gesprek", systemImage: "bubble.left.and.bubble.right") }.tag(VrijTab.chat)
            ConversationShelf(openChat: { tab = .chat })
                .tabItem { Label("Bibliotheek", systemImage: "books.vertical") }.tag(VrijTab.conversations)
            ModelShelf().tabItem { Label("Modellen", systemImage: "cpu") }.tag(VrijTab.models)
            Preferences().tabItem { Label("Instellingen", systemImage: "slider.horizontal.3") }.tag(VrijTab.settings)
        }
        .tint(.blue)
        .alert("JJS Vrij", isPresented: Binding(get: { space.problem != nil }, set: { if !$0 { space.problem = nil } })) {
            Button("OK", role: .cancel) { space.problem = nil }
        } message: { Text(space.problem ?? "") }
        .sheet(isPresented: Binding(get: { !space.sharedFiles.isEmpty }, set: { if !$0 { space.sharedFiles = [] } })) {
            NativeShare(items: space.sharedFiles)
        }
        .onChange(of: space.exportFile) { _, file in if let file { space.sharedFiles = [file] } }
    }
}

@MainActor
private struct WritingRoom: View {
    @EnvironmentObject private var space: Workspace
    @State private var draft = ""
    @State private var inserts: [String] = []
    @State private var selectingFiles = false
    @State private var reading = false
    @State private var follow = true
    @State private var expanding = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if space.conversation?.letters.isEmpty != false {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("JJS Vrij").font(.largeTitle.bold())
                                Text("Jouw gesprek. Op jouw toestel.").font(.title3).foregroundStyle(.secondary)
                                Text(space.models.isEmpty ? "Importeer of download een GGUF-bestand via Modellen. Daarna kun je hier schrijven." : "Je geselecteerde model staat klaar. Stel je vraag of voeg een bestand toe.")
                                    .foregroundStyle(.secondary)
                            }.padding(.vertical, 30)
                        }
                        ForEach(space.conversation?.letters ?? []) { letter in
                            LetterView(letter: letter, reuse: { draft = letter.text; focused = true }, retry: {
                                Task { await space.retry(letter.id) }
                            })
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: space.conversation?.letters.last?.text) { _, _ in
                    if follow { scroll.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: space.selected) { _, _ in scroll.scrollTo("latest", anchor: .bottom) }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            }
            .navigationTitle("JJS Vrij").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Nieuw gesprek", systemImage: "square.and.pencil") { Task { await space.newConversation() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Antwoord volgen", isOn: $follow)
                        Button("Exporteer als tekst", systemImage: "doc.text") { Task { await space.exportConversation(text: true, all: false) } }
                        Button("Exporteer als JSON", systemImage: "square.and.arrow.up") { Task { await space.exportConversation(text: false, all: false) } }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Gespreksopties")
                }
            }
            .fileImporter(isPresented: $selectingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    reading = true
                    Task {
                        defer { reading = false }
                        for file in urls {
                            do { inserts.append("Bijlage: \(file.lastPathComponent)\n" + (try await space.readAttachment(file))) }
                            catch { space.problem = error.localizedDescription }
                        }
                    }
                case .failure(let error): space.problem = error.localizedDescription
                }
            }
            .sheet(isPresented: $expanding) {
                NavigationStack {
                    TextEditor(text: $draft).padding().navigationTitle("Bericht schrijven")
                        .toolbar { Button("Gereed") { expanding = false } }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if space.isWriting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(space.activity).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop", systemImage: "stop.circle.fill") { space.stop() }.labelStyle(.iconOnly)
                }
            }
            if !inserts.isEmpty {
                HStack {
                    Label("\(inserts.count) bijlagen", systemImage: "paperclip").font(.caption)
                    Spacer()
                    Button("Verwijder bijlagen", systemImage: "xmark.circle") { inserts.removeAll() }.font(.caption)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("Bestand toevoegen", systemImage: "paperclip") { selectingFiles = true }
                    Button("Groot schrijfveld", systemImage: "arrow.up.left.and.arrow.down.right") { expanding = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Bijlage of groter schrijfveld").disabled(reading)
                TextField("Schrijf je bericht", text: $draft, axis: .vertical)
                    .lineLimit(1...7).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                    .focused($focused)
                if reading { ProgressView().frame(width: 44, height: 44) }
                else {
                    Button("Verstuur", systemImage: "arrow.up") {
                        let originalDraft = draft, originalInserts = inserts
                        let message = ([originalDraft] + originalInserts).filter { !$0.isEmpty }.joined(separator: "\n\n")
                        Task {
                            if await space.submit(message), draft == originalDraft, inserts == originalInserts {
                                draft = ""; inserts = []
                            }
                        }
                    }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!space.ready || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inserts.isEmpty))
                }
            }
        }.padding().background(.regularMaterial)
    }
}

private struct LetterView: View {
    let letter: Letter
    let reuse: () -> Void
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(letter.speaker == .person ? "Jij" : "JJS",
                  systemImage: letter.speaker == .person ? "person.crop.circle" : "sparkles")
                .font(.subheadline.bold()).foregroundStyle(.secondary)
            if letter.text.isEmpty && letter.status == .writing {
                Text("Het model wordt voorbereid…").foregroundStyle(.secondary)
            } else {
                // Plain text always exposes the complete generated content,
                // including source code and literal punctuation.
                Text(letter.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if letter.status == .waiting { Label("Wacht op verwerking", systemImage: "clock").font(.caption) }
            if letter.status == .failed || letter.status == .stopped {
                Text(letter.detail).font(.footnote).foregroundStyle(.secondary)
                Button("Opnieuw proberen", systemImage: "arrow.clockwise", action: retry)
            }
            HStack {
                Button("Kopieer", systemImage: "doc.on.doc") { UIPasteboard.general.string = letter.text }
                ShareLink(item: letter.text) { Label("Deel", systemImage: "square.and.arrow.up") }
                if letter.speaker == .person { Button("Gebruik opnieuw", systemImage: "pencil", action: reuse) }
            }.font(.callout).labelStyle(.iconOnly)
        }.padding(letter.speaker == .person ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(letter.speaker == .person ? Color(uiColor: .secondarySystemBackground) : .clear,
                        in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
private struct ConversationShelf: View {
    @EnvironmentObject private var space: Workspace
    let openChat: () -> Void
    @State private var query = ""
    @State private var importing = false
    @State private var deleting: Conversation?
    @State private var renaming: Conversation?
    @State private var title = ""
    private var results: [Conversation] {
        space.library.conversations.filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.letters.contains { $0.text.localizedStandardContains(query) }
        }.sorted { $0.modified > $1.modified }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { chat in
                    Button {
                        space.selected = chat.id; openChat()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chat.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(chat.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.contextMenu {
                        Button("Naam wijzigen", systemImage: "pencil") { renaming = chat; title = chat.name }
                        Button("Verwijder", systemImage: "trash", role: .destructive) { deleting = chat }
                    }.swipeActions {
                        Button("Verwijder", role: .destructive) { deleting = chat }
                    }
                }
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
            .searchable(text: $query, prompt: "Zoek in al je tekst")
            .navigationTitle("Bibliotheek")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Nieuw", systemImage: "plus") { Task { await space.newConversation(); openChat() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Importeer tekst of JSON", systemImage: "square.and.arrow.down") { importing = true }
                        Button("Alles als tekst exporteren") { Task { await space.exportConversation(text: true, all: true) } }
                        Button("Alles als JSON exporteren") { Task { await space.exportConversation(text: false, all: true) } }
                    } label: { Image(systemName: "arrow.up.arrow.down.circle") }.accessibilityLabel("Import en export")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text]) { result in
                switch result {
                case .success(let url): Task { await space.importConversation(url); openChat() }
                case .failure(let error): space.problem = error.localizedDescription
                }
            }
            .confirmationDialog("Gesprek verwijderen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Verwijder", role: .destructive) { if let deleting { Task { await space.remove(deleting.id) } }; deleting = nil }
            }
            .alert("Naam wijzigen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Naam", text: $title)
                Button("Bewaar") { if let renaming { Task { await space.rename(renaming.id, title) } }; renaming = nil }
                Button("Annuleer", role: .cancel) { renaming = nil }
            }
        }
    }
}

@MainActor
private struct ModelShelf: View {
    @EnvironmentObject private var space: Workspace
    @State private var importing = false
    @State private var downloading = false
    @State private var links = ""
    @State private var deleting: DiskModel?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Importeer GGUF uit Bestanden", systemImage: "folder.badge.plus") { importing = true }
                    Button("Download GGUF via URL", systemImage: "arrow.down.circle") { downloading = true }.disabled(space.downloading)
                    if space.downloading {
                        ProgressView(space.transfer)
                        Button("Download annuleren", role: .cancel) { space.cancelDownload() }
                    } else if !space.transfer.isEmpty { Text(space.transfer).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("Importeer losse GGUF-bestanden of een map. Selecteer bij gesplitste modellen alle delen samen. Je modelbestanden worden ongewijzigd opgeslagen.")
                }
                Section("Op je toestel") {
                    if space.models.isEmpty { ContentUnavailableView("Nog geen modellen", systemImage: "cpu") }
                    ForEach(space.models) { model in
                        Button { Task { await space.chooseModel(model.id) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.title).foregroundStyle(.primary)
                                    Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if space.settings.model == model.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }.contextMenu {
                            Button("Deel / exporteer GGUF", systemImage: "square.and.arrow.up") { Task { await space.shareModel(model) } }
                            Button("Verwijder model", systemImage: "trash", role: .destructive) { deleting = model }.disabled(space.isWriting)
                        }.swipeActions(edge: .leading) {
                            Button("Deel", systemImage: "square.and.arrow.up") { Task { await space.shareModel(model) } }.tint(.blue)
                        }.swipeActions {
                            Button("Verwijder", role: .destructive) { deleting = model }.disabled(space.isWriting)
                        }
                    }
                }
            }.navigationTitle("Modellen")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): Task { await space.importModels(urls) }
                    case .failure(let error): space.problem = error.localizedDescription
                    }
                }
                .sheet(isPresented: $downloading) {
                    NavigationStack {
                        Form {
                            Section {
                                TextEditor(text: $links).frame(minHeight: 160).keyboardType(.URL)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("GGUF-bestandslinks, één per regel")
                            } footer: {
                                Text("Plak een rechtstreekse bestandslink, geen webpagina. Voor een gesplitst model gebruik je één link per regel. De website ontvangt je downloadverzoek.")
                            }
                        }.navigationTitle("GGUF downloaden")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { downloading = false } }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Download") { space.downloadModels(links); downloading = false }
                                        .disabled(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                    }
                }
                .confirmationDialog("Model verwijderen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Verwijder", role: .destructive) { if let deleting { Task { await space.deleteModel(deleting) } }; deleting = nil }
                }
        }
    }
}

@MainActor
private struct Preferences: View {
    @EnvironmentObject private var space: Workspace
    @State private var context = "0"
    @State private var temperature = "0.7"
    @State private var metal = true
    @State private var template = ""
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Context · 0 = modelstandaard", text: $context).keyboardType(.numberPad)
                    TextField("Temperatuur", text: $temperature).keyboardType(.decimalPad)
                    Toggle("Apple Metal", isOn: $metal)
                } header: { Text("Uitvoering") } footer: {
                    Text("Er is geen appquotum voor tokens, berichten of generatieduur. iOS beheert geheugen, rekenkracht en de levenscyclus. Bij een volle context wordt actieve context verschoven; opgeslagen tekst blijft behouden.")
                }
                Section {
                    TextField("Leeg = modeltemplate · raw = directe tekst", text: $template)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Invoerformaat") } footer: {
                    Text("JJS Vrij voegt geen systeemprompt, inhoudsfilter of verborgen vervolgopdracht toe. Raw biedt berichtinhoud gescheiden door regeleinden aan, zonder rolmarkeringen. Modellen zonder template gebruiken automatisch directe tekst.")
                }
                Button(saved ? "Instellingen bewaard" : "Bewaar instellingen", systemImage: saved ? "checkmark.circle" : "checkmark") {
                    Task { saved = await space.configure(context: context, temperature: temperature, metal: metal, template: template) }
                }
                Section("Gegevens en privacy") {
                    Text("Gesprekken, bijlagen en inferentie blijven op het toestel. JJS Vrij bevat geen advertenties, tracking of analytics. Alleen een door jou gestarte modeldownload maakt verbinding met de gekozen server; die ontvangt onder andere je IP-adres.")
                    Text("Gesprekken kunnen deel uitmaken van je iOS-back-up. GGUF-bestanden zijn uitgesloten van die back-up. Gebruik Bibliotheek voor tekst- of JSON-overdracht, en Modellen om GGUF-bestanden te delen of te verwijderen.")
                    Text("Tekstimport bewaart het hele bestand als een nieuw bericht. Tekstexport is een leesbaar transcript. JSON bewaart de rollen en berichtstatussen. Afbeeldingen en PDF-scans worden lokaal als tekst gelezen; lokale spraakherkenning vraagt iOS-toestemming.")
                }
                Section("Over JJS Vrij") {
                    LabeledContent("Versie", value: "2.0")
                    NavigationLink("Open-sourcelicentie") {
                        ScrollView { Text(license).textSelection(.enabled).padding() }.navigationTitle("Licentie")
                    }
                }
            }.navigationTitle("Instellingen")
                .task {
                    let options = space.settings
                    context = String(options.context); temperature = String(options.temperature)
                    metal = options.metal; template = options.template
                }
        }
    }
    private var license: String {
        guard let path = Bundle.main.url(forResource: "LLAMA-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: path, encoding: .utf8) else { return "llama.cpp · MIT License" }
        return text
    }
}

private struct NativeShare: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
