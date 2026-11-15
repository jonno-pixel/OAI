import Foundation

struct VrijError: LocalizedError, Sendable {
    let description: String
    var errorDescription: String? { description }
    init(_ description: String) { self.description = description }
}

enum Speaker: String, Codable, Sendable { case person, model }
enum ReplyStatus: String, Codable, Sendable { case ready, waiting, writing, stopped, failed }

struct Letter: Identifiable, Codable, Sendable {
    let id: UUID
    var speaker: Speaker
    var text: String
    var status: ReplyStatus
    var detail: String
    let date: Date
    init(speaker: Speaker, text: String, status: ReplyStatus = .ready, date: Date = Date()) {
        id = UUID(); self.speaker = speaker; self.text = text
        self.status = status; detail = ""; self.date = date
    }
}

struct Conversation: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var letters: [Letter]
    var modified: Date
    init(name: String = "Nieuw gesprek", letters: [Letter] = [], modified: Date = Date()) {
        id = UUID(); self.name = name; self.letters = letters; self.modified = modified
    }
}

struct InferenceSettings: Codable, Sendable {
    var model: String = ""
    var context: UInt32 = 0
    var temperature: Float = 0.7
    var metal: Bool = true
    var template: String = ""
}

struct PendingReply: Identifiable, Codable, Sendable {
    var id: UUID { letter }
    let conversation: UUID
    let letter: UUID
    let settings: InferenceSettings
}

struct LibraryState: Codable, Sendable {
    var format = 1
    var revision: UInt64 = 0
    var conversations: [Conversation] = []
    var pending: [PendingReply] = []
    var settings = InferenceSettings()

    mutating func recoverInterruptedReplies() {
        var interrupted = Set<UUID>()
        for c in conversations.indices {
            for m in conversations[c].letters.indices where conversations[c].letters[m].status == .writing {
                conversations[c].letters[m].status = .stopped
                conversations[c].letters[m].detail = "De vorige uitvoering is onderbroken. De ontvangen tekst is bewaard."
                interrupted.insert(conversations[c].letters[m].id)
            }
        }
        pending.removeAll { interrupted.contains($0.letter) }
    }
}

struct ConversationArchive: Codable, Sendable {
    var format = 1
    var conversations: [Conversation]
}

struct DiskModel: Identifiable, Sendable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    let bytes: Int64
}

struct RuntimeMessage: Sendable {
    let role: String
    let text: String
}

enum RuntimeEvent: Sendable {
    case progress(String)
    case output(String)
}

struct RuntimeSummary: Sendable {
    let produced: UInt64
    let shifts: UInt64
}

enum TextTransfer {
    static func transcript(_ conversations: [Conversation]) -> String {
        conversations.map { conversation in
            let body = conversation.letters.map {
                ($0.speaker == .person ? "Jij:\n" : "JJS:\n") + $0.text
            }.joined(separator: "\n\n")
            return "# " + conversation.name + "\n\n" + body
        }.joined(separator: "\n\n====================\n\n")
    }

    static func decode(_ data: Data) throws -> String {
        // BOMs must be checked before UTF-8: UTF-16 ASCII bytes can otherwise
        // look like valid UTF-8 containing alternating NUL characters.
        if data.starts(with: [0xff, 0xfe]) {
            if let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return text }
        } else if data.starts(with: [0xfe, 0xff]) {
            if let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return text }
        } else if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        }
        throw VrijError("Dit bestand is geen geldige UTF-8- of UTF-16-tekst.")
    }

    static func rawPrompt(_ messages: [RuntimeMessage]) -> String {
        messages.map(\.text).joined(separator: "\n")
    }
}

struct TokenTextBuffer: Sendable {
    private var bytes: [UInt8] = []
    mutating func receive(_ incoming: [UInt8]) -> String {
        bytes.append(contentsOf: incoming)
        guard !bytes.isEmpty else { return "" }
        var boundary = bytes.count - 1
        while boundary > 0 && bytes[boundary] & 0xc0 == 0x80 { boundary -= 1 }
        let first = bytes[boundary]
        let needed: Int
        switch first {
        case 0xc2...0xdf: needed = 2
        case 0xe0...0xef: needed = 3
        case 0xf0...0xf4: needed = 4
        default: needed = 1
        }
        let end = bytes.count - boundary < needed ? boundary : bytes.count
        let text = String(decoding: bytes[..<end], as: UTF8.self)
        bytes.removeFirst(end)
        return text
    }
    mutating func finish() -> String {
        defer { bytes.removeAll() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
