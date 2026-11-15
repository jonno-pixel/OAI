import Foundation

actor LibraryVault {
    private let location: URL
    private var writtenRevision: UInt64 = 0

    init(location: URL) { self.location = location }

    func restore() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: location.path) else { return LibraryState() }
        let decoded = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: location))
        guard decoded.format == 1 else { throw VrijError("Onbekende versie van de gespreksopslag.") }
        writtenRevision = decoded.revision
        return decoded
    }

    func write(_ state: LibraryState) throws {
        guard state.revision >= writtenRevision else { return }
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(state)
        // Atomic replacement leaves the previous complete library intact if a write fails.
        #if os(iOS)
        try encoded.write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try encoded.write(to: location, options: .atomic)
        #endif
        writtenRevision = state.revision
    }

    func decodeArchive(_ url: URL) throws -> [Conversation] {
        try Self.importJSON(Data(contentsOf: url))
    }

    func exportFile(_ conversations: [Conversation], plain: Bool) throws -> URL {
        let data = plain ? Data(TextTransfer.transcript(conversations).utf8) : try Self.exportJSON(conversations)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("JJS-Vrij-" + UUID().uuidString + (plain ? ".txt" : ".json"))
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func exportJSON(_ conversations: [Conversation]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ConversationArchive(conversations: conversations))
    }

    static func importJSON(_ data: Data) throws -> [Conversation] {
        let archive = try JSONDecoder().decode(ConversationArchive.self, from: data)
        guard archive.format == 1 else { throw VrijError("Dit gespreksarchief heeft een onbekende versie.") }
        // Imported IDs are replaced so importing the same library twice cannot
        // create duplicate identities in SwiftUI or connect old queued jobs.
        return archive.conversations.map { source in
            let letters = source.letters.map { source -> Letter in
                var letter = Letter(speaker: source.speaker, text: source.text,
                                    status: source.status == .waiting || source.status == .writing ? .stopped : source.status, date: source.date)
                letter.detail = source.detail
                return letter
            }
            return Conversation(name: source.name, letters: letters, modified: source.modified)
        }
    }
}
