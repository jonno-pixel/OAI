import Foundation

@main
enum Verification {
    static func main() async throws {
        try textEncodingAndStreaming()
        try await archiveAndRecovery()
        try await modelTransfer()
        print("PASS: text, UTF-8 streaming, persistence, revision ordering, recovery, JSON transfer, GGUF import/export/download and failed-transfer cleanup")
    }
    private static func textEncodingAndStreaming() throws {
        let sample = "JJS Vrij — café 🙂\0\n日本語"
        precondition(tryDecode(Data(sample.utf8)) == sample)
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let prefix = encoding == .utf16LittleEndian ? Data([0xff, 0xfe]) : Data([0xfe, 0xff])
            precondition(tryDecode(prefix + sample.data(using: encoding)!) == sample)
        }
        let bytes = Array(sample.utf8)
        for position in 0...bytes.count {
            var decoder = TokenTextBuffer()
            let result = decoder.receive(Array(bytes[..<position])) + decoder.receive(Array(bytes[position...])) + decoder.finish()
            precondition(result == sample)
        }
        do { _ = try TextTransfer.decode(Data([0xff, 0x00])); fatalError("Invalid text accepted") } catch is VrijError {}
    }
    private static func tryDecode(_ data: Data) -> String { try! TextTransfer.decode(data) }
    private static func archiveAndRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json")
        let vault = LibraryVault(location: file)
        let large = String(repeating: "Alle tekst blijft — 🙂\0\n", count: 50_000)
        let person = Letter(speaker: .person, text: large)
        let reply = Letter(speaker: .model, text: "Gedeeltelijk antwoord", status: .writing)
        let chat = Conversation(name: "Controle", letters: [person, reply])
        var state = LibraryState()
        state.conversations = [chat]
        state.pending = [PendingReply(conversation: chat.id, letter: reply.id, settings: InferenceSettings())]
        state.revision = 2
        try await vault.write(state)
        var stale = state; stale.revision = 1; stale.conversations = []
        try await vault.write(stale)
        let reopened = LibraryVault(location: file)
        var loaded = try await reopened.restore()
        precondition(loaded.conversations[0].letters[0].text == large && loaded.revision == 2)
        loaded.recoverInterruptedReplies()
        precondition(loaded.pending.isEmpty && loaded.conversations[0].letters[1].status == .stopped)
        precondition(loaded.conversations[0].letters[1].text == reply.text)
        let archived = try LibraryVault.exportJSON([chat])
        let imported = try LibraryVault.importJSON(archived)
        precondition(imported[0].id != chat.id && imported[0].letters[0].id != person.id)
        precondition(imported[0].letters[0].text == large && imported[0].letters[0].date == person.date)
        precondition(imported[0].letters[1].status == .stopped)
        precondition(TextTransfer.transcript([chat]) == "# Controle\n\nJij:\n" + large + "\n\nJJS:\n" + reply.text)
        let plain = try await vault.exportFile([chat], plain: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let plainBytes = try Data(contentsOf: plain)
        precondition(tryDecode(plainBytes) == TextTransfer.transcript([chat]))
        let raw = [RuntimeMessage(role: "user", text: large), RuntimeMessage(role: "assistant", text: reply.text)]
        precondition(TextTransfer.rawPrompt(raw) == large + "\n" + reply.text)
    }
    private static func modelTransfer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try ModelFiles(root: folder.appendingPathComponent("Models"))
        let input = folder.appendingPathComponent("Input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let fixture = Data("GGUF".utf8) + Data(repeating: 73, count: 4096)
        for name in ["local-00001-of-00002.gguf", "local-00002-of-00002.gguf"] {
            try fixture.write(to: input.appendingPathComponent(name))
        }
        let added = try await files.ingest([input])
        precondition(added.count == 1 && added[0].bytes == Int64(fixture.count * 2))
        let output = try await files.export(added[0])
        precondition(output.count == 2)
        for part in output { let bytes = try Data(contentsOf: part); precondition(bytes == fixture) }
        try await files.delete(added[0])
        let empty = try await files.all(); precondition(empty.isEmpty)
        let alternative = input.appendingPathComponent("model.data")
        try fixture.write(to: alternative)
        let renamed = try await files.ingest([alternative])
        precondition(renamed.count == 1)
        try await files.delete(renamed[0])
        do { _ = try await files.file("../../outside.gguf"); fatalError("Path traversal accepted") } catch is VrijError {}
        let base = URL(string: ProcessInfo.processInfo.environment["VRIJ_TEST_SERVER"]!)!
        let download = try await files.download([base.appendingPathComponent("valid.gguf")]) { _ in }
        let urls = try await files.export(download[0])
        let downloaded = try Data(contentsOf: urls[0]); precondition(downloaded == fixture)
        for invalid in ["html.gguf", "missing.gguf"] {
            do { _ = try await files.download([base.appendingPathComponent(invalid)]) { _ in }; fatalError("Invalid download accepted") }
            catch is VrijError {}
        }
        let remaining = try await files.all(); precondition(remaining.count == 1)
    }
}
