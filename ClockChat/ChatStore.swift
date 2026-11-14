import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var state = SavedState()
    @Published var selectedID: UUID?
    @Published var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private let file: URL
    init() {
        let folder = URL.applicationSupportDirectory.appending(path: "ClockChat", directoryHint: .isDirectory)
        file = folder.appending(path: "conversations.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
            }
        } catch { self.error = "Opgeslagen gegevens konden niet worden geladen: \(error.localizedDescription)" }
        selectedID = state.conversations.first?.id
    }
    var connection: Connection {
        state.connections[state.selectedProvider.rawValue] ?? Connection(provider: state.selectedProvider, url: state.selectedProvider.baseURL)
    }
    var current: Conversation? { state.conversations.first { $0.id == selectedID } }
    func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
        } catch { self.error = "Bewaren mislukt: \(error.localizedDescription)" }
    }
    func configure(_ connection: Connection, key: String) throws {
        try Keychain.write(key, for: connection.provider)
        state.selectedProvider = connection.provider
        state.connections[connection.provider.rawValue] = connection
        save()
    }
    func newChat() {
        guard !busy else { return }
        let chat = Conversation()
        state.conversations.insert(chat, at: 0)
        selectedID = chat.id
        save()
    }
    func delete(_ id: UUID) {
        guard !busy else { return }
        state.conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = state.conversations.first?.id }
        save()
    }
    func stop() { task?.cancel() }
    func send(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return false }
        let config = connection
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Kies eerst een model bij Instellingen. Gebruik ‘Verbinding testen’ om beschikbare modellen op te halen."
            return false
        }
        do { _ = try APIClient.endpoint(config, path: "chat/completions") }
        catch { self.error = error.localizedDescription; return false }
        let key = Keychain.read(config.provider)
        if config.provider == .openAI && key.isEmpty { error = "Vul je OpenAI API-sleutel in bij Instellingen."; return false }
        if current == nil { newChat() }
        guard let id = selectedID, let index = state.conversations.firstIndex(where: { $0.id == id }) else { return false }
        if state.conversations[index].messages.isEmpty { state.conversations[index].title = String(text.prefix(48)) }
        state.conversations[index].messages.append(Message(role: "user", content: text))
        // Interrupted answers stay visible but are not sent back as completed model responses.
        let history = state.conversations[index].messages.filter { !$0.interrupted }
        let answer = Message(role: "assistant", content: "", interrupted: true)
        state.conversations[index].messages.append(answer)
        state.conversations[index].updated = Date()
        busy = true
        save()
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.task = nil; self.save() }
            do {
                try await APIClient.stream(config, key: key, messages: history) { [weak self] chunk in
                    guard let self, let i = self.state.conversations.firstIndex(where: { $0.id == id }),
                          let j = self.state.conversations[i].messages.firstIndex(where: { $0.id == answer.id }) else { return }
                    self.state.conversations[i].messages[j].content += chunk
                }
                try Task.checkCancellation()
                if let i = self.state.conversations.firstIndex(where: { $0.id == id }),
                   let j = self.state.conversations[i].messages.firstIndex(where: { $0.id == answer.id }) {
                    self.state.conversations[i].messages[j].interrupted = false
                }
            } catch {
                if !Task.isCancelled { self.error = Self.friendly(error) }
            }
        }
        return true
    }
    static func friendly(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "De server reageert niet op tijd. Controleer of het model geladen is."
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost:
                return "Geen verbinding. Controleer internet, het pc-adres, de server en toestemming voor het lokale netwerk. localhost verwijst op je iPhone naar je iPhone."
            default: break
            }
        }
        return error.localizedDescription
    }
}
