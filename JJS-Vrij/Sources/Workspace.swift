import Foundation
import SwiftUI
import UIKit

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var library = LibraryState()
    @Published private(set) var models: [DiskModel] = []
    @Published var selected: UUID?
    @Published var problem: String?
    @Published private(set) var ready = false
    @Published private(set) var active: UUID?
    @Published private(set) var activity = "Starten…"
    @Published private(set) var downloading = false
    @Published private(set) var transfer = ""
    @Published var sharedFiles: [URL] = []
    @Published var exportFile: URL?
    private let vault: LibraryVault
    private var modelFiles: ModelFiles?
    private let runner = GGUFRunner()
    private let media = MediaReader()
    private var queue: Task<Void, Never>?
    private var inference: Task<RuntimeSummary, Error>?
    private var downloadTask: Task<Void, Never>?
    private var foreground = true

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        vault = LibraryVault(location: support.appendingPathComponent("JJSVrij/library.json"))
        do { modelFiles = try ModelFiles(root: documents.appendingPathComponent("GGUF", isDirectory: true)) }
        catch { problem = error.localizedDescription }
        Task { await open() }
    }

    var conversation: Conversation? { library.conversations.first { $0.id == selected } }
    var isWriting: Bool { active != nil }
    var settings: InferenceSettings { library.settings }

    private func open() async {
        do {
            library = try await vault.restore()
            library.recoverInterruptedReplies()
            if library.conversations.isEmpty { library.conversations.append(Conversation()) }
            selected = library.conversations.first?.id
            try await reloadModels()
            try await checkpoint()
            ready = true; activity = "Klaar"
            startQueue()
        } catch { problem = error.localizedDescription; activity = "Opslag kon niet worden geopend" }
    }

    private func checkpoint() async throws {
        library.revision &+= 1
        try await vault.write(library)
    }

    func newConversation() async {
        let created = Conversation()
        library.conversations.insert(created, at: 0); selected = created.id
        do { try await checkpoint() } catch { problem = error.localizedDescription }
    }

    func rename(_ id: UUID, _ title: String) async {
        guard let index = library.conversations.firstIndex(where: { $0.id == id }) else { return }
        library.conversations[index].name = title
        do { try await checkpoint() } catch { problem = error.localizedDescription }
    }

    func remove(_ id: UUID) async {
        if let active, library.conversations.first(where: { $0.id == id })?.letters.contains(where: { $0.id == active }) == true { stop() }
        library.conversations.removeAll { $0.id == id }; library.pending.removeAll { $0.conversation == id }
        if library.conversations.isEmpty { library.conversations.append(Conversation()) }
        if selected == id { selected = library.conversations.first?.id }
        do { try await checkpoint() } catch { problem = error.localizedDescription }
    }

    func chooseModel(_ id: String) async {
        library.settings.model = id
        do { try await checkpoint() } catch { problem = error.localizedDescription }
    }

    func configure(context: String, temperature: String, metal: Bool, template: String) async -> Bool {
        guard let size = UInt32(context.trimmingCharacters(in: .whitespacesAndNewlines)),
              let heat = Float(temperature.replacingOccurrences(of: ",", with: ".")), heat.isFinite, heat >= 0 else {
            problem = "Gebruik een niet-negatieve gehele contextgrootte en een eindige temperatuur van nul of hoger. Context 0 gebruikt de modelstandaard."
            return false
        }
        library.settings.context = size; library.settings.temperature = heat
        library.settings.metal = metal; library.settings.template = template.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try await checkpoint(); return true } catch { problem = error.localizedDescription; return false }
    }

    func submit(_ text: String) async -> Bool {
        guard ready else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard models.contains(where: { $0.id == library.settings.model }) else {
            problem = "Importeer of download eerst een GGUF-model en selecteer het bij Modellen."; return false
        }
        if selected == nil { await newConversation() }
        guard let index = library.conversations.firstIndex(where: { $0.id == selected }) else { return false }
        let question = Letter(speaker: .person, text: text)
        let response = Letter(speaker: .model, text: "", status: .waiting)
        if library.conversations[index].letters.isEmpty {
            library.conversations[index].name = text.components(separatedBy: .newlines).first ?? "Gesprek"
        }
        library.conversations[index].letters.append(contentsOf: [question, response])
        library.conversations[index].modified = Date()
        library.pending.append(PendingReply(conversation: library.conversations[index].id, letter: response.id, settings: library.settings))
        do { try await checkpoint(); startQueue(); return true }
        catch { problem = error.localizedDescription; return false }
    }

    func retry(_ letter: UUID) async {
        guard let c = library.conversations.firstIndex(where: { $0.letters.contains(where: { $0.id == letter }) }),
              let m = library.conversations[c].letters.firstIndex(where: { $0.id == letter }),
              [.stopped, .failed].contains(library.conversations[c].letters[m].status) else { return }
        library.conversations[c].letters[m].text = ""; library.conversations[c].letters[m].detail = ""
        library.conversations[c].letters[m].status = .waiting
        library.pending.removeAll { $0.letter == letter }
        library.pending.append(PendingReply(conversation: library.conversations[c].id, letter: letter, settings: library.settings))
        do { try await checkpoint(); startQueue() } catch { problem = error.localizedDescription }
    }

    func stop() { inference?.cancel() }
    func scene(_ phase: ScenePhase) {
        foreground = phase == .active
        UIApplication.shared.isIdleTimerDisabled = foreground && isWriting
    }

    private func update(_ id: UUID, _ change: (inout Letter) -> Void) {
        guard let c = library.conversations.firstIndex(where: { $0.letters.contains(where: { $0.id == id }) }),
              let m = library.conversations[c].letters.firstIndex(where: { $0.id == id }) else { return }
        change(&library.conversations[c].letters[m]); library.conversations[c].modified = Date()
    }

    private func receive(_ event: RuntimeEvent, for letter: UUID) async throws {
        switch event {
        case .progress(let value): activity = value
        case .output(let fragment):
            update(letter) { $0.text += fragment }
            try await checkpoint()
        }
    }

    private func startQueue() {
        guard queue == nil, let modelFiles else { return }
        queue = Task {
            while let job = library.pending.first {
                guard let chat = library.conversations.first(where: { $0.id == job.conversation }),
                      let index = chat.letters.firstIndex(where: { $0.id == job.letter }) else {
                    library.pending.removeAll { $0.id == job.id }; continue
                }
                active = job.letter
                UIApplication.shared.isIdleTimerDisabled = foreground
                update(job.letter) { $0.status = .writing }
                do {
                    try await checkpoint()
                    let file = try await modelFiles.file(job.settings.model)
                    let messages = chat.letters[..<index].map {
                        RuntimeMessage(role: $0.speaker == .person ? "user" : "assistant", text: $0.text)
                    }
                    let running = Task {
                        try await runner.reply(to: messages, modelFile: file, settings: job.settings) { event in
                            try await self.receive(event, for: job.letter)
                        }
                    }
                    inference = running
                    let summary = try await running.value
                    update(job.letter) {
                        $0.status = .ready
                        $0.detail = "Model-eindtoken · \(summary.produced.formatted()) tokens · \(summary.shifts.formatted()) contextverschuivingen"
                    }
                    activity = "Antwoord voltooid"
                } catch is CancellationError {
                    update(job.letter) { $0.status = .stopped; $0.detail = "Door jou gestopt. Ontvangen tekst is bewaard." }
                    activity = "Gestopt"
                } catch {
                    update(job.letter) { $0.status = .failed; $0.detail = error.localizedDescription }
                    problem = error.localizedDescription; activity = "Uitvoering onderbroken"
                }
                inference = nil; active = nil
                UIApplication.shared.isIdleTimerDisabled = false
                library.pending.removeAll { $0.id == job.id }
                do { try await checkpoint() } catch { problem = error.localizedDescription; break }
            }
            queue = nil
        }
    }

    private func reloadModels() async throws {
        guard let modelFiles else { throw VrijError("De modellenopslag is niet beschikbaar.") }
        models = try await modelFiles.all()
        if !models.contains(where: { $0.id == library.settings.model }) { library.settings.model = models.first?.id ?? "" }
    }

    func importModels(_ urls: [URL]) async {
        guard let modelFiles else { return }
        transfer = "GGUF-bestanden importeren…"
        do {
            let added = try await modelFiles.ingest(urls)
            try await reloadModels()
            if let first = added.first { library.settings.model = first.id }
            try await checkpoint(); transfer = "Import voltooid"
        } catch { problem = error.localizedDescription; transfer = "Import mislukt" }
    }

    func deleteModel(_ model: DiskModel) async {
        guard !isWriting, let modelFiles else { return }
        do { try await modelFiles.delete(model); try await reloadModels(); try await checkpoint() }
        catch { problem = error.localizedDescription }
    }

    func shareModel(_ model: DiskModel) async {
        guard let modelFiles else { return }
        do { sharedFiles = try await modelFiles.export(model) } catch { problem = error.localizedDescription }
    }

    func downloadModels(_ input: String) {
        guard !downloading, let modelFiles else { return }
        let lines = input.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let links = lines.compactMap(URL.init(string:))
        guard !links.isEmpty, links.count == lines.count else { problem = "Vul geldige rechtstreekse GGUF-bestandslinks in, één per regel."; return }
        downloading = true
        downloadTask = Task {
            defer { downloading = false; downloadTask = nil }
            do {
                let added = try await modelFiles.download(links) { value in await self.transferStatus(value) }
                try await reloadModels()
                if let first = added.first { library.settings.model = first.id }
                try await checkpoint(); transfer = "Download voltooid"
            } catch is CancellationError { transfer = "Download geannuleerd" }
            catch let error as URLError where error.code == .cancelled { transfer = "Download geannuleerd" }
            catch { problem = error.localizedDescription; transfer = "Download mislukt" }
        }
    }
    private func transferStatus(_ value: String) { transfer = value }
    func cancelDownload() { downloadTask?.cancel() }

    func readAttachment(_ url: URL) async throws -> String { try await media.text(from: url) }

    func importConversation(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let added: [Conversation]
            if url.pathExtension.lowercased() == "json" {
                added = try await vault.decodeArchive(url)
            } else {
                added = [Conversation(name: url.deletingPathExtension().lastPathComponent,
                                      letters: [Letter(speaker: .person, text: try await media.text(from: url))])]
            }
            library.conversations.insert(contentsOf: added, at: 0)
            selected = added.first?.id ?? selected
            try await checkpoint()
        } catch { problem = error.localizedDescription }
    }

    func exportConversation(text: Bool, all: Bool) async {
        do {
            let selectedChats = all ? library.conversations : library.conversations.filter { $0.id == selected }
            exportFile = try await vault.exportFile(selectedChats, plain: text)
        } catch { problem = error.localizedDescription }
    }
}
